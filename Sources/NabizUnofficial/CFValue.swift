import CoreFoundation
import Foundation
import IOKit

/// Belgelenmemiş kaynaklardan gelen değerleri tipini denetleyerek okur.
///
/// Anahtarın tipi bir macOS sürümünde değişirse (ör. sayı yerine sözlük) değer `nil` olur;
/// zorla dönüştürme yapılmaz.
public enum CFValue {
    public static func dictionary(_ value: Any?) -> [String: Any]? {
        guard let ref = cfRef(value), CFGetTypeID(ref) == CFDictionaryGetTypeID() else { return nil }
        return ref as? [String: Any]
    }

    public static func array(_ value: Any?) -> [Any]? {
        guard let ref = cfRef(value), CFGetTypeID(ref) == CFArrayGetTypeID() else { return nil }
        return ref as? [Any]
    }

    public static func string(_ value: Any?) -> String? {
        guard let ref = cfRef(value), CFGetTypeID(ref) == CFStringGetTypeID() else { return nil }
        return ref as? String
    }

    /// Sayı (`CFBoolean` sayı sayılmaz).
    public static func double(_ value: Any?) -> Double? {
        guard let ref = cfRef(value), CFGetTypeID(ref) == CFNumberGetTypeID() else { return nil }
        let number = unsafeDowncast(ref, to: NSNumber.self)
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    /// Tam sayı; kesirli sayılar reddedilir.
    public static func int64(_ value: Any?) -> Int64? {
        guard let ref = cfRef(value), CFGetTypeID(ref) == CFNumberGetTypeID() else { return nil }
        let cfNumber = unsafeDowncast(ref, to: CFNumber.self)
        guard !CFNumberIsFloatType(cfNumber) else { return nil }
        var result: Int64 = 0
        return CFNumberGetValue(cfNumber, .sInt64Type, &result) ? result : nil
    }

    private static func cfRef(_ value: Any?) -> CFTypeRef? {
        guard let value else { return nil }
        return value as CFTypeRef
    }
}

public enum IORegistry {
    /// Kayıt girdisinin tek bir özelliğini okur; bulunamazsa `nil`.
    public static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        guard entry != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
