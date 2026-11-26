import LocalAuthentication
import SwiftUI

/// Verrou Face ID : l’application montre des chiffres, des marges et des montants de virement.
/// Quand elle revient après plus de 30 secondes en arrière-plan (ou à son lancement), elle demande
/// Face ID, avec le code de l’iPhone en secours. Réglable téléphone par téléphone (Réglages),
/// allumé par défaut. Dans le sélecteur d’applications, son contenu est caché.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()
    static let key = "verrouFaceID"
    static let grace: TimeInterval = 30

    @Published private(set) var locked: Bool
    @Published private(set) var hidden = false
    @Published private(set) var refused = false
    private var leftAt: Date?
    private var asking = false

    /// Face ID (ou Touch ID, ou le code) disponible sur ce téléphone.
    static var available: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    var enabled: Bool {
        get { !Config.isDemo && (SharedStore.defaults.object(forKey: Self.key) as? Bool ?? true) && Self.available }
        set {
            SharedStore.defaults.set(newValue, forKey: Self.key)
            objectWillChange.send()
        }
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    private init() {
        locked = false
        locked = enabled
    }

    /// L’application passe en arrière-plan : contenu caché (sélecteur d’applications), heure notée.
    func wentAway() {
        guard enabled else { return }
        leftAt = Date()
        hidden = true
    }

    /// L’application revient au premier plan : verrou si l’absence a duré, sinon on rouvre.
    func cameBack() {
        guard enabled else {
            locked = false
            hidden = false
            return
        }
        if let leftAt, Date().timeIntervalSince(leftAt) > Self.grace { locked = true }
        leftAt = nil
        hidden = false
        if locked { unlock() }
    }

    func unlock() {
        guard locked, !asking else { return }
        asking = true
        refused = false
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Ouvrir Orbismini") { ok, _ in
            Task { @MainActor in
                self.asking = false
                if ok {
                    self.locked = false
                } else {
                    self.refused = true
                }
            }
        }
    }
}

/// Écran du verrou : logo, et un bouton pour redemander Face ID après une annulation.
struct LockScreen: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Theme.bg2.ignoresSafeArea()
            VStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                (Text("Orbis").foregroundColor(Theme.gold) + Text("mini").foregroundColor(Theme.text))
                    .font(.system(size: 26, weight: .semibold))
                if lock.locked {
                    Button {
                        lock.unlock()
                    } label: {
                        Label("Déverrouiller avec " + lock.biometryName, systemImage: "faceid")
                            .bold()
                            .frame(maxWidth: 280, minHeight: 48)
                    }
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Theme.onGold)
                    .padding(.top, 10)
                    if lock.refused {
                        Text("Déverrouillage annulé.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }
}
