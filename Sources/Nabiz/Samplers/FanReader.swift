import Foundation
import NabizUnofficial

struct FanInfo: Sendable, Equatable, Identifiable {
    let id: Int
    /// `F<n>Ac` — anlık devir (RPM)
    let actual: Double
    /// `F<n>Tg` — sistemin istediği devir
    let target: Double?
    /// `F<n>Mn` / `F<n>Mx`
    let minimum: Double?
    let maximum: Double?

    /// Anlık / en yüksek devir (0…1).
    var fraction: Double? { Self.fraction(actual: actual, maximum: maximum) }
    /// Fan durmuşsa (Apple Silicon'da boştayken olağandır) devir 0'dır.
    var isStopped: Bool { actual < 1 }

    static func fraction(actual: Double, maximum: Double?) -> Double? {
        guard let maximum, maximum > 0, actual.isFinite else { return nil }
        return min(max(actual / maximum, 0), 1)
    }
}

struct FanSnapshot: Sendable {
    let date: Date
    /// `FNum`; fansız Mac'lerde 0 (ya da anahtar yok).
    let count: Int
    let fans: [FanInfo]
    /// Doğrulama ekranı için ham SMC değerleri.
    let readings: [SMCReading]
}

/// SMC fan anahtarları (yalnızca okuma; fan denetimi kapsam dışı).
enum FanReader {
    /// SMC anahtar adlarında fan numarası tek karakterdir.
    static let maxFans = 10

    static func keys(forFan index: Int) -> (actual: String, target: String, minimum: String, maximum: String) {
        ("F\(index)Ac", "F\(index)Tg", "F\(index)Mn", "F\(index)Mx")
    }

    static func read(_ client: SMCClient) throws -> FanSnapshot {
        var readings: [SMCReading] = []
        func value(_ name: String) -> Double? {
            guard let key = FourCC(name), let value = try? client.read(key) else { return nil }
            readings.append(SMCReading(key: name, type: value.type.description, hex: value.hex, value: value.number))
            return value.number
        }

        // FNum yoksa fansız Mac kabul edilir (ör. MacBook Air): bölüm gizlenir, hata sayılmaz.
        let count = min(max(Int(value("FNum") ?? 0), 0), maxFans)
        var fans: [FanInfo] = []
        for index in 0..<count {
            let keys = keys(forFan: index)
            guard let actual = value(keys.actual) else {
                throw UnofficialError("\(keys.actual) okunamadı (FNum = \(count))")
            }
            fans.append(FanInfo(
                id: index,
                actual: actual,
                target: value(keys.target),
                minimum: value(keys.minimum),
                maximum: value(keys.maximum)
            ))
        }
        return FanSnapshot(date: Date(), count: count, fans: fans, readings: readings)
    }
}
