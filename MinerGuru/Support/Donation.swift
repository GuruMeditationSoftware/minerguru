import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins

/// Wallet addresses for voluntary donations (also shown on the website).
enum DonationCoin: String, CaseIterable, Identifiable {
    case btc = "BTC"
    case bch = "BCH"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .btc: "Bitcoin"
        case .bch: "Bitcoin Cash"
        }
    }

    var address: String {
        switch self {
        case .btc: "bc1qc6xpuwkys8jsjt439tfw2eu3fctkx7ad0hkehe"
        case .bch: "bitcoincash:qruvqq2x9vyd9gykre058r4lda4gulpres33nr9aml"
        }
    }

    /// `false` as long as the build carries a placeholder instead of a real address.
    var isConfigured: Bool { !address.contains("ADRESSE-EINTRAGEN") }

    /// BIP21-style payment URI, so wallet apps open it directly when the QR code is scanned.
    var paymentURI: String {
        switch self {
        case .btc: "bitcoin:\(address)"
        case .bch: address
        }
    }
}

enum QRCode {
    static func image(for text: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = ceil(size * 2 / output.extent.width)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}

/// Quiet line at the top of the fleet page. A click opens the addresses.
struct SupportDevelopmentButton: View {
    @State private var isShowingDialog = false
    @State private var isHovered = false

    var body: some View {
        Button {
            isShowingDialog = true
        } label: {
            Label("Diese Entwicklung unterstützen", systemImage: "heart")
                .font(.system(size: 12))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Spenden-Adressen und QR-Codes anzeigen")
        .sheet(isPresented: $isShowingDialog) { SupportDevelopmentSheet() }
    }
}

/// Both coins side by side: QR code, address, copy button.
struct SupportDevelopmentSheet: View {
    @State private var copied: DonationCoin?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Diese Entwicklung unterstützen")
                .font(.headline)
            Text("MinerGuru ist kostenlos und zeigt keine Werbung. Wenn dir die App hilft, freue ich mich über eine kleine Spende für die Weiterentwicklung.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                ForEach(DonationCoin.allCases) { coin in
                    coinCard(coin)
                }
            }

            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func coinCard(_ coin: DonationCoin) -> some View {
        VStack(spacing: 10) {
            Text(verbatim: coin.name)
                .font(.subheadline.weight(.medium))

            if coin.isConfigured, let image = QRCode.image(for: coin.paymentURI, size: 170) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))

                Text(verbatim: coin.address)
                    .font(.mono(10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(coin.address, forType: .string)
                    copied = coin
                } label: {
                    Label(copied == coin ? "Kopiert" : "Adresse kopieren",
                          systemImage: copied == coin ? "checkmark" : "doc.on.doc")
                }
            } else {
                Text("Adresse noch nicht hinterlegt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 186, height: 186)
                    .insetSurface()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .nativeCard()
    }
}

/// Settings card: one row per coin with copy button and a QR code on demand.
struct DonationSection: View {
    @State private var copied: DonationCoin?
    @State private var qrCoin: DonationCoin?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Entwicklung unterstützen", systemImage: "heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                Text("MinerGuru ist kostenlos. Wenn dir die App gefällt, freue ich mich über eine kleine Spende für die Weiterentwicklung.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)

                ForEach(DonationCoin.allCases) { coin in
                    Divider()
                    row(for: coin)
                }

                if let qrCoin, qrCoin.isConfigured, let image = QRCode.image(for: qrCoin.paymentURI, size: 150) {
                    Divider()
                    HStack {
                        Spacer()
                        Image(nsImage: image)
                            .interpolation(.none)
                            .padding(8)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nativeCard()
        }
    }

    private func row(for coin: DonationCoin) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: coin.rawValue)
                .fontWeight(.semibold)
                .frame(width: 34, alignment: .leading)
            Text(verbatim: coin.isConfigured ? coin.address : String(localized: "Adresse noch nicht hinterlegt"))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                qrCoin = qrCoin == coin ? nil : coin
            } label: {
                Image(systemName: "qrcode")
            }
            .help("QR-Code anzeigen")
            .disabled(!coin.isConfigured)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(coin.address, forType: .string)
                copied = coin
            } label: {
                Image(systemName: copied == coin ? "checkmark" : "doc.on.doc")
            }
            .help("Adresse kopieren")
            .disabled(!coin.isConfigured)
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 28)
        .padding(.vertical, 6)
    }
}
