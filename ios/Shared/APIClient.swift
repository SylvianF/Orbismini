import Foundation

extension Notification.Name {
    /// Premier essai sans réponse : Render se réveille sans doute (offre gratuite, endormi après 15 min).
    static let serverWaking = Notification.Name("OrbisminiServerWaking")
}

enum APIError: LocalizedError, Equatable {
    case needsLogin
    case refused(String)
    case server(Int, String?)
    case network(String)
    case offline
    case invalid

    var errorDescription: String? {
        switch self {
        case .needsLogin: return "Mot de passe à saisir de nouveau."
        case .refused(let m): return m
        case .server(let code, let m): return m ?? "Erreur du serveur (\(code))."
        case .network(let m): return m
        case .offline: return "Pas de réseau."
        case .invalid: return "Réponse illisible du serveur."
        }
    }
}

/// Appels au serveur d’Orbismini : délais adaptés au réveil de Render, nouveaux essais espacés.
final class APIClient: @unchecked Sendable {
    /// Application : jusqu’à 3 essais de 45 s (Render met jusqu’à une minute à se réveiller).
    static let app = APIClient(timeout: 45, attempts: 3)
    /// Widget : iOS le coupe vers 30 s, donc un seul essai de 20 s, puis les derniers cours gardés.
    static let widget = APIClient(timeout: 20, attempts: 1)

    let session: URLSession
    let attempts: Int
    let delays: [Double]

    init(timeout: TimeInterval, attempts: Int, delays: [Double] = [3, 8], protocolClasses: [AnyClass]? = nil) {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * Double(attempts) + 30
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        if let protocolClasses { c.protocolClasses = protocolClasses }
        session = URLSession(configuration: c)
        self.attempts = max(1, attempts)
        self.delays = delays
    }

    func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET", json: Data? = nil,
                 form: Data? = nil, headers: [String: String] = [:], auth: Bool = true) -> URLRequest {
        var parts = URLComponents(url: Config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { parts.queryItems = query }
        var r = URLRequest(url: parts.url!)
        r.httpMethod = method
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            r.httpBody = json
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let form {
            r.httpBody = form
            r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if auth, let cookie = Secrets.get(.session) {
            r.setValue(Config.sessionCookie + "=" + cookie, forHTTPHeaderField: "Cookie")
        }
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    static func retryable(_ e: URLError) -> Bool {
        [.timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed,
         .badServerResponse, .secureConnectionFailed].contains(e.code)
    }

    /// Envoi avec nouveaux essais (réseau coupé net, 502/503/504 pendant le réveil de Render).
    func send(_ req: URLRequest, followRedirects: Bool = true) async throws -> (Data, HTTPURLResponse) {
        var last: APIError = .network("Serveur injoignable.")
        for attempt in 0..<attempts {
            if attempt > 0 {
                NotificationCenter.default.post(name: .serverWaking, object: nil)
                let wait = delays.isEmpty ? 0 : delays[min(attempt - 1, delays.count - 1)]
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            do {
                let (data, response) = try await session.data(for: req, delegate: followRedirects ? nil : NoRedirect())
                guard let http = response as? HTTPURLResponse else { throw APIError.invalid }
                if [502, 503, 504].contains(http.statusCode), attempt < attempts - 1 {
                    last = .server(http.statusCode, Self.message(data))
                    continue
                }
                return (data, http)
            } catch let e as URLError {
                if e.code == .notConnectedToInternet || e.code == .dataNotAllowed { throw APIError.offline }
                if e.code == .cancelled { throw CancellationError() }
                guard Self.retryable(e) else { throw APIError.network(e.localizedDescription) }
                last = e.code == .timedOut
                    ? .network("Le serveur ne répond pas (il se réveille peut-être). Réessaie dans une minute.")
                    : .network(e.localizedDescription)
            }
        }
        throw last
    }

    func json<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, http) = try await send(req)
        switch http.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.invalid }
        case 401: throw APIError.needsLogin
        case 403: throw APIError.refused(Self.message(data) ?? "Accès refusé.")
        default: throw APIError.server(http.statusCode, Self.message(data))
        }
    }

    static func message(_ data: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
    }
}

/// Pour la connexion : la réponse 303 garde son cookie au lieu d’être suivie.
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Cours et courbes : par la session (application), ou par la clé du widget (/api/widget).
enum DataService {
    static func snapshot(period: Period, client: APIClient, preferWidgetKey: Bool) async throws -> Snapshot {
        let key = Secrets.get(.widgetKey) ?? ""
        if !key.isEmpty, preferWidgetKey || !Session.isOpen {
            return try await viaWidgetKey(period: period, key: key, client: client)
        }
        return try await viaSession(period: period, client: client)
    }

    static func viaWidgetKey(period: Period, key: String, client: APIClient) async throws -> Snapshot {
        let req = client.request("/api/widget", query: [URLQueryItem(name: "period", value: period.rawValue)],
                                 headers: ["X-Widget-Key": key], auth: false)
        do {
            return try await client.json(WidgetDTO.self, req).snapshot(period)
        } catch APIError.refused {
            throw APIError.refused("Clé du widget refusée par Orbismini.")
        }
    }

    static func viaSession(period: Period, client: APIClient) async throws -> Snapshot {
        func history(_ metal: Metal) -> URLRequest {
            client.request("/api/spot-history", query: [URLQueryItem(name: "period", value: period.rawValue),
                                                        URLQueryItem(name: "metal", value: metal.rawValue)])
        }
        async let goldResult = capture { try await client.json(HistoryDTO.self, history(.gold)) }
        async let silverResult = capture { try await client.json(HistoryDTO.self, history(.silver)) }
        async let spotResult = capture { try await client.json(SpotDTO.self, client.request("/api/spot")) }
        let (g, s, spot) = await (goldResult, silverResult, spotResult)

        for r in [g.error, s.error, spot.error] {
            if let e = r as? APIError, e == .needsLogin { throw e }
            if r is CancellationError { throw CancellationError() }
        }
        if let ge = g.error, s.error != nil { throw ge }

        var gold = (try? g.get().series) ?? .failed(g.error?.localizedDescription ?? "Cours indisponible")
        let silver = (try? s.get().series) ?? .failed(s.error?.localizedDescription ?? "Cours indisponible")
        // Or : cours Kitco (Bid) comme le site, la courbe restant celle de BullionVault.
        if let q = try? spot.get(), gold.error == nil {
            gold.price = q.price
            gold.source = q.source
            gold.quotedAt = DateParser.parse(q.updatedAt) ?? gold.quotedAt
            gold.marketClosed = q.marketClosed ?? false
        }
        return Snapshot(period: period, updatedAt: Date(), gold: gold, silver: silver)
    }

    static func weather(client: APIClient) async throws -> Weather {
        try await client.json(Weather.self, client.request("/api/weather"))
    }

    static func alert(client: APIClient, settings: AlertSettings? = nil) async throws -> AlertState {
        var body: Data?
        if let settings { body = try JSONEncoder().encode(settings) }
        let req = client.request("/api/alert", method: settings == nil ? "GET" : "POST", json: body,
                                 headers: ["X-Appareil": Secrets.deviceID])
        return try await client.json(AlertState.self, req)
    }
}

func capture<T>(_ op: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await op()) } catch { return .failure(error) }
}

extension Result {
    var error: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}
