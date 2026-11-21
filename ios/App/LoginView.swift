import SwiftUI

@MainActor
final class LoginModel: ObservableObject {
    @Published var password = ""
    @Published var error: String?
    @Published var status: LoadStatus = .idle
    private var waking: NSObjectProtocol?

    init() {
        waking = NotificationCenter.default.addObserver(forName: .serverWaking, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if self?.status == .loading { self?.status = .waking }
            }
        }
    }

    deinit {
        if let waking { NotificationCenter.default.removeObserver(waking) }
    }

    /// Même formulaire que la page de connexion du site (POST /login).
    static func form(_ password: String) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        let encoded = password.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return Data(("username=GoldApp&password=" + encoded).utf8)
    }

    func login() async -> Bool {
        guard !password.isEmpty else { return false }
        error = nil
        status = .loading
        defer { if status == .loading || status == .waking { status = .idle } }
        let client = APIClient.app
        let req = client.request("/login", method: "POST", form: Self.form(password), auth: false)
        do {
            let (data, http) = try await client.send(req, followRedirects: false)
            switch http.statusCode {
            case 300..<400:
                guard let cookie = Session.cookie(from: http) else {
                    error = "Connexion refusée par le serveur."
                    return false
                }
                Session.store(cookie: cookie)
                password = ""
                return true
            case 404:
                // Serveur sans mot de passe (GOLDAPP_PASSWORD absent) : l’application est ouverte.
                Session.markOpenServer()
                return true
            default:
                let page = String(data: data, encoding: .utf8) ?? ""
                error = page.contains("incorrect") ? "Mot de passe incorrect." : "Erreur du serveur (\(http.statusCode))."
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct LoginView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var model = LoginModel()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [Theme.gold.opacity(0.12), .clear], center: UnitPoint(x: 0.5, y: 0.32),
                           startRadius: 10, endRadius: 320)
                .background(Theme.bg2)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image("Logo")
                    .resizable()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                (Text("Orbis").foregroundStyle(Theme.gold) + Text("mini").foregroundStyle(Theme.text))
                    .font(.system(size: 28, weight: .semibold))
                Text("Saisis le mot de passe pour ouvrir l’application.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                SecureField("Mot de passe", text: $model.password)
                    .textContentType(.password)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Color(hex: 0x101C24), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? Theme.gold : Theme.line, lineWidth: focused ? 2 : 1))
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(go)
                if let error = model.error {
                    Text(error).font(.subheadline).foregroundStyle(Color(hex: 0xFFB3AD))
                }
                Button(action: go) {
                    HStack {
                        if model.status == .loading || model.status == .waking { ProgressView().tint(Theme.bg2) }
                        Text("Ouvrir").bold()
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .background(Theme.gold, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color(hex: 0x18242B))
                .disabled(model.password.isEmpty || model.status == .loading || model.status == .waking)
                if model.status == .waking { StatusLine(status: .waking) }
            }
            .frame(maxWidth: 340)
            .padding(.horizontal, 16)
        }
        .onAppear { focused = Config.startScreen != "connexion" }
    }

    private func go() {
        Task {
            if await model.login() { app.didLogin() }
        }
    }
}
