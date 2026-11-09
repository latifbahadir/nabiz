import Darwin

/// Resmi olmayan bir kaynağa erişilemediğinde nedeni.
public struct UnofficialError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Özel sembolleri çalışma zamanında `dlopen` + `dlsym` ile çözer.
///
/// Bağlayıcı bu sembolleri hiç görmez: macOS bir sürümde sembolü kaldırırsa uygulama
/// açılışta çökmez, yalnızca ilgili özellik "okunamadı" olur.
public enum PrivateSymbol {
    /// - Parameters:
    ///   - name: C sembol adı (ör. `IOHIDEventSystemClientCreate`).
    ///   - image: Kütüphane yolu (ör. `/System/Library/Frameworks/IOKit.framework/IOKit`).
    ///   - type: `@convention(c)` işlev tipi. İmzanın doğruluğu çağıranın sorumluluğundadır;
    ///     burada yalnızca boyutun bir işlev göstericisiyle aynı olduğu denetlenir.
    public static func resolve<T>(_ name: String, in image: String, as type: T.Type) throws -> T {
        guard MemoryLayout<T>.size == MemoryLayout<UnsafeRawPointer>.size else {
            throw UnofficialError("\(name): \(T.self) bir C işlev göstericisi değil")
        }
        guard let handle = dlopen(image, RTLD_LAZY | RTLD_LOCAL) else {
            throw UnofficialError("\(image) yüklenemedi: \(lastError())")
        }
        // Sistem çerçeveleri süreç boyunca yüklü kalır; tutamaç bilerek kapatılmaz.
        guard let pointer = dlsym(handle, name) else {
            throw UnofficialError("\(name) sembolü bulunamadı")
        }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static func lastError() -> String {
        dlerror().map { String(cString: $0) } ?? "bilinmeyen hata"
    }
}
