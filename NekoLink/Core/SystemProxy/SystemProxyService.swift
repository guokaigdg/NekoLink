import Foundation
import Observation

/// 系统代理状态 + 启停。通过 XPC 与 CatcatHelper 通信。
@Observable
@MainActor
final class SystemProxyService {

    // MARK: - 状态
    private(set) var isEnabled = false
    private(set) var helperInstalled: Bool = HelperInstaller.isInstalled()
    private(set) var helperVersion: String?
    private(set) var lastError: String?

    /// mihomo mixed-port，默认 7890；后续若解析订阅 yaml 可动态读取
    var proxyHost = "127.0.0.1"
    var proxyPort = 7890
    var bypass: [String] = ["localhost", "127.0.0.1", "*.local"]

    // MARK: - 公开操作

    func ensureHelperInstalled() async throws {
        if HelperInstaller.isInstalled() { helperInstalled = true; return }
        try await Task.detached {
            try HelperInstaller.install()
        }.value
        helperInstalled = HelperInstaller.isInstalled()
    }

    func enable() async {
        let host = proxyHost
        let port = proxyPort
        let by = bypass
        // 乐观更新：立刻让 UI 响应
        isEnabled = true
        do {
            try await ensureHelperInstalled()
            try await XPCBridge.call { proxy, finish in
                proxy.setSystemProxy(host: host, port: port, bypass: by) { ok, msg in
                    finish(ok ? .success(()) : .failure(SystemProxyError.helper(msg ?? "未知错误")))
                }
            }
        } catch {
            lastError = "\(error)"
        }
        // 异步验证真实状态（在后台线程跑 networksetup）
        await refreshStatus()
    }

    func disable() async {
        guard helperInstalled else { isEnabled = false; return }
        // 乐观更新
        isEnabled = false
        do {
            try await XPCBridge.call { proxy, finish in
                proxy.clearSystemProxy { ok, msg in
                    finish(ok ? .success(()) : .failure(SystemProxyError.helper(msg ?? "未知错误")))
                }
            }
        } catch {
            lastError = "\(error)"
        }
        await refreshStatus()
    }

    func toggle() async {
        if isEnabled { await disable() } else { await enable() }
    }

    /// 主动同步系统状态。优先用 networksetup 直接读取（不需要 root），失败时回退 XPC。
    func refreshStatus() async {
        helperInstalled = HelperInstaller.isInstalled()
        guard helperInstalled else { isEnabled = false; return }

        // 方案 A：在后台线程跑 networksetup（不阻塞 MainActor），无需 XPC，无需 root
        if let state = await Task.detached { Self.readProxyStateFromNetworkSetup() }.value {
            isEnabled = state.enabled
                && state.host == proxyHost
                && state.port == proxyPort
            // 同步 helper 版本（仅在有 XPC 时尝试）
            if let v = try? await XPCBridge.call({ proxy, finish in
                proxy.version { finish(.success($0)) }
            }) {
                helperVersion = v
            }
            return
        }

        // 方案 B：回退 XPC
        let expectHost = proxyHost
        let expectPort = proxyPort
        do {
            let result: ProxyState = try await XPCBridge.call { proxy, finish in
                proxy.currentProxy { enabled, host, port in
                    finish(.success(ProxyState(enabled: enabled, host: host, port: port)))
                }
            }
            isEnabled = result.enabled && result.host == expectHost && result.port == expectPort

            let v: String = try await XPCBridge.call { proxy, finish in
                proxy.version { finish(.success($0)) }
            }
            helperVersion = v
        } catch {
            lastError = "\(error)"
        }
    }

    /// 通过 /usr/sbin/networksetup 直接读取系统代理状态（不需要 root 权限）。
    private nonisolated static func readProxyStateFromNetworkSetup() -> ProxyState? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        proc.arguments = ["-listallnetworkservices"]
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()
        do { try proc.run(); proc.waitUntilExit() } catch { return nil }
        guard proc.terminationStatus == 0 else { return nil }
        let services = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .components(separatedBy: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        guard let firstService = services?.first else { return nil }

        // 读取 HTTP 代理
        let getProc = Process()
        getProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        getProc.arguments = ["-getwebproxy", firstService]
        let getOutPipe = Pipe()
        getProc.standardOutput = getOutPipe
        getProc.standardError = Pipe()
        do { try getProc.run(); getProc.waitUntilExit() } catch { return nil }
        guard getProc.terminationStatus == 0 else { return nil }
        let output = String(data: getOutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        var enabled = false
        var host: String?
        var port = 0
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("Enabled: ") {
                enabled = line.contains("Yes")
            } else if line.hasPrefix("Server: ") {
                host = line.replacingOccurrences(of: "Server: ", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Port: ") {
                port = Int(line.replacingOccurrences(of: "Port: ", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return ProxyState(enabled: enabled, host: host, port: port)
    }

    func uninstallHelper() async {
        do {
            try HelperInstaller.uninstall()
            helperInstalled = false
            isEnabled = false
        } catch {
            lastError = "\(error)"
        }
    }
}

private struct ProxyState: Sendable {
    let enabled: Bool
    let host: String?
    let port: Int
}

enum SystemProxyError: Error, LocalizedError {
    case helper(String)
    case noProxy
    var errorDescription: String? {
        switch self {
        case .helper(let m): return m
        case .noProxy: return "无法获取 helper 代理"
        }
    }
}

// MARK: - XPC 桥接

/// 把基于回调的 NSXPCConnection 适配成 async/await，规避 Swift 6 的 Sendable 检查。
private enum XPCBridge {

    /// 调用一次 helper 方法。`work` 在连接就绪后被调用，必须最终调用一次 `finish`。
    static func call<T: Sendable>(
        _ work: @escaping @Sendable (any HelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            // 用专属辅助类把可变引用与连接包起来，避免捕获 NSXPCConnection 的 @Sendable 报错。
            let session = XPCSession<T>(continuation: cont)
            session.start(work: work)
        }
    }
}

/// 包装单次 XPC 调用的全部状态。所有跨线程访问通过 NSLock 序列化。
/// 通过 @unchecked Sendable 抑制 NSXPCConnection 不 Sendable 的告警 —— 仅在 lock 内部访问。
private final class XPCSession<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var conn: NSXPCConnection?
    private let cont: CheckedContinuation<T, Error>

    init(continuation: CheckedContinuation<T, Error>) {
        self.cont = continuation
    }

    func start(work: @escaping @Sendable (any HelperProtocol, @escaping @Sendable (Result<T, Error>) -> Void) -> Void) {
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        conn.invalidationHandler = { [weak self] in
            self?.finish(.failure(SystemProxyError.helper("Helper 未安装或连接已断开")))
        }
        conn.interruptionHandler = { [weak self] in
            self?.finish(.failure(SystemProxyError.helper("Helper 连接中断")))
        }

        lock.lock()
        self.conn = conn
        lock.unlock()

        conn.resume()

        let proxyObject = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.finish(.failure(error))
        }
        guard let proxy = proxyObject as? HelperProtocol else {
            finish(.failure(SystemProxyError.noProxy))
            return
        }

        work(proxy) { [weak self] result in
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<T, Error>) {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        let c = conn
        conn = nil
        lock.unlock()

        c?.invalidate()
        switch result {
        case .success(let v): cont.resume(returning: v)
        case .failure(let e): cont.resume(throwing: e)
        }
    }
}
