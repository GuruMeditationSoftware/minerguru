import SwiftUI
import Charts

/// Scatter chart of the difficulty of every ASIC result over time (log scale), with the pool difficulty
/// as reference line. Results above the line were submitted as shares.
struct ShareDifficultyChartCard: View {
    @ObservedObject var tracker: ShareDifficultyTracker
    let isLiveLogRunning: Bool

    private var samples: [ShareSample] { tracker.samples }
    private var poolDifficulties: [Double] {
        Array(Set(samples.compactMap(\.poolDifficulty))).sorted()
    }
    private var hasPools: Bool { samples.contains { $0.pool != nil } }

    /// Longer pauses between two results break the line (sampling mode: one window per minute).
    private static let maxLineGap: TimeInterval = 20

    private func poolLabel(_ sample: ShareSample) -> String {
        hasPools ? (sample.pool?.rawValue ?? "Pool") : "Share"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Difficulty pro Share", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let best = samples.map(\.difficulty).max() {
                    Text("Bester: \(MinerSystemInfo.formatDifficultyNumber(best))")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Group {
                if samples.isEmpty {
                    ContentUnavailableView {
                        Label(tracker.isSampling ? "Sammle Shares…" : "Noch keine Shares", systemImage: "chart.dots.scatter")
                            .font(.callout)
                    } description: {
                        Text("Die erste Stichprobe dauert etwa \(Int(ShareDifficultyTracker.sampleWindow.components.seconds)) Sekunden.")
                            .font(.caption)
                    }
                } else {
                    chart
                }
            }
            .frame(height: 190)

            HStack(spacing: 6) {
                Circle()
                    .fill(isLiveLogRunning ? Signal.good : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(sourceText)
                Spacer()
                Text("\(samples.count) Ergebnisse • \(samples.filter(\.isSubmitted).count) über Pool-Difficulty")
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }

    private var sourceText: String {
        if isLiveLogRunning { return String(localized: "Live aus dem Live-Log") }
        if tracker.isSampling { return String(localized: "Stichprobe läuft…") }
        let interval = Int(ShareDifficultyTracker.sampleInterval.components.seconds)
        if let last = tracker.lastSampleDate {
            return String(localized: "Stichprobe alle \(interval) s • zuletzt \(last.formatted(date: .omitted, time: .standard))")
        }
        return String(localized: "Stichprobe alle \(interval) s")
    }

    private var chart: some View {
        Chart {
            ForEach(poolDifficulties, id: \.self) { target in
                RuleMark(y: .value("Pool-Difficulty", target))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Pool \(MinerSystemInfo.formatDifficultyNumber(target))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }

            let series = ShareSample.lineSeries(for: samples, maxGap: Self.maxLineGap)
            ForEach(Array(zip(samples, series)), id: \.0.id) { sample, seriesKey in
                LineMark(
                    x: .value("Zeit", sample.date),
                    y: .value("Difficulty", sample.difficulty),
                    series: .value("Verlauf", seriesKey)
                )
                .interpolationMethod(.linear) // straight segments: no invented values between results
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .foregroundStyle(by: .value("Pool", poolLabel(sample)))

                // Shares that reached the pool difficulty (sent to the pool) stay visible as dots.
                if sample.isSubmitted {
                    PointMark(
                        x: .value("Zeit", sample.date),
                        y: .value("Difficulty", sample.difficulty)
                    )
                    .symbolSize(28)
                    .foregroundStyle(by: .value("Pool", poolLabel(sample)))
                }
            }
        }
        .chartYScale(type: .log)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(MinerSystemInfo.formatDifficultyNumber(v))
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: hasPools ? ["Pool 1", "Pool 2"] : ["Share"],
                                   range: hasPools ? [Accent.color, Color.secondary] : [Accent.color])
        .chartLegend(hasPools ? .visible : .hidden)
    }
}
