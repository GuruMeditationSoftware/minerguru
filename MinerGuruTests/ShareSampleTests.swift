import Foundation
import Testing
@testable import MinerGuru

@Suite("Share difficulty from the live log")
struct ShareSampleTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func entry(_ line: String) throws -> MinerLogEntry {
        try #require(MinerLogEntry.parse(rawLine: line, receivedAt: now))
    }

    @Test func parsesAxeOSResult() throws {
        let sample = try #require(ShareSample.parse(try entry(
            "\u{1B}[0;32mI (300518763) asic_result: ID: 6a68c4730003bbd9, ASIC nr: 0, Core: 95/5, ver: 200EA000 Nonce 8995C7BE diff 1284.3 of 874.\u{1B}[0m"
        )))
        #expect(sample.difficulty == 1284.3)
        #expect(sample.poolDifficulty == 874)
        #expect(sample.pool == nil)
        #expect(sample.isSubmitted)
        #expect(sample.date == now)
    }

    @Test func resultBelowPoolDifficultyIsNotSubmitted() throws {
        let sample = try #require(ShareSample.parse(try entry(
            "I (1) asic_result: ID: 6a68, ASIC nr: 0, Core: 6/8, ver: 20070000 Nonce 255C580D diff 566.6 of 874."
        )))
        #expect(!sample.isSubmitted)
    }

    @Test(arguments: [
        ("I (300305461) asic_result: (Sec) Job ID: 78 AsicNr: 1 Ver: 233DC000 Nonce 81C58102; Extranonce2 00000000000978f5 diff 499255.1/3075/791M",
         499_255.1, 3_075.0, ShareSample.Pool.secondary),
        ("I (1) asic_result: (Pri) Job ID: 10 AsicNr: 3 Ver: 25C46000 Nonce 4042818B; Extranonce2 00f6 diff 2074.8/1000/1.03M",
         2_074.8, 1_000.0, .primary),
    ])
    func parsesNerdOSResultWithPool(line: String, difficulty: Double, poolDifficulty: Double, pool: ShareSample.Pool) throws {
        let sample = try #require(ShareSample.parse(try entry(line)))
        #expect(sample.difficulty == difficulty)
        #expect(sample.poolDifficulty == poolDifficulty)
        #expect(sample.pool == pool)
    }

    @Test(arguments: [
        "I (300518530) stratum_v1_task: message result accepted",
        "I (300518763) asic_result: Processing time: 2.3 ms",
        "I (1) stratum_api: Set difficulty 874 of 874",
        "W (2) power: VR temp high",
    ])
    func ignoresOtherLines(line: String) throws {
        #expect(ShareSample.parse(try entry(line)) == nil)
    }

    @Test func parsesWithoutPoolDifficulty() {
        let sample = ShareSample.parse(message: "Nonce 1 diff 42", date: now)
        #expect(sample == nil) // pool difficulty is part of both known formats
    }

    @Test @MainActor func trackerCollectsOnlySharesAndCapsHistory() throws {
        let tracker = ShareDifficultyTracker()
        tracker.ingest([
            try entry("I (1) asic_result: ID: a, Nonce 1 diff 1284.3 of 874."),
            try entry("I (2) stratum_v1_task: message result accepted"),
        ])
        #expect(tracker.samples.count == 1)

        let line = try entry("I (3) asic_result: ID: a, Nonce 2 diff 400.0 of 874.")
        tracker.ingest(Array(repeating: line, count: ShareDifficultyTracker.maxSamples + 10))
        #expect(tracker.samples.count == ShareDifficultyTracker.maxSamples)
        #expect(tracker.samples.last?.difficulty == 400)
    }

    @Test func lineSeriesBreaksAtGapsAndSeparatesPools() {
        func sample(_ seconds: Double, _ pool: ShareSample.Pool?) -> ShareSample {
            ShareSample(date: now.addingTimeInterval(seconds), difficulty: 1_000, poolDifficulty: 874, pool: pool)
        }
        let single = [sample(0, nil), sample(5, nil), sample(70, nil), sample(72, nil)]
        #expect(ShareSample.lineSeries(for: single, maxGap: 20) == ["Share#0", "Share#0", "Share#1", "Share#1"])

        // Gaps are measured per pool: a slow pool 1 does not break pool 2.
        let dual = [sample(0, .secondary), sample(1, .primary), sample(10, .secondary), sample(30, .primary), sample(31, .secondary)]
        #expect(ShareSample.lineSeries(for: dual, maxGap: 20) == ["Pool 2#0", "Pool 1#0", "Pool 2#0", "Pool 1#1", "Pool 2#1"])

        #expect(ShareSample.lineSeries(for: [], maxGap: 20).isEmpty)
    }

    @Test @MainActor func trackerKeepsSamplesInTimeOrder() throws {
        let tracker = ShareDifficultyTracker()
        let late = try #require(MinerLogEntry.parse(rawLine: "I (1) asic_result: ID: a, Nonce 1 diff 900.0 of 874.", receivedAt: now.addingTimeInterval(10)))
        let early = try #require(MinerLogEntry.parse(rawLine: "I (2) asic_result: ID: a, Nonce 2 diff 500.0 of 874.", receivedAt: now))
        tracker.ingest([late])
        tracker.ingest([early])
        #expect(tracker.samples.map(\.difficulty) == [500, 900])
    }
}
