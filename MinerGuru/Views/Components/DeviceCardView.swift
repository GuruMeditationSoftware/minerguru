import SwiftUI

/// What a device card shows of a miner: the board family, its model line and how many ASICs sit on it.
struct DeviceCardSpec: Equatable {
    enum Display { case oled, tft }

    /// Silkscreen name on the board, e.g. `bitaxe` or `nerdqaxe++`
    let family: String
    /// Model line under the chips, e.g. `Gamma 601`
    let model: String
    let chipCount: Int
    let chipModel: String?
    let display: Display

    init(family: String, model: String, chipCount: Int, chipModel: String?, display: Display) {
        self.family = family
        self.model = model
        self.chipCount = chipCount
        self.chipModel = chipModel
        self.display = display
    }

    /// Spec from the miner's current telemetry, or from the remembered hardware title while it is offline.
    init(miner: MinerDevice) {
        self.init(title: miner.hardwareTitle, info: miner.latestInfo)
    }

    /// Spec of a miner found by the network scan.
    init(scanned info: MinerSystemInfo) {
        self.init(title: info.detectedHardwareTitle, info: info)
    }

    private init(title: String, info: MinerSystemInfo?) {
        let words = title.split(separator: " ", maxSplits: 1).map(String.init)
        let lower = title.lowercased()
        let isNerd = info.map { $0.firmware == .nerdOS } ?? lower.hasPrefix("nerd")

        family = (words.first ?? title).lowercased()
        model = words.count > 1 ? words[1] : ""
        chipModel = info?.asicModel
        display = isNerd ? .tft : .oled
        chipCount = info?.asicCount ?? Self.guessedChipCount(lowercasedTitle: lower)
    }

    private static func guessedChipCount(lowercasedTitle title: String) -> Int {
        if title.contains("eko") { return 12 }
        if title.contains("octaxe") { return 8 }
        if title.contains("hex") || title.contains("haxe") { return 6 }
        if title.contains("qaxe") || title.contains("qx") || title.contains("q137") { return 4 }
        if title.contains("duo") || title.contains("gt") { return 2 }
        return 1
    }

    /// Chip grid as columns × rows.
    var chipGrid: (columns: Int, rows: Int) {
        switch chipCount {
        case ...1: return (1, 1)
        case 2: return (2, 1)
        case 3...4: return (2, 2)
        case 5...6: return (3, 2)
        case 7...8: return (4, 2)
        default: return (Int((Double(chipCount) / 2).rounded(.up)), 2)
        }
    }
}

/// A miner drawn as a card-sized board seen from above: dark solder mask, silver ASIC lids,
/// a small display and the model on the silkscreen. Like a bank card it is an object,
/// so it stays dark in light mode. Details drop away at small sizes.
struct DeviceCardView: View {
    let spec: DeviceCardSpec
    var width: CGFloat = 160
    /// State shown by the board's LED, the app's status block; `nil` hides it.
    var led: LED? = nil

    struct LED: Equatable {
        let state: MinerConnectionState
        var isHighTemp: Bool = false
    }

    static let aspect: CGFloat = 1.586

    private var height: CGFloat { width / Self.aspect }
    private var isDetailed: Bool { width >= 80 }

    var body: some View {
        let w = width
        let h = height
        let radius = max(3, w * 0.07)

        ZStack(alignment: .topLeading) {
            // Solder mask: graphite with a soft light from the top left. NerdOS boards are a touch cooler.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(
                    colors: spec.display == .tft
                        ? [Color(red: 0.17, green: 0.18, blue: 0.21), Color(red: 0.09, green: 0.10, blue: 0.12), Color(red: 0.06, green: 0.06, blue: 0.08)]
                        : [Color(white: 0.21), Color(white: 0.11), Color(white: 0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            if isDetailed {
                traces(w: w, h: h)
                port(w: w, h: h)
                display(w: w, h: h)
            }

            chips(w: w, h: h)

            if width >= 120 {
                Text(spec.family)
                    .font(.system(size: w * 0.062, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize()
                    .offset(x: w * 0.07, y: h * 0.08)

                Text(modelLine)
                    .font(.system(size: w * 0.046, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: w * 0.86, alignment: .leading)
                    .offset(x: w * 0.07, y: h * 0.83)
            }

            if let led {
                let size = isDetailed ? max(6, w * 0.04) : 6
                StatusBlock(state: led.state, isHighTemp: led.isHighTemp, size: size)
                    .offset(x: w - size - (isDetailed ? w * 0.07 : 3), y: isDetailed ? h * 0.1 : 3)
            }

            // Edge catches the light at the top
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                    lineWidth: width >= 60 ? 1 : 0.5
                )
        }
        .frame(width: w, height: h)
        .compositingGroup()
        .shadow(color: .black.opacity(isDetailed ? 0.35 : 0.15), radius: isDetailed ? w * 0.06 : 1, x: 0, y: isDetailed ? w * 0.04 : 0.5)
        // Only the LED carries information: VoiceOver reads the state, the drawing itself stays silent
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(led.map(Self.accessibilityText) ?? Text(""))
        .accessibilityHidden(led == nil)
        .help(led.map(Self.accessibilityText) ?? Text(""))
    }

    private static func accessibilityText(_ led: LED) -> Text {
        switch led.state {
        case .online: return led.isHighTemp ? Text("Online, Temperatur hoch") : Text("Online")
        case .checking, .unknown: return Text("Verbindung wird geprüft")
        case .offline: return Text("Offline")
        }
    }

    private var modelLine: String {
        [spec.model, spec.chipModel.map { spec.chipCount > 1 ? "\(spec.chipCount)× \($0)" : $0 }]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: Parts

    /// Area the ASICs share: right of the display on detailed cards, centered on small ones.
    private func chipArea(w: CGFloat, h: CGFloat) -> CGRect {
        isDetailed
            ? CGRect(x: w * 0.36, y: h * 0.2, width: w * 0.56, height: h * 0.58)
            : CGRect(x: w * 0.12, y: h * 0.16, width: w * 0.76, height: h * 0.68)
    }

    private func chips(w: CGFloat, h: CGFloat) -> some View {
        let area = chipArea(w: w, h: h)
        let grid = spec.chipGrid
        let cell = min(area.width / CGFloat(grid.columns), area.height / CGFloat(grid.rows))
        let chip = min(cell * 0.74, h * 0.38)
        let gridWidth = cell * CGFloat(grid.columns)
        let gridHeight = cell * CGFloat(grid.rows)
        let originX = area.midX - gridWidth / 2
        let originY = area.midY - gridHeight / 2

        return ZStack(alignment: .topLeading) {
            ForEach(0..<max(1, spec.chipCount), id: \.self) { index in
                let column = index % grid.columns
                let row = index / grid.columns
                ASICLid(size: chip, label: chip >= 30 ? spec.chipModel : nil)
                    .offset(
                        x: originX + CGFloat(column) * cell + (cell - chip) / 2,
                        y: originY + CGFloat(row) * cell + (cell - chip) / 2
                    )
            }
        }
    }

    private func traces(w: CGFloat, h: CGFloat) -> some View {
        Path { path in
            let area = chipArea(w: w, h: h)
            for step in 0..<4 {
                let y = area.minY + area.height * (0.2 + 0.2 * CGFloat(step))
                path.move(to: CGPoint(x: w * 0.04, y: y))
                path.addLine(to: CGPoint(x: w * 0.3, y: y))
                path.addLine(to: CGPoint(x: area.minX - w * 0.02, y: y + h * 0.03))
            }
            path.move(to: CGPoint(x: area.midX, y: area.maxY + h * 0.02))
            path.addLine(to: CGPoint(x: area.midX + w * 0.06, y: h * 0.96))
            path.move(to: CGPoint(x: area.maxX - w * 0.04, y: area.minY - h * 0.02))
            path.addLine(to: CGPoint(x: area.maxX, y: h * 0.04))
        }
        .stroke(Color(red: 0.85, green: 0.6, blue: 0.4).opacity(0.09), lineWidth: max(0.5, w * 0.005))
    }

    /// USB-C socket at the left edge.
    private func port(w: CGFloat, h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: w * 0.012)
            .fill(LinearGradient(colors: [Color(white: 0.7), Color(white: 0.45)], startPoint: .top, endPoint: .bottom))
            .frame(width: w * 0.035, height: h * 0.14)
            .offset(x: 0, y: h * 0.43)
    }

    /// Bitaxe boards carry a small OLED, NerdOS boards a colour TFT that shows the hashrate.
    @ViewBuilder
    private func display(w: CGFloat, h: CGFloat) -> some View {
        switch spec.display {
        case .oled:
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: w * 0.008)
                    .fill(Color.black)
                VStack(alignment: .leading, spacing: h * 0.025) {
                    Capsule().fill(Color.white.opacity(0.55)).frame(width: w * 0.09, height: max(0.5, h * 0.018))
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: w * 0.13, height: max(0.5, h * 0.018))
                }
                .padding(.leading, w * 0.018)
            }
            .frame(width: w * 0.19, height: h * 0.13)
            .overlay(RoundedRectangle(cornerRadius: w * 0.008).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
            .offset(x: w * 0.09, y: h * 0.42)
        case .tft:
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.012)
                    .fill(Color(red: 0.03, green: 0.04, blue: 0.06))
                Path { path in
                    let line: [(x: CGFloat, y: CGFloat)] = [(0, 0.7), (0.2, 0.55), (0.38, 0.62), (0.55, 0.38), (0.74, 0.45), (1, 0.28)]
                    path.addLines(line.map { CGPoint(x: $0.x * w * 0.17, y: $0.y * h * 0.26) })
                }
                .stroke(Accent.color.opacity(0.9), style: StrokeStyle(lineWidth: max(0.75, w * 0.007), lineCap: .round, lineJoin: .round))
                .frame(width: w * 0.17, height: h * 0.26)
            }
            .frame(width: w * 0.21, height: h * 0.36)
            .overlay(RoundedRectangle(cornerRadius: w * 0.012).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .offset(x: w * 0.08, y: h * 0.32)
        }
    }
}

/// Nickel-plated lid of one ASIC with its laser-etched model.
private struct ASICLid: View {
    let size: CGFloat
    let label: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(1, size * 0.1), style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.86), Color(white: 0.6), Color(white: 0.76)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: max(1, size * 0.06), style: .continuous)
                .strokeBorder(Color.black.opacity(0.18), lineWidth: max(0.5, size * 0.025))
                .padding(size * 0.12)
            if let label {
                Text(label)
                    .font(.system(size: size * 0.15, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.38))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, size * 0.16)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: max(0.5, size * 0.05), x: 0, y: size * 0.03)
    }
}

/// Up to three device cards fanned out like cards in a hand, the strongest miner in front.
struct DeviceCardStack: View {
    let cards: [(spec: DeviceCardSpec, led: DeviceCardView.LED?)]
    var width: CGFloat = 176

    var body: some View {
        let shown = Array(cards.prefix(3))
        let height = width / DeviceCardView.aspect
        // Back to front: rotation and offset of each card
        let poses: [(angle: Double, x: CGFloat, y: CGFloat)] = switch shown.count {
        case 1: [(-8, 0, 0)]
        case 2: [(-2, 0.16, -0.12), (-11, -0.04, 0.04)]
        default: [(4, 0.26, -0.16), (-3, 0.1, -0.06), (-12, -0.06, 0.06)]
        }

        ZStack {
            ForEach(Array(shown.enumerated().reversed()), id: \.offset) { index, card in
                let pose = poses[shown.count - 1 - index]
                DeviceCardView(spec: card.spec, width: width, led: card.led)
                    .rotationEffect(.degrees(pose.angle))
                    .offset(x: width * pose.x, y: width * pose.y)
            }
        }
        .frame(width: width * 1.4, height: height * 1.5)
        .accessibilityHidden(true)
    }
}
