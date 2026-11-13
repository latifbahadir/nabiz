import SwiftUI

struct BatteryTab: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Pil", symbol: "battery.100", value: model.battery.map { "%\($0.percent)" })

            if let battery = model.battery {
                FillBar(fraction: Double(battery.percent) / 100, color: color(for: battery))
                Text(statusText(battery))
                    .font(.callout)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    InfoRow("Sağlık", battery.health.map { Fmt.percent($0) } ?? "—")
                    InfoRow("Döngü sayısı", battery.cycleCount.map(String.init) ?? "—")
                    InfoRow("Güç", battery.watts.map(powerText) ?? "—")
                    InfoRow("Sıcaklık", battery.temperatureCelsius.map { Fmt.celsius($0) } ?? "—")
                    InfoRow("Tam şarj kapasitesi", battery.nominalCapacity.map { "\(Fmt.integer(UInt64($0))) mAh" } ?? "—")
                    InfoRow("Tasarım kapasitesi", battery.designCapacity.map { "\(Fmt.integer(UInt64($0))) mAh" } ?? "—")
                }
                .font(.caption)
            } else {
                Text("Pil bilgisi okunamadı.").foregroundStyle(.secondary)
            }

            Divider()
            EnergyLedgerSection(model: model, limit: 6)
        }
    }

    private func statusText(_ battery: BatterySnapshot) -> String {
        switch battery.state {
        case .charging:
            "Şarj oluyor" + (battery.minutesRemaining.map { " · dolmasına \(Fmt.duration(minutes: $0))" } ?? "")
        case .charged:
            "Tamamen dolu · adaptörde"
        case .onACNotCharging:
            "Adaptörde · şarj olmuyor"
        case .discharging:
            "Pilde" + (battery.minutesRemaining.map { " · \(Fmt.duration(minutes: $0)) kaldı" } ?? " · süre hesaplanıyor")
        }
    }

    private func powerText(_ watts: Double) -> String {
        let magnitude = Fmt.number(abs(watts), digits: 1) + " W"
        if abs(watts) < 0.05 { return "0 W" }
        return watts > 0 ? "\(magnitude) (pile giriyor)" : "\(magnitude) (pilden çekiliyor)"
    }

    private func color(for battery: BatterySnapshot) -> Color {
        if battery.state == .charging { return .green }
        return battery.percent <= 20 ? .red : .green.opacity(0.8)
    }
}
