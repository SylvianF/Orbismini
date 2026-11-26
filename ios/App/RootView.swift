import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(ThemeChoice.key, store: SharedStore.defaults) private var themeRaw = ThemeChoice.saphir.rawValue

    private var theme: ThemeChoice { ThemeChoice(rawValue: themeRaw) ?? .saphir }

    var body: some View {
        let _ = styleBars(theme)
        return Group {
            if model.loggedIn {
                TabView(selection: $model.tab) {
                    CoursView()
                        .tabItem { Label("Cours", systemImage: "chart.xyaxis.line") }
                        .tag(AppModel.Tab.cours)
                    MeteoView()
                        .tabItem { Label("Météo", systemImage: "cloud.sun") }
                        .tag(AppModel.Tab.meteo)
                    ScanView()
                        .tabItem { Label("Scan", systemImage: "viewfinder") }
                        .tag(AppModel.Tab.scan)
                    NavigationStack { WebModuleView(view: "rachat", title: "Rachat").tabHeader("Rachat") }
                        .tabItem { Label("Rachat", systemImage: "list.bullet.rectangle") }
                        .tag(AppModel.Tab.rachat)
                    NavigationStack { WebModuleView(view: "chiffres", title: "Chiffres").tabHeader("Chiffres") }
                        .tabItem { Label("Chiffres", systemImage: "chart.bar") }
                        .tag(AppModel.Tab.chiffres)
                }
                .sheet(isPresented: $model.showAlert) { NavigationStack { AlerteView() } }
                .sheet(isPresented: $model.showSettings) { NavigationStack { SettingsView() } }
                .sheet(isPresented: $model.showWidgetPreview) { NavigationStack { WidgetPreviewView() } }
            } else {
                LoginView()
            }
        }
        .background(Theme.bg2.ignoresSafeArea())
        .preferredColorScheme(theme.colorScheme)
        .tint(Theme.gold)
        // Thème changé : tout est redessiné, pages web comprises (elles relisent le thème).
        .id(themeRaw)
    }

    private func styleBars(_ theme: ThemeChoice) {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(Theme.bg2)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        // Même barre du haut partout : unie, de la couleur du fond, sans trait.
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Theme.bg2)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

// MARK: - Éléments communs

enum LoadStatus: Equatable {
    case idle
    case loading
    case waking
    case fresh(Date)
    case offline(Date?, String)
    case demo
}

/// Ligne d’état : serveur qui se réveille, hors connexion avec l’heure des données gardées ;
/// rien quand les données sont à jour.
struct StatusLine: View {
    let status: LoadStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView().controlSize(.mini)
                Text("Actualisation…")
            case .waking:
                ProgressView().controlSize(.mini)
                Text("Le serveur se réveille (jusqu’à une minute)…")
            case .fresh:
                // Tout va bien : rien à dire, la page reste au plus haut.
                EmptyView()
            case .offline(let d, let why):
                Image(systemName: "wifi.exclamationmark").foregroundStyle(Theme.down)
                Text((d.map { "Données de " + Fmt.dayTime($0) + " · " } ?? "") + why)
                    .lineLimit(2)
            case .demo:
                Image(systemName: "info.circle")
                Text("Données d’exemple (captures d’écran)")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.line.opacity(0.6), lineWidth: 0.5))
    }
}

extension View {
    /// Fond d’Orbismini derrière une liste ou un défilement : uni, le même que les pages du site.
    func orbisminiBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.bg2.ignoresSafeArea())
    }

    /// En-tête commun aux cinq onglets : petit titre centré, cloche (alerte de cours) et roue (réglages).
    func tabHeader(_ title: String) -> some View { modifier(TabHeader(title: title)) }
}

private struct TabHeader: ViewModifier {
    @EnvironmentObject private var app: AppModel
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { app.showAlert = true } label: { Image(systemName: "bell") }
                        .accessibilityLabel("Alerte de cours")
                    Button { app.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages")
                }
            }
    }
}
