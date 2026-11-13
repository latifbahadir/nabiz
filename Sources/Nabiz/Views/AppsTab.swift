import AppKit
import SwiftUI

/// Uygulama ikonları; panel kapanınca boşaltılır.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var icons: [String: NSImage] = [:]

    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        if icons.count > 60 { icons.removeAll() }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        icons[path] = icon
        return icon
    }

    func removeAll() { icons.removeAll() }
}

/// Kaynakları kim kullanıyor: uygulama / servis bazında sıralı liste.
struct AppsTab: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Ölçüt", selection: $model.processMetric) {
                ForEach(ProcessMetric.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TopList(model: model, metric: model.processMetric, limit: 12, expandable: true)
            if model.processMetric == .energy {
                Divider()
                EnergyLedgerSection(model: model, limit: 10)
            }

            footer
        }
    }

    private var explanation: String {
        switch model.processMetric {
        case .cpu: "Son \(Int(model.interval)) sn. %100 = bir çekirdek tam dolu (Activity Monitor gibi)."
        case .memory: "Anlık bellek ayak izi (Activity Monitor “Bellek” sütunu)."
        case .gpu: "Son \(Int(model.interval)) sn'de GPU'da çalışılan süre oranı."
        case .energy: "Şu anki ortalama güç (işlem enerji sayaçları). Altta: geçmişte pili en çok harcayanlar."
        case .disk: "Son \(Int(model.interval)) sn'de diske okunan + yazılan."
        }
    }

    @ViewBuilder private var footer: some View {
        if let p = model.processes {
            Text("\(p.readableCount) işlem okundu · \(p.restrictedCount) sistem işlemi yetki gerektiriyor (root)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Root veya başka kullanıcıya ait işlemlerin sayaçları yönetici yetkisi olmadan okunamaz. CPU'daki payları “Yetki gerektiren sistem işlemleri” satırında gösterilir.")
        }
    }
}

/// Bir ölçüte göre en çok kullanan uygulamalar.
struct TopList: View {
    @Bindable var model: PanelModel
    let metric: ProcessMetric
    let limit: Int
    let expandable: Bool

    var body: some View {
        if let snapshot = model.processes {
            let apps = snapshot.top(metric, limit: limit)
            let peak = max(apps.first?.value(metric) ?? 0, restricted ?? 0, 1e-9)
            VStack(alignment: .leading, spacing: expandable ? 4 : 3) {
                if apps.isEmpty {
                    Text(emptyText(snapshot)).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(apps) { app in
                    AppRow(model: model, app: app, metric: metric, peak: peak, expandable: expandable)
                }
                if let restricted, restricted >= 0.01 {
                    RestrictedRow(value: restricted, peak: peak, compact: !expandable)
                }
            }
        } else {
            Text("Ölçülüyor…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var restricted: Double? {
        metric == .cpu ? model.restrictedCPU : nil
    }

    private func emptyText(_ snapshot: ProcessSnapshot) -> String {
        if snapshot.interval == nil, metric != .memory { return "Ölçülüyor…" }
        if metric == .gpu, case .unavailable = model.gpuProcessStatus {
            return "İşlem başına GPU okunamadı — ayrıntı Doğrulama sekmesinde"
        }
        return "Şu an kullanan yok"
    }
}

private struct AppRow: View {
    @Bindable var model: PanelModel
    let app: AppUsage
    let metric: ProcessMetric
    let peak: Double
    let expandable: Bool

    private var expanded: Bool { model.expandedApps.contains(app.key) }

    var body: some View {
        let value = app.value(metric) ?? 0
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if expandable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                        .frame(width: 8)
                        .opacity(app.processes.count > 1 ? 1 : 0)
                }
                AppIcon(app: app)
                VStack(alignment: .leading, spacing: 0) {
                    Text(app.name).lineLimit(1).truncationMode(.middle)
                    if expandable {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(metric.format(value))
                    .monospacedDigit()
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .font(expandable ? .callout : .caption)
            .contentShape(Rectangle())
            .onTapGesture {
                guard expandable, app.processes.count > 1 else { return }
                if expanded { model.expandedApps.remove(app.key) } else { model.expandedApps.insert(app.key) }
            }
            .help(help)

            if expandable {
                FillBar(fraction: value / peak, color: color)
                    .frame(height: 4)
                    .padding(.leading, 30)
            }

            if expandable, expanded {
                ProcessList(app: app, metric: metric)
                    .padding(.leading, 30)
            }
        }
    }

    private var subtitle: String {
        var parts = [app.kind.label]
        if app.processes.count > 1 { parts.append("\(app.processes.count) işlem") }
        if metric == .energy, let wakeups = app.processes.compactMap(\.wakeups).reduce(nil, { ($0 ?? 0) + $1 }) {
            parts.append("\(Fmt.number(wakeups, digits: 0)) uyanma/sn")
        }
        return parts.joined(separator: " · ")
    }

    private var help: String {
        var lines = ["\(app.name) — \(app.kind.label)"]
        if let path = app.bundlePath ?? (app.key.hasPrefix("/") ? app.key : nil) { lines.append(path) }
        return lines.joined(separator: "\n")
    }

    private var color: Color {
        switch metric {
        case .cpu: .blue
        case .memory: .green
        case .gpu: .purple
        case .energy: .orange
        case .disk: .teal
        }
    }
}

private struct ProcessList: View {
    let app: AppUsage
    let metric: ProcessMetric

    var body: some View {
        let sorted = app.processes.sorted { ($0.value(metric) ?? 0) > ($1.value(metric) ?? 0) }
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sorted.prefix(8)) { process in
                HStack {
                    Text(process.name).lineLimit(1).truncationMode(.middle)
                    Text("\(process.pid)").foregroundStyle(.tertiary)
                    Spacer()
                    Text(process.value(metric).map(metric.format) ?? "—").monospacedDigit()
                }
            }
            if sorted.count > 8 {
                Text("+\(sorted.count - 8) işlem daha").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct RestrictedRow: View {
    let value: Double
    let peak: Double
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if !compact { Color.clear.frame(width: 8, height: 1) }
                Image(systemName: "lock").frame(width: 16).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Yetki gerektiren sistem işlemleri").lineLimit(1)
                    if !compact {
                        Text("kernel_task, WindowServer… · toplamdan hesaplandı")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(ProcessMetric.cpu.format(value)).monospacedDigit().frame(minWidth: 52, alignment: .trailing)
            }
            .font(compact ? .caption : .callout)
            .foregroundStyle(.secondary)
            .help("Root işlemlerinin sayaçları yetkisiz okunamaz. Değer = sistem CPU toplamı − okunabilen işlemlerin toplamı.")
            if !compact {
                FillBar(fraction: value / peak, color: .gray).frame(height: 4).padding(.leading, 30)
            }
        }
    }
}

struct AppIcon: View {
    let app: AppUsage

    var body: some View {
        if let path = app.bundlePath {
            Image(nsImage: AppIconCache.shared.icon(for: path))
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: app.kind.symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }
}

/// Sistem sekmesindeki kısa "En çok" özeti.
struct TopSummary: View {
    @Bindable var model: PanelModel
    let metric: ProcessMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("En çok kullananlar").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Tümü") {
                    model.processMetric = metric
                    model.tab = .apps
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            TopList(model: model, metric: metric, limit: 3, expandable: false)
        }
    }
}

/// Geçmişte en çok enerji harcayanlar (enerji defterinden).
struct EnergyLedgerSection: View {
    @Bindable var model: PanelModel
    let limit: Int

    var body: some View {
        let summary = model.energySummary(limit: limit)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("En çok enerji harcayanlar", systemImage: "battery.75percent").font(.headline)
                Spacer()
            }
            HStack {
                Picker("Aralık", selection: $model.energyRange) {
                    ForEach(EnergyRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
                Spacer()
                Toggle("Yalnızca pildeyken", isOn: $model.energyBatteryOnly)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)
            }

            if summary.total <= 0 {
                Text(emptyText(summary))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(summary.entries) { entry in
                    EnergyRow(
                        name: name(entry.key),
                        info: model.processGroups[entry.key],
                        key: entry.key,
                        joules: entry.joules,
                        share: entry.joules / summary.total,
                        seconds: summary.seconds
                    )
                }
                if summary.others > 0 {
                    HStack {
                        Text("Diğerleri").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.energy(summary.others)) · \(Fmt.percent(summary.others / summary.total))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                Text(footnote(summary))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func name(_ key: String) -> String {
        model.processGroups[key]?.name ?? (key as NSString).lastPathComponent
    }

    private func emptyText(_ summary: EnergyLedger.Summary) -> String {
        if model.energyBatteryOnly { return "Bu aralıkta pilde geçen ölçüm yok." }
        return "Henüz yeterli ölçüm yok. Nabız açık kaldıkça (dakikada bir) birikir."
    }

    private func footnote(_ summary: EnergyLedger.Summary) -> String {
        let minutes = Int((summary.seconds / 60).rounded())
        let span = minutes >= 60 ? Fmt.duration(minutes: minutes) : "\(max(minutes, 1)) dk"
        return "\(span) ölçüm · toplam \(Fmt.energy(summary.total)) (ort. \(Fmt.power(summary.total / max(summary.seconds, 1)))). Yalnızca okunabilen işlemler; ekran, Wi-Fi gibi donanım ve root işlemleri dahil değil."
    }
}

private struct EnergyRow: View {
    let name: String
    let info: ProcessGroupInfo?
    let key: String
    let joules: Double
    let share: Double
    let seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                icon
                Text(name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(Fmt.energy(joules)).monospacedDigit()
                Text(Fmt.percent(share)).monospacedDigit().foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
            .font(.callout)
            FillBar(fraction: share, color: .orange).frame(height: 4).padding(.leading, 22)
        }
        .help("\(name) — \(info?.kind.label ?? "kapanmış işlem")\nOrtalama \(Fmt.power(joules / max(seconds, 1)))\n\(key)")
    }

    @ViewBuilder private var icon: some View {
        if let path = info?.bundlePath {
            Image(nsImage: AppIconCache.shared.icon(for: path)).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: (info?.kind ?? .other).symbol)
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16, height: 16)
        }
    }
}
