import Foundation

// MARK: - Cours et courbes

enum Period: String, Codable, CaseIterable, Identifiable {
    case day = "1", week = "7", month = "30", year = "365"

    var id: String { rawValue }
    /// Comme le widget Scriptable : « 1 jour », « 7 jours », « 1 mois », « 1 an ».
    var label: String {
        switch self {
        case .day: return "1 jour"
        case .week: return "7 jours"
        case .month: return "1 mois"
        case .year: return "1 an"
        }
    }
    var short: String {
        switch self {
        case .day: return "1 j"
        case .week: return "7 j"
        case .month: return "1 mois"
        case .year: return "1 an"
        }
    }
}

enum Metal: String, Codable, CaseIterable, Identifiable {
    case gold, silver
    var id: String { rawValue }
    var title: String { self == .gold ? "Or pur · 1 kg" : "Argent pur · 1 kg" }
}

struct PricePoint: Codable, Hashable {
    var date: Date
    var price: Double
}

/// Un métal : dernier cours et courbe de la période.
struct MetalSeries: Codable, Equatable {
    var price: Double?
    var points: [PricePoint] = []
    var source: String?
    var quotedAt: Date?
    var marketClosed = false
    var error: String?

    var hasCurve: Bool { points.count > 1 }
    var isAvailable: Bool { error == nil && !points.isEmpty }

    /// Variation sur la courbe elle-même (BullionVault), comme le site et le widget Scriptable.
    var delta: Double? {
        guard let first = points.first?.price, let last = points.last?.price, points.count > 1 else { return nil }
        return last - first
    }
    var percent: Double? {
        guard let delta, let first = points.first?.price, first != 0 else { return nil }
        return delta / first * 100
    }
    var low: Double? { points.map(\.price).min() }
    var high: Double? { points.map(\.price).max() }

    static func failed(_ message: String) -> MetalSeries { MetalSeries(error: message) }
}

/// Ce qu’affichent l’écran Cours et le widget pour une période.
struct Snapshot: Codable, Equatable {
    var period: Period
    var updatedAt: Date
    var gold: MetalSeries
    var silver: MetalSeries

    func series(_ metal: Metal) -> MetalSeries { metal == .gold ? gold : silver }

    /// Moment du dernier cours affiché (pied du widget).
    func when(_ metal: Metal) -> Date {
        let s = series(metal)
        return (metal == .gold ? s.quotedAt : nil) ?? s.points.last?.date ?? updatedAt
    }
}

// MARK: - Réponses du serveur (server.py)

/// /api/widget : points en paires [date, prix].
struct WidgetDTO: Decodable {
    struct Pair: Decodable {
        let date: String
        let price: Double
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            date = try c.decode(String.self)
            price = try c.decode(Double.self)
        }
    }
    struct Metal: Decodable {
        let points: [Pair]?
        let price: Double?
        let source: String?
        let quotedAt: String?
        let marketClosed: Bool?
        let error: String?
    }
    let period: String?
    let updatedAt: String?
    let gold: Metal?
    let silver: Metal?

    func snapshot(_ period: Period) -> Snapshot {
        func series(_ m: Metal?) -> MetalSeries {
            guard let m else { return .failed("Cours indisponible") }
            if let error = m.error { return .failed(error) }
            let points = (m.points ?? []).compactMap { p in DateParser.parse(p.date).map { PricePoint(date: $0, price: p.price) } }
            return MetalSeries(price: m.price ?? points.last?.price, points: points, source: m.source,
                               quotedAt: DateParser.parse(m.quotedAt), marketClosed: m.marketClosed ?? false)
        }
        return Snapshot(period: Period(rawValue: self.period ?? "") ?? period,
                        updatedAt: DateParser.parse(updatedAt) ?? Date(),
                        gold: series(gold), silver: series(silver))
    }
}

/// /api/spot-history
struct HistoryDTO: Decodable {
    struct Point: Decodable {
        let date: String
        let price: Double
    }
    let points: [Point]
    let quotedAt: String?
    let source: String?

    var series: MetalSeries {
        let pts = points.compactMap { p in DateParser.parse(p.date).map { PricePoint(date: $0, price: p.price) } }
        return MetalSeries(price: pts.last?.price, points: pts, source: source ?? "BullionVault",
                           quotedAt: DateParser.parse(quotedAt))
    }
}

/// /api/spot : or pur en €/kg (Kitco, sinon BullionVault).
struct SpotDTO: Decodable {
    let price: Double
    let updatedAt: String?
    let source: String?
    let marketClosed: Bool?
}

// MARK: - Météo de l’or (/api/weather, meteo_or.py)

struct Weather: Codable, Equatable {
    struct Sky: Codable, Equatable {
        var key: String
        var icon: String
        var label: String
        var text: String
    }
    struct Agitation: Codable, Equatable {
        var percent: Double?
        var level: String?
    }
    struct Indicator: Codable, Equatable, Identifiable {
        var key: String
        var group: String
        var label: String
        var value: String?
        var signal: Double?
        var text: String?
        var id: String { key }
    }
    struct Day: Codable, Equatable {
        var day: String
        var score: Double?
        var weather: Sky?
    }
    var at: String?
    var price: Double?
    var score: Double?
    var weather: Sky?
    var up: Int?
    var down: Int?
    var flat: Int?
    var agitation: Agitation?
    var indicators: [Indicator]?
    var history: [Day]?
    var missing: [String]?

    struct Group: Identifiable {
        let name: String
        var items: [Indicator]
        var id: String { name }
    }

    /// Indices par groupe, dans l’ordre du serveur (Tendance, Économie, Repères).
    var groups: [Group] {
        var out: [Group] = []
        for x in indicators ?? [] {
            if let i = out.firstIndex(where: { $0.name == x.group }) { out[i].items.append(x) } else { out.append(Group(name: x.group, items: [x])) }
        }
        return out
    }
}

// MARK: - Alerte de cours (/api/alert, alerte.py)

struct AlertState: Codable, Equatable {
    struct Hit: Codable, Equatable, Identifiable {
        var id: String
        var dir: String
        var level: Double?
        var price: Double?
        var at: String?
        var ref: Double?
        var change: Double?

        /// Même texte que les notifications (alerte.what).
        var title: String {
            switch dir {
            case "up", "down":
                return "Or en " + (dir == "up" ? "hausse" : "baisse") + " de " + Fmt.decimal(abs(change ?? 0), digits: 1) + " % sur 24 h"
            default:
                return "Or " + (dir == "above" ? "au-dessus de " : "en dessous de ") + Fmt.kilo(level ?? 0)
            }
        }
    }
    var above: Double?
    var below: Double?
    var move: Double?
    var updated: String?
    var hits: [Hit]?
    var channel: String?
    var price: Double?
    var mode: String?

    var isActive: Bool { above != nil || below != nil || move != nil }
}

/// Réglages envoyés au serveur (le plus récent l’emporte).
struct AlertSettings: Encodable {
    var above: Double?
    var below: Double?
    var move: Double?
    var updated: String
    var hits: [AlertState.Hit]
}

/// Contrôle de la saisie, comme la page web (alerte-cours.js).
enum AlertForm {
    struct Values: Equatable {
        var above: Double?
        var below: Double?
        var move: Double?
    }

    static func validate(above: String, below: String, move: String, price: Double?) -> Result<Values, AlertFormError> {
        let a = Fmt.parseNumber(above), b = Fmt.parseNumber(below), m = Fmt.parseNumber(move)
        for (text, value) in [(above, a), (below, b)] where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let value, value > 1000 else { return .failure(.init("Saisir un cours en euros par kilo, par exemple 120 000.")) }
        }
        if !move.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let m, m >= 0.5, m <= 20 else { return .failure(.init("Saisir une variation entre 0,5 et 20 %, par exemple 2.")) }
        }
        if let price, let a, a <= price {
            return .failure(.init("Le cours est déjà au-dessus de " + Fmt.kilo(a) + " : choisir un seuil plus haut."))
        }
        if let price, let b, b >= price {
            return .failure(.init("Le cours est déjà en dessous de " + Fmt.kilo(b) + " : choisir un seuil plus bas."))
        }
        return .success(Values(above: a, below: b, move: m))
    }
}

struct AlertFormError: Error, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}
