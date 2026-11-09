import Foundation
import NabizUnofficial

struct TemperatureStats: Sendable, Equatable {
    let average: Double
    let maximum: Double
    let count: Int
}

struct SMCReading: Sendable, Hashable {
    let key: String
    let type: String
    let hex: String
    /// Tipine göre çözülmüş sayı (sıcaklıkta °C, fanda RPM).
    let value: Double?
}

struct TemperatureSnapshot: Sendable {
    let date: Date
    /// `Tp*` anahtarları
    let cpu: TemperatureStats?
    /// `Tg*` anahtarları
    let gpu: TemperatureStats?
    /// `Tp*`/`Tg*` her zaman; `includesAll` ise tüm `T*` `flt` anahtarları.
    let readings: [SMCReading]
    let includesAll: Bool

    /// SMC'de kullanılmayan yuvalar 0, bozuk olanlar uç değer döndürür (ör. TTPD ≈ −3·10⁸).
    static func isPlausible(_ celsius: Double) -> Bool { celsius > 0 && celsius < 150 }

    static func stats(_ values: [Double]) -> TemperatureStats? {
        let valid = values.filter(isPlausible)
        guard let maximum = valid.max() else { return nil }
        return TemperatureStats(average: valid.reduce(0, +) / Double(valid.count), maximum: maximum, count: valid.count)
    }
}

/// SMC sıcaklık anahtarlarının gruplanması (yük testiyle doğrulandı, #7):
/// CPU yükünde `Tp*`, GPU yükünde `Tg*` en çok yükselir.
enum TemperatureKeys {
    static let cpuPrefix = "Tp"
    static let gpuPrefix = "Tg"

    /// Yalnızca `T` ile başlayan `flt ` anahtarları sıcaklık sayılır.
    static func classify(_ keys: [(key: FourCC, type: FourCC)]) -> (cpu: [FourCC], gpu: [FourCC], other: [FourCC]) {
        var cpu: [FourCC] = [], gpu: [FourCC] = [], other: [FourCC] = []
        for (key, type) in keys where type.description == "flt " && key.description.hasPrefix("T") {
            let name = key.description
            if name.hasPrefix(cpuPrefix) { cpu.append(key) }
            else if name.hasPrefix(gpuPrefix) { gpu.append(key) }
            else { other.append(key) }
        }
        return (cpu.sorted(), gpu.sorted(), other.sorted())
    }
}

/// SMC sensörlerinin (sıcaklık ve fan) okuma sıklığı; yalnızca panel açıkken. Varsayılan 60 sn.
enum SensorSettings {
    static let defaultsKey = "SensorInterval"
    static let choices: [Int] = [5, 15, 60]
    static let defaultInterval = 60

    static func load(_ defaults: UserDefaults = .standard) -> Int {
        let value = defaults.integer(forKey: defaultsKey)
        return choices.contains(value) ? value : defaultInterval
    }

    static func save(_ seconds: Int, _ defaults: UserDefaults = .standard) {
        defaults.set(seconds, forKey: defaultsKey)
    }
}

/// Bir SMC okumasının sonucu: sıcaklık ve fan birlikte okunur (#8 kararı: aynı sıklık).
struct SensorReading: Sendable {
    let temperature: TemperatureSnapshot?
    let temperatureStatus: UnofficialStatus
    let fans: FanSnapshot?
    let fanStatus: UnofficialStatus
}

/// SMC'den sıcaklık ve fan okur. SMC çağrıları ana iş parçacığını bekletmesin diye kendi seri
/// kuyruğunda çalışır; ilk kullanımda anahtar listesi bir kez taranır (~0,7 sn, M5 Pro).
final class SMCSensorSampler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.latifbahadir.nabiz.sensors", qos: .utility)
    // Aşağıdakiler yalnızca `queue` üzerinde kullanılır.
    private let gate = UnofficialGate(id: "smc-temperature", title: "AppleSMC → Tp* / Tg*")
    private let hidGate = UnofficialGate(id: "hid-temperature", title: "IOHIDEventSystemClient → sıcaklık servisleri")
    private let fanGate = UnofficialGate(id: "smc-fan", title: "AppleSMC → FNum, F*Ac/Tg/Mn/Mx")
    private var client: SMCClient?
    private var keys: (cpu: [FourCC], gpu: [FourCC], other: [FourCC])?

    let sourceTitle = "AppleSMC → Tp* / Tg*"
    let hidSourceTitle = "IOHIDEventSystemClient → sıcaklık servisleri"

    func sample(includeAll: Bool, completion: @escaping @MainActor (SensorReading) -> Void) {
        queue.async { [self] in
            let temperature: Result<TemperatureSnapshot, Error>? = gate.call { Result { try read(includeAll: includeAll) } }
            report(temperature, to: gate)
            let fans: Result<FanSnapshot, Error>? = fanGate.call { Result { try FanReader.read(try connectedClient()) } }
            report(fans, to: fanGate)
            let reading = SensorReading(
                temperature: try? temperature?.get(), temperatureStatus: gate.status,
                fans: try? fans?.get(), fanStatus: fanGate.status
            )
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(reading) } }
        }
    }

    private func report<T>(_ result: Result<T, Error>?, to gate: UnofficialGate) {
        switch result {
        case .success?: gate.report(.available)
        case .failure(let error)?: gate.report(.unavailable(Self.describe(error)))
        case nil: break
        }
    }

    private func connectedClient() throws -> SMCClient {
        let client = try self.client ?? SMCClient()
        self.client = client
        return client
    }

    func readHID(completion: @escaping @MainActor ([HIDTemperature.Reading]?, UnofficialStatus) -> Void) {
        queue.async { [self] in
            let result: Result<[HIDTemperature.Reading], Error>? = hidGate.call { Result { try HIDTemperature.readAll() } }
            switch result {
            case .success?: hidGate.report(.available)
            case .failure(let error)?: hidGate.report(.unavailable(Self.describe(error)))
            case nil: break
            }
            let readings = try? result?.get()
            let status = hidGate.status
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(readings, status) } }
        }
    }

    func retryAfterCrash(completion: @escaping @MainActor (UnofficialStatus) -> Void) {
        queue.async { [self] in
            gate.retryAfterCrash()
            hidGate.retryAfterCrash()
            fanGate.retryAfterCrash()
            let status = gate.status
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(status) } }
        }
    }

    private func read(includeAll: Bool) throws -> TemperatureSnapshot {
        let client = try connectedClient()
        let keys = try self.keys ?? discover(client)
        self.keys = keys
        guard !keys.cpu.isEmpty || !keys.gpu.isEmpty else {
            throw UnofficialError("SMC'de Tp*/Tg* sıcaklık anahtarı yok")
        }

        func readings(_ list: [FourCC]) -> [SMCReading] {
            list.compactMap { key in
                guard let value = try? client.read(key) else { return nil }
                return SMCReading(key: key.description, type: value.type.description, hex: value.hex, value: value.number)
            }
        }
        let cpu = readings(keys.cpu)
        let gpu = readings(keys.gpu)
        let other = includeAll ? readings(keys.other) : []
        return TemperatureSnapshot(
            date: Date(),
            cpu: TemperatureSnapshot.stats(cpu.compactMap(\.value)),
            gpu: TemperatureSnapshot.stats(gpu.compactMap(\.value)),
            readings: cpu + gpu + other,
            includesAll: includeAll
        )
    }

    private func discover(_ client: SMCClient) throws -> (cpu: [FourCC], gpu: [FourCC], other: [FourCC]) {
        let count = try client.keyCount()
        var found: [(key: FourCC, type: FourCC)] = []
        for index in 0..<count {
            guard let key = try? client.key(at: index), key.description.hasPrefix("T"),
                  let type = try? client.type(of: key) else { continue }
            found.append((key, type))
        }
        return TemperatureKeys.classify(found)
    }

    private static func describe(_ error: Error) -> String {
        (error as? UnofficialError)?.description ?? String(describing: error)
    }
}
