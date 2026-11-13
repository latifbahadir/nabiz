import Darwin
import Foundation
import IOKit
import NabizUnofficial

/// İşlem başına GPU süresi: `IOAccelerator` altındaki kullanıcı istemcilerinin (`AGXDeviceUserClient`)
/// `AppUsage[].accumulatedGPUTime` (ns) değerleri (belgelenmemiş; ADR 0003).
///
/// Her istemcinin `IOUserClientCreator` özelliği "pid 410, WindowServer" biçimindedir. Bir işlemin birden
/// fazla istemcisi olabilir; toplamları alınır. Oran = Δ GPU süresi / Δ duvar saati.
/// Yalnızca panel açıkken okunur (yüzlerce kayıt girdisi gezilir).
final class GPUProcessSampler {
    let gate = UnofficialGate(id: "gpu-process-app-usage", title: "IOAccelerator → AGXDeviceUserClient → AppUsage")
    private var previous: [pid_t: UInt64] = [:]
    private var lastTime: UInt64?
    private var service: io_service_t = 0

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    /// pid → GPU süresi oranı. İlk okumada ya da kaynak okunamazsa `nil`.
    func sample() -> [pid_t: Double]? {
        let result: Result<[pid_t: Double]?, UnofficialError>? = gate.call { read() }
        switch result {
        case .success(let values)?:
            gate.report(.available)
            return values
        case .failure(let error)?:
            gate.report(.unavailable(error.description))
            return nil
        case nil:
            return nil
        }
    }

    /// Panel kapanınca eski farklar bırakılır; bir sonraki açılışta ilk okuma yeniden `nil` döner.
    func reset() {
        previous = [:]
        lastTime = nil
    }

    private func read() -> Result<[pid_t: Double]?, UnofficialError> {
        if service == 0 {
            service = Self.findAccelerator()
            guard service != 0 else { return .failure(UnofficialError("IOAccelerator servisi bulunamadı")) }
        }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            IOObjectRelease(service)
            service = 0
            return .failure(UnofficialError("IOAccelerator alt girdileri okunamadı"))
        }
        defer { IOObjectRelease(iterator) }

        var totals: [pid_t: UInt64] = [:]
        var clientCount = 0
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard let creator = CFValue.string(IORegistry.property(child, "IOUserClientCreator")),
                  let pid = Self.parseCreator(creator)?.pid,
                  let usage = CFValue.array(IORegistry.property(child, "AppUsage")) else { continue }
            clientCount += 1
            totals[pid, default: 0] &+= Self.gpuTime(usage)
        }
        guard clientCount > 0 else {
            return .failure(UnofficialError("“IOUserClientCreator”/“AppUsage” taşıyan istemci bulunamadı"))
        }

        let now = DispatchTime.now().uptimeNanoseconds
        defer {
            previous = totals
            lastTime = now
        }
        guard let lastTime, now > lastTime else { return .success(nil) }
        return .success(Self.rates(current: totals, previous: previous, elapsedNanos: now - lastTime))
    }

    /// "pid 410, WindowServer" → (410, "WindowServer").
    static func parseCreator(_ text: String) -> (pid: pid_t, name: String)? {
        guard text.hasPrefix("pid ") else { return nil }
        let rest = text.dropFirst(4)
        let parts = rest.split(separator: ",", maxSplits: 1)
        guard let first = parts.first, let pid = pid_t(first.trimmingCharacters(in: .whitespaces)), pid >= 0 else { return nil }
        let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return (pid, name)
    }

    /// `AppUsage` dizisindeki `accumulatedGPUTime` (ns) toplamı; tipi beklenmeyen öğeler atlanır.
    static func gpuTime(_ appUsage: [Any]) -> UInt64 {
        appUsage.reduce(0) { sum, item in
            guard let entry = CFValue.dictionary(item),
                  let time = CFValue.int64(entry["accumulatedGPUTime"]), time > 0 else { return sum }
            return sum &+ UInt64(time)
        }
    }

    /// İstemciler kapanınca toplam düşebilir; o işlem için fark sıfır sayılır.
    static func rates(current: [pid_t: UInt64], previous: [pid_t: UInt64], elapsedNanos: UInt64) -> [pid_t: Double] {
        guard elapsedNanos > 0 else { return [:] }
        var result: [pid_t: Double] = [:]
        for (pid, time) in current {
            guard let old = previous[pid] else { continue }
            let delta = CounterMath.delta(time, old)
            if delta > 0 { result[pid] = Double(delta) / Double(elapsedNanos) }
        }
        return result
    }

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
