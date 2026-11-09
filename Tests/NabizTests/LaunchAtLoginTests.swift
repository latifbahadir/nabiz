import Foundation
import ServiceManagement
import Testing
@testable import Nabiz

@Suite("Girişte başlat")
struct LaunchAtLoginTests {
    @Test("Açık ve /Applications içinde: uyarı yok")
    func enabledInApplications() {
        let state = LaunchAtLogin.state(for: .enabled, bundlePath: "/Applications/Nabız.app")
        #expect(state == .init(enabled: true, message: nil, needsApproval: false))
    }

    @Test("Açık ama derleme klasöründen çalışıyor: konum uyarısı")
    func enabledOutsideApplications() {
        let state = LaunchAtLogin.state(for: .enabled, bundlePath: "/Users/x/projects/nabiz/build/Nabız.app")
        #expect(state.enabled)
        #expect(state.message?.contains("/Applications") == true)
        #expect(!state.needsApproval)
    }

    @Test("Onay gerekiyorsa kapalı sayılır ve ayarlara yönlendirir")
    func requiresApproval() {
        let state = LaunchAtLogin.state(for: .requiresApproval, bundlePath: "/Applications/Nabız.app")
        #expect(!state.enabled)
        #expect(state.needsApproval)
        #expect(state.message?.contains("Giriş Öğeleri") == true)
    }

    @Test("Kayıtlı değil: kapalı, mesaj yok")
    func notRegistered() {
        #expect(LaunchAtLogin.state(for: .notRegistered, bundlePath: "/Applications/Nabız.app")
            == .init(enabled: false, message: nil, needsApproval: false))
        #expect(LaunchAtLogin.state(for: .notFound, bundlePath: "/Applications/Nabız.app").enabled == false)
    }

    @Test("Kullanıcının Uygulamalar klasörü de kabul edilir")
    func userApplications() {
        #expect(LaunchAtLogin.isInApplicationsFolder(NSHomeDirectory() + "/Applications/Nabız.app"))
        #expect(!LaunchAtLogin.isInApplicationsFolder("/tmp/Nabız.app"))
        #expect(!LaunchAtLogin.isInApplicationsFolder("/ApplicationsX/Nabız.app"))
    }
}
