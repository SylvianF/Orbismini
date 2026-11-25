import Charts
import SwiftUI

/// Or et argent sur le même dessin, chacun avec son échelle : l’or à gauche (chiffres dorés),
/// l’argent à droite (chiffres argentés). Chaque courbe est ramenée entre son plus bas et son
/// plus haut de la période : elles occupent toute la hauteur et gardent leur vraie forme.
/// Sur l’écran verrouillé (une seule couleur), l’argent est en tirets et les échelles sont cachées.
struct OverlayChart: View {
    let gold: [PricePoint]
    let silver: [PricePoint]
    var lineWidth: CGFloat = 3
    var monochrome = false
    var showScales = true

    /// Hauteurs des repères de l’échelle, entre 0 (plus bas) et 1 (plus haut).
    private static let marks: [Double] = [0, 0.5, 1]
    private static let pad = 0.1

    private struct Scale {
        let low: Double
        let high: Double
        init(_ points: [PricePoint]) {
            let prices = points.map(\.price)
            let lo = prices.min() ?? 0, hi = prices.max() ?? 1
            low = lo
            high = hi > lo ? hi : lo + 1
        }
        func y(_ price: Double) -> Double { (price - low) / (high - low) }
        func price(_ y: Double) -> Double { low + y * (high - low) }
    }

    private var g: Scale { Scale(gold) }
    private var s: Scale { Scale(silver) }
    private var start: Date { [gold.first?.date, silver.first?.date].compactMap { $0 }.min() ?? Date() }
    private var end: Date { [gold.last?.date, silver.last?.date].compactMap { $0 }.max() ?? Date() }

    var body: some View {
        Chart {
            silverLine
            goldLine
        }
        .chartXScale(domain: start...max(end, start.addingTimeInterval(60)))
        .chartYScale(domain: -Self.pad...(1 + Self.pad))
        .chartXAxis(.hidden)
        .chartYAxis(showScales && !monochrome ? .visible : .hidden)
        .chartYAxis { scales }
        .chartLegend(.hidden)
        .accessibilityElement()
        .accessibilityLabel("Cours de l’or et de l’argent, chacun avec son échelle")
    }

    @AxisContentBuilder
    private var scales: some AxisContent {
        AxisMarks(position: .leading, values: Self.marks) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4])).foregroundStyle(Theme.line)
            AxisValueLabel {
                Text(label(g, value)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.gold)
            }
        }
        AxisMarks(position: .trailing, values: Self.marks) { value in
            AxisValueLabel {
                Text(label(s, value)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.silver)
            }
        }
    }

    private func label(_ scale: Scale, _ value: AxisValue) -> String {
        guard let y = value.as(Double.self) else { return "" }
        let price = scale.price(y)
        return price >= 10_000 ? Fmt.decimal(price / 1000, digits: 1) + " k" : Fmt.decimal(price)
    }

    private var silverLine: some ChartContent {
        ForEach(silver, id: \.date) { p in
            LineMark(x: .value("Moment", p.date), y: .value("Hauteur", s.y(p.price)), series: .value("Métal", "Argent"))
                .foregroundStyle(monochrome ? Color.primary.opacity(0.75) : Theme.silver)
                .lineStyle(StrokeStyle(lineWidth: monochrome ? max(lineWidth - 0.6, 1.4) : lineWidth,
                                       lineCap: .round, lineJoin: .round, dash: monochrome ? [3, 3] : []))
        }
    }

    private var goldLine: some ChartContent {
        ForEach(gold, id: \.date) { p in
            LineMark(x: .value("Moment", p.date), y: .value("Hauteur", g.y(p.price)), series: .value("Métal", "Or"))
                .foregroundStyle(monochrome ? Color.primary : Theme.gold)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Une ligne « Or 98 540 € ↑ +0,82 % » pour l’en-tête des courbes superposées.
struct OverlayLegend: View {
    let series: MetalSeries
    let metal: Metal
    var big = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Capsule()
                    .fill(metal == .gold ? Theme.gold : Theme.silver)
                    .frame(width: 14, height: 4)
                Text(metal == .gold ? "Or" : "Argent")
                    .font(.system(size: big ? 12 : 10, weight: .semibold))
                    .foregroundStyle(metal == .gold ? Theme.gold : Theme.silver)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(series.price.map { Fmt.euros($0) } ?? "—")
                .font(.system(size: big ? 22 : 17, weight: .bold))
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(Fmt.variation(series, withAmount: false))
                .font(.system(size: big ? 13 : 11, weight: .semibold))
                .foregroundStyle(Theme.trend(series.delta))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}
