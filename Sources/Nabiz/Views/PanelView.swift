import AppKit
import SwiftUI

struct PanelView: View {
    @Bindable var model: PanelModel
    let monitor: Monitor
    /// Sekme içeriğinin en fazla yüksekliği; aşarsa içerik kaydırılır (panel ekrandan taşmasın).
    /// `nil`: kaydırma yok (PNG'ye çizerken; ImageRenderer ScrollView çizmez).
    var maxContentHeight: CGFloat?

    @State private var contentHeight: CGFloat = 0

    /// Panelin sığacağı ekran: başlık, sekmeler, alt satır ve ok için pay bırakılır.
    static func maxContentHeight(for screen: NSScreen?) -> CGFloat {
        let available = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        return max(available - 230, 300)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Nabız").font(.title3.weight(.semibold))
                Text(model.topology.chip).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }

            Picker("Görünüm", selection: $model.tab) {
                Text("Sistem").tag(PanelTab.system)
                Text("Uygulamalar").tag(PanelTab.apps)
                Text("Ağ · Disk").tag(PanelTab.io)
                if model.hasBattery { Text("Pil").tag(PanelTab.battery) }
                Text("Doğrulama").tag(PanelTab.verify)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let maxContentHeight {
                ScrollView(.vertical) {
                    tabContent
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        })
                }
                .id(model.tab) // sekme değişince en üstten başla
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
                .frame(height: min(max(contentHeight, 1), maxContentHeight))
            } else {
                tabContent
            }

            Divider()

            LaunchAtLoginRow(model: model)

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

    @ViewBuilder private var tabContent: some View {
        switch model.tab {
        case .system: SystemTab(model: model)
        case .apps: AppsTab(model: model)
        case .io: IOTab(model: model)
        case .battery: BatteryTab(model: model)
        case .verify: VerificationView(model: model, monitor: monitor)
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct LaunchAtLoginRow: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Girişte başlat", isOn: Binding(
                get: { model.launchAtLogin.enabled },
                set: { model.launchAtLogin = LaunchAtLogin.set($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)

            if let message = model.launchAtLogin.message {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(message).fixedSize(horizontal: false, vertical: true)
                    if model.launchAtLogin.needsApproval {
                        Button("Aç") { LaunchAtLogin.openLoginItemsSettings() }
                            .controlSize(.mini)
                    }
                }
                .font(.caption)
            }
        }
    }
}
