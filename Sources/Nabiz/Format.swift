import Foundation

enum Fmt {
    static let locale = Locale(identifier: "tr_TR")

    /// 0.123 → "%12"
    static func percent(_ fraction: Double, digits: Int = 0) -> String {
        "%" + number(fraction * 100, digits: digits)
    }

    /// Menü çubuğu için: genişlik oynamasın diye tek haneli değerler figure space ile doldurulur.
    static func paddedPercent(_ fraction: Double) -> String {
        let value = Int((fraction * 100).rounded())
        return "%" + (value < 10 ? "\u{2007}" : "") + String(value)
    }

    static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    static func integer(_ value: UInt64) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
    }

    /// İkili birimler (1 GB = 1024³ bayt), Activity Monitor ile aynı.
    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let gb = value / 1_073_741_824
        if gb >= 1 { return number(gb, digits: 1) + " GB" }
        let mb = value / 1_048_576
        return number(mb, digits: mb >= 10 ? 0 : 1) + " MB"
    }
}
