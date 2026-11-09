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

        // Geliştirme: `Nabiz --snapshot <dosya.png> [system|io|battery|verify]` paneli dosyaya çizip çıkar.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let tab: PanelTab = switch args.dropFirst(i + 2).first {
            case "io": .io
            case "battery": .battery
            case "verify": .verify
            default: .system
            }
            monitor.start()
            Snapshot.render(monitor: monitor, to: args[i + 1], tab: tab)
            return
        }

        // Geliştirme: `Nabiz --login-item status|on|off` giriş öğesi durumunu yazdırıp çıkar.
        if let i = args.firstIndex(of: "--login-item") {
            let state: LaunchAtLogin.State = switch args.dropFirst(i + 1).first {
            case "on": LaunchAtLogin.set(true)
            case "off": LaunchAtLogin.set(false)
            default: LaunchAtLogin.current()
            }
            print("girişte başlat: \(state.enabled ? "açık" : "kapalı")" + (state.message.map { " — \($0)" } ?? ""))
            NSApp.terminate(nil)
            return
        }

        statusBar = StatusBarController(monitor: monitor)
        monitor.start()
    }
}
