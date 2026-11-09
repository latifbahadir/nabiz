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

    /// Hız, ondalık birimler (1 KB = 1000 bayt): "0 B/sn", "340 KB/sn", "1,2 MB/sn".
    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        let units = ["B", "KB", "MB", "GB"]
        var scaled = value
        var unit = 0
        while scaled >= 1000, unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }
        let digits = unit == 0 || scaled >= 100 ? 0 : 1
        return number(scaled, digits: digits) + " \(units[unit])/sn"
    }

    /// Disk boyutları, ondalık birimler (Finder ve `df -H` ile aynı).
    static func decimalBytes(_ bytes: Int64) -> String {
        let value = Double(bytes)
        if value >= 1e12 { return number(value / 1e12, digits: 2) + " TB" }
        if value >= 1e9 { return number(value / 1e9, digits: 1) + " GB" }
        return number(value / 1e6, digits: 0) + " MB"
    }

    /// 43.25 → "43,3 °C"
    static func celsius(_ value: Double, digits: Int = 1) -> String {
        number(value, digits: digits) + " °C"
    }

    /// 571 → "9 sa 31 dk", 45 → "45 dk"
    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours > 0 ? "\(hours) sa \(rest) dk" : "\(rest) dk"
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
