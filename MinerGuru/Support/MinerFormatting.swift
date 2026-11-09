import Foundation

/// Formatting of technical miner metrics. Uses the dot notation of the miners' AxeOS web UI
/// (`1.05 TH/s`, `4.40G`) on purpose; prices and percentages use `DisplayFormat` (German notation).
enum MinerFormatting {
    /// Formats hashrate given in GH/s into TH/s (when >= 1000 GH/s) or GH/s.
    static func formatHashrate(_ ghs: Double) -> String {
        guard ghs > 0 else { return "0 GH/s" }
        if ghs >= 1000.0 {
            return String(format: "%.2f TH/s", ghs / 1000.0)
        }
        return String(format: "%.0f GH/s", ghs)
    }

    /// Formats hashrate numeric value and unit separately for large KPI cards.
    static func splitHashrate(_ ghs: Double) -> (value: String, unit: String) {
        guard ghs > 0 else { return ("0", "GH/s") }
        if ghs >= 1000.0 {
            return (String(format: "%.2f", ghs / 1000.0), "TH/s")
        }
        return (String(format: "%.0f", ghs), "GH/s")
    }

    static func formatUptime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    static func formatLatency(_ ms: Double?) -> String {
        guard let ms, ms > 0 else { return "—" }
        if ms < 10 {
            return String(format: "%.1f ms", ms)
        }
        return String(format: "%.0f ms", ms)
    }
}
