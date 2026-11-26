import Charts
import SwiftUI

/// Courbe d’un métal dans le widget, comme le site (gold-chart.js) : repère du début de période,
/// surface, courbe et dernier cours ; plus haut et plus bas écrits dans les coins.
struct CourseChart: View {
    let points: [PricePoint]
    let color: Color
    var showLabels = true
    var period: Period = .day

    private var prices: [Double] { points.map(\.price) }
    private var low: Double { prices.min() ?? 0 }
    private var high: Double { prices.max() ?? 1 }
    private var pad: Double { max((high - low) * 0.12, 1) }
    private var bottom: Double { low - pad }

    var body: some View {
        Chart {
            baseLine
            curve
            lastPoint
        }
        .chartYScale(domain: bottom...(high + pad))
        .chartXScale(domain: (points.first?.date ?? Date())...(points.last?.date ?? Date()))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .overlay(alignment: .topTrailing) {
            if showLabels, points.count > 1 { corner("▲ " + Fmt.euros(high)) }
        }
        .overlay(alignment: .bottomTrailing) {
            if showLabels, points.count > 1 { corner("▼ " + Fmt.euros(low)) }
        }
        .accessibilityElement()
        .accessibilityLabel("Courbe sur " + period.label)
        .accessibilityValue(points.last.map { "Dernier cours " + Fmt.euros($0.price) } ?? "")
    }

    private func corner(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
    }

    private var fill: LinearGradient {
        LinearGradient(stops: [.init(color: color.opacity(0.34), location: 0),
                               .init(color: color.opacity(0.07), location: 0.6),
                               .init(color: color.opacity(0), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    @ChartContentBuilder
    private var baseLine: some ChartContent {
        if let first = points.first {
            RuleMark(y: .value("Début", first.price))
                .foregroundStyle(Theme.muted.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
        }
    }

    private var curve: some ChartContent {
        ForEach(points, id: \.date) { p in
            AreaMark(x: .value("Moment", p.date), yStart: .value("Bas", bottom), yEnd: .value("Cours", p.price),
                     series: .value("Série", "surface"))
                .foregroundStyle(fill)
            LineMark(x: .value("Moment", p.date), y: .value("Cours", p.price), series: .value("Série", "cours"))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    @ChartContentBuilder
    private var lastPoint: some ChartContent {
        if let last = points.last {
            PointMark(x: .value("Moment", last.date), y: .value("Cours", last.price))
                .foregroundStyle(color)
                .symbolSize(40)
        }
    }
}
