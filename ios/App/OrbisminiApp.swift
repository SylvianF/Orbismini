import SwiftUI
import UIKit
import UserNotifications

@main
struct OrbisminiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environment(\.locale, Fmt.fr)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .onOpenURL { model.open($0) }
        }
    }
}

/// État général : connexion, onglet affiché, écrans ouverts par une notification ou le widget.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Tab: Hashable { case cours, meteo, scan, rachat, chiffres }

    @Published var tab: Tab = .cours
    @Published var loggedIn: Bool
    @Published var showAlert = false
    @Published var showSettings = false
    @Published var showWidgetPreview = false

    private init() {
        loggedIn = Config.isDemo || Session.isOpen
        switch Config.startScreen {
        case "connexion": loggedIn = false
        case "meteo": tab = .meteo
        case "scan": tab = .scan
        case "rachat": tab = .rachat
        case "chiffres": tab = .chiffres
        case "alerte": showAlert = true
        case "reglages": showSettings = true
        case "widget": showWidgetPreview = true
        default: break
        }
    }

    /// Le serveur demande le mot de passe (cookie périmé ou mot de passe changé).
    func needLogin() {
        guard !Config.isDemo else { return }
        Session.clear()
        loggedIn = false
    }

    func didLogin() {
        loggedIn = true
        WebSession.shared.pushCookie()
        Task { await Push.uploadKnownToken() }
    }

    func logout() {
        Session.clear()
        WebSession.shared.clearCookie()
        loggedIn = false
    }

    /// orbismini://cours (widget), orbismini://alerte (notification), orbismini://meteo…
    func open(_ url: URL) {
        switch url.host ?? "" {
        case "alerte": tab = .cours; showAlert = true
        case "meteo": tab = .meteo
        case "scan": tab = .scan
        case "rachat": tab = .rachat
        case "chiffres": tab = .chiffres
        default: tab = .cours
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        WebSession.shared.start()
        if !Config.isDemo { Task { await Push.registerIfAllowed() } }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await Push.upload(token: token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        SharedStore.defaults.set(error.localizedDescription, forKey: Push.errorKey)
    }

    // Notification reçue application ouverte : affichée quand même.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // Notification touchée : écran de l’alerte.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in AppModel.shared.open(URL(string: "orbismini://alerte")!) }
        completionHandler()
    }
}

/// Notifications d’Apple : autorisation, jeton envoyé au serveur (/api/apns).
@MainActor
enum Push {
    static let tokenKey = "apnsJeton"
    static let serverKey = "apnsServeur"      // le serveur envoie-t-il les notifications de l’application ?
    static let errorKey = "apnsErreur"

    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func ask() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if ok { UIApplication.shared.registerForRemoteNotifications() }
        return ok
    }

    static func registerIfAllowed() async {
        let s = await status()
        if s == .authorized || s == .provisional || s == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    static func upload(token: String) async {
        SharedStore.defaults.set(token, forKey: tokenKey)
        SharedStore.defaults.removeObject(forKey: errorKey)
        await uploadKnownToken()
    }

    static func uploadKnownToken() async {
        guard Session.isOpen, let token = SharedStore.defaults.string(forKey: tokenKey) else { return }
        let client = APIClient.app
        let body = try? JSONSerialization.data(withJSONObject: ["token": token, "env": Config.apnsEnvironment])
        let req = client.request("/api/apns", method: "POST", json: body, headers: ["X-Appareil": Secrets.deviceID])
        struct Answer: Decodable { let enabled: Bool? }
        do {
            let answer = try await client.json(Answer.self, req)
            SharedStore.defaults.set(answer.enabled ?? false, forKey: serverKey)
        } catch APIError.server(404, _) {
            SharedStore.defaults.set(false, forKey: serverKey)   // serveur sans /api/apns (avant la mise à jour)
        } catch {
            SharedStore.defaults.set(error.localizedDescription, forKey: errorKey)
        }
    }

    static var serverSends: Bool { SharedStore.defaults.bool(forKey: serverKey) }
}
