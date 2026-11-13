import Charts
import SwiftUI

struct SystemTab: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RangePicker(model: model)
            CPUSection(model: model)
            Divider()
            GPUSection(model: model)
            Divider()
            TemperatureSection(model: model)
            Divider()
            if let fans = model.fans, !fans.fans.isEmpty {
                FanSection(fans: fans)
                Divider()
            }
            MemorySection(model: model)
        }
    }
}

// MARK: - İşlemci

private struct CPUSection: View {
    @Bindable var model: PanelModel

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

            TopSummary(model: model, metric: .cpu)
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

// MARK: - GPU

private struct GPUSection: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "GPU", symbol: "square.stack.3d.up", value: model.gpu.map { Fmt.percent($0.device) })

            if let gpu = model.gpu {
                Text(details(gpu))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if case .unavailable = model.gpuStatus {
                Label("Okunamadı — ayrıntı Doğrulama sekmesinde", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HistoryChart(points: model.chartPoints(\.gpu), range: model.range, tint: .purple)

            TopSummary(model: model, metric: .gpu)
        }
    }

    private func details(_ gpu: GPUSnapshot) -> String {
        var parts: [String] = []
        if let renderer = gpu.renderer { parts.append("İşleyici \(Fmt.percent(renderer))") }
        if let tiler = gpu.tiler { parts.append("Döşeyici \(Fmt.percent(tiler))") }
        if let memory = gpu.inUseMemory { parts.append("Bellek \(Fmt.bytes(memory))") }
        if let cores = model.gpuInfo?.coreCount { parts.append("\(cores) çekirdek") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sıcaklık

private struct TemperatureSection: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Sıcaklık", symbol: "thermometer.medium", value: headline)

            if let t = model.temperature, t.cpu != nil || t.gpu != nil {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    row("İşlemci", t.cpu)
                    row("GPU", t.gpu)
                }
                .font(.caption)
            } else if case .unavailable = model.temperatureStatus {
                Label("Okunamadı — ayrıntı Doğrulama sekmesinde", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(ageText)
                Spacer()
                Picker("Okuma sıklığı", selection: $model.sensorInterval) {
                    ForEach(SensorSettings.choices, id: \.self) { Text("\($0) sn").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 130)
                .help("Sıcaklık ve fan yalnızca panel açıkken bu sıklıkla okunur")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var headline: String? {
        guard let t = model.temperature else { return nil }
        let parts = [t.cpu.map { "CPU \(Fmt.number($0.maximum, digits: 0))°" }, t.gpu.map { "GPU \(Fmt.number($0.maximum, digits: 0))°" }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var ageText: String {
        guard let date = model.temperature?.date else { return "Okunuyor…" }
        let seconds = max(Int(Date().timeIntervalSince(date)), 0)
        return seconds < 2 ? "Az önce okundu" : "\(seconds) sn önce okundu"
    }

    private func row(_ label: String, _ stats: TemperatureStats?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(stats.map { "en yüksek \(Fmt.celsius($0.maximum))" } ?? "—").monospacedDigit()
            Text(stats.map { "ort. \(Fmt.celsius($0.average)) · \($0.count) sensör" } ?? "").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

// MARK: - Fan

private struct FanSection: View {
    let fans: FanSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Fanlar", symbol: "fan", value: headline)
            ForEach(fans.fans) { fan in
                HStack(spacing: 8) {
                    Text("Fan \(fan.id + 1)").foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
                    FillBar(fraction: fan.fraction ?? 0, color: .teal)
                    Text(detail(fan)).monospacedDigit().frame(width: 150, alignment: .trailing)
                }
                .font(.caption)
            }
        }
    }

    private var headline: String {
        fans.fans.allSatisfy(\.isStopped) ? "Duruyor" : fans.fans.map { Fmt.integer(UInt64($0.actual.rounded())) }.joined(separator: " · ") + " RPM"
    }

    private func detail(_ fan: FanInfo) -> String {
        if fan.isStopped { return "duruyor" }
        let rpm = "\(Fmt.integer(UInt64(fan.actual.rounded()))) RPM"
        guard let fraction = fan.fraction, let maximum = fan.maximum else { return rpm }
        return "\(rpm) · \(Fmt.percent(fraction)) / \(Fmt.integer(UInt64(maximum.rounded())))"
    }
}

// MARK: - Bellek

private struct MemorySection: View {
    @Bindable var model: PanelModel

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

            TopSummary(model: model, metric: .memory)
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
