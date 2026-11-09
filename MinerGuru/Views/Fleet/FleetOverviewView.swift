import SwiftUI
import Charts
import AppKit

struct FleetOverviewView: View {
    @ObservedObject var store: MinerStore
    @Environment(\.redactor) private var redactor

    var body: some View {
        PageScrollView(spacing: 32) {
            Group {
                UpdateBanner(updates: store.updates)
                if store.miners.isEmpty {
                    FleetOnboardingView(store: store)
                } else {
                    HStack {
                        Spacer()
                        SupportDevelopmentButton()
                    }
                    .padding(.bottom, -20)
                    soloChanceSection
                    fleetSection
                    minersGridSection
                    PoolOverviewTable(store: store)
                }
            }
        }
        .navigationTitle("Fleet")
        .navigationSubtitle(
            store.miners.isEmpty
                ? "Local network \(redactor.ip(store.scanner.subnetPrefix)).0/24"
                : "\(store.onlineMiners.count) of \(store.miners.count) miners online"
        )
    }

    // MARK: - Solo-mining odds

    private var soloChanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Solo odds")
                        .font(.system(size: 20, weight: .medium))
                    Text("Probability of finding a block with the current fleet hashrate")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Picker("Timeframe", selection: $store.soloChanceTimeframe) {
                    ForEach(SoloChanceTimeframe.allCases) { tf in
                        Text(tf.title).tag(tf)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            AdaptiveGrid(minColumnWidth: 340, spacing: 16) {
                ForEach(store.activeFleetCoinSummaries) { summary in
                    CoinSoloChanceCard(summary: summary, timeframe: store.soloChanceTimeframe)
                }
            }
        }
    }

    // MARK: - Fleet: hashrate, boards, chart and key figures

    private var fleetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fleet")
                        .font(.system(size: 20, weight: .medium))
                    Text(fleetMetaLine)
                        .font(.mono(11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        store.showScannerSheet = true
                    } label: {
                        Label("Scan Network", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Button {
                        store.showAddIPSheet = true
                    } label: {
                        Label("Add IP", systemImage: "plus")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) {
                        hashrateFigure
                        FleetHashrateChart(samples: store.fleetHistory)
                            .frame(height: 148)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    DeviceCardStack(cards: stackCards, width: 176)
                        .padding(.top, 8)
                }
                .padding(24)

                Divider()

                fleetFigures
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .nativeCard(cornerRadius: 16)
        }
    }

    private var fleetMetaLine: String {
        var parts = [String(localized: "\(store.onlineMiners.count) of \(store.miners.count) online")]
        let offline = store.miners.count - store.onlineMiners.count
        if offline > 0 {
            parts.append(String(localized: "\(offline) offline"))
        }
        if let last = store.lastGlobalRefresh {
            parts.append(String(localized: "updated \(last.formatted(date: .omitted, time: .standard))"))
        }
        return parts.joined(separator: " · ")
    }

    private var hashrateFigure: some View {
        let split = MinerFormatting.splitHashrate(store.totalHashrateGHs)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Total hashrate")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(split.value)
                    .font(.figure(44))
                Text(split.unit)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }
            Text(String(format: String(localized: "%.0f GH/s · %lld miners active"), store.totalHashrateGHs, store.onlineMiners.count))
                .font(.mono(11))
                .foregroundStyle(.tertiary)
        }
    }

    /// The three strongest online miners, the strongest in front.
    private var stackCards: [(spec: DeviceCardSpec, led: DeviceCardView.LED?)] {
        let ranked = store.onlineMiners.sorted { ($0.latestInfo?.hashRate ?? 0) > ($1.latestInfo?.hashRate ?? 0) }
        let miners = ranked.isEmpty ? store.miners : ranked
        return miners.prefix(3).map { miner in
            let hot = (miner.latestInfo?.temp ?? 0) >= store.tempWarningThresholdC
            return (DeviceCardSpec(miner: miner), DeviceCardView.LED(state: miner.connectionState, isHighTemp: hot))
        }
    }

    private var fleetFigures: some View {
        let totalAcc = store.totalSharesAccepted
        let totalRej = store.totalSharesRejected
        let rejRate = (totalAcc + totalRej) > 0 ? Double(totalRej) / Double(totalAcc + totalRej) * 100 : 0
        let latency = store.averagePoolLatencyMs

        return HStack(alignment: .top, spacing: 0) {
            FleetFigure(
                title: "Power",
                value: DisplayFormat.decimal(store.totalPowerWatts, fractionDigits: 1),
                unit: "W",
                detail: String(localized: "\(DisplayFormat.decimal(store.totalPowerWatts * 24 / 1000, fractionDigits: 2)) kWh per day")
            )
            figureDivider
            FleetFigure(
                title: "Efficiency",
                value: store.fleetEfficiencyJPerTH > 0 ? DisplayFormat.decimal(store.fleetEfficiencyJPerTH, fractionDigits: 1) : "—",
                unit: "J/TH",
                detail: String(localized: "Energy per terahash")
            )
            figureDivider
            FleetFigure(
                title: "Shares",
                value: totalAcc.formatted(.number.locale(DisplayFormat.locale)),
                unit: nil,
                detail: String(localized: "\(totalRej) rejected · \(DisplayFormat.percent(rejRate, fractionDigits: 2))")
            )
            figureDivider
            FleetFigure(
                title: "Best diff since restart",
                value: MinerSystemInfo.formatSessionBest(store.bestSessionMiner?.difficulty),
                unit: nil,
                detail: String(localized: "All-time \(store.highestBestDiffFormatted)")
            )
            figureDivider
            FleetFigure(
                title: "Ø Pool latency",
                value: latency.map { DisplayFormat.decimal($0, fractionDigits: 0) } ?? "—",
                unit: latency != nil ? "ms" : nil,
                detail: LatencyQuality.evaluate(latency).label
            )
        }
    }

    private var figureDivider: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(width: 1)
            .padding(.horizontal, 20)
    }

    // MARK: - Miner cards

    private var minersGridSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Miners")
                    .font(.system(size: 20, weight: .medium))
                Text("\(store.miners.count)")
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
            }

            AdaptiveGrid(minColumnWidth: 340, spacing: 16) {
                ForEach(store.miners) { miner in
                    MinerSummaryCard(
                        miner: miner,
                        tempWarningThreshold: store.tempWarningThresholdC,
                        onSelect: {
                            store.selection = .miner(miner.id)
                        },
                        onRestart: {
                            Task { await store.restartMiner(minerID: miner.id) }
                        },
                        onRemove: {
                            store.removeMiner(id: miner.id)
                        }
                    )
                }
            }
        }
    }
}

/// One key figure in the strip under the fleet chart: label, figure with unit, a mono detail line.
private struct FleetFigure: View {
    let title: LocalizedStringKey
    let value: String
    let unit: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.figure(20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.mono(11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fleet hashrate over the last refresh rounds: one accent line on a muted grid.
struct FleetHashrateChart: View {
    let samples: [FleetHashrateSample]

    /// Seconds on the axis while the history covers only a few minutes, so labels do not repeat.
    static func timeFormat(for samples: [FleetHashrateSample]) -> Date.FormatStyle {
        let span = (samples.last?.timestamp ?? .now).timeIntervalSince(samples.first?.timestamp ?? .now)
        return span < 600 ? .dateTime.hour().minute().second() : .dateTime.hour().minute()
    }

    var body: some View {
        if samples.count < 2 {
            Text("The history fills in with every refresh")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
        } else {
            let values = samples.map(\.hashRateGHs)
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let pad = max((high - low) * 0.6, high * 0.02, 1)
            let domain = max(0, low - pad)...(high + pad)

            Chart(samples) { sample in
                AreaMark(
                    x: .value("Time", sample.timestamp),
                    yStart: .value("Base", domain.lowerBound),
                    yEnd: .value("GH/s", sample.hashRateGHs)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Accent.color.opacity(0.08))

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("GH/s", sample.hashRateGHs)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Accent.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: Self.timeFormat(for: samples))
                                .font(.mono(10))
                                .foregroundStyle(Color.mutedLabel)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel {
                        if let ghs = value.as(Double.self) {
                            Text(MinerFormatting.formatHashrate(ghs))
                                .font(.mono(10))
                                .foregroundStyle(Color.mutedLabel)
                        }
                    }
                }
            }
        }
    }
}
