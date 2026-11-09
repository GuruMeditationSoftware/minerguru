import Foundation

/// Detailed per-pool status returned in `stratum.pools[]` by NerdOS (NerdQAxe++) and newer AxeOS versions.
struct MinerStratumPoolStatus: Codable, Sendable, Equatable {
    var active: Bool?
    var connected: Bool?
    var poolDifficulty: Double?
    var networkDifficulty: Double?
    var poolDiffErr: Bool?
    var accepted: Int?
    var rejected: Int?
    var pingRtt: Double?
    var pingLoss: Double?
    var bestDiff: Double?
    var responseTime: Double?

    init(
        active: Bool? = nil,
        connected: Bool? = nil,
        poolDifficulty: Double? = nil,
        networkDifficulty: Double? = nil,
        poolDiffErr: Bool? = nil,
        accepted: Int? = nil,
        rejected: Int? = nil,
        pingRtt: Double? = nil,
        pingLoss: Double? = nil,
        bestDiff: Double? = nil,
        responseTime: Double? = nil
    ) {
        self.active = active
        self.connected = connected
        self.poolDifficulty = poolDifficulty
        self.networkDifficulty = networkDifficulty
        self.poolDiffErr = poolDiffErr
        self.accepted = accepted
        self.rejected = rejected
        self.pingRtt = pingRtt
        self.pingLoss = pingLoss
        self.bestDiff = bestDiff
        self.responseTime = responseTime
    }

    /// Effective latency in ms for this pool slot (`pingRtt` on NerdQAxe++ or `responseTime` on AxeOS).
    var effectiveLatencyMs: Double? {
        if let pingRtt, pingRtt > 0 { return pingRtt }
        if let responseTime, responseTime > 0 { return responseTime }
        return nil
    }
}

struct MinerStratumDetail: Codable, Sendable, Equatable {
    /// `0` = Classic Primary/Fallback Failover, `1` = Simultaneous Dual-Pool Mining.
    var poolMode: Int?
    var activePoolMode: Int?
    /// Percentage of hashrate allocated to Pool 1 in Dual-Pool mode (`1...99`, where Pool 2 gets `100 - poolBalance`).
    var poolBalance: Int?
    var usingFallback: Bool?
    var totalBestDiff: Double?
    var pools: [MinerStratumPoolStatus]?

    init(
        poolMode: Int? = nil,
        activePoolMode: Int? = nil,
        poolBalance: Int? = nil,
        usingFallback: Bool? = nil,
        totalBestDiff: Double? = nil,
        pools: [MinerStratumPoolStatus]? = nil
    ) {
        self.poolMode = poolMode
        self.activePoolMode = activePoolMode
        self.poolBalance = poolBalance
        self.usingFallback = usingFallback
        self.totalBestDiff = totalBestDiff
        self.pools = pools
    }
}

struct ShareRejectionReason: Codable, Sendable, Equatable, Hashable {
    var message: String
    var count: Int

    init(message: String, count: Int) {
        self.message = message
        self.count = count
    }
}

/// Unified telemetry model decoded from `GET /api/system/info` across Bitaxe (AxeOS) and NerdQAxe++ (NerdOS).
struct MinerSystemInfo: Codable, Sendable, Equatable {
    // MARK: - Hashrate (in GH/s)
    var hashRate: Double
    var hashRate1m: Double?
    var hashRate10m: Double?
    var hashRate1h: Double?
    var hashRate1d: Double?
    var expectedHashrate: Double?

    // MARK: - Thermal & Cooling
    var temp: Double
    var vrTemp: Double?
    var fanSpeedPercent: Double
    var fanRPM: Int
    var fan2SpeedPercent: Double?
    var fan2RPM: Int?
    var autoFanSpeed: Bool
    var autoFanModeRaw: Int
    var targetTemp: Double?
    var overheatMode: Bool
    /// NerdOS: the limit the firmware protects itself at; it has no overheat flag.
    var overheatTemp: Double?
    /// AxeOS 2.15+: paused on purpose.
    var miningPaused: Bool
    /// What the pool really set; `stratumSuggestedDifficulty` is only what the miner asked for.
    var reportedPoolDifficulty: Double?
    /// NerdOS: settings can only be changed with a one-time code.
    var otp: Bool

    // MARK: - Power & ASIC Clocking
    var power: Double
    var voltageVolts: Double
    var currentAmps: Double
    var coreVoltageTargetMV: Int
    var coreVoltageActualMV: Int
    var frequencyMHz: Int
    var overclockEnabled: Bool

    // MARK: - Shares & Difficulty
    var sharesAccepted: Int
    var sharesRejected: Int
    var sharesRejectedReasons: [ShareRejectionReason]
    /// Share of hashes the chips got wrong, as AxeOS reports it.
    var errorPercentage: Double?
    var bestDiffFormatted: String
    var bestDiffNumeric: Double
    var bestSessionDiffFormatted: String
    var bestSessionDiffNumeric: Double
    var networkDifficulty: Double?

    // MARK: - Pool & Stratum
    var stratumURL: String
    var stratumPort: Int
    var stratumUser: String
    var stratumSuggestedDifficulty: Double?
    var fallbackStratumURL: String
    var fallbackStratumPort: Int
    var fallbackStratumUser: String
    var isUsingFallbackStratum: Bool
    /// Pool round-trip latency in milliseconds reported directly by the miner firmware (if supported).
    var minerReportedPoolLatencyMs: Double?
    var stratumDetail: MinerStratumDetail?
    /// Configured pool slots on AxeOS 2.15+ (`pools[]`), `nil` on older firmware and NerdOS.
    var axePools: [AxeOSPool]? = nil
    var primaryPoolIndex: Int? = nil
    var secondaryPoolIndex: Int? = nil
    /// Top-level decode flags of primary and fallback (AxeOS 2.13+); slots carry their own on 2.15+.
    var stratumDecodeCoinbase: Bool? = nil
    var fallbackStratumDecodeCoinbase: Bool? = nil
    /// Top-level TLS flags of primary and fallback (AxeOS reports 0/1, NerdOS true/false).
    var stratumTLS: Bool? = nil
    var fallbackStratumTLS: Bool? = nil

    // MARK: - Current Block Template (AxeOS 2.13+, see `BlockTemplateSummary`)
    var blockHeight: Int? = nil
    /// Pool tag from the coinbase scriptSig, e.g. `/solo.ckpool.org/`.
    var blockScriptSig: String? = nil
    var blockSignals: [String]? = nil
    var coinbaseOutputs: [CoinbaseOutput]? = nil
    var coinbaseOthersCount: Int? = nil
    var coinbaseOthersValueSats: Double? = nil
    var coinbaseValueTotalSats: Double? = nil
    var coinbaseValueUserSats: Double? = nil
    /// `verified`, `not_found`, `not_applicable` or `unknown` (AxeOS 2.16+).
    var coinbasePayoutStatus: String? = nil

    // MARK: - Hardware & System Identification
    var deviceModel: String?
    var asicModel: String
    var boardVersion: String?
    var asicCount: Int
    var smallCoreCount: Int?
    /// Factory clock reported by NerdOS (`defaultFrequency` / `defaultCoreVoltage`).
    var defaultFrequencyMHz: Int? = nil
    var defaultCoreVoltageMV: Int? = nil
    var hostname: String
    var macAddress: String?
    var ssid: String?
    var wifiStatus: String?
    var wifiRSSI: Int?
    var firmwareVersion: String
    var axeOSVersion: String?
    var idfVersion: String?
    var uptimeSeconds: Int
    /// Why the miner last started, in the firmware's words (`resetReason`, NerdOS `lastResetReason`).
    var resetReason: String? = nil
    var freeHeap: Int?

    init(
        hashRate: Double = 0,
        hashRate1m: Double? = nil,
        hashRate10m: Double? = nil,
        hashRate1h: Double? = nil,
        hashRate1d: Double? = nil,
        expectedHashrate: Double? = nil,
        temp: Double = 0,
        vrTemp: Double? = nil,
        fanSpeedPercent: Double = 0,
        fanRPM: Int = 0,
        fan2SpeedPercent: Double? = nil,
        fan2RPM: Int? = nil,
        autoFanSpeed: Bool = true,
        autoFanModeRaw: Int = 1,
        targetTemp: Double? = nil,
        overheatMode: Bool = false,
        overheatTemp: Double? = nil,
        miningPaused: Bool = false,
        reportedPoolDifficulty: Double? = nil,
        otp: Bool = false,
        power: Double = 0,
        voltageVolts: Double = 0,
        currentAmps: Double = 0,
        coreVoltageTargetMV: Int = 1200,
        coreVoltageActualMV: Int = 1200,
        frequencyMHz: Int = 525,
        overclockEnabled: Bool = false,
        sharesAccepted: Int = 0,
        sharesRejected: Int = 0,
        errorPercentage: Double? = nil,
        sharesRejectedReasons: [ShareRejectionReason] = [],
        bestDiffFormatted: String = "0",
        bestDiffNumeric: Double = 0,
        bestSessionDiffFormatted: String = "0",
        bestSessionDiffNumeric: Double = 0,
        networkDifficulty: Double? = nil,
        stratumURL: String = "",
        stratumPort: Int = 3333,
        stratumUser: String = "",
        stratumSuggestedDifficulty: Double? = nil,
        fallbackStratumURL: String = "",
        fallbackStratumPort: Int = 3333,
        fallbackStratumUser: String = "",
        isUsingFallbackStratum: Bool = false,
        minerReportedPoolLatencyMs: Double? = nil,
        stratumDetail: MinerStratumDetail? = nil,
        deviceModel: String? = nil,
        asicModel: String = "BM1370",
        boardVersion: String? = nil,
        asicCount: Int = 1,
        smallCoreCount: Int? = nil,
        hostname: String = "miner",
        macAddress: String? = nil,
        ssid: String? = nil,
        wifiStatus: String? = nil,
        wifiRSSI: Int? = nil,
        firmwareVersion: String = "",
        axeOSVersion: String? = nil,
        idfVersion: String? = nil,
        uptimeSeconds: Int = 0,
        freeHeap: Int? = nil
    ) {
        self.hashRate = hashRate
        self.hashRate1m = hashRate1m
        self.hashRate10m = hashRate10m
        self.hashRate1h = hashRate1h
        self.hashRate1d = hashRate1d
        self.expectedHashrate = expectedHashrate
        self.temp = temp
        self.vrTemp = vrTemp
        self.fanSpeedPercent = fanSpeedPercent
        self.fanRPM = fanRPM
        self.fan2SpeedPercent = fan2SpeedPercent
        self.fan2RPM = fan2RPM
        self.autoFanSpeed = autoFanSpeed
        self.autoFanModeRaw = autoFanModeRaw
        self.targetTemp = targetTemp
        self.overheatMode = overheatMode
        self.overheatTemp = overheatTemp
        self.miningPaused = miningPaused
        self.reportedPoolDifficulty = reportedPoolDifficulty
        self.otp = otp
        self.power = power
        self.voltageVolts = voltageVolts
        self.currentAmps = currentAmps
        self.coreVoltageTargetMV = coreVoltageTargetMV
        self.coreVoltageActualMV = coreVoltageActualMV
        self.frequencyMHz = frequencyMHz
        self.overclockEnabled = overclockEnabled
        self.sharesAccepted = sharesAccepted
        self.sharesRejected = sharesRejected
        self.errorPercentage = errorPercentage
        self.sharesRejectedReasons = sharesRejectedReasons
        self.bestDiffFormatted = bestDiffFormatted
        self.bestDiffNumeric = bestDiffNumeric
        self.bestSessionDiffFormatted = bestSessionDiffFormatted
        self.bestSessionDiffNumeric = bestSessionDiffNumeric
        self.networkDifficulty = networkDifficulty
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.stratumUser = stratumUser
        self.stratumSuggestedDifficulty = stratumSuggestedDifficulty
        self.fallbackStratumURL = fallbackStratumURL
        self.fallbackStratumPort = fallbackStratumPort
        self.fallbackStratumUser = fallbackStratumUser
        self.isUsingFallbackStratum = isUsingFallbackStratum
        self.minerReportedPoolLatencyMs = minerReportedPoolLatencyMs
        self.stratumDetail = stratumDetail
        self.deviceModel = deviceModel
        self.asicModel = asicModel
        self.boardVersion = boardVersion
        self.asicCount = asicCount
        self.smallCoreCount = smallCoreCount
        self.hostname = hostname
        self.macAddress = macAddress
        self.ssid = ssid
        self.wifiStatus = wifiStatus
        self.wifiRSSI = wifiRSSI
        self.firmwareVersion = firmwareVersion
        self.axeOSVersion = axeOSVersion
        self.idfVersion = idfVersion
        self.uptimeSeconds = uptimeSeconds
        self.freeHeap = freeHeap
    }

    // MARK: - Computed Metrics & Dual-Pool Detection

    /// Energy efficiency in Joules per Terahash (J/TH = Watts / TH/s).
    var efficiencyJPerTH: Double {
        let ths = hashRate / 1000.0
        guard ths > 0.01, power > 0 else { return 0 }
        return power / ths
    }

    /// Share rejection percentage (0–100).
    var shareRejectionRatePercent: Double {
        let total = sharesAccepted + sharesRejected
        guard total > 0 else { return 0 }
        return (Double(sharesRejected) / Double(total)) * 100.0
    }

    /// True if the miner is operating in simultaneous Dual-Pool Mining mode (NerdQAxe++ `poolMode == 1` or `activePoolMode == 1`).
    var isDualPoolMining: Bool {
        if let detail = stratumDetail {
            if detail.activePoolMode == 1 || detail.poolMode == 1 {
                return true
            }
            if let pools = detail.pools, pools.count >= 2,
               pools[0].connected == true && pools[1].connected == true && detail.usingFallback != true {
                return true
            }
        }
        return false
    }

    /// Percentage (1...99) of hashrate assigned to Pool 1 in Dual-Pool mode.
    var dualPoolPrimaryPercent: Int {
        let raw = stratumDetail?.poolBalance ?? 50
        return max(1, min(99, raw))
    }

    /// Percentage (1...99) of hashrate assigned to Pool 2 in Dual-Pool mode.
    var dualPoolSecondaryPercent: Int {
        100 - dualPoolPrimaryPercent
    }

    /// Telemetry status for Pool 1 (Primary) from `stratum.pools[0]`, if available.
    var primaryPoolStatus: MinerStratumPoolStatus? {
        guard let pools = stratumDetail?.pools, !pools.isEmpty else { return nil }
        return pools[0]
    }

    /// Telemetry status for Pool 2 (Secondary / Fallback) from `stratum.pools[1]`, if available.
    var secondaryPoolStatus: MinerStratumPoolStatus? {
        guard let pools = stratumDetail?.pools, pools.count >= 2 else { return nil }
        return pools[1]
    }

    /// Miner-reported Stratum ping RTT (ms) specifically for Pool 1.
    var primaryPoolMinerLatencyMs: Double? {
        if let p0 = primaryPoolStatus?.effectiveLatencyMs {
            return p0
        }
        if !isUsingFallbackStratum, let rt = minerReportedPoolLatencyMs, rt > 0 {
            return rt
        }
        return nil
    }

    /// Miner-reported Stratum ping RTT (ms) specifically for Pool 2.
    var secondaryPoolMinerLatencyMs: Double? {
        if let p1 = secondaryPoolStatus?.effectiveLatencyMs {
            return p1
        }
        if isUsingFallbackStratum, let rt = minerReportedPoolLatencyMs, rt > 0 {
            return rt
        }
        return nil
    }

    var primaryPoolEndpoint: String {
        guard !stratumURL.isEmpty else { return String(localized: "Nicht konfiguriert") }
        return "\(StratumHost.clean(stratumURL, keepPort: true)):\(stratumPort)"
    }

    var fallbackPoolEndpoint: String {
        guard !fallbackStratumURL.isEmpty else { return String(localized: "Nicht konfiguriert") }
        return "\(StratumHost.clean(fallbackStratumURL, keepPort: true)):\(fallbackStratumPort)"
    }

    /// Currently active pool host & port summary (handles Single, Fallback, and Dual-Pool modes).
    var activePoolEndpoint: String {
        if isDualPoolMining {
            let h1 = StratumHost.clean(stratumURL, keepPort: true)
            let h2 = StratumHost.clean(fallbackStratumURL, keepPort: true)
            return "\(h1) (\(dualPoolPrimaryPercent)%) + \(h2) (\(dualPoolSecondaryPercent)%)"
        }
        if isUsingFallbackStratum && !fallbackStratumURL.isEmpty {
            return fallbackPoolEndpoint
        }
        return primaryPoolEndpoint
    }

    var activePoolHost: String {
        if isDualPoolMining {
            return "\(StratumHost.clean(stratumURL, keepPort: true)) + \(StratumHost.clean(fallbackStratumURL, keepPort: true))"
        }
        if isUsingFallbackStratum && !fallbackStratumURL.isEmpty {
            return StratumHost.clean(fallbackStratumURL, keepPort: true)
        }
        return StratumHost.clean(stratumURL, keepPort: true)
    }

    var activePoolPort: Int {
        if isUsingFallbackStratum && !fallbackStratumURL.isEmpty {
            return fallbackStratumPort
        }
        return stratumPort
    }

    var activePoolUser: String {
        if isDualPoolMining {
            let w1 = extractWorker(from: stratumUser) ?? stratumUser
            let w2 = extractWorker(from: fallbackStratumUser) ?? fallbackStratumUser
            if w1 == w2 {
                return stratumUser
            }
            return "\(w1) / \(w2)"
        }
        if isUsingFallbackStratum && !fallbackStratumUser.isEmpty {
            return fallbackStratumUser
        }
        return stratumUser
    }

    /// Extracts worker name suffix from `wallet.worker` if present.
    var activeWorkerName: String? {
        extractWorker(from: isUsingFallbackStratum ? fallbackStratumUser : stratumUser)
    }

    func extractWorker(from user: String) -> String? {
        guard let dotIndex = user.lastIndex(of: "."), dotIndex < user.index(before: user.endIndex) else {
            return nil
        }
        return String(user[user.index(after: dotIndex)...])
    }

    /// Detected cryptocurrency for Pool 1 (Primary).
    var primaryPoolCoin: MinedCoin {
        let netDiff = primaryPoolStatus?.networkDifficulty ?? (!isUsingFallbackStratum ? networkDifficulty : nil)
        return MinedCoin.detect(
            poolHost: StratumHost.clean(stratumURL, keepPort: true),
            stratumUser: stratumUser,
            networkDifficulty: netDiff
        )
    }

    /// Detected cryptocurrency for Pool 2 (Secondary / Fallback).
    var secondaryPoolCoin: MinedCoin {
        let netDiff = secondaryPoolStatus?.networkDifficulty ?? (isUsingFallbackStratum ? networkDifficulty : nil)
        return MinedCoin.detect(
            poolHost: StratumHost.clean(fallbackStratumURL, keepPort: true),
            stratumUser: fallbackStratumUser,
            networkDifficulty: netDiff
        )
    }

    /// Detected cryptocurrency for the currently active pool (or dominant pool in Dual-Pool mode).
    var activePoolCoin: MinedCoin {
        if isDualPoolMining {
            return dualPoolSecondaryPercent > dualPoolPrimaryPercent ? secondaryPoolCoin : primaryPoolCoin
        }
        return isUsingFallbackStratum ? secondaryPoolCoin : primaryPoolCoin
    }

    /// Human-readable summary of the currently mined coin(s), e.g. "BTC" or "BTC (1%) + BCH (99%)".
    var activeCoinsSummary: String {
        if isDualPoolMining {
            let c1 = primaryPoolCoin
            let c2 = secondaryPoolCoin
            if c1 == c2 {
                return "\(c1.symbol) (Dual \(dualPoolPrimaryPercent)%/\(dualPoolSecondaryPercent)%)"
            }
            return "\(c1.symbol) (\(dualPoolPrimaryPercent)%) + \(c2.symbol) (\(dualPoolSecondaryPercent)%)"
        }
        return activePoolCoin.symbol
    }

    var primaryPoolNetworkDiffFormatted: String? {
        if let nd = primaryPoolStatus?.networkDifficulty ?? (!isUsingFallbackStratum ? networkDifficulty : nil), nd > 0 {
            return Self.formatDifficultyNumber(nd)
        }
        return nil
    }

    var secondaryPoolNetworkDiffFormatted: String? {
        if let nd = secondaryPoolStatus?.networkDifficulty ?? (isUsingFallbackStratum ? networkDifficulty : nil), nd > 0 {
            return Self.formatDifficultyNumber(nd)
        }
        return nil
    }

    /// Active pool difficulty if reported via `stratum.pools` or `stratumSuggestedDifficulty`.
    var activePoolDifficulty: Double? {
        if isDualPoolMining {
            let d1 = primaryPoolStatus?.poolDifficulty
            let d2 = secondaryPoolStatus?.poolDifficulty
            return dualPoolSecondaryPercent >= dualPoolPrimaryPercent ? (d2 ?? d1) : (d1 ?? d2)
        }
        if let pools = stratumDetail?.pools {
            if let activePool = pools.first(where: { $0.active == true }), let diff = activePool.poolDifficulty, diff > 0 {
                return diff
            }
            if let firstDiff = pools.first?.poolDifficulty, firstDiff > 0 {
                return firstDiff
            }
        }
        if let reportedPoolDifficulty, reportedPoolDifficulty > 0 {
            return reportedPoolDifficulty
        }
        return stratumSuggestedDifficulty
    }
}

/// Payload sent via `PATCH /api/system` to update miner settings on Bitaxe / NerdQAxe++.
struct MinerSystemUpdatePayload: Codable, Sendable {
    var hostname: String?
    var frequency: Int?
    var coreVoltage: Int?
    var overclockEnabled: Int?
    var autofanspeed: Int?
    var fanspeed: Int?
    var manualFanSpeed: Int?
    var temptarget: Int?
    var pidTargetTemp: Int?
    var poolMode: Int?
    var poolBalance: Int?
    var stratumURL: String?
    var stratumPort: Int?
    var stratumUser: String?
    var stratumPassword: String?
    var fallbackStratumURL: String?
    var fallbackStratumPort: Int?
    var fallbackStratumUser: String?
    var fallbackStratumPassword: String?
    /// AxeOS 2.15+: slots to write (merged by `id`) and which slots act as primary / fallback.
    var pools: [AxeOSPool]?
    var primaryPoolIndex: Int?
    var secondaryPoolIndex: Int?

    init(
        hostname: String? = nil,
        frequency: Int? = nil,
        coreVoltage: Int? = nil,
        overclockEnabled: Int? = nil,
        autofanspeed: Int? = nil,
        fanspeed: Int? = nil,
        manualFanSpeed: Int? = nil,
        temptarget: Int? = nil,
        pidTargetTemp: Int? = nil,
        poolMode: Int? = nil,
        poolBalance: Int? = nil,
        stratumURL: String? = nil,
        stratumPort: Int? = nil,
        stratumUser: String? = nil,
        stratumPassword: String? = nil,
        fallbackStratumURL: String? = nil,
        fallbackStratumPort: Int? = nil,
        fallbackStratumUser: String? = nil,
        fallbackStratumPassword: String? = nil,
        pools: [AxeOSPool]? = nil,
        primaryPoolIndex: Int? = nil,
        secondaryPoolIndex: Int? = nil
    ) {
        self.hostname = hostname
        self.frequency = frequency
        self.coreVoltage = coreVoltage
        self.overclockEnabled = overclockEnabled
        self.autofanspeed = autofanspeed
        self.fanspeed = fanspeed
        self.manualFanSpeed = manualFanSpeed
        self.temptarget = temptarget
        self.pidTargetTemp = pidTargetTemp
        self.poolMode = poolMode
        self.poolBalance = poolBalance
        self.stratumURL = stratumURL
        self.stratumPort = stratumPort
        self.stratumUser = stratumUser
        self.stratumPassword = stratumPassword
        self.fallbackStratumURL = fallbackStratumURL
        self.fallbackStratumPort = fallbackStratumPort
        self.fallbackStratumUser = fallbackStratumUser
        self.fallbackStratumPassword = fallbackStratumPassword
        self.pools = pools
        self.primaryPoolIndex = primaryPoolIndex
        self.secondaryPoolIndex = secondaryPoolIndex
    }
}
