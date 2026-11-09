import SwiftUI

/// Power page (MG-14): the user's own tariff, schedules that switch the miners, and the costs per miner and fleet.
struct PowerView: View {
    @ObservedObject var store: MinerStore
    @ObservedObject private var power: PowerStore
    @Environment(\.redactor) private var redactor

    @State private var editingZone: EditingZone?
    @State private var editingRule: EditingRule?

    private struct EditingZone: Identifiable {
        var zone: TariffZone
        let isNew: Bool
        var id: UUID { zone.id }
    }

    private struct EditingRule: Identifiable {
        var rule: ScheduleRule
        let isNew: Bool
        var id: UUID { rule.id }
    }

    init(store: MinerStore) {
        self.store = store
        self._power = ObservedObject(wrappedValue: store.power)
    }

    var body: some View {
        // Re-render once a minute, so the current zone and the costs follow the clock.
        TimelineView(.everyMinute) { context in
            PageScrollView {
                figures(now: context.date)
                tariffCard(now: context.date)
                schedulesCard
                minersCard(now: context.date)
            }
        }
        .navigationTitle("Power (section)")
        .navigationSubtitle("Tariff, schedules and costs")
        .sheet(item: $editingZone) { item in
            TariffZoneEditorSheet(zone: item.zone, isNew: item.isNew, currencyCode: power.tariff.currencyCode) { saved in
                if let idx = power.tariff.zones.firstIndex(where: { $0.id == saved.id }) {
                    power.tariff.zones[idx] = saved
                } else {
                    power.tariff.zones.append(saved)
                }
            }
        }
        .sheet(item: $editingRule) { item in
            ScheduleRuleEditorSheet(rule: item.rule, isNew: item.isNew, zones: power.tariff.zones, miners: store.miners) { saved in
                if let idx = power.rules.firstIndex(where: { $0.id == saved.id }) {
                    power.rules[idx] = saved
                } else {
                    power.rules.append(saved)
                }
            }
        }
    }

    // MARK: - Figures

    private var fleetWatts: Double { store.totalPowerWatts }

    private func fleetCost(hours: Double, from start: Date) -> Double {
        store.onlineMiners.reduce(0) { $0 + power.projectedCost(for: $1, hours: hours, from: start) }
    }

    private func figures(now: Date) -> some View {
        let tariff = power.tariff
        let zone = tariff.zone(at: now)
        let today = fleetCost(hours: 24, from: Calendar.current.startOfDay(for: now))
        let month = fleetCost(hours: 24 * 30, from: now)
        let totalTH = store.totalHashrateGHs / 1000
        return AdaptiveGrid(minColumnWidth: 180) {
            PowerFigure(
                label: "Price now",
                value: tariff.formatPrice(tariff.price(at: now), digits: 3),
                detail: zone.map { "\($0.name) · \($0.window.timeRangeText)" }
                    ?? (tariff.hasZones ? String(localized: "Standard price") : String(localized: "Fixed price"))
            )
            PowerFigure(
                label: "Power",
                value: String(format: "%.0f W", fleetWatts),
                detail: String(localized: "\(store.onlineMiners.count) miners online")
            )
            PowerFigure(
                label: "Cost per hour",
                value: tariff.formatPrice(power.costPerHour(watts: fleetWatts, at: now), digits: 3),
                detail: String(localized: "at the current draw")
            )
            PowerFigure(
                label: "Today",
                value: tariff.formatPrice(today),
                detail: String(localized: "midnight to midnight, projected")
            )
            PowerFigure(
                label: "30 days",
                value: tariff.formatPrice(month),
                detail: totalTH > 0.01
                    ? String(localized: "\(tariff.formatPrice(month / totalTH)) per TH/s")
                    : String(localized: "with prices and pauses")
            )
        }
    }

    // MARK: - Tariff

    private func tariffCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Tariff", systemImage: "bolt.badge.clock")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Menu {
                    Button("Night and day (off-peak/peak)") { addTemplate(.dayNight) }
                    Button("Cheaper weekends") { addTemplate(.weekend) }
                } label: {
                    Label("Template", systemImage: "square.on.square")
                }
                .fixedSize()
                .help("Add typical zones, then adjust the prices")
                Button {
                    editingZone = EditingZone(zone: newZone(), isNew: true)
                } label: {
                    Label("Add Zone", systemImage: "plus")
                }
                .help("Add a time zone with its own price, e.g. a night rate")
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                LabeledContent("Currency") {
                    TextField("EUR", text: currencyBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                }
                LabeledContent(power.tariff.hasZones ? "Standard price per kWh" : "Price per kWh") {
                    TextField("0.30", value: $power.tariff.basePricePerKWh, format: .number.precision(.fractionLength(2...4)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                }
                Spacer()
            }
            .fixedSize(horizontal: false, vertical: true)

            if power.tariff.hasZones {
                VStack(spacing: 0) {
                    ForEach(Array(power.tariff.zones.enumerated()), id: \.element.id) { index, zone in
                        zoneRow(zone, index: index, isNow: power.tariff.zone(at: now)?.id == zone.id)
                        if zone.id != power.tariff.zones.last?.id { Divider() }
                    }
                }
            } else {
                Text("A fixed price applies around the clock. With zones, nights, weekends or peak hours get prices of their own, and schedules can follow them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WeekTariffBar(tariff: power.tariff, now: now)

            if !power.tariff.overlappingZones.isEmpty || power.tariff.hasGaps {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(power.tariff.overlappingZones, id: \.0.id) { pair in
                        hint("“\(pair.0.name)” and “\(pair.1.name)” overlap. There “\(pair.0.name)” applies because it is higher up.",
                             systemImage: "exclamationmark.triangle", color: Signal.warning)
                    }
                    if power.tariff.hasGaps {
                        hint("Times without a zone cost the standard price (grey in the week bar).",
                             systemImage: "info.circle", color: .secondary)
                    }
                }
            }
        }
        .padding(16)
        .nativeCard()
    }

    private func zoneRow(_ zone: TariffZone, index: Int, isNow: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ZonePalette.color(index))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(zone.name).font(.subheadline.weight(.medium))
                    if isNow {
                        Text("now")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Accent.color)
                    }
                }
                Text("\(WeekdayOrder.summary(zone.window.weekdays)) · \(zone.window.timeRangeText)")
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(power.tariff.formatPrice(zone.pricePerKWh, digits: 3) + " / kWh")
                .font(.mono(12))
                .foregroundStyle(.secondary)
            let ruleCount = power.rules.filter { $0.trigger == .zone(zone.id) }.count
            if ruleCount > 0 {
                Text(ruleCount == 1 ? "1 schedule" : "\(ruleCount) schedules")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Button {
                moveZone(at: index, by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move up: wins where zones overlap")
            Button {
                editingZone = EditingZone(zone: zone, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            Button(role: .destructive) {
                power.removeZone(id: zone.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete zone; schedules for this zone are removed with it")
        }
        .padding(.vertical, 8)
    }

    private var currencyBinding: Binding<String> {
        Binding {
            power.tariff.currencyCode
        } set: { value in
            let code = String(value.uppercased().filter(\.isLetter).prefix(3))
            if code.count == 3 { power.tariff.currencyCode = code }
        }
    }

    private func moveZone(at index: Int, by offset: Int) {
        let target = index + offset
        guard power.tariff.zones.indices.contains(target) else { return }
        power.tariff.zones.swapAt(index, target)
    }

    private func newZone() -> TariffZone {
        TariffZone(
            name: String(localized: "Night"),
            pricePerKWh: power.tariff.basePricePerKWh,
            window: WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 22 * 60, endMinute: 6 * 60)
        )
    }

    private enum Template { case dayNight, weekend }

    private func addTemplate(_ template: Template) {
        let base = power.tariff.basePricePerKWh
        switch template {
        case .dayNight:
            power.tariff.zones.append(TariffZone(
                name: String(localized: "Night"), pricePerKWh: (base * 0.8 * 1000).rounded() / 1000,
                window: WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 22 * 60, endMinute: 6 * 60)))
            power.tariff.zones.append(TariffZone(
                name: String(localized: "Day"), pricePerKWh: base,
                window: WeeklyWindow(weekdays: WeekdayOrder.workdays, startMinute: 6 * 60, endMinute: 22 * 60)))
        case .weekend:
            power.tariff.zones.append(TariffZone(
                name: String(localized: "Weekend"), pricePerKWh: (base * 0.8 * 1000).rounded() / 1000,
                window: WeeklyWindow(weekdays: WeekdayOrder.weekend, startMinute: 0, endMinute: 0)))
        }
    }

    // MARK: - Schedules

    private var schedulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Schedules", systemImage: "calendar.badge.clock")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Button {
                    editingRule = EditingRule(rule: newRule(), isNew: true)
                } label: {
                    Label("Add Schedule", systemImage: "plus")
                }
                .disabled(store.miners.isEmpty)
                .help("Send miners into night mode or pause them during a tariff zone or at set times")
            }

            if power.rules.isEmpty {
                Text("No schedules yet. A schedule puts miners into night mode or pauses them during a tariff zone or at set times; afterwards they return to their own settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(power.rules.enumerated()), id: \.element.id) { index, rule in
                        ruleRow(rule, index: index)
                        if rule.id != power.rules.last?.id { Divider() }
                    }
                }
            }

            Divider()

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("This Mac runs the schedules", isOn: $power.runsSchedules)
                    Text("Only one device should switch, otherwise the Mac and the phone work against each other. A sleeping Mac does not switch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Night mode for all miners now", isOn: $power.manualNight)
                        .padding(.top, 8)
                    Text("Stays on until you switch it off again, also from Control Center. A scheduled pause stays a pause.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Fan in night mode")
                        Text(verbatim: "\(power.nightFanPercent) %")
                            .monospacedDigit()
                        Stepper("Fan in night mode", value: $power.nightFanPercent, in: 20...100, step: 5)
                            .labelsHidden()
                    }
                    Text("Night mode lowers the clock to Eco and fixes the fan speed. Pause needs AxeOS 2.15; older AxeOS and NerdOS go into night mode instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 420, alignment: .leading)
            }

            OtpWaitingNotice(store: store)

            if let error = power.lastError {
                hint("Last switch failed: \(error)", systemImage: "exclamationmark.triangle", color: Signal.bad)
            }
        }
        .padding(16)
        .nativeCard()
    }

    private func ruleRow(_ rule: ScheduleRule, index: Int) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding {
                rule.isEnabled
            } set: { value in
                if let idx = power.rules.firstIndex(where: { $0.id == rule.id }) { power.rules[idx].isEnabled = value }
            })
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Image(systemName: rule.action.systemImage)
                .frame(width: 20)
                .foregroundStyle(rule.isEnabled ? .primary : .tertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(rule.action.title) · \(triggerText(rule.trigger))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text(minersText(rule))
                    .font(.mono(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            if rule.isActive(at: Date(), tariff: power.tariff) {
                Text("active")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Accent.color)
            }

            Button {
                guard index > 0 else { return }
                power.rules.swapAt(index, index - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .help("Move up: wins when several schedules apply at once")
            Button {
                editingRule = EditingRule(rule: rule, isNew: false)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit")
            Button(role: .destructive) {
                power.rules.removeAll { $0.id == rule.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete schedule")
        }
        .padding(.vertical, 8)
    }

    private func newRule() -> ScheduleRule {
        let trigger: ScheduleTrigger = power.tariff.zones.first.map { .zone($0.id) }
            ?? .window(WeeklyWindow(weekdays: WeekdayOrder.all, startMinute: 22 * 60, endMinute: 6 * 60))
        return ScheduleRule(trigger: trigger, action: .nightMode)
    }

    private func triggerText(_ trigger: ScheduleTrigger) -> String {
        switch trigger {
        case .zone(let id):
            guard let zone = power.zone(id: id) else { return String(localized: "zone deleted") }
            return String(localized: "during “\(zone.name)”")
        case .window(let window):
            return "\(WeekdayOrder.summary(window.weekdays)) \(window.timeRangeText)"
        }
    }

    private func minersText(_ rule: ScheduleRule) -> String {
        guard !rule.minerIDs.isEmpty else { return String(localized: "All miners") }
        let names = store.miners.filter { rule.minerIDs.contains($0.id) }.map { redactor.freeText($0.displayName) }
        return names.isEmpty ? String(localized: "Miner removed") : names.joined(separator: ", ")
    }

    // MARK: - Miners

    private func minersCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Cost per Miner", systemImage: "cpu")
                .font(.system(size: 15, weight: .medium))

            if store.miners.isEmpty {
                Text("No miners yet. Add miners to see their consumption and costs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Miners")
                        Text("Schedule")
                        Text("Power").gridColumnAlignment(.trailing)
                        Text("per hour").gridColumnAlignment(.trailing)
                        Text("today").gridColumnAlignment(.trailing)
                        Text("30 days").gridColumnAlignment(.trailing)
                        Text("30 days per TH/s").gridColumnAlignment(.trailing)
                    }
                    .sectionLabelStyle()
                    Divider()
                    ForEach(store.miners) { miner in
                        minerRow(miner, now: now)
                    }
                }
            }
        }
        .padding(16)
        .nativeCard()
    }

    private func minerRow(_ miner: MinerDevice, now: Date) -> some View {
        let tariff = power.tariff
        let watts = miner.latestInfo?.power ?? 0
        let isOnline = miner.connectionState.isOnline && miner.latestInfo != nil
        let month = power.projectedCost(for: miner, hours: 24 * 30, from: now)
        let th = (miner.latestInfo?.hashRate ?? 0) / 1000
        return GridRow {
            Text(redactor.freeText(miner.displayName))
                .lineLimit(1)
                .truncationMode(.middle)
            scheduleState(miner, now: now)
            Text(isOnline ? String(format: "%.1f W", watts) : String(localized: "Offline"))
                .foregroundStyle(isOnline ? .primary : .tertiary)
            Text(isOnline ? tariff.formatPrice(power.costPerHour(watts: watts, at: now), digits: 3) : "—")
            Text(isOnline ? tariff.formatPrice(power.costToday(for: miner)) : "—")
            Text(isOnline ? tariff.formatPrice(month) : "—")
            Text(isOnline && th > 0.01 ? tariff.formatPrice(month / th) : "—")
        }
        .font(.mono(12))
    }

    private func scheduleState(_ miner: MinerDevice, now: Date) -> some View {
        let planned = PowerStore.effective(power.plannedAction(for: miner.id, at: now), for: miner)
        let current = power.state(for: miner.id)
        return HStack(spacing: 4) {
            Image(systemName: current.systemImage)
            Text(current.title)
            if planned != current {
                Text("→ \(planned.title)")
                    .foregroundStyle(.secondary)
                    .help(power.runsSchedules
                          ? String(localized: "Switches as soon as the miner is online and the last switch was 15 minutes ago")
                          : String(localized: "This Mac does not run schedules"))
            }
        }
        .font(.system(size: 12))
    }

    private func hint(_ text: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(color)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Figure

private struct PowerFigure: View {
    let label: LocalizedStringKey
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabelStyle()
            Text(value)
                .font(.figure(22))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .nativeCard()
    }
}

// MARK: - Week bar

enum ZonePalette {
    private static let colors: [Color] = [
        Accent.color,
        Color.dynamic(light: 0x3b6fd4, dark: 0x6f9bf0),
        Signal.good,
        Color.dynamic(light: 0x8a56c9, dark: 0xb18ae8),
        Color.dynamic(light: 0x1f9aa8, dark: 0x4cc6d3),
        Signal.bad,
    ]

    static func color(_ index: Int) -> Color { colors[index % colors.count] }
}

/// One row per weekday, coloured by the zone that applies; base price in grey, the current moment marked.
struct WeekTariffBar: View {
    let tariff: PowerTariff
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: now)
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(WeekdayOrder.mondayFirst, id: \.self) { day in
                HStack(spacing: 8) {
                    Text(WeekdayOrder.shortName(day))
                        .font(.mono(11))
                        .foregroundStyle(day == today ? .primary : .tertiary)
                        .frame(width: 28, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            ForEach(Array(tariff.segments(weekday: day).enumerated()), id: \.offset) { _, segment in
                                Rectangle()
                                    .fill(color(for: segment.zoneID))
                                    .frame(width: width(segment, in: geo.size.width))
                                    .offset(x: x(segment.startMinute, in: geo.size.width))
                                    .help(label(for: segment))
                            }
                            if day == today {
                                Rectangle()
                                    .fill(Color.primary)
                                    .frame(width: 2)
                                    .offset(x: x(nowMinute, in: geo.size.width) - 1)
                            }
                        }
                    }
                    .frame(height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                Color.clear.frame(width: 28, height: 1)
                GeometryReader { geo in
                    ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                        Text("\(hour)")
                            .font(.mono(10))
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                            .position(x: x(hour * 60, in: geo.size.width), y: 6)
                    }
                }
                .frame(height: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Weekly overview of the tariff"))
    }

    private func x(_ minute: Int, in width: CGFloat) -> CGFloat {
        width * CGFloat(minute) / CGFloat(WeeklyWindow.minutesPerDay)
    }

    private func width(_ segment: TariffSegment, in width: CGFloat) -> CGFloat {
        max(1, x(segment.endMinute, in: width) - x(segment.startMinute, in: width))
    }

    private func color(for zoneID: UUID?) -> Color {
        guard let zoneID, let index = tariff.zones.firstIndex(where: { $0.id == zoneID }) else {
            return Color.primary.opacity(0.12)
        }
        return ZonePalette.color(index).opacity(0.85)
    }

    private func label(for segment: TariffSegment) -> String {
        let name = tariff.zones.first { $0.id == segment.zoneID }?.name ?? String(localized: "Standard price")
        return "\(name) \(WeeklyWindow.clock(segment.startMinute))–\(WeeklyWindow.clock(segment.endMinute))"
    }
}
