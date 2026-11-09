import AppKit
import NabizUnofficial
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
                gpu
                Divider()
                temperature
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

    // MARK: GPU

    private var gpu: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("GPU — ham değerler", systemImage: "square.stack.3d.up").font(.headline)
            Text("Kaynak: IOKit \(model.gpuSourceTitle) (belgelenmemiş anahtarlar). Sürücü değeri bir önceki okumadan bu yana geçen süre için hesaplar; Nabız her \(Int(model.interval)) sn'de bir okur.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Anlamı: GPU donanımının aktif kaldığı süre (powermetrics “GPU HW active residency” ile aynı eğilim). Uygulamaların GPU'da iş yaptığı süreden yüksek olabilir: kısa iş patlamalarından sonra GPU bir süre aktif kalır.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                UnofficialStatusLabel(status: model.gpuStatus)
                if case .unavailable(let reason) = model.gpuStatus, reason.contains("önceki çalıştırmada") {
                    Button("Yeniden dene") { monitor.retryGPU() }.controlSize(.mini)
                }
            }
            if let info = model.gpuInfo {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    InfoRow("Model", info.model ?? "—")
                    InfoRow("Çekirdek (gpu-core-count)", info.coreCount.map(String.init) ?? "—")
                    InfoRow("Sürücü sınıfı", info.ioClass ?? "—")
                }
            }
            if let gpu = model.gpu {
                if gpu.raw.isEmpty {
                    Text("Ham değerler bir sonraki ölçümde gelecek…").foregroundStyle(.secondary)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                        ForEach(gpu.raw, id: \.self) { item in
                            InfoRow(item.key, item.value)
                        }
                    }
                }
                Text("Kullanım = “\(GPUSnapshot.deviceKey)” / 100 = \(Fmt.percent(gpu.device))")
                    .monospacedDigit()
            }
            CommandRow(
                note: "Aynı sözlük. Dikkat: pencere tüm okuyucular için ortaktır; ioreg okuyunca Nabız'ın bir sonraki değeri yalnızca aradaki kısa süreyi kapsar:",
                command: #"ioreg -rc IOAccelerator -d1 | grep PerformanceStatistics"#
            )
            CommandRow(
                note: "Bağımsız karşılaştırma (yönetici parolası ister; “GPU HW active residency” satırı; M5 Pro'da sürücü değeri genelde 0–12 puan yukarıda):",
                command: "sudo powermetrics --samplers gpu_power -i 2000 -n 3"
            )
            Text("Activity Monitor → Pencere → GPU Geçmişi de aynı eğilimi göstermelidir.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Sıcaklık

    private var temperature: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sıcaklık — ham değerler", systemImage: "thermometer.medium").font(.headline)
            Text("Kaynak: AppleSMC (belgelenmemiş anahtarlar, yalnızca okuma). CPU = Tp*, GPU = Tg* anahtarları; eşleme yük testiyle doğrulandı (CPU yükünde Tp, GPU yükünde Tg en çok yükselir). Yalnızca panel açıkken, \(model.temperatureInterval) sn'de bir okunur.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                UnofficialStatusLabel(status: model.temperatureStatus)
                if case .unavailable(let reason) = model.temperatureStatus, reason.contains("önceki çalıştırmada") {
                    Button("Yeniden dene") { monitor.retryTemperature() }.controlSize(.mini)
                }
            }
            if let t = model.temperature {
                let cpu = t.readings.filter { $0.key.hasPrefix(TemperatureKeys.cpuPrefix) }
                let gpu = t.readings.filter { $0.key.hasPrefix(TemperatureKeys.gpuPrefix) }
                let other = t.readings.filter { !$0.key.hasPrefix(TemperatureKeys.cpuPrefix) && !$0.key.hasPrefix(TemperatureKeys.gpuPrefix) }
                Text("Ortalama / en yüksek = geçerli değerlerin (0 < °C < 150) ortalaması / en büyüğü\nCPU: \(statsText(t.cpu)) · GPU: \(statsText(t.gpu))")
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("CPU anahtarları (Tp*, \(cpu.count))") { smcTable(cpu) }
                DisclosureGroup("GPU anahtarları (Tg*, \(gpu.count))") { smcTable(gpu) }
                if t.includesAll {
                    DisclosureGroup("Diğer T* anahtarları (\(other.count); anlamları belgelenmemiş, gösterime katılmaz)") { smcTable(other) }
                }
            }

            Divider().padding(.vertical, 2)
            Text("Çapraz kontrol: bağımsız ikinci kaynak IOHIDEventSystemClient (özel API). M5 Pro'da küme adı vermez (PMU tdie*); değerler Tp*/Tg* ile aynı aralıkta olmalıdır. Pahalıdır (~0,1 sn), yalnızca istenince okunur.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("HID sensörlerini oku") { monitor.readHIDTemperatures() }.controlSize(.small)
                if model.hidStatus != .unknown { UnofficialStatusLabel(status: model.hidStatus) }
            }
            if let hid = model.hidTemperatures {
                let valid = hid.filter { TemperatureSnapshot.isPlausible($0.celsius) }
                let dies = valid.filter { $0.name.hasPrefix("PMU tdie") }
                Text("PMU tdie*: \(statsText(TemperatureSnapshot.stats(dies.map(\.celsius)))) · \(hid.count) servis, \(hid.count - valid.count) geçersiz değer (ör. PMU tdev ≈ −9201)")
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("HID servisleri (\(hid.count))") {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                        ForEach(Array(hid.sorted { $0.name < $1.name }.enumerated()), id: \.offset) { _, reading in
                            InfoRow(reading.name, Fmt.celsius(reading.celsius, digits: 2))
                        }
                    }
                }
            }
        }
    }

    private func smcTable(_ readings: [SMCReading]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
            ForEach(readings, id: \.self) { r in
                GridRow {
                    Text(r.key).font(.caption.monospaced())
                    Text("\(r.type) \(r.hex)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(r.celsius.map { Fmt.celsius($0, digits: 2) } ?? "—").monospacedDigit()
                }
            }
        }
    }

    private func statsText(_ stats: TemperatureStats?) -> String {
        stats.map { "\(Fmt.celsius($0.average)) / \(Fmt.celsius($0.maximum)) (\($0.count))" } ?? "—"
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

/// Resmi olmayan bir kaynağın durumu (ADR 0003).
private struct UnofficialStatusLabel: View {
    let status: UnofficialStatus

    var body: some View {
        let (symbol, color): (String, Color) = switch status {
        case .available: ("checkmark.circle.fill", .green)
        case .unavailable: ("xmark.octagon.fill", .red)
        case .unknown: ("clock", .secondary)
        }
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text("Resmi olmayan kaynak · \(status.label)")
                .fixedSize(horizontal: false, vertical: true)
        }
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
