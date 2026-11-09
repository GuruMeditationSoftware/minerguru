import SwiftUI

/// Pool mode, dual-pool split and the stratum endpoints (two, or up to eight slots on AxeOS 2.15+),
/// with a latency test and the pool library.
struct PoolControlTab: View {
    @Binding var form: MinerSettingsForm
    let miner: MinerDevice
    @ObservedObject var library: PoolLibraryStore
    let isSaving: Bool
    let onSave: () -> Void

    @State private var testedPrimaryMs: Double?
    @State private var testedFallbackMs: Double?
    @State private var isTesting = false
    @State private var savedToLibrary: Set<Int> = []

    private var isDual: Bool { miner.supportsDualPool && form.poolMode == .dual }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Stratum-Server & Wallet konfigurieren")
                    .font(.subheadline.weight(.medium))
                Spacer()
                presetMenu
            }

            if miner.supportsDualPool {
                poolModeSection
            }

            if form.poolAPI == .slots {
                slotRoleSection
            }

            ForEach(form.visibleSlots, id: \.self) { index in
                Divider()
                PoolEndpointEditor(
                    endpoint: $form.slots[index],
                    library: library,
                    title: title(for: index),
                    symbol: "\(min(index + 1, 50)).circle.fill",
                    hostPlaceholder: index == form.primarySlot ? "public-pool.io" : "eusolo.ckpool.org",
                    passwordHelp: form.poolAPI == .slots
                        ? String(localized: "„*****“ behält das auf dem Miner gespeicherte Passwort.")
                        : String(localized: "Leer lassen, um das auf dem Miner gespeicherte Passwort zu behalten."),
                    networkDifficulty: networkDifficulty(for: index),
                    testedLatencyMs: latency(for: index),
                    isSavedToLibrary: savedToLibrary.contains(index),
                    onSaveToLibrary: { saveToLibrary(index) },
                    onClear: canClear(index) ? { form.clearSlot(index) } : nil
                )
            }

            Divider()

            if let warning = form.poolCoinWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.warning)
            }

            if let message = form.poolValidationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.warning)
            } else if !form.slotsToClear.isEmpty {
                Label(
                    String(localized: "Beim Speichern geleert: ") + form.slotsToClear.map { form.slotTitle($0) }.joined(separator: ", "),
                    systemImage: "trash"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: testLatencies) {
                    HStack(spacing: 6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Label("Pool-Latenz testen", systemImage: "waveform.path.ecg")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isTesting)

                Spacer()

                Button(action: onSave) {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().controlSize(.small) }
                        Label("Speichern & neu starten", systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || form.poolValidationMessage != nil)
            }
        }
        .onAppear {
            testedPrimaryMs = miner.primaryPoolEffectiveLatencyMs
            testedFallbackMs = miner.secondaryPoolEffectiveLatencyMs
        }
    }

    // MARK: - Slots

    private func title(for index: Int) -> String {
        switch form.poolAPI {
        case .slots:
            if index == form.primarySlot { return String(localized: "\(form.slotTitle(index)) – Primärer Pool") }
            if index == form.secondarySlot { return String(localized: "\(form.slotTitle(index)) – Fallback-Pool") }
            return String(localized: "\(form.slotTitle(index)) – Reserve")
        case .legacy:
            if index == 0 {
                return isDual ? String(localized: "Pool 1 – Primärer Stratum-Pool (\(form.primaryPercent)%)") : String(localized: "Primärer Stratum-Pool")
            }
            return isDual ? String(localized: "Pool 2 – Sekundärer Stratum-Pool (\(form.secondaryPercent)%)") : String(localized: "Fallback Stratum-Pool")
        }
    }

    private func canClear(_ index: Int) -> Bool {
        form.slots[index].hasContent && (form.poolAPI == .legacy ? index != 0 : index != form.primarySlot)
    }

    private func networkDifficulty(for index: Int) -> Double? {
        if index == form.primarySlot { return miner.latestInfo?.primaryPoolStatus?.networkDifficulty }
        if index == form.secondarySlot { return miner.latestInfo?.secondaryPoolStatus?.networkDifficulty }
        return nil
    }

    private func latency(for index: Int) -> Double? {
        if index == form.primarySlot { return testedPrimaryMs }
        if index == form.secondarySlot { return testedFallbackMs }
        return nil
    }

    private func saveToLibrary(_ index: Int) {
        let endpoint = form.slots[index]
        guard endpoint.hasContent, library.config(matching: endpoint) == nil else { return }
        let config = PoolConfig(
            name: PoolConfig.suggestedName(host: endpoint.host, port: endpoint.port, user: endpoint.user),
            endpoint: endpoint
        )
        library.add(config)
        savedToLibrary.insert(index)
    }

    // MARK: - Sections

    private var presetMenu: some View {
        Menu("Pool-Vorlage einfügen…") {
            Section("Als Primär-Pool übernehmen") {
                presetButtons { form.primary.host = $0.host; form.primary.port = $0.port }
            }
            Section("Als Fallback / Pool 2 übernehmen") {
                presetButtons { form.fallback.host = $0.host; form.fallback.port = $0.port }
            }
        }
        .controlSize(.small)
        .fixedSize()
    }

    private func presetButtons(_ apply: @escaping (PoolPreset) -> Void) -> some View {
        ForEach(PoolPreset.commonPools) { preset in
            Button("\(preset.name) (\(preset.host):\(preset.port))" as String) { apply(preset) }
        }
    }

    private var slotRoleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pool-Slots (AxeOS: bis zu \(AxeOSPool.slotCount))", systemImage: "square.stack.3d.up")
                .font(.subheadline.weight(.medium))
            HStack(spacing: 16) {
                Picker("Primär", selection: $form.primarySlot) {
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
            Text("Weitere Slots bleiben als Reserve auf dem Miner gespeichert – so wechselst du Pools ohne neu einzutippen.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func roleChoices(including current: Int) -> [Int] {
        Array(Set(form.slots.indices.filter { form.slots[$0].hasContent } + [current])).sorted()
    }

    private func slotChoiceTitle(_ index: Int) -> String {
        let slot = form.slots[index]
        guard slot.hasContent else { return String(localized: "\(form.slotTitle(index)) (leer)") }
        let name = library.config(matching: slot)?.name ?? StratumHost.clean(slot.host)
        return "\(form.slotTitle(index)): \(name)"
    }

    private var poolModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pool-Betriebsmodus", systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("", selection: $form.poolMode) {
                    Text("Standard (Failover)").tag(MinerSettingsForm.PoolMode.failover)
                    Text("Dual-Pool Mining").tag(MinerSettingsForm.PoolMode.dual)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }

            if isDual {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pool 1 (Primär): \(form.primaryPercent)%")
                        Spacer()
                        Text("Hashrate-Aufteilung")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Pool 2 (Sekundär): \(form.secondaryPercent)%")
                    }
                    .font(.caption.weight(.medium).monospacedDigit())
                    Slider(value: $form.poolBalance, in: 1...99, step: 1)
                }
                .padding(12)
                .nativeCard(cornerRadius: 8)
            }
        }
    }

    private func testLatencies() {
        isTesting = true
        let primary = form.primary
        let fallback = form.fallback
        Task {
            async let primaryMs = PoolLatencyService.shared.measureTCPConnectLatencyMs(host: primary.host, port: primary.port)
            async let fallbackMs: Double? = fallback.host.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : await PoolLatencyService.shared.measureTCPConnectLatencyMs(host: fallback.host, port: fallback.port)
            (testedPrimaryMs, testedFallbackMs) = await (primaryMs, fallbackMs)
            isTesting = false
        }
    }
}

/// Host, port, password and wallet fields for one stratum pool, with the pool library.
private struct PoolEndpointEditor: View {
    @Binding var endpoint: MinerSettingsForm.PoolEndpoint
    @ObservedObject var library: PoolLibraryStore
    let title: String
    let symbol: String
    let hostPlaceholder: String
    let passwordHelp: String?
    let networkDifficulty: Double?
    let testedLatencyMs: Double?
    let isSavedToLibrary: Bool
    let onSaveToLibrary: () -> Void
    let onClear: (() -> Void)?

    private var libraryMatch: PoolConfig? { library.config(matching: endpoint) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if endpoint.hasContent {
                    CoinBadgeView(
                        coin: MinedCoin.detect(poolHost: endpoint.host, stratumUser: endpoint.user, networkDifficulty: networkDifficulty),
                        compact: true
                    )
                }
                Spacer()
                if let testedLatencyMs {
                    LatencyBadgeView(latencyMs: testedLatencyMs)
                }
                libraryMenu
                if let onClear {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Pool aus diesem Slot entfernen")
                }
            }

            if let libraryMatch {
                Label("Bibliothek: \(libraryMatch.name)", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                PoolField("Stratum Host / URL (ohne stratum+tcp://)") {
                    TextField(hostPlaceholder, text: $endpoint.host)
                        .monospaced()
                }
                PoolField("Port") {
                    TextField("3333", value: $endpoint.port, format: .number.grouping(.never))
                        .monospaced()
                        .frame(width: 90)
                }
                PoolField("Passwort") {
                    TextField("x", text: $endpoint.password)
                        .monospaced()
                        .frame(width: 80)
                        .help(passwordHelp ?? "")
                }
            }

            PoolField("Wallet-Adresse.Worker (Stratum User)") {
                TextField("bc1q...deinewallet.bitaxe", text: $endpoint.user)
                    .monospaced()
                    .sensitive()
            }
        }
    }

    private var libraryMenu: some View {
        Menu {
            if library.pools.isEmpty {
                Text("Bibliothek ist leer")
            }
            ForEach(library.pools) { pool in
                Button("\(pool.name) – \(pool.hostAndPort)") {
                    var replacement = pool.endpoint
                    if StratumHost.clean(endpoint.host).lowercased() == pool.host.lowercased() {
                        replacement.advanced = endpoint.advanced
                    }
                    endpoint = replacement
                }
            }
            Divider()
            Button("Diesen Pool in Bibliothek speichern", action: onSaveToLibrary)
                .disabled(!endpoint.hasContent || libraryMatch != nil || isSavedToLibrary)
        } label: {
            Label("Bibliothek", systemImage: "server.rack")
        }
        .controlSize(.small)
        .fixedSize()
    }
}
