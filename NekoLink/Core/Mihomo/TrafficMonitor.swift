import Foundation
import Observation

/// 单个采样点（每秒一条）。
public struct TrafficSample: Sendable, Hashable {
    public let timestamp: Date
    public let up: Double      // bytes/sec
    public let down: Double    // bytes/sec
}

/// 通过 WebSocket 订阅 mihomo 的 /traffic，维护近 N 秒的环形缓冲。
@Observable
@MainActor
final class TrafficMonitor {

    // MARK: - 公开状态
    private(set) var samples: [TrafficSample] = []
    private(set) var isConnected = false
    var capacity: Int = 60   // 保留 60 秒

    /// 当前速率（最近一条采样）
    var current: TrafficSample? { samples.last }

    /// 区间内峰值，用于纵轴自适应
    var peak: Double {
        samples.reduce(0) { max($0, max($1.up, $1.down)) }
    }

    // MARK: - 内部
    private var task: URLSessionWebSocketTask?
    private var session: URLSession = .shared
    private var pumpTask: Task<Void, Never>?
    private var baseURL: URL
    private var secret: String?
    private var reconnectDelay: TimeInterval = 1

    init(baseURL: URL = URL(string: "http://127.0.0.1:9090")!, secret: String? = nil) {
        self.baseURL = baseURL
        self.secret = secret
    }

    // MARK: - 控制

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

    func clear() {
        samples.removeAll()
    }

    /// 热替换控制器地址。若已在跑，会重启 WebSocket 循环。
    func updateBaseURL(_ url: URL, secret: String? = nil) {
        guard url != baseURL || secret != self.secret else { return }
        let wasRunning = pumpTask != nil
        stop()
        baseURL = url
        self.secret = secret
        if wasRunning { start() }
    }

    // MARK: - 实现

    private func runLoop() async {
        // 自动重连：直到任务被取消
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
                guard let sample = parse(message: msg) else { continue }
                append(sample)
            } catch {
                // 断开
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
        comps.path = "/traffic"
        if let secret, !secret.isEmpty {
            // 部分 mihomo 版本通过 query token 鉴权
            comps.queryItems = [.init(name: "token", value: secret)]
        }
        return comps.url
    }

    private func parse(message: URLSessionWebSocketTask.Message) -> TrafficSample? {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return nil
        }
        struct Payload: Decodable { let up: Double; let down: Double }
        guard let p = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return TrafficSample(timestamp: Date(), up: p.up, down: p.down)
    }

    private func append(_ s: TrafficSample) {
        samples.append(s)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

// MARK: - 速率格式化

func formatRate(_ bytesPerSec: Double) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .binary
    f.allowedUnits = [.useKB, .useMB, .useGB]
    return f.string(fromByteCount: Int64(bytesPerSec)) + "/s"
}
