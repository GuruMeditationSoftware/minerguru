import Foundation

enum MinerConnectionState: Equatable, Sendable {
    case unknown
    case checking
    case online
    case offline(reason: String)

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }
}

struct MinerTelemetrySample: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var timestamp: Date
    var hashRateGHs: Double
    var asicTempC: Double
    var vrTempC: Double?
    var powerWatts: Double
    var poolLatencyMs: Double?
    var fanPercent: Double

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        hashRateGHs: Double,
        asicTempC: Double,
        vrTempC: Double? = nil,
        powerWatts: Double,
        poolLatencyMs: Double? = nil,
        fanPercent: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hashRateGHs = hashRateGHs
        self.asicTempC = asicTempC
        self.vrTempC = vrTempC
        self.powerWatts = powerWatts
        self.poolLatencyMs = poolLatencyMs
        self.fanPercent = fanPercent
    }
}

struct PoolLatencyMeasurement: Codable, Sendable, Equatable {
    /// Latency reported by the miner firmware itself (`responseTime` in `/api/system/info`).
    var minerReportedMs: Double?
    /// Direct TCP handshake latency in ms measured to the primary pool (`stratumURL:stratumPort`).
    var primaryPoolDirectMs: Double?
    /// Direct TCP handshake latency in ms measured to the fallback pool (`fallbackStratumURL:fallbackStratumPort`).
    var fallbackPoolDirectMs: Double?
    var measuredAt: Date

    init(
        minerReportedMs: Double? = nil,
        primaryPoolDirectMs: Double? = nil,
        fallbackPoolDirectMs: Double? = nil,
        measuredAt: Date = Date()
    ) {
        self.minerReportedMs = minerReportedMs
        self.primaryPoolDirectMs = primaryPoolDirectMs
        self.fallbackPoolDirectMs = fallbackPoolDirectMs
        self.measuredAt = measuredAt
    }

    /// Best available latency for the currently active pool.
    func effectiveLatencyMs(usingFallback: Bool) -> Double? {
        if let minerReportedMs, minerReportedMs > 0 {
            return minerReportedMs
        }
        if usingFallback {
            return fallbackPoolDirectMs ?? primaryPoolDirectMs
        }
        return primaryPoolDirectMs
    }
}

/// Hardware tuning preset for Frequency (MHz) and Core Voltage (mV).
struct MinerClockPreset: Identifiable, Sendable, Equatable {
    var id: String { "\(name)-\(frequencyMHz)-\(coreVoltageMV)" }
    let name: String
    let subtitle: String
    let frequencyMHz: Int
    let coreVoltageMV: Int

    init(name: String, subtitle: String, frequencyMHz: Int, coreVoltageMV: Int) {
        self.name = name
        self.subtitle = subtitle
        self.frequencyMHz = frequencyMHz
        self.coreVoltageMV = coreVoltageMV
    }
}

/// Persisted configuration entry for a miner in the user's network.
struct PersistedMinerConfig: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var ipAddress: String
    var customName: String?
    var addedAt: Date
    var cachedHostname: String?
    var cachedHardwareModel: String?

    init(
        id: UUID = UUID(),
        ipAddress: String,
        customName: String? = nil,
        addedAt: Date = Date(),
        cachedHostname: String? = nil,
        cachedHardwareModel: String? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.customName = customName
        self.addedAt = addedAt
        self.cachedHostname = cachedHostname
        self.cachedHardwareModel = cachedHardwareModel
    }
}

/// Live runtime state and telemetry history of a miner in MinerGuru.
struct MinerDevice: Identifiable, Sendable, Equatable {
    var id: UUID
    var ipAddress: String
    var customName: String?
    var addedAt: Date
    var lastSeenAt: Date?
    var cachedHostname: String?
    var cachedHardwareModel: String?

    var connectionState: MinerConnectionState
    var latestInfo: MinerSystemInfo?
    var rawJSON: String?
    var poolLatency: PoolLatencyMeasurement?
    var history: [MinerTelemetrySample]

    init(
        config: PersistedMinerConfig,
        connectionState: MinerConnectionState = .unknown,
        latestInfo: MinerSystemInfo? = nil,
        rawJSON: String? = nil,
        poolLatency: PoolLatencyMeasurement? = nil,
        history: [MinerTelemetrySample] = []
    ) {
        self.id = config.id
        self.ipAddress = config.ipAddress
        self.customName = config.customName
        self.addedAt = config.addedAt
        self.cachedHostname = config.cachedHostname
        self.cachedHardwareModel = config.cachedHardwareModel
        self.connectionState = connectionState
        self.latestInfo = latestInfo
        self.rawJSON = rawJSON
        self.poolLatency = poolLatency
        self.history = history
    }

    var persistedConfig: PersistedMinerConfig {
        PersistedMinerConfig(
            id: id,
            ipAddress: ipAddress,
            customName: customName,
            addedAt: addedAt,
            cachedHostname: latestInfo?.hostname ?? cachedHostname,
            cachedHardwareModel: latestInfo?.detectedHardwareTitle ?? cachedHardwareModel
        )
    }

    var displayName: String {
        if let customName = customName?.trimmingCharacters(in: .whitespacesAndNewlines), !customName.isEmpty {
            return customName
        }
        if let hostname = latestInfo?.hostname, !hostname.isEmpty {
            return hostname
        }
        if let cachedHostname, !cachedHostname.isEmpty {
            return cachedHostname
        }
        return ipAddress
    }

    var hardwareTitle: String {
        latestInfo?.detectedHardwareTitle ?? cachedHardwareModel ?? String(localized: "Unknown Miner")
    }

    var isNerdOS: Bool { latestInfo?.firmware == .nerdOS }
    var requiresOtp: Bool { latestInfo?.otp == true }

    var isMultiChip: Bool { (latestInfo?.asicCount ?? 1) > 1 }

    var primaryPoolEffectiveLatencyMs: Double? {
        if let p1 = latestInfo?.primaryPoolMinerLatencyMs, p1 > 0 {
            return p1
        }
        if let direct = poolLatency?.primaryPoolDirectMs, direct > 0 {
            return direct
        }
        if let info = latestInfo, !info.isUsingFallbackStratum, let r = info.minerReportedPoolLatencyMs, r > 0 {
            return r
        }
        return nil
    }

    var secondaryPoolEffectiveLatencyMs: Double? {
        if let p2 = latestInfo?.secondaryPoolMinerLatencyMs, p2 > 0 {
            return p2
        }
        if let direct = poolLatency?.fallbackPoolDirectMs, direct > 0 {
            return direct
        }
        if let info = latestInfo, info.isUsingFallbackStratum, let r = info.minerReportedPoolLatencyMs, r > 0 {
            return r
        }
        return nil
    }

    var activePoolLatencyMs: Double? {
        if let info = latestInfo, info.isDualPoolMining {
            let p1 = primaryPoolEffectiveLatencyMs
            let p2 = secondaryPoolEffectiveLatencyMs
            if let p1, let p2 {
                let w1 = Double(info.dualPoolPrimaryPercent) / 100.0
                let w2 = Double(info.dualPoolSecondaryPercent) / 100.0
                return p1 * w1 + p2 * w2
            }
            return p2 ?? p1 ?? info.minerReportedPoolLatencyMs
        }
        if let latency = poolLatency?.effectiveLatencyMs(usingFallback: latestInfo?.isUsingFallbackStratum ?? false) {
            return latency
        }
        return latestInfo?.minerReportedPoolLatencyMs
    }

    /// Eco / standard / boost for this miner's chip, on the clock steps its firmware offers.
    /// NerdOS reports its own factory clock, which becomes the standard profile.
    var recommendedPresets: [MinerClockPreset] {
        guard let info = latestInfo, let tuning = info.asicTuning else { return [] }
        let nerdOS = info.firmware == .nerdOS
        return tuning.presets(
            standardFrequencyMHz: nerdOS ? info.defaultFrequencyMHz : nil,
            standardVoltageMV: nerdOS ? info.defaultCoreVoltageMV : nil
        ).map { preset in
            let hashrate = info.expectedHashrateGHs(frequencyMHz: preset.frequencyMHz)
            return MinerClockPreset(
                name: preset.name,
                subtitle: hashrate.map { "≈ " + MinerFormatting.formatHashrate($0) } ?? "",
                frequencyMHz: preset.frequencyMHz,
                coreVoltageMV: preset.voltageMV
            )
        }
    }

    /// Range of the frequency stepper: the firmware steps of the chip, widened to the current and factory value.
    var frequencyRange: ClosedRange<Int> {
        settingRange(options: latestInfo?.asicTuning?.frequencyOptions,
                     values: [latestInfo?.frequencyMHz, latestInfo?.defaultFrequencyMHz],
                     fallback: MinerSettingsForm.frequencyRange)
    }

    /// Range of the core voltage stepper, analogous to `frequencyRange`.
    var coreVoltageRange: ClosedRange<Int> {
        settingRange(options: latestInfo?.asicTuning?.voltageOptions,
                     values: [latestInfo?.coreVoltageTargetMV, latestInfo?.defaultCoreVoltageMV],
                     fallback: MinerSettingsForm.coreVoltageRange)
    }

    private func settingRange(options: [Int]?, values: [Int?], fallback: ClosedRange<Int>) -> ClosedRange<Int> {
        let known = (options ?? []) + values.compactMap { $0 }.filter { $0 > 0 }
        guard let low = known.min(), let high = known.max(), options?.isEmpty == false else { return fallback }
        return low...high
    }
}
