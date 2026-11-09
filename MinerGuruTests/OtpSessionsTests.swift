import Foundation
import Testing
@testable import MinerGuru

@MainActor
@Suite("One-time code sessions")
struct OtpSessionsTests {
    private func miner(otp: Bool = true) -> MinerDevice {
        Fixtures.device(ip: "192.0.2.1", name: "Test", info: try! Fixtures.info(["otp": otp]))
    }

    /// Hands out the given answers in turn and counts the sessions it created.
    private final class Script {
        var answers: [String?]
        var prompts: [String?] = []
        init(_ answers: [String?]) { self.answers = answers }
    }

    private func sessions(answers: [String?], create: @escaping OtpSessions.Create = { _, _ in
        OtpSession(token: "t1", expires: Date().addingTimeInterval(86400))
    }) -> (OtpSessions, Script) {
        let script = Script(answers)
        let otp = OtpSessions(usesKeychain: false)
        otp.create = create
        otp.prompt = { _, problem in
            script.prompts.append(problem)
            return script.answers.isEmpty ? nil : script.answers.removeFirst()
        }
        return (otp, script)
    }

    private let refused = MinerAPIError.httpStatusError(401, "OTP/Session required")

    @Test func readsTheOtpFlag() throws {
        let on = try JSONDecoder().decode(MinerSystemInfo.self, from: Data(#"{"otp": true}"#.utf8))
        let missing = try JSONDecoder().decode(MinerSystemInfo.self, from: Data("{}".utf8))
        #expect(on.otp)
        #expect(!missing.otp)
    }

    @Test func expiryComesFromTheDurationNotTheMinersClock() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let data = Data(#"{"token":"abc","ttlMs":86400000,"expiresAt":5}"#.utf8)
        let session = try OtpSession(response: data, now: now)
        #expect(session.token == "abc")
        #expect(session.expires == now.addingTimeInterval(86400))
        #expect(session.isUsable(at: now))
        #expect(!session.isUsable(at: now.addingTimeInterval(86400 - 30)))
    }

    @Test func recognisesTheAnswersOfTheFirmware() {
        #expect(refused.isOtpRefused)
        #expect(!refused.isOtpBlocked)
        #expect(MinerAPIError.httpStatusError(401, "blocked for 5 minutes").isOtpBlocked)
        #expect(!MinerAPIError.httpStatusError(401, "blocked for 5 minutes").isOtpRefused)
        #expect(!MinerAPIError.httpStatusError(401, "Unauthorized").isOtpRefused)
        #expect(MinerAPIError.httpStatusError(401, "Invalid TOTP").isOtpWrongCode)
    }

    @Test func minerWithoutOtpNeverAsks() async throws {
        let (otp, script) = sessions(answers: [])
        let sent = try await otp.perform(for: miner(otp: false), interactive: true) { $0 }
        #expect(sent == nil)
        #expect(script.prompts.isEmpty)
    }

    @Test func asksOnceAndReusesTheSession() async throws {
        let (otp, script) = sessions(answers: ["123456"])
        let device = miner()
        #expect(try await otp.perform(for: device, interactive: true) { $0 } == "t1")
        #expect(try await otp.perform(for: device, interactive: true) { $0 } == "t1")
        #expect(script.prompts.count == 1)
        #expect(otp.canWriteUnattended(device))
    }

    @Test func asksAgainAfterAMalformedOrWrongCode() async throws {
        let (otp, script) = sessions(answers: ["12", "111111", " 123456 "]) { _, code in
            guard code == "123456" else { throw MinerAPIError.httpStatusError(401, "Invalid TOTP") }
            return OtpSession(token: "ok", expires: Date().addingTimeInterval(86400))
        }
        #expect(try await otp.authorize(miner()) == "ok")
        #expect(script.prompts.count == 3)
        #expect(script.prompts[0] == nil)
        #expect(script.prompts[1] != nil)
        #expect(script.prompts[2] != nil)
    }

    @Test func cancellingWritesNothing() async {
        let (otp, _) = sessions(answers: [nil])
        var writes = 0
        await #expect(throws: OtpError.cancelled) {
            try await otp.perform(for: miner(), interactive: true) { _ in writes += 1 }
        }
        #expect(writes == 0)
    }

    @Test func minerThatTurnedOtpOffGoesOn() async throws {
        let (otp, _) = sessions(answers: ["123456"]) { _, _ in throw MinerAPIError.httpStatusError(405, "") }
        #expect(try await otp.perform(for: miner(), interactive: true) { $0 } == nil)
    }

    @Test func aRefusedSessionIsReplacedOnce() async throws {
        var made = 0
        let script = Script(["123456", "654321"])
        let otp = OtpSessions(usesKeychain: false)
        otp.prompt = { _, _ in script.answers.removeFirst() }
        otp.create = { _, code in OtpSession(token: code, expires: Date().addingTimeInterval(86400)) }
        let device = miner()
        let sent = try await otp.perform(for: device, interactive: true) { token in
            made += 1
            if made == 1 { throw refused }
            return token
        }
        #expect(sent == "654321")
        #expect(made == 2)
    }

    @Test func unattendedWriteWithoutSessionSendsNothing() async {
        let (otp, script) = sessions(answers: ["123456"])
        var writes = 0
        await #expect(throws: OtpError.codeNeeded) {
            try await otp.perform(for: miner(), interactive: false) { _ in writes += 1 }
        }
        #expect(writes == 0)
        #expect(script.prompts.isEmpty)
    }

    @Test func unattendedWriteDropsARefusedSession() async throws {
        let (otp, script) = sessions(answers: ["123456"])
        let device = miner()
        try await otp.authorize(device)
        await #expect(throws: MinerAPIError.self) {
            try await otp.perform(for: device, interactive: false) { _ in throw refused }
        }
        #expect(!otp.canWriteUnattended(device))
        #expect(script.prompts.count == 1)
    }

    @Test func expiredSessionDoesNotCountForSchedules() async throws {
        let (otp, _) = sessions(answers: ["123456"])
        let device = miner()
        try await otp.authorize(device)
        #expect(!otp.canWriteUnattended(device, at: Date().addingTimeInterval(86400)))
    }
}
