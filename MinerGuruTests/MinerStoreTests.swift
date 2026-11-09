import Foundation
import Testing
@testable import MinerGuru

@Suite("MinerStore")
@MainActor
struct MinerStoreTests {
    private func makeStore(defaults: UserDefaults = Fixtures.defaults()) -> MinerStore {
        MinerStore(defaults: defaults, startBackgroundWork: false)
    }

    // MARK: Settings

    @Test func soloChanceTimeframeIsPersisted() {
        let defaults = Fixtures.defaults()
        #expect(makeStore(defaults: defaults).soloChanceTimeframe == .perDay)
        makeStore(defaults: defaults).soloChanceTimeframe = .perWeek
        #expect(makeStore(defaults: defaults).soloChanceTimeframe == .perWeek)
    }

    @Test func defaultSettings() {
        let store = makeStore()
        #expect(store.miners.isEmpty)
        #expect(store.pollingIntervalSeconds == 5)
        #expect(store.tempWarningThresholdC == 68)
        #expect(store.autoScanOnEmptyLaunch)
        #expect(store.selection == .overview)
    }

    @Test func settingsArePersisted() {
        let defaults = Fixtures.defaults()
        let store = makeStore(defaults: defaults)
        store.tempWarningThresholdC = 72
        store.autoScanOnEmptyLaunch = false

        let reloaded = makeStore(defaults: defaults)
        #expect(reloaded.tempWarningThresholdC == 72)
        #expect(!reloaded.autoScanOnEmptyLaunch)
    }

    // MARK: Miner list

    @Test func addMinerNormalizesSortsAndPersists() {
        let defaults = Fixtures.defaults()
        let store = makeStore(defaults: defaults)
        store.addMiner(ipAddress: " http://192.168.1.33/ ", customName: "  NerdQAxe  ")
        store.addMiner(ipAddress: "192.168.1.9")

        #expect(store.miners.map(\.ipAddress) == ["192.168.1.9", "192.168.1.33"])
        #expect(store.miners.last?.customName == "NerdQAxe")

        let reloaded = makeStore(defaults: defaults)
        #expect(reloaded.miners.map(\.ipAddress) == ["192.168.1.9", "192.168.1.33"])
        #expect(reloaded.miners.allSatisfy { $0.connectionState == .checking })
    }

    @Test func addingExistingMinerUpdatesNameInsteadOfDuplicating() {
        let store = makeStore()
        store.addMiner(ipAddress: "192.168.1.28")
        let again = store.addMiner(ipAddress: "192.168.1.28", customName: "Wohnzimmer")
        #expect(store.miners.count == 1)
        #expect(again?.customName == "Wohnzimmer")
        #expect(store.isIPAlreadyAdded("HTTP://192.168.1.28/"))
        #expect(!store.isIPAlreadyAdded("192.168.1.29"))
    }

    @Test func emptyAddressIsRejected() {
        let store = makeStore()
        #expect(store.addMiner(ipAddress: "   ") == nil)
        #expect(store.miners.isEmpty)
    }

    @Test func addMinerWithScanResultStartsOnline() throws {
        let store = makeStore()
        let info = try Fixtures.bitaxeInfo()
        let device = try #require(store.addMiner(ipAddress: "192.168.1.28", initialInfo: info))
        #expect(device.connectionState == .online)
        #expect(device.history.count == 1)
        #expect(device.cachedHostname == "bitaxe")
    }

    @Test func removeMinerResetsSelection() {
        let store = makeStore()
        let device = store.addMiner(ipAddress: "192.168.1.28")!
        store.selection = .miner(device.id)
        store.removeMiner(id: device.id)
        #expect(store.miners.isEmpty)
        #expect(store.selection == .overview)
    }

    @Test func renameMiner() {
        let store = makeStore()
        let device = store.addMiner(ipAddress: "192.168.1.28")!
        store.updateMinerCustomName(id: device.id, customName: "  Keller ")
        #expect(store.miners.first?.customName == "Keller")
        store.updateMinerCustomName(id: device.id, customName: "   ")
        #expect(store.miners.first?.customName == nil)
    }

    @Test func corruptPersistedDataIsIgnored() {
        let defaults = Fixtures.defaults()
        defaults.set(Data("garbage".utf8), forKey: "MinerGuru.SavedMiners.v1")
        #expect(makeStore(defaults: defaults).miners.isEmpty)
    }

    // MARK: Applying fetch results

    @Test func successfulFetchUpdatesDeviceAndHistory() throws {
        var device = Fixtures.device(state: .checking)
        let info = try Fixtures.bitaxeInfo(hashRate: 1_100)
        let result = MinerStore.SingleMinerFetchResult(
            id: device.id, info: info, rawJSON: "{}", latency: PoolLatencyMeasurement(minerReportedMs: 25, primaryPoolDirectMs: 30), errorDescription: nil
        )

        let persistedChanged = MinerStore.apply(result, to: &device)
        #expect(persistedChanged) // hostname and model learned for the first time
        #expect(device.connectionState == .online)
        #expect(device.latestInfo?.hashRate == 1_100)
        #expect(device.history.count == 1)
        #expect(device.history.first?.poolLatencyMs == 25) // miner-reported latency wins
        #expect(device.lastSeenAt != nil)

        #expect(!MinerStore.apply(result, to: &device)) // nothing new to persist
        #expect(device.history.count == 2)
    }

    @Test func historyIsCapped() throws {
        var device = Fixtures.device()
        let result = MinerStore.SingleMinerFetchResult(
            id: device.id, info: try Fixtures.bitaxeInfo(), rawJSON: nil, latency: PoolLatencyMeasurement(), errorDescription: nil
        )
        for _ in 0..<(MinerStore.maxHistorySamples + 5) {
            _ = MinerStore.apply(result, to: &device)
        }
        #expect(device.history.count == MinerStore.maxHistorySamples)
    }

    @Test func failedFetchMarksOfflineAndKeepsLastTelemetry() throws {
        var device = Fixtures.device(info: try Fixtures.bitaxeInfo())
        let result = MinerStore.SingleMinerFetchResult(id: device.id, info: nil, rawJSON: nil, latency: nil, errorDescription: "Timeout")
        #expect(!MinerStore.apply(result, to: &device))
        #expect(device.connectionState == .offline(reason: "Timeout"))
        #expect(device.latestInfo != nil)
    }

    // MARK: Fleet aggregation

    @Test func fleetTotalsOnlyCountOnlineMiners() throws {
        let store = makeStore()
        let first = store.addMiner(ipAddress: "192.168.1.10", initialInfo: try Fixtures.bitaxeInfo(hashRate: 1_000, power: 20, overrides: ["bestDiff": 1_000_000]))!
        store.addMiner(ipAddress: "192.168.1.11", initialInfo: try Fixtures.bitaxeInfo(hashRate: 1_500, power: 25, overrides: ["bestDiff": 4_400_000_000]))
        store.addMiner(ipAddress: "192.168.1.12", initialInfo: try Fixtures.bitaxeInfo(hashRate: 9_999))
        store.miners[2].connectionState = .offline(reason: "weg")

        #expect(store.onlineMiners.count == 2)
        #expect(store.totalHashrateGHs == 2_500)
        #expect(store.totalPowerWatts == 45)
        #expect(abs(store.fleetEfficiencyJPerTH - 18) < 0.001)
        #expect(store.totalSharesAccepted == 1_800)
        #expect(store.totalSharesRejected == 6)
        #expect(store.highestBestDiffFormatted == "4.40G")
        #expect(store.averagePoolLatencyMs == 25)
        #expect(store.menuBarSummaryText == "2.50 TH/s")
        #expect(store.activeFleetCoinSummaries.map(\.coin) == [.btc])
        _ = first
    }

    @Test func fleetHistoryRecordsOnlineHashrateAndStaysCapped() throws {
        let store = makeStore()
        store.addMiner(ipAddress: "192.168.1.10", initialInfo: try Fixtures.bitaxeInfo(hashRate: 1_000))
        store.addMiner(ipAddress: "192.168.1.11", initialInfo: try Fixtures.bitaxeInfo(hashRate: 500))
        store.miners[1].connectionState = .offline(reason: "weg")

        store.recordFleetSample()
        #expect(store.fleetHistory.last?.hashRateGHs == 1_000)
        #expect(store.fleetHistory.last?.onlineCount == 1)

        for _ in 0..<(MinerStore.maxHistorySamples + 5) {
            store.recordFleetSample()
        }
        #expect(store.fleetHistory.count == MinerStore.maxHistorySamples)
    }

    @Test func menuBarTextForEmptyAndOfflineFleet() {
        let store = makeStore()
        #expect(store.menuBarSummaryText == "MinerGuru")
        store.addMiner(ipAddress: "192.168.1.10")
        #expect(store.menuBarSummaryText == "Offline")
        #expect(store.highestBestDiffFormatted == "—")
        #expect(store.averagePoolLatencyMs == nil)
        #expect(store.fleetEfficiencyJPerTH == 0)
    }

    @Test func bannerShowsMessage() {
        let store = makeStore()
        store.showBanner("Hallo", isError: true)
        #expect(store.statusBannerMessage == "Hallo")
        #expect(store.statusBannerIsError)
    }
}
