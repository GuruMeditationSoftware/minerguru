import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

/// Stored telemetry of one miner over days and months, from the local history database.
struct LongTermHistoryCard: View {
    let history: HistoryStore
    let miner: MinerDevice

    @AppStorage("MinerGuru.LongTermRange") private var range = HistoryRange.week
    @AppStorage("MinerGuru.LongTermMetric") private var metric = HistoryMetric.hashrate
    @State private var points: [HistoryPoint] = []

    private var values: [Double] { points.compactMap(metric.value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Long-term history")
                    .font(.system(size: 20, weight: .medium))
                Spacer()
                Picker("Timeframe", selection: $range) {
                    ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Metric", selection: $metric) {
                        ForEach(HistoryMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button {
                        Task { await exportCSV() }
                    } label: {
                        Label("CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(points.isEmpty)
                    .help("Save history as CSV")
                }

                if values.isEmpty {
                    Text("No data for this period yet. MinerGuru records while the app is running.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    chart.frame(height: 170)
                    stats
                }
            }
            .padding(16)
            .nativeCard()
        }
        .task(id: "\(miner.id)-\(range.rawValue)") { await load() }
    }

    private var chart: some View {
        // One snapshot for the whole chart: Charts runs these closures later, when the state may have moved on.
        let metric = metric
        let segments = Array(metric.segments(of: points, in: range).enumerated())
        return Chart {
            ForEach(segments, id: \.offset) { index, segment in
                ForEach(segment) { point in
                    if let value = metric.value(point) {
                        LineMark(x: .value("Time", point.date), y: .value(metric.title, value), series: .value("Segment", index))
                            .foregroundStyle(Accent.color)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: metric == .errors))
        .mutedAxes()
    }

    private var stats: some View {
        HStack(spacing: 24) {
            stat("Ø", metric.format(values.reduce(0, +) / Double(values.count)))
            stat("Min", metric.format(values.min() ?? 0))
            stat("Max", metric.format(values.max() ?? 0))
            if let uptime {
                stat("Uptime", DisplayFormat.decimal(uptime, fractionDigits: 1) + " %")
            }
            Spacer()
        }
    }

    private var uptime: Double? {
        let recorded = points.reduce(0) { $0 + $1.recordedMinutes }
        guard recorded > 0 else { return nil }
        return Double(points.reduce(0) { $0 + $1.onlineMinutes }) / Double(recorded) * 100
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.mono(12))
        }
    }

    private func load() async {
        let now = Date()
        points = await history.points(minerID: miner.id, from: now.addingTimeInterval(-range.seconds), to: now)
    }

    private func exportCSV() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(miner.displayName)-\(range.rawValue).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = miner.displayName
        do {
            try HistoryCSV.text(points: points, minerName: { _ in name }).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
