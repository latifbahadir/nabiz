import Foundation

/// Bir resmi olmayan kaynağın ilk çağrısının sürecin çökmesine yol açıp açmadığını hatırlar.
///
/// İlk çağrıdan önce diske bir işaret dosyası yazılır, çağrı dönünce silinir. Süreç o arada
/// çökerse işaret kalır ve sonraki açılışta kaynak devre dışı başlar; böylece girişte başlayan
/// uygulama çökme döngüsüne girmez. İşaret, yazıldığı macOS derlemesi ve Nabız sürümünü taşır:
/// bunlardan biri değişince kaynak yeniden denenir.
public struct CrashGuard: Sendable {
    public let directory: URL
    /// macOS derlemesi + uygulama sürümü.
    public let fingerprint: String

    public init(directory: URL, fingerprint: String) {
        self.directory = directory
        self.fingerprint = fingerprint
    }

    public static let standard = CrashGuard(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nabiz/crash-guard", isDirectory: true),
        fingerprint: currentFingerprint()
    )

    public static func currentFingerprint() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "geliştirme"
        return "\(os) · Nabız \(app)"
    }

    /// Önceki bir çalıştırmada aynı derleme ve sürümle bu kaynağın ilk çağrısında çökülmüş mü?
    /// Parmak izi farklı olan eski işaret silinir.
    public func crashedPreviously(_ id: String) -> Bool {
        let url = marker(id)
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return false }
        if content == fingerprint { return true }
        try? FileManager.default.removeItem(at: url)
        return false
    }

    public func begin(_ id: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fingerprint.write(to: marker(id), atomically: true, encoding: .utf8)
    }

    public func end(_ id: String) {
        try? FileManager.default.removeItem(at: marker(id))
    }

    private func marker(_ id: String) -> URL {
        directory.appendingPathComponent("\(id).inflight")
    }
}
