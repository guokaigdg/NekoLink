import Foundation
import Observation
import SwiftUI

/// 应用全局状态。聚合 CoreManager 与 MihomoAPI，供视图层观察。
@Observable
@MainActor
final class AppModel {
    // MARK: - Core
    let core = CoreManager()
    let subscriptions = SubscriptionService()
    let traffic = TrafficMonitor()
    let logs = LogStream()
    let connections = ConnectionMonitor()
    let systemProxy = SystemProxyService()
    let launchAtLogin = LaunchAtLoginService()
    let updater = UpdaterService()
    let appearance = AppearanceService()
    let tunnel = TunnelManager()
    var api = MihomoAPI(baseURL: URL(string: "http://127.0.0.1:9090")!, secret: nil)

    // MARK: - 暴露给 UI 的派生状态
    var coreRunning: Bool { core.state == .running }
    var statusText: String {
        switch core.state {
        case .stopped:  return "已停止"
        case .starting: return "启动中…"
        case .running:  return "运行中"
        case .failed(let msg): return "失败：\(msg)"
        }
    }

    // MARK: - 代理 / 节点
    var proxies: [ProxyGroup] = []
    var currentMode: TunnelMode = .rule
    var lastError: String?

    /// 节点 → 最近一次测速延迟（ms）。0 表示超时/不可达。
    var delays: [String: Int] = [:]
    /// 正在测速中的策略组名集合
    var testingGroups: Set<String> = []

    // MARK: - 操作
    func toggleCore() async {
        if coreRunning {
            traffic.stop()
            logs.stop()
            connections.stop()
            // 关闭 core 时一并关闭系统代理，防止网络中断
            if systemProxy.isEnabled { await systemProxy.disable() }
            await core.stop()
        } else {
            do {
                try await core.start()
                try await Task.sleep(for: .milliseconds(400))
                traffic.start()
                logs.start()
                connections.start()
                await refresh()
                await syncSystemProxyPort()
                await systemProxy.refreshStatus()
            } catch {
                lastError = "\(error)"
            }
        }
    }

    func refresh() async {
        do {
            let cfg = try await api.fetchConfig()
            currentMode = cfg.mode
            let groups = try await api.fetchProxies()
            proxies = groups
        } catch {
            lastError = "\(error)"
        }
    }

    func switchMode(_ mode: TunnelMode) async {
        do {
            try await api.patchConfig(mode: mode)
            currentMode = mode
        } catch {
            lastError = "\(error)"
        }
    }

    /// 测速：并发对组内所有成员请求 /delay，结果写入 `delays` 字典。
    /// 失败/超时记 0。
    func testGroup(_ group: ProxyGroup) async {
        let groupName = group.name
        if testingGroups.contains(groupName) { return }
        testingGroups.insert(groupName)
        defer { testingGroups.remove(groupName) }

        let api = self.api
        let names = group.members.map(\.name)

        await withTaskGroup(of: (String, Int).self) { tg in
            for name in names {
                tg.addTask {
                    let delay = (try? await api.testDelay(name: name)) ?? 0
                    return (name, delay)
                }
            }
            for await (name, delay) in tg {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.delays[name] = delay
                }
            }
        }
    }

    /// 单节点测速
    func testNode(_ name: String) async {
        let delay = (try? await api.testDelay(name: name)) ?? 0
        withAnimation(.easeInOut(duration: 0.25)) {
            delays[name] = delay
        }
    }

    /// 激活订阅。若当前 core 在跑则重启使新配置生效。
    func activateSubscription(_ id: UUID) async {
        do {
            let changed = try subscriptions.activate(id)
            if changed && coreRunning {
                traffic.stop()
                logs.stop()
                connections.stop()
                await core.stop()
                try await core.start()
                try await Task.sleep(for: .milliseconds(500))
                traffic.start()
                logs.start()
                connections.start()
                await refresh()
                await syncSystemProxyPort()
            } else if changed {
                await syncSystemProxyPort()
            }
        } catch {
            lastError = "\(error)"
        }
    }

    func refreshSubscription(_ id: UUID) async {
        do {
            _ = try await subscriptions.refresh(id: id)
            // 若刷新的是当前激活订阅且 core 在跑，重启使其生效
            if subscriptions.activeID == id && coreRunning {
                traffic.stop()
                logs.stop()
                connections.stop()
                await core.stop()
                try await core.start()
                try await Task.sleep(for: .milliseconds(500))
                traffic.start()
                logs.start()
                connections.start()
                await refresh()
                await syncSystemProxyPort()
            } else if subscriptions.activeID == id {
                await syncSystemProxyPort()
            }
        } catch {
            lastError = "\(error)"
        }
    }

    /// 从激活订阅 yaml 解析端口并同步给 SystemProxyService。
    /// 若系统代理当前已开启且端口/地址变化，立即重新下发。
    func syncSystemProxyPort() async {
        guard let parsed = subscriptions.parseActiveConfig() else { return }
        guard let httpPort = parsed.httpPort else {
            // yaml 没声明 mixed-port / port，用 mihomo 默认 7890 不变
            return
        }

        // 同步 external-controller 给 api 与各 monitor
        if let ec = parsed.externalController, !ec.isEmpty,
           let newURL = URL(string: ec.contains("://") ? ec : "http://\(ec)"),
           newURL != currentControllerURL {
            currentControllerURL = newURL
            api = MihomoAPI(baseURL: newURL, secret: nil)
            traffic.updateBaseURL(newURL)
            logs.updateBaseURL(newURL)
            connections.updateBaseURL(newURL)
        }

        if systemProxy.proxyPort == httpPort { return }

        let wasEnabled = systemProxy.isEnabled
        systemProxy.proxyPort = httpPort
        if wasEnabled {
            await systemProxy.enable()
        }
    }

    private var currentControllerURL: URL = URL(string: "http://127.0.0.1:9090")!
}
