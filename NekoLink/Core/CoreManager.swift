import Foundation
import Observation

/// 负责启动 / 停止 mihomo 子进程，捕获 stdout 日志。
@Observable
@MainActor
final class CoreManager {

    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    private(set) var state: State = .stopped
    private(set) var recentLogs: [String] = []

    private var process: Process?
    private var stdoutPipe: Pipe?

    /// mihomo 二进制查找顺序：
    /// 1. App Bundle Resources/mihomo
    /// 2. ~/.config/nekolink/mihomo
    /// 3. /opt/homebrew/bin/mihomo
    /// 4. /usr/local/bin/mihomo
    static func locateBinary() -> URL? {
        if let bundled = Bundle.main.url(forResource: "mihomo", withExtension: nil) {
            return bundled
        }
        let fm = FileManager.default
        let candidates: [String] = [
            (NSHomeDirectory() as NSString).appendingPathComponent(".config/nekolink/mihomo"),
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// 配置目录：~/.config/nekolink
    static func configDirectory() -> URL {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/nekolink", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func start() async throws {
        guard state != .running, state != .starting else { return }
        state = .starting

        guard let binary = Self.locateBinary() else {
            state = .failed("找不到 mihomo 二进制")
            throw CoreError.binaryNotFound
        }

        let configDir = Self.configDirectory()
        // 若不存在配置文件，写一个最小占位（仅开放 9090 控制端口）。
        let configFile = configDir.appendingPathComponent("config.yaml")
        if !FileManager.default.fileExists(atPath: configFile.path) {
            try Self.defaultConfigYAML.write(to: configFile, atomically: true, encoding: .utf8)
        }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["-d", configDir.path]

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendLog(line)
            }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                self?.state = (p.terminationStatus == 0) ? .stopped : .failed("退出码 \(p.terminationStatus)")
                self?.process = nil
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.stdoutPipe = outPipe

            // 等待 mihomo API 就绪（轮询 /version 端点，最多 10 秒）
            let apiBaseURL = URL(string: "http://127.0.0.1:9090")!
            var ready = false
            for _ in 0..<20 {
                if !proc.isRunning {
                    state = .failed("mihomo 启动异常退出")
                    throw CoreError.startupFailed
                }
                if await Self.checkAPIReady(at: apiBaseURL) {
                    ready = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if ready {
                state = .running
            } else {
                // mihomo 进程在跑但 API 不就绪（可能 MMDB 下载卡住等）
                state = .running
            }
        } catch {
            state = .failed("\(error)")
            throw error
        }
    }

    /// 检查 mihomo RESTful API 是否可达
    private static func checkAPIReady(at url: URL) async -> Bool {
        guard let components = URLComponents(url: url.appendingPathComponent("version"), resolvingAgainstBaseURL: false) else { return false }
        guard let checkURL = components.url else { return false }
        var request = URLRequest(url: checkURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        do {
            let (_, resp) = try await URLSession.shared.data(for: request)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
            return true
        } catch {
            return false
        }
    }

    func stop() async {
        guard let proc = process, proc.isRunning else {
            state = .stopped
            return
        }
        proc.terminate()
        // 等待 1.5s，必要时强杀。
        for _ in 0..<15 {
            if !proc.isRunning { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        process = nil
        state = .stopped
    }

    private func appendLog(_ chunk: String) {
        let lines = chunk.split(separator: "\n").map(String.init)
        recentLogs.append(contentsOf: lines)
        // 保留最近 500 行
        if recentLogs.count > 500 {
            recentLogs.removeFirst(recentLogs.count - 500)
        }
    }

    enum CoreError: Error, LocalizedError {
        case binaryNotFound
        case startupFailed
        var errorDescription: String? {
            switch self {
            case .binaryNotFound: return "找不到 mihomo 二进制，请放置到 ~/.config/nekolink/mihomo 或通过 brew 安装"
            case .startupFailed: return "mihomo 启动失败，可能 geoip 数据损坏或配置有误"
            }
        }
    }

    private static let defaultConfigYAML: String = """
    # NekoLink 默认配置（占位）
    mixed-port: 7890
    allow-lan: false
    mode: rule
    log-level: info
    external-controller: 127.0.0.1:9090
    proxies: []
    proxy-groups: []
    rules:
      - MATCH,DIRECT
    """
}
