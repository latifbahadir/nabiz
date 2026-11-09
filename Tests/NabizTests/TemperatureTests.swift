import Foundation
import Testing
@testable import Nabiz
@testable import NabizUnofficial

@Suite("SMC ve sıcaklık")
struct TemperatureTests {
    @Test("SMC yapısı C düzeniyle aynı (80 bayt, alan konumları)")
    func layout() {
        #expect(SMCParam.isLayoutValid)
        #expect(MemoryLayout<SMCParam>.size == 80)
    }

    @Test("Dört karakterli anahtar dönüşümü")
    func fourCC() {
        #expect(FourCC("Tp0a")?.description == "Tp0a")
        #expect(FourCC("#KEY")?.rawValue == 0x234B_4559)
        #expect(FourCC("çok uzun") == nil)
        #expect(FourCC("Tg") == nil)
    }

    @Test("SMC değer tipleri çözülür")
    func decoding() {
        // 34.5 °C, küçük endian float
        let bits = Float(34.5).bitPattern
        let little = [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: bits >> $0) }
        #expect(SMCValue(type: FourCC("flt ")!, bytes: little).number == 34.5)
        #expect(SMCValue(type: FourCC("ui8 ")!, bytes: [2]).number == 2)
        #expect(SMCValue(type: FourCC("ui16")!, bytes: [0x25, 0x80]).number == 9600)
        #expect(SMCValue(type: FourCC("si16")!, bytes: [0xff, 0xfe]).number == -2)
        #expect(SMCValue(type: FourCC("sp78")!, bytes: [0x22, 0x80]).number == 34.5)
        #expect(SMCValue(type: FourCC("fpe2")!, bytes: [0x15, 0x18]).number == 1350)
        // Boyut tutmazsa ya da tip bilinmiyorsa sayı yok
        #expect(SMCValue(type: FourCC("flt ")!, bytes: [0, 0]).number == nil)
        #expect(SMCValue(type: FourCC("ioft")!, bytes: [0x99, 0x99, 0x1c, 0, 0, 0, 0, 0]).number == nil)
        #expect(SMCValue(type: FourCC("ui16")!, bytes: [0x25, 0x80]).hex == "2580")
        // NaN float reddedilir
        let nan = Float.nan.bitPattern
        #expect(SMCValue(type: FourCC("flt ")!, bytes: [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: nan >> $0) }).number == nil)
    }

    @Test("Anahtarlar Tp/Tg/diğer olarak gruplanır; flt olmayanlar ve T dışı anahtarlar dışarıda")
    func classify() {
        let flt = FourCC("flt ")!
        let keys: [(key: FourCC, type: FourCC)] = [
            (FourCC("Tp0a")!, flt), (FourCC("Tp00")!, flt), (FourCC("Tg05")!, flt),
            (FourCC("Tm00")!, flt), (FourCC("TG0B")!, FourCC("ioft")!), (FourCC("F0Ac")!, flt),
        ]
        let result = TemperatureKeys.classify(keys)
        #expect(result.cpu.map(\.description) == ["Tp00", "Tp0a"])
        #expect(result.gpu.map(\.description) == ["Tg05"])
        #expect(result.other.map(\.description) == ["Tm00"]) // TG0B (büyük G) ioft olduğu için yok
    }

    @Test("İstatistik geçersiz değerleri (0, uç değerler) dışarıda bırakır")
    func stats() {
        let stats = TemperatureSnapshot.stats([34, 36, 0, -306_783_232, 40, 9_999])
        #expect(stats == TemperatureStats(average: 110.0 / 3, maximum: 40, count: 3))
        #expect(TemperatureSnapshot.stats([0, -9201]) == nil)
        #expect(TemperatureSnapshot.stats([]) == nil)
    }

    @Test("Okuma sıklığı: varsayılan 60 sn, yalnızca izin verilen değerler")
    func settings() throws {
        let suite = "nabiz-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SensorSettings.load(defaults) == 60)
        SensorSettings.save(5, defaults)
        #expect(SensorSettings.load(defaults) == 5)
        defaults.set(1, forKey: SensorSettings.defaultsKey)
        #expect(SensorSettings.load(defaults) == 60)
    }

    @Test("Gerçek sistem: SMC açılabiliyorsa Tp/Tg makul aralıkta")
    func realSMC() throws {
        guard let client = try? SMCClient() else { return } // CI sanal makinesinde SMC olmayabilir
        let count = try client.keyCount()
        #expect(count > 0)
        guard let key = FourCC("Tp00"), let value = try? client.read(key) else { return } // farklı çip
        #expect(value.type.description == "flt ")
        #expect(value.number.map(TemperatureSnapshot.isPlausible) == true)
        #expect(throws: UnofficialError.self) { try client.read(FourCC("Zzzz")!) }
    }

    @Test("Gerçek sistem: HID sıcaklıkları okunur ya da hata verir, çökmez")
    func realHID() {
        guard let readings = try? HIDTemperature.readAll() else { return }
        #expect(readings.contains { TemperatureSnapshot.isPlausible($0.celsius) } || readings.isEmpty)
    }
}
