import AppKit
import Foundation

/// A session the miner granted for a one-time code (NerdOS): sent as `X-OTP-Session` when writing settings.
struct OtpSession: Codable, Equatable, Sendable {
    var token: String
    var expires: Date

    /// A session this close to its end could run out on the way to the miner.
    static let safetyMargin: TimeInterval = 60

    func isUsable(at date: Date) -> Bool { expires.timeIntervalSince(date) > Self.safetyMargin }

    /// The miner answers `{token, ttlMs, expiresAt}`. Its clock may be wrong, so only the duration counts.
    init(response data: Data, now: Date = Date()) throws {
        struct Answer: Decodable {
            var token: String
            var ttlMs: Double
        }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        token = answer.token
        expires = now.addingTimeInterval(answer.ttlMs / 1000)
    }

    init(token: String, expires: Date) {
        self.token = token
        self.expires = expires
    }
}

enum OtpError: LocalizedError, Equatable {
    case cancelled
    case codeNeeded

    var errorDescription: String? {
        switch self {
        case .cancelled: String(localized: "No one-time code entered, nothing changed.")
        case .codeNeeded: String(localized: "This miner needs a one-time code.")
        }
    }
}

/// Sessions for miners that protect their settings with a one-time code. The code itself is never kept.
/// Schedules only use a stored session: five refused requests lock the miner for five minutes.
@MainActor
final class OtpSessions: ObservableObject {
    /// Asks for the code; `nil` when the user cancels. The second argument says what was wrong with the last try.
    typealias Prompt = @MainActor (_ minerName: String, _ problem: String?) async -> String?
    typealias Create = @Sendable (_ host: String, _ code: String) async throws -> OtpSession

    var prompt: Prompt = OtpSessions.askWithAlert
    var create: Create = { try await MinerAPIClient.shared.createOtpSession(host: $0, code: $1) }

    @Published private var sessions: [UUID: OtpSession] = [:]
    private var looked: Set<UUID> = []
    private var running: [UUID: Task<String?, Error>] = [:]
    private let usesKeychain: Bool

    init(usesKeychain: Bool = true) {
        self.usesKeychain = usesKeychain
    }

    private func account(_ id: UUID) -> String { "otp.\(id.uuidString)" }

    /// The stored session of a miner, if it can still be used.
    func token(for id: UUID, at date: Date = Date()) -> String? {
        if usesKeychain, looked.insert(id).inserted, let text = Keychain.password(account: account(id)),
           let stored = try? JSONDecoder().decode(OtpSession.self, from: Data(text.utf8)) {
            sessions[id] = stored
        }
        guard let session = sessions[id], session.isUsable(at: date) else { return nil }
        return session.token
    }

    /// Whether a schedule may write to this miner without anyone at the screen.
    func canWriteUnattended(_ miner: MinerDevice, at date: Date = Date()) -> Bool {
        !miner.requiresOtp || token(for: miner.id, at: date) != nil
    }

    func invalidate(_ id: UUID) {
        looked.insert(id)
        sessions[id] = nil
        if usesKeychain { Keychain.setPassword("", account: account(id)) }
    }

    private func keep(_ session: OtpSession, for id: UUID) {
        looked.insert(id)
        sessions[id] = session
        if usesKeychain, let data = try? JSONEncoder().encode(session) {
            Keychain.setPassword(String(decoding: data, as: UTF8.self), account: account(id))
        }
    }

    /// Returns a valid session, asking for a code if there is none; `nil` when the miner no longer uses OTP.
    @discardableResult
    func authorize(_ miner: MinerDevice) async throws -> String? {
        if let token = token(for: miner.id) { return token }
        if let task = running[miner.id] { return try await task.value }
        let task = Task { try await self.askForCode(miner) }
        running[miner.id] = task
        defer { running[miner.id] = nil }
        return try await task.value
    }

    private func askForCode(_ miner: MinerDevice) async throws -> String? {
        var problem: String?
        while true {
            guard let answer = await prompt(miner.displayName, problem) else { throw OtpError.cancelled }
            let code = answer.trimmingCharacters(in: .whitespaces)
            guard code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                problem = String(localized: "The code has 6 digits.")
                continue
            }
            do {
                let session = try await create(miner.ipAddress, code)
                keep(session, for: miner.id)
                return session.token
            } catch MinerAPIError.httpStatusError(405, _) {
                return nil
            } catch let error as MinerAPIError where error.isOtpWrongCode {
                problem = String(localized: "That code is wrong. Wait for the next one and try again.")
            }
        }
    }

    /// Runs a write. `interactive` may ask for a code; otherwise only a stored session is used
    /// and a refused one is dropped, so the next attempt does not cost another failed try.
    func perform<T>(for miner: MinerDevice, interactive: Bool, _ write: (String?) async throws -> T) async throws -> T {
        var token: String?
        if miner.requiresOtp {
            token = interactive ? try await authorize(miner) : self.token(for: miner.id)
            if token == nil, !interactive { throw OtpError.codeNeeded }
        }
        do {
            return try await write(token)
        } catch let error as MinerAPIError where error.isOtpRefused {
            invalidate(miner.id)
            guard interactive else { throw error }
            return try await write(try await authorize(miner))
        }
    }

    private static func askWithAlert(minerName: String, problem: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "One-time code for \(minerName)")
        alert.informativeText = problem ?? String(localized: "This miner protects its settings with a one-time code. Enter the 6-digit code from your authenticator app. The session lasts up to 24 hours.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "123456"
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Confirm"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
