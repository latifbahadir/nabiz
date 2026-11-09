import Foundation
import NabizUnofficial
import Observation

enum PanelTab: Hashable {
    case system, io, battery, verify
}

enum HistoryRange: Double, CaseIterable, Identifiable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case hour = 3600

    var id: Double { rawValue }
    var label: String {
        switch self {
        case .fiveMinutes: "5 dk"
        case .fifteenMinutes: "15 dk"
        case .hour: "1 sa"
        }
    }
}

struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

/// Panelin gösterdiği veriler. Yalnızca panel açıkken güncellenir.
@MainActor
@Observable
final class PanelModel {
    let topology: CPUTopology
    let interval: TimeInterval
    let hasBattery: Bool

    var cpu: CPUSnapshot?
    var memory: MemorySnapshot?
    var history: [HistoryPoint] = []
    var selfUsage: SelfUsage?
    var network: NetworkSnapshot?
    var primaryInterface: String?
    var diskIO: DiskIOSnapshot?
    var diskCapacity: DiskCapacity?
    var battery: BatterySnapshot?
    var gpu: GPUSnapshot?
    var gpuInfo: GPUInfo?
    var gpuStatus: UnofficialStatus = .unknown
    var gpuSourceTitle = ""
    var temperature: TemperatureSnapshot?
    var temperatureStatus: UnofficialStatus = .unknown
    var temperatureInterval = TemperatureSettings.load() {
        didSet { TemperatureSettings.save(temperatureInterval) }
    }
    var hidTemperatures: [HIDTemperature.Reading]?
    var hidStatus: UnofficialStatus = .unknown

    var launchAtLogin = LaunchAtLogin.State(enabled: false, message: nil, needsApproval: false)

    var tab: PanelTab = .system
    var range: HistoryRange = .fiveMinutes

    init(topology: CPUTopology, interval: TimeInterval, hasBattery: Bool) {
        self.topology = topology
        self.interval = interval
        self.hasBattery = hasBattery
    }

    /// Seçili aralıktaki noktalar; grafik maliyetini sınırlamak için en fazla
    /// `maxPoints` kovaya ortalanarak indirgenir.
    func chartPoints(_ value: KeyPath<HistoryPoint, Double>, maxPoints: Int = 180) -> [ChartPoint] {
        let start = Date().addingTimeInterval(-range.rawValue)
        let points = history
            .filter { $0.date >= start }
            .map { ChartPoint(date: $0.date, value: $0[keyPath: value]) }
        return Self.downsample(points, maxPoints: maxPoints)
    }

    /// İsteğe bağlı değerler için: okunamayan noktalar grafiğe girmez (sıfır olarak çizilmez).
    func chartPoints(_ value: KeyPath<HistoryPoint, Double?>, maxPoints: Int = 180) -> [ChartPoint] {
        let start = Date().addingTimeInterval(-range.rawValue)
        let points = history
            .filter { $0.date >= start }
            .compactMap { point in point[keyPath: value].map { ChartPoint(date: point.date, value: $0) } }
        return Self.downsample(points, maxPoints: maxPoints)
    }

    /// Noktaları eşit kovalara bölüp ortalamasını alır; her kova son noktasının tarihini taşır.
    nonisolated static func downsample(_ points: [ChartPoint], maxPoints: Int) -> [ChartPoint] {
        guard maxPoints > 0, points.count > maxPoints else { return points }
        let bucket = Int((Double(points.count) / Double(maxPoints)).rounded(.up))
        return stride(from: 0, to: points.count, by: bucket).map { i in
            let slice = points[i..<min(i + bucket, points.count)]
            let mean = slice.reduce(0) { $0 + $1.value } / Double(slice.count)
            return ChartPoint(date: slice.last!.date, value: mean)
        }
    }
}
