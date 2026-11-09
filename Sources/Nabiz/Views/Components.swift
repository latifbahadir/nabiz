import Charts
import SwiftUI

struct RangePicker: View {
    @Bindable var model: PanelModel

    var body: some View {
        HStack {
            Text("Geçmiş").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Picker("Geçmiş", selection: $model.range) {
                ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 170)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let symbol: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol).font(.headline)
            Spacer()
            Text(value ?? "—").font(.title3.monospacedDigit().weight(.semibold))
        }
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct LegendValue: View {
    let color: Color
    let label: String
    let value: UInt64

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Text(Fmt.bytes(value)).monospacedDigit()
        }
        .font(.caption)
    }
}

struct HistoryChart: View {
    let points: [ChartPoint]
    let range: HistoryRange
    let tint: Color

    var body: some View {
        let now = Date()
        Chart(points) { point in
            AreaMark(x: .value("Zaman", point.date), y: .value("Değer", point.value))
                .foregroundStyle(tint.opacity(0.2))
            LineMark(x: .value("Zaman", point.date), y: .value("Değer", point.value))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
        }
        .chartXScale(domain: now.addingTimeInterval(-range.rawValue)...now)
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Fmt.percent(v)) }
                }
            }
        }
        .frame(height: 64)
    }
}

/// Hız grafiği (ör. indirme/yükleme); y ekseni verinin en büyük değerine göre ölçeklenir.
struct RateChart: View {
    struct Series {
        let label: String
        let color: Color
        let points: [ChartPoint]
    }

    let series: [Series]
    let range: HistoryRange

    var body: some View {
        let now = Date()
        let peak = max(series.flatMap(\.points).map(\.value).max() ?? 0, 1000)
        Chart {
            ForEach(series.indices, id: \.self) { i in
                ForEach(series[i].points) { point in
                    LineMark(
                        x: .value("Zaman", point.date),
                        y: .value("Hız", point.value),
                        series: .value("Seri", series[i].label)
                    )
                    .foregroundStyle(series[i].color)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
        }
        .chartXScale(domain: now.addingTimeInterval(-range.rawValue)...now)
        .chartYScale(domain: 0...(peak * 1.1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, peak]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(Fmt.rate(v)) }
                }
            }
        }
        .frame(height: 64)
    }
}

/// Doluluk çubuğu.
struct FillBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                Rectangle().fill(color).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }
}

/// Etiket–değer satırı (Grid içinde).
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}
