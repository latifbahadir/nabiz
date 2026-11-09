import SwiftUI

struct IOTab: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RangePicker(model: model)
            NetworkSection(model: model)
            Divider()
            DiskSection(model: model)
        }
    }
}

private struct NetworkSection: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ağ", symbol: "network", value: model.primaryInterface)

            HStack(spacing: 18) {
                RateValue(symbol: "arrow.down", color: .blue, label: "İndirme", value: model.network?.download)
                RateValue(symbol: "arrow.up", color: .orange, label: "Yükleme", value: model.network?.upload)
                Spacer()
            }

            RateChart(
                series: [
                    .init(label: "İndirme", color: .blue, points: model.chartPoints(\.download)),
                    .init(label: "Yükleme", color: .orange, points: model.chartPoints(\.upload)),
                ],
                range: model.range
            )

            Text("Wi‑Fi, Ethernet ve hücresel arayüzlerinin toplamı; VPN tünelleri çift sayılmaz.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiskSection: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Disk", symbol: "internaldrive",
                value: model.diskCapacity.map { "\(Fmt.decimalBytes($0.used)) / \(Fmt.decimalBytes($0.total))" }
            )

            if let capacity = model.diskCapacity {
                FillBar(fraction: capacity.usedFraction, color: .teal)
                Text("Kullanılabilir: \(Fmt.decimalBytes(capacity.availableForImportantUsage)) (\(capacity.volumeName ?? "/"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                RateValue(symbol: "arrow.down.doc", color: .teal, label: "Okuma", value: model.diskIO?.rate.readRate)
                RateValue(symbol: "arrow.up.doc", color: .pink, label: "Yazma", value: model.diskIO?.rate.writeRate)
                Spacer()
            }

            RateChart(
                series: [
                    .init(label: "Okuma", color: .teal, points: model.chartPoints(\.diskRead)),
                    .init(label: "Yazma", color: .pink, points: model.chartPoints(\.diskWrite)),
                ],
                range: model.range
            )
        }
    }
}

private struct RateValue: View {
    let symbol: String
    let color: Color
    let label: String
    let value: Double?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value.map(Fmt.rate) ?? "—").font(.callout.monospacedDigit().weight(.medium))
            }
        }
    }
}
