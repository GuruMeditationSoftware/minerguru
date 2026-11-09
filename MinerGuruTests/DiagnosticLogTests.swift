import Foundation
import Testing
@testable import MinerGuru

@Suite("Diagnostic log")
struct DiagnosticLogTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func writesOneLinePerEvent() throws {
        let log = DiagnosticLog(path: try folder().appendingPathComponent("minerguru.log"))
        log.write("state", "first\nsecond")
        log.write("alert", "third")
        let lines = log.exportText().split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("[state] first second"))
    }

    @Test func keepsOnlyTwoFiles() throws {
        let base = try folder()
        let log = DiagnosticLog(path: base.appendingPathComponent("minerguru.log"))
        let line = String(repeating: "x", count: 100_000)
        for index in 0..<25 { log.write("test", "\(index) \(line)") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).sorted() == ["minerguru.1.log", "minerguru.log"])
        let text = log.exportText()
        #expect(!text.contains("] 0 x"))
        #expect(text.contains("] 24 x"))
        #expect(text.utf8.count <= 2 * DiagnosticLog.maxBytes)
    }

    @Test func staysSilentUntilActivated() {
        let log = DiagnosticLog()
        log.write("test", "nothing")
        #expect(log.exportText().isEmpty)
    }

    @Test func profileNamesFieldsButNoValues() throws {
        var device = Fixtures.device(ip: "192.168.1.50", name: "Gamma", info: try Fixtures.info(["ASICModel": "BM1370"]))
        device.rawJSON = #"{"stratumUser":"bc1qsecret.worker","stratumPassword":"hunter2","ssid":"HomeWifi","temp":55}"#
        let profile = DiagnosticLog.profile(device, device.latestInfo!)
        #expect(profile.contains("keys=ssid,stratumPassword,stratumUser,temp"))
        #expect(!profile.contains("secret"))
        #expect(!profile.contains("hunter2"))
        #expect(!profile.contains("HomeWifi"))
    }

    @Test func measurementsEveryFifteenMinutes() throws {
        var health = MinerHealth()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let info = try Fixtures.info(["temp": 55, "hashRate_1m": 1000, "sharesAccepted": 5, "uptimeSeconds": 7200])
        health.update(info, at: start)
        #expect(health.snapshot(info, at: start)?.contains("temp=55.0") == true)
        #expect(health.snapshot(info, at: start.addingTimeInterval(14 * 60)) == nil)
        #expect(health.snapshot(info, at: start.addingTimeInterval(15 * 60)) != nil)
    }
}
