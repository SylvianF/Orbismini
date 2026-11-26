import SwiftUI

/// Formats de l’écran verrouillé (et du mode veille) : une ligne sous l’heure, une pastille ronde,
/// un rectangle avec la courbe. iOS les affiche d’une seule couleur : pas de couleurs ici.
enum LockSize: String, CaseIterable {
    case inline, circular, rectangular

    var title: String {
        switch self {
        case .inline: return "Ligne (sous l’heure)"
        case .circular: return "Pastille"
        case .rectangular: return "Rectangle avec la courbe"
        }
    }
    /// Taille sur un iPhone courant, pour l’aperçu dans l’application.
    var previewSize: CGSize {
        switch self {
        case .inline: return CGSize(width: 250, height: 22)
        case .circular: return CGSize(width: 72, height: 72)
        case .rectangular: return CGSize(width: 172, height: 76)
        }
    }
}

struct LockContent: View {
    let snapshot: Snapshot?
    let metal: Metal
    let both: Bool
    let size: LockSize

    var body: some View {
        if let s = snapshot {
            switch size {
            case .inline: inline(s)
            case .circular: circular(s)
            case .rectangular: rectangular(s)
            }
        } else {
            Text(size == .circular ? "—" : "Orbismini : cours indisponibles")
                .font(.system(size: 12))
        }
    }

    // « Or 98 540 € ↑ +0,82 % » ; les deux métaux : « Or ↑ +0,82 % · Ag ↓ −0,31 % ».
    private func inline(_ s: Snapshot) -> some View {
        Text(both ? short(s.gold, "Or") + " · " + short(s.silver, "Ag") : long(s.series(metal), metal))
    }

    private func circular(_ s: Snapshot) -> some View {
        let series = s.series(both ? .gold : metal)
        return ZStack {
            Circle().fill(Color.primary.opacity(0.14))
            VStack(spacing: 0) {
                Text(metal == .silver && !both ? "Ag" : "Or")
                    .font(.system(size: 11, weight: .semibold))
                Text(percentOnly(series))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(series.price.map { compactPrice($0) } ?? "")
                    .font(.system(size: 9))
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            .padding(5)
        }
    }

    private func rectangular(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(both ? short(s.gold, "Or") + "  " + short(s.silver, "Ag") : long(s.series(metal), metal))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.6)
            chart(s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func chart(_ s: Snapshot) -> some View {
        if both {
            OverlayChart(gold: s.gold.points, silver: s.silver.points, lineWidth: 2.4, monochrome: true)
        } else if s.series(metal).hasCurve {
            LockLine(points: s.series(metal).points)
        }
    }

    private func long(_ series: MetalSeries, _ m: Metal) -> String {
        (m == .gold ? "Or " : "Argent ") + (series.price.map { Fmt.euros($0) } ?? "—") + " " + Fmt.variation(series, withAmount: false)
    }

    private func short(_ series: MetalSeries, _ label: String) -> String {
        label + " " + Fmt.variation(series, withAmount: false)
    }

    private func percentOnly(_ series: MetalSeries) -> String {
        guard let p = series.percent else { return "—" }
        return (p > 0 ? "+" : p < 0 ? "−" : "") + Fmt.decimal(abs(p), digits: 1, minDigits: 1) + "%"
    }

    private func compactPrice(_ v: Double) -> String {
        v >= 10_000 ? Fmt.decimal(v / 1000, digits: 1) + " k€" : Fmt.euros(v)
    }
}

/// Courbe d’un métal sur l’écran verrouillé : un trait épais, sans surface ni couleur.
private struct LockLine: View {
    let points: [PricePoint]

    var body: some View {
        OverlayChart(gold: points, silver: [], lineWidth: 2.4, monochrome: true)
    }
}
