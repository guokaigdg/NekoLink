import Foundation

// MARK: - 模型

public enum TunnelMode: String, Codable, CaseIterable, Sendable {
    case rule, global, direct
    public var label: String {
        switch self {
        case .rule:   return "规则"
        case .global: return "全局"
        case .direct: return "直连"
        }
    }
}

public struct MihomoConfig: Codable, Sendable {
    public let port: Int?
    public let socksPort: Int?
    public let mixedPort: Int?
    public let mode: TunnelMode
    public let logLevel: String?
    public let allowLan: Bool?

    enum CodingKeys: String, CodingKey {
        case port, mode
        case socksPort = "socks-port"
        case mixedPort = "mixed-port"
        case logLevel = "log-level"
        case allowLan = "allow-lan"
    }
}

public struct ProxyItem: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let now: String?
    public let all: [String]?
    public let history: [DelayHistory]?

    public var latestDelay: Int? { history?.last?.delay }
}

public struct DelayHistory: Codable, Sendable {
    public let time: String
    public let delay: Int
}

/// 通过把 `all` 的子代理打平后形成的逻辑分组，方便 UI 直接展示。
public struct ProxyGroup: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let now: String?
    public let members: [ProxyItem]
}

// MARK: - API 客户端

public actor MihomoAPI {
    private let baseURL: URL
    private let secret: String?
    private let session: URLSession

    public init(baseURL: URL, secret: String?) {
        self.baseURL = baseURL
        self.secret = secret
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 5
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    public func updateBaseURL(_ url: URL) {
        // baseURL 不可变，调用方应替换实例。保留接口以便未来扩展。
        _ = url
    }

    public func fetchConfig() async throws -> MihomoConfig {
        try await get("/configs", as: MihomoConfig.self)
    }

    public func patchConfig(mode: TunnelMode) async throws {
        struct Body: Encodable { let mode: String }
        try await patch("/configs", body: Body(mode: mode.rawValue))
    }

    public func fetchProxies() async throws -> [ProxyGroup] {
        struct Wrapper: Decodable { let proxies: [String: ProxyItem] }
        let wrapper = try await get("/proxies", as: Wrapper.self)
        let items = wrapper.proxies

        // 仅以含 `all` 的项目作为分组，其它视为普通代理。
        return items.values
            .filter { $0.all?.isEmpty == false }
            .map { group in
                let members = (group.all ?? []).compactMap { items[$0] }
                return ProxyGroup(
                    name: group.name,
                    type: group.type,
                    now: group.now,
                    members: members
                )
            }
            .sorted { $0.name < $1.name }
    }

    public func selectProxy(group: String, name: String) async throws {
        struct Body: Encodable { let name: String }
        let path = "/proxies/" + (group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group)
        try await put(path, body: Body(name: name))
    }

    public func testDelay(name: String, url: String = "https://www.gstatic.com/generate_204", timeout: Int = 3000) async throws -> Int {
        struct Resp: Decodable { let delay: Int }
        var comps = URLComponents()
        comps.path = "/proxies/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name) + "/delay"
        comps.queryItems = [
            .init(name: "url", value: url),
            .init(name: "timeout", value: String(timeout))
        ]
        return try await get(comps.string ?? "", as: Resp.self).delay
    }

    public func closeAllConnections() async throws {
        try await delete("/connections")
    }

    public func closeConnection(id: String) async throws {
        let path = "/connections/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)
        try await delete(path)
    }

    // MARK: - HTTP helpers

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        let url = URL(string: path, relativeTo: baseURL)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let secret, !secret.isEmpty {
            req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let req = makeRequest(path, method: "GET")
        let (data, resp) = try await session.data(for: req)
        try Self.validate(resp)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func patch<B: Encodable>(_ path: String, body: B) async throws {
        var req = makeRequest(path, method: "PATCH")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await session.data(for: req)
        try Self.validate(resp)
    }

    private func put<B: Encodable>(_ path: String, body: B) async throws {
        var req = makeRequest(path, method: "PUT")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await session.data(for: req)
        try Self.validate(resp)
    }

    private func delete(_ path: String) async throws {
        let req = makeRequest(path, method: "DELETE")
        let (_, resp) = try await session.data(for: req)
        try Self.validate(resp)
    }

    private static func validate(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode)
        }
    }
}

public enum APIError: Error, LocalizedError {
    case invalidResponse
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .http(let c):     return "HTTP \(c)"
        }
    }
}
