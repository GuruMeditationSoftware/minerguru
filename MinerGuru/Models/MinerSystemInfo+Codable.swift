import Foundation

// Lenient decoding for AxeOS / NerdOS payloads: fields may be missing, renamed or sent as strings.
extension MinerSystemInfo {
    // MARK: - Flexible Decoding

    enum CodingKeys: String, CodingKey {
        case hashRate
        case hashRate_1m
        case hashRate_10m
        case hashRate_1h
        case hashRate_1d
        case expectedHashrate
        case temp
        case vrTemp
        case fanspeed
        case fanrpm
        case fanspeed2
        case fanrpm2
        case fan2rpm
        case autofanspeed
        case temptarget
        case pidTargetTemp
        case overheat_mode
        case power
        case voltage
        case current
        case currentA
        case coreVoltage
        case coreVoltageActual
        case frequency
        case actualFrequency
        case overclockEnabled
        case sharesAccepted
        case sharesRejected
        case sharesRejectedReasons
        case bestDiff
        case bestDifficulty
        case bestSessionDiff
        case bestSessionDifficulty
        case networkDifficulty
        case stratumURL
        case stratumPort
        case stratumUser
        case stratumSuggestedDifficulty
        case poolDifficulty
        case fallbackStratumURL
        case fallbackStratumPort
        case fallbackStratumUser
        case isUsingFallbackStratum
        case responseTime
        case lastpingrtt
        case stratum
        case pools
        case primaryPoolIndex
        case secondaryPoolIndex
        case stratumDecodeCoinbase
        case fallbackStratumDecodeCoinbase
        case stratumTLS
        case fallbackStratumTLS
        case blockHeight
        case scriptsig
        case blockSignals
        case coinbaseOutputs
        case coinbaseOthersCount
        case coinbaseOthersValueSatoshis
        case coinbaseValueTotalSatoshis
        case coinbaseValueUserSatoshis
        case coinbasePayoutStatus
        case deviceModel
        case ASICModel
        case asicModel
        case boardVersion
        case asicCount
        case smallCoreCount
        case hashrateMonitor
        case defaultFrequency
        case defaultCoreVoltage
        case hostname
        case overheat_temp
        case miningPaused
        case otp
        case macAddr
        case ssid
        case wifiStatus
        case wifiRSSI
        case rssi
        case version
        case axeOSVersion
        case idfVersion
        case errorPercentage
        case uptimeSeconds
        case resetReason, lastResetReason
        case uptime
        case freeHeap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.hashRate = Self.decodeDouble(c, forKey: .hashRate) ?? 0
        self.hashRate1m = Self.decodeDouble(c, forKey: .hashRate_1m)
        self.hashRate10m = Self.decodeDouble(c, forKey: .hashRate_10m)
        self.hashRate1h = Self.decodeDouble(c, forKey: .hashRate_1h)
        self.hashRate1d = Self.decodeDouble(c, forKey: .hashRate_1d)
        self.expectedHashrate = Self.decodeDouble(c, forKey: .expectedHashrate)

        self.temp = Self.decodeDouble(c, forKey: .temp) ?? 0
        let rawVrTemp = Self.decodeDouble(c, forKey: .vrTemp)
        self.vrTemp = (rawVrTemp ?? 0) > 0 ? rawVrTemp : nil

        self.fanSpeedPercent = Self.decodeDouble(c, forKey: .fanspeed) ?? 0
        self.fanRPM = Self.decodeInt(c, forKey: .fanrpm) ?? 0
        self.fan2SpeedPercent = Self.decodeDouble(c, forKey: .fanspeed2)
        let rawFan2RPM = Self.decodeInt(c, forKey: .fanrpm2) ?? Self.decodeInt(c, forKey: .fan2rpm)
        self.fan2RPM = (rawFan2RPM ?? 0) > 0 ? rawFan2RPM : nil

        let rawAutoFanInt = Self.decodeInt(c, forKey: .autofanspeed)
        self.autoFanModeRaw = rawAutoFanInt ?? (Self.decodeBool(c, forKey: .autofanspeed) == false ? 0 : 1)
        self.autoFanSpeed = self.autoFanModeRaw != 0

        self.targetTemp = Self.decodeDouble(c, forKey: .temptarget) ?? Self.decodeDouble(c, forKey: .pidTargetTemp)
        self.overheatMode = Self.decodeBool(c, forKey: .overheat_mode) ?? false
        self.overheatTemp = Self.decodeDouble(c, forKey: .overheat_temp)
        self.miningPaused = Self.decodeBool(c, forKey: .miningPaused) ?? false
        self.reportedPoolDifficulty = Self.decodeDouble(c, forKey: .poolDifficulty)

        self.power = Self.decodeDouble(c, forKey: .power) ?? 0

        // Normalize voltage: Bitaxe/NerdQAxe++ often reports mV (e.g. 5148 or 11796), normalize > 100 to Volts
        let rawVoltage = Self.decodeDouble(c, forKey: .voltage) ?? 0
        self.voltageVolts = rawVoltage > 100 ? (rawVoltage / 1000.0) : rawVoltage

        // Prefer `currentA` if present (NerdQAxe++), else normalize `current` from mA to A if > 100
        if let currentA = Self.decodeDouble(c, forKey: .currentA), currentA > 0 {
            self.currentAmps = currentA
        } else {
            let rawCurrent = Self.decodeDouble(c, forKey: .current) ?? 0
            self.currentAmps = rawCurrent > 100 ? (rawCurrent / 1000.0) : rawCurrent
        }

        self.coreVoltageTargetMV = Self.decodeInt(c, forKey: .coreVoltage) ?? 1200
        self.coreVoltageActualMV = Self.decodeInt(c, forKey: .coreVoltageActual) ?? self.coreVoltageTargetMV
        self.frequencyMHz = Self.decodeInt(c, forKey: .frequency)
            ?? Self.decodeInt(c, forKey: .actualFrequency)
            ?? 525
        self.overclockEnabled = Self.decodeBool(c, forKey: .overclockEnabled) ?? false

        self.sharesAccepted = Self.decodeInt(c, forKey: .sharesAccepted) ?? 0
        self.sharesRejected = Self.decodeInt(c, forKey: .sharesRejected) ?? 0
        self.errorPercentage = Self.decodeDouble(c, forKey: .errorPercentage)
        self.sharesRejectedReasons = (try? c.decode([ShareRejectionReason].self, forKey: .sharesRejectedReasons)) ?? []

        let bestDiffPair = Self.decodeDifficulty(c, primaryKey: .bestDiff, secondaryKey: .bestDifficulty)
        self.bestDiffFormatted = bestDiffPair.formatted
        self.bestDiffNumeric = bestDiffPair.numeric

        let sessionDiffPair = Self.decodeDifficulty(c, primaryKey: .bestSessionDiff, secondaryKey: .bestSessionDifficulty)
        self.bestSessionDiffFormatted = sessionDiffPair.formatted
        self.bestSessionDiffNumeric = sessionDiffPair.numeric

        self.networkDifficulty = Self.decodeDouble(c, forKey: .networkDifficulty)

        self.stratumURL = (try? c.decode(String.self, forKey: .stratumURL)) ?? ""
        self.stratumPort = Self.decodeInt(c, forKey: .stratumPort) ?? 3333
        self.stratumUser = (try? c.decode(String.self, forKey: .stratumUser)) ?? ""
        self.stratumSuggestedDifficulty = Self.decodeDouble(c, forKey: .stratumSuggestedDifficulty)
            ?? Self.decodeDouble(c, forKey: .poolDifficulty)

        self.fallbackStratumURL = (try? c.decode(String.self, forKey: .fallbackStratumURL)) ?? ""
        self.fallbackStratumPort = Self.decodeInt(c, forKey: .fallbackStratumPort) ?? 3333
        self.fallbackStratumUser = (try? c.decode(String.self, forKey: .fallbackStratumUser)) ?? ""

        let decodedStratumDetail = try? c.decode(MinerStratumDetail.self, forKey: .stratum)
        self.stratumDetail = decodedStratumDetail

        // AxeOS 2.15+: up to eight pool slots plus the indices of primary and fallback.
        self.axePools = (try? c.decode([LenientAxeOSPool].self, forKey: .pools))?.compactMap(\.pool)
        self.primaryPoolIndex = Self.decodeInt(c, forKey: .primaryPoolIndex)
        self.secondaryPoolIndex = Self.decodeInt(c, forKey: .secondaryPoolIndex)
        self.stratumDecodeCoinbase = Self.decodeBool(c, forKey: .stratumDecodeCoinbase)
        self.fallbackStratumDecodeCoinbase = Self.decodeBool(c, forKey: .fallbackStratumDecodeCoinbase)
        self.stratumTLS = Self.decodeBool(c, forKey: .stratumTLS)
        self.fallbackStratumTLS = Self.decodeBool(c, forKey: .fallbackStratumTLS)

        // AxeOS 2.13+: what the miner sees of the block template.
        self.blockHeight = Self.decodeInt(c, forKey: .blockHeight)
        self.blockScriptSig = try? c.decode(String.self, forKey: .scriptsig)
        self.blockSignals = try? c.decode([String].self, forKey: .blockSignals)
        self.coinbaseOutputs = try? c.decode([CoinbaseOutput].self, forKey: .coinbaseOutputs)
        self.coinbaseOthersCount = Self.decodeInt(c, forKey: .coinbaseOthersCount)
        self.coinbaseOthersValueSats = Self.decodeDouble(c, forKey: .coinbaseOthersValueSatoshis)
        self.coinbaseValueTotalSats = Self.decodeDouble(c, forKey: .coinbaseValueTotalSatoshis)
        self.coinbaseValueUserSats = Self.decodeDouble(c, forKey: .coinbaseValueUserSatoshis)
        self.coinbasePayoutStatus = try? c.decode(String.self, forKey: .coinbasePayoutStatus)

        let topLevelFallback = Self.decodeBool(c, forKey: .isUsingFallbackStratum)
        self.isUsingFallbackStratum = topLevelFallback ?? decodedStratumDetail?.usingFallback ?? false

        // Extract pool response time (ms) from top-level `responseTime`, `lastpingrtt`, or `stratum.pools[]`
        if let topRT = Self.decodeDouble(c, forKey: .responseTime), topRT > 0 {
            self.minerReportedPoolLatencyMs = topRT
        } else if let lastPing = Self.decodeDouble(c, forKey: .lastpingrtt), lastPing > 0 {
            self.minerReportedPoolLatencyMs = lastPing
        } else if let pools = decodedStratumDetail?.pools {
            if let activePool = pools.first(where: { $0.active == true }), let rt = activePool.effectiveLatencyMs {
                self.minerReportedPoolLatencyMs = rt
            } else if let connectedPool = pools.first(where: { $0.connected == true }), let rt = connectedPool.effectiveLatencyMs {
                self.minerReportedPoolLatencyMs = rt
            } else {
                self.minerReportedPoolLatencyMs = pools.first?.effectiveLatencyMs
            }
        } else {
            self.minerReportedPoolLatencyMs = nil
        }

        self.deviceModel = try? c.decode(String.self, forKey: .deviceModel)
        self.asicModel = (try? c.decode(String.self, forKey: .ASICModel))
            ?? (try? c.decode(String.self, forKey: .asicModel))
            ?? "BM1370"
        self.boardVersion = try? c.decode(String.self, forKey: .boardVersion)

        // AxeOS ≤ 2.9 and NerdOS report `asicCount`; AxeOS 2.12+ lists one entry per chip in
        // `hashrateMonitor.asics`; otherwise the board table knows the count.
        let monitorAsics = (try? c.decode(HashrateMonitor.self, forKey: .hashrateMonitor))?.asics?.count
        if let rawAsicCount = Self.decodeInt(c, forKey: .asicCount), rawAsicCount > 0 {
            self.asicCount = rawAsicCount
        } else if let monitorAsics, monitorAsics > 0 {
            self.asicCount = monitorAsics
        } else if let board = self.boardVersion, let family = BitaxeFamily.forBoard(board) {
            self.asicCount = family.asicCount
        } else if let model = self.deviceModel, let known = NerdOSModel.forDeviceModel(model) {
            self.asicCount = known.asicCount
        } else {
            self.asicCount = 1
        }
        self.defaultFrequencyMHz = Self.decodeInt(c, forKey: .defaultFrequency)
        self.defaultCoreVoltageMV = Self.decodeInt(c, forKey: .defaultCoreVoltage)

        self.smallCoreCount = Self.decodeInt(c, forKey: .smallCoreCount)
        self.hostname = (try? c.decode(String.self, forKey: .hostname)) ?? "miner"
        self.otp = Self.decodeBool(c, forKey: .otp) ?? false
        self.macAddress = try? c.decode(String.self, forKey: .macAddr)
        self.ssid = try? c.decode(String.self, forKey: .ssid)
        self.wifiStatus = try? c.decode(String.self, forKey: .wifiStatus)
        self.wifiRSSI = Self.decodeInt(c, forKey: .wifiRSSI) ?? Self.decodeInt(c, forKey: .rssi)
        self.firmwareVersion = (try? c.decode(String.self, forKey: .version)) ?? ""
        self.axeOSVersion = try? c.decode(String.self, forKey: .axeOSVersion)
        self.idfVersion = try? c.decode(String.self, forKey: .idfVersion)
        self.uptimeSeconds = Self.decodeInt(c, forKey: .uptimeSeconds) ?? Self.decodeInt(c, forKey: .uptime) ?? 0
        self.resetReason = (try? c.decode(String.self, forKey: .resetReason)) ?? (try? c.decode(String.self, forKey: .lastResetReason))
        self.freeHeap = Self.decodeInt(c, forKey: .freeHeap)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hashRate, forKey: .hashRate)
        try c.encodeIfPresent(hashRate1m, forKey: .hashRate_1m)
        try c.encodeIfPresent(hashRate10m, forKey: .hashRate_10m)
        try c.encodeIfPresent(hashRate1h, forKey: .hashRate_1h)
        try c.encodeIfPresent(hashRate1d, forKey: .hashRate_1d)
        try c.encodeIfPresent(expectedHashrate, forKey: .expectedHashrate)
        try c.encode(temp, forKey: .temp)
        try c.encodeIfPresent(vrTemp, forKey: .vrTemp)
        try c.encode(fanSpeedPercent, forKey: .fanspeed)
        try c.encode(fanRPM, forKey: .fanrpm)
        try c.encodeIfPresent(fan2SpeedPercent, forKey: .fanspeed2)
        try c.encodeIfPresent(fan2RPM, forKey: .fanrpm2)
        try c.encode(autoFanModeRaw, forKey: .autofanspeed)
        try c.encodeIfPresent(targetTemp, forKey: .temptarget)
        try c.encode(overheatMode ? 1 : 0, forKey: .overheat_mode)
        try c.encodeIfPresent(overheatTemp, forKey: .overheat_temp)
        try c.encode(miningPaused, forKey: .miningPaused)
        try c.encodeIfPresent(reportedPoolDifficulty, forKey: .poolDifficulty)
        try c.encode(power, forKey: .power)
        try c.encode(voltageVolts, forKey: .voltage)
        try c.encode(currentAmps, forKey: .current)
        try c.encode(coreVoltageTargetMV, forKey: .coreVoltage)
        try c.encode(coreVoltageActualMV, forKey: .coreVoltageActual)
        try c.encode(frequencyMHz, forKey: .frequency)
        try c.encode(overclockEnabled ? 1 : 0, forKey: .overclockEnabled)
        try c.encode(sharesAccepted, forKey: .sharesAccepted)
        try c.encode(sharesRejected, forKey: .sharesRejected)
        try c.encode(sharesRejectedReasons, forKey: .sharesRejectedReasons)
        try c.encode(bestDiffFormatted, forKey: .bestDiff)
        try c.encode(bestSessionDiffFormatted, forKey: .bestSessionDiff)
        try c.encode(stratumURL, forKey: .stratumURL)
        try c.encode(stratumPort, forKey: .stratumPort)
        try c.encode(stratumUser, forKey: .stratumUser)
        try c.encodeIfPresent(stratumSuggestedDifficulty, forKey: .stratumSuggestedDifficulty)
        try c.encode(fallbackStratumURL, forKey: .fallbackStratumURL)
        try c.encode(fallbackStratumPort, forKey: .fallbackStratumPort)
        try c.encode(fallbackStratumUser, forKey: .fallbackStratumUser)
        try c.encode(isUsingFallbackStratum ? 1 : 0, forKey: .isUsingFallbackStratum)
        try c.encodeIfPresent(minerReportedPoolLatencyMs, forKey: .responseTime)
        try c.encodeIfPresent(stratumDetail, forKey: .stratum)
        try c.encodeIfPresent(axePools, forKey: .pools)
        try c.encodeIfPresent(primaryPoolIndex, forKey: .primaryPoolIndex)
        try c.encodeIfPresent(secondaryPoolIndex, forKey: .secondaryPoolIndex)
        try c.encodeIfPresent(stratumDecodeCoinbase, forKey: .stratumDecodeCoinbase)
        try c.encodeIfPresent(fallbackStratumDecodeCoinbase, forKey: .fallbackStratumDecodeCoinbase)
        try c.encodeIfPresent(stratumTLS, forKey: .stratumTLS)
        try c.encodeIfPresent(fallbackStratumTLS, forKey: .fallbackStratumTLS)
        try c.encodeIfPresent(blockHeight, forKey: .blockHeight)
        try c.encodeIfPresent(blockScriptSig, forKey: .scriptsig)
        try c.encodeIfPresent(blockSignals, forKey: .blockSignals)
        try c.encodeIfPresent(coinbaseOutputs, forKey: .coinbaseOutputs)
        try c.encodeIfPresent(coinbaseOthersCount, forKey: .coinbaseOthersCount)
        try c.encodeIfPresent(coinbaseOthersValueSats, forKey: .coinbaseOthersValueSatoshis)
        try c.encodeIfPresent(coinbaseValueTotalSats, forKey: .coinbaseValueTotalSatoshis)
        try c.encodeIfPresent(coinbaseValueUserSats, forKey: .coinbaseValueUserSatoshis)
        try c.encodeIfPresent(coinbasePayoutStatus, forKey: .coinbasePayoutStatus)
        try c.encodeIfPresent(deviceModel, forKey: .deviceModel)
        try c.encode(asicModel, forKey: .ASICModel)
        try c.encodeIfPresent(boardVersion, forKey: .boardVersion)
        try c.encode(asicCount, forKey: .asicCount)
        try c.encodeIfPresent(smallCoreCount, forKey: .smallCoreCount)
        try c.encodeIfPresent(defaultFrequencyMHz, forKey: .defaultFrequency)
        try c.encodeIfPresent(defaultCoreVoltageMV, forKey: .defaultCoreVoltage)
        try c.encode(hostname, forKey: .hostname)
        try c.encode(otp, forKey: .otp)
        try c.encodeIfPresent(macAddress, forKey: .macAddr)
        try c.encodeIfPresent(ssid, forKey: .ssid)
        try c.encodeIfPresent(wifiStatus, forKey: .wifiStatus)
        try c.encodeIfPresent(wifiRSSI, forKey: .wifiRSSI)
        try c.encode(firmwareVersion, forKey: .version)
        try c.encodeIfPresent(axeOSVersion, forKey: .axeOSVersion)
        try c.encodeIfPresent(idfVersion, forKey: .idfVersion)
        try c.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try c.encodeIfPresent(freeHeap, forKey: .freeHeap)
    }

    // MARK: - Helpers

    private static func decodeDouble(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let i = try? c.decode(Int.self, forKey: key) { return Double(i) }
        if let s = try? c.decode(String.self, forKey: key), let d = Double(s.trimmingCharacters(in: .whitespaces)) {
            return d
        }
        return nil
    }

    private static func decodeInt(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Int? {
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let d = try? c.decode(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? c.decode(String.self, forKey: key), let i = Int(s.trimmingCharacters(in: .whitespaces)) {
            return i
        }
        return nil
    }

    private static func decodeBool(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool? {
        if let b = try? c.decode(Bool.self, forKey: key) { return b }
        if let i = try? c.decode(Int.self, forKey: key) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: key) {
            let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
            if ["1", "true", "yes", "on"].contains(lower) { return true }
            if ["0", "false", "no", "off"].contains(lower) { return false }
        }
        return nil
    }

    private static func decodeDifficulty(
        _ c: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        secondaryKey: CodingKeys
    ) -> (formatted: String, numeric: Double) {
        for key in [primaryKey, secondaryKey] {
            if let num = try? c.decode(Double.self, forKey: key) {
                return (formatDifficultyNumber(num), num)
            }
            if let intNum = try? c.decode(Int64.self, forKey: key) {
                let d = Double(intNum)
                return (formatDifficultyNumber(d), d)
            }
            if let str = try? c.decode(String.self, forKey: key), !str.isEmpty {
                let numeric = parseDifficultyString(str)
                return (str.trimmingCharacters(in: .whitespaces), numeric)
            }
        }
        return ("0", 0)
    }

    static func formatDifficultyNumber(_ value: Double) -> String {
        guard value > 0 else { return "0" }
        let units: [(Double, String)] = [
            (1_000_000_000_000_000, "P"),
            (1_000_000_000_000, "T"),
            (1_000_000_000, "G"),
            (1_000_000, "M"),
            (1_000, "K")
        ]
        for (threshold, suffix) in units {
            if value >= threshold {
                let scaled = value / threshold
                return String(format: scaled >= 100 ? "%.0f%@" : "%.2f%@", scaled, suffix)
            }
        }
        return String(format: "%.0f", value)
    }

    static func parseDifficultyString(_ raw: String) -> Double {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return 0 }

        let multipliers: [Character: Double] = [
            "K": 1_000,
            "M": 1_000_000,
            "G": 1_000_000_000,
            "T": 1_000_000_000_000,
            "P": 1_000_000_000_000_000
        ]

        if let lastChar = trimmed.last, let mult = multipliers[lastChar] {
            let numberPart = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
            if let val = Double(numberPart) {
                return val * mult
            }
        }
        return Double(trimmed) ?? 0
    }
}

/// `hashrateMonitor` of AxeOS 2.12+; only the number of chips is used.
private struct HashrateMonitor: Decodable {
    struct Asic: Decodable {}
    let asics: [Asic]?
}
