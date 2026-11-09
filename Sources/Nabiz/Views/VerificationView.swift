import AppKit
import SwiftUI

/// Nabız'ın değerlerinin nereden geldiğini ve nasıl hesaplandığını gösterir;
/// sistem araçlarıyla karşılaştırma imkânı verir.
struct VerificationView: View {
    let model: PanelModel
    let monitor: Monitor

    @State private var comparison: (vmStat: [String: UInt64], ours: RawVMStats)?
    @State private var comparing = false
    @State private var comparisonFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                selfUsage
                Divider()
                cpu
                Divider()
                memory
                Divider()
                network
                Divider()
                disk
                if model.hasBattery {
                    Divider()
                    battery
                }
            }
            .font(.caption)
            .padding(.trailing, 10) // kaydırma çubuğu için
        }
        .frame(height: 560)
    }

    // MARK: Ağ

    private var network: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ağ — ham değerler", systemImage: "network").font(.headline)
            Text("Kaynak: sysctl NET_RT_IFLIST2 (arayüz başına 64 bit bayt sayaçları, netstat ile aynı). Sayılan: en*, pdp_ip*. Birimler ondalıktır (1 KB = 1000 bayt).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let net = model.network {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        Text("Arayüz").gridColumnAlignment(.leading)
                        Text("Alınan (toplam)")
                        Text("Gönderilen (toplam)")
                    }
                    .foregroundStyle(.secondary)
                    ForEach(net.counters.filter { $0.value.read + $0.value.written > 0 }.sorted { $0.key < $1.key }, id: \.key) { name, counters in
                        GridRow {
                            Text(name).gridColumnAlignment(.leading)
                            Text(Fmt.integer(counters.read))
                            Text(Fmt.integer(counters.written))
                        }
                    }
                }
                .monospacedDigit()
                rateFormula(rate: net.rate, readName: "indirme", writeName: "yükleme")
            }
            CommandRow(
                note: "Karşılaştırmak için (bayt / 2 sn; ikiye bölün):",
                command: "netstat -I \(model.primaryInterface ?? "en0") -b -w 2"
            )
        }
    }

    // MARK: Disk

    private var disk: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Disk — ham değerler", systemImage: "internaldrive").font(.headline)
            Text("G/Ç kaynağı: IOKit IOBlockStorageDriver → Statistics (tüm sürücüler). Doluluk: URLResourceValues (Finder ile aynı).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let io = model.diskIO {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    InfoRow("Sürücü sayısı", String(io.driverCount))
                    InfoRow("Okunan (toplam)", Fmt.integer(io.totals.read) + " bayt")
                    InfoRow("Yazılan (toplam)", Fmt.integer(io.totals.written) + " bayt")
                }
                rateFormula(rate: io.rate, readName: "okuma", writeName: "yazma")
            }
            if let capacity = model.diskCapacity {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    InfoRow("Toplam", Fmt.integer(UInt64(capacity.total)) + " bayt")
                    InfoRow("Kullanılabilir (önemli kullanım)", Fmt.integer(UInt64(capacity.availableForImportantUsage)) + " bayt")
                    InfoRow("Boş bloklar", Fmt.integer(UInt64(capacity.availablePlain)) + " bayt")
                }
                Text("Kullanılan = toplam − kullanılabilir (temizlenebilir alan kullanılabilir sayılır; bu yüzden df'ten büyük çıkabilir).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CommandRow(note: "Karşılaştırmak için (MB/s, disk başına):", command: "iostat -d -w 2")
            CommandRow(note: "Doluluk (Avail ≈ boş bloklar):", command: "df -H /")
        }
    }

    // MARK: Pil

    private var battery: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pil — ham değerler", systemImage: "battery.100").font(.headline)
            Text("Yüzde, durum, kalan süre: IOPowerSources (pmset ile aynı). Diğerleri: IOKit AppleSmartBattery.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let b = model.battery {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    InfoRow("DesignCapacity", b.designCapacity.map { "\($0) mAh" } ?? "—")
                    InfoRow("NominalChargeCapacity", b.nominalCapacity.map { "\($0) mAh" } ?? "—")
                    InfoRow("AppleRawMaxCapacity", b.rawMaxCapacity.map { "\($0) mAh" } ?? "—")
                    InfoRow("Voltage", b.voltage.map { "\($0) mV" } ?? "—")
                    InfoRow("InstantAmperage", b.amperage.map { "\($0) mA" } ?? "—")
                    InfoRow("Temperature", b.temperature.map { "\($0) (°C × 100)" } ?? "—")
                }
                if let nominal = b.nominalCapacity, let design = b.designCapacity, let health = b.health {
                    Text("Sağlık = min(Nominal / Design, 1) = min(\(nominal) / \(design), 1) = \(Fmt.percent(health, digits: 1))")
                        .monospacedDigit()
                }
                if let v = b.voltage, let a = b.amperage, let w = b.watts {
                    Text("Güç = V × A = \(Fmt.number(Double(v) / 1000, digits: 3)) V × \(Fmt.number(Double(a) / 1000, digits: 3)) A = \(Fmt.number(w, digits: 2)) W")
                        .monospacedDigit()
                }
            }
            CommandRow(note: "Yüzde ve kalan süre:", command: "pmset -g batt")
            CommandRow(
                note: "Sağlık ve döngü (Sistem Bilgisi):",
                command: #"system_profiler SPPowerDataType | grep -E "Cycle Count|Maximum Capacity""#
            )
        }
    }

    private func rateFormula(rate: RateSnapshot, readName: String, writeName: String) -> some View {
        let seconds = Fmt.number(rate.interval, digits: 2)
        return Text("""
        Hız = Δbayt / Δt
        \(readName): \(Fmt.integer(rate.delta.read)) / \(seconds) sn = \(Fmt.rate(rate.readRate))
        \(writeName): \(Fmt.integer(rate.delta.written)) / \(seconds) sn = \(Fmt.rate(rate.writeRate))
        """)
        .monospacedDigit()
    }

    // MARK: Nabız'ın kendi tüketimi

    private var selfUsage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nabız'ın kendi tüketimi", systemImage: "leaf").font(.headline)
            if let usage = model.selfUsage {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    row("CPU (açıldığından beri ort.)", Fmt.percent(usage.averageCPU, digits: 2))
                    row("CPU (şu an, panel açık)", usage.recentCPU.map { Fmt.percent($0, digits: 2) } ?? "ölçülüyor…")
                    row("Uyanma / sn (ort.)", Fmt.number(usage.averageWakeups, digits: 1))
                    row("Bellek", Fmt.bytes(usage.footprint))
                }
                Text("CPU değeri tek çekirdeğe göredir (Activity Monitor'deki % CPU sütunu gibi). Panel kapalıyken Nabız yalnızca birkaç sistem çağrısı yapar; panel açıkken çizim nedeniyle biraz artar.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: İşlemci

    private var cpu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("İşlemci — ham değerler", systemImage: "cpu").font(.headline)
            Text("Kaynak: host_processor_info (son \(Int(model.interval)) sn'lik tick farkı, tüm çekirdekler)")
                .foregroundStyle(.secondary)
            if let cpu = model.cpu {
                let d = cpu.delta
                let total = d.user + d.system + d.nice + d.idle
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    row("user", Fmt.integer(d.user))
                    row("nice", Fmt.integer(d.nice))
                    row("system", Fmt.integer(d.system))
                    row("idle", Fmt.integer(d.idle))
                }
                Text("Kullanım = (user + nice + system) / toplam\n= \(Fmt.integer(d.user + d.nice + d.system)) / \(Fmt.integer(total)) = \(Fmt.percent(cpu.total, digits: 1))")
                    .monospacedDigit()
            }
            CommandRow(
                note: "Karşılaştırmak için (ikinci satıra bakın; ilki açılıştan beri ortalamadır):",
                command: #"top -l 2 -s 2 -n 0 | grep "CPU usage""#
            )
        }
    }

    // MARK: Bellek

    private var memory: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Bellek — vm_stat ile karşılaştırma", systemImage: "memorychip").font(.headline)
            if let m = model.memory {
                Text("Kaynak: host_statistics64 · sayfa boyutu \(Fmt.integer(m.pageSize)) bayt\nKullanılan = (anonim − temizlenebilir) + sabit + sıkıştırıcıda")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(comparing ? "Çalışıyor…" : "vm_stat ile karşılaştır") {
                    Task {
                        comparing = true
                        let result = await monitor.compareWithVMStat()
                        comparison = result
                        comparisonFailed = result == nil
                        comparing = false
                    }
                }
                .disabled(comparing)
                .controlSize(.small)
                if comparisonFailed { Text("vm_stat çalıştırılamadı").foregroundStyle(.red) }
            }

            if let comparison {
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        Text("Alan (sayfa)").gridColumnAlignment(.leading)
                        Text("Nabız")
                        Text("vm_stat")
                        Text("Fark")
                    }
                    .foregroundStyle(.secondary)
                    ForEach(VMStat.fields, id: \.key) { field in
                        let ours = comparison.ours[keyPath: field.value]
                        let theirs = comparison.vmStat[field.key]
                        GridRow {
                            Text(field.label).gridColumnAlignment(.leading)
                            Text(Fmt.integer(ours))
                            Text(theirs.map(Fmt.integer) ?? "—")
                            Text(theirs.map { diffText(ours, $0) } ?? "—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .monospacedDigit()
                Text("İki ölçüm birkaç milisaniye arayla alındığı için küçük farklar normaldir.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Yardımcılar

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }

    private func diffText(_ ours: UInt64, _ theirs: UInt64) -> String {
        let diff = Int64(bitPattern: ours) - Int64(bitPattern: theirs)
        return diff == 0 ? "0" : (diff > 0 ? "+" : "−") + Fmt.integer(UInt64(abs(diff)))
    }
}

private struct CommandRow: View {
    let note: String
    let command: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note).foregroundStyle(.secondary)
            HStack {
                Text(command)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Kopyala")
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
