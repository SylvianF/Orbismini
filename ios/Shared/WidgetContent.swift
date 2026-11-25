import SwiftUI

enum WidgetSize: String, CaseIterable {
    case small, medium, large

    /// Taille d’un iPhone courant (6,1 pouces), pour l’aperçu dans l’application.
    var previewSize: CGSize {
        switch self {
        case .small: return CGSize(width: 158, height: 158)
        case .medium: return CGSize(width: 338, height: 158)
        case .large: return CGSize(width: 338, height: 354)
        }
    }
    var title: String {
        switch self {
        case .small: return "Petit"
        case .medium: return "Moyen"
        case .large: return "Grand"
        }
    }
}

/// Contenu du widget, le même que widget/Orbismini-widget.js (Scriptable) : or, argent, courbe.
/// Partagé avec l’application pour l’aperçu (Réglages → Aperçu du widget).
struct WidgetContent: View {
    let snapshot: Snapshot?
    let metal: Metal
    let size: WidgetSize
    var stale = false
    var message: String?
    /// Or et argent superposés (variation en %), au lieu d’un seul métal.
    var both = false

    var body: some View {
        if let snapshot, both {
            switch size {
            case .small: bothSmall(snapshot)
            case .medium: bothMedium(snapshot)
            case .large: bothLarge(snapshot)
            }
        } else if let snapshot {
            switch size {
            case .small: small(snapshot)
            case .medium: medium(snapshot)
            case .large: large(snapshot)
            }
        } else {
            unavailable
        }
    }

    private func small(_ s: Snapshot) -> some View {
        let series = s.series(metal)
        return VStack(alignment: .leading, spacing: 2) {
            MetalBlock(series: series, metal: metal, compact: true)
            if series.hasCurve {
                CourseChart(points: series.points, color: color(metal), showLabels: false).padding(.top, 4)
            }
            Spacer(minLength: 0)
            Footer(snapshot: s, metal: metal, stale: stale)
        }
    }

    private func medium(_ s: Snapshot) -> some View {
        let series = s.series(metal)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                MetalBlock(series: series, metal: metal, compact: false).frame(width: 118, alignment: .leading)
                if series.hasCurve {
                    CourseChart(points: series.points, color: color(metal))
                }
            }
            .frame(maxHeight: .infinity)
            Footer(snapshot: s, metal: metal, stale: stale)
        }
    }

    private func large(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metalRow(s.gold, .gold)
            Spacer(minLength: 6)
            metalRow(s.silver, .silver)
            Footer(snapshot: s, metal: metal, stale: stale)
        }
    }

    @ViewBuilder
    private func metalRow(_ series: MetalSeries, _ m: Metal) -> some View {
        MetalBlock(series: series, metal: m, compact: false)
        if series.hasCurve {
            CourseChart(points: series.points, color: color(m))
        }
    }

    // MARK: - Or et argent superposés

    private func bothSmall(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            compactLine(s.gold, .gold)
            compactLine(s.silver, .silver)
            OverlayChart(gold: s.gold.points, silver: s.silver.points, lineWidth: 2.6, showScales: false).padding(.top, 3)
            Footer(snapshot: s, metal: .gold, stale: stale)
        }
    }

    private func bothMedium(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 12) {
                OverlayLegend(series: s.gold, metal: .gold)
                OverlayLegend(series: s.silver, metal: .silver)
                Spacer(minLength: 0)
            }
            OverlayChart(gold: s.gold.points, silver: s.silver.points, lineWidth: 3)
            Footer(snapshot: s, metal: .gold, stale: stale)
        }
    }

    private func bothLarge(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 18) {
                OverlayLegend(series: s.gold, metal: .gold, big: true)
                OverlayLegend(series: s.silver, metal: .silver, big: true)
                Spacer(minLength: 0)
            }
            OverlayChart(gold: s.gold.points, silver: s.silver.points, lineWidth: 3.6)
            Text("Chaque courbe a son échelle : or à gauche, argent à droite (€/kg)")
                .font(.system(size: 9)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
            Footer(snapshot: s, metal: .gold, stale: stale)
        }
    }

    private func compactLine(_ series: MetalSeries, _ m: Metal) -> some View {
        HStack(spacing: 4) {
            Text(m == .gold ? "Or" : "Ag").font(.system(size: 11, weight: .bold)).foregroundStyle(color(m))
            Text(Fmt.variation(series, withAmount: false))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.trend(series.delta))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Orbismini").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
            Spacer().frame(height: 2)
            Text("Cours indisponibles").font(.system(size: 12)).foregroundStyle(Theme.text)
            Text(message ?? "Ouvre Orbismini une première fois, puis réessaie dans quelques minutes.")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(_ m: Metal) -> Color { m == .gold ? Theme.gold : Theme.silver }
}

struct MetalBlock: View {
    let series: MetalSeries
    let metal: Metal
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(metal.title)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(metal == .gold ? Theme.gold : Theme.silver)
                .lineLimit(1)
            if series.isAvailable, let price = series.price {
                Text(Fmt.euros(price))
                    .font(.system(size: compact ? 20 : 24, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(Fmt.variation(series, withAmount: !compact))
                    .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    .foregroundStyle(Theme.trend(series.delta))
                    .lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text("Cours indisponible").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }
}

private struct Footer: View {
    let snapshot: Snapshot
    let metal: Metal
    let stale: Bool

    private var line: String {
        var out = stale ? "⚠ " : ""
        out += snapshot.period.label + " · " + Fmt.time(snapshot.when(metal))
        if metal == .gold && snapshot.gold.marketClosed { out += " · marché fermé" }
        return out
    }

    var body: some View {
        Text(line)
            .font(.system(size: 9))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
    }
}
