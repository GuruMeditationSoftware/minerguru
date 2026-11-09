import SwiftUI

/// Grid of static hardware, network and firmware facts.
struct MinerHardwareSection: View {
    let miner: MinerDevice
    @Environment(\.redactor) private var redactor
    let info: MinerSystemInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hardware- & System-Telemetrie", systemImage: "memorychip")
                .font(.system(size: 15, weight: .medium))

            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                GridRow {
                    pair("Modell / Typ", miner.hardwareTitle)
                    pair("ASIC-Chip", "\(info.asicCount)x \(info.asicModel)")
                    pair("Board-Version", info.boardVersion ?? "—")
                    pair("Small Cores", info.smallCoreCount.map { "\($0)" } ?? "—")
                }
                Divider()
                GridRow {
                    pair("Hostname", info.hostname)
                    pair("MAC-Adresse", info.macAddress.map(redactor.mac) ?? "—")
                    pair("WLAN SSID", info.ssid.map(redactor.ssid) ?? "—")
                    pair("WLAN Signal", info.wifiRSSI.map { "\($0) dBm" } ?? info.wifiStatus ?? "—")
                }
                Divider()
                GridRow {
                    pair("Firmware", info.firmwareVersion.isEmpty ? "—" : info.firmwareVersion)
                    pair("ESP-IDF", info.idfVersion ?? "—")
                    pair("Freier Heap RAM", info.freeHeap.map { "\($0 / 1024) KB" } ?? "—")
                    pair("Best Diff Session / Allzeit", "\(info.sessionBestDiffText) / \(info.bestDiffFormatted)")
                }
            }
            .padding(16)
            .nativeCard()
        }
    }

    private func pair(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium).monospaced())
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
