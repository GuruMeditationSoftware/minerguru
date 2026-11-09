import SwiftUI

/// First-launch screen when no miner is configured: network scan and manual IP entry.
struct FleetOnboardingView: View {
    @ObservedObject var store: MinerStore
    @ObservedObject private var scanner: NetworkScanStore
    @Environment(\.redactor) private var redactor

    @State private var quickIPInput: String = ""
    @State private var quickNameInput: String = ""
    @State private var isTestingQuickIP: Bool = false
    @State private var quickIPError: String?

    init(store: MinerStore) {
        self.store = store
        self._scanner = ObservedObject(wrappedValue: store.scanner)
    }


    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                DeviceCardStack(cards: [
                    (DeviceCardSpec(family: "nerdqaxe++", model: "", chipCount: 4, chipModel: "BM1370", display: .tft), nil),
                    (DeviceCardSpec(family: "bitaxe", model: "Gamma 601", chipCount: 1, chipModel: "BM1370", display: .oled), nil)
                ], width: 168)
                .padding(.bottom, 8)

                Text("Monitor Bitaxe and NerdQAxe miners on your home network")
                    .font(.system(size: 28, weight: .medium))

                Text("Scan your local network or add a miner directly by IP address.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 580)
            }
            .padding(.top, 12)

            HStack(alignment: .top, spacing: 20) {
                // Card 1: Automatic Network Scan
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan network automatically")
                                .font(.system(size: 15, weight: .medium))
                            Text("Looks for Bitaxe & NerdQAxe++ in \(redactor.ip(scanner.subnetPrefix)).1–254")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Text("Subnet:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("192.168.1", text: $scanner.subnetPrefix)
                            .sensitive()
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .monospaced()
                        Text(".1 – .254")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if scanner.isScanning {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(
                                value: Double(scanner.completedCount),
                                total: Double(max(1, scanner.totalCount))
                            )
                            HStack {
                                Text("Checking IPs on the local network… (\(scanner.completedCount)/\(scanner.totalCount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Spacer()
                                Button("Stop") {
                                    scanner.stopScan()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    } else {
                        Button {
                            scanner.startScan(autoAddNew: true)
                        } label: {
                            Label("Scan local network now", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    if !scanner.discoveredMiners.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Miners found (\(scanner.discoveredMiners.count)):")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)

                            ForEach(scanner.discoveredMiners) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(item.info.hostname)
                                                .font(.subheadline.weight(.medium))
                                            HardwareBadgeView(title: item.info.detectedHardwareTitle)
                                        }
                                        Text("\(redactor.ip(item.ipAddress)) • \(MinerFormatting.formatHashrate(item.info.hashRate)) • \(String(format: "%.1f °C", item.info.temp))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    Button(store.isIPAlreadyAdded(item.ipAddress) ? "Added" : "Add") {
                                        store.addMiner(
                                            ipAddress: item.ipAddress,
                                            initialInfo: item.info,
                                            rawJSON: item.rawJSON
                                        )
                                    }
                                    .disabled(store.isIPAlreadyAdded(item.ipAddress))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeCard()

                // Card 2: Manual IP Entry
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "plus.rectangle.on.folder.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add miner by IP address")
                                .font(.system(size: 15, weight: .medium))
                            Text("Enter an IP address or hostname directly")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("IP address or hostname")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("e.g. 192.168.1.150 or bitaxe.local", text: $quickIPInput)
                                .sensitive()
                                .textFieldStyle(.roundedBorder)
                                .monospaced()
                                .onSubmit {
                                    addQuickMiner()
                                }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Display name (optional)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            TextField("e.g. Living Room Gamma 601 or NerdQAxe++", text: $quickNameInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let quickIPError {
                        Label(quickIPError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        addQuickMiner()
                    } label: {
                        HStack {
                            if isTestingQuickIP {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Label("Connect & add miner", systemImage: "plus.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    .controlSize(.large)
                    .disabled(quickIPInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTestingQuickIP)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeCard()
            }
            .frame(maxWidth: 920)
        }
        .frame(maxWidth: .infinity)
    }

    private func addQuickMiner() {
        let host = MinerAPIClient.normalizeHost(quickIPInput)
        guard !host.isEmpty else { return }
        isTestingQuickIP = true
        quickIPError = nil

        Task {
            do {
                let (info, raw) = try await MinerAPIClient.shared.fetchSystemInfo(host: host, timeout: 3.0)
                await MainActor.run {
                    store.addMiner(
                        ipAddress: host,
                        customName: quickNameInput,
                        initialInfo: info,
                        rawJSON: raw
                    )
                    quickIPInput = ""
                    quickNameInput = ""
                    isTestingQuickIP = false
                }
            } catch {
                await MainActor.run {
                    // Add anyway so user can monitor when it comes online, and inform user
                    store.addMiner(ipAddress: host, customName: quickNameInput)
                    quickIPInput = ""
                    quickNameInput = ""
                    isTestingQuickIP = false
                }
            }
        }
    }
}
