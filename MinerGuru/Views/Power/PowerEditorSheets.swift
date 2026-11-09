import SwiftUI

// MARK: - Shared controls

/// Seven day toggles, Monday first, with shortcuts for every day, workdays and the weekend.
struct WeekdayPicker: View {
    @Binding var days: Set<Weekday>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(WeekdayOrder.mondayFirst, id: \.self) { day in
                    Toggle(WeekdayOrder.shortName(day), isOn: Binding {
                        days.contains(day)
                    } set: { on in
                        if on { days.insert(day) } else { days.remove(day) }
                    })
                    .toggleStyle(.button)
                }
            }
            HStack(spacing: 12) {
                Button("Täglich") { days = WeekdayOrder.all }
                Button("Mo–Fr") { days = WeekdayOrder.workdays }
                Button("Wochenende") { days = WeekdayOrder.weekend }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}

/// From–to time of day in 15-minute steps; the same time twice means the whole day.
struct TimeWindowFields: View {
    @Binding var window: WeeklyWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker("Von", selection: $window.startMinute) { options }
                    .frame(width: 130)
                Picker("bis", selection: $window.endMinute) { options }
                    .frame(width: 120)
            }
            Text(window.isWholeDay
                 ? "Gleiche Zeit zweimal: gilt den ganzen Tag."
                 : window.wrapsMidnight ? "Läuft über Mitternacht in den nächsten Tag." : " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var options: some View {
        ForEach(Array(stride(from: 0, to: WeeklyWindow.minutesPerDay, by: 15)), id: \.self) { minute in
            Text(WeeklyWindow.clock(minute)).tag(minute)
        }
    }
}

// MARK: - Zone editor

struct TariffZoneEditorSheet: View {
    @State var zone: TariffZone
    let isNew: Bool
    let currencyCode: String
    let onSave: (TariffZone) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool {
        !zone.name.trimmingCharacters(in: .whitespaces).isEmpty && !zone.window.weekdays.isEmpty && zone.pricePerKWh >= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Neue Tarifzone" : "Tarifzone bearbeiten")
                .font(.headline)

            Form {
                TextField("Name", text: $zone.name, prompt: Text("z. B. Nacht"))
                LabeledContent("Preis pro kWh") {
                    HStack(spacing: 6) {
                        TextField("", value: $zone.pricePerKWh, format: .number.precision(.fractionLength(2...4)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                        Text(currencyCode).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Tage") { WeekdayPicker(days: $zone.window.weekdays) }
                LabeledContent("Uhrzeit") { TimeWindowFields(window: $zone.window) }
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    zone.name = zone.name.trimmingCharacters(in: .whitespaces)
                    onSave(zone)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - Schedule editor

struct ScheduleRuleEditorSheet: View {
    @State var rule: ScheduleRule
    let isNew: Bool
    let zones: [TariffZone]
    let miners: [MinerDevice]
    let onSave: (ScheduleRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.redactor) private var redactor

    private enum TriggerKind: Hashable { case zone, window }

    private var kind: Binding<TriggerKind> {
        Binding {
            if case .zone = rule.trigger { return .zone }
            return .window
        } set: { newKind in
            switch newKind {
            case .zone:
                if let first = zones.first { rule.trigger = .zone(first.id) }
            case .window:
                rule.trigger = .window(WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 22 * 60, endMinute: 6 * 60))
            }
        }
    }

    private var zoneID: Binding<UUID> {
        Binding {
            if case .zone(let id) = rule.trigger { return id }
            return zones.first?.id ?? UUID()
        } set: { rule.trigger = .zone($0) }
    }

    private var window: Binding<WeeklyWindow> {
        Binding {
            if case .window(let window) = rule.trigger { return window }
            return WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 0, endMinute: 0)
        } set: { rule.trigger = .window($0) }
    }

    private var isValid: Bool {
        switch rule.trigger {
        case .zone(let id): return zones.contains { $0.id == id }
        case .window(let window): return !window.weekdays.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Neuer Zeitplan" : "Zeitplan bearbeiten")
                .font(.headline)

            Form {
                Picker("Wann", selection: kind) {
                    Text("Während einer Tarifzone").tag(TriggerKind.zone)
                        .disabled(zones.isEmpty)
                    Text("Zu festen Uhrzeiten").tag(TriggerKind.window)
                }
                .pickerStyle(.radioGroup)

                if kind.wrappedValue == .zone {
                    Picker("Zone", selection: zoneID) {
                        ForEach(zones) { zone in
                            Text("\(zone.name) (\(WeekdayOrder.summary(zone.window.weekdays)) \(zone.window.timeRangeText))").tag(zone.id)
                        }
                    }
                    Text("Ändert sich die Zone, zieht der Zeitplan mit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Tage") { WeekdayPicker(days: window.weekdays) }
                    LabeledContent("Uhrzeit") { TimeWindowFields(window: window) }
                }

                Picker("Aktion", selection: $rule.action) {
                    ForEach([PowerAction.nightMode, .pause, .normal]) { action in
                        Label(action.title, systemImage: action.systemImage).tag(action)
                    }
                }
                if rule.action == .normal {
                    Text("„Normal“ hält Miner bei ihren eigenen Einstellungen, auch wenn ein Zeitplan weiter unten etwas anderes will.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Miner") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Alle Miner", isOn: Binding {
                            rule.minerIDs.isEmpty
                        } set: { all in
                            rule.minerIDs = all ? [] : Set(miners.map(\.id))
                        })
                        if !rule.minerIDs.isEmpty {
                            ForEach(miners) { miner in
                                Toggle(isOn: Binding {
                                    rule.minerIDs.contains(miner.id)
                                } set: { on in
                                    if on { rule.minerIDs.insert(miner.id) } else if rule.minerIDs.count > 1 { rule.minerIDs.remove(miner.id) }
                                }) {
                                    Text(minerLabel(miner))
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func minerLabel(_ miner: MinerDevice) -> String {
        let name = redactor.freeText(miner.displayName)
        guard rule.action == .pause, miner.latestInfo != nil, !PowerStore.canPause(miner) else { return name }
        return String(localized: "\(name) (kann nicht pausieren, Nachtmodus)")
    }
}
