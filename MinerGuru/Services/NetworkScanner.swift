import Foundation
import Darwin

struct DiscoveredMiner: Identifiable, Sendable, Equatable {
    var id: String { ipAddress }
    let ipAddress: String
    let info: MinerSystemInfo
    let rawJSON: String
    let responseTimeMs: Double

    init(ipAddress: String, info: MinerSystemInfo, rawJSON: String, responseTimeMs: Double) {
        self.ipAddress = ipAddress
        self.info = info
        self.rawJSON = rawJSON
        self.responseTimeMs = responseTimeMs
    }
}

enum NetworkScanner {
    /// Detects the active local IPv4 `/24` prefix (e.g., `"192.168.1"`) and full local IP of the Mac.
    static func detectLocalSubnetPrefix() -> (prefix: String, localIP: String) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return ("192.168.1", "192.168.1.100")
        }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(interface: String, ip: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr

        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback, let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    addr,
                    socklen_t(addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = String(decoding: hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    let name = String(cString: current.pointee.ifa_name)
                    if isPrivateIPv4(ip) {
                        candidates.append((name, ip))
                    }
                }
            }
            ptr = current.pointee.ifa_next
        }

        // Prefer standard macOS Ethernet/Wi-Fi interfaces (en0, en1, en2...)
        let preferred = candidates.first(where: { $0.interface == "en0" })
            ?? candidates.first(where: { $0.interface.hasPrefix("en") })
            ?? candidates.first

        if let chosen = preferred {
            let parts = chosen.ip.split(separator: ".")
            if parts.count == 4 {
                let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"
                return (prefix, chosen.ip)
            }
        }
        return ("192.168.1", "192.168.1.100")
    }

    static func isPrivateIPv4(_ ip: String) -> Bool {
        if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") {
            return true
        }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    /// Scans a `/24` subnet (`<prefix>.1` ... `<prefix>.254`) concurrently for Bitaxe & NerdQAxe++ miners.
    static func scanSubnet(
        prefix rawPrefix: String,
        concurrency: Int = 36,
        timeoutPerHost: TimeInterval = 1.5,
        onProgress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void,
        onDiscovered: @escaping @Sendable (DiscoveredMiner) -> Void
    ) async -> [DiscoveredMiner] {
        let prefix = normalizePrefix(rawPrefix)
        let hosts = (1...254).map { "\(prefix).\($0)" }
        let total = hosts.count

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutPerHost
        config.timeoutIntervalForResource = timeoutPerHost + 0.5
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        let scanSession = URLSession(configuration: config)

        return await withTaskGroup(of: DiscoveredMiner?.self, returning: [DiscoveredMiner].self) { group in
            var nextIndex = 0
            var completedCount = 0
            var discovered: [DiscoveredMiner] = []

            let initialBatch = min(concurrency, total)
            while nextIndex < initialBatch {
                let ip = hosts[nextIndex]
                nextIndex += 1
                group.addTask {
                    await probeHost(ip: ip, session: scanSession, timeout: timeoutPerHost)
                }
            }

            while let result = await group.next() {
                completedCount += 1
                onProgress(completedCount, total)

                if let miner = result {
                    discovered.append(miner)
                    onDiscovered(miner)
                }

                if nextIndex < total && !Task.isCancelled {
                    let ip = hosts[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        await probeHost(ip: ip, session: scanSession, timeout: timeoutPerHost)
                    }
                }
            }

            return discovered.sorted { ipSortKey($0.ipAddress) < ipSortKey($1.ipAddress) }
        }
    }

    private static func probeHost(
        ip: String,
        session: URLSession,
        timeout: TimeInterval
    ) async -> DiscoveredMiner? {
        guard !Task.isCancelled,
              let url = URL(string: "http://\(ip)/api/system/info") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let startNs = DispatchTime.now().uptimeNanoseconds
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }

        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
        guard let info = try? JSONDecoder().decode(MinerSystemInfo.self, from: data) else {
            return nil
        }

        let rawJSON = String(data: data, encoding: .utf8) ?? "{}"
        return DiscoveredMiner(
            ipAddress: ip,
            info: info,
            rawJSON: rawJSON,
            responseTimeMs: elapsedMs
        )
    }

    static func normalizePrefix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".").map(String.init)
        if parts.count >= 3 {
            return "\(parts[0]).\(parts[1]).\(parts[2])"
        }
        return trimmed
    }

    static func ipSortKey(_ ip: String) -> Int {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }
}
