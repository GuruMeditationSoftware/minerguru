import Foundation
import Testing
@testable import MinerGuru

@Suite("Best difficulty since reboot (session)")
struct SessionBestDiffTests {
    @Test func singlePoolSessionBelongsToActivePool() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["bestDiff": 4_398_121_003, "bestSessionDiff": 38_723_607])
        #expect(info.sessionBestDiff == 38_723_607)
        #expect(info.sessionBestDiffText == "38.72M")
        #expect(info.bestDiffFormatted == "4.40G") // all-time stays separate
        #expect(info.primaryPoolSessionBestDiff == 38_723_607)
        #expect(info.secondaryPoolSessionBestDiff == nil)
    }

    @Test func fallbackPoolGetsSessionWhenActive() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["bestSessionDiff": 1_000_000, "isUsingFallbackStratum": 1])
        #expect(info.primaryPoolSessionBestDiff == nil)
        #expect(info.secondaryPoolSessionBestDiff == 1_000_000)
    }

    @Test func nothingFoundYetAfterReboot() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["bestSessionDiff": 0])
        #expect(info.sessionBestDiff == nil)
        #expect(info.sessionBestDiffText == "—")
        #expect(info.primaryPoolSessionBestDiff == nil)
        #expect(MinerSystemInfo.formatSessionBest(nil) == "—")
    }

    @Test func dualPoolUsesPerPoolValues() throws {
        let info = try Fixtures.info([
            "bestDiff": 20_494_162_828,
            "bestSessionDiff": 790_846_423,
            "stratumURL": "eusolo.ckpool.org",
            "fallbackStratumURL": "bch.solopool.eu",
            "stratum": [
                "poolMode": 1, "activePoolMode": 1, "poolBalance": 1,
                "pools": [
                    ["connected": true, "bestDiff": 1_030_328],
                    ["connected": true, "bestDiff": 790_846_423],
                ],
            ],
        ])
        #expect(info.primaryPoolSessionBestDiff == 1_030_328)
        #expect(info.secondaryPoolSessionBestDiff == 790_846_423)
        #expect(info.sessionBestDiffText == "791M")
        #expect(MinerSystemInfo.formatSessionBest(info.primaryPoolSessionBestDiff) == "1.03M")
    }

    @Test func dualPoolWithoutPerPoolValuesShowsNothingPerPool() throws {
        let info = try Fixtures.dualPoolInfo()
        #expect(info.primaryPoolSessionBestDiff == nil)
        #expect(info.secondaryPoolSessionBestDiff == nil)
    }

    @Test @MainActor func fleetSessionBestPicksHighestOnlineMiner() throws {
        let defaults = Fixtures.defaults()
        let store = MinerStore(defaults: defaults, startBackgroundWork: false)
        #expect(store.bestSessionMiner == nil)

        store.addMiner(ipAddress: "192.168.1.10", initialInfo: try Fixtures.bitaxeInfo(overrides: ["hostname": "a", "bestSessionDiff": 5_000_000]))
        store.addMiner(ipAddress: "192.168.1.11", initialInfo: try Fixtures.bitaxeInfo(overrides: ["hostname": "b", "bestSessionDiff": 90_000_000]))
        store.addMiner(ipAddress: "192.168.1.12", initialInfo: try Fixtures.bitaxeInfo(overrides: ["hostname": "c", "bestSessionDiff": 900_000_000]))
        store.miners[2].connectionState = .offline(reason: "weg")

        let best = try #require(store.bestSessionMiner)
        #expect(best.miner.displayName == "b")
        #expect(best.difficulty == 90_000_000)
    }
}
