import Foundation
import IOKit
import Testing
@testable import NabizUnofficial

@Suite("Resmi olmayan API izolasyon katmanı")
struct UnofficialLayerTests {
    private static let iokit = "/System/Library/Frameworks/IOKit.framework/IOKit"

    private func temporaryGuard(fingerprint: String = "test-1") -> CrashGuard {
        CrashGuard(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("nabiz-crash-guard-\(UUID().uuidString)", isDirectory: true),
            fingerprint: fingerprint
        )
    }

    // MARK: dlsym

    @Test("Var olan sembol çözülür ve çağrılabilir")
    func resolvesExistingSymbol() throws {
        typealias Matching = @convention(c) (UnsafePointer<CChar>) -> Unmanaged<CFMutableDictionary>?
        let matching = try PrivateSymbol.resolve("IOServiceMatching", in: Self.iokit, as: Matching.self)
        let dictionary = matching("IOPlatformExpertDevice")?.takeRetainedValue()
        #expect(dictionary != nil)
    }

    @Test("Olmayan sembol hata verir, çökmez")
    func missingSymbol() {
        typealias Fn = @convention(c) () -> Void
        #expect(throws: UnofficialError("NabizOlmayanSembol sembolü bulunamadı")) {
            try PrivateSymbol.resolve("NabizOlmayanSembol", in: Self.iokit, as: Fn.self)
        }
    }

    @Test("Olmayan kütüphane ve işlev olmayan tip reddedilir")
    func badImageOrType() {
        typealias Fn = @convention(c) () -> Void
        #expect(throws: UnofficialError.self) {
            try PrivateSymbol.resolve("x", in: "/System/Library/Frameworks/Yok.framework/Yok", as: Fn.self)
        }
        #expect(throws: UnofficialError.self) {
            try PrivateSymbol.resolve("IOServiceMatching", in: Self.iokit, as: (Int, Int).self)
        }
    }

    // MARK: CF tip denetimi

    @Test("Yanlış CF tipi reddedilir")
    func typeChecks() {
        let dictionary: [String: Any] = ["Device Utilization %": 42, "Ad": "GPU", "Bayrak": true, "Kesir": 1.5]
        let cfDictionary = dictionary as CFDictionary

        let parsed = CFValue.dictionary(cfDictionary)
        #expect(parsed != nil)
        #expect(CFValue.dictionary("sözlük değil" as CFString) == nil)
        #expect(CFValue.dictionary(nil) == nil)

        #expect(CFValue.int64(parsed?["Device Utilization %"]) == 42)
        #expect(CFValue.double(parsed?["Device Utilization %"]) == 42)
        #expect(CFValue.int64(parsed?["Ad"]) == nil)
        #expect(CFValue.string(parsed?["Ad"]) == "GPU")
        #expect(CFValue.string(parsed?["Device Utilization %"]) == nil)
        // CFBoolean sayı değildir.
        #expect(CFValue.double(kCFBooleanTrue) == nil)
        #expect(CFValue.int64(parsed?["Bayrak"]) == nil)
        // Kesirli sayı tam sayı olarak okunmaz.
        #expect(CFValue.int64(parsed?["Kesir"]) == nil)
        #expect(CFValue.double(parsed?["Kesir"]) == 1.5)
        #expect(CFValue.array([1, 2] as CFArray)?.count == 2)
        #expect(CFValue.array(cfDictionary) == nil)
    }

    @Test("Kayıt özelliği: geçersiz girdi nil döner")
    func registryProperty() {
        #expect(IORegistry.property(0, "IOClass") == nil)
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        #expect(CFValue.string(IORegistry.property(service, "IOPlatformUUID")) != nil)
        #expect(IORegistry.property(service, "NabizOlmayanAnahtar") == nil)
    }

    // MARK: Çökme koruması

    @Test("İlk çağrı tamamlanmazsa sonraki açılışta kaynak kapalı başlar")
    func crashMarkerBlocksNextLaunch() {
        let crashGuard = temporaryGuard()
        crashGuard.begin("gpu") // çağrı dönmeden süreç "çöktü"

        let gate = UnofficialGate(id: "gpu", title: "GPU", crashGuard: crashGuard, disabledByUser: false)
        #expect(!gate.isOpen)
        var ran = false
        #expect(gate.call { ran = true; return 1 } == nil)
        #expect(!ran)
        if case .unavailable(let reason) = gate.status {
            #expect(reason.contains("önceki çalıştırmada"))
        } else {
            Issue.record("durum okunamadı olmalı")
        }

        gate.retryAfterCrash(disabledByUser: false)
        #expect(gate.isOpen)
        #expect(gate.call { 7 } == 7)
    }

    @Test("Başarılı ilk çağrı işareti siler")
    func successfulCallClearsMarker() {
        let crashGuard = temporaryGuard()
        let gate = UnofficialGate(id: "fan", title: "Fan", crashGuard: crashGuard, disabledByUser: false)
        #expect(gate.call { 3 } == 3)
        #expect(!crashGuard.crashedPreviously("fan"))
        #expect(UnofficialGate(id: "fan", title: "Fan", crashGuard: crashGuard, disabledByUser: false).isOpen)
    }

    @Test("Fırlatan ilk çağrı da işareti siler")
    func throwingCallClearsMarker() {
        let crashGuard = temporaryGuard()
        let gate = UnofficialGate(id: "hid", title: "HID", crashGuard: crashGuard, disabledByUser: false)
        #expect(throws: UnofficialError.self) {
            try gate.call { () throws -> Int? in throw UnofficialError("x") }
        }
        #expect(!crashGuard.crashedPreviously("hid"))
    }

    @Test("macOS veya Nabız sürümü değişince kaynak yeniden denenir")
    func fingerprintChangeRetries() {
        let old = temporaryGuard(fingerprint: "macOS 26.6 · Nabız 0.3.0")
        old.begin("hid")
        #expect(old.crashedPreviously("hid"))
        let updated = CrashGuard(directory: old.directory, fingerprint: "macOS 26.7 · Nabız 0.3.0")
        #expect(!updated.crashedPreviously("hid"))
        #expect(!old.crashedPreviously("hid")) // eski işaret silindi
    }

    // MARK: Kapatma anahtarı

    @Test("Kullanıcı kapatınca gövde hiç çalışmaz")
    func killSwitch() {
        let gate = UnofficialGate(id: "gpu", title: "GPU", crashGuard: temporaryGuard(), disabledByUser: true)
        var ran = false
        #expect(gate.call { ran = true; return 1 } == nil)
        #expect(!ran)
        gate.report(.available)
        #expect(gate.status != .available)
        gate.retryAfterCrash(disabledByUser: true)
        #expect(!gate.isOpen)
    }

    @Test("Kapatma anahtarı ortam değişkeni ve defaults ile okunur")
    func killSwitchSources() throws {
        let suite = "nabiz-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(!UnofficialSettings.disabledByUser(environment: [:], defaults: defaults))
        #expect(UnofficialSettings.disabledByUser(environment: ["NABIZ_DISABLE_UNOFFICIAL": "1"], defaults: defaults))
        #expect(!UnofficialSettings.disabledByUser(environment: ["NABIZ_DISABLE_UNOFFICIAL": "0"], defaults: defaults))
        defaults.set(true, forKey: UnofficialSettings.defaultsKey)
        #expect(UnofficialSettings.disabledByUser(environment: [:], defaults: defaults))
    }

    @Test("Okuma sonucu durum olarak bildirilir")
    func reportStatus() {
        let gate = UnofficialGate(id: "gpu", title: "GPU", crashGuard: temporaryGuard(), disabledByUser: false)
        #expect(gate.status == .unknown)
        gate.report(.unavailable("anahtar yok"))
        #expect(gate.status.label == "okunamadı: anahtar yok")
        gate.report(.available)
        #expect(gate.status.label == "kullanılabilir")
    }
}
