import Foundation
import IOKit
import NabizUnofficial

struct GPUSnapshot: Sendable {
    /// `Device Utilization %` / 100 — GPU'nun herhangi bir işle meşgul olduğu süre oranı.
    let device: Double
    /// `Renderer Utilization %` / 100 (piksel/hesaplama birimleri).
    let renderer: Double?
    /// `Tiler Utilization %` / 100 (geometri birimi).
    let tiler: Double?
    /// `In use system memory` (bayt) — GPU'nun şu an kullandığı birleşik bellek.
    let inUseMemory: UInt64?
    /// `Alloc system memory` (bayt) — GPU sürücüsünün ayırdığı birleşik bellek.
    let allocatedMemory: UInt64?
    /// Doğrulama ekranı için ham anahtar–değer çiftleri (yalnızca panel açıkken doldurulur).
    let raw: [RawValue]

    struct RawValue: Sendable, Hashable {
        let key: String
        let value: String
    }

    static let deviceKey = "Device Utilization %"
    static let rendererKey = "Renderer Utilization %"
    static let tilerKey = "Tiler Utilization %"
    static let inUseMemoryKey = "In use system memory"
    static let allocatedMemoryKey = "Alloc system memory"

    /// `PerformanceStatistics` sözlüğünden anlık görüntü üretir.
    /// Kullanım anahtarı yoksa ya da 0…100 dışındaysa hata döner (ölçek değişmiş olabilir).
    static func parse(_ stats: [String: Any], includeRaw: Bool) -> Result<GPUSnapshot, UnofficialError> {
        guard let device = CFValue.double(stats[deviceKey]) else {
            return .failure(UnofficialError("“\(deviceKey)” anahtarı yok veya sayı değil"))
        }
        guard let deviceFraction = fraction(device) else {
            return .failure(UnofficialError("“\(deviceKey)” beklenmeyen değer: \(device)"))
        }
        func bytes(_ key: String) -> UInt64? {
            CFValue.int64(stats[key]).flatMap { $0 >= 0 ? UInt64($0) : nil }
        }
        return .success(GPUSnapshot(
            device: deviceFraction,
            renderer: CFValue.double(stats[rendererKey]).flatMap(fraction),
            tiler: CFValue.double(stats[tilerKey]).flatMap(fraction),
            inUseMemory: bytes(inUseMemoryKey),
            allocatedMemory: bytes(allocatedMemoryKey),
            raw: includeRaw ? rawValues(stats) : []
        ))
    }

    private static func fraction(_ percent: Double) -> Double? {
        (0...100).contains(percent) ? percent / 100 : nil
    }

    private static func rawValues(_ stats: [String: Any]) -> [RawValue] {
        stats.keys.sorted().map { key in
            let value = stats[key]
            let text = CFValue.int64(value).map(String.init)
                ?? CFValue.double(value).map { String($0) }
                ?? CFValue.string(value)
                ?? "(\(value.map { String(describing: type(of: $0)) } ?? "?"))"
            return RawValue(key: key, value: text)
        }
    }
}

/// GPU bilgisi (değişmez): model ve çekirdek sayısı.
struct GPUInfo: Sendable {
    let model: String?
    let coreCount: Int?
    let ioClass: String?
}

/// GPU kullanımını IOKit `IOAccelerator` → `PerformanceStatistics` sözlüğünden okur (belgelenmemiş anahtarlar).
///
/// Tik başına tek bir kayıt özelliği okunur (~20 µs, M5 Pro); servis tutamacı önbellekte tutulur.
/// Geçmiş grafiği için sürekli örneklenir; ham değerler yalnızca panel açıkken toplanır.
///
/// Sürücü değeri **bir önceki okumadan bu yana geçen pencere** için hesaplar ve pencere tüm
/// okuyucular için ortaktır (`ioreg`, Activity Monitor, Stats okudukça kısalır). Bu yüzden servis
/// bulunurken yapılan okumadan hemen sonraki değer anlamsızdır (≈0); ilk okuma `nil` döner.
final class GPUSampler {
    let gate = UnofficialGate(id: "gpu-performance-statistics", title: "IOAccelerator → PerformanceStatistics")
    private(set) var info: GPUInfo?
    private var service: io_service_t = 0

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    func sample(includeRaw: Bool) -> GPUSnapshot? {
        let result: Result<GPUSnapshot?, UnofficialError>? = gate.call { read(includeRaw: includeRaw) }
        switch result {
        case .success(let snapshot)?:
            gate.report(.available)
            return snapshot // ilk okumada nil
        case .failure(let error)?:
            gate.report(.unavailable(error.description))
            return nil
        case nil:
            return nil // kapı kapalı
        }
    }

    private func read(includeRaw: Bool) -> Result<GPUSnapshot?, UnofficialError> {
        let isFirstRead = service == 0
        if isFirstRead {
            service = Self.findAccelerator()
            guard service != 0 else { return .failure(UnofficialError("IOAccelerator servisi bulunamadı")) }
            info = GPUInfo(
                model: CFValue.string(IORegistry.property(service, "model")),
                coreCount: CFValue.int64(IORegistry.property(service, "gpu-core-count")).map { Int($0) },
                ioClass: CFValue.string(IORegistry.property(service, "IOClass"))
            )
        }
        guard let stats = CFValue.dictionary(IORegistry.property(service, "PerformanceStatistics")) else {
            // Sürücü yeniden başlamış olabilir; bir sonraki tikte servis yeniden aranır.
            IOObjectRelease(service)
            service = 0
            return .failure(UnofficialError("“PerformanceStatistics” sözlüğü okunamadı"))
        }
        // Anahtarlar her okumada denetlenir; ilk okumanın değeri yine de atılır (pencere bilinmiyor).
        return GPUSnapshot.parse(stats, includeRaw: includeRaw).map { isFirstRead ? nil : $0 }
    }

    /// `PerformanceStatistics` taşıyan ilk `IOAccelerator` servisi.
    private static func findAccelerator() -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        while case let candidate = IOIteratorNext(iterator), candidate != 0 {
            if CFValue.dictionary(IORegistry.property(candidate, "PerformanceStatistics")) != nil {
                return candidate
            }
            IOObjectRelease(candidate)
        }
        return 0
    }
}
