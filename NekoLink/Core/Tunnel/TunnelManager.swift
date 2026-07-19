import Foundation
import NetworkExtension
import Observation

/// TUN 模式管理器。
///
/// 通过 NetworkExtension 的 `NETunnelProviderManager` 控制 TUN 隧道启停。
/// 需要开发者账号签名后生效，否则无法加载系统扩展。
@Observable
@MainActor
final class TunnelManager {

    // MARK: - 状态
    private(set) var isEnabled = false
    private(set) var status: NEVPNStatus = .invalid
    private(set) var lastError: String?

    private var manager: NETunnelProviderManager?
    private nonisolated(unsafe) var statusObserver: NSObjectProtocol?

    /// TUN 配置
    var tunAddresses: [String] = ["198.18.0.1"]
    var tunSubnetMasks: [String] = ["255.255.255.0"]
    var dnsServers: [String] = ["223.5.5.5", "114.114.114.114"]
    var mtu: Int = 1500
    var mixedPort: Int = 7890
    var logLevel: String = "info"
    var deviceName: String = "neko0"

    /// TUN 模式是否可用（系统扩展已安装并通过用户批准）
    var isAvailable: Bool {
        // 简化判断：检查是否有已保存的配置
        manager != nil
    }

    init() {
        loadTunnelManager()
    }

    nonisolated deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 公开操作

    /// 加载已保存的隧道配置
    func loadTunnelManager() {
        Task {
            await load()
        }
    }

    /// 开启 TUN 模式
    func enable() async {
        do {
            let mgr = try await createOrLoadManager()
            mgr.isEnabled = true
            try await mgr.saveToPreferences()
            try await mgr.loadFromPreferences()

            // 启动隧道
            try mgr.connection.startVPNTunnel()

            // 注册状态监听
            observeStatus(mgr)

            manager = mgr
            isEnabled = true
            status = mgr.connection.status
        } catch {
            lastError = "启用 TUN 失败: \(error.localizedDescription)"
        }
    }

    /// 关闭 TUN 模式
    func disable() async {
        guard let mgr = manager else { return }

        mgr.connection.stopVPNTunnel()
        mgr.isEnabled = false
        do {
            try await mgr.saveToPreferences()
        } catch {
            lastError = "保存 TUN 配置失败: \(error.localizedDescription)"
        }

        isEnabled = false
        status = .disconnected
    }

    /// 切换 TUN 模式
    func toggle() async {
        if isEnabled {
            await disable()
        } else {
            await enable()
        }
    }

    /// 刷新状态
    func refreshStatus() async {
        await load()
        if let mgr = manager {
            status = mgr.connection.status
            isEnabled = mgr.isEnabled && status == .connected
        }
    }

    // MARK: - 内部

    private func load() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let mgr = managers.first(where: { isNekoLinkTunnel($0) }) {
                manager = mgr
                status = mgr.connection.status
                isEnabled = mgr.isEnabled && status == .connected
                observeStatus(mgr)
            } else {
                manager = nil
                status = .invalid
                isEnabled = false
            }
        } catch {
            lastError = "加载 TUN 配置失败: \(error.localizedDescription)"
        }
    }

    private func createOrLoadManager() async throws -> NETunnelProviderManager {
        if let mgr = manager {
            return mgr
        }

        let mgr = NETunnelProviderManager()
        mgr.localizedDescription = "NekoLink TUN"

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "app.nekolink.NekoLink.tunnel"
        proto.serverAddress = "240.0.0.1"
        proto.providerConfiguration = [
            "tunAddresses": tunAddresses,
            "tunSubnetMasks": tunSubnetMasks,
            "dnsServers": dnsServers,
            "mtu": mtu,
            "mixedPort": mixedPort,
            "logLevel": logLevel,
            "deviceName": deviceName,
        ]
        mgr.protocolConfiguration = proto

        try await mgr.saveToPreferences()
        try await mgr.loadFromPreferences()
        return mgr
    }

    private func observeStatus(_ mgr: NETunnelProviderManager) {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: mgr.connection,
            queue: .main
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            let status = conn.status
            let enabled = status == .connected
            Task { @MainActor in
                self?.status = status
                self?.isEnabled = enabled
            }
        }
    }

    /// 判断 managers 中的某一个是否属于 NekoLink
    private func isNekoLinkTunnel(_ mgr: NETunnelProviderManager) -> Bool {
        guard let proto = mgr.protocolConfiguration as? NETunnelProviderProtocol else {
            return false
        }
        return proto.providerBundleIdentifier == "app.nekolink.NekoLink.tunnel"
    }
}