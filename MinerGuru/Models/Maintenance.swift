import Foundation

/// What a maintenance task is about. Each kind brings its name, icon and a sensible interval.
enum MaintenanceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case firmware, fanCleaning, dust, thermalPaste, fanReplacement, power, cabling, pools, backup, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firmware: String(localized: "Check for firmware update")
        case .fanCleaning: String(localized: "Clean the fan")
        case .dust: String(localized: "Dust the heatsink")
        case .thermalPaste: String(localized: "Renew thermal paste")
        case .fanReplacement: String(localized: "Replace the fan")
        case .power: String(localized: "Check power supply and plugs")
        case .cabling: String(localized: "Check location and Wi-Fi")
        case .pools: String(localized: "Check pool and payout address")
        case .backup: String(localized: "Back up settings")
        case .custom: String(localized: "Custom task")
        }
    }

    var hint: String {
        switch self {
        case .firmware: String(localized: "New firmware brings fixes. Back up your settings before updating.")
        case .fanCleaning: String(localized: "Dust on the fan costs speed and drives up the temperature. Clean it only when it has stopped.")
        case .dust: String(localized: "Use compressed air or a brush, and unplug the miner first.")
        case .thermalPaste: String(localized: "If the temperature rises at the same frequency, the paste has often dried out.")
        case .fanReplacement: String(localized: "Bearings wear out. Replace loud or slow fans in good time.")
        case .power: String(localized: "Warm plugs and undersized power supplies are the most common fire hazard.")
        case .cabling: String(localized: "Check airflow, room temperature and Wi-Fi reception.")
        case .pools: String(localized: "Are pool and address still right? Compare them with the block view.")
        case .backup: String(localized: "Note down or export pools and frequency before something goes wrong.")
        case .custom: ""
        }
    }

    var systemImage: String {
        switch self {
        case .firmware: "arrow.down.circle"
        case .fanCleaning, .fanReplacement: "fan"
        case .dust: "wind"
        case .thermalPaste: "thermometer.medium"
        case .power: "powerplug"
        case .cabling: "wifi"
        case .pools: "checkmark.shield"
        case .backup: "tray.and.arrow.down"
        case .custom: "wrench.and.screwdriver"
        }
    }

    /// Days between two runs, suggested when the task is created.
    var defaultIntervalDays: Int {
        switch self {
        case .firmware, .pools: 30
        case .fanCleaning, .backup: 90
        case .dust, .power, .cabling: 180
        case .thermalPaste: 365
        case .fanReplacement: 730
        case .custom: 30
        }
    }
}

struct MaintenanceTask: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: MaintenanceKind
    /// Own title, for `.custom` or to rename a task.
    var customTitle = ""
    /// Miners this task is for; empty means all miners.
    var minerIDs: Set<UUID> = []
    /// Days until it is due again; 0 = once.
    var intervalDays: Int
    var nextDue: Date
    var notes = ""

    var title: String {
        let own = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? kind.title : own
    }

    enum Status: Equatable { case overdue, dueSoon, planned }

    static let dueSoonDays = 7

    func status(at date: Date = Date(), calendar: Calendar = .current) -> Status {
        let days = daysUntilDue(at: date, calendar: calendar)
        if days < 0 { return .overdue }
        return days <= Self.dueSoonDays ? .dueSoon : .planned
    }

    func daysUntilDue(at date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: nextDue)).day ?? 0
    }

    /// The next date after it was done on `date`; `nil` for a task that runs once.
    func nextDue(afterDoneOn date: Date, calendar: Calendar = .current) -> Date? {
        intervalDays > 0 ? calendar.date(byAdding: .day, value: intervalDays, to: date) : nil
    }
}

/// One finished maintenance job, kept as a record per miner.
struct MaintenanceRecord: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: MaintenanceKind
    var title: String
    var minerIDs: Set<UUID>
    var doneAt: Date
    var notes = ""
}
