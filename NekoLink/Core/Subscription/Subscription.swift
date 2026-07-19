import Foundation

/// 订阅元信息（持久化在 UserDefaults，YAML 内容单独写文件）。
public struct Subscription: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var updatedAt: Date?
    public var userInfo: UserInfo?

    public init(id: UUID = UUID(), name: String, url: URL, updatedAt: Date? = nil, userInfo: UserInfo? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.updatedAt = updatedAt
        self.userInfo = userInfo
    }

    /// 来自响应头 `subscription-userinfo: upload=...; download=...; total=...; expire=...`
    public struct UserInfo: Codable, Hashable, Sendable {
        public var upload: Int64
        public var download: Int64
        public var total: Int64
        public var expire: TimeInterval?

        public var used: Int64 { upload + download }
        public var remaining: Int64 { max(0, total - used) }
        public var usedRatio: Double {
            guard total > 0 else { return 0 }
            return min(1, Double(used) / Double(total))
        }
        public var expireDate: Date? {
            guard let expire, expire > 0 else { return nil }
            return Date(timeIntervalSince1970: expire)
        }
    }
}

extension Subscription.UserInfo {
    /// 解析 `subscription-userinfo` 头。
    static func parse(_ header: String) -> Subscription.UserInfo? {
        var dict: [String: Int64] = [:]
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, let v = Int64(kv[1]) {
                dict[kv[0]] = v
            }
        }
        guard let up = dict["upload"], let down = dict["download"], let total = dict["total"] else {
            return nil
        }
        return .init(
            upload: up,
            download: down,
            total: total,
            expire: dict["expire"].map { TimeInterval($0) }
        )
    }
}
