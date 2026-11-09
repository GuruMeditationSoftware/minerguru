import SwiftUI
import WidgetKit

// The app's look in the widgets: graphite surfaces from the system, one muted Bitcoin orange for the hashrate,
// signal colors only where they mean something. Values copied from MinerGuru/Views/Components/Theme.swift.

/// Colors picked by the widget's color scheme. Widgets are archived per appearance, so they are resolved
/// here instead of through a dynamic NSColor.
struct Palette {
    let scheme: ColorScheme

    private func pick(_ light: UInt32, _ dark: UInt32) -> Color {
        let hex = scheme == .dark ? dark : light
        return Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    var accent: Color { pick(0xd9780a, 0xf0a03c) }
    var good: Color { pick(0x14a06c, 0x3ecf8e) }
    var warning: Color { pick(0xc77a00, 0xf5b041) }
    var bad: Color { pick(0xc23b3b, 0xe66767) }
    var idle: Color { pick(0x8a8a8e, 0x6e6e73) }
    /// The app's coin dot colors, by ticker symbol.
    func coin(_ symbol: String) -> Color {
        switch symbol {
        case "BTC": accent
        case "BCH": good
        case "DGB": pick(0x2a78d6, 0x5aa2f5)
        case "XEC": pick(0x0e9f9f, 0x3cc9c9)
        case "BSV": pick(0xb58a06, 0xf5c04a)
        case "PPC": pick(0x4f9a2a, 0x7ccf5a)
        case "NMC": pick(0x5b6ad0, 0x8d98f0)
        case "FB": pick(0x7c5ce0, 0xa48af5)
        default: idle
        }
    }
    var track: Color { Color.primary.opacity(scheme == .dark ? 0.14 : 0.08) }
    var bar: Color { Color.primary.opacity(scheme == .dark ? 0.32 : 0.22) }
}

enum MinerLook {
    case online, hot, checking, offline

    init(_ miner: WidgetSnapshot.Miner, warningC: Double) {
        switch miner.state {
        case .online: self = (miner.tempC ?? 0) >= warningC ? .hot : .online
        case .offline: self = .offline
        case .checking: self = .checking
        }
    }

    func color(_ palette: Palette) -> Color {
        switch self {
        case .online: return palette.good
        case .hot: return palette.warning
        case .checking: return palette.idle
        case .offline: return palette.bad
        }
    }
}

/// The status LED of the app: each state has its own shape, so it reads without the colors
/// (which the clear and tinted widget styles take away).
struct StatusBlock: View {
    let look: MinerLook
    var size: CGFloat = 8
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = look.color(Palette(scheme: scheme))
        let line = max(1, size * 0.16)
        Group {
            switch look {
            case .online:
                Rectangle().fill(color)
            case .hot:
                Rectangle().fill(color)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .rotationEffect(.degrees(45))
            case .checking:
                Rectangle().strokeBorder(color, lineWidth: line)
            case .offline:
                ZStack {
                    Rectangle().strokeBorder(color, lineWidth: line)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size))
                        path.addLine(to: CGPoint(x: size, y: 0))
                    }
                    .stroke(color, lineWidth: line)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The app's mark: a square m of wide bars whose right leg runs into a small ASIC chip.
struct Mark: View {
    var size: CGFloat = 14
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            MarkLetter()
                .stroke(Color.primary, style: StrokeStyle(lineWidth: size * 0.15, lineCap: .butt, lineJoin: .miter))
            MarkChip()
                .fill(Palette(scheme: scheme).accent)
                .widgetAccentable()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct MarkLetter: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 3.8 * u, y: 20.2 * u))
        path.addLine(to: CGPoint(x: 3.8 * u, y: 3.8 * u))
        path.addLine(to: CGPoint(x: 20.2 * u, y: 3.8 * u))
        path.addLine(to: CGPoint(x: 20.2 * u, y: 15 * u))
        path.move(to: CGPoint(x: 12 * u, y: 3.8 * u))
        path.addLine(to: CGPoint(x: 12 * u, y: 14 * u))
        return path
    }
}

private struct MarkChip: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 24
        func scaled(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * u, y: y * u, width: w * u, height: h * u) }
        var path = Path()
        path.addRoundedRect(in: scaled(17.8, 16.4, 4.8, 4.8), cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u))
        for pin in [scaled(16.6, 17.45, 1.2, 0.7), scaled(16.6, 19.45, 1.2, 0.7), scaled(22.6, 17.45, 1.2, 0.7),
                    scaled(22.6, 19.45, 1.2, 0.7), scaled(18.85, 21.2, 0.7, 1.2), scaled(20.85, 21.2, 0.7, 1.2)] {
            path.addRect(pin)
        }
        return path
    }
}

/// Hashrate over 24 hours: a soft line in the accent color with a faint area below.
struct Sparkline: View {
    let values: [Double]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size)
            if points.count > 1 {
                let accent = Palette(scheme: scheme).accent
                ZStack {
                    Self.curve(points, closedAt: geo.size.height)
                        .fill(LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Self.curve(points, closedAt: nil)
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
                .widgetAccentable()
            }
        }
        .accessibilityHidden(true)
    }

    private static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        let pad = max((high - low) * 0.18, high * 0.01, 0.001)
        let lo = low - pad, hi = high + pad
        return values.enumerated().map { index, value in
            CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: size.height * (1 - CGFloat((value - lo) / (hi - lo))))
        }
    }

    private static func curve(_ points: [CGPoint], closedAt bottom: CGFloat?) -> Path {
        var path = Path()
        path.move(to: points[0])
        for (previous, point) in zip(points, points.dropFirst()) {
            let mid = (previous.x + point.x) / 2
            path.addCurve(to: point, control1: CGPoint(x: mid, y: previous.y), control2: CGPoint(x: mid, y: point.y))
        }
        if let bottom, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: bottom))
            path.addLine(to: CGPoint(x: points[0].x, y: bottom))
            path.closeSubpath()
        }
        return path
    }
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func figure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }
}

/// Header row of every widget: mark or symbol, title, and something on the right.
struct WidgetHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Mark(size: 13)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing
        }
    }
}

/// Big figure with its unit beside it, e.g. `16.75 TH/s`.
struct Figure: View {
    let value: String
    let unit: String
    var size: CGFloat = 30

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.figure(size))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .widgetAccentable()
            Text(unit)
                .font(.system(size: max(11, size * 0.4), weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
