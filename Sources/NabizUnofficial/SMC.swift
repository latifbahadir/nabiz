import Foundation
import IOKit

/// `AppleSMC` kullanıcı istemcisinin alışveriş yapısı (C'deki `SMCKeyData_t`, 80 bayt).
///
/// Belgelenmemiştir; düzen yıllardır aynı olsa da yanlış boyut sürücüye bozuk istek gönderir.
/// Bu yüzden `SMCClient` açılmadan önce `isLayoutValid` denetlenir (birim testi de denetler).
struct SMCParam {
    struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        // C yapısının hizalama dolgusu. Swift bir sonraki alanı kuyruk dolgusuna
        // yerleştirmesin diye açıkça yazılır (yoksa yapı 76 bayt olur).
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    var key: UInt32 = 0
    var version: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var powerLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var command: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    static var isLayoutValid: Bool {
        MemoryLayout<SMCParam>.size == 80
            && MemoryLayout<SMCParam>.offset(of: \.keyInfo) == 28
            && MemoryLayout<SMCParam>.offset(of: \.result) == 40
            && MemoryLayout<SMCParam>.offset(of: \.command) == 42
            && MemoryLayout<SMCParam>.offset(of: \.data32) == 44
            && MemoryLayout<SMCParam>.offset(of: \.bytes) == 48
    }
}

/// Dört karakterlik SMC anahtarı/tipi (ör. `Tp01`, `flt `).
public struct FourCC: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return nil }
        rawValue = bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    public var description: String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: rawValue >> $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func < (a: FourCC, b: FourCC) -> Bool { a.description < b.description }
}

/// Ham SMC değeri ve tipine göre çözümü.
public struct SMCValue: Sendable, Equatable {
    public let type: FourCC
    public let bytes: [UInt8]

    public init(type: FourCC, bytes: [UInt8]) {
        self.type = type
        self.bytes = bytes
    }

    /// Sayısal değer; tip bilinmiyorsa ya da boyut tutmuyorsa `nil`.
    public var number: Double? {
        func unsigned() -> UInt64 { bytes.reduce(0) { $0 << 8 | UInt64($1) } } // büyük endian
        switch (type.description, bytes.count) {
        case ("flt ", 4):
            // Apple Silicon SMC'si kayan noktayı küçük endian yazar.
            let bits = bytes.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case ("ui8 ", 1), ("ui16", 2), ("ui32", 4):
            return Double(unsigned())
        case ("si8 ", 1):
            return Double(Int8(bitPattern: bytes[0]))
        case ("si16", 2):
            return Double(Int16(bitPattern: UInt16(unsigned())))
        case ("si32", 4):
            return Double(Int32(bitPattern: UInt32(unsigned())))
        case ("sp78", 2):
            return Double(Int16(bitPattern: UInt16(unsigned()))) / 256
        case ("fpe2", 2):
            return Double(unsigned()) / 4
        case ("flag", 1):
            return Double(bytes[0])
        default:
            return nil
        }
    }

    /// Doğrulama ekranı için ham baytlar (onaltılık).
    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }
}

/// `AppleSMC` üzerinden yalnızca okuma yapan istemci. Yazma komutu (6) hiç gönderilmez.
///
/// İş parçacığı güvenli değildir; tek bir seri kuyruktan kullanılmalıdır.
public final class SMCClient {
    private enum Command: UInt8 {
        case readBytes = 5
        case keyFromIndex = 8
        case keyInfo = 9
    }

    /// `kSMCHandleYPCEvent`
    private static let selector: UInt32 = 2

    private var connection: io_connect_t = 0
    private var infoCache: [FourCC: (size: UInt32, type: FourCC)] = [:]

    public init() throws {
        guard SMCParam.isLayoutValid else {
            throw UnofficialError("SMC yapı düzeni beklenen 80 bayt değil (\(MemoryLayout<SMCParam>.size))")
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw UnofficialError("AppleSMC servisi bulunamadı") }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == KERN_SUCCESS else {
            throw UnofficialError("AppleSMC açılamadı (\(String(format: "0x%08x", result)))")
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// SMC'deki anahtar sayısı (`#KEY`).
    public func keyCount() throws -> Int {
        let value = try read(FourCC("#KEY")!)
        guard let count = value.number, count >= 0 else { throw UnofficialError("#KEY çözülemedi") }
        return Int(count)
    }

    public func key(at index: Int) throws -> FourCC {
        var input = SMCParam()
        input.command = Command.keyFromIndex.rawValue
        input.data32 = UInt32(index)
        return FourCC(rawValue: try call(input).key)
    }

    public func read(_ key: FourCC) throws -> SMCValue {
        let info = try self.info(key)
        var input = SMCParam()
        input.key = key.rawValue
        input.keyInfo.dataSize = info.size
        input.command = Command.readBytes.rawValue
        let output = try call(input)
        let count = min(Int(info.size), 32)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(count)) }
        return SMCValue(type: info.type, bytes: bytes)
    }

    /// Anahtarın tipi ve boyutu (önbellekte tutulur).
    public func type(of key: FourCC) throws -> FourCC { try info(key).type }

    private func info(_ key: FourCC) throws -> (size: UInt32, type: FourCC) {
        if let cached = infoCache[key] { return cached }
        var input = SMCParam()
        input.key = key.rawValue
        input.command = Command.keyInfo.rawValue
        let output = try call(input)
        let info = (size: output.keyInfo.dataSize, type: FourCC(rawValue: output.keyInfo.dataType))
        infoCache[key] = info
        return info
    }

    private func call(_ input: SMCParam) throws -> SMCParam {
        var input = input
        var output = SMCParam()
        var outputSize = MemoryLayout<SMCParam>.size
        let result = IOConnectCallStructMethod(
            connection, Self.selector, &input, MemoryLayout<SMCParam>.size, &output, &outputSize
        )
        guard result == KERN_SUCCESS else {
            throw UnofficialError("SMC çağrısı başarısız (\(String(format: "0x%08x", result)))")
        }
        guard output.result == 0 else {
            throw UnofficialError("SMC \(FourCC(rawValue: input.key)) okunamadı (kod \(output.result))")
        }
        return output
    }
}
