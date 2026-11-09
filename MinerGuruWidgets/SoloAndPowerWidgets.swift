import SwiftUI
import WidgetKit

// MARK: - Solo chance

/// Odds of finding a block solo with the whole fleet, per coin, as the app computes them.
struct SoloWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Solo", provider: FleetProvider()) { entry in
            SoloWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetCommand.openOverview.url)
        }
        .configurationDisplayName(LocalizedStringResource("Solo chance"))
        .description(LocalizedStringResource("How likely the fleet finds a block solo, for every coin."))
        .supportedFamilies([.systemSmall])
    }
}

struct SoloWidgetView: View {
    let entry: FleetEntry
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let coins = entry.source == .empty ? [] : entry.snapshot.solo
        if coins.count > 1 {
            several(coins)
        } else {
            single(coins.first)
        }
    }

    /// One coin: its odds large, with the expected time per block.
    private func single(_ solo: WidgetSnapshot.Solo?) -> some View {
        let text = entry.text
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette(scheme: scheme).coin(solo?.coin ?? "BTC"))
                    .frame(width: 8, height: 8)
                    .widgetAccentable()
                Text(text("Solo chance"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(solo?.coin ?? "")
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(solo?.odds ?? "–")
                .font(.figure(26))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .widgetAccentable()
                .opacity(entry.source == .stale ? 0.45 : 1)
            Text(solo?.period ?? text("No miners online"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let solo {
                Text(text("Ø 1 block every"))
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                Text(solo.blockEvery)
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Several coins: a row each, Bitcoin and the largest first, as many as fit.
    private func several(_ coins: [WidgetSnapshot.Solo]) -> some View {
        let text = entry.text
        let palette = Palette(scheme: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            Text(text("Solo chance"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(coins[0].period)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            ForEach(coins.prefix(3), id: \.coin) { solo in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(palette.coin(solo.coin))
                            .frame(width: 7, height: 7)
                            .widgetAccentable()
                        Text(solo.coin)
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                    }
                    Text(solo.odds)
                        .font(.figure(coins.count > 2 ? 15 : 19))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                        .opacity(entry.source == .stale ? 0.45 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Power

/// Draw now, efficiency, energy and cost of the day, and the energy per hour of today.
struct PowerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Power", provider: FleetProvider()) { entry in
            PowerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetCommand.openPower.url)
        }
        .configurationDisplayName(LocalizedStringResource("Power (section)"))
        .description(LocalizedStringResource("Power, energy and cost of the fleet today."))
        .supportedFamilies([.systemMedium])
    }
}

struct PowerWidgetView: View {
    let entry: FleetEntry

    var body: some View {
        let s = entry.snapshot
        let text = entry.text
        if entry.source == .empty {
            EmptyFleetView(text: text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(text("Power (section)"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(text("today"))
                        .font(.mono(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if s.nightModeOn {
                        Label(text("Night mode"), systemImage: "moon.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Figure(value: text.decimal(s.totalPowerW, digits: 0), unit: "W", size: 30)
                            .opacity(entry.source == .stale ? 0.45 : 1)
                        Text(s.efficiencyJPerTH.map(text.efficiency) ?? "–")
                            .font(.mono(11))
                            .foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                    Stat(title: text("Energy / day"), value: s.energyPerDayKWh.map(text.energy) ?? "–")
                    Stat(title: text("Cost today"), value: s.costToday ?? "–")
                }
                EnergyBars(hours: s.energyHourlyKWh)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

/// 24 bars, one per hour of today; the running hour is drawn darker, hours to come as stubs.
struct EnergyBars: View {
    let hours: [Double?]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme: scheme)
        let values = hours.count == 24 ? hours : [Double?](repeating: nil, count: 24)
        let peak = max(values.compactMap { $0 }.max() ?? 0, 0.001)
        let current = values.lastIndex { $0 != nil }
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let value = values[hour]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(value == nil ? palette.track : (hour == current ? Color.primary : palette.bar))
                        .frame(height: value.map { max(3, geo.size.height * CGFloat($0 / peak)) } ?? 3)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(minHeight: 18, maxHeight: 30)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}
