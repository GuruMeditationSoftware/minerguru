import SwiftUI
import AppKit

@MainActor
struct MinerGuruAppIconView: View {
    let size: CGFloat

    // Same mark as `MinerGuruMark` in the app (Views/Components/Theme.swift): a square m of wide bars
    // on a 24-unit grid, the right leg runs into a small ASIC chip with pins in Bitcoin orange.
    var body: some View {
        let scale = size / 1024.0
        let tile = 824 * scale
        let mark = 440 * scale
        let u = mark / 24
        let bar = mark * 0.15
        let accent = Color(red: 0xF0 / 255.0, green: 0xA0 / 255.0, blue: 0x3C / 255.0)

        ZStack {
            // Anodised graphite: a soft light from the top, darker toward the bottom edge
            RoundedRectangle(cornerRadius: 185 * scale, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.11), Color(white: 0.075)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: tile, height: tile)
                .overlay(
                    RoundedRectangle(cornerRadius: 185 * scale, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom),
                            lineWidth: max(1, 4 * scale)
                        )
                )
                .shadow(color: .black.opacity(0.38), radius: 22 * scale, x: 0, y: 12 * scale)

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 3.8 * u, y: 20.2 * u))
                    path.addLine(to: CGPoint(x: 3.8 * u, y: 3.8 * u))
                    path.addLine(to: CGPoint(x: 20.2 * u, y: 3.8 * u))
                    path.addLine(to: CGPoint(x: 20.2 * u, y: 15 * u))
                    path.move(to: CGPoint(x: 12 * u, y: 3.8 * u))
                    path.addLine(to: CGPoint(x: 12 * u, y: 14 * u))
                }
                .stroke(Color(white: 0.93), style: StrokeStyle(lineWidth: bar, lineCap: .butt, lineJoin: .miter))

                Path { path in
                    func scaled(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                        CGRect(x: x * u, y: y * u, width: w * u, height: h * u)
                    }
                    path.addRoundedRect(in: scaled(17.8, 16.4, 4.8, 4.8), cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u))
                    for pin in [
                        scaled(16.6, 17.45, 1.2, 0.7), scaled(16.6, 19.45, 1.2, 0.7),
                        scaled(22.6, 17.45, 1.2, 0.7), scaled(22.6, 19.45, 1.2, 0.7),
                        scaled(18.85, 21.2, 0.7, 1.2), scaled(20.85, 21.2, 0.7, 1.2)
                    ] {
                        path.addRect(pin)
                    }
                }
                .fill(accent)
            }
            .frame(width: mark, height: mark)
        }
        .frame(width: size, height: size)
    }
}

@MainActor
func renderIcon(pixelSize: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: MinerGuruAppIconView(size: CGFloat(pixelSize)))
    renderer.scale = 1.0
    guard let cgImage = renderer.cgImage else {
        throw NSError(domain: "IconGen", code: 1)
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 2)
    }
    try pngData.write(to: url)
}

@MainActor
func generateAllIcons() throws {
    let fm = FileManager.default
    let iconsetDir = URL(fileURLWithPath: "/tmp/AppIcon.iconset")
    let xcassetDir = URL(fileURLWithPath: "MinerGuru/Assets.xcassets/AppIcon.appiconset")

    try? fm.removeItem(at: iconsetDir)
    try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: xcassetDir, withIntermediateDirectories: true)

    let specs: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for spec in specs {
        let iconsetURL = iconsetDir.appendingPathComponent(spec.name)
        let xcassetURL = xcassetDir.appendingPathComponent(spec.name)
        try renderIcon(pixelSize: spec.pixels, to: iconsetURL)
        try? fm.removeItem(at: xcassetURL)
        try fm.copyItem(at: iconsetURL, to: xcassetURL)
    }

    let contentsJSON = """
    {
      "images" : [
        { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try Data(contentsJSON.utf8).write(to: xcassetDir.appendingPathComponent("Contents.json"))

    // Build native macOS .icns file directly from PNG chunks
    let icnsChunks: [(tag: String, file: String)] = [
        ("icp4", "icon_16x16.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]

    var bodyData = Data()
    for chunk in icnsChunks {
        let pngData = try Data(contentsOf: iconsetDir.appendingPathComponent(chunk.file))
        let chunkLen = UInt32(8 + pngData.count).bigEndian
        bodyData.append(contentsOf: chunk.tag.utf8)
        withUnsafeBytes(of: chunkLen) { bodyData.append(contentsOf: $0) }
        bodyData.append(pngData)
    }

    var icnsData = Data()
    icnsData.append(contentsOf: "icns".utf8)
    let totalLen = UInt32(8 + bodyData.count).bigEndian
    withUnsafeBytes(of: totalLen) { icnsData.append(contentsOf: $0) }
    icnsData.append(bodyData)

    let icnsURL = URL(fileURLWithPath: "MinerGuru/AppIcon.icns")
    try icnsData.write(to: icnsURL)
    print("Generated all PNG icons and MinerGuru/AppIcon.icns (\(icnsData.count) bytes) successfully.")
}

try MainActor.assumeIsolated {
    try generateAllIcons()
}
