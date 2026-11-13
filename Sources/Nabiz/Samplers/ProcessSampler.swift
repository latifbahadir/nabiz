import AppKit
import Darwin
import Foundation

/// İşlemin (ya da grubunun) türü.
enum ProcessKind: Int, Sendable, Comparable {
    /// Dock'ta görünen, normal bir uygulama (ve yardımcı işlemleri).
    case app
    /// Menü çubuğu / arka plan uygulaması (.app paketi var ama Dock'ta değil).
    case backgroundApp
    /// macOS'un kendi servisleri (`/System`, `/usr` …).
    case system
    /// Paket dışı üçüncü taraf işlem: komut satırı aracı, daemon, ajan.
    case other

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .app: "Uygulama"
        case .backgroundApp: "Arka plan uygulaması"
        case .system: "Sistem servisi"
        case .other: "Diğer işlem"
        }
    }

    var symbol: String {
        switch self {
        case .app: "app"
        case .backgroundApp: "menubar.rectangle"
        case .system: "gearshape"
        case .other: "terminal"
        }
    }
}

/// İşlemin kimliği: yolundan çıkarılır, işlem yaşadıkça önbellekte tutulur.
struct ProcessIdentity: Sendable, Equatable {
    /// Gruplama anahtarı: en dıştaki `.app` paketinin yolu, yoksa çalıştırılabilir dosyanın yolu.
    let groupKey: String
    /// En dıştaki `.app` paketi (ör. Chrome yardımcıları için `/Applications/Google Chrome.app`).
    let bundlePath: String?
    /// Çalıştırılabilir dosyanın adı (ör. "Google Chrome Helper (Renderer)").
    let processName: String
    let isSystemPath: Bool

    static let systemPrefixes = [
        "/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/",
        "/private/var/db/com.apple.", "/Library/Developer/CoreSimulator/",
    ]

    static func from(path: String, fallbackName: String) -> ProcessIdentity {
        guard !path.isEmpty else {
            return ProcessIdentity(groupKey: "name:" + fallbackName, bundlePath: nil, processName: fallbackName, isSystemPath: false)
        }
        let processName = (path as NSString).lastPathComponent
        let isSystem = systemPrefixes.contains { path.hasPrefix($0) }
        // İlk ".app/" en dıştaki pakettir: yardımcı uygulamalar ana uygulamanın içinde durur.
        if let range = path.range(of: ".app/") {
            let bundle = String(path[..<range.lowerBound]) + ".app"
            return ProcessIdentity(groupKey: bundle, bundlePath: bundle, processName: processName, isSystemPath: isSystem)
        }
        return ProcessIdentity(groupKey: path, bundlePath: nil, processName: processName, isSystemPath: isSystem)
    }

    /// Türü belirler. `regularBundles`: Dock'ta görünen çalışan uygulamaların paket yolları.
    static func kind(bundlePath: String?, isSystemPath: Bool, regularBundles: Set<String>) -> ProcessKind {
        if let bundlePath, regularBundles.contains(bundlePath) { return .app }
        if isSystemPath { return .system }
        return bundlePath != nil ? .backgroundApp : .other
    }

    /// Kullanıcıya gösterilen grup adı.
    static func displayName(bundlePath: String?, processName: String) -> String {
        guard let bundlePath else { return processName }
        // Yerelleştirilmiş ad (ör. "Sistem Ayarları"); Finder uzantıları gösteriyorsa ".app" atılır.
        let name = FileManager.default.displayName(atPath: bundlePath)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Ölçüt: hangi kaynağa göre sıralanacağı.
enum ProcessMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, gpu, energy, disk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Bellek"
        case .gpu: "GPU"
        case .energy: "Enerji"
        case .disk: "Disk"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "square.stack.3d.up"
        case .energy: "bolt"
        case .disk: "internaldrive"
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .cpu, .gpu: Fmt.percent(value, digits: value < 0.1 ? 1 : 0)
        case .memory: Fmt.bytes(UInt64(max(value, 0)))
        case .energy: Fmt.power(value)
        case .disk: Fmt.rate(value)
        }
    }
}

/// Tek bir işlemin son ölçüm aralığındaki tüketimi.
struct ProcessUsage: Sendable, Identifiable {
    let pid: pid_t
    let name: String
    /// Çekirdek cinsinden (1.0 = bir çekirdek tam dolu; Activity Monitor "% CPU" / 100).
    var cpu: Double?
    /// `ri_phys_footprint` (Activity Monitor "Bellek" sütunu).
    var memory: UInt64?
    /// Ortalama güç (W) = Δ`ri_energy_nj` / Δt.
    var power: Double?
    /// Disk okuma + yazma (bayt/sn).
    var diskRate: Double?
    /// Uyanma / sn (kesme + paket boşta uyanmaları).
    var wakeups: Double?
    /// GPU süresi oranı (resmi olmayan kaynak).
    var gpu: Double?

    var id: pid_t { pid }

    func value(_ metric: ProcessMetric) -> Double? {
        switch metric {
        case .cpu: cpu
        case .memory: memory.map { Double($0) }
        case .gpu: gpu
        case .energy: power
        case .disk: diskRate
        }
    }
}

/// Bir uygulama ya da servis: aynı gruptaki işlemlerin toplamı.
struct AppUsage: Sendable, Identifiable {
    let key: String
    let name: String
    let kind: ProcessKind
    let bundlePath: String?
    let processes: [ProcessUsage]
    private let totals: [ProcessMetric: Double]

    var id: String { key }

    init(key: String, name: String, kind: ProcessKind, bundlePath: String?, processes: [ProcessUsage]) {
        self.key = key
        self.name = name
        self.kind = kind
        self.bundlePath = bundlePath
        self.processes = processes
        var totals: [ProcessMetric: Double] = [:]
        for metric in ProcessMetric.allCases {
            let values = processes.compactMap { $0.value(metric) }
            if !values.isEmpty { totals[metric] = values.reduce(0, +) }
        }
        self.totals = totals
    }

    /// Gruptaki okunabilen işlemlerin toplamı; hiçbiri okunamadıysa `nil`.
    func value(_ metric: ProcessMetric) -> Double? { totals[metric] }
}

struct ProcessSnapshot: Sendable {
    let date: Date
    let apps: [AppUsage]
    /// `proc_pid_rusage` ile okunabilen işlem sayısı.
    let readableCount: Int
    /// Yetki gerektiren (root / başka kullanıcı) işlem sayısı.
    let restrictedCount: Int
    /// Ölçüm aralığı (sn); ilk taramada `nil` (oranlar henüz yok).
    let interval: TimeInterval?

    /// Seçilen ölçüte göre en çok kullananlar (sıfır olanlar elenir).
    func top(_ metric: ProcessMetric, limit: Int) -> [AppUsage] {
        Self.top(apps, metric: metric, limit: limit)
    }

    /// Okunabilen tüm işlemlerin toplam CPU'su (çekirdek).
    var totalCPU: Double { apps.reduce(0) { $0 + ($1.value(.cpu) ?? 0) } }

    static func top(_ apps: [AppUsage], metric: ProcessMetric, limit: Int) -> [AppUsage] {
        let ranked = apps.compactMap { app in app.value(metric).flatMap { $0 > 0 ? (app, $0) : nil } }
        return ranked
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .prefix(limit)
            .map(\.0)
    }
}

/// Bir grubun kalıcı bilgisi; işlem kapansa da enerji defteri için adı saklanır.
struct ProcessGroupInfo: Sendable {
    let name: String
    let bundlePath: String?
    var kind: ProcessKind
}

/// Sayaç farkı: önceki değerden küçükse (sayaç sıfırlanmış) sıfır.
enum CounterMath {
    static func delta(_ current: UInt64, _ previous: UInt64) -> UInt64 {
        current >= previous ? current - previous : 0
    }

    static func rate(_ current: UInt64, _ previous: UInt64, seconds: TimeInterval, scale: Double = 1) -> Double? {
        guard seconds > 0 else { return nil }
        return Double(delta(current, previous)) * scale / seconds
    }
}

/// Tüm işlemleri `proc_pid_rusage(RUSAGE_INFO_V6)` ile okur (resmi API; Activity Monitor ile aynı sayaçlar).
///
/// - Kimlik (yol, grup) işlem başına bir kez `proc_pidpath` ile çözülür ve `ri_proc_start_abstime` ile
///   pid yeniden kullanımına karşı denetlenir.
/// - Root ya da başka kullanıcıya ait işlemler yetki olmadan okunamaz; sayıları raporlanır.
/// - Tam tarama ~1000 işlemde birkaç ms sürer: panel açıkken her tikte, kapalıyken yalnızca
///   enerji defteri için seyrek yapılır.
final class ProcessSampler {
    struct Counters {
        let start: UInt64
        let cpu: UInt64      // mach zaman birimi
        let energy: UInt64   // nJ
        let disk: UInt64     // bayt
        let wakeups: UInt64
    }

    struct Scan {
        let date: Date
        /// Önceki taramadan bu yana geçen süre; ilk taramada `nil`.
        let interval: TimeInterval?
        let processes: [(identity: ProcessIdentity, usage: ProcessUsage)]
        let restrictedPIDs: [pid_t]
        /// Grup başına bu aralıkta harcanan enerji (J).
        let energyByGroup: [String: Double]
    }

    private var previous: [pid_t: Counters] = [:]
    private var identities: [pid_t: (start: UInt64, identity: ProcessIdentity)] = [:]
    private(set) var groups: [String: ProcessGroupInfo] = [:]
    private var lastScanAbs: UInt64?
    private var pidBuffer: [pid_t] = []
    private let nanosPerTick: Double

    init() {
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        nanosPerTick = timebase.denom == 0 ? 1 : Double(timebase.numer) / Double(timebase.denom)
    }

    func scan() -> Scan {
        let nowAbs = mach_absolute_time()
        let seconds = lastScanAbs.map { Double(nowAbs &- $0) * nanosPerTick / 1e9 }
        let pids = listPIDs()

        var processes: [(identity: ProcessIdentity, usage: ProcessUsage)] = []
        processes.reserveCapacity(pids.count)
        var restricted: [pid_t] = []
        var energy: [String: Double] = [:]
        var nextPrevious: [pid_t: Counters] = [:]
        nextPrevious.reserveCapacity(pids.count)
        var nextIdentities: [pid_t: (start: UInt64, identity: ProcessIdentity)] = [:]
        nextIdentities.reserveCapacity(pids.count)

        for pid in pids {
            guard let info = Self.rusage(pid) else {
                restricted.append(pid)
                continue
            }
            let counters = Counters(
                start: info.ri_proc_start_abstime,
                cpu: info.ri_user_time &+ info.ri_system_time,
                energy: info.ri_energy_nj,
                disk: info.ri_diskio_bytesread &+ info.ri_diskio_byteswritten,
                wakeups: info.ri_interrupt_wkups &+ info.ri_pkg_idle_wkups
            )
            let identity: ProcessIdentity
            if let cached = identities[pid], cached.start == counters.start {
                identity = cached.identity
            } else {
                identity = Self.identity(pid)
            }
            nextIdentities[pid] = (counters.start, identity)
            nextPrevious[pid] = counters

            var usage = ProcessUsage(pid: pid, name: identity.processName, memory: info.ri_phys_footprint)
            if let seconds, let old = previous[pid], old.start == counters.start {
                usage.cpu = CounterMath.rate(counters.cpu, old.cpu, seconds: seconds, scale: nanosPerTick / 1e9)
                usage.power = CounterMath.rate(counters.energy, old.energy, seconds: seconds, scale: 1e-9)
                usage.diskRate = CounterMath.rate(counters.disk, old.disk, seconds: seconds)
                usage.wakeups = CounterMath.rate(counters.wakeups, old.wakeups, seconds: seconds)
                energy[identity.groupKey, default: 0] += Double(CounterMath.delta(counters.energy, old.energy)) * 1e-9
            } else if let lastScanAbs, counters.start > lastScanAbs {
                // Önceki taramadan sonra başlamış: tüm enerjisi bu aralığa aittir.
                energy[identity.groupKey, default: 0] += Double(counters.energy) * 1e-9
            }
            processes.append((identity, usage))
        }

        previous = nextPrevious
        identities = nextIdentities
        lastScanAbs = nowAbs
        updateGroups(processes.map(\.identity))
        return Scan(date: Date(), interval: seconds, processes: processes, restrictedPIDs: restricted, energyByGroup: energy)
    }

    /// Taramayı uygulama gruplarına toplar. `gpu`: pid → GPU süresi oranı (okunabildiyse).
    func snapshot(from scan: Scan, gpu: [pid_t: Double]?) -> ProcessSnapshot {
        var byGroup: [String: [ProcessUsage]] = [:]
        var seen = Set<pid_t>()
        for (identity, var usage) in scan.processes {
            usage.gpu = gpu?[usage.pid]
            seen.insert(usage.pid)
            byGroup[identity.groupKey, default: []].append(usage)
        }
        // Yetki gerektiren işlemler (ör. WindowServer) yalnızca GPU'da görünür.
        if let gpu {
            for (pid, value) in gpu where !seen.contains(pid) && value > 0 {
                let identity = Self.identity(pid)
                updateGroups([identity])
                byGroup[identity.groupKey, default: []]
                    .append(ProcessUsage(pid: pid, name: identity.processName, gpu: value))
            }
        }
        let apps = byGroup.map { key, processes in
            let info = groups[key]
            return AppUsage(
                key: key,
                name: info?.name ?? key,
                kind: info?.kind ?? .other,
                bundlePath: info?.bundlePath,
                processes: processes
            )
        }
        return ProcessSnapshot(
            date: scan.date,
            apps: apps,
            readableCount: scan.processes.count,
            restrictedCount: scan.restrictedPIDs.count,
            interval: scan.interval
        )
    }

    /// Grup adlarını ve türlerini günceller (tür, uygulamanın Dock'ta olup olmamasına göre değişebilir).
    private func updateGroups(_ identities: [ProcessIdentity]) {
        let regular = Self.regularBundles()
        for identity in identities {
            let kind = ProcessIdentity.kind(bundlePath: identity.bundlePath, isSystemPath: identity.isSystemPath, regularBundles: regular)
            if groups[identity.groupKey] != nil {
                groups[identity.groupKey]?.kind = kind
            } else {
                groups[identity.groupKey] = ProcessGroupInfo(
                    name: ProcessIdentity.displayName(bundlePath: identity.bundlePath, processName: identity.processName),
                    bundlePath: identity.bundlePath,
                    kind: kind
                )
            }
        }
    }

    private static func regularBundles() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { app in
            app.activationPolicy == .regular ? app.bundleURL?.path : nil
        })
    }

    private func listPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        let capacity = Int(estimate) + 64
        if pidBuffer.count < capacity { pidBuffer = [pid_t](repeating: 0, count: capacity) }
        let count = pidBuffer.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(pidBuffer.prefix(Int(count)))
    }

    static func rusage(_ pid: pid_t) -> rusage_info_v6? {
        var info = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
            }
        }
        return result == 0 ? info : nil
    }

    static func identity(_ pid: pid_t) -> ProcessIdentity {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(cString: buffer) : ""
        var nameBuffer = [CChar](repeating: 0, count: 64)
        let name = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 ? String(cString: nameBuffer) : "pid \(pid)"
        return ProcessIdentity.from(path: path, fallbackName: pid == 0 ? "kernel_task" : name)
    }
}
