import Foundation

/// User-selectable timeframe for Solo-Mining block discovery probability.
enum SoloChanceTimeframe: String, CaseIterable, Identifiable, Codable, Sendable {
    case perBlock = "Pro Block"
    case perHour  = "Pro Stunde"
    case perDay   = "Pro Tag"
    case perWeek  = "Pro Woche"
    case perMonth = "Pro Monat"
    case perYear  = "Pro Jahr"

    /// Persisted in UserDefaults, so the German raw values stay unchanged.
    var id: String { rawValue }

    var title: String {
        switch self {
        case .perBlock: return String(localized: "Pro Block")
        case .perHour:  return String(localized: "Pro Stunde")
        case .perDay:   return String(localized: "Pro Tag")
        case .perWeek:  return String(localized: "Pro Woche")
        case .perMonth: return String(localized: "Pro Monat")
        case .perYear:  return String(localized: "Pro Jahr")
        }
    }

    /// Effective duration in seconds for a given coin.
    func durationSeconds(for coin: MinedCoin) -> Double {
        switch self {
        case .perBlock:
            return coin.targetBlockTimeSeconds
        case .perHour:
            return 3_600
        case .perDay:
            return 86_400
        case .perWeek:
            return 86_400 * 7
        case .perMonth:
            return 86_400 * 30.4375
        case .perYear:
            return 86_400 * 365.25
        }
    }

    /// Number of network blocks mined during this timeframe for a given coin.
    func blockCount(for coin: MinedCoin) -> Double {
        durationSeconds(for: coin) / max(1, coin.targetBlockTimeSeconds)
    }
}

extension MinedCoin {
    /// Target block interval in seconds on the coin's blockchain.
    var targetBlockTimeSeconds: Double {
        switch self {
        case .btc, .bch, .xec, .bsv, .ppc, .nmc, .unknown:
            return 600 // 10 minutes (144 blocks/day)
        case .dgb:
            return 75  // DigiByte SHA-256 algorithm target interval
        case .fb:
            return 30  // Fractal Bitcoin 30s block time
        }
    }

    /// Current block subsidy (reward per block excluding fees).
    var blockSubsidyCoins: Double {
        switch self {
        case .btc: return 3.125
        case .bch: return 3.125
        case .bsv: return 3.125
        case .dgb: return 275.0
        case .xec: return 1_812_500.0
        case .fb:  return 25.0
        case .ppc: return 35.0
        case .nmc: return 3.125
        case .unknown: return 3.125
        }
    }

    /// Fallback network difficulty used only if the Stratum pool has not reported `networkDifficulty` yet.
    var fallbackNetworkDifficulty: Double {
        switch self {
        case .btc, .unknown:
            return 144_080_230_085_156.0
        case .bch:
            return 750_830_101_440.0
        case .bsv:
            return 85_000_000_000.0
        case .dgb:
            return 120_000_000.0
        case .xec:
            return 250_000_000_000.0
        case .fb:
            return 5_000_000_000_000.0
        case .ppc, .nmc:
            return 10_000_000_000_000.0
        }
    }
}

/// Aggregated fleet hashrate, difficulty, and solo-mining probability for a specific `MinedCoin`.
struct FleetCoinMiningSummary: Identifiable, Sendable, Equatable {
    var id: String { coin.rawValue }
    let coin: MinedCoin
    /// Total fleet hashrate in GH/s directed at this coin (accounting for Dual-Pool percentage splits).
    let totalHashrateGHs: Double
    /// Live network difficulty for this coin's blockchain.
    let networkDifficulty: Double
    /// Human-readable list of miners/shares contributing to this coin.
    let contributingMinersText: String
    /// True if `networkDifficulty` came directly from a live Stratum pool report.
    let isLiveDifficulty: Bool

    init(
        coin: MinedCoin,
        totalHashrateGHs: Double,
        networkDifficulty: Double,
        contributingMinersText: String,
        isLiveDifficulty: Bool
    ) {
        self.coin = coin
        self.totalHashrateGHs = totalHashrateGHs
        self.networkDifficulty = networkDifficulty
        self.contributingMinersText = contributingMinersText
        self.isLiveDifficulty = isLiveDifficulty
    }

    /// Expected number of blocks found (Poisson rate $\lambda$) within the given timeframe.
    /// Formula: $\lambda = (H \times T) / (D \times 2^{32})$
    func expectedBlocksLambda(for timeframe: SoloChanceTimeframe) -> Double {
        guard totalHashrateGHs > 0, networkDifficulty > 0 else { return 0 }
        let hashesPerSecond = totalHashrateGHs * 1_000_000_000.0
        let seconds = timeframe.durationSeconds(for: coin)
        let hashesPerBlock = networkDifficulty * 4_294_967_296.0
        return (hashesPerSecond * seconds) / hashesPerBlock
    }

    /// Exact probability ($0.0 \dots 1.0$) of finding at least 1 block in the given timeframe: $P = 1 - e^{-\lambda}$.
    func probability(for timeframe: SoloChanceTimeframe) -> Double {
        let lambda = expectedBlocksLambda(for: timeframe)
        guard lambda > 0 else { return 0 }
        if lambda < 1e-7 {
            return lambda
        }
        return 1.0 - exp(-lambda)
    }

    /// Formatted percentage string (e.g. `"0,016 %"` or `"5,65 %"` or `"0,000018 %"`).
    func formattedProbabilityPercent(for timeframe: SoloChanceTimeframe) -> String {
        let pct = probability(for: timeframe) * 100.0
        guard pct > 0 else { return "0 %" }
        let digits: Int
        switch pct {
        case 10...:     digits = 1
        case 1...:      digits = 2
        case 0.01...:   digits = 3
        case 0.0001...: digits = 5
        default:        digits = 7
        }
        return DisplayFormat.percent(pct, fractionDigits: digits)
    }

    /// Formatted "1 : N" odds string (e.g. `"1 : 6.283"`, `"1 : 18"`, `"1 : 156,2 Mio."`).
    func formattedOddsRatio(for timeframe: SoloChanceTimeframe) -> String {
        let p = probability(for: timeframe)
        guard p > 0 else { return "—" }
        let oneIn = max(1.0, (1.0 / p).rounded())

        if oneIn >= 1_000_000_000 {
            return String(localized: "1 : \(DisplayFormat.decimal(oneIn / 1_000_000_000.0, fractionDigits: 2)) Mrd.")
        } else if oneIn >= 10_000_000 {
            return String(localized: "1 : \(DisplayFormat.decimal(oneIn / 1_000_000.0, fractionDigits: 1)) Mio.")
        }
        return "1 : \(DisplayFormat.decimal(oneIn, fractionDigits: 0))"
    }

    /// Expected average time to find a block at current hashrate.
    var expectedTimePerBlockFormatted: String {
        let lambdaPerDay = expectedBlocksLambda(for: .perDay)
        guard lambdaPerDay > 0 else { return "—" }
        let days = 1.0 / lambdaPerDay
        if days < 1.0 {
            return String(localized: "~\(DisplayFormat.decimal(days * 24.0, fractionDigits: 1)) Std.")
        } else if days < 60.0 {
            return String(localized: "~\(DisplayFormat.decimal(days, fractionDigits: 1)) Tage")
        }
        let years = days / 365.25
        if years >= 1_000 {
            return String(localized: "~\(DisplayFormat.decimal(years.rounded(), fractionDigits: 0)) J.")
        }
        return String(localized: "~\(DisplayFormat.decimal(years, fractionDigits: 1)) Jahre")
    }

}

extension FleetCoinMiningSummary {
    /// Aggregates hashrate, live network difficulty and contributing miners per coin.
    /// Dual-pool miners split their hashrate by the configured percentages. Bitcoin is listed first,
    /// the remaining coins by descending hashrate.
    static func summaries(for onlineMiners: [MinerDevice]) -> [FleetCoinMiningSummary] {
        struct CoinBucket {
            var hashrateGHs: Double = 0
            var liveDifficulty: Double?
            var miners: [String] = []
        }

        var buckets: [MinedCoin: CoinBucket] = [:]

        func add(_ coin: MinedCoin, hashrate: Double, difficulty: Double?, label: String) {
            var bucket = buckets[coin] ?? CoinBucket()
            bucket.hashrateGHs += hashrate
            if let difficulty, difficulty > 0 {
                bucket.liveDifficulty = difficulty
            }
            bucket.miners.append(label)
            buckets[coin] = bucket
        }

        for miner in onlineMiners {
            guard let info = miner.latestInfo else { continue }
            if info.isDualPoolMining {
                let p1 = info.dualPoolPrimaryPercent
                let p2 = info.dualPoolSecondaryPercent
                add(info.primaryPoolCoin,
                    hashrate: info.hashRate * Double(p1) / 100.0,
                    difficulty: info.primaryPoolStatus?.networkDifficulty,
                    label: "\(miner.displayName) (\(p1)%)")
                add(info.secondaryPoolCoin,
                    hashrate: info.hashRate * Double(p2) / 100.0,
                    difficulty: info.secondaryPoolStatus?.networkDifficulty,
                    label: "\(miner.displayName) (\(p2)%)")
            } else {
                let activeStatus = info.isUsingFallbackStratum ? info.secondaryPoolStatus : info.primaryPoolStatus
                add(info.activePoolCoin,
                    hashrate: info.hashRate,
                    difficulty: activeStatus?.networkDifficulty ?? info.networkDifficulty,
                    label: miner.displayName)
            }
        }

        return buckets.map { coin, bucket in
            FleetCoinMiningSummary(
                coin: coin,
                totalHashrateGHs: bucket.hashrateGHs,
                networkDifficulty: bucket.liveDifficulty ?? coin.fallbackNetworkDifficulty,
                contributingMinersText: bucket.miners.joined(separator: " + "),
                isLiveDifficulty: bucket.liveDifficulty != nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.coin == .btc && rhs.coin != .btc { return true }
            if rhs.coin == .btc && lhs.coin != .btc { return false }
            return lhs.totalHashrateGHs > rhs.totalHashrateGHs
        }
    }
}
