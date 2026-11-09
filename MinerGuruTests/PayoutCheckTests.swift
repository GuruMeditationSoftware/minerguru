import Foundation
import Testing
@testable import MinerGuru

@Suite("Payout watch")
struct PayoutCheckTests {
    private let mine = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
    private let other = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
    private let cash = "qruvqq2x9vyd9gykre058r4lda4gulpres33nr9aml"

    @Test func addressIsThePartBeforeTheFirstDot() {
        #expect(PayoutCheck.address(fromUser: " bc1qabc.worker.x ") == "bc1qabc")
        #expect(PayoutCheck.address(fromUser: "account") == "account")
    }

    @Test func recognisesDefaults() {
        #expect(PayoutCheck.verdict(user: "replace-this-with-your-btc-address.bitaxe", expected: nil) == .factoryDefault)
        #expect(PayoutCheck.verdict(user: "bc1q7n70rumyv6lvu8avpml0c3uggvssfu52egum3q.nerdqaxe", expected: nil) == .factoryDefault)
        #expect(PayoutCheck.verdict(user: "BC1Q7N70RUMYV6LVU8AVPML0C3UGGVSSFU52EGUM3Q.x", expected: mine) == .factoryDefault)
    }

    @Test func comparesWithTheExpectedAddress() {
        #expect(PayoutCheck.verdict(user: "\(mine).w", expected: mine) == .expected)
        #expect(PayoutCheck.verdict(user: "\(other).w", expected: mine) == .foreign)
        #expect(PayoutCheck.verdict(user: "\(other).w", expected: nil) == .valid)
        #expect(PayoutCheck.verdict(user: "\(other).w", expected: "bc1qar0") == .valid)
        #expect(PayoutCheck.verdict(user: "\(cash).w", expected: "bitcoincash:\(cash)") == .expected)
    }

    @Test func invalidIsAnAccountOrATypo() {
        #expect(PayoutCheck.verdict(user: "wicked_miner.1", expected: mine) == .account)
        #expect(PayoutCheck.verdict(user: "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdx.w", expected: nil) == .account)
        #expect(PayoutCheck.verdict(user: "", expected: mine) == .empty)
    }

    @Test func allSlotsAreChecked() throws {
        let info = try Fixtures.bitaxeInfo(overrides: [
            "stratumUser": "\(mine).a", "fallbackStratumUser": "\(other).a",
        ])
        let slots = PayoutCheck.slots(of: info, expected: ["BTC": mine])
        #expect(slots.map(\.key) == ["primary", "fallback"])
        #expect(slots.map(\.verdict) == [.expected, .foreign])
    }

    @Test func axeOSSlotsCountToo() throws {
        let info = try Fixtures.bitaxeInfo(overrides: ["pools": [
            ["id": 0, "stratumURL": "solo.ckpool.org", "stratumPort": 3333, "stratumUser": "\(mine).a"],
            ["id": 3, "stratumURL": "public-pool.io", "stratumPort": 21496, "stratumUser": "replace-this-with-your-btc-address.a"],
        ]])
        let slots = PayoutCheck.slots(of: info, expected: [:])
        #expect(slots.map(\.key) == ["pool0", "pool3"])
        #expect(slots[1].verdict == .factoryDefault)
    }

    @Test func workerStaysWhenTheAddressChanges() {
        #expect(PayoutCheck.user("old.worker", withAddress: "new") == "new.worker")
        #expect(PayoutCheck.user("old", withAddress: "new") == "new")
    }

    @Test func missingAddressCountsOnlyOnBitcoinSoloPools() throws {
        let solo = try Fixtures.bitaxeInfo(overrides: ["coinbasePayoutStatus": "not_found", "stratumUser": "\(mine).a"])
        #expect(PayoutCheck.blockSkipsMiner(solo))
        let shared = try Fixtures.bitaxeInfo(overrides: ["coinbasePayoutStatus": "not_found", "stratumURL": "pool.braiins.com", "stratumUser": "\(mine).a"])
        #expect(!PayoutCheck.blockSkipsMiner(shared))
        let verified = try Fixtures.bitaxeInfo(overrides: ["coinbasePayoutStatus": "verified", "stratumUser": "\(mine).a"])
        #expect(!PayoutCheck.blockSkipsMiner(verified))
    }
}

@Suite("Change log", .serialized)
struct ChangeLogTests {
    @Test func unchangedCertificateIsNoChange() throws {
        let current = try #require(ChangeLog.flatten(rawJSON: #"{"pools":[{"id":0,"stratumCert":"PEM"}]}"#))
        #expect(ChangeLog.changes(body: Data(#"{"pools":[{"id":0,"stratumCert":"PEM"}]}"#.utf8), current: current).isEmpty)
        let changed = ChangeLog.changes(body: Data(#"{"pools":[{"id":0,"stratumCert":"NEW"}]}"#.utf8), current: current)
        #expect(changed.map(\.after) == ["•••"])
    }

    private func body(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

    @Test func showsOnlyChangedValues() throws {
        let current = ChangeLog.flatten(["frequency": 500, "coreVoltage": 1150, "hostname": "a"])
        let changes = ChangeLog.changes(body: try body(["frequency": 600, "coreVoltage": 1150]), current: current)
        #expect(changes == [ChangeField(key: "frequency", before: "500", after: "600")])
    }

    @Test func comparesPoolSlotsByID() throws {
        let current = ChangeLog.flatten(["pools": [["id": 2, "stratumUser": "old.a", "stratumPort": 3333]]])
        let changes = ChangeLog.changes(body: try body(["pools": [["id": 2, "stratumUser": "new.a", "stratumPort": 3333]]]), current: current)
        #expect(changes == [ChangeField(key: "pools.2.stratumUser", before: "old.a", after: "new.a")])
    }

    @Test func passwordsNeverShow() throws {
        let changes = ChangeLog.changes(body: try body(["stratumPassword": "secret"]), current: [:])
        #expect(changes == [ChangeField(key: "stratumPassword", before: nil, after: "•••")])
        #expect(ChangeLog.changes(body: try body(["pools": [["id": 0, "stratumPassword": "*****"]]]), current: [:]).isEmpty)
    }

    @Test func storesEntriesAndRemembersRestarts() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let log = ChangeLog()
        log.activate(path: path)
        defer { try? FileManager.default.removeItem(at: path) }
        log.noteValues(host: "1.2.3.4", rawJSON: #"{"frequency":500}"#)
        log.recordWrite(host: "1.2.3.4", method: "PATCH", path: "/api/system", body: try body(["frequency": 600]), failure: nil)
        ChangeLog.$source.withValue(.watchdog) {
            log.recordWrite(host: "1.2.3.4", method: "POST", path: "/api/system/restart", body: nil, failure: nil)
        }
        log.recordWrite(host: "1.2.3.4", method: "POST", path: "/api/otp/session", body: nil, failure: nil)

        let reloaded = ChangeLog()
        reloaded.activate(path: path)
        #expect(reloaded.entries.count == 2)
        #expect(reloaded.entries.first?.action == "restart")
        #expect(reloaded.lastAutomaticRestart(host: "1.2.3.4") != nil)
        #expect(reloaded.lastAutomaticRestart(host: "9.9.9.9") == nil)
        #expect(reloaded.exportText().contains("frequency: 500 -> 600"))
    }
}
