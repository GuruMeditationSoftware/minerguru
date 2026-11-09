import SwiftUI
import AppKit

/// Shows the raw `/api/system/info` response of a miner, with copy to clipboard.
struct RawJSONInspectorSheet: View {
    let miner: MinerDevice
    @Environment(\.dismiss) private var dismiss
    @Environment(\.redactor) private var redactor
    @State private var copied = false

    private var json: String { miner.rawJSON ?? "{}" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Raw API Data (/api/system/info)")
                        .font(.system(size: 15, weight: .medium))
                    Text("http://\(redactor.ip(miner.ipAddress))/api/system/info")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(json, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy JSON", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.cancelAction)
            }

            ScrollView {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .sensitive()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }
}
