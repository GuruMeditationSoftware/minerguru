import Foundation

/// Best share difficulty since the miner's last reboot ("session"), overall and per pool.
///
/// AxeOS (Bitaxe) only reports `bestSessionDiff` for the whole miner; it belongs to the pool
/// that is currently active. NerdOS additionally reports `stratum.pools[n].bestDiff` per pool.
extension MinerSystemInfo {
    /// Session best of the whole miner, `nil` if nothing was found yet.
    var sessionBestDiff: Double? {
        bestSessionDiffNumeric > 0 ? bestSessionDiffNumeric : nil
    }

    /// Session best on pool 1 (primary).
    var primaryPoolSessionBestDiff: Double? {
        if let perPool = primaryPoolStatus?.bestDiff, perPool > 0 { return perPool }
        return !isDualPoolMining && !isUsingFallbackStratum ? sessionBestDiff : nil
    }

    /// Session best on pool 2 (secondary / fallback).
    var secondaryPoolSessionBestDiff: Double? {
        if let perPool = secondaryPoolStatus?.bestDiff, perPool > 0 { return perPool }
        return !isDualPoolMining && isUsingFallbackStratum ? sessionBestDiff : nil
    }

    /// `"38.7M"` or `"—"`.
    var sessionBestDiffText: String {
        sessionBestDiff.map(Self.formatDifficultyNumber) ?? "—"
    }

    static func formatSessionBest(_ value: Double?) -> String {
        value.map(formatDifficultyNumber) ?? "—"
    }
}

extension MinerStore {
    /// Miner with the highest session best difficulty among the online miners.
    var bestSessionMiner: (miner: MinerDevice, difficulty: Double)? {
        onlineMiners
            .compactMap { miner in miner.latestInfo?.sessionBestDiff.map { (miner, $0) } }
            .max { $0.1 < $1.1 }
    }
}
