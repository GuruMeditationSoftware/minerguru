import SwiftUI

enum ControlTab: String, CaseIterable, Identifiable {
    case performance
    case pool
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: return String(localized: "Clock & Fan")
        case .pool: return "Pool & Stratum"
        case .system: return String(localized: "System & Name")
        }
    }
}

/// Settings dialog for one miner: clock & fan, pools, name & device actions.
struct MinerControlView: View {
    @ObservedObject var store: MinerStore
    let minerID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.redactor) private var redactor

    @State private var selectedTab: ControlTab
    @State private var form = MinerSettingsForm()
    @State private var didLoadForm = false

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showRestartConfirm = false

    init(store: MinerStore, minerID: UUID, initialTab: ControlTab = .performance) {
        self.store = store
        self.minerID = minerID
        self._selectedTab = State(initialValue: initialTab)
    }

    private var miner: MinerDevice? {
        store.miners.first(where: { $0.id == minerID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Picker("", selection: $selectedTab) {
                ForEach(ControlTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            Divider()

            if let miner {
                ScrollView {
                    tabContent(for: miner)
                        .padding(20)
                }
                .onAppear { loadForm(from: miner) }
                // Below the scroll area: the buttons sit at the end of a long form, a message above them would stay out of sight.
                if let message = errorMessage ?? successMessage {
                    StatusMessage(text: message, isError: errorMessage != nil)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            } else {
                ContentUnavailableView("No Miner Selected", systemImage: "cpu")
            }
        }
        .frame(width: 580, height: 590)
        .alert("Really restart the miner?", isPresented: $showRestartConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restart Now", role: .destructive) {
                Task {
                    await store.restartMiner(minerID: minerID)
                    dismiss()
                }
            }
        } message: {
            Text("The miner briefly stops mining and restarts within a few seconds.")
        }
    }

    // MARK: - Layout

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.title2)
                .foregroundStyle(.secondary)

            if let miner {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Miner Settings: \(miner.displayName)")
                            .font(.system(size: 15, weight: .medium))
                        HardwareBadgeView(title: miner.hardwareTitle)
                    }
                    Text("IP address: \(redactor.ip(miner.ipAddress))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Miner Settings")
                    .font(.system(size: 15, weight: .medium))
            }

            Spacer()

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func tabContent(for miner: MinerDevice) -> some View {
        switch selectedTab {
        case .performance:
            PerformanceControlTab(form: $form, miner: miner, isSaving: isSaving) {
                save(form.performancePayload(existingAutoFanMode: miner.latestInfo?.autoFanModeRaw),
                     success: String(localized: "Settings sent. Clock and voltage only apply after the miner restarts."))
            }
        case .pool:
            PoolControlTab(form: $form, miner: miner, library: store.poolLibrary, isSaving: isSaving) {
                let pools = form
                perform(success: String(localized: "Pool configuration saved, the miner was restarted.")) {
                    try await store.applyPoolSettings(pools, minerID: minerID)
                }
            }
        case .system:
            SystemControlTab(
                form: $form,
                miner: miner,
                isSaving: isSaving,
                onSaveAlias: {
                    store.updateMinerCustomName(id: miner.id, customName: form.customAlias)
                    errorMessage = nil
                    successMessage = String(localized: "Display name saved.")
                },
                onSaveHostname: { save(form.hostnamePayload, success: String(localized: "Hostname sent.")) },
                onRestart: { showRestartConfirm = true }
            )
        }
    }

    // MARK: - Actions

    private func loadForm(from miner: MinerDevice) {
        guard !didLoadForm else { return }
        form = MinerSettingsForm(miner: miner)
        didLoadForm = miner.latestInfo != nil
    }

    /// Sends a settings payload to the miner and shows the result in the dialog.
    private func save(_ payload: MinerSystemUpdatePayload, success: String) {
        perform(success: success) {
            try await store.updateMinerSettings(minerID: minerID, payload: payload)
        }
    }

    private func perform(success: String, _ action: @escaping @MainActor () async throws -> Void) {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        Task {
            do {
                try await action()
                successMessage = success
            } catch is CancellationError {
                // The user declined the confirmation: nothing happened.
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Inline success / error message at the bottom of a dialog.
private struct StatusMessage: View {
    let text: String
    let isError: Bool

    var body: some View {
        Label {
            Text(text)
                .font(.caption.weight(isError ? .regular : .medium))
        } icon: {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        }
        .foregroundStyle(isError ? Signal.bad : Signal.good)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background((isError ? Signal.bad : Signal.good).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
