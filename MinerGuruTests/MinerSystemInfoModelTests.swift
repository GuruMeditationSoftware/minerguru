import Foundation
import Testing
@testable import MinerGuru

@Suite("MinerSystemInfo derived values")
struct MinerSystemInfoModelTests {
    @Test func lenientDecodingAcceptsStringsAndMissingFields() throws {
        let info = try Fixtures.info([
            "hashRate": "512.5",
            "temp": 50,
            "isUsingFallbackStratum": "1",
            "fallbackStratumURL": "public-pool.io",
            "fallbackStratumUser": "bc1qwallet.rig",
        ])
        #expect(info.hashRate == 512.5)
        #expect(info.temp == 50)
        #expect(info.isUsingFallbackStratum)
        #expect(info.hostname == "miner")
        #expect(info.stratumURL.isEmpty)
        #expect(info.activePoolEndpoint == "public-pool.io:3333") // missing port defaults to 3333
        #expect(info.activeWorkerName == "rig")
    }

    @Test func singlePoolEndpointsAndCoin() throws {
        let info = try Fixtures.bitaxeInfo()
        #expect(!info.isDualPoolMining)
        #expect(info.primaryPoolEndpoint == "eusolo.ckpool.org:3333")
        #expect(info.activePoolEndpoint == "eusolo.ckpool.org:3333")
        #expect(info.activePoolHost == "eusolo.ckpool.org")
        #expect(info.activePoolCoin == .btc)
        #expect(info.activeWorkerName == "bitaxe")
    }

    @Test func fallbackPoolIsActiveWhenUsingFallback() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["isUsingFallbackStratum": 1])
        #expect(info.activePoolEndpoint == "public-pool.io:21496")
        #expect(info.activePoolHost == "public-pool.io")
    }

    @Test func unconfiguredPool() throws {
        let info = try Fixtures.info(["hashRate": 1])
        #expect(info.primaryPoolEndpoint == "Not configured")
        #expect(info.fallbackPoolEndpoint == "Not configured")
    }

    @Test func dualPoolSplitAndCoins() throws {
        let info = try Fixtures.dualPoolInfo()
        #expect(info.isDualPoolMining)
        #expect(info.dualPoolPrimaryPercent == 1)
        #expect(info.dualPoolSecondaryPercent == 99)
        #expect(info.primaryPoolCoin == .btc)
        #expect(info.secondaryPoolCoin == .bch)
        #expect(info.activePoolCoin == .bch) // dominant pool
        #expect(info.activePoolEndpoint == "eusolo.ckpool.org (1%) + bch.solopool.eu (99%)")
        #expect(info.activeCoinsSummary == "BTC (1%) + BCH (99%)")
        #expect(info.activePoolUser == "bc1qexample.nerdqaxe") // same worker on both pools
    }

    @Test func dualPoolPercentIsClamped() throws {
        let info = try Fixtures.info([
            "stratum": ["poolMode": 1, "poolBalance": 0, "pools": []],
        ])
        #expect(info.dualPoolPrimaryPercent == 1)
        #expect(info.dualPoolSecondaryPercent == 99)
    }

    @Test func efficiencyAndRejectionRate() throws {
        let info = try Fixtures.bitaxeInfo(hashRate: 1200, power: 18, overrides: ["sharesAccepted": 99, "sharesRejected": 1])
        #expect(abs(info.efficiencyJPerTH - 15.0) < 0.001)
        #expect(abs(info.shareRejectionRatePercent - 1.0) < 0.001)

        let idle = try Fixtures.bitaxeInfo(hashRate: 0, power: 5, overrides: ["sharesAccepted": 0, "sharesRejected": 0])
        #expect(idle.efficiencyJPerTH == 0)
        #expect(idle.shareRejectionRatePercent == 0)
    }

    @Test func workerExtraction() throws {
        let info = try Fixtures.bitaxeInfo()
        #expect(info.extractWorker(from: "wallet.worker1") == "worker1")
        #expect(info.extractWorker(from: "wallet.a.b") == "b")
        #expect(info.extractWorker(from: "wallet.") == nil)
        #expect(info.extractWorker(from: "wallet") == nil)
    }

    @Test func hardwareTitle() throws {
        #expect(try Fixtures.bitaxeInfo().detectedHardwareTitle == "Bitaxe Gamma 601")
        #expect(try Fixtures.dualPoolInfo().detectedHardwareTitle == "NerdQAxe++")
    }

    @Test func encodeDecodeRoundTripKeepsKeyValues() throws {
        let original = try Fixtures.dualPoolInfo()
        let decoded = try JSONDecoder().decode(MinerSystemInfo.self, from: JSONEncoder().encode(original))
        #expect(decoded.hashRate == original.hashRate)
        #expect(decoded.hostname == original.hostname)
        #expect(decoded.stratumURL == original.stratumURL)
        #expect(decoded.fallbackStratumUser == original.fallbackStratumUser)
        #expect(decoded.detectedHardwareTitle == original.detectedHardwareTitle)
    }
}
