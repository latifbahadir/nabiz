import Foundation

struct HistoryPoint: Sendable {
    let date: Date
    let cpu: Double
    let memory: Double
}

/// Sabit kapasiteli halka tampon: eski kayıtlar kendiliğinden düşer.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private var head = 0
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    var elements: [Element] {
        storage.count < capacity ? storage : Array(storage[head...] + storage[..<head])
    }
}

/// Tüm ölçümleri yöneten tek zamanlayıcı.
///
/// Tüketimi düşük tutmak için:
/// - Tek bir zamanlayıcı, toleranslı (sistem uyanmaları birleştirebilsin).
/// - Panel kapalıyken yalnızca CPU/RAM sayaçları okunur ve menü metni
///   değiştiyse güncellenir; SwiftUI tarafına hiçbir şey gönderilmez.
/// - Panel verisi yalnızca panel açıkken yayınlanır.
@MainActor
final class Monitor {
    static let interval: TimeInterval = 2
    static let historyCapacity = Int(3600 / interval) // son 1 saat

    let topology: CPUTopology
    let panel: PanelModel

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let selfSampler = SelfUsageSampler()
    private var history = RingBuffer<HistoryPoint>(capacity: historyCapacity)
    private var timer: Timer?
    private var panelVisible = false

    private(set) var latestCPU: CPUSnapshot?
    private(set) var latestMemory: MemorySnapshot?
    var onTick: (() -> Void)?

    init() {
        topology = CPUTopology.load()
        panel = PanelModel(topology: topology, interval: Self.interval)
    }

    func start() {
        tick()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = Self.interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        if visible { publish() }
    }

    /// Doğrulama ekranı için: vm_stat'ı çalıştırır ve hemen ardından kendi ölçümünü alır.
    func compareWithVMStat() async -> (vmStat: [String: UInt64], ours: RawVMStats)? {
        guard let vmStat = await VMStat.run(), let ours = memorySampler.sample() else { return nil }
        return (vmStat, ours.raw)
    }

    private func tick() {
        latestCPU = cpuSampler.sample()
        latestMemory = memorySampler.sample()
        if let cpu = latestCPU, let memory = latestMemory {
            history.append(HistoryPoint(date: Date(), cpu: cpu.total, memory: memory.usedFraction))
        }
        onTick?()
        if panelVisible { publish() }
    }

    private func publish() {
        panel.cpu = latestCPU
        panel.memory = latestMemory
        panel.history = history.elements
        panel.selfUsage = selfSampler.sample()
    }
}
