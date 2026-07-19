import Foundation

/// 通过 osascript 以管理员权限安装 / 卸载 NekoLinkHelper。
/// 流程：
///   1. App bundle Resources 内打包 helper bin 与 plist
///   2. 用户首次启用系统代理 → osascript 提示输入密码（一次性）
///   3. 把 bin 拷贝到 /Library/PrivilegedHelperTools/，plist 拷到 /Library/LaunchDaemons/
///   4. launchctl bootstrap system/<plist>
enum HelperInstaller {

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: HelperConstants.helperBinaryPath)
            && FileManager.default.fileExists(atPath: HelperConstants.helperPlistPath)
    }

    /// 在 App bundle 中查找资源（NekoLinkHelper 二进制 + Helper.plist）。
    static func bundledHelperBinary() -> URL? {
        Bundle.main.url(forResource: "NekoLinkHelper", withExtension: nil)
    }

    static func bundledHelperPlist() -> URL? {
        Bundle.main.url(forResource: "Helper", withExtension: "plist")
    }

    enum InstallError: Error, LocalizedError {
        case bundleResourcesMissing
        case scriptFailed(Int32, String)
        case userCancelled

        var errorDescription: String? {
            switch self {
            case .bundleResourcesMissing: return "App 资源中未找到 helper 二进制 / plist"
            case .scriptFailed(let c, let m): return "安装脚本失败（\(c)）：\(m)"
            case .userCancelled: return "用户取消授权"
            }
        }
    }

    /// 触发管理员授权弹窗并完成安装。返回是否成功。
    static func install() throws {
        guard let bin = bundledHelperBinary(), let plist = bundledHelperPlist() else {
            throw InstallError.bundleResourcesMissing
        }

        let script = """
        do shell script "\
        mkdir -p /Library/PrivilegedHelperTools && \
        cp '\(bin.path)' '\(HelperConstants.helperBinaryPath)' && \
        chmod 755 '\(HelperConstants.helperBinaryPath)' && \
        chown root:wheel '\(HelperConstants.helperBinaryPath)' && \
        cp '\(plist.path)' '\(HelperConstants.helperPlistPath)' && \
        chmod 644 '\(HelperConstants.helperPlistPath)' && \
        chown root:wheel '\(HelperConstants.helperPlistPath)' && \
        launchctl bootout system/\(HelperConstants.helperLabel) 2>/dev/null; \
        launchctl bootstrap system '\(HelperConstants.helperPlistPath)'\
        " with administrator privileges
        """
        try runOsascript(script)
    }

    static func uninstall() throws {
        let script = """
        do shell script "\
        launchctl bootout system/\(HelperConstants.helperLabel) 2>/dev/null; \
        rm -f '\(HelperConstants.helperBinaryPath)' '\(HelperConstants.helperPlistPath)'\
        " with administrator privileges
        """
        try runOsascript(script)
    }

    private static func runOsascript(_ source: String) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        let err = Pipe()
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            // 用户取消时 osascript 退出码 1，message 含 "User canceled"
            if msg.lowercased().contains("user canceled") {
                throw InstallError.userCancelled
            }
            throw InstallError.scriptFailed(proc.terminationStatus, msg)
        }
    }
}
