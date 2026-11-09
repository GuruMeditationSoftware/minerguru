import Foundation

/// One ASIC result with its difficulty, parsed from the miner's live log.
///
/// - AxeOS (Bitaxe):  `asic_result: ID: …, Nonce F0AE9D21 diff 1284.3 of 874.`
/// - NerdOS (NerdQAxe): `asic_result: (Sec) Job ID: 78 … diff 141114.6/3075/791M`
///
/// Results at or above the pool difficulty are submitted to the pool as shares.
struct ShareSample: Identifiable, Equatable, Sendable {
    enum Pool: String, Sendable {
        case primary = "Pool 1"
        case secondary = "Pool 2"
    }

    let id = UUID()
    let date: Date
    let difficulty: Double
    /// Pool difficulty at that time (`nil` if the firmware did not report it).
    let poolDifficulty: Double?
    /// Pool the result belongs to (NerdOS dual-pool logs only).
    let pool: Pool?

    /// Whether the result reached the pool difficulty, i.e. was sent to the pool as a share.
    var isSubmitted: Bool {
        guard let poolDifficulty else { return true }
        return difficulty >= poolDifficulty
    }

    static func == (lhs: ShareSample, rhs: ShareSample) -> Bool {
        lhs.date == rhs.date && lhs.difficulty == rhs.difficulty
            && lhs.poolDifficulty == rhs.poolDifficulty && lhs.pool == rhs.pool
    }

    // `diff 1284.3 of 874` (AxeOS) or `diff 141114.6/3075` (NerdOS)
    private static let diffPattern = try! NSRegularExpression(pattern: #"\bdiff\s+([0-9]+(?:\.[0-9]+)?)(?:\s+of\s+|/)([0-9]+(?:\.[0-9]+)?)"#)
    private static let poolPattern = try! NSRegularExpression(pattern: #"\((Pri|Sec)\)"#)

    /// Parses an `asic_result` log entry; returns `nil` for every other line.
    static func parse(_ entry: MinerLogEntry) -> ShareSample? {
        guard entry.componentTag?.lowercased() == "asic_result" else { return nil }
        return parse(message: entry.message, date: entry.receivedAt)
    }

    static func parse(message: String, date: Date) -> ShareSample? {
        let range = NSRange(message.startIndex..., in: message)
        guard let match = diffPattern.firstMatch(in: message, range: range),
              let diffRange = Range(match.range(at: 1), in: message),
              let difficulty = Double(message[diffRange]) else { return nil }

        let poolDifficulty = Range(match.range(at: 2), in: message).flatMap { Double(message[$0]) }

        var pool: Pool?
        if let poolMatch = poolPattern.firstMatch(in: message, range: range),
           let tagRange = Range(poolMatch.range(at: 1), in: message) {
            pool = message[tagRange] == "Pri" ? .primary : .secondary
        }
        return ShareSample(date: date, difficulty: difficulty, poolDifficulty: poolDifficulty, pool: pool)
    }

    /// Line series key per sample: one line per pool, broken wherever two results of the same pool are
    /// more than `maxGap` apart (e.g. between two sample windows), so no line bridges missing data.
    static func lineSeries(for samples: [ShareSample], maxGap: TimeInterval) -> [String] {
        var segmentPerPool: [String: Int] = [:]
        var lastDatePerPool: [String: Date] = [:]
        return samples.map { sample in
            let pool = sample.pool?.rawValue ?? "Share"
            if let last = lastDatePerPool[pool], sample.date.timeIntervalSince(last) > maxGap {
                segmentPerPool[pool, default: 0] += 1
            }
            lastDatePerPool[pool] = sample.date
            return "\(pool)#\(segmentPerPool[pool, default: 0])"
        }
    }
}
