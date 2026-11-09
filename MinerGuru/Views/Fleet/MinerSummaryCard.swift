import SwiftUI
import Charts
import AppKit

// MARK: - Compact Individual Miner Summary Card

struct MinerSummaryCard: View {
    let miner: MinerDevice
    @Environment(\.redactor) private var redactor
    let tempWarningThreshold: Double
    let onSelect: () -> Void
    let onRestart: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let info = miner.latestInfo
        let isHighTemp = (info?.temp ?? 0) >= tempWarningThreshold

        VStack(alignment: .leading, spacing: 16) {
            topHeaderRow(info: info, isHighTemp: isHighTemp)

            if let info {
                hashrateRow(info: info)
                Divider()
                sensorRow(info: info, isHighTemp: isHighTemp)
                poolFooterBar(info: info)
            } else {
                offlinePlaceholderRow
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nativeCard(highlight: isHighTemp ? Signal.warning.opacity(0.5) : nil)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Label("Details & Steuerung öffnen", systemImage: "gauge.with.dots.needle.67percent")
            }

            Button {
                if let url = URL(string: "http://\(miner.ipAddress)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("AxeOS / NerdOS im Browser öffnen", systemImage: "safari")
            }

            Divider()

            Button {
                onRestart()
            } label: {
                Label("Miner neu starten", systemImage: "arrow.clockwise.circle")
            }

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Aus MinerGuru entfernen", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func topHeaderRow(info: MinerSystemInfo?, isHighTemp: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            DeviceCardView(
                spec: DeviceCardSpec(miner: miner),
                width: 84,
                led: .init(state: miner.connectionState, isHighTemp: isHighTemp)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(redactor.freeText(miner.displayName))
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(miner.hardwareTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(redactor.ip(miner.ipAddress))
                    if let fw = info?.firmwareVersion, !fw.isEmpty {
                        Text(fw)
                    }
                }
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func hashrateRow(info: MinerSystemInfo) -> some View {
        let split = MinerFormatting.splitHashrate(info.hashRate)

        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text("Hashrate")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    MinerActiveCoinsBadgeView(info: info, compact: true)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(split.value)
                        .font(.figure(28))
                    Text(split.unit)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Text("Session-Best \(info.sessionBestDiffText) · Allzeit \(info.bestDiffFormatted)")
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if miner.history.count >= 2 {
                let recentSamples = Array(miner.history.suffix(30))
                Chart(recentSamples) { sample in
                    LineMark(
                        x: .value("Zeit", sample.timestamp),
                        y: .value("GH/s", sample.hashRateGHs)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Accent.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 112, height: 36)
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func sensorRow(info: MinerSystemInfo, isHighTemp: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sensor(
                label: "ASIC",
                value: "\(DisplayFormat.decimal(info.temp, fractionDigits: 1)) °C",
                detail: nil,
                warning: isHighTemp
            )

            if let vr = info.vrTemp {
                sensor(label: "VR", value: "\(DisplayFormat.decimal(vr, fractionDigits: 0)) °C", detail: nil, warning: vr > 75)
            } else {
                sensor(label: String(localized: "Takt"), value: "\(info.frequencyMHz) MHz", detail: nil)
            }

            sensor(
                label: String(localized: "Leistung"),
                value: "\(DisplayFormat.decimal(info.power, fractionDigits: 1)) W",
                detail: "\(DisplayFormat.decimal(info.efficiencyJPerTH, fractionDigits: 1)) J/TH"
            )

            if let fan2RPM = info.fan2RPM, fan2RPM > 0 {
                let fan2Pct = info.fan2SpeedPercent ?? info.fanSpeedPercent
                sensor(
                    label: String(localized: "Lüfter"),
                    value: "\(DisplayFormat.decimal(info.fanSpeedPercent, fractionDigits: 0)) / \(DisplayFormat.decimal(fan2Pct, fractionDigits: 0)) %",
                    detail: "\(info.fanRPM)/\(fan2RPM) RPM"
                )
            } else {
                sensor(
                    label: String(localized: "Lüfter"),
                    value: "\(DisplayFormat.decimal(info.fanSpeedPercent, fractionDigits: 0)) %",
                    detail: info.fanRPM > 0 ? "\(info.fanRPM) RPM" : nil
                )
            }
        }
    }

    @ViewBuilder
    private func poolFooterBar(info: MinerSystemInfo) -> some View {
        HStack(spacing: 8) {
            Text(info.activePoolEndpoint)
                .font(.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            PoolModeBadgeView(info: info, compact: true)

            Spacer(minLength: 8)

            LatencyBadgeView(latencyMs: miner.activePoolLatencyMs, compact: true)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .insetSurface()
    }

    @ViewBuilder
    private var offlinePlaceholderRow: some View {
        HStack(spacing: 8) {
            if case .checking = miner.connectionState {
                ProgressView()
                    .controlSize(.small)
                Text("Verbinde mit \(redactor.ip(miner.ipAddress))…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if case .offline(let reason) = miner.connectionState {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nicht erreichbar")
                        .font(.system(size: 13))
                        .foregroundStyle(Signal.bad)
                    Text(reason)
                        .font(.mono(11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .frame(height: 80)
    }

    private func sensor(label: String, value: String, detail: String?, warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.mono(12))
                .foregroundStyle(warning ? AnyShapeStyle(Signal.warning) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail ?? " ")
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
