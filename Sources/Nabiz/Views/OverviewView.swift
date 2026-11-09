import Charts
import SwiftUI

struct OverviewView: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Geçmiş").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Geçmiş", selection: $model.range) {
                    ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 170)
            }
            CPUSection(model: model)
            Divider()
            MemorySection(model: model)
        }
    }
}

// MARK: - İşlemci

private struct CPUSection: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "İşlemci", symbol: "cpu", value: model.cpu.map { Fmt.percent($0.total) })

            if let cpu = model.cpu {
                Text("Kullanıcı \(Fmt.percent(cpu.user)) · Sistem \(Fmt.percent(cpu.system)) · Boşta \(Fmt.percent(cpu.idle))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HistoryChart(points: model.chartPoints(\.cpu), range: model.range, tint: .blue)

            ForEach(model.topology.groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(group.name) çekirdekleri (\(group.cpuIDs.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 3) {
                        ForEach(group.cpuIDs, id: \.self) { id in
                            CoreBar(id: id, load: model.cpu?.cores.indices.contains(id) == true ? model.cpu?.cores[id] : nil)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                LegendDot(color: .blue, label: "Kullanıcı")
                LegendDot(color: .orange, label: "Sistem")
                Spacer()
                if let load = model.cpu?.loadAverage, load.count == 3 {
                    Text("Yük: " + load.map { Fmt.number($0, digits: 2) }.joined(separator: "  "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("Yük ortalaması: son 1, 5 ve 15 dakika")
                }
            }
        }
    }
}

private struct CoreBar: View {
    let id: Int
    let load: CoreLoad?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                Rectangle().fill(.quaternary)
                VStack(spacing: 0) {
                    Rectangle().fill(.orange).frame(height: h * (load?.system ?? 0))
                    Rectangle().fill(.blue).frame(height: h * (load?.user ?? 0))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(height: 26)
        .help("Çekirdek \(id): \(load.map { Fmt.percent($0.total) } ?? "—")")
    }
}

// MARK: - Bellek

private struct MemorySection: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Bellek", symbol: "memorychip",
                value: model.memory.map { "\(Fmt.bytes($0.used)) / \(Fmt.bytes($0.total))" }
            )

            if let memory = model.memory {
                MemoryBar(memory: memory)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    GridRow {
                        LegendValue(color: .blue, label: "Uygulama", value: memory.app)
                        LegendValue(color: .orange, label: "Sabit (wired)", value: memory.wired)
                    }
                    GridRow {
                        LegendValue(color: .purple, label: "Sıkıştırılmış", value: memory.compressed)
                        LegendValue(color: .gray, label: "Önbellek", value: memory.cachedFiles)
                    }
                }
            }

            HistoryChart(points: model.chartPoints(\.memory), range: model.range, tint: .green)

            if let memory = model.memory {
                HStack {
                    Text("Takas: \(Fmt.bytes(memory.swapUsed)) / \(Fmt.bytes(memory.swapTotal))")
                    Spacer()
                    PressureLabel(memory: memory)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MemoryBar: View {
    let memory: MemorySnapshot

    var body: some View {
        let parts: [(UInt64, Color)] = [
            (memory.app, .blue), (memory.wired, .orange),
            (memory.compressed, .purple), (memory.cachedFiles, .gray.opacity(0.6)),
        ]
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(parts.indices, id: \.self) { i in
                    Rectangle()
                        .fill(parts[i].1)
                        .frame(width: geo.size.width * min(Double(parts[i].0) / Double(max(memory.total, 1)), 1))
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }
}

private struct PressureLabel: View {
    let memory: MemorySnapshot

    var body: some View {
        let (text, color): (String, Color) = switch memory.pressure {
        case .normal: ("Normal", .green)
        case .warning: ("Uyarı", .yellow)
        case .critical: ("Kritik", .red)
        case .unknown: ("Bilinmiyor", .secondary)
        }
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("Baskı: \(text)")
            if let available = memory.availablePercent {
                Text("(kullanılabilir %\(available))")
            }
        }
        .help("Çekirdeğin bildirdiği bellek baskısı seviyesi (kern.memorystatus_vm_pressure_level)")
    }
}

// MARK: - Ortak parçalar

private struct SectionHeader: View {
    let title: String
    let symbol: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol).font(.headline)
            Spacer()
            Text(value ?? "—").font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct LegendValue: View {
    let color: Color
    let label: String
    let value: UInt64

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(Fmt.bytes(value)).monospacedDigit()
        }
        .font(.caption)
    }
}

struct HistoryChart: View {
    let points: [ChartPoint]
    let range: HistoryRange
    let tint: Color

    var body: some View {
        let now = Date()
        Chart(points) { point in
            AreaMark(x: .value("Zaman", point.date), y: .value("Değer", point.value))
                .foregroundStyle(tint.opacity(0.2))
            LineMark(x: .value("Zaman", point.date), y: .value("Değer", point.value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
        }
        .chartXScale(domain: now.addingTimeInterval(-range.rawValue)...now)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Fmt.percent(v)) }
                }
            }
        }
        .frame(height: 64)
    }
}
