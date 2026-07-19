import Foundation

/// 主 App 与 NekoLinkHelper 共享的 XPC 协议。
/// 注意：所有方法必须 @objc 兼容，参数 Codable 受限于 NSSecureCoding 类型。
@objc public protocol HelperProtocol {
    /// 把系统代理（HTTP / HTTPS / SOCKS）指向给定 host:port，对所有活跃网络服务生效。
    func setSystemProxy(host: String,
                        port: Int,
                        bypass: [String],
                        reply: @escaping (Bool, String?) -> Void)

    /// 关闭系统代理（保留地址但 disabled）。
    func clearSystemProxy(reply: @escaping (Bool, String?) -> Void)

    /// 当前系统代理是否启用 + 指向 host:port（任一活跃服务）。
    func currentProxy(reply: @escaping (Bool, String?, Int) -> Void)

    /// helper 版本号。
    func version(reply: @escaping (String) -> Void)

    /// 卸载（停止 launchd job + 删除文件）。失败时返回 reason。
    func uninstall(reply: @escaping (Bool, String?) -> Void)
}

public enum HelperConstants {
    public static let machServiceName = "app.nekolink.NekoLink.helper"
    public static let helperLabel     = "app.nekolink.NekoLink.helper"
    public static let helperBinaryPath  = "/Library/PrivilegedHelperTools/" + helperLabel
    public static let helperPlistPath   = "/Library/LaunchDaemons/" + helperLabel + ".plist"
    public static let currentVersion    = "0.1.0"
}
