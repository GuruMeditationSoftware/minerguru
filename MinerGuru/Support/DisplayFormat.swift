import Foundation

/// Central number formatting.
///
/// Percentages, odds and durations follow the Mac's region like all other numbers (`1.234,56` in Germany).
/// Unit tests, which run outside the app bundle, always use German notation.
/// Technical miner metrics (hashrate, difficulty) intentionally keep the dot notation
/// of the miners' own AxeOS web interface, see `MinerFormatting`.
enum DisplayFormat {
    static let locale: Locale = Bundle.main.localizations.contains("en") ? .autoupdatingCurrent : Locale(identifier: "de_DE")

    /// Fixed number of fraction digits, e.g. `decimal(1234.5, fractionDigits: 2)` → `"1.234,50"`.
    static func decimal(_ value: Double, fractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// Up to `maxFractionDigits` fraction digits, trailing zeros dropped, e.g. `3.125` → `"3,125"`.
    static func decimal(_ value: Double, maxFractionDigits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(locale))
    }

    /// `"1,23 %"`
    static func percent(_ value: Double, fractionDigits: Int) -> String {
        "\(decimal(value, fractionDigits: fractionDigits)) %"
    }
}
