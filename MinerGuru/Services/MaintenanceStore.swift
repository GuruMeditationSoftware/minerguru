import Foundation

/// Planned maintenance and the record of what was done.
@MainActor
final class MaintenanceStore: ObservableObject {
    @Published var tasks: [MaintenanceTask] { didSet { save(tasks, Self.tasksKey) } }
    @Published private(set) var records: [MaintenanceRecord] { didSet { save(records, Self.recordsKey) } }

    private let defaults: UserDefaults
    private var remindedAt: [UUID: Date] = [:]

    private static let tasksKey = "MinerGuru.MaintenanceTasks.v1"
    private static let recordsKey = "MinerGuru.MaintenanceRecords.v1"
    private static let remindAgain: TimeInterval = 86_400

    init(defaults: UserDefaults) {
        self.defaults = defaults
        tasks = Self.load([MaintenanceTask].self, Self.tasksKey, defaults) ?? []
        records = Self.load([MaintenanceRecord].self, Self.recordsKey, defaults) ?? []
    }

    var sortedTasks: [MaintenanceTask] { tasks.sorted { $0.nextDue < $1.nextDue } }

    func dueCount(at date: Date = Date()) -> Int {
        tasks.filter { $0.status(at: date) == .overdue || $0.daysUntilDue(at: date) == 0 }.count
    }

    func upsert(_ task: MaintenanceTask) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task } else { tasks.append(task) }
    }

    func remove(id: UUID) { tasks.removeAll { $0.id == id } }

    func markDone(_ task: MaintenanceTask, on date: Date = Date(), notes: String = "") {
        records.insert(MaintenanceRecord(kind: task.kind, title: task.title, minerIDs: task.minerIDs, doneAt: date, notes: notes), at: 0)
        if let next = task.nextDue(afterDoneOn: date) {
            var updated = task
            updated.nextDue = next
            upsert(updated)
        } else {
            remove(id: task.id)
        }
    }

    func removeRecord(id: UUID) { records.removeAll { $0.id == id } }

    /// A task keeps its last miner: an empty set would mean all miners. It then shows "Miner entfernt".
    func forget(minerID: UUID) {
        for index in tasks.indices where tasks[index].minerIDs.count > 1 { tasks[index].minerIDs.remove(minerID) }
    }

    /// Reminder for due tasks, at most once a day per task.
    func dueEvents(at date: Date = Date()) -> [AlertEvent] {
        tasks.compactMap { task in
            guard task.daysUntilDue(at: date) <= 0,
                  remindedAt[task.id].map({ date.timeIntervalSince($0) >= Self.remindAgain }) ?? true else { return nil }
            remindedAt[task.id] = date
            return AlertEvent(kind: .maintenance, minerID: task.id,
                              title: String(localized: "Maintenance due: \(task.title)"),
                              body: task.kind.hint.isEmpty ? String(localized: "Mark it as done in MinerGuru.") : task.kind.hint,
                              isRecovery: false, minerName: task.title)
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
