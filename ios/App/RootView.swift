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
                    WebModuleView(view: "rachat", title: "Rachat")
                        .tabItem { Label("Rachat", systemImage: "list.bullet.rectangle") }
                        .tag(AppModel.Tab.rachat)
                    WebModuleView(view: "chiffres", title: "Chiffres")
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
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
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

/// Ligne d’état : à jour, serveur qui se réveille, hors connexion avec l’heure des données gardées.
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
            case .fresh(let d):
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.up)
                Text("À jour à " + Fmt.time(d))
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
    /// Fond d’Orbismini derrière une liste ou un défilement.
    func orbisminiBackground() -> some View {
        scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
    }
}
