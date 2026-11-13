import Foundation
import IOKit.ps

enum EnergyRange: Double, CaseIterable, Identifiable {
    case hour = 3600
    case halfDay = 43200

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .hour: "Son 1 sa"
        case .halfDay: "Son 12 sa"
        }
    }
}

/// Uygulama başına harcanan enerjinin defteri (bellekte, en fazla 12 saat).
///
/// İşlem enerji sayaçlarının (`ri_energy_nj`) farkları 5 dakikalık kovalara yazılır. Kapanan kovada
/// yalnızca en çok harcayan `keepPerBucket` grup ayrı tutulur, gerisi "diğer" olarak toplanır; böylece
/// bellek kullanımı sınırlı kalır. Kova, pil/adaptör durumu değişince de kapanır (pildeyken filtresi için).
struct EnergyLedger: Sendable {
    struct Bucket: Sendable {
        let start: Date
        let onBattery: Bool
        /// Bu kovada ölçülen süre (sn).
        var seconds: Double
        /// Grup anahtarı → J.
        var energy: [String: Double]
        var others: Double
    }

    struct Entry: Sendable, Identifiable {
        let key: String
        let joules: Double
        var id: String { key }
    }

    struct Summary: Sendable {
        let entries: [Entry]
        /// Listede ayrı gösterilmeyenlerin toplamı (J).
        let others: Double
        let total: Double
        /// Ölçümün kapsadığı süre (sn).
        let seconds: Double
    }

    static let bucketLength: TimeInterval = 300
    static let capacity = Int(EnergyRange.halfDay.rawValue / bucketLength)
    static let keepPerBucket = 30

    private(set) var buckets: [Bucket] = []

    mutating func add(_ energy: [String: Double], seconds: Double, onBattery: Bool, at date: Date) {
        guard seconds > 0 else { return }
        if let last = buckets.last, last.onBattery == onBattery,
           date.timeIntervalSince(last.start) < Self.bucketLength {
            buckets[buckets.count - 1].seconds += seconds
            for (key, joules) in energy where joules > 0 {
                buckets[buckets.count - 1].energy[key, default: 0] += joules
            }
            return
        }
        if !buckets.isEmpty { buckets[buckets.count - 1].compact(keep: Self.keepPerBucket) }
        buckets.append(Bucket(start: date, onBattery: onBattery, seconds: seconds, energy: energy.filter { $0.value > 0 }, others: 0))
        if buckets.count > Self.capacity { buckets.removeFirst(buckets.count - Self.capacity) }
    }

    func summary(since start: Date, batteryOnly: Bool, limit: Int) -> Summary {
        var totals: [String: Double] = [:]
        var others = 0.0
        var seconds = 0.0
        for bucket in buckets where bucket.start >= start && (!batteryOnly || bucket.onBattery) {
            seconds += bucket.seconds
            others += bucket.others
            for (key, joules) in bucket.energy { totals[key, default: 0] += joules }
        }
        let sorted = totals.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let shown = sorted.prefix(limit).map { Entry(key: $0.key, joules: $0.value) }
        let hidden = sorted.dropFirst(limit).reduce(0) { $0 + $1.value }
        let total = totals.values.reduce(0, +) + others
        return Summary(entries: shown, others: others + hidden, total: total, seconds: seconds)
    }
}

extension EnergyLedger.Bucket {
    mutating func compact(keep: Int) {
        guard energy.count > keep else { return }
        let sorted = energy.sorted { $0.value > $1.value }
        others += sorted.dropFirst(keep).reduce(0) { $0 + $1.value }
        energy = Dictionary(uniqueKeysWithValues: sorted.prefix(keep).map { ($0.key, $0.value) })
    }
}

enum PowerSource {
    /// Mac şu an pilden mi besleniyor (IOPowerSources, pmset ile aynı).
    static func isOnBattery() -> Bool {
        guard let type = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }
}
