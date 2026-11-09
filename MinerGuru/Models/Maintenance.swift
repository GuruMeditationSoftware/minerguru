import Foundation

/// What a maintenance task is about. Each kind brings its name, icon and a sensible interval.
enum MaintenanceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case firmware, fanCleaning, dust, thermalPaste, fanReplacement, power, cabling, pools, backup, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firmware: String(localized: "Firmware-Update prüfen")
        case .fanCleaning: String(localized: "Lüfter reinigen")
        case .dust: String(localized: "Kühlkörper entstauben")
        case .thermalPaste: String(localized: "Wärmeleitpaste erneuern")
        case .fanReplacement: String(localized: "Lüfter tauschen")
        case .power: String(localized: "Netzteil und Stecker prüfen")
        case .cabling: String(localized: "Standort und WLAN prüfen")
        case .pools: String(localized: "Pool und Auszahlungsadresse prüfen")
        case .backup: String(localized: "Einstellungen sichern")
        case .custom: String(localized: "Eigene Aufgabe")
        }
    }

    var hint: String {
        switch self {
        case .firmware: String(localized: "Neue Firmware bringt Fehlerbehebungen. Vor dem Update Einstellungen sichern.")
        case .fanCleaning: String(localized: "Staub am Lüfter kostet Drehzahl und treibt die Temperatur hoch. Nur im Stillstand reinigen.")
        case .dust: String(localized: "Mit Druckluft oder Pinsel, Miner vorher vom Strom trennen.")
        case .thermalPaste: String(localized: "Steigt die Temperatur bei gleichem Takt, ist die Paste oft trocken.")
        case .fanReplacement: String(localized: "Lager nutzen sich ab. Laute oder langsame Lüfter rechtzeitig ersetzen.")
        case .power: String(localized: "Warme Stecker und knappe Netzteile sind die häufigste Brandursache.")
        case .cabling: String(localized: "Luftzufuhr, Umgebungstemperatur und WLAN-Empfang kontrollieren.")
        case .pools: String(localized: "Stimmen Pool und Adresse noch? Abgleich mit der Blockansicht.")
        case .backup: String(localized: "Pools und Takt notieren oder exportieren, bevor etwas schiefgeht.")
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
