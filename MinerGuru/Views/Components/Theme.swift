import SwiftUI
import AppKit

// MARK: - Colors

extension Color {
    /// Color that follows the window's appearance, given as hex values for light and dark.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    /// Quiet border of panels and rows.
    static let hairline = Color.primary.opacity(0.08)

    /// Axis labels; an explicit color, since hierarchical styles pick up the accent inside charts.
    static let mutedLabel = Color(nsColor: .tertiaryLabelColor)
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

/// Surfaces of the interface: one graphite ramp for light and dark. Color is carried by content
/// (hashrate line, device cards, status blocks), never by the surfaces themselves.
enum Surface {
    /// Sidebar, the deepest surface
    static let sidebar = Color.dynamic(light: 0xf2f2f3, dark: 0x0f0f10)
    /// Background of the detail pages
    static let page = Color.dynamic(light: 0xfafafa, dark: 0x141415)
    /// Panels and cards
    static let card = Color.dynamic(light: 0xffffff, dark: 0x19191b)
    /// Raised surface: selection, insets inside cards
    static let raised = Color.dynamic(light: 0xededee, dark: 0x232325)
}

/// The one accent: a toned-down Bitcoin orange for the hashrate line, the selection and the figure that matters.
enum Accent {
    static let color = Color.dynamic(light: 0xd9780a, dark: 0xf0a03c)
}

/// Status colors, toned to sit inside the graphite palette. They only carry meaning.
enum Signal {
    static let good = Color.dynamic(light: 0x14a06c, dark: 0x3ecf8e)
    static let warning = Color.dynamic(light: 0xc77a00, dark: 0xf5b041)
    static let bad = Color.dynamic(light: 0xc23b3b, dark: 0xe66767)
    static let idle = Color.dynamic(light: 0x8a8a8e, dark: 0x6e6e73)
}

// MARK: - Type

extension Font {
    /// Monospaced type for figures in meta lines, axes, counts and addresses.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Large key figure, e.g. the fleet hashrate.
    static func figure(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium).monospacedDigit()
    }
}

// MARK: - Panels

extension View {
    /// Card with a hairline, as every section uses it.
    func panel(cornerRadius: CGFloat = 14, padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(Surface.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
    }

    /// Small mono label above lists, figures and groups.
    func sectionLabelStyle() -> some View {
        font(.mono(11))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Mark

/// The app's mark: a square m made of wide bars. Its right leg stops short and runs into
/// a small ASIC chip with pins, the chip that does the mining.
struct MinerGuruMark: View {
    var size: CGFloat = 18
    var color: Color = .primary

    /// The chip on the mark's grid of 24 units: a body with two pins to the left, right and below.
    static let chipBody = CGRect(x: 17.8, y: 16.4, width: 4.8, height: 4.8)
    static let chipCornerRadius: CGFloat = 0.5
    static let chipPins: [CGRect] = [
        CGRect(x: 16.6, y: 17.45, width: 1.2, height: 0.7),
        CGRect(x: 16.6, y: 19.45, width: 1.2, height: 0.7),
        CGRect(x: 22.6, y: 17.45, width: 1.2, height: 0.7),
        CGRect(x: 22.6, y: 19.45, width: 1.2, height: 0.7),
        CGRect(x: 18.85, y: 21.2, width: 0.7, height: 1.2),
        CGRect(x: 20.85, y: 21.2, width: 0.7, height: 1.2)
    ]

    var body: some View {
        ZStack {
            MarkLetter()
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.15, lineCap: .butt, lineJoin: .miter))
            MarkChip()
                .fill(Accent.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The m on a grid of 24 units: left leg full height, the middle leg ends early, the right leg runs toward the chip.
struct MarkLetter: Shape {
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

/// The chip of the mark with its pins, scaled from the 24-unit grid.
struct MarkChip: Shape {
    func path(in rect: CGRect) -> Path {
        let u = rect.width / 24
        func scaled(_ r: CGRect) -> CGRect { CGRect(x: r.minX * u, y: r.minY * u, width: r.width * u, height: r.height * u) }
        var path = Path()
        path.addRoundedRect(
            in: scaled(MinerGuruMark.chipBody),
            cornerSize: CGSize(width: MinerGuruMark.chipCornerRadius * u, height: MinerGuruMark.chipCornerRadius * u)
        )
        for pin in MinerGuruMark.chipPins {
            path.addRect(scaled(pin))
        }
        return path
    }
}

// MARK: - Status block

/// The signature detail: a small square LED that shows a miner's state.
/// Each state has its own shape, so it reads without telling the colors apart:
/// online is a filled block, too hot a filled diamond, checking an outline, offline an outline with a slash.
struct StatusBlock: View {
    let state: MinerConnectionState
    var isHighTemp: Bool = false
    var size: CGFloat = 8

    private enum Look { case online, hot, checking, offline }

    private var look: Look {
        switch state {
        case .online: return isHighTemp ? .hot : .online
        case .checking, .unknown: return .checking
        case .offline: return .offline
        }
    }

    var color: Color {
        switch look {
        case .online: return Signal.good
        case .hot: return Signal.warning
        case .checking: return Signal.idle
        case .offline: return Signal.bad
        }
    }

    var body: some View {
        Group {
            switch look {
            case .online:
                Rectangle().fill(color)
            case .hot:
                Rectangle().fill(color)
                    .frame(width: size * 0.78, height: size * 0.78)
                    .rotationEffect(.degrees(45))
            case .checking:
                Rectangle().strokeBorder(color, lineWidth: max(1, size * 0.16))
            case .offline:
                ZStack {
                    Rectangle().strokeBorder(color, lineWidth: max(1, size * 0.16))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size))
                        path.addLine(to: CGPoint(x: size, y: 0))
                    }
                    .stroke(color, lineWidth: max(1, size * 0.16))
                }
            }
        }
        .frame(width: size, height: size)
    }
}
