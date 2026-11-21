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

/// Module du site d’Orbismini (Scan, Rachat, Chiffres, liste des cours) dans l’application.
/// La barre d’onglets du site est cachée : l’application a la sienne. Rien ne change pour le site.
struct WebModuleView: View {
    let view: String
    let title: String

    var body: some View {
        WebPage(view: view)
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.bg2.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebPage: UIViewRepresentable {
    let view: String

    func makeCoordinator() -> Coordinator { Coordinator(view: view) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let scripts = config.userContentController
        // Même identifiant de téléphone que l’application : l’alerte du site et celle de l’application ne font qu’une.
        scripts.addUserScript(WKUserScript(
            source: "try{localStorage.setItem('orbismini-appareil','\(Secrets.deviceID)')}catch(e){}",
            injectionTime: .atDocumentStart, forMainFrameOnly: true))
        // Onglets du site cachés (l’application a les siens) ; impression confiée à l’iPhone.
        scripts.addUserScript(WKUserScript(
            source: """
            (function(){var s=document.createElement('style');s.textContent='.views{display:none!important}';
            (document.head||document.documentElement).appendChild(s);
            window.print=function(){window.webkit.messageHandlers.imprimer.postMessage(1)};})();
            """,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        scripts.add(WeakHandler(context.coordinator), name: "imprimer")

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = UIColor(Theme.bg2)
        web.scrollView.backgroundColor = UIColor(Theme.bg2)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let view: String
        weak var web: WKWebView?

        init(view: String) { self.view = view }

        func loadHome() {
            var r = URLRequest(url: Config.baseURL)
            r.timeoutInterval = 70   // Render endormi : jusqu’à une minute pour se réveiller
            web?.load(r)
        }

        /// Ouvre la vue du site voulue (mobile.js : boutons data-view).
        private func showView(_ web: WKWebView) {
            guard web.url?.host == Config.host, web.url?.path == "/" || web.url?.path == "" else { return }
            let js = "(function(){var b=document.querySelector('.views button[data-view=\"\(view)\"]');if(b&&document.body.dataset.view!=='\(view)')b.click();})()"
            web.evaluateJavaScript(js)
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

/// Évite que la page garde le coordinateur en vie (cycle avec WKUserContentController).
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
