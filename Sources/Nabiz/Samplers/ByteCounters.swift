/// Birikimli bayt sayacı çifti: ağda (alınan, gönderilen), diskte (okunan, yazılan).
struct ByteCounters: Sendable, Equatable {
    var read: UInt64 = 0
    var written: UInt64 = 0

    /// Yalnızca iki okumada da bulunan anahtarların farkını toplar.
    /// Bir sayaç geri gitmişse (arayüz/disk sıfırlandı) o anahtarın o yöndeki farkı 0 sayılır;
    /// yeni eklenen disk/arayüz ilk okumada sıçrama yaratmaz.
    static func delta<Key: Hashable>(previous: [Key: ByteCounters], current: [Key: ByteCounters]) -> ByteCounters {
        var sum = ByteCounters()
        for (key, now) in current {
            guard let before = previous[key] else { continue }
            if now.read >= before.read { sum.read += now.read - before.read }
            if now.written >= before.written { sum.written += now.written - before.written }
        }
        return sum
    }
}

/// İki okuma arasındaki hız.
struct RateSnapshot: Sendable {
    let delta: ByteCounters
    let interval: Double
    var readRate: Double { interval > 0 ? Double(delta.read) / interval : 0 }
    var writeRate: Double { interval > 0 ? Double(delta.written) / interval : 0 }
}
