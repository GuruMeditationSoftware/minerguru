import SwiftUI
import WidgetKit

struct FleetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FleetEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FleetEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
            return
        }
        Task { completion(await SnapshotLoader.entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FleetEntry>) -> Void) {
        Task {
            let entry = await SnapshotLoader.entry()
            completion(Timeline(entries: [entry], policy: .after(SnapshotLoader.nextUpdate(after: entry.date))))
        }
    }
}

/// The fleet at a glance: small and medium show the total, large lists the miners.
struct FleetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Fleet", provider: FleetProvider()) { entry in
            FleetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetCommand.openOverview.url)
        }
        .configurationDisplayName(LocalizedStringResource("Fleet"))
        .description(LocalizedStringResource("Total hashrate, state and power of all miners."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FleetWidgetView: View {
    let entry: FleetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.source == .empty {
            EmptyFleetView(text: entry.text)
        } else {
            switch family {
            case .systemMedium: FleetMedium(entry: entry)
            case .systemLarge: FleetLarge(entry: entry)
            default: FleetSmall(entry: entry)
            }
        }
    }
}

// MARK: - Parts

/// "■ 5/5" or "■ 5/5 online", with the shape of the worst state in the fleet.
struct FleetCount: View {
    let entry: FleetEntry
    var showsWord = false

    var body: some View {
        let s = entry.snapshot
        let online = entry.source == .stale ? "–" : "\(s.onlineMiners.count)"
        HStack(spacing: 4) {
            StatusBlock(look: fleetLook, size: 7)
            Text(showsWord ? entry.text.format("%@/%d online", online, s.miners.count) : "\(online)/\(s.miners.count)")
                .font(.mono(11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var fleetLook: MinerLook {
        let s = entry.snapshot
        if entry.source == .stale { return .checking }
        if !s.offlineMiners.isEmpty { return .offline }
        if !s.hotMiners.isEmpty { return .hot }
        return s.onlineMiners.isEmpty ? .checking : .online
    }
}

/// The line under the figure: a problem if there is one, else power and efficiency.
struct FleetStatusLine: View {
    let entry: FleetEntry
    /// Shown when nothing is wrong; power and efficiency if not given.
    var calm: String? = nil

    var body: some View {
        let s = entry.snapshot
        let text = entry.text
        Group {
            if entry.source == .stale {
                Text(text.format("As of %@", text.time(s.date)))
            } else if let hot = s.hotMiners.first {
                HStack(spacing: 4) {
                    StatusBlock(look: .hot, size: 7)
                    Text("\(hot.name) · \(text.temperature(hot.tempC ?? 0))")
                }
            } else if let offline = s.offlineMiners.first {
                HStack(spacing: 4) {
                    StatusBlock(look: .offline, size: 7)
                    Text(text.format("%@ offline", offline.name))
                }
            } else {
                Text(calm ?? text.powerLine(s))
            }
        }
        .font(.mono(11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private func fleetFigure(_ entry: FleetEntry, size: CGFloat) -> some View {
    let split = WidgetText.hashrate(entry.snapshot.totalHashRateGHs)
    return Figure(value: split.value, unit: split.unit, size: size)
        .opacity(entry.source == .stale ? 0.45 : 1)
}

// MARK: - Sizes

struct FleetSmall: View {
    let entry: FleetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: entry.text("Fleet")) { FleetCount(entry: entry) }
            fleetFigure(entry, size: 30)
                .padding(.top, 2)
            Sparkline(values: entry.snapshot.fleetHourlyGHs)
                .frame(maxHeight: .infinity)
            FleetStatusLine(entry: entry)
        }
    }
}

struct FleetMedium: View {
    let entry: FleetEntry

    var body: some View {
        let s = entry.snapshot
        let text = entry.text
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: text("Fleet")) {
                FleetCount(entry: entry, showsWord: true)
                Text(text.time(s.date))
                    .font(.mono(11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
            }
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    fleetFigure(entry, size: 30)
                    FleetStatusLine(entry: entry, calm: text.format("%d miners active", s.onlineMiners.count))
                }
                .layoutPriority(1)
                VStack(alignment: .trailing, spacing: 2) {
                    Sparkline(values: s.fleetHourlyGHs)
                    Text("24 h").font(.mono(10)).foregroundStyle(.tertiary)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Stat(title: text("Power"), value: s.totalPowerW > 0 ? text.watts(s.totalPowerW) : "–")
                Stat(title: text("Efficiency"), value: s.efficiencyJPerTH.map(text.efficiency) ?? "–")
                Stat(title: text("Best Diff"), value: s.bestDiff ?? "–")
                Stat(title: text("Ø Ping"), value: s.pingMs.map(text.milliseconds) ?? "–")
            }
        }
    }
}

struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FleetLarge: View {
    let entry: FleetEntry
    /// Rows that fit the large size.
    static let maxRows = 6

    var body: some View {
        let s = entry.snapshot
        let text = entry.text
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: text("Fleet")) { FleetCount(entry: entry, showsWord: true) }
            HStack(alignment: .bottom, spacing: 14) {
                fleetFigure(entry, size: 30)
                    .layoutPriority(1)
                Sparkline(values: s.fleetHourlyGHs)
                    .frame(height: 34)
            }
            VStack(spacing: 0) {
                ForEach(Array(sortedMiners.prefix(Self.maxRows).enumerated()), id: \.element.id) { index, miner in
                    if index > 0 { Divider() }
                    MinerRow(miner: miner, entry: entry)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            HStack {
                Text(sortedMiners.count > Self.maxRows
                     ? text.format("%d more", sortedMiners.count - Self.maxRows) + " · " + text.powerLine(s)
                     : text.powerLine(s))
                Spacer()
                Text(entry.source == .stale ? text.format("As of %@", text.time(s.date)) : text.time(s.date))
            }
            .font(.mono(11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    /// Problems first, then the strongest miners.
    private var sortedMiners: [WidgetSnapshot.Miner] {
        let s = entry.snapshot
        func rank(_ m: WidgetSnapshot.Miner) -> Int {
            switch MinerLook(m, warningC: s.tempWarningC) {
            case .offline: return 0
            case .hot: return 1
            case .checking: return 2
            case .online: return 3
            }
        }
        return s.miners.sorted { (rank($0), -$0.hashRateGHs) < (rank($1), -$1.hashRateGHs) }
    }
}

struct MinerRow: View {
    let miner: WidgetSnapshot.Miner
    let entry: FleetEntry

    var body: some View {
        Link(destination: WidgetCommand.openMiner(miner.id).url) {
            MinerRowContent(miner: miner, entry: entry)
        }
    }
}

struct MinerRowContent: View {
    let miner: WidgetSnapshot.Miner
    let entry: FleetEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let text = entry.text
        let look = entry.source == .stale ? MinerLook.checking : MinerLook(miner, warningC: entry.snapshot.tempWarningC)
        HStack(spacing: 8) {
            StatusBlock(look: look, size: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(miner.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(miner.model).font(.mono(10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text(miner.state == .online ? WidgetText.hashrateText(miner.hashRateGHs) : text("offline"))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                Text(miner.tempC.map(text.temperature) ?? "–")
                    .font(.mono(10))
                    .foregroundStyle(look == .hot ? AnyShapeStyle(Palette(scheme: scheme).warning) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.vertical, 5)
    }
}

/// No miners yet: a hint to start the scan in the app.
struct EmptyFleetView: View {
    let text: WidgetText

    var body: some View {
        VStack(spacing: 8) {
            Mark(size: 28)
            Text(text("No miners yet"))
                .font(.system(size: 13, weight: .semibold))
            Text(text("Click to scan the network in MinerGuru"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
