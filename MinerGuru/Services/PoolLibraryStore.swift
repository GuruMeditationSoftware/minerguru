import Foundation

/// Persisted list of pool configurations the user can assign to miners.
@MainActor
final class PoolLibraryStore: ObservableObject {
    @Published private(set) var pools: [PoolConfig] = []

    private let defaults: UserDefaults
    private static let key = "MinerGuru.PoolConfigs.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                pools = try JSONDecoder().decode([PoolConfig].self, from: data)
            } catch {
                Log.persistence.error("Pool configurations not readable: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func config(id: UUID?) -> PoolConfig? {
        guard let id else { return nil }
        return pools.first { $0.id == id }
    }

    /// The library entry that equals `endpoint` (same host, port and account), if any.
    func config(matching endpoint: MinerSettingsForm.PoolEndpoint) -> PoolConfig? {
        guard endpoint.hasContent else { return nil }
        return pools.first { $0.matches(endpoint) }
    }

    @discardableResult
    func add(_ config: PoolConfig) -> PoolConfig {
        pools.append(config)
        save()
        return config
    }

    func update(_ config: PoolConfig) {
        guard let idx = pools.firstIndex(where: { $0.id == config.id }) else { return }
        pools[idx] = config
        save()
    }

    func remove(id: UUID) {
        pools.removeAll { $0.id == id }
        save()
    }

    func duplicate(id: UUID) -> PoolConfig? {
        guard let original = config(id: id) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name += String(localized: " Kopie")
        return add(copy)
    }

    /// Adds every pool configured on a miner (all slots) that is not in the library yet. Returns the number added.
    @discardableResult
    func importPools(from miners: [MinerDevice]) -> Int {
        var added = 0
        for miner in miners where miner.latestInfo != nil {
            for endpoint in MinerSettingsForm(miner: miner).slots
            where !endpoint.host.isEmpty && config(matching: endpoint) == nil {
                pools.append(PoolConfig(
                    name: PoolConfig.suggestedName(host: endpoint.host, port: endpoint.port, user: endpoint.user),
                    endpoint: endpoint
                ))
                added += 1
            }
        }
        if added > 0 { save() }
        return added
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(pools), forKey: Self.key)
        } catch {
            Log.persistence.error("Pool configurations not savable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
