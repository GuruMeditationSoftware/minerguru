import Foundation

/// One pool a miner works for, as far as the Stratum probe needs it.
struct BlockProbeTarget: Hashable, Sendable {
    enum Slot: Hashable, Sendable {
        case primary
        case secondary
    }

    var host: String
    var port: Int
    var tls: Bool
    /// The miner's own Stratum user; the payout check runs against its address.
    var user: String
    var coin: MinedCoin
    var slot: Slot
    /// Hashrate share in dual pool mode, `nil` when the miner works for one pool only.
    var sharePercent: Int?

    /// The probe logs in as `<wallet>.minerguru`, so it never takes the miner's worker name.
    var probeUser: String {
        let wallet = user.split(separator: ".", maxSplits: 1).first.map(String.init) ?? user
        return "\(wallet).minerguru"
    }

    /// Pools to probe for a miner: none if the firmware reports the block itself (AxeOS 2.13+),
    /// both in dual pool mode, otherwise the one delivering work.
    static func targets(for info: MinerSystemInfo) -> [BlockProbeTarget] {
        guard BlockTemplateSummary(info: info) == nil else { return [] }
        let primary = BlockProbeTarget(
            url: info.stratumURL, port: info.stratumPort, tlsFlag: info.stratumTLS,
            user: info.stratumUser, coin: info.primaryPoolCoin, slot: .primary
        )
        let secondary = BlockProbeTarget(
            url: info.fallbackStratumURL, port: info.fallbackStratumPort, tlsFlag: info.fallbackStratumTLS,
            user: info.fallbackStratumUser, coin: info.secondaryPoolCoin, slot: .secondary
        )
        if info.isDualPoolMining {
            return [
                primary.map { var t = $0; t.sharePercent = info.dualPoolPrimaryPercent; return t },
                secondary.map { var t = $0; t.sharePercent = info.dualPoolSecondaryPercent; return t },
            ].compactMap { $0 }
        }
        return [(info.isUsingFallbackStratum ? secondary : primary)].compactMap { $0 }
    }

    private init?(url: String, port: Int, tlsFlag: Bool?, user: String, coin: MinedCoin, slot: Slot) {
        let host = StratumHost.clean(url)
        guard !host.isEmpty, (1...65535).contains(port), !user.isEmpty else { return nil }
        let scheme = url.lowercased()
        self.host = host
        self.port = port
        self.tls = tlsFlag == true || scheme.hasPrefix("stratum+ssl://") || scheme.hasPrefix("stratum+tls://")
        self.user = user
        self.coin = coin
        self.slot = slot
    }
}

/// Results of the Stratum probe per pool, fetched while a miner's detail page is open.
@MainActor
final class BlockProbeStore: ObservableObject {
    enum State {
        case loading
        case loaded(BlockTemplateSummary)
        case failed(String)
    }

    struct Entry {
        var state: State
        var updatedAt: Date
    }

    /// At most one connection per pool in this time, unless the user asks.
    static let minimumInterval: TimeInterval = 5 * 60

    @Published private(set) var entries: [BlockProbeTarget: Entry] = [:]
    @Published private(set) var running: Set<BlockProbeTarget> = []

    typealias Fetch = @Sendable (BlockProbeTarget) async throws -> StratumJob
    private let fetch: Fetch

    init(fetch: @escaping Fetch = { target in
        try await StratumProbe.fetchJob(host: target.host, port: target.port, tls: target.tls, user: target.probeUser)
    }) {
        self.fetch = fetch
    }

    /// Probes `target` unless it ran within `minimumInterval`; `force` skips that wait.
    func refresh(_ target: BlockProbeTarget, force: Bool = false, now: Date = Date()) {
        guard !running.contains(target) else { return }
        if !force, let entry = entries[target], now.timeIntervalSince(entry.updatedAt) < Self.minimumInterval { return }
        running.insert(target)
        if entries[target] == nil {
            entries[target] = Entry(state: .loading, updatedAt: now)
        }
        let fetch = fetch
        Task {
            let state: State
            do {
                let job = try await fetch(target)
                state = BlockTemplateSummary(job: job, coin: target.coin, stratumUser: target.user).map(State.loaded)
                    ?? .failed(String(localized: "Der Auftrag des Pools ließ sich nicht lesen."))
            } catch let error as StratumProbeError {
                state = .failed(error.message)
            } catch {
                state = .failed(error.localizedDescription)
            }
            entries[target] = Entry(state: state, updatedAt: Date())
            running.remove(target)
        }
    }

    /// Forgets all results, e.g. when the probe is switched off.
    func reset() {
        entries = [:]
    }
}
