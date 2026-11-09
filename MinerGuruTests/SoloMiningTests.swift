import Foundation
import Testing
@testable import MinerGuru

@Suite("Solo-mining probability")
struct SoloMiningTests {
    private static let twoPow32 = 4_294_967_296.0

    /// Network difficulty that yields `lambda` expected blocks per day at `hashrateGHs`.
    private func difficulty(forLambdaPerDay lambda: Double, hashrateGHs: Double) -> Double {
        hashrateGHs * 1e9 * 86_400 / (lambda * Self.twoPow32)
    }

    private func summary(hashrateGHs: Double, difficulty: Double, coin: MinedCoin = .btc) -> FleetCoinMiningSummary {
        FleetCoinMiningSummary(coin: coin, totalHashrateGHs: hashrateGHs, networkDifficulty: difficulty,
                               contributingMinersText: "", isLiveDifficulty: true)
    }

    @Test func timeframeDurations() {
        #expect(SoloChanceTimeframe.perHour.durationSeconds(for: .btc) == 3_600)
        #expect(SoloChanceTimeframe.perDay.durationSeconds(for: .btc) == 86_400)
        #expect(SoloChanceTimeframe.perBlock.durationSeconds(for: .btc) == 600)
        #expect(SoloChanceTimeframe.perBlock.durationSeconds(for: .dgb) == 75)
        #expect(SoloChanceTimeframe.perDay.blockCount(for: .btc) == 144)
        #expect(SoloChanceTimeframe.perDay.blockCount(for: .fb) == 2_880)
    }

    @Test func lambdaMatchesFormula() {
        // 1 TH/s against BTC-like difficulty 144 T: λ = H·T / (D·2^32)
        let s = summary(hashrateGHs: 1_000, difficulty: 144e12)
        let expected = 1e12 * 86_400 / (144e12 * Self.twoPow32)
        #expect(abs(s.expectedBlocksLambda(for: .perDay) - expected) < 1e-18)
        #expect(abs(s.probability(for: .perDay) - expected) / expected < 1e-6)
    }

    @Test func probabilityIsPoissonAtLeastOneBlock() {
        let s = summary(hashrateGHs: 1_000, difficulty: difficulty(forLambdaPerDay: 2, hashrateGHs: 1_000))
        #expect(abs(s.probability(for: .perDay) - (1 - exp(-2))) < 1e-9)
        #expect(s.probability(for: .perWeek) > s.probability(for: .perDay))
        #expect(s.probability(for: .perYear) <= 1)
    }

    @Test func zeroHashrateOrDifficulty() {
        for s in [summary(hashrateGHs: 0, difficulty: 1e12), summary(hashrateGHs: 100, difficulty: 0)] {
            #expect(s.probability(for: .perDay) == 0)
            #expect(s.formattedProbabilityPercent(for: .perDay) == "0 %")
            #expect(s.formattedOddsRatio(for: .perDay) == "—")
            #expect(s.expectedTimePerBlockFormatted == "—")
        }
    }

    @Test func formattedProbabilityAndOdds() {
        let s = summary(hashrateGHs: 1_000, difficulty: difficulty(forLambdaPerDay: 0.001, hashrateGHs: 1_000))
        // p = 1 − e^−0.001 ≈ 0.09995 %, 1/p ≈ 1000.5 → rounded to 1.001
        #expect(s.formattedProbabilityPercent(for: .perDay) == "0,100 %")
        #expect(s.formattedOddsRatio(for: .perDay) == "1 : 1.001")
    }

    @Test func oddsUseMillionsAndBillions() {
        let millions = summary(hashrateGHs: 1_000, difficulty: difficulty(forLambdaPerDay: 1.0 / 156_200_000, hashrateGHs: 1_000))
        #expect(millions.formattedOddsRatio(for: .perDay) == "1 : 156,2 Mio.")
        let billions = summary(hashrateGHs: 1_000, difficulty: difficulty(forLambdaPerDay: 1.0 / 2_500_000_000, hashrateGHs: 1_000))
        #expect(billions.formattedOddsRatio(for: .perDay) == "1 : 2,50 Mrd.")
    }

    @Test(arguments: [
        (2.0, "~12,0 Std."),
        (0.1, "~10,0 Tage"),
        (1.0 / 730.5, "~2,0 Jahre"),
        (1.0 / (365.25 * 19_598), "~19.598 J."),
    ])
    func expectedTimePerBlock(lambdaPerDay: Double, expected: String) {
        let s = summary(hashrateGHs: 1_000, difficulty: difficulty(forLambdaPerDay: lambdaPerDay, hashrateGHs: 1_000))
        #expect(s.expectedTimePerBlockFormatted == expected)
    }
}

@Suite("Fleet aggregation per coin")
struct FleetAggregationTests {
    @Test func singleAndDualPoolMinersAreSplitByCoin() throws {
        let bitaxe = Fixtures.device(ip: "192.168.1.28", info: try Fixtures.bitaxeInfo(hashRate: 1_000))
        let nerd = Fixtures.device(ip: "192.168.1.33", info: try Fixtures.dualPoolInfo(hashRate: 6_000, btcNetworkDifficulty: 141e12))

        let summaries = FleetCoinMiningSummary.summaries(for: [bitaxe, nerd])
        #expect(summaries.map(\.coin) == [.btc, .bch])

        let btc = try #require(summaries.first { $0.coin == .btc })
        #expect(abs(btc.totalHashrateGHs - 1_060) < 0.001)
        #expect(btc.contributingMinersText == "bitaxe + nerdqaxe (1%)")
        #expect(btc.isLiveDifficulty)
        #expect(btc.networkDifficulty == 141e12)

        let bch = try #require(summaries.first { $0.coin == .bch })
        #expect(abs(bch.totalHashrateGHs - 5_940) < 0.001)
        #expect(!bch.isLiveDifficulty)
        #expect(bch.networkDifficulty == MinedCoin.bch.fallbackNetworkDifficulty)
    }

    @Test func bitcoinIsListedFirstOthersByHashrate() throws {
        let dgb = Fixtures.device(ip: "10.0.0.1", info: try Fixtures.bitaxeInfo(hashRate: 5_000, overrides: ["stratumURL": "dgb.pool.example"]))
        let bch = Fixtures.device(ip: "10.0.0.2", info: try Fixtures.bitaxeInfo(hashRate: 2_000, overrides: ["stratumURL": "bch.solopool.eu"]))
        let btc = Fixtures.device(ip: "10.0.0.3", info: try Fixtures.bitaxeInfo(hashRate: 500))
        #expect(FleetCoinMiningSummary.summaries(for: [dgb, bch, btc]).map(\.coin) == [.btc, .dgb, .bch])
    }

    @Test func minersWithoutTelemetryAreIgnored() {
        #expect(FleetCoinMiningSummary.summaries(for: [Fixtures.device(info: nil)]).isEmpty)
    }
}
