import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

// Usage: swift scripts/generate-qr.swift <text> <output.png>
let args = CommandLine.arguments
guard args.count == 3 else { print("Usage: generate-qr.swift <text> <out.png>"); exit(1) }

let filter = CIFilter.qrCodeGenerator()
filter.message = Data(args[1].utf8)
filter.correctionLevel = "M"
guard let output = filter.outputImage else { exit(1) }
let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
let rep = NSBitmapImageRep(ciImage: scaled)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
