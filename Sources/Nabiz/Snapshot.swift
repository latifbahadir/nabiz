import AppKit
import SwiftUI

/// Geliştirme aracı: paneli menü çubuğu olmadan PNG'ye çizer.
@MainActor
enum Snapshot {
    static func render(monitor: Monitor, to path: String, verify: Bool) {
        monitor.setPanelVisible(true)
        monitor.panel.tab = verify ? .verify : .overview
        // İlk CPU farkı için birkaç ölçüm bekle.
        DispatchQueue.main.asyncAfter(deadline: .now() + Monitor.interval * 3 + 0.5) {
            let renderer = ImageRenderer(content: PanelView(model: monitor.panel, monitor: monitor)
                .background(Color(nsColor: .windowBackgroundColor)))
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }
}
