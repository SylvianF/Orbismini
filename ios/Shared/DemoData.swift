import Foundation

/// Données d’exemple (captures d’écran de GitHub Actions, aperçu du widget) : jamais de vrais cours.
enum DemoData {
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 20; c.hour = 16; c.minute = 42
        c.timeZone = Fmt.paris
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    static func series(_ metal: Metal, _ period: Period) -> MetalSeries {
        let count = 120
        let days = Double(period.days)
        let span = days * 86_400
        let base = metal == .gold ? 118_400.0 : 1_452.0
        let swing = metal == .gold ? 1_350.0 : 31.0
        let points = (0..<count).map { i -> PricePoint in
            let x = Double(i) / Double(count - 1)
            let wave = sin(x * 7.1) * 0.45 + sin(x * 17.3 + 1) * 0.18 + x * (metal == .gold ? 1.1 : -0.6)
            return PricePoint(date: now.addingTimeInterval(-span * (1 - x)), price: (base + wave * swing).rounded())
        }
        return MetalSeries(price: points.last?.price, points: points, source: "Exemple", quotedAt: now)
    }

    static func snapshot(_ period: Period = .day) -> Snapshot {
        Snapshot(period: period, updatedAt: now, gold: series(.gold, period), silver: series(.silver, period))
    }

    static let weather = Weather(
        at: DateParser.iso(now), price: 119_600, score: 0.38,
        weather: .init(key: "eclaircies", icon: "🌤️", label: "Éclaircies", text: "Les indices penchent plutôt vers la hausse."),
        up: 4, down: 1, flat: 2,
        agitation: .init(percent: 0.92, level: "habituelle"),
        indicators: [
            .init(key: "ma200", group: "Tendance", label: "Moyenne sur 200 jours", value: "+8,4 %", signal: 1,
                  text: "Le cours est au-dessus de sa moyenne des 200 derniers jours : la tendance de fond monte."),
            .init(key: "mom", group: "Tendance", label: "Élan sur 3 mois", value: "+3,1 %", signal: 1,
                  text: "Sur trois mois, l’or a gagné du terrain."),
            .init(key: "vol", group: "Tendance", label: "Agitation", value: "0,92 % par jour", signal: 0,
                  text: "Écart moyen d’un jour à l’autre ; ici : agitation habituelle."),
            .init(key: "rates", group: "Économie", label: "Taux d'intérêt américains", value: "4,12 % (−0,15 pt)", signal: 0,
                  text: "L'or ne rapporte pas d'intérêts : quand les taux baissent, il attire plus."),
            .init(key: "vix", group: "Économie", label: "Indice de la peur (VIX)", value: "17,8", signal: 0,
                  text: "Inquiétude modérée sur les marchés boursiers."),
            .init(key: "ratio", group: "Repères", label: "Ratio or / argent", value: "82,4", signal: 0,
                  text: "Dans sa moyenne habituelle (65 à 85)."),
        ],
        history: (1...6).map { i in
            Weather.Day(day: "2026-11-\(13 + i)", score: 0.3,
                        weather: i < 3 ? .init(key: "variable", icon: "⛅", label: "Temps variable", text: "")
                                       : .init(key: "eclaircies", icon: "🌤️", label: "Éclaircies", text: ""))
        },
        missing: nil
    )

    static let alert = AlertState(
        above: 121_000, below: 112_000, move: 2, updated: DateParser.iso(now),
        hits: [.init(id: "exemple", dir: "above", level: 118_000, price: 118_210, at: DateParser.iso(now.addingTimeInterval(-86_400 * 2)))],
        channel: nil, price: 119_600, mode: "appareil"
    )
}
