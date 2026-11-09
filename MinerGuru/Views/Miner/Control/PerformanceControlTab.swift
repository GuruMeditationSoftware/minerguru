import SwiftUI

/// Clock presets, manual frequency / core voltage and fan control.
struct PerformanceControlTab: View {
    @Binding var form: MinerSettingsForm
    let miner: MinerDevice
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Übertakten geschieht immer auf eigenes Risiko. Zu hoher Takt oder zu hohe Spannung können den Miner beschädigen, die Garantie erlischt.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Unknown chips get no profiles, only manual tuning.
            if !miner.recommendedPresets.isEmpty {
                presets
                Divider()
            }
            manualTuning
            Divider()
            fanControl
            Divider()

            HStack {
                Spacer()
                Button(action: onSave) {
                    HStack(spacing: 6) {
                        if isSaving { ProgressView().controlSize(.small) }
                        Label("Takt & Lüfter auf Miner anwenden", systemImage: "checkmark.circle.fill")
                    }
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schnell-Profile für \(miner.hardwareTitle)")
                .font(.subheadline.weight(.medium))

            ForEach(miner.recommendedPresets) { preset in
                let isCurrent = form.isCurrent(preset)
                Button {
                    form.apply(preset)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(preset.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: "\(preset.frequencyMHz) MHz  •  \(preset.coreVoltageMV) mV")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(isCurrent ? Accent.color : .secondary)
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                    .nativeCard(highlight: isCurrent ? Accent.color : nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var manualTuning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manuelle Feinabstimmung (ASIC-Takt & Kernspannung)")
                .font(.subheadline.weight(.medium))

            stepperRow("Frequenz (MHz):", value: $form.frequencyMHz, range: miner.frequencyRange, step: 25, unit: "MHz")
            stepperRow("Core Voltage (mV):", value: $form.coreVoltageMV, range: miner.coreVoltageRange, step: 10, unit: "mV")
        }
    }

    private func stepperRow(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue) \(unit)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .frame(width: 90, alignment: .trailing)
            }
        }
    }

    private var fanControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Lüftersteuerung")
                .font(.subheadline.weight(.medium))

            Toggle("Automatische Temperaturregelung (Auto-Fan)", isOn: $form.autoFanSpeed)
                .font(.subheadline)

            if !form.autoFanSpeed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Manuelle Lüfterdrehzahl:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(form.manualFanPercent)) %")
                            .font(.subheadline.weight(.medium).monospacedDigit())
                    }
                    Slider(value: $form.manualFanPercent, in: MinerSettingsForm.manualFanRange, step: 5)
                }
            }
        }
    }
}
