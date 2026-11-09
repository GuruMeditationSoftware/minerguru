import SwiftUI

struct NetworkScannerSheet: View {
    @ObservedObject var store: MinerStore
    @Environment(\.redactor) private var redactor
    @ObservedObject private var scanner: NetworkScanStore
    @Environment(\.dismiss) private var dismiss

    init(store: MinerStore) {
        self.store = store
        self._scanner = ObservedObject(wrappedValue: store.scanner)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lokales Netzwerk nach Minern durchsuchen")
                        .font(.system(size: 15, weight: .medium))
                    Text("Erkennt automatisch Bitaxe (Gamma 601, Supra, Ultra) & NerdQAxe++ über /api/system/info")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fertig") {
                    scanner.stopScan()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            // Subnet configuration & Start/Stop button
            HStack(spacing: 12) {
                Text("Subnetz-Präfix:")
                    .font(.subheadline)
                TextField("192.168.1", text: $scanner.subnetPrefix)
                    .sensitive()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .monospaced()
                    .disabled(scanner.isScanning)
                Text(".1 bis .254")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if scanner.isScanning {
                    Button {
                        scanner.stopScan()
                    } label: {
                        Label("Scan abbrechen", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        scanner.startScan(autoAddNew: false)
                    } label: {
                        Label("Scan starten", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if scanner.isScanning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(
                        value: Double(scanner.completedCount),
                        total: Double(max(1, scanner.totalCount))
                    )
                    HStack {
                        Text("Scanne \(redactor.ip(scanner.subnetPrefix)).1–254… (\(scanner.completedCount) / \(scanner.totalCount) IPs geprüft)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Spacer()
                        Text("\(scanner.discoveredMiners.count) Miner gefunden")
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Discovered list
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Gefundene Miner im Netzwerk (\(scanner.discoveredMiners.count))")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if !scanner.discoveredMiners.isEmpty {
                        Button("Alle neuen hinzufügen") {
                            scanner.addAllDiscovered()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(scanner.discoveredMiners.allSatisfy { store.isIPAlreadyAdded($0.ipAddress) })
                    }
                }

                if scanner.discoveredMiners.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: scanner.isScanning ? "dot.radiowaves.left.and.right" : "network")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(scanner.isScanning ? "Suche läuft…" : "Noch keine Miner im Scan-Ergebnis")
                            .font(.system(size: 15, weight: .medium))
                        Text(
                            scanner.isScanning
                                ? "Antwortende Bitaxe- und NerdQAxe++-Miner erscheinen sofort hier."
                                : "Klicke auf „Scan starten“, um das Subnetz \(redactor.ip(scanner.subnetPrefix)).1–254 zu durchsuchen."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(scanner.discoveredMiners) { item in
                                let alreadyAdded = store.isIPAlreadyAdded(item.ipAddress)
                                HStack(spacing: 14) {
                                    DeviceCardView(spec: DeviceCardSpec(scanned: item.info), width: 52)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(item.info.hostname)
                                                .font(.subheadline.weight(.medium))
                                            HardwareBadgeView(title: item.info.detectedHardwareTitle)
                                            Text("\(item.info.asicCount)x \(item.info.asicModel)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        HStack(spacing: 12) {
                                            Text(redactor.ip(item.ipAddress))
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                            Text(MinerFormatting.formatHashrate(item.info.hashRate))
                                                .font(.caption.weight(.medium).monospacedDigit())
                                            Text(String(format: "%.1f °C", item.info.temp))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "%.1f W", item.info.power))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if alreadyAdded {
                                        Label("Bereits vorhanden", systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(.green)
                                    } else {
                                        Button("Hinzufügen") {
                                            store.addMiner(
                                                ipAddress: item.ipAddress,
                                                initialInfo: item.info,
                                                rawJSON: item.rawJSON
                                            )
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(12)
                                .nativeCard()
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 640, height: 480)
        .onAppear {
            if !scanner.isScanning && scanner.discoveredMiners.isEmpty {
                scanner.startScan(autoAddNew: false)
            }
        }
    }
}

// MARK: - Manual IP Addition Sheet

struct AddMinerByIPSheet: View {
    @ObservedObject var store: MinerStore
    @Environment(\.redactor) private var redactor
    @Environment(\.dismiss) private var dismiss

    @State private var ipOrHost: String = ""
    @State private var customName: String = ""
    @State private var isTesting: Bool = false
    @State private var previewInfo: MinerSystemInfo?
    @State private var previewRawJSON: String?
    @State private var testError: String?

    init(store: MinerStore) {
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "plus")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Miner per IP-Adresse oder Hostname hinzufügen")
                        .font(.system(size: 15, weight: .medium))
                    Text("Verbindet sich über HTTP mit /api/system/info deines Bitaxe oder NerdQAxe++")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP-Adresse oder lokaler Hostname")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("z.B. 192.168.1.142 oder nerdqaxe.local", text: $ipOrHost)
                            .sensitive()
                            .textFieldStyle(.roundedBorder)
                            .monospaced()
                            .onSubmit {
                                testConnection()
                            }

                        Button {
                            testConnection()
                        } label: {
                            HStack(spacing: 6) {
                                if isTesting {
                                    ProgressView().controlSize(.small)
                                }
                                Text("Verbindung prüfen")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(ipOrHost.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Eigener Anzeigename (optional)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("z.B. Büro Gamma 601 oder Keller NerdQAxe++", text: $customName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let info = previewInfo {
                HStack(spacing: 12) {
                    DeviceCardView(spec: DeviceCardSpec(scanned: info), width: 52, led: .init(state: .online))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(info.hostname)
                                .font(.subheadline.weight(.medium))
                            HardwareBadgeView(title: info.detectedHardwareTitle)
                        }
                        Text("\(MinerFormatting.formatHashrate(info.hashRate)) · \(DisplayFormat.decimal(info.temp, fractionDigits: 1)) °C · \(info.activePoolEndpoint)")
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .nativeCard(cornerRadius: 12)
            } else if let testError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Signal.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Miner aktuell nicht erreichbar")
                            .font(.caption.weight(.medium))
                        Text("\(testError) — Du kannst die IP trotzdem hinzufügen.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .nativeCard(cornerRadius: 12, highlight: Signal.warning.opacity(0.4))
            }

            Spacer()

            Divider()

            HStack {
                Button("Abbrechen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Miner hinzufügen") {
                    addAndClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(ipOrHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 500, height: 340)
    }

    private func testConnection() {
        let host = MinerAPIClient.normalizeHost(ipOrHost)
        guard !host.isEmpty else { return }
        isTesting = true
        previewInfo = nil
        testError = nil

        Task {
            do {
                let (info, raw) = try await MinerAPIClient.shared.fetchSystemInfo(host: host, timeout: 3.0)
                await MainActor.run {
                    previewInfo = info
                    previewRawJSON = raw
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testError = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func addAndClose() {
        let host = MinerAPIClient.normalizeHost(ipOrHost)
        guard !host.isEmpty else { return }
        if let device = store.addMiner(
            ipAddress: host,
            customName: customName,
            initialInfo: previewInfo,
            rawJSON: previewRawJSON
        ) {
            store.selection = .miner(device.id)
        }
        dismiss()
    }
}
