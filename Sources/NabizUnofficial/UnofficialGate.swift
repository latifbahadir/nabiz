import Foundation

/// Bir resmi olmayan kaynağın kullanıcıya gösterilen durumu.
public enum UnofficialStatus: Equatable, Sendable {
    /// Henüz okunmadı.
    case unknown
    case available
    case unavailable(String)

    public var label: String {
        switch self {
        case .unknown: "henüz okunmadı"
        case .available: "kullanılabilir"
        case .unavailable(let reason): "okunamadı: \(reason)"
        }
    }
}

/// Kullanıcının tüm resmi olmayan kaynakları kapatma anahtarı.
public enum UnofficialSettings {
    public static let environmentKey = "NABIZ_DISABLE_UNOFFICIAL"
    public static let defaultsKey = "DisableUnofficialAPIs"

    /// `NABIZ_DISABLE_UNOFFICIAL=1` ya da
    /// `defaults write com.latifbahadir.nabiz DisableUnofficialAPIs -bool YES`.
    public static func disabledByUser(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> Bool {
        environment[environmentKey] == "1" || defaults.bool(forKey: defaultsKey)
    }
}

/// Bir resmi olmayan kaynağa erişimin tek kapısı.
///
/// - Kullanıcı kapattıysa ya da önceki çalıştırmada ilk çağrıda çökülmüşse kapı kapalıdır:
///   `call` gövdeyi hiç çalıştırmaz.
/// - İlk çağrı `CrashGuard` ile korunur; sonraki çağrılar ek maliyet getirmez.
/// - Örnekleyici okuma sonucunu `report` ile bildirir; Doğrulama ekranı `status`'u gösterir.
///
/// İş parçacığı güvenli değildir; her örnekleyici kendi kapısını tek bir iş parçacığından kullanır.
public final class UnofficialGate {
    public let id: String
    /// Kullanıcıya gösterilen kaynak adı (ör. "IOAccelerator PerformanceStatistics").
    public let title: String
    public private(set) var status: UnofficialStatus = .unknown
    /// Kapı kapalıysa nedeni.
    public private(set) var blockReason: String?

    private let crashGuard: CrashGuard
    private var firstCallDone = false

    public init(
        id: String,
        title: String,
        crashGuard: CrashGuard = .standard,
        disabledByUser: Bool = UnofficialSettings.disabledByUser()
    ) {
        self.id = id
        self.title = title
        self.crashGuard = crashGuard
        if disabledByUser {
            blockReason = "resmi olmayan kaynaklar kullanıcı tarafından kapatıldı (\(UnofficialSettings.defaultsKey))"
        } else if crashGuard.crashedPreviously(id) {
            blockReason = "önceki çalıştırmada bu kaynak okunurken uygulama kapandı; bu macOS/Nabız sürümünde devre dışı"
        }
        if let blockReason { status = .unavailable(blockReason) }
    }

    public var isOpen: Bool { blockReason == nil }

    /// Kapı açıksa gövdeyi çalıştırır, kapalıysa `nil` döner.
    public func call<T>(_ body: () throws -> T?) rethrows -> T? {
        guard isOpen else { return nil }
        if firstCallDone { return try body() }
        crashGuard.begin(id)
        defer {
            crashGuard.end(id)
            firstCallDone = true
        }
        return try body()
    }

    /// Okuma sonucunu kaydeder. Kapı kapalıyken kapanma nedeni korunur.
    public func report(_ status: UnofficialStatus) {
        guard isOpen else { return }
        self.status = status
    }

    /// Çökme nedeniyle kapanan kaynağı yeniden dener (kullanıcı kapatmasını geçersiz kılmaz).
    public func retryAfterCrash(disabledByUser: Bool = UnofficialSettings.disabledByUser()) {
        guard !disabledByUser else { return }
        crashGuard.end(id)
        blockReason = nil
        firstCallDone = false
        status = .unknown
    }
}
