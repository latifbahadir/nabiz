import AppKit

@main
@MainActor
enum NabizApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Dock ikonu yok
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: Monitor?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let monitor = Monitor()
        self.monitor = monitor

        // Geliştirme: `Nabiz --snapshot <dosya.png> [verify]` paneli dosyaya çizip çıkar.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            monitor.start()
            Snapshot.render(monitor: monitor, to: args[i + 1], verify: args.contains("verify"))
            return
        }

        statusBar = StatusBarController(monitor: monitor)
        monitor.start()
    }
}
