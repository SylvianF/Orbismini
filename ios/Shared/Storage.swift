import Foundation
import Security

/// Dossier et réglages partagés entre l’application et le widget (groupe d’applications).
enum SharedStore {
    static var folder: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Config.appGroup) {
            return url
        }
        // Sans groupe (simulateur sans signature) : dossier propre à l’application.
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: Config.appGroup) ?? .standard }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(name), options: [.atomic])
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }

    // Derniers cours gardés : affichés hors connexion, et par le widget.
    static func snapshot(_ period: Period) -> Snapshot? { load(Snapshot.self, from: "cours-\(period.rawValue).json") }
    static func saveSnapshot(_ s: Snapshot) { save(s, as: "cours-\(s.period.rawValue).json") }
    static func weather() -> Weather? { load(Weather.self, from: "meteo.json") }
    static func saveWeather(_ w: Weather) { save(w, as: "meteo.json") }

    static func clearCache() {
        Period.allCases.forEach { remove("cours-\($0.rawValue).json") }
        remove("meteo.json")
    }
}

enum SecretKey: String {
    case session = "session"          // cookie goldapp_session (connexion par mot de passe)
    case device = "appareil"          // identifiant secret du téléphone (X-Appareil)
    case widgetKey = "cle-widget"     // clé du widget (GOLDAPP_WIDGET_KEY), facultative
}

/// Trousseau d’Apple, partagé avec le widget par le groupe d’applications.
enum Secrets {
    private static let service = "fr.cndo.orbismini"

    private static func query(_ key: SecretKey, group: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        if group { q[kSecAttrAccessGroup as String] = Config.appGroup }
        return q
    }

    static func get(_ key: SecretKey) -> String? {
        for group in [true, false] {
            var q = query(key, group: group)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: AnyObject?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    static func set(_ key: SecretKey, _ value: String?) {
        for group in [true, false] { SecItemDelete(query(key, group: group) as CFDictionary) }
        guard let value, !value.isEmpty else { return }
        for group in [true, false] {
            var q = query(key, group: group)
            q[kSecValueData as String] = Data(value.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(q as CFDictionary, nil) == errSecSuccess { return }
            // Sans droit au groupe (simulateur sans signature) : trousseau propre à l’application.
        }
    }

    /// Identifiant secret de ce téléphone (32 caractères hexadécimaux), tiré une fois.
    static var deviceID: String {
        if let id = get(.device), id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil { return id }
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let id = bytes.map { String(format: "%02x", $0) }.joined()
        set(.device, id)
        return id
    }
}

/// Connexion à Orbismini : cookie de session gardé dans le trousseau.
enum Session {
    private static let openKey = "serveurSansMotDePasse"

    static var isOpen: Bool { Secrets.get(.session) != nil || SharedStore.defaults.bool(forKey: openKey) }

    static func store(cookie: String?) {
        Secrets.set(.session, cookie)
        SharedStore.defaults.set(false, forKey: openKey)
    }

    /// Serveur sans mot de passe (GOLDAPP_PASSWORD absent) : rien à retenir.
    static func markOpenServer() { SharedStore.defaults.set(true, forKey: openKey) }

    static func clear() {
        Secrets.set(.session, nil)
        SharedStore.defaults.set(false, forKey: openKey)
    }

    /// Valeur du cookie goldapp_session dans une réponse (Set-Cookie).
    static func cookie(from response: HTTPURLResponse) -> String? {
        var fields: [String: String] = [:]
        for (k, v) in response.allHeaderFields {
            if let k = k as? String, let v = v as? String { fields[k] = v }
        }
        let url = response.url ?? Config.baseURL
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .first { $0.name == Config.sessionCookie && !$0.value.isEmpty }?.value
    }
}
