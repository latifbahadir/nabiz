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
