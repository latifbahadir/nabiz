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
                Text("Genel").tag(PanelTab.overview)
                Text("Doğrulama").tag(PanelTab.verify)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch model.tab {
            case .overview: OverviewView(model: model)
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
