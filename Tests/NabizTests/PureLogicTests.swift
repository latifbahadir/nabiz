import Foundation
import Testing
@testable import Nabiz

@Suite("Saf mantık")
struct PureLogicTests {
    @Test("vm_stat çıktısı ayrıştırılır")
    func parseVMStat() {
        let output = """
        Mach Virtual Memory Statistics: (page size of 16384 bytes)
        Pages free:                                    68100.
        Pages wired down:                             207344.
        "Translation faults":                      297709403.
        File-backed pages:                            273344.
        """
        let values = VMStat.parse(output)
        #expect(values["Pages free"] == 68100)
        #expect(values["Pages wired down"] == 207344)
        #expect(values["Translation faults"] == 297709403)
        #expect(values["File-backed pages"] == 273344)
        #expect(values.count == 4) // başlık satırı sayı değil, atlanır
    }

    @Test("Halka tampon kapasiteyi aşınca en eskiyi düşürür ve sırayı korur")
    func ringBuffer() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for i in 1...2 { buffer.append(i) }
        #expect(buffer.elements == [1, 2])
        for i in 3...5 { buffer.append(i) }
        #expect(buffer.elements == [3, 4, 5])
    }

    @Test("Biçimlendirme Türkçe kurallara uyar")
    func formatting() {
        #expect(Fmt.percent(0.123) == "%12")
        #expect(Fmt.percent(0.0039, digits: 2) == "%0,39")
        #expect(Fmt.paddedPercent(0.05) == "%\u{2007}5")
        #expect(Fmt.paddedPercent(0.42) == "%42")
        #expect(Fmt.bytes(25_769_803_776) == "24,0 GB")
        #expect(Fmt.bytes(12 * 1_048_576) == "12 MB")
        #expect(Fmt.integer(3375) == "3.375")
    }

    @Test("İndirgeme nokta sayısını sınırlar ve ortalamayı korur")
    func downsample() {
        let start = Date(timeIntervalSince1970: 0)
        let points = (0..<1000).map { ChartPoint(date: start.addingTimeInterval(Double($0)), value: Double($0 % 2)) }
        let reduced = PanelModel.downsample(points, maxPoints: 100)
        #expect(reduced.count <= 100)
        #expect(reduced.allSatisfy { abs($0.value - 0.5) < 0.01 })
        #expect(reduced.last?.date == points.last?.date)
        #expect(PanelModel.downsample(Array(points.prefix(10)), maxPoints: 100).count == 10)
    }

    @Test("Bellek hesabı Activity Monitor tanımlarını izler")
    func memoryMath() {
        var raw = RawVMStats()
        raw.anonymous = 100; raw.purgeable = 10; raw.wired = 20; raw.compressor = 5; raw.fileBacked = 30
        let snapshot = MemorySnapshot(
            total: 1000 * 16384, pageSize: 16384, raw: raw,
            swapUsed: 0, swapTotal: 0, pressure: .normal, availablePercent: 80
        )
        #expect(snapshot.app == 90 * 16384)
        #expect(snapshot.cachedFiles == 40 * 16384)
        #expect(snapshot.used == (90 + 20 + 5) * 16384)
        #expect(abs(snapshot.usedFraction - 0.115) < 1e-9)
    }
}
