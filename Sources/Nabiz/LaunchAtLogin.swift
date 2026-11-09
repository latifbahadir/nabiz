import Foundation
import ServiceManagement

/// Girişte otomatik başlatma: `SMAppService.mainApp` (macOS 13+).
/// Giriş öğesi, uygulamanın **şu an çalıştığı konumu** kaydeder; bu yüzden
/// Nabız `/Applications` içinden çalışmıyorsa kullanıcı uyarılır.
enum LaunchAtLogin {
    struct State: Equatable {
        let enabled: Bool
        /// Kullanıcıya gösterilecek açıklama; her şey yolundaysa nil.
        let message: String?
        /// Kullanıcının Sistem Ayarları'nda onay vermesi gerekiyor.
        let needsApproval: Bool
    }

    static func current() -> State {
        state(for: SMAppService.mainApp.status, bundlePath: Bundle.main.bundlePath)
    }

    /// Açar/kapatır ve son durumu döndürür. Hata olursa durumla birlikte açıklama verir.
    static func set(_ enabled: Bool) -> State {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return current()
        } catch {
            let base = current()
            return State(
                enabled: base.enabled,
                message: "İşlem yapılamadı: \(error.localizedDescription)",
                needsApproval: base.needsApproval
            )
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func isInApplicationsFolder(_ bundlePath: String) -> Bool {
        let applications = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        return applications.contains { bundlePath.hasPrefix($0) }
    }

    /// Saf eşleme: test edilebilir.
    static func state(for status: SMAppService.Status, bundlePath: String) -> State {
        switch status {
        case .enabled:
            let warning = isInApplicationsFolder(bundlePath)
                ? nil
                : "Nabız Uygulamalar klasörü dışından çalışıyor; giriş öğesi bu konumu açar. Önce /Applications'a kurun."
            return State(enabled: true, message: warning, needsApproval: false)
        case .requiresApproval:
            return State(
                enabled: false,
                message: "Sistem Ayarları > Genel > Giriş Öğeleri'nden Nabız'a izin verin.",
                needsApproval: true
            )
        case .notRegistered, .notFound:
            return State(enabled: false, message: nil, needsApproval: false)
        @unknown default:
            return State(enabled: false, message: nil, needsApproval: false)
        }
    }
}
