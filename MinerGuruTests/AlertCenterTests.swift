import Foundation
import Testing
@testable import MinerGuru

/// Records delivered alerts instead of showing them.
private actor RecordingNotifier: AlertNotifier {
    private(set) var delivered: [AlertEvent] = []
    func requestAuthorization() async -> Bool { true }
    func deliver(_ event: AlertEvent) async { delivered.append(event) }
}

@Suite("AlertCenter")
@MainActor
struct AlertCenterTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private let changeLog = ChangeLog()

    private func makeCenter(enabled: Bool = true) -> (AlertCenter, RecordingNotifier) {
        let notifier = RecordingNotifier()
        let center = AlertCenter(defaults: Fixtures.defaults(), notifier: notifier, guardsAppNap: false, changeLog: changeLog)
        center.isEnabled = enabled
        return (center, notifier)
    }

    private func miner(_ state: MinerConnectionState, id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!) -> MinerDevice {
        var config = PersistedMinerConfig(ipAddress: "192.168.1.50", customName: "Gamma")
        config.id = id
        return MinerDevice(config: config, connectionState: state)
    }

    /// Polls every `step` seconds with the given states and returns all alerts sent.
    private func poll(_ center: AlertCenter, _ states: [MinerConnectionState], step: TimeInterval = 60, from: TimeInterval = 0) async -> [AlertEvent] {
        var sent: [AlertEvent] = []
        for (i, state) in states.enumerated() {
            sent += await center.evaluate([miner(state)], now: start.addingTimeInterval(from + Double(i) * step))
        }
        return sent
    }

    private let off = MinerConnectionState.offline(reason: "Timeout")

    @Test func offlineAfterThreePollsAndRecovery() async {
        let (center, notifier) = makeCenter()
        let sent = await poll(center, [.online, off, off, off, .online])
        #expect(sent.map(\.isRecovery) == [false, true])
        #expect(await notifier.delivered.count == 2)
    }

    @Test func shortOutageFromRestartIsIgnored() async {
        let (center, _) = makeCenter()
        let sent = await poll(center, [.online, off, off, off, off, .online], step: 5)
        #expect(sent.isEmpty)
    }

    @Test func checkingStateDoesNotCount() async {
        let (center, _) = makeCenter()
        let sent = await poll(center, [off, .checking, .checking, off])
        #expect(sent.isEmpty)
    }

    @Test func flappingIsThrottled() async {
        let (center, _) = makeCenter()
        let first = await poll(center, [off, off, off, .online])
        let second = await poll(center, [off, off, off, .online], from: 300)
        #expect(first.count == 2)
        #expect(second.isEmpty)
    }

    @Test func mutedMinerAndDisabledKindAreSilent() async {
        let (center, notifier) = makeCenter()
        center.setMuted(true, minerID: miner(.online).id)
        #expect(await poll(center, [off, off, off]).isEmpty)

        let (center2, _) = makeCenter()
        center2.setKind(.offline, enabled: false)
        #expect(await poll(center2, [off, off, off]).isEmpty)
        #expect(await notifier.delivered.isEmpty)
    }

    @Test func disabledCenterSendsNothing() async {
        let (center, _) = makeCenter(enabled: false)
        #expect(await poll(center, [off, off, off, .online]).isEmpty)
    }

    @Test func settingsArePersisted() {
        let defaults = Fixtures.defaults()
        let id = UUID()
        let center = AlertCenter(defaults: defaults, notifier: RecordingNotifier(), guardsAppNap: false)
        center.isEnabled = true
        center.setMuted(true, minerID: id)
        center.setKind(.offline, enabled: false)

        let reloaded = AlertCenter(defaults: defaults, notifier: RecordingNotifier(), guardsAppNap: false)
        #expect(reloaded.isEnabled)
        #expect(reloaded.isMuted(id))
        #expect(!reloaded.isKindEnabled(.offline))
    }

    private func hot(_ flag: Bool) throws -> MinerDevice {
        var device = miner(.online)
        device.latestInfo = try Fixtures.info(["temp": 60, "overheat_mode": flag ? 1 : 0, "sharesAccepted": 5, "hashRate_1m": 900, "uptimeSeconds": 7200])
        return device
    }

    @Test func overheatAlarmsOnceAndGivesTheAllClear() async throws {
        let (center, _) = makeCenter()
        var sent: [AlertEvent] = []
        for (i, flag) in [true, true, false, false, false].enumerated() {
            sent += await center.evaluate([try hot(flag)], now: start.addingTimeInterval(Double(i) * 60))
        }
        #expect(sent.map(\.kind) == [.overheat, .overheat])
        #expect(sent.map(\.isRecovery) == [false, true])
    }

    @Test func overheatCanBeSwitchedOff() async throws {
        let (center, _) = makeCenter()
        center.setKind(.overheat, enabled: false)
        #expect(await center.evaluate([try hot(true)], now: start).isEmpty)
    }

    @Test func flatlineAlarmsAfterTenMinutesAndNewSharesClearIt() async throws {
        let (center, _) = makeCenter()
        var device = try hot(false)
        var sent: [AlertEvent] = []
        for minute in 0...11 {
            sent += await center.evaluate([device], now: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(sent.map(\.kind) == [.flatline])
        device.latestInfo = try Fixtures.info(["temp": 60, "sharesAccepted": 6, "hashRate_1m": 950, "uptimeSeconds": 7900])
        sent = await center.evaluate([device], now: start.addingTimeInterval(12 * 60))
        #expect(sent.map(\.isRecovery) == [true])
    }

    // MARK: - Watchdog and payout

    private func device(host: String, _ overrides: [String: Any], reachable: Bool = false) throws -> MinerDevice {
        var value = miner(.online)
        value.ipAddress = host
        value.latestInfo = try Fixtures.bitaxeInfo(overrides: ["uptimeSeconds": 7200].merging(overrides) { _, new in new })
        value.poolLatency = PoolLatencyMeasurement(primaryPoolDirectMs: reachable ? 20 : nil)
        return value
    }

    @Test func fallbackAlarmAndAllClear() async throws {
        let (center, _) = makeCenter()
        let onFallback = try device(host: "10.1.0.1", ["isUsingFallbackStratum": 1])
        _ = await center.evaluate([onFallback], now: start)
        let raised = await center.evaluate([onFallback], now: start.addingTimeInterval(600))
        #expect(raised.map(\.kind) == [.fallback])
        let cleared = await center.evaluate([try device(host: "10.1.0.1", [:])], now: start.addingTimeInterval(660))
        #expect(cleared.map(\.isRecovery) == [true])
    }

    @Test func watchdogRestartsOnceAnHour() async throws {
        let (center, _) = makeCenter()
        center.restartsToPrimary = true
        var restarted = 0
        center.restartMiner = { miner in
            restarted += 1
            ChangeLog.$source.withValue(.watchdog) {
                changeLog.recordWrite(host: miner.ipAddress, method: "POST", path: "/api/system/restart", body: nil, failure: nil)
            }
        }
        let stuck = try device(host: "10.1.0.2", ["isUsingFallbackStratum": 1], reachable: true)
        for minute in [0.0, 10, 15, 16, 30] {
            _ = await center.evaluate([stuck], now: Date().addingTimeInterval(minute * 60))
        }
        #expect(restarted == 1)
    }

    @Test func readOnlySaysOnceAnHourThatARestartWasLeftOut() async throws {
        let (center, _) = makeCenter()
        center.restartsToPrimary = true
        center.isReadOnly = { true }
        var restarted = 0
        center.restartMiner = { _ in restarted += 1 }
        let stuck = try device(host: "10.1.0.3", ["isUsingFallbackStratum": 1], reachable: true)
        let start = Date()
        var skipped: [AlertEvent] = []
        for minute in [0.0, 10, 15, 16, 30, 76] {
            let events = await center.evaluate([stuck], now: start.addingTimeInterval(minute * 60))
            skipped += events.filter { $0.title.contains("nicht neu gestartet") || $0.title.contains("not restarted") }
        }
        #expect(restarted == 0)
        #expect(skipped.count == 2)
    }

    @Test func flatlineWithRestartIsOneMessage() async throws {
        let (center, notifier) = makeCenter()
        center.restartsOnFlatline = true
        center.restartMiner = { _ in }
        let device = try hot(false)
        var sent: [AlertEvent] = []
        // The fake restart leaves no change log entry, so stop at the poll that found the flatline.
        for minute in 0...11 where sent.isEmpty {
            sent += await center.evaluate([device], now: start.addingTimeInterval(Double(minute) * 60))
        }
        #expect(sent.count == 1)
        #expect(sent.first?.kind == .flatline)
        #expect(await notifier.delivered.count == 1)
        #expect(await notifier.delivered.first?.title == sent.first?.title)
        #expect(sent.first?.standsAlone == true)
    }

    @Test func aPowerCutIsOneMessage() async {
        let (center, notifier) = makeCenter()
        let ids = (1...24).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000000%02d", $0))! }
        var sent: [AlertEvent] = []
        for step in 0...3 {
            sent += await center.evaluate(ids.map { miner(off, id: $0) }, now: start.addingTimeInterval(Double(step) * 60))
        }
        #expect(sent.count == 24)
        let delivered = await notifier.delivered
        #expect(delivered.count == 1)
        #expect(delivered.first?.title.contains("24") == true)
        #expect(delivered.first?.body.contains("Gamma") == true)
    }

    @Test func restartMessagesAreNotFolded() {
        let id = UUID()
        func event(_ alone: Bool, recovery: Bool = false) -> AlertEvent {
            AlertEvent(kind: .flatline, minerID: id, title: "t", body: "b", isRecovery: recovery, minerName: "A", standsAlone: alone)
        }
        #expect(AlertEvent.combine([event(false), event(true)]).count == 2)
        #expect(AlertEvent.combine([event(false), event(false, recovery: true)]).count == 2)
        #expect(AlertEvent.combine([event(false)]) == [event(false)])
    }

    @Test func confirmationUsesWordsNotFieldNames() {
        #expect(ChangeField(key: "overclockEnabled", before: "0", after: "1").summary == "\(ChangeLog.title(forKey: "overclockEnabled")): \(ChangeLog.shown("0", forKey: "overclockEnabled")) → \(ChangeLog.shown("1", forKey: "overclockEnabled"))")
        for key in ["overclockEnabled", "poolMode", "poolBalance", "primaryPoolIndex", "secondaryPoolIndex", "temptarget", "pidTargetTemp", "pools.1.stratumTLS", "pools.1.stratumProtocol"] {
            #expect(ChangeLog.title(forKey: key) != key)
            #expect(!ChangeLog.title(forKey: key).contains("stratum"))
        }
        #expect(ChangeLog.shown("1", forKey: "poolMode") == "Dual-Pool")
        #expect(ChangeLog.shown("0", forKey: "primaryPoolIndex") == "1")
        #expect(ChangeLog.shown("600", forKey: "frequency") == "600")
    }

    @Test func watchdogStaysOffByDefault() async throws {
        let (center, _) = makeCenter()
        var restarted = 0
        center.restartMiner = { _ in restarted += 1 }
        let stuck = try device(host: "10.1.0.3", ["isUsingFallbackStratum": 1], reachable: true)
        for minute in [0.0, 10, 15, 16] {
            _ = await center.evaluate([stuck], now: start.addingTimeInterval(minute * 60))
        }
        #expect(restarted == 0)
    }

    @Test func unexpectedRestartNamesTheReason() async throws {
        let (center, _) = makeCenter()
        _ = await center.evaluate([try device(host: "10.1.0.4", [:])], now: start)
        let sent = await center.evaluate([try device(host: "10.1.0.4", ["uptimeSeconds": 10, "resetReason": "Brownout"])], now: start.addingTimeInterval(60))
        #expect(sent.map(\.kind) == [.restart])
        #expect(sent.first?.body.contains("Brownout") == true)
    }

    private let walletA = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private let walletB = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"

    @Test func changedAddressAlarms() async throws {
        let (center, _) = makeCenter()
        _ = await center.evaluate([try device(host: "10.1.0.5", ["stratumUser": "\(walletA).a"])], now: start)
        let sent = await center.evaluate([try device(host: "10.1.0.5", ["stratumUser": "\(walletB).a"])], now: start.addingTimeInterval(60))
        #expect(sent.map(\.kind) == [.payout])
    }

    @Test func ownAddressChangeStaysQuiet() async throws {
        let (center, _) = makeCenter()
        let now = Date()
        _ = await center.evaluate([try device(host: "10.1.0.6", ["stratumUser": "\(walletA).a"])], now: now)
        changeLog.recordWrite(host: "10.1.0.6", method: "PATCH", path: "/api/system", body: nil, failure: nil, at: now)
        let sent = await center.evaluate([try device(host: "10.1.0.6", ["stratumUser": "\(walletB).a"])], now: now.addingTimeInterval(60))
        #expect(sent.isEmpty)
    }

    @Test func defaultAddressAlarmsOnce() async throws {
        let (center, _) = makeCenter()
        let stock = try device(host: "10.1.0.7", ["stratumUser": "replace-this-with-your-btc-address.bitaxe", "isUsingFallbackStratum": 0])
        let first = await center.evaluate([stock], now: start)
        let second = await center.evaluate([stock], now: start.addingTimeInterval(60))
        #expect(first.map(\.kind).contains(.payout))
        #expect(second.isEmpty)
    }

    @Test func foreignAddressFollowsTheExpectedOne() async throws {
        let (center, _) = makeCenter()
        let value = try device(host: "10.1.0.8", ["stratumUser": "\(walletB).a", "fallbackStratumUser": "\(walletA).a"])
        #expect(await center.evaluate([value], now: start).isEmpty)
        center.setExpectedAddress(walletA, for: .btc)
        let sent = await center.evaluate([value], now: start.addingTimeInterval(60))
        #expect(sent.map(\.kind) == [.payout])
    }

    @Test func blockWithoutTheMinerNeedsThreePolls() async throws {
        let (center, _) = makeCenter()
        let value = try device(host: "10.1.0.9", ["stratumUser": "\(walletA).a", "fallbackStratumUser": "\(walletA).a", "coinbasePayoutStatus": "not_found"])
        var counts: [Int] = []
        for poll in 0..<4 {
            counts.append(await center.evaluate([value], now: start.addingTimeInterval(Double(poll) * 60)).count)
        }
        #expect(counts == [0, 0, 1, 0])
    }
}
