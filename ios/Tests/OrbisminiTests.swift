import XCTest
@testable import Orbismini

final class FormatTests: XCTestCase {
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    func testEuros() {
        XCTAssertEqual(plain(Fmt.euros(121_345.6)), "121 346 €")
        XCTAssertEqual(plain(Fmt.kilo(120_000)), "120 000 €/kg")
        XCTAssertEqual(plain(Fmt.decimal(2.5, digits: 1)), "2,5")
    }

    func testParseNumber() {
        XCTAssertEqual(Fmt.parseNumber("120 000"), 120_000)
        XCTAssertEqual(Fmt.parseNumber("120\u{202F}000 €/kg"), 120_000)
        XCTAssertEqual(Fmt.parseNumber("2,5"), 2.5)
        XCTAssertEqual(Fmt.parseNumber("2,5 %"), 2.5)
        XCTAssertNil(Fmt.parseNumber(""))
        XCTAssertNil(Fmt.parseNumber("abc"))
    }

    func testVariationLikeScriptable() {
        let s = MetalSeries(price: 101, points: [PricePoint(date: Date(), price: 100), PricePoint(date: Date(), price: 101)])
        XCTAssertEqual(plain(Fmt.variation(s, withAmount: true)), "↑ +1 % · +1 €")
        let d = MetalSeries(price: 99, points: [PricePoint(date: Date(), price: 100), PricePoint(date: Date(), price: 99.5)])
        XCTAssertEqual(plain(Fmt.variation(d, withAmount: false)), "↓ −0,5 %")
    }

    func testPythonDates() {
        let a = DateParser.parse("2026-11-21T10:00:00+00:00")
        let b = DateParser.parse("2026-11-21T10:00:00.123456+00:00")
        let c = DateParser.parse("2026-11-21T11:00:00+01:00")
        let d = DateParser.parse("2026-11-21T10:00:00Z")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, c)
        XCTAssertEqual(a, d)
        XCTAssertNil(DateParser.parse("pas une date"))
        XCTAssertNil(DateParser.parse(nil))
    }
}

final class DecodingTests: XCTestCase {
    func testWidgetPayload() throws {
        let json = """
        {"period":"1","updatedAt":"2026-11-21T10:00:00.5+00:00",
         "gold":{"points":[["2026-11-21T08:00:00+00:00",118000.5],["2026-11-21T09:50:00.123000+00:00",118500]],
                 "price":118610,"source":"Kitco","quotedAt":"2026-11-21T09:59:00+00:00","marketClosed":false},
         "silver":{"error":"BullionVault indisponible"}}
        """
        let s = try JSONDecoder().decode(WidgetDTO.self, from: Data(json.utf8)).snapshot(.week)
        XCTAssertEqual(s.period, .day)
        XCTAssertEqual(s.gold.price, 118_610)
        XCTAssertEqual(s.gold.points.count, 2)
        XCTAssertEqual(s.gold.delta, 499.5)
        XCTAssertEqual(s.gold.source, "Kitco")
        XCTAssertNotNil(s.gold.quotedAt)
        XCTAssertFalse(s.silver.isAvailable)
        XCTAssertEqual(s.silver.error, "BullionVault indisponible")
        // Gardé sur l’iPhone puis relu : identique.
        let again = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(again, s)
    }

    func testHistory() throws {
        let json = """
        {"points":[{"date":"2026-11-21T08:00:00+00:00","price":1450.2},{"date":"2026-11-21T09:00:00+00:00","price":1461}],
         "source":"BullionVault","unit":"EUR/kg","period":"1","metal":"silver","quotedAt":"2026-11-21T09:00:00+00:00"}
        """
        let s = try JSONDecoder().decode(HistoryDTO.self, from: Data(json.utf8)).series
        XCTAssertEqual(s.price, 1461)
        XCTAssertTrue(s.hasCurve)
        XCTAssertEqual(s.low, 1450.2)
    }

    func testWeather() throws {
        let json = """
        {"at":"2026-11-21T10:00:00+00:00","price":119000,"ma200":110000,"score":0.4,
         "weather":{"key":"eclaircies","icon":"🌤️","label":"Éclaircies","text":"Plutôt à la hausse."},
         "up":4,"down":1,"flat":2,"agitation":{"percent":0.9,"level":"habituelle"},
         "indicators":[{"key":"a","group":"Tendance","label":"A","value":"+1 %","signal":1,"text":"t"},
                       {"key":"b","group":"Économie","label":"B","value":"2","signal":-1,"text":"t"},
                       {"key":"c","group":"Tendance","label":"C","value":"3","signal":0,"text":"t"}],
         "history":[{"day":"2026-11-20","score":0.2,"weather":{"key":"variable","icon":"⛅","label":"Temps variable","text":""}}],
         "errors":[],"missing":[],"odds":{"rows":[]}}
        """
        let w = try JSONDecoder().decode(Weather.self, from: Data(json.utf8))
        XCTAssertEqual(w.weather?.label, "Éclaircies")
        XCTAssertEqual(w.groups.map(\.name), ["Tendance", "Économie"])
        XCTAssertEqual(w.groups.first?.items.count, 2)
    }

    func testAlert() throws {
        let json = """
        {"above":121000.0,"hits":[{"id":"x1","dir":"up","level":2.0,"price":121000,"ref":118000,"change":2.54,"at":"2026-11-21T10:00:00+00:00"}],
         "channel":"orbismini-abc","price":119000,"mode":"appareil"}
        """
        let a = try JSONDecoder().decode(AlertState.self, from: Data(json.utf8))
        XCTAssertTrue(a.isActive)
        XCTAssertEqual(a.hits?.first?.title.replacingOccurrences(of: "\u{202F}", with: " "), "Or en hausse de 2,5 % sur 24 h")
        // Seuils absents : non envoyés (le serveur les retire, le plus récent l’emporte).
        let body = try JSONEncoder().encode(AlertSettings(above: nil, below: 100_000, move: nil, updated: "t", hits: []))
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNil(sent?["above"])
        XCTAssertEqual(sent?["below"] as? Double, 100_000)
    }
}

final class AlertFormTests: XCTestCase {
    func testLikeTheWebPage() {
        XCTAssertEqual(try? AlertForm.validate(above: "125 000", below: "", move: "2,5", price: 120_000).get(),
                       AlertForm.Values(above: 125_000, below: nil, move: 2.5))
        XCTAssertThrowsError(try AlertForm.validate(above: "125", below: "", move: "", price: nil).get())
        XCTAssertThrowsError(try AlertForm.validate(above: "", below: "", move: "30", price: nil).get())
        XCTAssertThrowsError(try AlertForm.validate(above: "110 000", below: "", move: "", price: 120_000).get())
        XCTAssertThrowsError(try AlertForm.validate(above: "", below: "125 000", move: "", price: 120_000).get())
        XCTAssertEqual(try? AlertForm.validate(above: "", below: "", move: "", price: 120_000).get(), AlertForm.Values())
    }
}

final class LoginTests: XCTestCase {
    func testFormLikeTheLoginPage() {
        XCTAssertEqual(String(data: LoginModel.form("a b&c=é"), encoding: .utf8),
                       "username=GoldApp&password=a%20b%26c%3D%C3%A9")
    }

    func testSessionCookieRead() {
        let r = HTTPURLResponse(url: URL(string: "https://mon-cours-or.onrender.com/login")!, statusCode: 303,
                                httpVersion: "HTTP/1.1",
                                headerFields: ["Set-Cookie": "goldapp_session=abc123; Path=/; Max-Age=15552000; HttpOnly; SameSite=Lax; Secure",
                                               "Location": "/"])!
        XCTAssertEqual(Session.cookie(from: r), "abc123")
        let out = HTTPURLResponse(url: URL(string: "https://mon-cours-or.onrender.com/logout")!, statusCode: 303,
                                  httpVersion: "HTTP/1.1", headerFields: ["Set-Cookie": "goldapp_session=; Path=/; Max-Age=0"])!
        XCTAssertNil(Session.cookie(from: out))
    }
}

/// Serveur simulé : réponses données d’avance, dans l’ordre.
final class FakeServer: URLProtocol {
    static var replies: [(Int, String)] = []
    static var error: URLError?
    static var calls = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        if let e = Self.error, Self.calls == 1 {
            client?.urlProtocol(self, didFailWithError: e)
            return
        }
        let (status, body) = Self.replies.isEmpty ? (500, "{}") : Self.replies.removeFirst()
        let r = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RetryTests: XCTestCase {
    private func client(attempts: Int = 3) -> APIClient {
        APIClient(timeout: 5, attempts: attempts, delays: [0, 0], protocolClasses: [FakeServer.self])
    }

    override func setUp() {
        FakeServer.replies = []
        FakeServer.error = nil
        FakeServer.calls = 0
    }

    func testRenderWakingThenAnswer() async throws {
        FakeServer.replies = [(503, "{}"), (502, ""), (200, #"{"price":1,"updatedAt":null}"#)]
        let spot = try await client().json(SpotDTO.self, client().request("/api/spot", auth: false))
        XCTAssertEqual(spot.price, 1)
        XCTAssertEqual(FakeServer.calls, 3)
    }

    func testTimeoutThenAnswer() async throws {
        FakeServer.error = URLError(.timedOut)
        FakeServer.replies = [(200, #"{"price":2}"#)]
        let spot = try await client().json(SpotDTO.self, client().request("/api/spot", auth: false))
        XCTAssertEqual(spot.price, 2)
        XCTAssertEqual(FakeServer.calls, 2)
    }

    func testPasswordNeededIsNotRetried() async {
        FakeServer.replies = [(401, #"{"error":"Mot de passe requis"}"#)]
        do {
            _ = try await client().json(SpotDTO.self, client().request("/api/spot", auth: false))
            XCTFail("401 attendu")
        } catch {
            XCTAssertEqual(error as? APIError, .needsLogin)
        }
        XCTAssertEqual(FakeServer.calls, 1)
    }

    func testOfflineFailsAtOnce() async {
        FakeServer.error = URLError(.notConnectedToInternet)
        do {
            _ = try await client().json(SpotDTO.self, client().request("/api/spot", auth: false))
            XCTFail("hors connexion attendu")
        } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
        XCTAssertEqual(FakeServer.calls, 1)
    }

    func testServerErrorMessageKept() async {
        FakeServer.replies = [(503, #"{"error":"Or pur indisponible"}"#)]
        do {
            _ = try await client(attempts: 1).json(SpotDTO.self, client().request("/api/spot", auth: false))
            XCTFail("503 attendu")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Or pur indisponible")
        }
    }
}

final class DemoTests: XCTestCase {
    func testDemoLooksLikeRealData() {
        for p in Period.allCases {
            let s = DemoData.snapshot(p)
            XCTAssertTrue(s.gold.hasCurve)
            XCTAssertTrue(s.silver.hasCurve)
            XCTAssertGreaterThan(s.gold.price ?? 0, 100_000)
        }
    }
}
