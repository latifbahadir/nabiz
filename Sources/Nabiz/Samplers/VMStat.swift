import Foundation

/// `/usr/bin/vm_stat` çıktısını okur; Nabız'ın değerleriyle karşılaştırmak için.
/// Yalnızca kullanıcı düğmeye bastığında çalışır.
enum VMStat {
    static func run() async -> [String: UInt64]? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/vm_stat")
            let pipe = Pipe()
            process.standardOutput = pipe
            do { try process.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return parse(String(decoding: data, as: UTF8.self))
        }.value
    }

    static func parse(_ output: String) -> [String: UInt64] {
        var values: [String: UInt64] = [:]
        for line in output.split(separator: "\n") {
            guard let colon = line.lastIndex(of: ":") else { continue }
            let key = line[..<colon]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
            if let number = UInt64(value) { values[key] = number }
        }
        return values
    }

    /// (vm_stat anahtarı, Türkçe etiket, Nabız'daki karşılığı)
    static let fields: [(key: String, label: String, value: KeyPath<RawVMStats, UInt64>)] = [
        ("Pages free", "Boş", \.free),
        ("Pages active", "Aktif", \.active),
        ("Pages inactive", "İnaktif", \.inactive),
        ("Pages speculative", "Spekülatif", \.speculative),
        ("Pages throttled", "Kısıtlı", \.throttled),
        ("Pages wired down", "Sabit (wired)", \.wired),
        ("Pages purgeable", "Temizlenebilir", \.purgeable),
        ("File-backed pages", "Dosya destekli", \.fileBacked),
        ("Anonymous pages", "Anonim", \.anonymous),
        ("Pages occupied by compressor", "Sıkıştırıcıda", \.compressor),
    ]
}
