import Foundation

/// A named stratum pool setup (host, port, wallet/worker, password) that can be assigned to miner pool slots.
struct PoolConfig: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int
    var user: String
    var password: String

    init(id: UUID = UUID(), name: String, host: String, port: Int = 3333, user: String = "", password: String = "x") {
        self.id = id
        self.name = name
        self.host = StratumHost.clean(host)
        self.port = port
        self.user = user
        self.password = password
    }

    /// From a pool read off a miner. Firmware does not report passwords (empty or `*****`); most pools ignore them.
    init(name: String, endpoint: MinerSettingsForm.PoolEndpoint) {
        let password = [AxeOSPool.maskedPassword, ""].contains(endpoint.password) ? "x" : endpoint.password
        self.init(name: name, host: endpoint.host, port: endpoint.port, user: endpoint.user, password: password)
    }

    var endpoint: MinerSettingsForm.PoolEndpoint {
        .init(host: host, port: port, user: user, password: password)
    }

    var hostAndPort: String { "\(host):\(port)" }

    var isValid: Bool {
        !StratumHost.clean(host).isEmpty && (1...65535).contains(port)
    }

    /// Same pool target and account, ignoring name and password.
    func matches(_ endpoint: MinerSettingsForm.PoolEndpoint) -> Bool {
        StratumHost.clean(endpoint.host).lowercased() == host.lowercased()
            && endpoint.port == port
            && endpoint.user.trimmingCharacters(in: .whitespaces) == user.trimmingCharacters(in: .whitespaces)
    }

    /// Readable default name for a pool found on a miner, e.g. "CKPool EU (Solo) · rig1".
    static func suggestedName(host: String, port: Int, user: String) -> String {
        let cleanHost = StratumHost.clean(host)
        let base = PoolPreset.commonPools.first { $0.host == cleanHost && $0.port == port }?.name ?? cleanHost
        let worker = user.split(separator: ".", maxSplits: 1).dropFirst().first.map(String.init)
        return worker.map { "\(base) · \($0)" } ?? base
    }
}
