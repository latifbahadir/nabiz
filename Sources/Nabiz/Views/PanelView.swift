import AppKit
import SwiftUI

struct PanelView: View {
    @Bindable var model: PanelModel
    let monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nabız").font(.title3.weight(.semibold))
                Text(model.topology.chip).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }

            Picker("Görünüm", selection: $model.tab) {
                Text("Sistem").tag(PanelTab.system)
                Text("Ağ · Disk").tag(PanelTab.io)
                if model.hasBattery { Text("Pil").tag(PanelTab.battery) }
                Text("Doğrulama").tag(PanelTab.verify)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.tab {
            case .system: SystemTab(model: model)
            case .io: IOTab(model: model)
            case .battery: BatteryTab(model: model)
            case .verify: VerificationView(model: model, monitor: monitor)
            }

            Divider()

            HStack {
                Text("Her \(Int(model.interval)) saniyede bir ölçülüyor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
