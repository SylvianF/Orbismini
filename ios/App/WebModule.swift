import SwiftUI
import UIKit
import WebKit

/// Session du site dans les pages web de l’application : même cookie que l’application native.
/// Connexion faite sur la page web (cookie expiré) : reprise par l’application, et l’inverse.
final class WebSession: NSObject, WKHTTPCookieStoreObserver {
    static let shared = WebSession()

    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    func start() {
        store.add(self)
        pushCookie()
    }

    func pushCookie(then done: (() -> Void)? = nil) {
        guard let value = Secrets.get(.session),
              let cookie = HTTPCookie(properties: [
                  .name: Config.sessionCookie, .value: value, .domain: Config.host, .path: "/",
                  .secure: "TRUE", .expires: Date().addingTimeInterval(180 * 86_400),
              ])
        else {
            done?()
            return
        }
        store.setCookie(cookie) { done?() }
    }

    func clearCookie() {
        store.getAllCookies { cookies in
            for c in cookies where c.name == Config.sessionCookie { self.store.delete(c) }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { cookies in
            guard let c = cookies.first(where: { $0.name == Config.sessionCookie && $0.domain.hasSuffix(Config.host) }),
                  !c.value.isEmpty, c.value != Secrets.get(.session)
            else { return }
            Session.store(cookie: c.value)
            Task { @MainActor in
                if !AppModel.shared.loggedIn { AppModel.shared.didLogin() }
            }
        }
    }
}

/// Module du site d’Orbismini (Pièce inconnue, Ticket, Rachat, Chiffres, liste des cours, Orbiscan)
/// dans l’application. L’en-tête et la barre d’onglets du site sont cachés : l’application a les
/// siens. Rien ne change pour le site lui-même.
struct WebModuleView: View {
    var view: String? = nil
    var path = "/"
    let title: String

    var body: some View {
        WebPage(view: view, path: path)
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.bg2.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebPage: UIViewRepresentable {
    let view: String?
    let path: String

    func makeCoordinator() -> Coordinator { Coordinator(view: view, path: path) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let scripts = config.userContentController
        // Même identifiant de téléphone que l’application : l’alerte du site et celle de l’application ne font qu’une.
        // Même thème que l’application (theme.js du site lit cette clé à l’ouverture).
        scripts.addUserScript(WKUserScript(
            source: "try{localStorage.setItem('orbismini-appareil','\(Secrets.deviceID)');"
                + "localStorage.setItem('orbismini-theme','\(ThemeChoice.current.rawValue)')}catch(e){}",
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // Onglets du site cachés dès le début (l’application a les siens) ; impression confiée à l’iPhone.
        // Page remontée au plus haut : ni la ligne « Dernière actualisation » (elle paraît dans la
        // pastille quand on tire l’écran vers le bas), ni les marges prévues pour les onglets du site.
        scripts.addUserScript(WKUserScript(
            source: """
            (function(){var s=document.createElement('style');
            s.textContent='.views,header.top,#splash,.fresh-text{display:none!important}'
              +'main{padding-top:6px!important;padding-bottom:calc(env(safe-area-inset-bottom) + 16px)!important}';
            document.documentElement.appendChild(s);
            window.print=function(){window.webkit.messageHandlers.imprimer.postMessage(1)};})();
            """,
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.add(WeakHandler(context.coordinator), name: "imprimer")
        // « Envoyer au client » (print.js) : PDF de l’estimation, SMS ou e-mail (EstimateShare).
        scripts.add(WeakHandler(context.coordinator), name: "partager")
        // Photo d’une pièce de monnaie (cercle) ou d’une pièce d’identité (cadre, recto puis verso) :
        // appareil photo de l’application. RIB et facture : appareil photo normal de l’iPhone.
        scripts.addUserScript(WKUserScript(source: Self.photoBridge, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        scripts.addScriptMessageHandler(WeakReplyHandler(context.coordinator), contentWorld: .page, name: "photo")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(Theme.bg2)
        web.scrollView.backgroundColor = UIColor(Theme.bg2)
        // Glisser du bord gauche : retour à l’écran précédent du site (pièce ouverte → liste des cours,
        // pièce inconnue → Scan…), comme le bouton retour de Safari.
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        #if DEBUG
        web.isInspectable = true
        #endif
        let coordinator = context.coordinator
        coordinator.web = web
        WebSession.shared.pushCookie { coordinator.loadHome() }
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    /// Remplace le sélecteur de photo du site par la prise de vue de l’application, puis remet la
    /// photo dans le champ, comme si elle venait du sélecteur : la page continue comme avant.
    static let photoBridge = """
    (function(){
      if (window.__orbisminiPhoto) return; window.__orbisminiPhoto = 1;
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.photo;
      if (!h) return;
      function put(i, b64) {
        var bin = atob(b64), bytes = new Uint8Array(bin.length);
        for (var n = 0; n < bin.length; n++) bytes[n] = bin.charCodeAt(n);
        var dt = new DataTransfer();
        dt.items.add(new File([bytes], 'photo.jpg', { type: 'image/jpeg', lastModified: Date.now() }));
        i.files = dt.files;
        i.dispatchEvent(new Event('change', { bubbles: true }));
      }
      // Pièce d'identité : recto et verso sont pris d'affilée dans l'application. Après le recto, la page
      // demande d'elle-même le verso : il lui est donné sans rouvrir l'appareil photo (verso), ou la
      // demande est ignorée s'il n'y a pas de verso (passeport, arrêt).
      var verso = null, sansVerso = 0;
      document.addEventListener('click', function (e) {
        var i = e.target;
        if (!(i instanceof HTMLInputElement) || i.type !== 'file') return;
        var k = i.closest('#piece-sides, .cs-shot') ? 'piece' : i.closest('#id-sides') ? 'identite' : null;
        if (!k) return;
        e.preventDefault(); e.stopPropagation();
        var box = i.closest('[data-side]'), side = box ? box.dataset.side : '';
        if (side === 'verso') {
          if (verso && Date.now() - verso.at < 60000) {
            var b = verso.b64; verso = null;
            setTimeout(function () { put(i, b); }, 0);
            return;
          }
          if (Date.now() < sansVerso) { sansVerso = 0; return; }
        }
        verso = null; sansVerso = 0;
        var deux = side === 'recto' && !document.querySelector('#id-sides [data-side=verso] .state.ok');
        h.postMessage({ kind: k, deux: deux }).then(function (r) {
          if (!r || !r.pages || !r.pages.length) return;
          if (deux) {
            if (r.pages.length > 1) verso = { b64: r.pages[1], at: Date.now() };
            else sansVerso = Date.now() + 3000;
          }
          put(i, r.pages[0]);
          if (r.fin === 'passeport') {
            // « Passeport : une seule page » de la page, dès que le recto est envoyé.
            var tries = 0, t = setInterval(function () {
              var one = document.getElementById('one-page');
              if (one && !one.hidden) { clearInterval(t); one.click(); }
              else if (++tries > 100) clearInterval(t);
            }, 200);
          }
        }).catch(function () {});
      }, true);
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
        WKScriptMessageHandlerWithReply {
        let view: String?
        let path: String
        weak var web: WKWebView?

        init(view: String?, path: String) {
            self.view = view
            self.path = path
        }

        func loadHome() {
            // « ?vue=rachat » : le site s’ouvre directement sur la vue voulue (mobile.js).
            let address = view.map { $0 == "cours" ? path : path + "?vue=" + $0 } ?? path
            var r = URLRequest(url: URL(string: address, relativeTo: Config.baseURL)?.absoluteURL ?? Config.baseURL)
            r.timeoutInterval = 70   // Render endormi : jusqu’à une minute pour se réveiller
            web?.load(r)
        }

        // Prise de vue demandée par la page (photoBridge) : la photo en base64, ou rien si annulée.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            let body = message.body as? [String: Any]
            guard let kind = PhotoKind(rawValue: body?["kind"] as? String ?? ""), let web, let host = Self.top(of: web) else {
                return replyHandler(nil, nil)
            }
            let both = body?["deux"] as? Bool ?? false
            Task { @MainActor in
                PhotoCapture.shared.take(kind, bothSides: both, from: host) { result in
                    let answer: [String: Any] = ["pages": result.photos.map { $0.base64EncodedString() }, "fin": result.end]
                    replyHandler(answer, nil)
                }
            }
        }

        static func top(of web: WKWebView) -> UIViewController? {
            guard var top = web.window?.rootViewController else { return nil }
            while let next = top.presentedViewController { top = next }
            return top
        }

        // Retour sur « / » sans la vue (après la page du mot de passe, par exemple) : on la redemande.
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            guard let view, view != "cours", let url = web.url, url.host == Config.host, url.path == "/",
                  !(url.query ?? "").contains("vue=") else { return }
            loadHome()
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            web.loadHTMLString(Self.offlinePage(error.localizedDescription), baseURL: nil)
        }

        // Liens vers d’autres sites (Numista, Gold.fr…) : ouverts dans Safari.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url, let scheme = url.scheme, ["http", "https"].contains(scheme),
               url.host != Config.host, action.targetFrame?.isMainFrame ?? true {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            if action.request.url?.absoluteString == "orbismini://recharger" {
                loadHome()
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                if url.host == Config.host { web.load(action.request) } else { UIApplication.shared.open(url) }
            }
            return nil
        }

        // Appareil photo (Orbiscan, pièce, ticket) : accordé pour le site d’Orbismini seulement.
        func webView(_ web: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == Config.host ? .grant : .prompt)
        }

        // Fenêtres alert() et confirm() du site.
        func webView(_ web: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(a, from: web) ?? completionHandler()
        }

        func webView(_ web: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(a, from: web) ?? completionHandler(false)
        }

        func webView(_ web: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            a.addTextField { $0.text = defaultText }
            a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(nil) })
            a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
            present(a, from: web) ?? completionHandler(nil)
        }

        // window.print() du site (estimation imprimée) : impression de l’iPhone ;
        // « Envoyer au client » : PDF de la même fiche, puis SMS ou e-mail au client.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let web else { return }
            if message.name == "partager" {
                let body = message.body as? [String: Any] ?? [:]
                let text = { (k: String) in (body[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                let (client, phone, email) = (text("client"), text("phone"), text("email"))
                let pdf = Data(base64Encoded: text("pdf")).flatMap { $0.starts(with: Array("%PDF".utf8)) ? $0 : nil }
                Task { @MainActor in
                    EstimateShare.shared.send(from: web, client: client, phone: phone, email: email, serverPDF: pdf)
                }
                return
            }
            guard message.name == "imprimer" else { return }
            let p = UIPrintInteractionController.shared
            let info = UIPrintInfo.printInfo()
            info.outputType = .general
            info.jobName = "Orbismini"
            p.printInfo = info
            p.printFormatter = web.viewPrintFormatter()
            p.present(animated: true)
        }

        private func present(_ controller: UIViewController, from web: WKWebView) -> Void? {
            guard var top = web.window?.rootViewController else { return nil }
            while let next = top.presentedViewController { top = next }
            top.present(controller, animated: true)
            return ()
        }

        static func offlinePage(_ why: String) -> String {
            """
            <!doctype html><html lang="fr"><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{margin:0;min-height:90vh;display:flex;align-items:center;justify-content:center;background:#121d25;
            color:#edf2f5;font:16px -apple-system,system-ui;text-align:center;padding:24px}p{color:#b5c7d3}
            a{display:inline-block;margin-top:12px;padding:12px 22px;border-radius:12px;background:#e9bf75;color:#18242b;
            font-weight:600;text-decoration:none}</style></head><body><div><h2>Page indisponible</h2>
            <p>\(why.replacingOccurrences(of: "<", with: "&lt;"))</p><p>Le serveur se réveille peut-être (jusqu’à une minute).</p>
            <a href="orbismini://recharger">Réessayer</a></div></body></html>
            """
        }
    }
}

/// Même chose pour les messages qui attendent une réponse (photo).
private final class WeakReplyHandler: NSObject, WKScriptMessageHandlerWithReply {
    weak var target: WKScriptMessageHandlerWithReply?
    init(_ target: WKScriptMessageHandlerWithReply) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let target else { return replyHandler(nil, nil) }
        target.userContentController(c, didReceive: message, replyHandler: replyHandler)
    }
}

/// Évite que la page garde le coordinateur en vie (cycle avec WKUserContentController).
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
