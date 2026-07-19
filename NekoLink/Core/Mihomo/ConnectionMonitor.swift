import Foundation
import Observation

// MARK: - 模型

public struct ConnectionInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let metadata: Metadata
    public let upload: Int64
    public let download: Int64
    public let start: Date
    public let chains: [String]
    public let rule: String?
    public let rulePayload: String?

    public struct Metadata: Hashable, Sendable {
        public let network: String
        public let type: String
        public let sourceIP: String
        public let destinationIP: String
        public let sourcePort: String
        public let destinationPort: String
        public let host: String
        public let process: String?
        public let processPath: String?
    }

    public var displayHost: String {
        if !metadata.host.isEmpty { return metadata.host }
        return metadata.destinationIP
    }
    public var displayPort: String { metadata.destinationPort }
    public var processName: String { metadata.process ?? "—" }
    public var chainSummary: String { chains.reversed().joined(separator: " → ") }
    public var ruleSummary: String {
        guard let rule, !rule.isEmpty else { return "—" }
        if let p = rulePayload, !p.isEmpty { return "\(rule)(\(p))" }
        return rule
    }
}

public struct ConnectionsSnapshot: Sendable {
    public let downloadTotal: Int64
    public let uploadTotal: Int64
    public let connections: [ConnectionInfo]
}

// MARK: - JSON 解码

private struct ConnectionsPayload: Decodable {
    let downloadTotal: Int64
    let uploadTotal: Int64
    let connections: [Item]?

    struct Item: Decodable {
        let id: String
        let metadata: Meta
        let upload: Int64
        let download: Int64
        let start: String
        let chains: [String]?
        let rule: String?
        let rulePayload: String?
    }
    struct Meta: Decodable {
        let network: String
        let type: String
        let sourceIP: String
        let destinationIP: String
        let sourcePort: String
        let destinationPort: String
        let host: String
        let process: String?
        let processPath: String?
    }
}

private nonisolated(unsafe) let iso8601: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private nonisolated(unsafe) let iso8601NoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private func parseDate(_ s: String) -> Date {
    iso8601.date(from: s) ?? iso8601NoFrac.date(from: s) ?? Date()
}

// MARK: - Monitor

@Observable
@MainActor
final class ConnectionMonitor {

    private(set) var snapshot = ConnectionsSnapshot(downloadTotal: 0, uploadTotal: 0, connections: [])
    private(set) var isConnected = false

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

    /// 热替换控制器地址。若已在跑，会重启 WebSocket。
    func updateBaseURL(_ url: URL, secret: String? = nil) {
        guard url != baseURL || secret != self.secret else { return }
        let wasRunning = pumpTask != nil
        stop()
        baseURL = url
        self.secret = secret
        if wasRunning { start() }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await connectOnce()
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(Int(reconnectDelay * 1000)))
            reconnectDelay = min(reconnectDelay * 2, 8)
        }
    }

    private func connectOnce() async {
        guard let url = makeURL() else { return }
        var req = URLRequest(url: url)
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
                if let snap = parse(message: msg) {
                    snapshot = snap
                }
            } catch {
                return
            }
        }
    }

    private func makeURL() -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        switch comps.scheme?.lowercased() {
        case "https": comps.scheme = "wss"
        default:      comps.scheme = "ws"
        }
        comps.path = "/connections"
        if let secret, !secret.isEmpty {
            comps.queryItems = [.init(name: "token", value: secret)]
        }
        return comps.url
    }

    private func parse(message: URLSessionWebSocketTask.Message) -> ConnectionsSnapshot? {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return nil
        }
        guard let p = try? JSONDecoder().decode(ConnectionsPayload.self, from: data) else {
            return nil
        }
        let conns: [ConnectionInfo] = (p.connections ?? []).map { item in
            ConnectionInfo(
                id: item.id,
                metadata: .init(
                    network: item.metadata.network,
                    type: item.metadata.type,
                    sourceIP: item.metadata.sourceIP,
                    destinationIP: item.metadata.destinationIP,
                    sourcePort: item.metadata.sourcePort,
                    destinationPort: item.metadata.destinationPort,
                    host: item.metadata.host,
                    process: item.metadata.process,
                    processPath: item.metadata.processPath
                ),
                upload: item.upload,
                download: item.download,
                start: parseDate(item.start),
                chains: item.chains ?? [],
                rule: item.rule,
                rulePayload: item.rulePayload
            )
        }
        return ConnectionsSnapshot(
            downloadTotal: p.downloadTotal,
            uploadTotal: p.uploadTotal,
            connections: conns
        )
    }
}
