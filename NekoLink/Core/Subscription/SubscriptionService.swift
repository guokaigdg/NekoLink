import Foundation
import Observation
import Yams

/// 订阅管理服务。
/// 职责：
/// - 元信息持久化（UserDefaults）
/// - YAML 文件落盘到 ~/.config/catcat/profiles/<id>.yaml
/// - 拉取 / 解析 / 校验
/// - 激活：写入 ~/.config/catcat/config.yaml
@Observable
@MainActor
final class SubscriptionService {

    // MARK: - 状态
    private(set) var subscriptions: [Subscription] = []
    private(set) var activeID: UUID?
    private(set) var lastError: String?

    func clearLastError() { lastError = nil }

    /// 自动刷新间隔（秒）。0 表示关闭。默认 6 小时。
    var autoRefreshInterval: TimeInterval {
        get { UserDefaults.standard.double(forKey: intervalKey).nonZero ?? 6 * 3600 }
        set {
            UserDefaults.standard.set(newValue, forKey: intervalKey)
            scheduleAutoRefresh()
        }
    }

    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - 持久化键
    private let listKey = "catcat.subscriptions"
    private let activeKey = "catcat.activeSubscription"
    private let intervalKey = "catcat.autoRefreshInterval"

    // MARK: - 路径
    private var profilesDir: URL {
        let dir = CoreManager.configDirectory().appendingPathComponent("profiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var activeConfigURL: URL {
        CoreManager.configDirectory().appendingPathComponent("config.yaml")
    }

    func profileURL(for id: UUID) -> URL {
        profilesDir.appendingPathComponent("\(id.uuidString).yaml")
    }

    init() {
        load()
        scheduleAutoRefresh()
    }

    deinit { }

    // MARK: - 自动刷新

    /// 调度后台定时刷新。每个 tick 检查所有订阅，更新过期超过 interval 的项。
    func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        let interval = autoRefreshInterval
        guard interval > 0 else { return }
        autoRefreshTask = Task { [weak self] in
            // 启动后等 30s 再开始，避免与冷启动其它任务争抢
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                await self?.tickRefresh(interval: interval)
                try? await Task.sleep(for: .seconds(min(interval, 600)))
            }
        }
    }

    private func tickRefresh(interval: TimeInterval) async {
        let now = Date()
        let stale = subscriptions.filter { sub in
            guard let updated = sub.updatedAt else { return true }
            return now.timeIntervalSince(updated) >= interval
        }
        for sub in stale {
            _ = try? await refresh(id: sub.id)
        }
    }

    // MARK: - 持久化

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: listKey),
           let list = try? JSONDecoder().decode([Subscription].self, from: data) {
            subscriptions = list
        }
        if let s = d.string(forKey: activeKey), let uuid = UUID(uuidString: s) {
            activeID = uuid
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(subscriptions) {
            d.set(data, forKey: listKey)
        }
        if let activeID {
            d.set(activeID.uuidString, forKey: activeKey)
        } else {
            d.removeObject(forKey: activeKey)
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(name: String, url: URL) async -> Subscription {
        var sub = Subscription(name: name, url: url)
        subscriptions.append(sub)
        persist()
        if (try? await refresh(id: sub.id)) != nil {
            // refresh 内已 persist
            sub = subscriptions.first(where: { $0.id == sub.id }) ?? sub
        }
        return sub
    }

    func remove(_ id: UUID) {
        subscriptions.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: profileURL(for: id))
        if activeID == id { activeID = nil }
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[idx].name = name
        persist()
    }

    // MARK: - 拉取与解析

    @discardableResult
    func refresh(id: UUID) async throws -> Subscription {
        guard let idx = subscriptions.firstIndex(where: { $0.id == id }) else {
            throw SubscriptionError.notFound
        }
        let sub = subscriptions[idx]
        do {
            let (data, info) = try await fetch(url: sub.url)
            try validateYAML(data)
            try data.write(to: profileURL(for: id), options: .atomic)
            subscriptions[idx].updatedAt = Date()
            subscriptions[idx].userInfo = info
            persist()
            // 若是当前激活订阅，同步到 config.yaml 并请求重启
            if activeID == id {
                try data.write(to: activeConfigURL, options: .atomic)
            }
            return subscriptions[idx]
        } catch {
            lastError = "\(error)"
            throw error
        }
    }

    func refreshAll() async {
        for sub in subscriptions {
            _ = try? await refresh(id: sub.id)
        }
    }

    /// 激活某条订阅：复制 yaml 到 config.yaml。返回是否需要重启 core。
    @discardableResult
    func activate(_ id: UUID) throws -> Bool {
        guard subscriptions.contains(where: { $0.id == id }) else {
            throw SubscriptionError.notFound
        }
        let src = profileURL(for: id)
        guard FileManager.default.fileExists(atPath: src.path) else {
            throw SubscriptionError.profileMissing
        }
        let data = try Data(contentsOf: src)
        try data.write(to: activeConfigURL, options: .atomic)
        let changed = (activeID != id)
        activeID = id
        persist()
        return changed
    }

    // MARK: - HTTP

    private func fetch(url: URL) async throws -> (Data, Subscription.UserInfo?) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        // 使用 clash-meta UA，兼容多数面板
        req.setValue("clash-verge/v2.0 (Catcat)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SubscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SubscriptionError.http(http.statusCode)
        }
        var info: Subscription.UserInfo?
        if let header = http.value(forHTTPHeaderField: "subscription-userinfo")
            ?? http.value(forHTTPHeaderField: "Subscription-Userinfo") {
            info = Subscription.UserInfo.parse(header)
        }
        return (data, info)
    }

    /// 用 Yams 校验：必须能解析为 mapping，且至少包含 `proxies` 或 `proxy-providers`。
    private func validateYAML(_ data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw SubscriptionError.notYAML
        }
        let parsed: Any?
        do {
            parsed = try Yams.load(yaml: text)
        } catch {
            throw SubscriptionError.yamlParse("\(error)")
        }
        guard let dict = parsed as? [String: Any] else {
            throw SubscriptionError.notYAML
        }
        if dict["proxies"] == nil && dict["proxy-providers"] == nil {
            throw SubscriptionError.missingProxies
        }
    }

    // MARK: - 解析活动配置

    /// 从 yaml 中提取的关键运行参数。
    struct ParsedConfig: Sendable, Equatable {
        var mixedPort: Int?
        var port: Int?       // HTTP
        var socksPort: Int?
        var externalController: String?

        /// 优先用于设置系统 HTTP/HTTPS 代理的端口（必须支持 HTTP）。
        var httpPort: Int? { mixedPort ?? port }
    }

    /// 解析当前激活订阅的 yaml；若无激活订阅返回 nil。
    func parseActiveConfig() -> ParsedConfig? {
        guard let id = activeID else { return nil }
        let url = profileURL(for: id)
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? Yams.load(yaml: text) as? [String: Any] else {
            return nil
        }
        var cfg = ParsedConfig()
        cfg.mixedPort = Self.intValue(parsed["mixed-port"])
        cfg.port = Self.intValue(parsed["port"])
        cfg.socksPort = Self.intValue(parsed["socks-port"])
        cfg.externalController = parsed["external-controller"] as? String
        return cfg
    }

    /// yaml 中端口可能是 Int 或 String，做兼容。
    private static func intValue(_ raw: Any?) -> Int? {
        if let v = raw as? Int { return v }
        if let s = raw as? String, let v = Int(s) { return v }
        return nil
    }

    // MARK: - 错误

    enum SubscriptionError: Error, LocalizedError {
        case notFound
        case profileMissing
        case invalidResponse
        case http(Int)
        case notYAML
        case yamlParse(String)
        case missingProxies

        var errorDescription: String? {
            switch self {
            case .notFound:        return "订阅不存在"
            case .profileMissing:  return "本地配置文件缺失，请刷新"
            case .invalidResponse: return "无效响应"
            case .http(let c):     return "HTTP \(c)"
            case .notYAML:         return "响应不是合法 YAML"
            case .yamlParse(let m):return "YAML 解析失败：\(m)"
            case .missingProxies:  return "配置中缺少 proxies / proxy-providers"
            }
        }
    }
}

private extension Double {
    /// 0 视作未设置；返回 nil 让调用方 fallback 到默认值。
    var nonZero: Double? { self == 0 ? nil : self }
}
