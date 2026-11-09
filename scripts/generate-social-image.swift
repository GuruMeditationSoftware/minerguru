// Draws the preview image that chats and social networks show for a link to the website (1200 × 630).
// Usage: swift scripts/generate-social-image.swift website/img/social.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "website/img/social.png"
let width = 1200, height = 630
let H = CGFloat(height)

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("no context") }
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

func image(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("missing \(path)") }
    return image
}
func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}
/// Text whose top edge sits `top` points below the top of the image.
func draw(_ text: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, hex: UInt32) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color(hex), .kern: -size * 0.02])
    string.draw(at: CGPoint(x: x, y: H - top - font.ascender + font.descender))
}

// Background in the website's dark theme
ctx.setFillColor(color(0x141415).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

// Title row: icon, name, what it is
ctx.draw(image("website/img/icon.png"), in: CGRect(x: 72, y: H - 64 - 72, width: 72, height: 72))
draw("MinerGuru", x: 164, top: 60, size: 40, weight: .semibold, hex: 0xf2f2f3)
draw("The app for Bitaxe and NerdQAxe · Mac, Windows, Android", x: 166, top: 110, size: 24, weight: .regular, hex: 0xa4a5ab)

// The dark fleet overview, running off the bottom edge
let shot = image("website/img/overview-dark.png")
let shotWidth: CGFloat = 1056
let shotHeight = shotWidth * CGFloat(shot.height) / CGFloat(shot.width)
let frame = CGRect(x: (CGFloat(width) - shotWidth) / 2, y: H - 176 - shotHeight, width: shotWidth, height: shotHeight)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 48, color: NSColor.black.withAlphaComponent(0.55).cgColor)
ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.setFillColor(color(0x19191b).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: frame, cornerWidth: 12, cornerHeight: 12, transform: nil))
ctx.clip()
ctx.interpolationQuality = .high
ctx.draw(shot, in: frame)
ctx.restoreGState()

guard let result = ctx.makeImage() else { fatalError("no image") }
let png = NSBitmapImageRep(cgImage: result).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
print("✅ \(output)")
