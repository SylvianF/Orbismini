import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var widgetKey = Secrets.get(.widgetKey) ?? ""
    @State private var saved = false

    var body: some View {
        Form {
            Section("Connexion") {
                LabeledContent("Serveur", value: Config.host)
                Button("Verrouiller l’application", role: .destructive) {
                    app.logout()
                    dismiss()
                }
            }
            Section {
                SecureField("Clé du widget (facultative)", text: $widgetKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer la clé") {
                    Secrets.set(.widgetKey, widgetKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    WidgetCenter.shared.reloadAllTimelines()
                    saved = true
                }
                if saved { Text("Clé enregistrée.").font(.footnote).foregroundStyle(Theme.up) }
                NavigationLink("Aperçu du widget") { WidgetPreviewView() }
            } header: {
                Text("Widget")
            } footer: {
                Text("Sans clé, le widget lit les cours avec la connexion de l’application. Avec la clé (la même que GOLDAPP_WIDGET_KEY sur Render), il les lit même après un verrouillage.")
            }
            Section("Données gardées") {
                Button("Effacer les cours gardés") {
                    SharedStore.clearCache()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            Section {
                Link("Ouvrir Orbismini dans Safari", destination: Config.baseURL)
                LabeledContent("Version", value: version)
            }
        }
        .orbisminiBackground()
        .navigationTitle("Réglages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
    }
}

/// Le widget tel qu’il paraît sur l’écran d’accueil, aux trois tailles (mêmes vues que le widget).
struct WidgetPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var metal: Metal = .gold

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("Métal", selection: $metal) {
                    Text("Or").tag(Metal.gold)
                    Text("Argent").tag(Metal.silver)
                }
                .pickerStyle(.segmented)
                ForEach(WidgetSize.allCases, id: \.self) { size in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(size.title).font(.caption).foregroundStyle(Theme.muted)
                        WidgetContent(snapshot: snapshot, metal: metal, size: size)
                            .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
                            .frame(width: size.previewSize.width, height: size.previewSize.height)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                Text(Config.isDemo || SharedStore.snapshot(.day) == nil ? "Données d’exemple." : "Derniers cours gardés sur l’iPhone.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .orbisminiBackground()
        .navigationTitle("Aperçu du widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
    }

    private var snapshot: Snapshot {
        Config.isDemo ? DemoData.snapshot() : (SharedStore.snapshot(.day) ?? DemoData.snapshot())
    }
}
