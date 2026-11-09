import SwiftUI

/// Switches miners to a saved pool at set times, for example to a lottery pool on weekend nights.
struct PoolSchedulesCard: View {
    @ObservedObject var store: MinerStore
    @ObservedObject private var schedules: PoolScheduleStore
    @ObservedObject private var library: PoolLibraryStore
    @ObservedObject private var power: PowerStore
    @Environment(\.redactor) private var redactor
    @State private var editing: EditingRule?

    private struct EditingRule: Identifiable {
        var rule: PoolScheduleRule
        let isNew: Bool
        var id: UUID { rule.id }
    }

    init(store: MinerStore) {
        self.store = store
        self._schedules = ObservedObject(wrappedValue: store.poolSchedules)
        self._library = ObservedObject(wrappedValue: store.poolLibrary)
        self._power = ObservedObject(wrappedValue: store.power)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Scheduled pool switching", systemImage: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Button {
                    if let pool = library.pools.first {
                        editing = EditingRule(rule: PoolScheduleRule(poolID: pool.id), isNew: true)
                    }
                } label: {
                    Label("Schedule a switch", systemImage: "plus")
                }
                .disabled(library.pools.isEmpty || store.miners.isEmpty)
                .help("Move miners to a saved pool at a set time")
            }

            if schedules.rules.isEmpty {
                Text("Move miners automatically, for example to a solo pool on nights and weekends and back in the morning. Each switch is its own entry; the miner restarts briefly.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedRules) { rule in
                        row(rule)
                        if rule.id != sortedRules.last?.id { Divider() }
                    }
                }
            }

            if !schedules.rules.isEmpty && !power.runsSchedules {
                Label("This Mac does not run schedules. You can turn that on on the Power page.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            OtpWaitingNotice(store: store)
            if let error = schedules.lastError {
                Label("Last pool switch failed: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.bad)
            }
        }
        .padding(16)
        .nativeCard()
        .sheet(item: $editing) { item in
            PoolScheduleEditorSheet(rule: item.rule, isNew: item.isNew, pools: library.pools, miners: store.miners) { saved in
                if let index = schedules.rules.firstIndex(where: { $0.id == saved.id }) {
                    schedules.rules[index] = saved
                } else {
                    schedules.rules.append(saved)
                }
            }
        }
    }

    private var sortedRules: [PoolScheduleRule] { schedules.rules.sorted { $0.minute < $1.minute } }

    private func row(_ rule: PoolScheduleRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding {
                rule.isEnabled
            } set: { value in
                if let index = schedules.rules.firstIndex(where: { $0.id == rule.id }) { schedules.rules[index].isEnabled = value }
            })
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(WeekdayOrder.summary(rule.weekdays)) \(WeeklyWindow.clock(rule.minute)) → \(poolName(rule))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text(minersText(rule))
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button {
                editing = EditingRule(rule: rule, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            Button(role: .destructive) {
                schedules.rules.removeAll { $0.id == rule.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete switch")
        }
        .padding(.vertical, 8)
    }

    private func poolName(_ rule: PoolScheduleRule) -> String {
        library.config(id: rule.poolID)?.name ?? String(localized: "Pool deleted")
    }

    private func minersText(_ rule: PoolScheduleRule) -> String {
        if rule.minerIDs.isEmpty { return String(localized: "All miners") }
        let names = store.miners.filter { rule.minerIDs.contains($0.id) }.map(\.displayName)
        return names.isEmpty ? String(localized: "Miner removed") : names.joined(separator: ", ")
    }
}

struct PoolScheduleEditorSheet: View {
    @State var rule: PoolScheduleRule
    let isNew: Bool
    let pools: [PoolConfig]
    let miners: [MinerDevice]
    let onSave: (PoolScheduleRule) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool { !rule.weekdays.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Schedule a pool switch" : "Edit pool switch")
                .font(.headline)

            Form {
                Picker("Pool", selection: $rule.poolID) {
                    ForEach(pools) { Text(verbatim: $0.name).tag($0.id) }
                }
                LabeledContent("Days") { WeekdayPicker(days: $rule.weekdays) }
                Picker("Time of day", selection: $rule.minute) {
                    ForEach(Array(stride(from: 0, to: WeeklyWindow.minutesPerDay, by: 15)), id: \.self) { minute in
                        Text(WeeklyWindow.clock(minute)).tag(minute)
                    }
                }
                LabeledContent("Miners") { MinerScopePicker(selection: $rule.minerIDs, miners: miners) }
            }
            .formStyle(.columns)

            Text("The miner gets the pool as its primary pool and restarts. If it was offline at that time, MinerGuru catches up within the next 30 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if isNew { rule.createdAt = Date() }
                    onSave(rule)
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

/// "All miners" or a selection; an empty set means all.
struct MinerScopePicker: View {
    @Binding var selection: Set<UUID>
    let miners: [MinerDevice]
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("All miners", isOn: Binding {
                selection.isEmpty && !isPicking
            } set: { all in
                isPicking = !all
                if all { selection = [] }
            })
            if !selection.isEmpty || isPicking {
                ForEach(miners) { miner in
                    Toggle(miner.displayName, isOn: Binding {
                        selection.contains(miner.id)
                    } set: { on in
                        // One stays: an empty set would mean all miners.
                        if on { selection.insert(miner.id) } else if selection.count > 1 { selection.remove(miner.id) }
                    })
                }
            }
        }
    }
}
