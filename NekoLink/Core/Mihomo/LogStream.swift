import Foundation
import Observation

public enum LogLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case debug, info, warning, error
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .debug:   return "调试"
        case .info:    return "信息"
        case .warning: return "警告"
        case .error:   return "错误"
        }
    }
    /// 用于 /logs?level= 查询；mihomo 接受 silent/error/warning/info/debug，按"最低级别"返回。
    public var queryValue: String { rawValue }
    public var rank: Int {
        switch self {
        case .debug:   return 0
        case .info:    return 1
        case .warning: return 2
        case .error:   return 3
        }
    }
}

public struct LogEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

/// 订阅 mihomo `/logs` WebSocket，按 level 过滤拉取，环形缓冲。
@Observable
@MainActor
final class LogStream {

    // MARK: - 公开状态
    private(set) var entries: [LogEntry] = []
    private(set) var isConnected = false
    var capacity: Int = 1000
    /// 最低订阅级别（向 server 拉取的级别；客户端再二次过滤展示）。
    var subscribeLevel: LogLevel = .info {
        didSet { if subscribeLevel != oldValue { restart() } }
    }

    // MARK: - 内部
    private var baseURL: URL
    private var secret: String?
    private let session: URLSession = .shared
    private var pumpTask: Task<Void, Never>?
    private var task: URLSessionWebSocketTask?
    private var reconnectDelay: TimeInterval = 1

    init(baseURL: URL = URL(string: "http://127.0.0.1:9090")!, secret: String? = nil) {
        self.baseURL = baseURL
        self.secret = secret
    }

    func start() {
        guard pumpTask == nil else { return }
        pumpTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        pumpTask?.cancel()
        pumpTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    func clear() { entries.removeAll() }

    /// 热替换控制器地址。若已在跑，会重启 WebSocket。
    func updateBaseURL(_ url: URL, secret: String? = nil) {
        guard url != baseURL || secret != self.secret else { return }
        let wasRunning = pumpTask != nil
        stop()
        baseURL = url
        self.secret = secret
        if wasRunning { start() }
    }

    private func restart() {
        stop()
        start()
    }

    // MARK: - 实现

    private func runLoop() async {
        while !Task.isCancelled {
            await connectOnce()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(Int(reconnectDelay * 1000)))
            reconnectDelay = min(reconnectDelay * 2, 8)
        }
    }

    private func connectOnce() async {
        guard let wsURL = makeWebSocketURL() else { return }
        var req = URLRequest(url: wsURL)
        if let secret, !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        let task = session.webSocketTask(with: req)
        self.task = task
        task.resume()
        isConnected = true
        reconnectDelay = 1

        defer {
            isConnected = false
            self.task = nil
        }

        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                if let entry = parse(message: msg) {
                    append(entry)
                }
            } catch {
                return
            }
        }
    }

    private func makeWebSocketURL() -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        switch comps.scheme?.lowercased() {
        case "https": comps.scheme = "wss"
        default:      comps.scheme = "ws"
        }
        comps.path = "/logs"
        var items = [URLQueryItem(name: "level", value: subscribeLevel.queryValue)]
        if let secret, !secret.isEmpty {
            items.append(URLQueryItem(name: "token", value: secret))
        }
        comps.queryItems = items
        return comps.url
    }

    private func parse(message: URLSessionWebSocketTask.Message) -> LogEntry? {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return nil
        }
        struct Payload: Decodable {
            let type: String
            let payload: String
        }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        let level = LogLevel(rawValue: p.type.lowercased()) ?? .info
        return LogEntry(level: level, message: p.payload)
    }

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}
