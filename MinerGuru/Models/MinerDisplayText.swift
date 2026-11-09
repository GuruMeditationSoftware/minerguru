import Foundation

/// Subtitles and values for the miner detail KPI cards. Kept in the model layer so the
/// wording and edge cases (dual fans, dual pools, missing averages) are unit-testable.
extension MinerSystemInfo {
    /// `"1m: 1.07 TH/s • 1h: 1.07 TH/s"`, `"1m Ø: 980 GH/s"` or `"1216 GH/s Live"`.
    var hashrateAveragesText: String {
        if let h1m = hashRate1m, let h1h = hashRate1h {
            return "1m: \(MinerFormatting.formatHashrate(h1m)) • 1h: \(MinerFormatting.formatHashrate(h1h))"
        }
        if let h1m = hashRate1m {
            return "1m Ø: \(MinerFormatting.formatHashrate(h1m))"
        }
        return String(format: "%.0f GH/s Live", hashRate)
    }

    /// `"PID Auto"` (NerdQAxe), `"Auto-Modus"` or `"Manuell"`.
    var fanModeLabel: String {
        if autoFanModeRaw == 2 { return "PID Auto" }
        return autoFanSpeed ? String(localized: "Auto mode") : String(localized: "Manual")
    }

    private var hasSecondFan: Bool { (fan2RPM ?? 0) > 0 }

    /// `"70"` or `"40 / 19"` for dual-fan devices.
    var fanPercentText: String {
        if hasSecondFan, let fan2SpeedPercent {
            return String(format: "%.0f / %.0f", fanSpeedPercent, fan2SpeedPercent)
        }
        return String(format: "%.0f", fanSpeedPercent)
    }

    /// `"5299 RPM • Manuell"` or `"1248 & 2592 RPM • PID Auto"`.
    var fanRPMText: String {
        if hasSecondFan, let fan2RPM {
            return "\(fanRPM) & \(fan2RPM) RPM • \(fanModeLabel)"
        }
        return "\(fanRPM) RPM • \(fanModeLabel)"
    }

    /// Voltage regulator temperature if reported, otherwise a short cooling verdict.
    func coolingText(warningThresholdC: Double) -> String {
        if let vrTemp {
            return String(format: String(localized: "Voltage regulator (VR): %.1f °C"), vrTemp)
        }
        return temp >= warningThresholdC ? String(localized: "Cooling: Elevated") : String(localized: "Cooling: Optimal")
    }

    var powerDetailText: String {
        String(format: "%.2f V • %.2f A", voltageVolts, currentAmps)
    }

    var dailyEnergyText: String {
        String(format: "~%.2f kWh / 24h", power * 24.0 / 1000.0)
    }

    var coreVoltageText: String {
        String(localized: "Target: \(String(coreVoltageTargetMV)) mV • Actual: \(String(coreVoltageActualMV)) mV")
    }

    var sharesText: String {
        "Shares: \(sharesAccepted) ok / \(sharesRejected) rej (\(String(format: "%.2f%%", shareRejectionRatePercent)))"
    }
}

extension MinerDevice {
    /// `"Dual (1%/99%) • P1: 20 ms / P2: 30 ms"` or `"Exzellent • eusolo.ckpool.org"`.
    var poolLatencyDetailText: String {
        guard let info = latestInfo else { return "—" }
        if info.isDualPoolMining {
            let p1 = primaryPoolEffectiveLatencyMs.map { String(format: "%.0f", $0) } ?? "—"
            let p2 = secondaryPoolEffectiveLatencyMs.map { String(format: "%.0f", $0) } ?? "—"
            return "Dual (\(info.dualPoolPrimaryPercent)%/\(info.dualPoolSecondaryPercent)%) • P1: \(p1) ms / P2: \(p2) ms"
        }
        return "\(LatencyQuality.evaluate(activePoolLatencyMs).label) • \(info.activePoolHost)"
    }

    var webInterfaceURL: URL? {
        URL(string: "http://\(ipAddress)")
    }
}
