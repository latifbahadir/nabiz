import Foundation
import IOKit

struct DiskCapacity: Sendable {
    let volumeName: String?
    let total: Int64
    /// Finder'ın gösterdiği "kullanılabilir" (temizlenebilir alan dahil).
    let availableForImportantUsage: Int64
    /// Yalnızca boş bloklar (`df` "Avail" sütununa yakın).
    let availablePlain: Int64
    var used: Int64 { max(total - availableForImportantUsage, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct DiskIOSnapshot: Sendable {
    /// read = okunan, written = yazılan
    let rate: RateSnapshot
    let totals: ByteCounters
    let driverCount: Int
}

/// Disk G/Ç: IOKit `IOBlockStorageDriver` sürücülerinin `Statistics` sözlüğü
/// (`Bytes (Read)`, `Bytes (Write)`; `iostat` ile aynı kaynak).
/// Doluluk: `/` biriminin `URLResourceValues` değerleri (Finder ile aynı).
final class DiskSampler {
    /// Kayıt kimliği → sürücü. Disk takılıp çıkarıldığında yakalamak için periyodik yenilenir.
    private var drivers: [UInt64: io_object_t] = [:]
    private var ticksSinceRefresh = Int.max
    private let refreshEvery = 30
    private var previous: (uptime: TimeInterval, counters: [UInt64: ByteCounters])?

    deinit {
        drivers.values.forEach { IOObjectRelease($0) }
    }

    func sampleIO() -> DiskIOSnapshot? {
        if ticksSinceRefresh >= refreshEvery { refreshDrivers() }
        ticksSinceRefresh += 1

        let now = ProcessInfo.processInfo.systemUptime
        var current: [UInt64: ByteCounters] = [:]
        for (id, driver) in drivers {
            guard
                let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any]
            else { continue }
            current[id] = ByteCounters(
                read: (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0,
                written: (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            )
        }
        defer { previous = (now, current) }
        guard let previous, now > previous.uptime else { return nil }

        let totals = current.values.reduce(into: ByteCounters()) {
            $0.read += $1.read
            $0.written += $1.written
        }
        return DiskIOSnapshot(
            rate: RateSnapshot(
                delta: ByteCounters.delta(previous: previous.counters, current: current),
                interval: now - previous.uptime
            ),
            totals: totals,
            driverCount: current.count
        )
    }

    static func capacity() -> DiskCapacity? {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        ]
        guard
            let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
            let total = values.volumeTotalCapacity,
            let important = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskCapacity(
            volumeName: values.volumeLocalizedName,
            total: Int64(total),
            availableForImportantUsage: important,
            availablePlain: Int64(values.volumeAvailableCapacity ?? 0)
        )
    }

    private func refreshDrivers() {
        ticksSinceRefresh = 0
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
                == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var fresh: [UInt64: io_object_t] = [:]
        while case let driver = IOIteratorNext(iterator), driver != 0 {
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(driver, &id) == KERN_SUCCESS, drivers[id] == nil {
                fresh[id] = driver
            } else if drivers[id] != nil {
                fresh[id] = drivers.removeValue(forKey: id)
                IOObjectRelease(driver)
            } else {
                IOObjectRelease(driver)
            }
        }
        drivers.values.forEach { IOObjectRelease($0) } // artık bulunmayan sürücüler
        drivers = fresh
    }
}
