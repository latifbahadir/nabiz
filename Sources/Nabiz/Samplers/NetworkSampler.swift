import Darwin
import Foundation
import SystemConfiguration

struct NetworkSnapshot: Sendable {
    /// read = alınan (indirme), written = gönderilen (yükleme)
    let rate: RateSnapshot
    var download: Double { rate.readRate }
    var upload: Double { rate.writeRate }
    /// Sayılan arayüzlerin birikimli sayaçları (doğrulama için).
    let counters: [String: ByteCounters]
}

/// `sysctl(NET_RT_IFLIST2)` ile arayüz başına 64 bit bayt sayaçlarını okur
/// (`netstat -ib` ile aynı kaynak). `getifaddrs` 32 bit sayaç verdiği için kullanılmaz.
///
/// Yalnızca fiziksel arayüzler sayılır: `en*` (Wi‑Fi, Ethernet) ve `pdp_ip*` (hücresel).
/// VPN tünelleri (`utun*`) hariçtir; aynı trafik `en*` üzerinden zaten geçtiği için çift sayılırdı.
final class NetworkSampler {
    private var previous: (uptime: TimeInterval, counters: [String: ByteCounters])?
    /// Arayüz numarası → ad. `if_indextoname` içeride `getifaddrs` çağırdığı için pahalıdır;
    /// ad yalnızca yeni bir numara görüldüğünde çözülür. Numaralar yeniden kullanılabildiği için
    /// önbellek ~5 dakikada bir boşaltılır.
    private var names: [UInt16: String] = [:]
    private var samplesSinceNameFlush = 0
    private lazy var store = SCDynamicStoreCreate(nil, "Nabiz" as CFString, nil, nil)

    func sample() -> NetworkSnapshot? {
        let now = ProcessInfo.processInfo.systemUptime
        samplesSinceNameFlush += 1
        if samplesSinceNameFlush >= 150 {
            samplesSinceNameFlush = 0
            names.removeAll(keepingCapacity: true)
        }
        guard let current = readCounters() else { return nil }
        defer { previous = (now, current) }
        guard let previous, now > previous.uptime else { return nil }
        return NetworkSnapshot(
            rate: RateSnapshot(
                delta: ByteCounters.delta(previous: previous.counters, current: current),
                interval: now - previous.uptime
            ),
            counters: current
        )
    }

    /// Varsayılan rotanın arayüzü (ör. `en0`). Yalnızca panel açıkken çağrılır.
    func primaryInterface() -> String? {
        guard
            let store,
            let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return value["PrimaryInterface"] as? String
    }

    static func isCounted(_ name: String) -> Bool {
        name.hasPrefix("en") || name.hasPrefix("pdp_ip")
    }

    func readCounters() -> [String: ByteCounters]? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return nil }

        var result: [String: ByteCounters] = [:]
        var nameBuffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let name = name(for: message.ifm_index, buffer: &nameBuffer) {
                        if Self.isCounted(name) {
                            result[name] = ByteCounters(
                                read: message.ifm_data.ifi_ibytes,
                                written: message.ifm_data.ifi_obytes
                            )
                        }
                    }
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return result
    }

    private func name(for index: UInt16, buffer: inout [CChar]) -> String? {
        if let cached = names[index] { return cached }
        guard let pointer = if_indextoname(UInt32(index), &buffer) else { return nil }
        let name = String(cString: pointer)
        names[index] = name
        return name
    }
}
