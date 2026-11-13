import Foundation

struct HistoryPoint: Sendable {
    let date: Date
    let cpu: Double
    let memory: Double
    /// bayt/sn
    let download: Double
    let upload: Double
    let diskRead: Double
    let diskWrite: Double
    /// 0…1; okunamadıysa nil (grafikte boşluk, sıfır değil).
    var gpu: Double? = nil
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
/// - Ağ, disk G/Ç ve GPU (tek kayıt özelliği, ~20 µs) geçmiş grafiği için sürekli, pil ve disk doluluğu
///   yalnızca panel açıkken okunur.
@MainActor
final class Monitor {
    static let interval: TimeInterval = 2
    static let historyCapacity = Int(3600 / interval) // son 1 saat

    let topology: CPUTopology
    let panel: PanelModel

    private let cpuSampler = CPUSampler()
    private let memorySampler = MemorySampler()
    private let networkSampler = NetworkSampler()
    private let diskSampler = DiskSampler()
    private let gpuSampler = GPUSampler()
    private let sensorSampler = SMCSensorSampler()
    private var sensorsInFlight = false
    private let selfSampler = SelfUsageSampler()
    private let processSampler = ProcessSampler()
    private let gpuProcessSampler = GPUProcessSampler()
    private var energyLedger = EnergyLedger()
    private var ticksSinceProcessScan = 0
    /// Panel kapalıyken enerji defteri için işlem taraması sıklığı (tik): 30 × 2 sn = 60 sn.
    static let backgroundProcessScanTicks = 30
    private var lastCapacityRead: TimeInterval = -.infinity
    private var history = RingBuffer<HistoryPoint>(capacity: historyCapacity)
    private var timer: Timer?
    private var panelVisible = false

    private(set) var latestCPU: CPUSnapshot?
    private(set) var latestMemory: MemorySnapshot?
    private var latestNetwork: NetworkSnapshot?
    private var latestDiskIO: DiskIOSnapshot?
    private var latestGPU: GPUSnapshot?
    var onTick: (() -> Void)?

    init() {
        topology = CPUTopology.load()
        panel = PanelModel(
            topology: topology,
            interval: Self.interval,
            hasBattery: BatterySampler.sample() != nil
        )
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
        if visible {
            // Kullanıcı Sistem Ayarları'ndan değiştirmiş olabilir; panel her açıldığında okunur.
            panel.launchAtLogin = LaunchAtLogin.current()
            scanProcesses()
            publish()
        } else {
            // İşlem listesi ve ikonlar panel kapalıyken bellekte tutulmaz.
            panel.processes = nil
            gpuProcessSampler.reset()
            AppIconCache.shared.removeAll()
        }
    }

    /// Çökme koruması nedeniyle kapanmış GPU kaynağını yeniden dener.
    func retryGPU() {
        gpuSampler.gate.retryAfterCrash()
        panel.gpuStatus = gpuSampler.gate.status
    }

    /// Sıcaklık ve fan (SMC) yalnızca panel açıkken ve `sensorInterval` sn'de bir okunur (varsayılan 60).
    /// Panel açılınca son okuma eskiyse hemen; Doğrulama sekmesinde tüm anahtarlar gerekirse hemen.
    private func refreshSensorsIfDue() {
        guard panelVisible, !sensorsInFlight else { return }
        let wantsAll = panel.tab == .verify
        let age = panel.temperature.map { Date().timeIntervalSince($0.date) } ?? .infinity
        let needsAll = wantsAll && panel.temperature?.includesAll != true
        guard age >= Double(panel.sensorInterval) || needsAll else { return }
        sensorsInFlight = true
        sensorSampler.sample(includeAll: wantsAll) { [weak self] reading in
            guard let self else { return }
            sensorsInFlight = false
            panel.temperatureStatus = reading.temperatureStatus
            // Okunamadıysa eski değer gösterilmez; yine de yeniden deneme sıklığı korunur.
            panel.temperature = reading.temperature
                ?? TemperatureSnapshot(date: Date(), cpu: nil, gpu: nil, readings: [], includesAll: wantsAll)
            panel.fans = reading.fans
            panel.fanStatus = reading.fanStatus
        }
    }

    /// Doğrulama ekranındaki çapraz kontrol düğmesi için (pahalı, yalnızca istenince).
    func readHIDTemperatures() {
        sensorSampler.readHID { [weak self] readings, status in
            self?.panel.hidTemperatures = readings
            self?.panel.hidStatus = status
        }
    }

    func retryTemperature() {
        sensorSampler.retryAfterCrash { [weak self] status in
            guard let self else { return }
            panel.temperatureStatus = status
            panel.temperature = nil
            panel.fans = nil
            refreshSensorsIfDue()
        }
    }

    /// Doğrulama ekranı için: vm_stat'ı çalıştırır ve hemen ardından kendi ölçümünü alır.
    func compareWithVMStat() async -> (vmStat: [String: UInt64], ours: RawVMStats)? {
        guard let vmStat = await VMStat.run(), let ours = memorySampler.sample() else { return nil }
        return (vmStat, ours.raw)
    }

    private func tick() {
        latestCPU = cpuSampler.sample()
        latestMemory = memorySampler.sample()
        latestNetwork = networkSampler.sample()
        latestDiskIO = diskSampler.sampleIO()
        // Ham değerler (string üretimi) yalnızca panel açıkken.
        latestGPU = gpuSampler.sample(includeRaw: panelVisible)
        ticksSinceProcessScan += 1
        if panelVisible || ticksSinceProcessScan >= Self.backgroundProcessScanTicks {
            scanProcesses()
        }
        if let cpu = latestCPU, let memory = latestMemory {
            history.append(HistoryPoint(
                date: Date(),
                cpu: cpu.total,
                memory: memory.usedFraction,
                download: latestNetwork?.download ?? 0,
                upload: latestNetwork?.upload ?? 0,
                diskRead: latestDiskIO?.rate.readRate ?? 0,
                diskWrite: latestDiskIO?.rate.writeRate ?? 0,
                gpu: latestGPU?.device
            ))
        }
        onTick?()
        if panelVisible { publish() }
    }

    /// İşlemleri tarar ve enerji defterine yazar; panel açıksa uygulama listesini de üretir.
    private func scanProcesses() {
        ticksSinceProcessScan = 0
        let scan = processSampler.scan()
        if let seconds = scan.interval {
            energyLedger.add(scan.energyByGroup, seconds: seconds, onBattery: PowerSource.isOnBattery(), at: scan.date)
        }
        guard panelVisible else { return }
        let gpu = gpuProcessSampler.sample()
        panel.processes = processSampler.snapshot(from: scan, gpu: gpu)
        panel.processGroups = processSampler.groups
        panel.energyLedger = energyLedger
        panel.gpuProcessStatus = gpuProcessSampler.gate.status
        panel.gpuProcessSourceTitle = gpuProcessSampler.gate.title
    }

    private func publish() {
        panel.cpu = latestCPU
        panel.memory = latestMemory
        panel.history = history.elements
        panel.network = latestNetwork
        panel.diskIO = latestDiskIO
        panel.gpu = latestGPU
        panel.gpuInfo = gpuSampler.info
        panel.gpuStatus = gpuSampler.gate.status
        panel.gpuSourceTitle = gpuSampler.gate.title
        panel.selfUsage = selfSampler.sample()

        // Panel açıkken bile pahalı sayılabilecek okumalar seyrek yapılır.
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastCapacityRead >= 10 {
            lastCapacityRead = now
            panel.diskCapacity = DiskSampler.capacity()
            panel.primaryInterface = networkSampler.primaryInterface()
        }
        if panel.hasBattery {
            panel.battery = BatterySampler.sample()
        }
        refreshSensorsIfDue()
    }
}
