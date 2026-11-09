import Foundation

enum MinerAPIError: LocalizedError, Sendable {
    case invalidAddress(String)
    case httpStatusError(Int, String)
    case decodingError(String)
    case networkError(String)
    case readOnly

    var errorDescription: String? {
        switch self {
        case .invalidAddress(let addr):
            return String(localized: "Invalid address: \(addr)")
        case .httpStatusError(let code, let detail):
            if isOtpBlocked {
                return String(localized: "Too many wrong one-time codes: the miner blocks changes for 5 minutes.")
            }
            if isOtpRefused {
                return String(localized: "The miner demands a valid one-time code.")
            }
            return String(localized: "HTTP error \(code)") + (detail.isEmpty ? "" : ": \(detail)")
        case .decodingError(let msg):
            return String(localized: "Invalid response from miner: \(msg)")
        case .networkError(let msg):
            return msg
        case .readOnly:
            return String(localized: "Read-only mode is on: MinerGuru changes nothing on the miner.")
        }
    }
}

extension MinerAPIError {
    private var unauthorizedDetail: String? {
        if case .httpStatusError(401, let detail) = self { detail.lowercased() } else { nil }
    }

    /// AxeOS also answers 401 (requests from outside the local network), so the text decides.
    var isOtpRefused: Bool { unauthorizedDetail.map { $0.contains("otp") && !$0.contains("blocked") } ?? false }
    var isOtpBlocked: Bool { unauthorizedDetail?.contains("blocked") ?? false }
    var isOtpWrongCode: Bool { unauthorizedDetail?.contains("invalid") ?? false }
}

actor MinerAPIClient {
    static let shared = MinerAPIClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        self.session = URLSession(configuration: config)
    }

    /// Normalizes a user-provided IP or hostname (strips http://, trailing slashes, etc.).
    static func normalizeHost(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["http://", "https://"] {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex])
        }
        return cleaned
    }

    private func buildURL(host: String, path: String) throws -> URL {
        let normalized = Self.normalizeHost(host)
        guard !normalized.isEmpty,
              let url = URL(string: "http://\(normalized)\(path)") else {
            throw MinerAPIError.invalidAddress(host)
        }
        return url
    }

    /// Queries `GET /api/system/info` on a Bitaxe or NerdQAxe++ miner.
    func fetchSystemInfo(
        host: String,
        timeout: TimeInterval = 3.5
    ) async throws -> (info: MinerSystemInfo, rawJSON: String) {
        let url = try buildURL(host: host, path: "/api/system/info")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MinerAPIError.networkError(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw MinerAPIError.httpStatusError(http.statusCode, bodyText)
        }

        let decoder = JSONDecoder()
        do {
            let info = try decoder.decode(MinerSystemInfo.self, from: data)
            let rawPretty: String
            if let jsonObj = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: prettyData, encoding: .utf8) {
                rawPretty = str
            } else {
                rawPretty = String(data: data, encoding: .utf8) ?? "{}"
            }
            return (info, rawPretty)
        } catch {
            throw MinerAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Updates miner configuration via `PATCH /api/system`.
    func updateSystemSettings(
        host: String,
        payload: MinerSystemUpdatePayload,
        otpSession: String? = nil
    ) async throws {
        let url = try buildURL(host: host, path: "/api/system")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.timeoutInterval = 5.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(otpSession, forHTTPHeaderField: "X-OTP-Session")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(payload)

        _ = try await sendWrite(request)
    }

    /// Exchanges a one-time code for a session via `POST /api/otp/session` (NerdOS).
    func createOtpSession(host: String, code: String) async throws -> OtpSession {
        let url = try buildURL(host: host, path: "/api/otp/session")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(code, forHTTPHeaderField: "X-TOTP")
        request.httpBody = Data("{}".utf8)

        let data = try await sendWrite(request)
        do {
            return try OtpSession(response: data)
        } catch {
            throw MinerAPIError.decodingError(error.localizedDescription)
        }
    }

    /// Empties one pool slot via `DELETE /api/system/pools/{index}` (AxeOS 2.15+).
    /// The firmware refuses to delete the slot selected as primary or fallback.
    func deletePoolSlot(host: String, index: Int) async throws {
        let url = try buildURL(host: host, path: "/api/system/pools/\(index)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 5.0

        _ = try await sendWrite(request)
    }

    /// Triggers a system reboot via `POST /api/system/restart`.
    func restartMiner(host: String) async throws {
        try await postSystemCommand(host: host, path: "/api/system/restart")
    }

    /// Stops hashing without a reboot via `POST /api/system/pause` (AxeOS 2.15+).
    func pauseMiner(host: String) async throws {
        try await postSystemCommand(host: host, path: "/api/system/pause")
    }

    /// Starts hashing again after `pauseMiner` via `POST /api/system/resume` (AxeOS 2.15+).
    func resumeMiner(host: String) async throws {
        try await postSystemCommand(host: host, path: "/api/system/resume")
    }

    private func postSystemCommand(host: String, path: String) async throws {
        let url = try buildURL(host: host, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        _ = try await sendWrite(request)
    }

    /// Sends something that changes a miner and notes the outcome in the diagnostic log: the names of
    /// the fields sent, never their values or the miner's answer, which can hold passwords.
    private func sendWrite(_ request: URLRequest) async throws -> Data {
        if ChangeLog.isReadOnly { throw MinerAPIError.readOnly }
        var fields = ""
        if let body = request.httpBody, let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], !object.isEmpty {
            fields = " fields=\(object.keys.sorted().joined(separator: ","))"
        }
        let target = "\(request.url?.host ?? "?"):\(request.url?.port ?? 80) \(request.httpMethod ?? "?") \(request.url?.path ?? "?")\(fields)"
        func note(failure: String?) {
            ChangeLog.shared.recordWrite(
                host: request.url?.host.map { host in request.url?.port.map { "\(host):\($0)" } ?? host } ?? "?",
                method: request.httpMethod ?? "?", path: request.url?.path ?? "?",
                body: request.httpBody, failure: failure
            )
        }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DiagnosticLog.shared.write("write", "\(target) status=\(status)")
            if response is HTTPURLResponse, !(200...299).contains(status) {
                note(failure: "HTTP \(status)")
                throw MinerAPIError.httpStatusError(status, String(data: data, encoding: .utf8) ?? "")
            }
            note(failure: nil)
            return data
        } catch let error as URLError {
            DiagnosticLog.shared.write("write", "\(target) failed=\(error.code.rawValue)")
            note(failure: error.localizedDescription)
            throw error
        }
    }
}
