import Foundation
import Testing
@testable import Nabiz

/// Gerçek sistemden okuyan testler: değerlerin makul aralıkta olduğunu doğrular.
@Suite("Sistem örnekleyicileri")
struct SystemSamplerTests {
    @Test("CPU: ilk okuma fark üretmez, ikincisi tutarlı oranlar verir")
    func cpu() async throws {
        let sampler = CPUSampler()
        #expect(sampler.sample() == nil)
        try await Task.sleep(for: .milliseconds(300))
        let snapshot = try #require(sampler.sample())
        #expect(abs(snapshot.user + snapshot.system + snapshot.idle - 1) < 1e-9)
        #expect(snapshot.cores.count == ProcessInfo.processInfo.processorCount)
        #expect(snapshot.cores.allSatisfy { (0...1).contains($0.total) })
    }

    @Test("Bellek: kullanılan toplamı aşmaz")
    func memory() throws {
        let snapshot = try #require(MemorySampler().sample())
        #expect(snapshot.total == ProcessInfo.processInfo.physicalMemory)
        #expect(snapshot.pageSize > 0)
        #expect(snapshot.used > 0 && snapshot.used <= snapshot.total)
        #expect(snapshot.used + snapshot.cachedFiles <= snapshot.total)
    }

    @Test("Topoloji: her çekirdek tam olarak bir gruba ait")
    func topology() {
        let topology = CPUTopology.load()
        let ids = topology.groups.flatMap(\.cpuIDs).sorted()
        #expect(ids == Array(0..<topology.cpuCount))
        #expect(topology.cpuCount == ProcessInfo.processInfo.processorCount)
    }

    @Test("Kendi tüketimi ölçülebilir")
    func selfUsage() {
        let usage = SelfUsageSampler().sample()
        #expect(usage.footprint > 0)
        #expect(usage.averageCPU >= 0)
    }
}

@Suite("Sistem örnekleyicileri — ağ, disk, pil")
struct Phase2SystemTests {
    @Test("Ağ: sayaçlar okunur, ikinci okuma negatif olmayan hız verir")
    func network() async throws {
        let sampler = NetworkSampler()
        #expect(sampler.sample() == nil)
        try await Task.sleep(for: .milliseconds(200))
        let snapshot = try #require(sampler.sample())
        #expect(!snapshot.counters.isEmpty)
        #expect(snapshot.counters.keys.allSatisfy(NetworkSampler.isCounted))
        #expect(snapshot.download >= 0 && snapshot.upload >= 0)
    }

    @Test("Disk: G/Ç ve doluluk makul")
    func disk() async throws {
        let sampler = DiskSampler()
        #expect(sampler.sampleIO() == nil)
        try await Task.sleep(for: .milliseconds(200))
        let io = try #require(sampler.sampleIO())
        #expect(io.driverCount > 0)
        #expect(io.totals.read > 0)

        let capacity = try #require(DiskSampler.capacity())
        #expect(capacity.total > 0)
        #expect(capacity.used > 0 && capacity.used <= capacity.total)
    }

    @Test("Pil: varsa değerler aralıkta")
    func battery() throws {
        guard let battery = BatterySampler.sample() else { return } // masaüstü Mac / CI
        #expect((0...100).contains(battery.percent))
        if let health = battery.health { #expect(health > 0 && health <= 1) }
    }
}
