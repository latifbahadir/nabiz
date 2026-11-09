import Foundation

/// `IOHIDEventSystemClient` ile sıcaklık sensörleri (özel API; semboller `dlsym` ile çözülür).
///
/// Pahalıdır (M5 Pro'da 77 servis ≈ 100 ms); yalnızca Doğrulama ekranında, istenince çapraz
/// kontrol için okunur.
public enum HIDTemperature {
    public struct Reading: Sendable, Hashable {
        public let name: String
        public let celsius: Double
    }

    private static let iokit = "/System/Library/Frameworks/IOKit.framework/IOKit"
    /// `kIOHIDEventTypeTemperature`
    private static let temperatureEvent: Int64 = 15
    /// AppleVendor sayfası / sıcaklık sensörü kullanımı
    private static let matching: [String: Int] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]

    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatching = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServices = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEvent = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloat = @convention(c) (AnyObject, Int32) -> Double

    /// Tüm sıcaklık servislerini okur. Değeri geçersiz olanlar (ör. −9201 °C) dahil edilir;
    /// süzme çağıranın işidir, ham liste olduğu gibi gösterilir.
    public static func readAll() throws -> [Reading] {
        let create = try PrivateSymbol.resolve("IOHIDEventSystemClientCreate", in: iokit, as: Create.self)
        let setMatching = try PrivateSymbol.resolve("IOHIDEventSystemClientSetMatching", in: iokit, as: SetMatching.self)
        let copyServices = try PrivateSymbol.resolve("IOHIDEventSystemClientCopyServices", in: iokit, as: CopyServices.self)
        let copyProperty = try PrivateSymbol.resolve("IOHIDServiceClientCopyProperty", in: iokit, as: CopyProperty.self)
        let copyEvent = try PrivateSymbol.resolve("IOHIDServiceClientCopyEvent", in: iokit, as: CopyEvent.self)
        let getFloat = try PrivateSymbol.resolve("IOHIDEventGetFloatValue", in: iokit, as: GetFloat.self)

        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            throw UnofficialError("IOHIDEventSystemClient oluşturulamadı")
        }
        _ = setMatching(client, matching as CFDictionary)
        guard let services = CFValue.array(copyServices(client)?.takeRetainedValue()) else {
            throw UnofficialError("HID servis listesi okunamadı")
        }

        let field = Int32(truncatingIfNeeded: temperatureEvent << 16)
        var readings: [Reading] = []
        for service in services {
            let object = service as AnyObject
            guard let name = CFValue.string(copyProperty(object, "Product" as CFString)?.takeRetainedValue()),
                  let event = copyEvent(object, temperatureEvent, 0, 0)?.takeRetainedValue()
            else { continue }
            let value = getFloat(event, field)
            if value.isFinite { readings.append(Reading(name: name, celsius: value)) }
        }
        return readings
    }
}
