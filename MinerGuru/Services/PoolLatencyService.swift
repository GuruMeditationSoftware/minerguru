import Foundation
import Darwin

/// Service that measures real-time TCP round-trip latency (RTT in ms) to Stratum mining pool servers.
actor PoolLatencyService {
    static let shared = PoolLatencyService()

    init() {}

    /// Measures TCP connect RTT (SYN -> SYN-ACK) in milliseconds to `host:port`, excluding DNS lookup time.
    func measureTCPConnectLatencyMs(
        host rawHost: String,
        port: Int,
        timeoutMs: Int32 = 2500
    ) async -> Double? {
        let host = StratumHost.clean(rawHost)
        guard !host.isEmpty, (1...65535).contains(port) else { return nil }

        return await Task.detached(priority: .utility) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            hints.ai_protocol = IPPROTO_TCP

            var res: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, String(port), &hints, &res)
            guard status == 0, let firstAddr = res else {
                return nil
            }
            defer { freeaddrinfo(res) }

            let sock = socket(firstAddr.pointee.ai_family, firstAddr.pointee.ai_socktype, firstAddr.pointee.ai_protocol)
            guard sock >= 0 else { return nil }
            defer { close(sock) }

            // Set non-blocking mode
            let flags = fcntl(sock, F_GETFL, 0)
            _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

            let startNs = DispatchTime.now().uptimeNanoseconds
            let connectResult = connect(sock, firstAddr.pointee.ai_addr, firstAddr.pointee.ai_addrlen)

            if connectResult == 0 {
                let elapsedNs = DispatchTime.now().uptimeNanoseconds - startNs
                return Double(elapsedNs) / 1_000_000.0
            }

            guard errno == EINPROGRESS else {
                return nil
            }

            var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
            let pollRes = poll(&pfd, 1, timeoutMs)
            guard pollRes > 0 else {
                return nil
            }

            var socketError: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &len) < 0 || socketError != 0 {
                return nil
            }

            let elapsedNs = DispatchTime.now().uptimeNanoseconds - startNs
            return Double(elapsedNs) / 1_000_000.0
        }.value
    }

    /// Measures pool latency for both primary and fallback pools of a miner and combines with miner-reported latency.
    func measureForMiner(info: MinerSystemInfo) async -> PoolLatencyMeasurement {
        async let primaryPing: Double? = {
            guard !info.stratumURL.isEmpty else { return nil }
            return await measureTCPConnectLatencyMs(host: info.stratumURL, port: info.stratumPort)
        }()

        async let fallbackPing: Double? = {
            guard !info.fallbackStratumURL.isEmpty else { return nil }
            // Avoid duplicate ping if primary and fallback are identical
            if StratumHost.clean(info.fallbackStratumURL) == StratumHost.clean(info.stratumURL)
                && info.fallbackStratumPort == info.stratumPort {
                return nil
            }
            return await measureTCPConnectLatencyMs(host: info.fallbackStratumURL, port: info.fallbackStratumPort)
        }()

        let (pMs, fMs) = await (primaryPing, fallbackPing)
        let resolvedFallback = fMs ?? (
            (StratumHost.clean(info.fallbackStratumURL) == StratumHost.clean(info.stratumURL)
                && info.fallbackStratumPort == info.stratumPort) ? pMs : nil
        )

        return PoolLatencyMeasurement(
            minerReportedMs: info.minerReportedPoolLatencyMs,
            primaryPoolDirectMs: pMs,
            fallbackPoolDirectMs: resolvedFallback,
            measuredAt: Date()
        )
    }
}
