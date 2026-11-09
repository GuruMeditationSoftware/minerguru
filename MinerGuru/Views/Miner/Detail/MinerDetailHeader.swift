import SwiftUI
import AppKit

/// Identity row with icon-only actions and a wrapping strip of network/system metadata.
struct MinerDetailHeader: View {
    let miner: MinerDevice
    @Environment(\.redactor) private var redactor
    let tempWarningThresholdC: Double
    let onShowJSON: () -> Void
    let onRestart: () -> Void
    let onOpenControl: () -> Void
    let onRefresh: () -> Void

    private var info: MinerSystemInfo? { miner.latestInfo }

    var body: some View {
        let isHighTemp = (info?.temp ?? 0) >= tempWarningThresholdC

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                DeviceCardView(
                    spec: DeviceCardSpec(miner: miner),
                    width: 168,
                    led: .init(state: miner.connectionState, isHighTemp: isHighTemp)
                )
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    identity(isHighTemp: isHighTemp)
                    if let info {
                        HStack(spacing: 16) {
                            PoolModeBadgeView(info: info)
                            MinerActiveCoinsBadgeView(info: info)
                        }
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                actionButtons
                    .layoutPriority(1)
            }

            Divider()

            // Wraps between items, never mid-value
            FlowLayout(horizontalSpacing: 24, verticalSpacing: 8) {
                metadata("IP", redactor.ip(miner.ipAddress), selectable: !redactor.isActive)
                if let info {
                    metadata("Uptime", MinerFormatting.formatUptime(info.uptimeSeconds))
                    if let ssid = info.ssid, !ssid.isEmpty {
                        metadata("Wi-Fi", redactor.ssid(ssid) + (info.wifiRSSI.map { " (\($0) dBm)" } ?? ""))
                    }
                    if !info.firmwareVersion.isEmpty {
                        metadata("Firmware", info.firmwareVersion)
                    }
                }
                Button(action: onRefresh) {
                    Label("Refresh Now", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
        }
        .padding(24)
        .nativeCard(cornerRadius: 16)
    }

    private func identity(isHighTemp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(redactor.freeText(miner.displayName))
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ConnectionStatusDot(state: miner.connectionState, isHighTemp: isHighTemp)
            }

            HStack(spacing: 8) {
                HardwareBadgeView(title: miner.hardwareTitle)
                if let info {
                    Text("\(info.asicCount)× \(info.asicModel)")
                        .font(.mono(11))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }
            }
        }
    }

    /// Always icon-only: identical look at every window size.
    private var actionButtons: some View {
        HStack(spacing: 8) {
            iconButton("Raw JSON", "curlybraces", action: onShowJSON)
            iconButton("Open in Browser", "safari") {
                if let url = miner.webInterfaceURL { NSWorkspace.shared.open(url) }
            }
            iconButton("Restart", "arrow.clockwise.circle", action: onRestart)
            iconButton("Controls & Settings…", "slider.horizontal.3", action: onOpenControl)
        }
    }

    private func iconButton(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize()
        .help(title)
    }

    private func metadata(_ label: LocalizedStringKey, _ value: String, selectable: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Group {
                if selectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(.mono(11))
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
