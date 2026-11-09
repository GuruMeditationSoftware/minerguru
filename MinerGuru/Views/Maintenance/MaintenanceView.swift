import SwiftUI

/// Plan of recurring maintenance per miner, and the record of what was done.
struct MaintenanceView: View {
    @ObservedObject var store: MinerStore
    @ObservedObject private var maintenance: MaintenanceStore
    @State private var editing: EditingTask?
    @State private var finishing: MaintenanceTask?

    private struct EditingTask: Identifiable {
        var task: MaintenanceTask
        let isNew: Bool
        var id: UUID { task.id }
    }

    init(store: MinerStore) {
        self.store = store
        self._maintenance = ObservedObject(wrappedValue: store.maintenance)
    }

    private var overdueCount: Int { maintenance.tasks.filter { $0.status() == .overdue }.count }
    private var soonCount: Int { maintenance.tasks.filter { $0.status() == .dueSoon }.count }

    var body: some View {
        PageScrollView(spacing: 16) {
            AdaptiveGrid(minColumnWidth: 150, spacing: 12) {
                summary("Overdue", overdueCount, tint: overdueCount > 0 ? Signal.bad : .primary)
                summary("In the next 7 days", soonCount, tint: soonCount > 0 ? Signal.warning : .primary)
                summary("Planned", maintenance.tasks.count, tint: .primary)
                summary("Completed", maintenance.records.count, tint: .primary)
            }
            tasksCard
            recordsCard
        }
        .navigationTitle("Maintenance")
        .navigationSubtitle("Plan tasks and keep a record of what was done")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(MaintenanceKind.allCases) { kind in
                        Button(kind.title) { add(kind) }
                    }
                } label: {
                    Label("Add task", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { item in
            MaintenanceTaskEditorSheet(task: item.task, isNew: item.isNew, miners: store.miners) { maintenance.upsert($0) }
        }
        .sheet(item: $finishing) { task in
            MaintenanceDoneSheet(task: task) { date, notes in maintenance.markDone(task, on: date, notes: notes) }
        }
    }

    private func add(_ kind: MaintenanceKind) {
        let due = Calendar.current.startOfDay(for: Date())
        editing = EditingTask(task: MaintenanceTask(kind: kind, intervalDays: kind.defaultIntervalDays, nextDue: due), isNew: true)
    }

    private func summary(_ title: LocalizedStringKey, _ count: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(verbatim: String(count))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.system(size: 15, weight: .medium))
            if maintenance.tasks.isEmpty {
                Text("No tasks yet. Use the plus at the top to add, for example, “Clean the fan” every 90 days. MinerGuru reminds you when a task is due.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    let tasks = maintenance.sortedTasks
                    ForEach(tasks) { task in
                        taskRow(task)
                        if task.id != tasks.last?.id { Divider() }
                    }
                }
            }
        }
        .padding(16)
        .nativeCard()
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.kind.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: task.title)
                    .font(.subheadline.weight(.medium))
                Text(verbatim: details(task))
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(verbatim: dueText(task))
                .font(.system(size: 12))
                .foregroundStyle(statusColor(task))
            Button("Mark done") { finishing = task }
            Button {
                editing = EditingTask(task: task, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            Button(role: .destructive) {
                maintenance.remove(id: task.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete task")
        }
        .padding(.vertical, 8)
    }

    private func details(_ task: MaintenanceTask) -> String {
        var parts = [minersText(task.minerIDs)]
        parts.append(task.intervalDays > 0 ? String(localized: "every \(task.intervalDays) days") : String(localized: "once"))
        if !task.notes.isEmpty { parts.append(task.notes) }
        return parts.joined(separator: " · ")
    }

    private func minersText(_ ids: Set<UUID>) -> String {
        if ids.isEmpty { return String(localized: "All miners") }
        let names = store.miners.filter { ids.contains($0.id) }.map(\.displayName)
        return names.isEmpty ? String(localized: "Miner removed") : names.joined(separator: ", ")
    }

    private func dueText(_ task: MaintenanceTask) -> String {
        let days = task.daysUntilDue()
        if days < 0 { return String(localized: "overdue by \(-days) days") }
        if days == 0 { return String(localized: "due today") }
        if days <= MaintenanceTask.dueSoonDays { return String(localized: "in \(days) days") }
        return task.nextDue.formatted(date: .abbreviated, time: .omitted)
    }

    private func statusColor(_ task: MaintenanceTask) -> Color {
        switch task.status() {
        case .overdue: Signal.bad
        case .dueSoon: Signal.warning
        case .planned: .secondary
        }
    }

    @ViewBuilder
    private var recordsCard: some View {
        if !maintenance.records.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Completed")
                    .font(.system(size: 15, weight: .medium))
                VStack(spacing: 0) {
                    ForEach(maintenance.records.prefix(50)) { record in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Signal.good)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: record.title)
                                    .font(.subheadline)
                                Text(verbatim: record.notes.isEmpty ? minersText(record.minerIDs) : "\(minersText(record.minerIDs)) · \(record.notes)")
                                    .font(.mono(11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(verbatim: record.doneAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                maintenance.removeRecord(id: record.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete entry")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(16)
            .nativeCard()
        }
    }
}

struct MaintenanceTaskEditorSheet: View {
    @State var task: MaintenanceTask
    let isNew: Bool
    let miners: [MinerDevice]
    let onSave: (MaintenanceTask) -> Void
    @Environment(\.dismiss) private var dismiss

    private var isValid: Bool { task.kind != .custom || !task.customTitle.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Add maintenance task" : "Edit maintenance task")
                .font(.headline)
            if !task.kind.hint.isEmpty {
                Text(verbatim: task.kind.hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                TextField("Title", text: $task.customTitle, prompt: Text(verbatim: task.kind == .custom ? "" : task.kind.title))
                DatePicker("Due on", selection: $task.nextDue, displayedComponents: .date)
                LabeledContent("Repeat") {
                    HStack(spacing: 6) {
                        TextField("", value: $task.intervalDays, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                        Text("days, 0 = once")
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Miners") { MinerScopePicker(selection: $task.minerIDs, miners: miners) }
                TextField("Note", text: $task.notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    task.intervalDays = max(0, task.intervalDays)
                    onSave(task)
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

struct MaintenanceDoneSheet: View {
    let task: MaintenanceTask
    let onDone: (Date, String) -> Void
    @State private var date = Date()
    @State private var notes = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: task.title)
                .font(.headline)
            Form {
                DatePicker("Done on", selection: $date, in: ...Date(), displayedComponents: .date)
                TextField("Note", text: $notes, prompt: Text("What was done?"), axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onDone(date, notes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
