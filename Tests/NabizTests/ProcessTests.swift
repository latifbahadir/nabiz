import Darwin
import Foundation
import Testing
@testable import Nabiz

@Suite("İşlemler")
struct ProcessTests {
    @Test("Yardımcı işlemler en dıştaki .app paketine gruplanır")
    func groupsByOutermostBundle() {
        let id = ProcessIdentity.from(
            path: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
            fallbackName: "x"
        )
        #expect(id.groupKey == "/Applications/Google Chrome.app")
        #expect(id.bundlePath == "/Applications/Google Chrome.app")
        #expect(id.processName == "Google Chrome Helper (Renderer)")
        #expect(!id.isSystemPath)
    }

    @Test("Paketsiz işlemler yola göre gruplanır, sistem yolu tanınır")
    func nonBundle() {
        let daemon = ProcessIdentity.from(path: "/usr/libexec/duetexpertd", fallbackName: "x")
        #expect(daemon.groupKey == "/usr/libexec/duetexpertd")
        #expect(daemon.bundlePath == nil)
        #expect(daemon.isSystemPath)
        let tool = ProcessIdentity.from(path: "/opt/homebrew/bin/node", fallbackName: "x")
        #expect(!tool.isSystemPath)
        let unknown = ProcessIdentity.from(path: "", fallbackName: "kernel_task")
        #expect(unknown.processName == "kernel_task")
    }

    @Test("Tür: Dock'taki uygulama, arka plan, sistem, diğer")
    func kinds() {
        let regular: Set = ["/Applications/Safari.app", "/System/Library/CoreServices/Finder.app"]
        #expect(ProcessIdentity.kind(bundlePath: "/Applications/Safari.app", isSystemPath: false, regularBundles: regular) == .app)
        #expect(ProcessIdentity.kind(bundlePath: "/System/Library/CoreServices/Finder.app", isSystemPath: true, regularBundles: regular) == .app)
        #expect(ProcessIdentity.kind(bundlePath: "/Applications/Stats.app", isSystemPath: false, regularBundles: regular) == .backgroundApp)
        #expect(ProcessIdentity.kind(bundlePath: "/System/Library/CoreServices/Dock.app", isSystemPath: true, regularBundles: regular) == .system)
        #expect(ProcessIdentity.kind(bundlePath: nil, isSystemPath: false, regularBundles: regular) == .other)
    }

    @Test("Grup toplamları ve sıralama")
    func totalsAndRanking() {
        let a = AppUsage(key: "a", name: "A", kind: .app, bundlePath: nil, processes: [
            ProcessUsage(pid: 1, name: "a1", cpu: 0.5, memory: 100),
            ProcessUsage(pid: 2, name: "a2", cpu: 0.25, memory: 50),
        ])
        let b = AppUsage(key: "b", name: "B", kind: .system, bundlePath: nil, processes: [
            ProcessUsage(pid: 3, name: "b", cpu: 1.0, memory: 10),
        ])
        let c = AppUsage(key: "c", name: "C", kind: .other, bundlePath: nil, processes: [
            ProcessUsage(pid: 4, name: "c", memory: 5),
        ])
        #expect(a.value(.cpu) == 0.75)
        #expect(a.value(.memory) == 150)
        #expect(c.value(.cpu) == nil)
        #expect(ProcessSnapshot.top([a, b, c], metric: .cpu, limit: 5).map(\.key) == ["b", "a"])
        #expect(ProcessSnapshot.top([a, b, c], metric: .memory, limit: 2).map(\.key) == ["a", "b"])
    }

    @Test("Biçimler")
    func formats() {
        #expect(ProcessMetric.memory.format(1_073_741_824) == "1,0 GB")
        #expect(ProcessMetric.memory.format(52_428_800) == "50 MB")
        #expect(ProcessMetric.cpu.format(1.5) == "%150")
        #expect(Fmt.power(0.0042) == "4 mW")
        #expect(Fmt.power(1.26) == "1,3 W")
        #expect(Fmt.energy(36) == "10 mWh")
        #expect(Fmt.energy(7200) == "2,0 Wh")
    }

    @Test("Sayaç farkı sıfırlanmada negatif olmaz")
    func counterMath() {
        #expect(CounterMath.delta(10, 4) == 6)
        #expect(CounterMath.delta(3, 4) == 0)
        #expect(CounterMath.rate(20, 10, seconds: 2) == 5)
        #expect(CounterMath.rate(20, 10, seconds: 0) == nil)
    }

    @Test("GPU istemci ayrıştırma ve oran")
    func gpuParsing() {
        #expect(GPUProcessSampler.parseCreator("pid 410, WindowServer")?.pid == 410)
        #expect(GPUProcessSampler.parseCreator("pid 410, WindowServer")?.name == "WindowServer")
        #expect(GPUProcessSampler.parseCreator("bozuk") == nil)
        let usage: [Any] = [
            ["API": "Metal", "accumulatedGPUTime": 1_000] as NSDictionary,
            ["API": "Metal", "accumulatedGPUTime": 500] as NSDictionary,
            "beklenmeyen" as NSString,
        ]
        #expect(GPUProcessSampler.gpuTime(usage) == 1_500)
        let rates = GPUProcessSampler.rates(current: [1: 3_000, 2: 100, 3: 50], previous: [1: 1_000, 2: 500], elapsedNanos: 4_000)
        #expect(rates[1] == 0.5)
        #expect(rates[2] == nil) // istemci kapanmış, toplam düşmüş
        #expect(rates[3] == nil) // yeni: önceki yok
    }

    @Test("Enerji defteri: kovalar, aralık, pil filtresi, sıkıştırma")
    func ledger() {
        var ledger = EnergyLedger()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        ledger.add(["a": 10, "b": 5], seconds: 60, onBattery: true, at: t0)
        ledger.add(["a": 10], seconds: 60, onBattery: true, at: t0.addingTimeInterval(60))
        ledger.add(["b": 30], seconds: 60, onBattery: false, at: t0.addingTimeInterval(120))
        #expect(ledger.buckets.count == 2)

        let all = ledger.summary(since: t0, batteryOnly: false, limit: 5)
        #expect(all.total == 55)
        #expect(all.seconds == 180)
        #expect(all.entries.map(\.key) == ["b", "a"])

        let battery = ledger.summary(since: t0, batteryOnly: true, limit: 1)
        #expect(battery.entries.map(\.key) == ["a"])
        #expect(battery.others == 5)
        #expect(battery.total == 25)

        var bucket = EnergyLedger.Bucket(start: t0, onBattery: false, seconds: 1, energy: ["a": 3, "b": 2, "c": 1], others: 0)
        bucket.compact(keep: 2)
        #expect(bucket.energy.keys.sorted() == ["a", "b"])
        #expect(bucket.others == 1)
    }

    @Test("Gerçek sistem: kendi işlemimiz okunur, oranlar makul")
    func realScan() throws {
        let sampler = ProcessSampler()
        let first = sampler.scan()
        #expect(first.interval == nil)
        #expect(first.processes.count > 10)
        let me = try #require(first.processes.first { $0.usage.pid == getpid() })
        #expect((me.usage.memory ?? 0) > 1_000_000)

        // Biraz CPU harca, sonra yeniden ölç.
        let end = Date().addingTimeInterval(0.3)
        var x = 0.0
        while Date() < end { x += sin(x) }
        #expect(x.isFinite)

        let second = sampler.scan()
        let interval = try #require(second.interval)
        #expect(interval > 0.25)
        let mine = try #require(second.processes.first { $0.usage.pid == getpid() })
        let cpu = try #require(mine.usage.cpu)
        #expect(cpu > 0.5 && cpu < 1.5, "tek iş parçacığı yaklaşık bir çekirdek: \(cpu)")
        let snapshot = sampler.snapshot(from: second, gpu: nil)
        #expect(snapshot.apps.contains { $0.processes.contains { $0.pid == getpid() } })
        #expect(snapshot.totalCPU < Double(ProcessInfo.processInfo.activeProcessorCount) + 1)
    }
}
