import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

/// A miner from the app's snapshot, to pick in the widget's settings.
struct MinerEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Miner"
    static let defaultQuery = MinerQuery()

    var id: UUID
    var name: String
    var model: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(model)")
    }

    init(_ miner: WidgetSnapshot.Miner) {
        id = miner.id
        name = miner.name
        model = miner.model
    }
}

struct MinerQuery: EntityQuery {
    private var miners: [WidgetSnapshot.Miner] { WidgetSnapshot.load()?.miners ?? [] }

    func entities(for identifiers: [UUID]) async throws -> [MinerEntity] {
        miners.filter { identifiers.contains($0.id) }.map(MinerEntity.init)
    }

    func suggestedEntities() async throws -> [MinerEntity] {
        miners.map(MinerEntity.init)
    }

    func defaultResult() async -> MinerEntity? {
        miners.max { $0.hashRateGHs < $1.hashRateGHs }.map(MinerEntity.init)
    }
}

struct SelectMinerIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose miner"
    static let description = IntentDescription("Which miner the widget shows.")

    @Parameter(title: "Miner")
    var miner: MinerEntity?
}

// MARK: - Timeline

struct MinerEntry: TimelineEntry, Sendable {
    let date: Date
    let fleet: FleetEntry
    let minerID: UUID?

    /// The chosen miner, or the strongest one while none is chosen.
    var miner: WidgetSnapshot.Miner? {
        let miners = fleet.snapshot.miners
        if let minerID { return miners.first { $0.id == minerID } }
        return miners.max { $0.hashRateGHs < $1.hashRateGHs }
    }
}

struct MinerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MinerEntry {
        MinerEntry(date: .now, fleet: .preview, minerID: nil)
    }

    func snapshot(for configuration: SelectMinerIntent, in context: Context) async -> MinerEntry {
        if context.isPreview { return placeholder(in: context) }
        return MinerEntry(date: .now, fleet: await SnapshotLoader.entry(), minerID: configuration.miner?.id)
    }

    func timeline(for configuration: SelectMinerIntent, in context: Context) async -> Timeline<MinerEntry> {
        let fleet = await SnapshotLoader.entry()
        let entry = MinerEntry(date: fleet.date, fleet: fleet, minerID: configuration.miner?.id)
        return Timeline(entries: [entry], policy: .after(SnapshotLoader.nextUpdate(after: entry.date)))
    }
}

// MARK: - Widget

/// One miner: hashrate, chip temperature against the warning threshold, state.
struct MinerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Miner", intent: SelectMinerIntent.self, provider: MinerProvider()) { entry in
            MinerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.miner.map { WidgetCommand.openMiner($0.id).url } ?? WidgetCommand.openOverview.url)
        }
        .configurationDisplayName(LocalizedStringResource("Miner"))
        .description(LocalizedStringResource("One miner with hashrate and temperature. Pick which one when editing the widget."))
        .supportedFamilies([.systemSmall])
    }
}

struct MinerWidgetView: View {
    let entry: MinerEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let text = entry.fleet.text
        if let miner = entry.miner {
            let stale = entry.fleet.source == .stale
            let look = stale ? MinerLook.checking : MinerLook(miner, warningC: entry.fleet.snapshot.tempWarningC)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    StatusBlock(look: look, size: 9)
                    Spacer()
                    Mark(size: 13)
                }
                Spacer(minLength: 6)
                Text(miner.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(miner.model)
                    .font(.mono(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if miner.state == .online || stale {
                    let split = WidgetText.hashrate(miner.hashRateGHs)
                    Figure(value: split.value, unit: split.unit, size: 28)
                        .opacity(stale ? 0.45 : 1)
                } else {
                    Text(text("offline"))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(look.color(Palette(scheme: scheme)))
                }
                Spacer(minLength: 6)
                HStack(spacing: 8) {
                    Text(stale ? text.format("As of %@", text.time(entry.fleet.snapshot.date))
                         : miner.state == .offline ? miner.host : miner.tempC.map(text.temperature) ?? "–")
                        .font(.mono(11))
                        .foregroundStyle(look == .hot ? AnyShapeStyle(look.color(Palette(scheme: scheme))) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                    if !stale, miner.state == .online, let temp = miner.tempC {
                        TemperatureBar(temp: temp, warning: entry.fleet.snapshot.tempWarningC, look: look)
                    }
                }
            }
        } else {
            EmptyFleetView(text: text)
        }
    }
}

/// Chip temperature on a scale from 30 °C to 10 °C past the warning threshold; the tick marks the threshold.
struct TemperatureBar: View {
    let temp: Double
    let warning: Double
    let look: MinerLook
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let low = 30.0, high = warning + 10
        let fraction = min(max((temp - low) / (high - low), 0.04), 1)
        let tick = (warning - low) / (high - low)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(look == .hot ? palette.warning : palette.bar)
                    .frame(width: geo.size.width * fraction)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1, height: geo.size.height + 4)
                    .offset(x: geo.size.width * tick)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
