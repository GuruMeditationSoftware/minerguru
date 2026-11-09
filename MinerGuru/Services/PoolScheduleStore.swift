import Foundation

/// Stored pool schedules and their execution after every refresh round. Whether this device may switch miners at all
/// is the same setting as for the power schedules.
@MainActor
final class PoolScheduleStore: ObservableObject {
    @Published var rules: [PoolScheduleRule] { didSet { save() } }
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private weak var minerStore: MinerStore?
    private var applied: [String: Date]
    private var switching: Set<UUID> = []

    private static let rulesKey = "MinerGuru.PoolSchedules.v1"
    private static let appliedKey = "MinerGuru.PoolSchedulesApplied.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        rules = defaults.data(forKey: Self.rulesKey).flatMap { try? JSONDecoder().decode([PoolScheduleRule].self, from: $0) } ?? []
        applied = defaults.data(forKey: Self.appliedKey).flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
    }

    func attach(to store: MinerStore) { minerStore = store }

    /// A rule keeps its last miner: an empty set would mean all miners. It then applies to none and shows "Miner entfernt".
    func forget(minerID: UUID) {
        for index in rules.indices where rules[index].minerIDs.count > 1 { rules[index].minerIDs.remove(minerID) }
    }

    func removeRules(usingPool poolID: UUID) {
        rules.removeAll { $0.poolID == poolID }
    }

    func evaluate(at date: Date = Date()) async {
        guard let store = minerStore, store.power.runsSchedules else { return }
        for rule in rules {
            guard let config = store.poolLibrary.config(id: rule.poolID) else { continue }
            for miner in store.onlineMiners where rule.applies(to: miner.id) && !switching.contains(miner.id) {
                let key = "\(rule.id.uuidString)|\(miner.id.uuidString)"
                guard let moment = rule.dueOccurrence(at: date, lastApplied: applied[key]) else { continue }
                var form = MinerSettingsForm(miner: miner)
                let switches = form.switchPrimary(to: config)
                // Stays due without a session, so it still runs if a code comes in time.
                if switches, !store.otp.canWriteUnattended(miner, at: date) { continue }
                applied[key] = moment
                saveApplied()
                guard switches else { continue }
                if let problem = form.poolValidationMessage {
                    lastError = problem
                    continue
                }
                switching.insert(miner.id)
                do {
                    try await store.applyPoolSettings(form, minerID: miner.id, interactive: false)
                    lastError = nil
                } catch {
                    lastError = String(localized: "\(miner.displayName): \(error.localizedDescription)")
                }
                switching.remove(miner.id)
            }
        }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(rules), forKey: Self.rulesKey)
    }

    private func saveApplied() {
        defaults.set(try? JSONEncoder().encode(applied), forKey: Self.appliedKey)
    }
}
