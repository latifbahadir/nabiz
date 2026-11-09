import Foundation
import IOKit
import IOKit.ps

enum BatteryState: Sendable {
    case charging, charged, onACNotCharging, discharging
}

struct BatterySnapshot: Sendable {
    // Resmi IOPowerSources API'si (pmset ile aynı)
    let percent: Int
    let state: BatteryState
    /// Şarj olurken dolmasına, pildeyken bitmesine kalan dakika; hesaplanıyorsa nil.
    let minutesRemaining: Int?

    // AppleSmartBattery (ham değerler)
    let cycleCount: Int?
    let designCapacity: Int?    // mAh
    let nominalCapacity: Int?   // mAh, tam şarj kapasitesi
    let rawMaxCapacity: Int?    // mAh
    let voltage: Int?           // mV
    let amperage: Int?          // mA; negatif = deşarj
    let temperature: Int?       // santi-°C

    /// Sağlık: tam şarj kapasitesi / tasarım kapasitesi, en fazla %100 (Sistem Bilgisi ile aynı).
    var health: Double? { Self.health(nominal: nominalCapacity, design: designCapacity) }
    /// Güç (W) = gerilim × akım. Pozitif: pile giren, negatif: pilden çekilen.
    var watts: Double? { Self.watts(millivolts: voltage, milliamps: amperage) }
    var temperatureCelsius: Double? { temperature.map { Double($0) / 100 } }

    static func health(nominal: Int?, design: Int?) -> Double? {
        guard let nominal, let design, design > 0 else { return nil }
        return min(Double(nominal) / Double(design), 1)
    }

    static func watts(millivolts: Int?, milliamps: Int?) -> Double? {
        guard let millivolts, let milliamps else { return nil }
        return Double(millivolts) * Double(milliamps) / 1_000_000
    }
}

/// Pil bilgisi. Yalnızca panel açıkken okunur.
enum BatterySampler {
    static func sample() -> BatterySnapshot? {
        guard let source = powerSource() else { return nil }

        let percent: Int
        if let current = source["Current Capacity"] as? Int, let max = source["Max Capacity"] as? Int, max > 0 {
            percent = Int((Double(current) / Double(max) * 100).rounded())
        } else {
            return nil
        }

        let onAC = (source["Power Source State"] as? String) == "AC Power"
        let charging = source["Is Charging"] as? Bool ?? false
        let charged = source["Is Charged"] as? Bool ?? false
        let state: BatteryState = charging ? .charging : charged ? .charged : onAC ? .onACNotCharging : .discharging

        let minutesKey = charging ? "Time to Full Charge" : "Time to Empty"
        let minutes = (source[minutesKey] as? Int).flatMap { $0 > 0 && (charging || !onAC) ? $0 : nil }

        let raw = smartBattery()
        func int(_ key: String) -> Int? { (raw[key] as? NSNumber)?.int64Value.clampedInt }

        return BatterySnapshot(
            percent: percent,
            state: state,
            minutesRemaining: minutes,
            cycleCount: int("CycleCount"),
            designCapacity: int("DesignCapacity"),
            nominalCapacity: int("NominalChargeCapacity"),
            rawMaxCapacity: int("AppleRawMaxCapacity"),
            voltage: int("Voltage"),
            amperage: int("InstantAmperage") ?? int("Amperage"),
            temperature: int("Temperature")
        )
    }

    private static func powerSource() -> [String: Any]? {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for item in list {
            if let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
               (description["Type"] as? String) == "InternalBattery" {
                return description
            }
        }
        return nil
    }

    private static func smartBattery() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var result: [String: Any] = [:]
        for key in ["CycleCount", "DesignCapacity", "NominalChargeCapacity", "AppleRawMaxCapacity",
                    "Voltage", "Amperage", "InstantAmperage", "Temperature"] {
            if let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() {
                result[key] = value
            }
        }
        return result
    }
}

private extension Int64 {
    /// Akım değerleri kayıtta işaretsiz 64 bit olarak durur (ör. 18446744073709550818 = −798);
    /// int64Value bunu doğru şekilde negatife çevirir.
    var clampedInt: Int { Int(clamping: self) }
}
