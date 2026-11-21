import Charts
import SwiftUI

/// Courbe d’un métal : repère du début de période, surface, courbe, dernier cours ; plus haut et
/// plus bas dans un coin (comme le widget Scriptable). Option : axes et lecture au doigt (application).
struct CourseChart: View {
    let points: [PricePoint]
    let color: Color
    var showLabels = true
    var interactive = false
    var period: Period = .day

    @State private var selected: Date?

    private var low: Double { points.map(\.price).min() ?? 0 }
    private var high: Double { points.map(\.price).max() ?? 1 }
    private var pad: Double { max((high - low) * 0.12, high * 0.0005, 1) }

    private var selectedPoint: PricePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }

    var body: some View {
        Chart {
            if let first = points.first {
                RuleMark(y: .value("Début", first.price))
                    .foregroundStyle(Theme.muted.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            ForEach(points, id: \.date) { p in
                AreaMark(x: .value("Moment", p.date),
                         yStart: .value("Bas", low - pad),
                         yEnd: .value("Cours", p.price))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.26), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Moment", p.date), y: .value("Cours", p.price))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let last = points.last, selectedPoint == nil {
                PointMark(x: .value("Moment", last.date), y: .value("Cours", last.price))
                    .foregroundStyle(color)
                    .symbolSize(36)
            }
            if let p = selectedPoint {
                RuleMark(x: .value("Moment", p.date))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 0) {
                            Text(Fmt.euros(p.price)).font(.caption.bold()).foregroundStyle(Theme.text)
                            Text(label(p.date)).font(.caption2).foregroundStyle(Theme.muted)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.bg2.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                    }
                PointMark(x: .value("Moment", p.date), y: .value("Cours", p.price))
                    .foregroundStyle(color)
                    .symbolSize(50)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXScale(domain: (points.first?.date ?? Date())...(points.last?.date ?? Date()))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.5))
                AxisValueLabel {
                    Text(value.as(Date.self).map(axisLabel) ?? "").font(.caption2).foregroundStyle(Theme.muted)
                }
            }
        }
        .chartXAxis(interactive ? .visible : .hidden)
        .chartYAxis(.hidden)
        .modifier(Selection(enabled: interactive, selected: $selected))
        .overlay(alignment: .topTrailing) {
            if showLabels, points.count > 1 {
                Text("▲ " + Fmt.euros(high)).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showLabels, points.count > 1, !interactive {
                Text("▼ " + Fmt.euros(low)).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Courbe sur " + period.label)
        .accessibilityValue(points.last.map { "Dernier cours " + Fmt.euros($0.price) } ?? "")
    }

    private func axisLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Fmt.fr
        f.timeZone = Fmt.paris
        f.dateFormat = period == .day ? "HH'h'" : period == .year ? "MMM" : "d MMM"
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
