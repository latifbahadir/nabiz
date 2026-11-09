import Darwin

/// Bir çekirdeğin (veya toplamın) kernel tick sayaçları.
struct CPUTicks: Sendable {
    var user: UInt32 = 0
    var system: UInt32 = 0
    var idle: UInt32 = 0
    var nice: UInt32 = 0

    var busy: UInt64 { UInt64(user) + UInt64(system) + UInt64(nice) }
    var total: UInt64 { busy + UInt64(idle) }
}

struct CoreLoad: Identifiable, Sendable {
    let id: Int
    /// user + nice (top da nice'ı user'a katar)
    let user: Double
    let system: Double
    var total: Double { user + system }
}

struct CPUSnapshot: Sendable {
    let user: Double
    let system: Double
    let idle: Double
    var total: Double { user + system }
    let cores: [CoreLoad]
    /// Son aralıktaki tüm çekirdeklerin toplam tick farkı (doğrulama için).
    let delta: (user: UInt64, system: UInt64, nice: UInt64, idle: UInt64)
    let loadAverage: [Double]
}

/// `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` ile çekirdek başına
/// tick sayaçlarını okur; kullanım iki okuma arasındaki farktan hesaplanır.
/// Activity Monitor ve `top` da aynı sayaçları kullanır.
final class CPUSampler {
    private let host = mach_host_self()
    private var previous: [CPUTicks]?

    func sample() -> CPUSnapshot? {
        guard let current = readTicks() else { return nil }
        defer { previous = current }
        guard let previous, previous.count == current.count else { return nil }

        var cores: [CoreLoad] = []
        cores.reserveCapacity(current.count)
        var sum: (user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) = (0, 0, 0, 0)

        for i in current.indices {
            // Sayaçlar 32 bit; taşmaya karşı sarmalı çıkarma.
            let user = UInt64(current[i].user &- previous[i].user)
            let system = UInt64(current[i].system &- previous[i].system)
            let nice = UInt64(current[i].nice &- previous[i].nice)
            let idle = UInt64(current[i].idle &- previous[i].idle)
            let total = Double(user + system + nice + idle)
            cores.append(CoreLoad(
                id: i,
                user: total > 0 ? Double(user + nice) / total : 0,
                system: total > 0 ? Double(system) / total : 0
            ))
            sum.user += user; sum.system += system; sum.nice += nice; sum.idle += idle
        }

        let total = Double(sum.user + sum.system + sum.nice + sum.idle)
        guard total > 0 else { return nil }

        var load = [Double](repeating: 0, count: 3)
        if getloadavg(&load, 3) != 3 { load = [] }

        return CPUSnapshot(
            user: Double(sum.user + sum.nice) / total,
            system: Double(sum.system) / total,
            idle: Double(sum.idle) / total,
            cores: cores,
            delta: sum,
            loadAverage: load
        )
    }

    private func readTicks() -> [CPUTicks]? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }

        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { cpu in
            let base = cpu * stride
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }
}
