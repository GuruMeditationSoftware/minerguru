import Foundation
import Network

/// The first job a pool hands out, as far as the block template is concerned.
struct StratumJob: Equatable, Sendable {
    var extranonce1: String?
    var extranonce2Size: Int?
    var prevHash: String
    var coinb1: String
    var coinb2: String
    var merkleBranchCount: Int
    var version: String
    var nbits: String
    var ntime: String

    var coinbase: DecodedCoinbase? {
        CoinbaseDecoder.decode(coinb1: coinb1, coinb2: coinb2, extranonce1: extranonce1, extranonce2Size: extranonce2Size)
    }
}

enum StratumProbeError: Error, Equatable, Sendable {
    case invalidEndpoint
    case connectionFailed(String)
    /// The pool refused `mining.authorize`, with its message.
    case rejected(String)
    case timeout
    case closed

    var message: String {
        switch self {
        case .invalidEndpoint: return String(localized: "Pool-Adresse ist unvollständig.")
        case .connectionFailed(let reason): return String(localized: "Keine Verbindung zum Pool: \(reason)")
        case .rejected(let reason): return String(localized: "Der Pool lehnt den User ab: \(reason)")
        case .timeout: return String(localized: "Der Pool hat keinen Auftrag geschickt.")
        case .closed: return String(localized: "Der Pool hat die Verbindung getrennt.")
        }
    }
}

/// Stratum V1 conversation up to the first `mining.notify`, without the network: subscribe,
/// authorize, read the job. Never submits a share.
struct StratumProbeSession {
    enum Event: Equatable {
        case job(StratumJob)
        case failed(StratumProbeError)
    }

    let user: String
    let password: String
    let userAgent: String
    private(set) var extranonce1: String?
    private(set) var extranonce2Size: Int?
    private var authorizeError: String?

    init(user: String, password: String = "x", userAgent: String) {
        self.user = user
        self.password = password
        self.userAgent = userAgent
    }

    /// Lines to send right after connecting.
    var openingLines: [String] {
        [
            Self.request(id: 1, method: "mining.subscribe", params: [userAgent]),
            Self.request(id: 2, method: "mining.authorize", params: [user, password]),
        ]
    }

    /// Feeds one line from the pool; returns an event once the probe is done.
    mutating func receive(_ line: String) -> Event? {
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        let id = (message["id"] as? NSNumber)?.intValue

        if let method = message["method"] as? String {
            let params = message["params"] as? [Any] ?? []
            switch method {
            case "mining.set_extranonce":
                if params.count >= 2 { readExtranonce(params[0], params[1]) }
            case "mining.notify":
                // Ocean sends the job before the authorize result, so a job is taken whenever it comes.
                if let authorizeError { return .failed(.rejected(authorizeError)) }
                return Self.job(from: params, extranonce1: extranonce1, extranonce2Size: extranonce2Size).map(Event.job)
            default:
                break
            }
            return nil
        }

        switch id {
        case 1:
            // [[subscriptions], extranonce1, extranonce2_size]; some pools refuse unknown agents and still send work.
            if let result = message["result"] as? [Any], result.count >= 3 {
                readExtranonce(result[1], result[2])
            }
        case 2:
            let accepted = (message["result"] as? Bool) ?? ((message["result"] as? NSNumber)?.boolValue ?? false)
            if !accepted {
                let reason = Self.errorText(message["error"]) ?? String(localized: "ohne Begründung")
                authorizeError = reason
                return .failed(.rejected(reason))
            }
        default:
            break
        }
        return nil
    }

    private mutating func readExtranonce(_ nonce1: Any, _ size: Any) {
        guard let nonce1 = nonce1 as? String, let size = (size as? NSNumber)?.intValue else { return }
        extranonce1 = nonce1
        extranonce2Size = size
    }

    /// `[job_id, prevhash, coinb1, coinb2, merkle_branch, version, nbits, ntime, clean]`
    static func job(from params: [Any], extranonce1: String?, extranonce2Size: Int?) -> StratumJob? {
        guard params.count >= 8,
              let prevHash = params[1] as? String,
              let coinb1 = params[2] as? String,
              let coinb2 = params[3] as? String,
              let branches = params[4] as? [Any],
              let version = params[5] as? String,
              let nbits = params[6] as? String,
              let ntime = params[7] as? String else { return nil }
        return StratumJob(
            extranonce1: extranonce1,
            extranonce2Size: extranonce2Size,
            prevHash: prevHash,
            coinb1: coinb1,
            coinb2: coinb2,
            merkleBranchCount: branches.count,
            version: version,
            nbits: nbits,
            ntime: ntime
        )
    }

    private static func errorText(_ error: Any?) -> String? {
        switch error {
        case let list as [Any]: return list.count >= 2 ? list[1] as? String : list.first.map { "\($0)" }
        case let text as String: return text
        case let object as [String: Any]: return object["message"] as? String
        default: return nil
        }
    }

    private static func request(id: Int, method: String, params: [String]) -> String {
        let object: [String: Any] = ["id": id, "method": method, "params": params]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Opens a short Stratum connection from the Mac to read the pool's current block template.
enum StratumProbe {
    static var userAgent: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "MinerGuru/\(version) (block view, no mining)"
    }

    static func fetchJob(host rawHost: String, port: Int, tls: Bool, user: String, timeout: Duration = .seconds(10)) async throws -> StratumJob {
        let host = StratumHost.clean(rawHost)
        guard !host.isEmpty, (1...65535).contains(port), let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw StratumProbeError.invalidEndpoint
        }
        let session = StratumProbeSession(user: user, userAgent: userAgent)
        let connection = StratumProbeConnection(host: host, port: nwPort, tls: tls, session: session)
        return try await withTaskCancellationHandler {
            try await connection.run(timeout: timeout)
        } onCancel: {
            connection.cancel()
        }
    }
}

/// One connection; state lives on its own queue.
private final class StratumProbeConnection: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.minerguru.stratum-probe")
    private let connection: NWConnection
    private var session: StratumProbeSession
    private var buffer = Data()
    private var continuation: CheckedContinuation<StratumJob, Error>?
    private var finished = false

    init(host: String, port: NWEndpoint.Port, tls: Bool, session: StratumProbeSession) {
        let parameters: NWParameters
        if tls {
            let options = NWProtocolTLS.Options()
            // Only public data travels here (address in, block template out); pools often use self-signed certificates.
            sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, _, complete in complete(true) }, .global())
            parameters = NWParameters(tls: options, tcp: .init())
        } else {
            parameters = .tcp
        }
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        self.session = session
    }

    func run(timeout: Duration) async throws -> StratumJob {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !finished else { return continuation.resume(throwing: CancellationError()) }
                self.continuation = continuation
                connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
                connection.start(queue: queue)
                let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
                queue.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.finish(.failure(StratumProbeError.timeout)) }
            }
        }
    }

    func cancel() {
        queue.async { [self] in finish(.failure(CancellationError())) }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            let payload = session.openingLines.map { $0 + "\n" }.joined()
            connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in })
            receive()
        case .failed(let error), .waiting(let error):
            finish(.failure(StratumProbeError.connectionFailed(error.localizedDescription)))
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.consume(data) }
            if self.finished { return }
            if let error {
                self.finish(.failure(StratumProbeError.connectionFailed(error.localizedDescription)))
            } else if isComplete {
                self.finish(.failure(StratumProbeError.closed))
            } else {
                self.receive()
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 1_000_000 else { return finish(.failure(StratumProbeError.closed)) }
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            switch session.receive(line) {
            case .job(let job): return finish(.success(job))
            case .failed(let error): return finish(.failure(error))
            case nil: continue
            }
        }
    }

    private func finish(_ result: Result<StratumJob, Error>) {
        guard !finished else { return }
        finished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}
