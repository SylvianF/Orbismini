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
        // Onglets du site cachés (l’application a les siens) ; impression confiée à l’iPhone.
        scripts.addUserScript(WKUserScript(
            source: """
            (function(){var s=document.createElement('style');
            s.textContent='.views,header.top,#splash{display:none!important}';
            (document.head||document.documentElement).appendChild(s);
            window.print=function(){window.webkit.messageHandlers.imprimer.postMessage(1)};})();
            """,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        scripts.add(WeakHandler(context.coordinator), name: "imprimer")
        // Boutons « Photographier… » : appareil photo de l’application (cercle pour les pièces,
        // scanner de documents pour pièce d’identité, RIB et facture), dans la page et dans Orbiscan.
        scripts.addUserScript(WKUserScript(source: Self.photoBridge, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        scripts.addScriptMessageHandler(WeakReplyHandler(context.coordinator), contentWorld: .page, name: "photo")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(Theme.bg2)
        web.scrollView.backgroundColor = UIColor(Theme.bg2)
        web.allowsBackForwardNavigationGestures = false
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
      function kind(i) {
        if (i.closest('#piece-sides, .cs-shot')) return 'piece';
        if (i.closest('#id-sides')) return 'identite';
        if (i.closest('#rib-side')) return 'rib';
        if (i.closest('#facture-side')) return 'facture';
        return null;
      }
      document.addEventListener('click', function (e) {
        var i = e.target;
        if (!(i instanceof HTMLInputElement) || i.type !== 'file') return;
        var k = kind(i);
        if (!k) return;
        e.preventDefault(); e.stopPropagation();
        h.postMessage({ kind: k }).then(function (b64) {
          if (!b64) return;
          var bin = atob(b64), bytes = new Uint8Array(bin.length);
          for (var n = 0; n < bin.length; n++) bytes[n] = bin.charCodeAt(n);
          var dt = new DataTransfer();
          dt.items.add(new File([bytes], 'photo.jpg', { type: 'image/jpeg', lastModified: Date.now() }));
          i.files = dt.files;
          i.dispatchEvent(new Event('change', { bubbles: true }));
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
            var r = URLRequest(url: URL(string: path, relativeTo: Config.baseURL)?.absoluteURL ?? Config.baseURL)
            r.timeoutInterval = 70   // Render endormi : jusqu’à une minute pour se réveiller
            web?.load(r)
        }

        /// Ouvre la vue du site voulue (mobile.js : onglets data-view, cartes data-open de l’écran Scan).
        private func showView(_ web: WKWebView) {
            guard let view, web.url?.host == Config.host, web.url?.path == "/" || web.url?.path == "" else { return }
            let js = "(function(){var v='\(view)';if(document.body.dataset.view===v)return;"
                + "var b=document.querySelector('.views button[data-view=\"'+v+'\"]')||document.querySelector('[data-open=\"'+v+'\"]');"
                + "if(b)b.click();})()"
            web.evaluateJavaScript(js)
        }

        // Prise de vue demandée par la page (photoBridge) : la photo en base64, ou rien si annulée.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping (Any?, String?) -> Void) {
            let raw = (message.body as? [String: Any])?["kind"] as? String ?? ""
            guard let kind = PhotoKind(rawValue: raw), let web, let host = Self.top(of: web) else {
                return replyHandler(nil, nil)
            }
            Task { @MainActor in
                PhotoCapture.shared.take(kind, from: host) { data in
                    replyHandler(data?.base64EncodedString(), nil)
                }
            }
        }

        static func top(of web: WKWebView) -> UIViewController? {
            guard var top = web.window?.rootViewController else { return nil }
            while let next = top.presentedViewController { top = next }
            return top
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) { showView(web) }

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

        // window.print() du site (estimation imprimée) : impression de l’iPhone.
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "imprimer", let web else { return }
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
