import Charts
import SwiftUI

/// Courbe d’un métal, comme le site (gold-chart.js) : repère du début de période, surface,
/// courbe, dernier cours, plus haut et plus bas ; bande de Bollinger au choix. Dans l’application :
/// échelle des prix, dates, et lecture du cours au doigt. Dans le widget : la courbe seule.
struct CourseChart: View {
    let points: [PricePoint]
    let color: Color
    var showLabels = true
    var interactive = false
    var period: Period = .day
    var band: [BandPoint] = []

    @State private var selected: Date?

    private var prices: [Double] { points.map(\.price) }
    private var low: Double { min(prices.min() ?? 0, band.map(\.low).min() ?? .infinity) }
    private var high: Double { max(prices.max() ?? 1, band.map(\.up).max() ?? -.infinity) }
    private var pad: Double { max((high - low) * 0.12, 1) }
    private var bottom: Double { low - pad }

    private var selectedPoint: PricePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
    private var highPoint: PricePoint? { points.max { $0.price < $1.price } }
    private var lowPoint: PricePoint? { points.min { $0.price < $1.price } }

    var body: some View {
        Chart {
            baseLine
            bandMarks
            curve
            extremes
            lastPoint
            selectionMarks
        }
        .chartYScale(domain: bottom...(high + pad))
        .chartXScale(domain: (points.first?.date ?? Date())...(points.last?.date ?? Date()))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    Text(value.as(Date.self).map(axisLabel) ?? "").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
        }
        .chartXAxis(interactive ? .visible : .hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [2, 5])).foregroundStyle(Theme.line)
                AxisValueLabel {
                    Text(value.as(Double.self).map { Fmt.decimal($0) } ?? "").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
        }
        .chartYAxis(interactive ? .visible : .hidden)
        .modifier(Selection(enabled: interactive, selected: $selected))
        .overlay(alignment: .topTrailing) {
            if showLabels, !interactive, points.count > 1 {
                Text("▲ " + Fmt.euros(prices.max() ?? 0)).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showLabels, !interactive, points.count > 1 {
                Text("▼ " + Fmt.euros(prices.min() ?? 0)).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Courbe sur " + period.label)
        .accessibilityValue(lastLabel)
    }

    // MARK: - Tracés

    private var lastLabel: String {
        guard let last = points.last else { return "" }
        return "Dernier cours " + Fmt.euros(last.price)
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

    private var bandMarks: some ChartContent {
        ForEach(band, id: \.date) { b in
            AreaMark(x: .value("Moment", b.date), yStart: .value("Bas", b.low), yEnd: .value("Haut", b.up),
                     series: .value("Série", "bande"))
                .foregroundStyle(Theme.band.opacity(0.1))
            LineMark(x: .value("Moment", b.date), y: .value("Cours", b.up), series: .value("Série", "haute"))
                .foregroundStyle(Theme.band.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1))
            LineMark(x: .value("Moment", b.date), y: .value("Cours", b.low), series: .value("Série", "basse"))
                .foregroundStyle(Theme.band.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1))
            LineMark(x: .value("Moment", b.date), y: .value("Cours", b.mid), series: .value("Série", "moyenne"))
                .foregroundStyle(Theme.band.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
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

    /// Plus haut et plus bas sur la courbe (application seulement).
    @ChartContentBuilder
    private var extremes: some ChartContent {
        if interactive, selectedPoint == nil, let hp = highPoint, let lp = lowPoint, hp.price != lp.price {
            PointMark(x: .value("Moment", hp.date), y: .value("Cours", hp.price))
                .foregroundStyle(color)
                .symbolSize(22)
                .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    extremeLabel("▲ " + Fmt.decimal(hp.price))
                }
            PointMark(x: .value("Moment", lp.date), y: .value("Cours", lp.price))
                .foregroundStyle(color)
                .symbolSize(22)
                .annotation(position: .bottom, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    extremeLabel("▼ " + Fmt.decimal(lp.price))
                }
        }
    }

    private func extremeLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.text)
    }

    @ChartContentBuilder
    private var lastPoint: some ChartContent {
        if let last = points.last, selectedPoint == nil {
            PointMark(x: .value("Moment", last.date), y: .value("Cours", last.price))
                .foregroundStyle(color)
                .symbolSize(40)
        }
    }

    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let p = selectedPoint {
            RuleMark(x: .value("Moment", p.date))
                .foregroundStyle(Theme.muted.opacity(0.6))
                .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    bubble(p)
                }
            PointMark(x: .value("Moment", p.date), y: .value("Cours", p.price))
                .foregroundStyle(color)
                .symbolSize(50)
        }
    }

    private func bubble(_ p: PricePoint) -> some View {
        VStack(spacing: 0) {
            Text(Fmt.euros(p.price, digits: 2)).font(.caption.bold()).foregroundStyle(Theme.text)
            Text(label(p.date)).font(.caption2).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Theme.bg2.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Libellés

    private func axisLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Fmt.fr
        f.timeZone = Fmt.paris
        switch period {
        case .day: f.dateFormat = "HH:mm"
        case .fiveYears, .tenYears: f.dateFormat = "MMM yy"
        default: f.dateFormat = "d MMM"
        }
        return f.string(from: d)
    }

    private func label(_ d: Date) -> String {
        period == .day ? Fmt.time(d) : Fmt.dayTime(d)
    }
}

/// Lecture au doigt, seulement dans l’application (pas dans le widget).
private struct Selection: ViewModifier {
    let enabled: Bool
    @Binding var selected: Date?

    func body(content: Content) -> some View {
        if enabled {
            content.chartXSelection(value: $selected)
        } else {
            content
        }
    }
}
