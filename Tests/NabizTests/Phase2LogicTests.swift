import Testing
@testable import Nabiz

@Suite("Ağ, disk ve pil hesapları")
struct Phase2LogicTests {
    @Test("Sayaç farkı yalnızca ortak anahtarları toplar, sıfırlanmayı ve yeni girdiyi yok sayar")
    func counterDelta() {
        let previous: [String: ByteCounters] = [
            "en0": .init(read: 1_000, written: 500),
            "en1": .init(read: 9_000, written: 9_000),   // sıfırlanacak
            "gone": .init(read: 1, written: 1),           // kayboldu
        ]
        let current: [String: ByteCounters] = [
            "en0": .init(read: 3_000, written: 800),
            "en1": .init(read: 10, written: 9_100),       // read geri gitti → 0
            "new": .init(read: 5_000_000, written: 5_000_000), // yeni → sayılmaz
        ]
        let delta = ByteCounters.delta(previous: previous, current: current)
        #expect(delta == ByteCounters(read: 2_000, written: 400))
        #expect(RateSnapshot(delta: delta, interval: 2).readRate == 1_000)
        #expect(RateSnapshot(delta: delta, interval: 0).writeRate == 0)
    }

    @Test("Ağ arayüz süzgeci fiziksel arayüzleri sayar, tünelleri saymaz")
    func interfaceFilter() {
        #expect(NetworkSampler.isCounted("en0"))
        #expect(NetworkSampler.isCounted("pdp_ip0"))
        for name in ["lo0", "utun3", "awdl0", "llw0", "bridge0", "anpi0", "ap1", "gif0"] {
            #expect(!NetworkSampler.isCounted(name), "\(name) sayılmamalı")
        }
    }

    @Test("Hız, disk boyutu ve süre biçimleri")
    func formats() {
        #expect(Fmt.rate(0) == "0 B/sn")
        #expect(Fmt.rate(999) == "999 B/sn")
        #expect(Fmt.rate(1_500) == "1,5 KB/sn")
        #expect(Fmt.rate(340_000) == "340 KB/sn")
        #expect(Fmt.rate(12_300_000) == "12,3 MB/sn")
        #expect(Fmt.rate(-5) == "0 B/sn")
        #expect(Fmt.decimalBytes(994_662_584_320) == "994,7 GB")
        #expect(Fmt.decimalBytes(2_000_000_000_000) == "2,00 TB")
        #expect(Fmt.duration(minutes: 571) == "9 sa 31 dk")
        #expect(Fmt.duration(minutes: 45) == "45 dk")
    }

    @Test("Pil sağlığı %100 ile sınırlanır, güç işaretini korur")
    func batteryMath() {
        #expect(BatterySnapshot.health(nominal: 8665, design: 8579) == 1)
        #expect(abs(BatterySnapshot.health(nominal: 7000, design: 8000)! - 0.875) < 1e-9)
        #expect(BatterySnapshot.health(nominal: 100, design: 0) == nil)
        #expect(abs(BatterySnapshot.watts(millivolts: 12913, milliamps: -798)! - (-10.304574)) < 1e-6)
        #expect(BatterySnapshot.watts(millivolts: nil, milliamps: 100) == nil)
    }
}
