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
                Button("Daily") { days = WeekdayOrder.all }
                Button("Mon–Fri") { days = WeekdayOrder.workdays }
                Button("Weekend") { days = WeekdayOrder.weekend }
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
                Picker("From", selection: $window.startMinute) { options }
                    .frame(width: 130)
                Picker("to", selection: $window.endMinute) { options }
                    .frame(width: 120)
            }
            Text(window.isWholeDay
                 ? "Same time twice: applies all day."
                 : window.wrapsMidnight ? "Runs past midnight into the next day." : " ")
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
            Text(isNew ? "New Tariff Zone" : "Edit Tariff Zone")
                .font(.headline)

            Form {
                TextField("Name", text: $zone.name, prompt: Text("e.g. Night"))
                LabeledContent("Price per kWh") {
                    HStack(spacing: 6) {
                        TextField("", value: $zone.pricePerKWh, format: .number.precision(.fractionLength(2...4)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                        Text(currencyCode).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Days") { WeekdayPicker(days: $zone.window.weekdays) }
                LabeledContent("Time of day") { TimeWindowFields(window: $zone.window) }
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
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
            Text(isNew ? "New Schedule" : "Edit Schedule")
                .font(.headline)

            Form {
                Picker("When", selection: kind) {
                    Text("During a tariff zone").tag(TriggerKind.zone)
                        .disabled(zones.isEmpty)
                    Text("At set times").tag(TriggerKind.window)
                }
                .pickerStyle(.radioGroup)

                if kind.wrappedValue == .zone {
                    Picker("Zone", selection: zoneID) {
                        ForEach(zones) { zone in
                            Text("\(zone.name) (\(WeekdayOrder.summary(zone.window.weekdays)) \(zone.window.timeRangeText))").tag(zone.id)
                        }
                    }
                    Text("If the zone changes, the schedule follows it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent("Days") { WeekdayPicker(days: window.weekdays) }
                    LabeledContent("Time of day") { TimeWindowFields(window: window) }
                }

                Picker("Action", selection: $rule.action) {
                    ForEach([PowerAction.nightMode, .pause, .normal]) { action in
                        Label(action.title, systemImage: action.systemImage).tag(action)
                    }
                }
                if rule.action == .normal {
                    Text("“Normal” keeps miners on their own settings, even if a schedule further down wants something else.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Miners") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("All miners", isOn: Binding {
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
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
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
        return String(localized: "\(name) (cannot pause, night mode)")
    }
}
