import NetworkExtension
import OSLog

/// NekoLink TUN 模式提供者。
///
/// 职责：
/// 1. 启动 mihomo 子进程并启用 TUN 模式
/// 2. 配置 TUN 虚拟网卡（IP、路由、DNS）
/// 3. 管理隧道生命周期
///
/// mihomo 内建 TUN 支持，本 provider 负责创建虚拟网卡并将流量导入 mihomo。
class PacketTunnelProvider: NEPacketTunnelProvider {

    private let logger = Logger(subsystem: "app.nekolink.tunnel", category: "PacketTunnel")
    private var mihomoProcess: Process?
    private var mihomoStdout: Pipe?

    // MARK: - 隧道生命周期

    override func startTunnel(options: [String: NSObject]? = nil, completionHandler: @escaping (Error?) -> Void) {
        logger.log("开始启动 TUN 隧道")

        guard let config = loadConfig() else {
            logger.error("无法加载配置")
            completionHandler(TunnelError.configMissing)
            return
        }

        do {
            // 1. 配置网络设置（IP、路由、DNS）
            let tunnelSettings = try makeNetworkSettings(config: config)

            // 2. 设置 TUN 网络参数
            setTunnelNetworkSettings(tunnelSettings) { [weak self] error in
                if let error {
                    self?.logger.error("设置 TUN 网络参数失败: \(error.localizedDescription)")
                    completionHandler(error)
                    return
                }

                // 3. 启动 mihomo
                self?.startMihomo(config: config) { error in
                    if let error {
                        self?.logger.error("启动 mihomo 失败: \(error.localizedDescription)")
                        completionHandler(error)
                    } else {
                        self?.logger.log("TUN 隧道已启动")
                        completionHandler(nil)
                    }
                }
            }
        } catch {
            logger.error("TUN 隧道启动失败: \(error.localizedDescription)")
            completionHandler(error)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        logger.log("停止 TUN 隧道，原因: \(reason.rawValue)")

        stopMihomo()

        // 取消所有挂起的数据包
        cancelTunnelWithError(nil)
        completionHandler()
    }

    // MARK: - mihomo 进程管理

    private func startMihomo(config: TunnelConfig, completion: @escaping (Error?) -> Void) {
        guard let binary = locateMihomoBinary() else {
            completion(TunnelError.binaryNotFound)
            return
        }

        let configDir = configDirectory()
        let configFile = configDir.appendingPathComponent("config.yaml")

        // 写入启用了 TUN 的配置
        do {
            let yaml = makeTunConfigYAML(config: config)
            try yaml.write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            completion(error)
            return
        }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["-d", configDir.path]

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = outPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let line = String(data: data, encoding: .utf8) {
                self?.logger.debug("mihomo: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        proc.terminationHandler = { [weak self] p in
            self?.logger.log("mihomo 进程退出，状态码: \(p.terminationStatus)")
            self?.mihomoProcess = nil
        }

        do {
            try proc.run()
            mihomoProcess = proc
            mihomoStdout = outPipe

            // 等待 API 就绪
            waitForAPIReady(timeout: 10) { ready in
                if ready {
                    completion(nil)
                } else {
                    completion(TunnelError.startupFailed)
                }
            }
        } catch {
            completion(error)
        }
    }

    private func stopMihomo() {
        mihomoStdout?.fileHandleForReading.readabilityHandler = nil
        mihomoStdout = nil

        guard let proc = mihomoProcess, proc.isRunning else {
            mihomoProcess = nil
            return
        }

        proc.terminate()
        for _ in 0..<15 {
            if !proc.isRunning { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        mihomoProcess = nil
    }

    // MARK: - 网络配置

    private func makeNetworkSettings(config: TunnelConfig) throws -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "240.0.0.1")

        // IPv4 配置
        let ipv4 = NEIPv4Settings(addresses: config.tunAddresses, subnetMasks: config.tunSubnetMasks)
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = [
            // 排除本地和内部流量
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"), // Apple
        ]
        settings.ipv4Settings = ipv4

        // DNS 配置
        let dns = NEDNSSettings(servers: config.dnsServers ?? ["223.5.5.5", "114.114.114.114"])
        settings.dnsSettings = dns

        // MTU
        settings.mtu = config.mtu ?? 1500

        return settings
    }

    // MARK: - 配置加载

    private struct TunnelConfig {
        var tunAddresses: [String]
        var tunSubnetMasks: [String]
        var dnsServers: [String]?
        var mtu: Int?
        var mixedPort: Int
        var logLevel: String
        var deviceName: String
    }

    private func loadConfig() -> TunnelConfig? {
        // 从 protocol configuration 中读取
        if let proto = protocolConfiguration as? NETunnelProviderProtocol,
           let dict = proto.providerConfiguration {
            let addresses = dict["tunAddresses"] as? [String] ?? ["198.18.0.1"]
            let masks = dict["tunSubnetMasks"] as? [String] ?? ["255.255.255.0"]
            let dns = dict["dnsServers"] as? [String]
            let mtu = dict["mtu"] as? Int
            let port = dict["mixedPort"] as? Int ?? 7890
            let logLevel = dict["logLevel"] as? String ?? "info"
            let deviceName = dict["deviceName"] as? String ?? "neko0"

            return TunnelConfig(
                tunAddresses: addresses,
                tunSubnetMasks: masks,
                dnsServers: dns,
                mtu: mtu,
                mixedPort: port,
                logLevel: logLevel,
                deviceName: deviceName
            )
        }
        // 默认配置
        return TunnelConfig(
            tunAddresses: ["198.18.0.1"],
            tunSubnetMasks: ["255.255.255.0"],
            dnsServers: ["223.5.5.5", "114.114.114.114"],
            mtu: 1500,
            mixedPort: 7890,
            logLevel: "info",
            deviceName: "neko0"
        )
    }

    // MARK: - 辅助方法

    private func locateMihomoBinary() -> URL? {
        // 优先从 app bundle 查找
        if let bundled = Bundle.main.url(forResource: "mihomo", withExtension: nil) {
            return bundled
        }
        // 回退到已知路径
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.config/nekolink/mihomo",
            "/opt/homebrew/bin/mihomo",
            "/usr/local/bin/mihomo"
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func configDirectory() -> URL {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/nekolink", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTunConfigYAML(config: TunnelConfig) -> String {
        """
        # NekoLink TUN 模式配置
        mixed-port: \(config.mixedPort)
        allow-lan: false
        mode: rule
        log-level: \(config.logLevel)
        external-controller: 127.0.0.1:9090

        tun:
          enable: true
          stack: system
          device: \(config.deviceName)
          dns-hijack:
            - 0.0.0.0:53
            - any:53
          auto-route: true
          auto-detect-interface: true

        dns:
          enable: true
          listen: 0.0.0.0:53
          default-nameserver:
            - 223.5.5.5
            - 114.114.114.114
          nameserver:
            - https://doh.alidns.com/dns-query
            - https://doh.pub/dns-query
          fallback:
            - https://dns.quad9.net/dns-query
            - tls://dns.google
          fallback-filter:
            geoip: true
            geoip-code: CN

        proxies: []
        proxy-groups: []
        rules:
          - MATCH,DIRECT
        """
    }

    private func waitForAPIReady(timeout: Int, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://127.0.0.1:9090/version")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        let deadline = DispatchTime.now() + .seconds(timeout)
        let queue = DispatchQueue.global()

        func poll() {
            if DispatchTime.now() >= deadline {
                completion(false)
                return
            }
            let task = URLSession.shared.dataTask(with: request) { _, resp, error in
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    completion(true)
                } else {
                    Thread.sleep(forTimeInterval: 0.5)
                    poll()
                }
            }
            task.resume()
        }
        poll()
    }

    enum TunnelError: Error, LocalizedError {
        case configMissing
        case binaryNotFound
        case startupFailed

        var errorDescription: String? {
            switch self {
            case .configMissing:  return "TUN 配置缺失"
            case .binaryNotFound: return "找不到 mihomo 二进制"
            case .startupFailed:  return "mihomo TUN 启动失败"
            }
        }
    }
}