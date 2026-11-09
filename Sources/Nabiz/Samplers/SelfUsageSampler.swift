import Darwin
import Foundation

/// Nabız'ın kendi kaynak tüketimi.
struct SelfUsage: Sendable {
    /// Son iki ölçüm arasındaki CPU kullanımı (tek çekirdek = 1.0).
    let recentCPU: Double?
    /// Uygulama açıldığından beri ortalama CPU kullanımı.
    let averageCPU: Double
    /// Açıldığından beri saniye başına ortalama uyanma (pil için önemli).
    let averageWakeups: Double
    /// Activity Monitor'deki "Bellek" sütunuyla aynı değer (phys_footprint).
    let footprint: UInt64
}

final class SelfUsageSampler {
    private let startUptime = ProcessInfo.processInfo.systemUptime
    private var last: (uptime: TimeInterval, cpu: TimeInterval)?

    func sample() -> SelfUsage {
        let now = ProcessInfo.processInfo.systemUptime
        let cpu = cpuTime()

        let recent: Double?
        if let last, now - last.uptime > 0.5 {
            recent = (cpu - last.cpu) / (now - last.uptime)
        } else {
            recent = nil
        }
        last = (now, cpu)

        let lifetime = max(now - startUptime, 1)
        return SelfUsage(
            recentCPU: recent,
            averageCPU: cpu / lifetime,
            averageWakeups: Double(wakeups()) / lifetime,
            footprint: footprint()
        )
    }

    private func cpuTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ t: timeval) -> TimeInterval { TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private func wakeups() -> UInt64 {
        var info = task_power_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.task_interrupt_wakeups + info.task_platform_idle_wakeups
    }

    private func footprint() -> UInt64 {
        var info = task_vm_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
