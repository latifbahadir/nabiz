import Foundation
import Testing
@testable import Nabiz
@testable import NabizUnofficial

@Suite("GPU")
struct GPUTests {
    /// M5 Pro'da `ioreg -rc IOAccelerator -d1` çıktısından alınmış örnek.
    private let sample: [String: Any] = [
        "In use system memory (driver)": 0,
        "Alloc system memory": 2_768_486_400,
        "Tiler Utilization %": 15,
        "recoveryCount": 0,
        "Renderer Utilization %": 49,
        "Device Utilization %": 49,
        "In use system memory": 940_032_000,
    ]

    private func parse(_ stats: [String: Any], raw: Bool = false) -> Result<GPUSnapshot, UnofficialError> {
        GPUSnapshot.parse(CFValue.dictionary(stats as CFDictionary)!, includeRaw: raw)
    }

    @Test("Örnek sözlük ayrıştırılır")
    func parsesSample() throws {
        let snapshot = try parse(sample).get()
        #expect(abs(snapshot.device - 0.49) < 1e-12)
        #expect(snapshot.renderer.map { abs($0 - 0.49) < 1e-12 } == true)
        #expect(snapshot.tiler.map { abs($0 - 0.15) < 1e-12 } == true)
        #expect(snapshot.inUseMemory == 940_032_000)
        #expect(snapshot.allocatedMemory == 2_768_486_400)
        #expect(snapshot.raw.isEmpty)
    }

    @Test("Ham değerler yalnızca istenince, sıralı üretilir")
    func rawValues() throws {
        let snapshot = try parse(sample, raw: true).get()
        #expect(snapshot.raw.map(\.key) == sample.keys.sorted())
        #expect(snapshot.raw.first { $0.key == "Device Utilization %" }?.value == "49")
    }

    @Test("Kullanım anahtarı yoksa, tipi değiştiyse ya da ölçek dışındaysa okunamadı")
    func rejectsUnexpected() {
        var missing = sample
        missing["Device Utilization %"] = nil
        #expect(throws: UnofficialError.self) { try parse(missing).get() }

        var wrongType = sample
        wrongType["Device Utilization %"] = "49"
        #expect(throws: UnofficialError.self) { try parse(wrongType).get() }

        var outOfRange = sample
        outOfRange["Device Utilization %"] = 4900 // ölçek değişmiş (ör. ‰)
        #expect(throws: UnofficialError.self) { try parse(outOfRange).get() }
    }

    @Test("Yardımcı anahtarlar bozuksa yalnızca onlar düşer")
    func optionalKeysDegrade() throws {
        var stats = sample
        stats["Renderer Utilization %"] = 250
        stats["In use system memory"] = -1
        stats["Tiler Utilization %"] = nil
        let snapshot = try parse(stats).get()
        #expect(snapshot.renderer == nil)
        #expect(snapshot.inUseMemory == nil)
        #expect(snapshot.tiler == nil)
        #expect(abs(snapshot.device - 0.49) < 1e-12)
    }

    @Test("Okunamayan GPU noktaları grafiğe sıfır olarak girmez")
    @MainActor
    func chartSkipsMissing() {
        let model = PanelModel(topology: CPUTopology.load(), interval: 2, hasBattery: false)
        let now = Date()
        model.history = [
            HistoryPoint(date: now.addingTimeInterval(-4), cpu: 0, memory: 0, download: 0, upload: 0, diskRead: 0, diskWrite: 0, gpu: 0.3),
            HistoryPoint(date: now.addingTimeInterval(-2), cpu: 0, memory: 0, download: 0, upload: 0, diskRead: 0, diskWrite: 0, gpu: nil),
            HistoryPoint(date: now, cpu: 0, memory: 0, download: 0, upload: 0, diskRead: 0, diskWrite: 0, gpu: 0.5),
        ]
        #expect(model.chartPoints(\.gpu).map(\.value) == [0.3, 0.5])
    }

    @Test("Gerçek sistem: ilk okuma nil; GPU varsa kullanım 0…1 ve durum kullanılabilir")
    func realSystem() {
        let sampler = GPUSampler()
        // İlk okuma pencereyi başlatır, değer üretmez.
        #expect(sampler.sample(includeRaw: true) == nil)
        Thread.sleep(forTimeInterval: 0.3)
        guard let snapshot = sampler.sample(includeRaw: true) else {
            // CI sanal makinesinde IOAccelerator istatistiği olmayabilir; çökmeden "okunamadı" olmalı.
            #expect(sampler.gate.status != .available)
            return
        }
        #expect((0...1).contains(snapshot.device))
        #expect(!snapshot.raw.isEmpty)
        #expect(sampler.gate.status == .available)
        #expect(sampler.info?.coreCount.map { $0 > 0 } ?? true)
    }
}
