#!/usr/bin/env swift
// Renders the DMG window background (660x400 pt, @2x) with an arrow and install hint.
// Usage: swift scripts/generate-dmg-background.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.dropFirst().first ?? "dmg-background.png"
let points = NSSize(width: 660, height: 400)
let scale: CGFloat = 2
let pixels = NSSize(width: points.width * scale, height: points.height * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("bitmap") }
rep.size = points // 144 dpi → Finder shows it at 660x400 pt

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: soft light gradient
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.97, green: 0.97, blue: 0.99, alpha: 1),
    NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.95, alpha: 1),
])!
gradient.draw(in: NSRect(origin: .zero, size: points), angle: -90)

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    let s = NSAttributedString(string: text, attributes: attrs)
    let w = s.size().width
    s.draw(at: NSPoint(x: centerX - w / 2, y: y))
}

let dark = NSColor(calibratedWhite: 0.12, alpha: 1)
let muted = NSColor(calibratedWhite: 0.38, alpha: 1)

// Title + hint (AppKit origin is bottom-left)
draw("MinerGuru installieren", size: 26, weight: .semibold, color: dark, centerX: points.width / 2, y: 328)
draw("Ziehe MinerGuru in den Ordner „Programme“", size: 15, weight: .regular, color: muted, centerX: points.width / 2, y: 298)

// Arrow between the two icon slots (icons sit at x=165 and x=495, y=190 from the top → 210 from the bottom)
let arrowY: CGFloat = 200
let arrow = NSBezierPath()
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 245, y: arrowY))
arrow.line(to: NSPoint(x: 410, y: arrowY))
NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.85, alpha: 0.9).setStroke()
arrow.stroke()

let head = NSBezierPath()
head.lineWidth = 6
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: 392, y: arrowY + 20))
head.line(to: NSPoint(x: 414, y: arrowY))
head.line(to: NSPoint(x: 392, y: arrowY - 20))
head.stroke()

draw("Danach kannst du das Fenster schließen und das Image auswerfen.", size: 12, weight: .regular, color: muted, centerX: points.width / 2, y: 40)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try png.write(to: URL(fileURLWithPath: outPath))
print("Background written to \(outPath)")
