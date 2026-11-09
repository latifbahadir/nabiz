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
        VStack(alignment: .leading, spacing: 14) {
            selfUsage
            Divider()
            cpu
            Divider()
            memory
        }
        .font(.caption)
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
