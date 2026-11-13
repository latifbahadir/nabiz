import AppKit
import SwiftUI

/// Menü çubuğu öğesi ve açılır panel.
///
/// Panel kapandığında SwiftUI görünüm ağacı tamamen bırakılır; kapalıyken
/// arka planda çizim ya da gözlem maliyeti kalmaz.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let monitor: Monitor
    private var lastTitle = ""
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)

    init(monitor: Monitor) {
        self.monitor = monitor
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        item.autosaveName = "NabizStatusItem" // ⌘-sürükleyerek verilen konum hatırlansın
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Nabız")
            button.target = self
            button.action = #selector(togglePanel(_:))
        }

        monitor.onTick = { [weak self] in self?.updateTitle() }
        updateTitle()
    }

    private func updateTitle() {
        let cpu = monitor.latestCPU.map { Fmt.paddedPercent($0.total) } ?? "—"
        let ram = monitor.latestMemory.map { Fmt.paddedPercent($0.usedFraction) } ?? "—"
        let lines = ["CPU \(cpu)", "RAM \(ram)"]
        let title = lines.joined(separator: "\n")
        guard title != lastTitle else { return } // değişmediyse yeniden çizme
        lastTitle = title
        item.button?.image = Self.twoLineImage(lines, font: font)
    }

    /// Menü çubuğunda yer kaplamasın diye iki satırlık dar bir görüntü.
    /// Şablon (template) görüntü olduğundan açık/koyu menü çubuğuna kendiliğinden uyar.
    private static func twoLineImage(_ lines: [String], font: NSFont) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let strings = lines.map { NSAttributedString(string: $0, attributes: attributes) }
        let width = ceil(strings.map { $0.size().width }.max() ?? 0)
        let lineHeight = ceil(font.ascender - font.descender)
        let size = NSSize(width: width, height: 22)
        let image = NSImage(size: size, flipped: true) { _ in
            let top = (size.height - lineHeight * 2) / 2
            for (i, string) in strings.enumerated() {
                string.draw(at: NSPoint(x: 0, y: top + lineHeight * CGFloat(i)))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        let host = NSHostingController(rootView: PanelView(
            model: monitor.panel,
            monitor: monitor,
            maxContentHeight: PanelView.maxContentHeight(for: sender.window?.screen)
        ))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        monitor.setPanelVisible(true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate()
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.setPanelVisible(false)
        popover.contentViewController = nil
    }
}
