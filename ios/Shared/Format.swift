import Foundation

/// Nombres, dates et heures à la française.
enum Fmt {
    static let fr = Locale(identifier: "fr_FR")
    static let paris = TimeZone(identifier: "Europe/Paris") ?? .current

    static func decimal(_ v: Double, digits: Int = 0, minDigits: Int? = nil) -> String {
        let f = NumberFormatter()
        f.locale = fr
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = minDigits ?? digits
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func euros(_ v: Double, digits: Int = 0) -> String { decimal(v, digits: digits) + " €" }
    static func kilo(_ v: Double) -> String { decimal(v.rounded()) + " €/kg" }

    /// « ↑ +0,42 % · +512 € » comme le widget Scriptable.
    static func variation(_ series: MetalSeries, withAmount: Bool) -> String {
        guard let delta = series.delta, let percent = series.percent else { return "" }
        let sign = delta > 0 ? "+" : delta < 0 ? "−" : ""
        let arrow = delta > 0 ? "↑ " : delta < 0 ? "↓ " : "→ "
        var out = arrow + sign + decimal(abs(percent), digits: 2, minDigits: 0) + " %"
        if withAmount { out += " · " + sign + euros(abs(delta)) }
        return out
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = fr
        f.timeZone = paris
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// « 21 novembre à 10:42 », ou « aujourd’hui à 10:42 ».
    static func dayTime(_ d: Date, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = paris
        if cal.isDate(d, inSameDayAs: now) { return "aujourd’hui à " + time(d) }
        let f = DateFormatter()
        f.locale = fr
        f.timeZone = paris
        f.dateFormat = "d MMMM"
        return f.string(from: d) + " à " + time(d)
    }

    /// « 120 000 », « 120000,5 », « 2,5 % » → nombre ; nil si illisible ou vide.
    static func parseNumber(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "€/kg", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "%", with: "")
            .components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{00A0}\u{202F}")))
            .joined()
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}

/// Dates du serveur Python (isoformat) : « 2026-11-21T10:00:00+00:00 », avec ou sans
/// fractions de seconde (jusqu’à 6 chiffres), ou « Z ».
enum DateParser {
    static func parse(_ text: String?) -> Date? {
        guard var s = text?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // Sans fuseau : heure UTC.
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: s)
    }

    static func iso(_ d: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}
