import SwiftUI

/// Pool slots of one miner on the pool configuration page: library pool per slot, primary / fallback
/// selection (AxeOS 2.15+) and dual-pool split (NerdQAxe).
struct MinerPoolAssignmentCard: View {
    let miner: MinerDevice
    @ObservedObject var library: PoolLibraryStore
    @Environment(\.redactor) private var redactor
    @Binding var form: MinerSettingsForm
    let isDirty: Bool
    let isApplying: Bool
    let errorMessage: String?
    let onApply: () -> Void
    let onReset: () -> Void
    let onSaveToLibrary: (MinerSettingsForm.PoolEndpoint) -> Void

    private var isDual: Bool { miner.supportsDualPool && form.poolMode == .dual }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if miner.supportsDualPool {
                dualPoolSection
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(form.visibleSlots, id: \.self) { index in
                    slotRow(index)
                }
            }

            if form.poolAPI == .slots {
                roleSection
            }

            footer
        }
        .padding(16)
        .nativeCard(highlight: isDirty ? Accent.color : nil)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            ConnectionStatusDot(state: miner.connectionState)
            VStack(alignment: .leading, spacing: 2) {
                Text(miner.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(firmwareDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HardwareBadgeView(title: miner.hardwareTitle)
        }
    }

    private var firmwareDescription: String {
        switch form.poolAPI {
        case .slots: return "\(redactor.ip(miner.ipAddress)) • " + String(localized: "\(AxeOSPool.slotCount) pool slots")
        case .legacy: return "\(redactor.ip(miner.ipAddress)) • " + (miner.supportsDualPool ? String(localized: "Failover or dual pool") : String(localized: "Primary + fallback"))
        }
    }

    private var dualPoolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $form.poolMode) {
                Text("Failover").tag(MinerSettingsForm.PoolMode.failover)
                Text("Dual Pool").tag(MinerSettingsForm.PoolMode.dual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if isDual {
                HStack(spacing: 8) {
                    Text("P1 \(form.primaryPercent)%")
                    Slider(value: $form.poolBalance, in: 1...99, step: 1)
                    Text("P2 \(form.secondaryPercent)%")
                }
                .font(.caption.weight(.medium).monospacedDigit())
            }
        }
    }

    private func slotRow(_ index: Int) -> some View {
        let endpoint = form.slots[index]
        return HStack(spacing: 8) {
            Text(slotLabel(index))
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)

            ZStack(alignment: .leading) {
                Color.clear
                if endpoint.hasContent {
                    CoinBadgeView(coin: coin(for: index), compact: true)
                }
            }
            .frame(width: 52, height: 18)

            LibraryPoolPicker(library: library, endpoint: endpoint) { config in
                if let config {
                    form.assign(config, toSlot: index)
                } else {
                    form.clearSlot(index)
                }
            }

            // Fixed column, also when a slot has no role, so all rows line up.
            ZStack(alignment: .trailing) {
                Color.clear
                roleBadge(index)
            }
            .frame(width: 74, height: 18)

            if endpoint.hasContent, library.config(matching: endpoint) == nil {
                Button {
                    onSaveToLibrary(endpoint)
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Add this pool to the library")
            }
        }
    }

    /// Coin from pool host and wallet; the network difficulty the miner reports helps for pools it is connected to.
    private func coin(for index: Int) -> MinedCoin {
        let endpoint = form.slots[index]
        let host = StratumHost.clean(endpoint.host).lowercased()
        var difficulty: Double?
        // Only while the slot still holds the pool the miner is connected to (drafts may differ).
        if let info = miner.latestInfo {
            if index == form.primarySlot, host == StratumHost.clean(info.stratumURL).lowercased() {
                difficulty = info.primaryPoolStatus?.networkDifficulty
            } else if index == form.secondarySlot, host == StratumHost.clean(info.fallbackStratumURL).lowercased() {
                difficulty = info.secondaryPoolStatus?.networkDifficulty
            }
        }
        return MinedCoin.detect(poolHost: endpoint.host, stratumUser: endpoint.user, networkDifficulty: difficulty)
    }

    private func slotLabel(_ index: Int) -> String {
        switch form.poolAPI {
        case .slots: return form.slotTitle(index)
        case .legacy: return index == 0 ? (isDual ? "Pool 1" : String(localized: "Primary")) : (isDual ? "Pool 2" : "Fallback")
        }
    }

    @ViewBuilder
    private func roleBadge(_ index: Int) -> some View {
        if form.poolAPI == .slots {
            if index == form.primarySlot {
                RoleBadge(text: String(localized: "Primary"), color: Signal.good)
            } else if index == form.secondarySlot {
                RoleBadge(text: "Fallback", color: Signal.warning)
            } else if form.slots[index].hasContent {
                RoleBadge(text: "Reserve", color: .secondary)
            }
        } else if isDual {
            RoleBadge(text: "\(index == 0 ? form.primaryPercent : form.secondaryPercent)%", color: Signal.idle)
        }
    }

    private var filledSlots: [Int] {
        form.slots.indices.filter { form.slots[$0].hasContent }
    }

    private var roleSection: some View {
        HStack(spacing: 12) {
            Picker("Primary", selection: $form.primarySlot) {
                ForEach(roleChoices(including: form.primarySlot), id: \.self) { index in
                    Text(slotChoiceTitle(index)).tag(index)
                }
            }
            Picker("Fallback", selection: $form.secondarySlot) {
                ForEach(roleChoices(including: form.secondarySlot), id: \.self) { index in
                    Text(slotChoiceTitle(index)).tag(index)
                }
            }
        }
        .font(.caption)
    }

    private func roleChoices(including current: Int) -> [Int] {
        Array(Set(filledSlots + [current])).sorted()
    }

    private func slotChoiceTitle(_ index: Int) -> String {
        let slot = form.slots[index]
        guard slot.hasContent else { return String(localized: "\(form.slotTitle(index)) (empty)") }
        let name = library.config(matching: slot)?.name ?? StratumHost.clean(slot.host)
        return "\(form.slotTitle(index)): \(name)"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = form.poolValidationMessage, isDirty {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.warning)
            }
            if let warning = form.poolCoinWarning, isDirty {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.warning)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(Signal.bad)
            }
            HStack {
                if !form.slotsToClear.isEmpty {
                    Text(String(localized: "Will be cleared: ") + form.slotsToClear.map { form.slotTitle($0) }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset", action: onReset)
                    .disabled(!isDirty || isApplying)
                Button(action: onApply) {
                    HStack(spacing: 6) {
                        if isApplying { ProgressView().controlSize(.small) }
                        Text("Apply & Restart")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Send the pools to the miner; it restarts afterwards so they take effect")
                .disabled(!isDirty || isApplying || form.poolValidationMessage != nil || !miner.connectionState.isOnline)
            }
            .controlSize(.small)
        }
    }
}

private struct RoleBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
