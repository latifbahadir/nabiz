import Darwin

/// `vm_statistics64` içindeki ham sayfa sayıları (vm_stat çıktısıyla aynı alanlar).
struct RawVMStats: Sendable {
    var free: UInt64 = 0
    var active: UInt64 = 0
    var inactive: UInt64 = 0
    var speculative: UInt64 = 0
    var throttled: UInt64 = 0
    var wired: UInt64 = 0
    var purgeable: UInt64 = 0
    var fileBacked: UInt64 = 0
    var anonymous: UInt64 = 0
    var compressor: UInt64 = 0
}

enum MemoryPressure: Sendable {
    case normal, warning, critical, unknown

    init(level: Int64?) {
        switch level {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

struct MemorySnapshot: Sendable {
    let total: UInt64
    let pageSize: UInt64
    let raw: RawVMStats

    /// Activity Monitor'deki tanımlar:
    /// Uygulama = anonim − temizlenebilir, Önbellek = dosya destekli + temizlenebilir
    var app: UInt64 { (raw.anonymous &- min(raw.purgeable, raw.anonymous)) * pageSize }
    var wired: UInt64 { raw.wired * pageSize }
    var compressed: UInt64 { raw.compressor * pageSize }
    var cachedFiles: UInt64 { (raw.fileBacked + raw.purgeable) * pageSize }
    /// Kullanılan = Uygulama + Sabit + Sıkıştırılmış
    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    let swapUsed: UInt64
    let swapTotal: UInt64
    let pressure: MemoryPressure
    /// `kern.memorystatus_level`: çekirdeğin kullanılabilir saydığı bellek yüzdesi.
    let availablePercent: Int?
}

/// `host_statistics64(HOST_VM_INFO64)` ile bellek sayaçlarını okur.
final class MemorySampler {
    private let host = mach_host_self()
    private let total = UInt64(Sysctl.integer("hw.memsize") ?? 0)
    private let pageSize: UInt64

    init() {
        var size: vm_size_t = 0
        pageSize = host_page_size(mach_host_self(), &size) == KERN_SUCCESS ? UInt64(size) : 16384
    }

    func sample() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let raw = RawVMStats(
            free: UInt64(stats.free_count),
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            speculative: UInt64(stats.speculative_count),
            throttled: UInt64(stats.throttled_count),
            wired: UInt64(stats.wire_count),
            purgeable: UInt64(stats.purgeable_count),
            fileBacked: UInt64(stats.external_page_count),
            anonymous: UInt64(stats.internal_page_count),
            compressor: UInt64(stats.compressor_page_count)
        )
        let swap = Sysctl.swapUsage()
        return MemorySnapshot(
            total: total,
            pageSize: pageSize,
            raw: raw,
            swapUsed: swap?.xsu_used ?? 0,
            swapTotal: swap?.xsu_total ?? 0,
            pressure: MemoryPressure(level: Sysctl.integer("kern.memorystatus_vm_pressure_level")),
            availablePercent: Sysctl.integer("kern.memorystatus_level").map(Int.init)
        )
    }
}
