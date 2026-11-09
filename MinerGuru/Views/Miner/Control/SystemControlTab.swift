import SwiftUI
import AppKit

/// Display name, network hostname and device actions (restart, web UI).
struct SystemControlTab: View {
    @Binding var form: MinerSettingsForm
    let miner: MinerDevice
    let isSaving: Bool
    let onSaveAlias: () -> Void
    let onSaveHostname: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name in MinerGuru")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 10) {
                    TextField("Custom name (empty = hostname of the miner)", text: $form.customAlias)
                        .textFieldStyle(.roundedBorder)
                    Button("Save", action: onSaveAlias)
                        .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Miner Hostname on the Network")
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 10) {
                    TextField("bitaxe", text: $form.deviceHostname)
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                    Button("Send Hostname", action: onSaveHostname)
                        .buttonStyle(.bordered)
                        .disabled(form.trimmedHostname.isEmpty || isSaving)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Device Actions")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 12) {
                    Button(action: onRestart) {
                        Label("Restart Miner (Reboot)", systemImage: "arrow.clockwise.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(Signal.warning)

                    Button {
                        if let url = URL(string: "http://\(miner.ipAddress)") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Open Web Interface in Browser", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
