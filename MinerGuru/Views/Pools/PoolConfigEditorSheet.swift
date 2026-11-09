import SwiftUI

/// Create or edit one saved pool configuration.
struct PoolConfigEditorSheet: View {
    @State var config: PoolConfig
    let isNew: Bool
    let onSave: (PoolConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var testedLatencyMs: Double?
    @State private var isTesting = false

    private var cleanedConfig: PoolConfig {
        var cleaned = config
        cleaned.name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.host = StratumHost.clean(config.host)
        cleaned.user = config.user.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.name.isEmpty {
            cleaned.name = PoolConfig.suggestedName(host: cleaned.host, port: cleaned.port, user: cleaned.user)
        }
        return cleaned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(isNew ? "New Pool Configuration" : "Edit Pool Configuration", systemImage: "server.rack")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Menu("Template…") {
                    ForEach(PoolPreset.commonPools) { preset in
                        Button("\(preset.name) (\(preset.host):\(preset.port))" as String) {
                            config.host = preset.host
                            config.port = preset.port
                            if config.name.isEmpty { config.name = preset.name }
                        }
                    }
                }
                .controlSize(.small)
                .fixedSize()
            }

            PoolField("Name") {
                TextField("e.g. CKPool EU · rig1", text: $config.name)
            }

            HStack(spacing: 12) {
                PoolField("Stratum host / URL (without stratum+tcp://)") {
                    TextField("public-pool.io", text: $config.host)
                        .monospaced()
                }
                PoolField("Port") {
                    TextField("3333", value: $config.port, format: .number.grouping(.never))
                        .monospaced()
                        .frame(width: 90)
                }
                PoolField("Password") {
                    TextField("x", text: $config.password)
                        .monospaced()
                        .frame(width: 80)
                }
            }

            PoolField("Wallet address.worker (stratum user)") {
                TextField("bc1q...yourwallet.bitaxe", text: $config.user)
                    .monospaced()
                    .sensitive()
            }

            if let coins = MinedCoin.mismatch(poolHost: config.host, stratumUser: config.user) {
                Label("This address belongs to \(coins.address.symbol), the pool mines \(coins.pool.symbol). Payouts could be lost.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Signal.warning)
            }

            HStack(spacing: 8) {
                if !config.host.isEmpty {
                    CoinBadgeView(coin: MinedCoin.detect(poolHost: config.host, stratumUser: config.user), showFullName: true, compact: true)
                }
                if let testedLatencyMs {
                    LatencyBadgeView(latencyMs: testedLatencyMs)
                }
                Spacer()
                Button(action: testLatency) {
                    HStack(spacing: 6) {
                        if isTesting { ProgressView().controlSize(.small) }
                        Label("Test Latency", systemImage: "waveform.path.ecg")
                    }
                }
                .disabled(isTesting || !cleanedConfig.isValid)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    onSave(cleanedConfig)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!cleanedConfig.isValid)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func testLatency() {
        isTesting = true
        let target = cleanedConfig
        Task {
            testedLatencyMs = await PoolLatencyService.shared.measureTCPConnectLatencyMs(host: target.host, port: target.port)
            isTesting = false
        }
    }
}

/// Caption above a text field, as used in the pool forms.
struct PoolField<Content: View>: View {
    private let label: LocalizedStringKey
    private let content: Content

    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// Picker that fills a miner pool slot from the pool library.
struct LibraryPoolPicker: View {
    @ObservedObject var library: PoolLibraryStore
    let endpoint: MinerSettingsForm.PoolEndpoint
    let onSelect: (PoolConfig?) -> Void

    private enum Choice: Hashable {
        case empty
        case unsaved
        case pool(UUID)
    }

    private var selection: Binding<Choice> {
        Binding {
            guard endpoint.hasContent else { return .empty }
            return library.config(matching: endpoint).map { .pool($0.id) } ?? .unsaved
        } set: { choice in
            switch choice {
            case .empty: onSelect(nil)
            case .pool(let id): onSelect(library.config(id: id))
            case .unsaved: break
            }
        }
    }

    var body: some View {
        Picker("", selection: selection) {
            Text("— empty —").tag(Choice.empty)
            if endpoint.hasContent, library.config(matching: endpoint) == nil {
                Text("\(StratumHost.clean(endpoint.host)):\(String(endpoint.port)) (not in library)")
                    .tag(Choice.unsaved)
            }
            if !library.pools.isEmpty {
                Divider()
                ForEach(library.pools) { pool in
                    Text("\(pool.name) – \(pool.hostAndPort)").tag(Choice.pool(pool.id))
                }
            }
        }
        .labelsHidden()
    }
}
