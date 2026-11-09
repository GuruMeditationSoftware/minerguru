import SwiftUI
import Charts

/// 2×2 grid of history charts: hashrate, temperatures, pool latency and power.
struct MinerTelemetryCharts: View {
    let miner: MinerDevice
    let info: MinerSystemInfo
    let tempWarningThresholdC: Double
    let pollingIntervalSeconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(.system(size: 20, weight: .medium))
                Spacer()
                Text("\(miner.history.count) samples · every \(pollingIntervalSeconds) s")
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
            }

            AdaptiveGrid(minColumnWidth: 340, spacing: 16) {
                ChartCard(title: "Hashrate History (GH/s)", subtitle: MinerFormatting.formatHashrate(info.hashRate),
                          icon: "bolt.horizontal.fill", tint: Accent.color) {
                    AreaLineChart(samples: miner.history, label: "GH/s", tint: Accent.color) { $0.hashRateGHs }
                }

                ChartCard(title: "ASIC & VR Temperature (°C)", subtitle: "ASIC \(DisplayFormat.decimal(info.temp, fractionDigits: 1)) °C",
                          icon: "thermometer.medium", tint: .secondary) {
                    temperatureChart
                }

                let latencySamples = miner.history.filter { ($0.poolLatencyMs ?? 0) > 0 }
                ChartCard(title: "Pool Latency to Stratum Server (ms)", subtitle: MinerFormatting.formatLatency(miner.activePoolLatencyMs),
                          icon: "globe.europe.africa.fill", tint: .secondary) {
                    if latencySamples.isEmpty {
                        ContentUnavailableView {
                            Label("No latency data yet", systemImage: "waveform.path.ecg")
                                .font(.caption)
                        }
                    } else {
                        AreaLineChart(samples: latencySamples, label: "Latenz (ms)", tint: .secondary, includesZero: true) { $0.poolLatencyMs ?? 0 }
                    }
                }

                ChartCard(title: "Power Draw (Watts)",
                          subtitle: "\(DisplayFormat.decimal(info.power, fractionDigits: 1)) W · \(DisplayFormat.decimal(info.efficiencyJPerTH, fractionDigits: 1)) J/TH",
                          icon: "bolt.fill", tint: .secondary) {
                    AreaLineChart(samples: miner.history, label: "Watt", tint: .secondary) { $0.powerWatts }
                }
            }
        }
    }

    private var temperatureChart: some View {
        Chart {
            ForEach(miner.history) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("ASIC °C", sample.asicTempC),
                    series: .value("Sensor", "ASIC")
                )
                .foregroundStyle(Color.primary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))

                if let vr = sample.vrTempC, vr > 0 {
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("VR °C", vr),
                        series: .value("Sensor", "VR")
                    )
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }

            RuleMark(y: .value("Warning", tempWarningThresholdC))
                .foregroundStyle(Signal.warning.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .mutedAxes()
    }
}

/// Card frame with title, current value and a fixed-height chart.
private struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(subtitle)
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
            }
            content
                .frame(height: 152)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nativeCard()
    }
}

/// Line chart with a faint fill below the line.
private struct AreaLineChart: View {
    let samples: [MinerTelemetrySample]
    let label: String
    let tint: Color
    var includesZero = false
    let value: (MinerTelemetrySample) -> Double

    var body: some View {
        Chart(samples) { sample in
            AreaMark(x: .value("Time", sample.timestamp), y: .value(label, value(sample)))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint.opacity(0.08))
            LineMark(x: .value("Time", sample.timestamp), y: .value(label, value(sample)))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .chartYScale(domain: .automatic(includesZero: includesZero))
        .mutedAxes()
    }
}

extension View {
    /// Hairline grid and small mono labels in the tertiary text color.
    func mutedAxes() -> some View {
        self
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.mono(10))
                        .foregroundStyle(Color.mutedLabel)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel()
                        .font(.mono(10))
                        .foregroundStyle(Color.mutedLabel)
                }
            }
    }
}
