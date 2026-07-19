import Foundation

/// 通过 networksetup 操作系统代理。
final class HelperService: NSObject, HelperProtocol {

    // MARK: - HelperProtocol

    func version(reply: @escaping (String) -> Void) {
        reply(HelperConstants.currentVersion)
    }

    func setSystemProxy(host: String,
                        port: Int,
                        bypass: [String],
                        reply: @escaping (Bool, String?) -> Void) {
        do {
            let services = try activeNetworkServices()
            for svc in services {
                try run("-setwebproxy", svc, host, "\(port)")
                try run("-setsecurewebproxy", svc, host, "\(port)")
                try run("-setsocksfirewallproxy", svc, host, "\(port)")
                try run("-setwebproxystate", svc, "on")
                try run("-setsecurewebproxystate", svc, "on")
                try run("-setsocksfirewallproxystate", svc, "on")
                if !bypass.isEmpty {
                    try run(["-setproxybypassdomains", svc] + bypass)
                }
            }
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func clearSystemProxy(reply: @escaping (Bool, String?) -> Void) {
        do {
            let services = try activeNetworkServices()
            for svc in services {
                try run("-setwebproxystate", svc, "off")
                try run("-setsecurewebproxystate", svc, "off")
                try run("-setsocksfirewallproxystate", svc, "off")
            }
            reply(true, nil)
        } catch {
            reply(false, "\(error)")
        }
    }

    func currentProxy(reply: @escaping (Bool, String?, Int) -> Void) {
        do {
            guard let svc = try activeNetworkServices().first else {
                reply(false, nil, 0)
                return
            }
            // 解析 networksetup -getwebproxy <svc>
            let out = try capture("-getwebproxy", svc)
            let enabled = out.contains("Enabled: Yes")
            var host: String?
            var port = 0
            for line in out.components(separatedBy: "\n") {
                if line.hasPrefix("Server: ") {
                    host = line.replacingOccurrences(of: "Server: ", with: "").trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Port: ") {
                    port = Int(line.replacingOccurrences(of: "Port: ", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
            reply(enabled, host, port)
        } catch {
            reply(false, nil, 0)
        }
    }

    func uninstall(reply: @escaping (Bool, String?) -> Void) {
        // 由 main.swift 完成实际卸载（这里只是先返回，让客户端断开后再清理）
        reply(true, nil)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            performUninstall()
        }
    }

    // MARK: - 工具

    private func activeNetworkServices() throws -> [String] {
        let out = try capture("-listallnetworkservices")
        return out
            .components(separatedBy: "\n")
            .dropFirst()  // 第一行是说明
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }   // * 表示 disabled
    }

    @discardableResult
    private func run(_ args: String...) throws -> String { try run(args) }

    @discardableResult
    private func run(_ args: [String]) throws -> String {
        try capture(args)
    }

    private func capture(_ args: String...) throws -> String { try capture(args) }

    private func capture(_ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "Helper", code: Int(proc.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "networksetup \(args.joined(separator: " "))\n\(err.isEmpty ? out : err)"])
        }
        return out
    }
}

func performUninstall() {
    let fm = FileManager.default
    _ = try? fm.removeItem(atPath: HelperConstants.helperBinaryPath)
    _ = try? fm.removeItem(atPath: HelperConstants.helperPlistPath)
    let unload = Process()
    unload.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unload.arguments = ["bootout", "system/" + HelperConstants.helperLabel]
    try? unload.run()
    unload.waitUntilExit()
    exit(0)
}
