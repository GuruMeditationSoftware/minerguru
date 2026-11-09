import SwiftUI

/// The eight key-figure cards of a miner (hashrate, temperature, power, …).
struct MinerKPIGrid: View {
    let miner: MinerDevice
    let info: MinerSystemInfo
    let tempWarningThresholdC: Double

    var body: some View {
        let hashrate = MinerFormatting.splitHashrate(info.hashRate)
        let isHighTemp = info.temp >= tempWarningThresholdC
        let latencyMs = miner.activePoolLatencyMs

        AdaptiveGrid(minColumnWidth: 260, spacing: 16) {
            MetricCardView(
                title: "Live Hashrate",
                value: hashrate.value,
                unit: hashrate.unit,
                subtitle: info.hashrateAveragesText,
                systemImage: "bolt.horizontal.circle.fill",
                tint: miner.isNerdOS ? .purple : .orange
            )
            MetricCardView(
                title: "ASIC Temperatur",
                value: String(format: "%.1f", info.temp),
                unit: "°C",
                subtitle: info.coolingText(warningThresholdC: tempWarningThresholdC),
                systemImage: "thermometer.medium",
                tint: isHighTemp ? .red : (info.temp > 62 ? .orange : .green),
                warning: isHighTemp || info.overheatMode
            )
            MetricCardView(
                title: "Verbrauch",
                value: String(format: "%.1f", info.power),
                unit: "W",
                subtitle: info.powerDetailText,
                systemImage: "bolt.fill",
                tint: .yellow
            )
            MetricCardView(
                title: "Effizienz",
                value: info.efficiencyJPerTH > 0 ? String(format: "%.1f", info.efficiencyJPerTH) : "—",
                unit: "J/TH",
                subtitle: info.dailyEnergyText,
                systemImage: "leaf.fill",
                tint: .green
            )
            MetricCardView(
                title: "Kühlung & Lüfter",
                value: info.fanPercentText,
                unit: "%",
                subtitle: info.fanRPMText,
                systemImage: "wind",
                tint: .blue
            )
            MetricCardView(
                title: "ASIC Takt & VCore",
                value: "\(info.frequencyMHz)",
                unit: "MHz",
                subtitle: info.coreVoltageText,
                systemImage: "waveform",
                tint: .teal
            )
            MetricCardView(
                title: info.isDualPoolMining ? "Pool-Latenz (Dual RTT)" : "Pool-Latenz (RTT)",
                value: latencyMs.map { String(format: "%.0f", $0) } ?? "—",
                unit: latencyMs != nil ? "ms" : nil,
                subtitle: miner.poolLatencyDetailText,
                systemImage: info.isDualPoolMining ? "arrow.triangle.branch" : "globe.europe.africa.fill",
                tint: LatencyQuality.evaluate(latencyMs).color
            )
            MetricCardView(
                title: "Best Diff (seit Neustart)",
                value: info.sessionBestDiffText,
                subtitle: String(localized: "Allzeit-Best: \(info.bestDiffFormatted)"),
                systemImage: "trophy.fill",
                tint: .indigo
            )
            MetricCardView(
                title: "Shares",
                value: "\(info.sharesAccepted)",
                subtitle: info.sharesText,
                systemImage: "checkmark.seal.fill",
                tint: .blue
            )
        }
    }
}
