import Foundation
import IOKit

/// Aynı performans seviyesindeki çekirdekler (ör. "Super", "Performance", "Efficiency").
struct CoreGroup: Identifiable, Sendable {
    /// `hw.perflevelN` içindeki N; 0 en hızlı seviyedir.
    let id: Int
    let name: String
    let cpuIDs: [Int]
}

/// Çekirdeklerin hangi gruba ait olduğu. Açılışta bir kez okunur.
///
/// Çekirdek sırası çipe göre değişir (ör. M5 Pro'da cpu0–11 "Performance",
/// cpu12–17 "Super"), bu yüzden sıra varsayılmaz; IODeviceTree'deki her
/// çekirdeğin `logical-cpu-id` ve `cluster-type` değerleri okunur ve
/// `hw.perflevelN.logicalcpu` sayılarıyla eşleştirilir.
struct CPUTopology: Sendable {
    let chip: String
    let cpuCount: Int
    let groups: [CoreGroup]

    static func load() -> CPUTopology {
        let chip = Sysctl.string("machdep.cpu.brand_string") ?? "Mac"
        let cpuCount = Int(Sysctl.integer("hw.ncpu") ?? 0)
        let fallback = CPUTopology(
            chip: chip, cpuCount: cpuCount,
            groups: [CoreGroup(id: 0, name: "Tüm", cpuIDs: Array(0..<cpuCount))]
        )

        let levelCount = Int(Sysctl.integer("hw.nperflevels") ?? 0)
        guard levelCount > 1 else { return fallback }

        var byClusterType = readClusterTypes()
        guard byClusterType.values.reduce(0, { $0 + $1.count }) == cpuCount else { return fallback }

        var groups: [CoreGroup] = []
        for level in 0..<levelCount {
            guard
                let count = Sysctl.integer("hw.perflevel\(level).logicalcpu"),
                let match = byClusterType.first(where: { $0.value.count == Int(count) })
            else { return fallback }
            byClusterType.removeValue(forKey: match.key)
            let name = Sysctl.string("hw.perflevel\(level).name") ?? match.key
            groups.append(CoreGroup(id: level, name: name, cpuIDs: match.value.sorted()))
        }
        return CPUTopology(chip: chip, cpuCount: cpuCount, groups: groups)
    }

    /// cluster-type ("P", "M", "E" …) → mantıksal CPU numaraları
    private static func readClusterTypes() -> [String: [Int]] {
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard cpus != 0 else { return [:] }
        defer { IOObjectRelease(cpus) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(cpus, "IODeviceTree", &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [String: [Int]] = [:]
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard
                let id = IORegistryEntryCreateCFProperty(child, "logical-cpu-id" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber,
                let typeData = IORegistryEntryCreateCFProperty(child, "cluster-type" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Data
            else { continue }
            let type = String(decoding: typeData.prefix { $0 != 0 }, as: UTF8.self)
            result[type, default: []].append(id.intValue)
        }
        return result
    }
}
