import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var widgetKey = Secrets.get(.widgetKey) ?? ""
    @AppStorage(ThemeChoice.key, store: SharedStore.defaults) private var themeRaw = ThemeChoice.saphir.rawValue
    @State private var saved = false
    @AppStorage(Push.nameKey, store: SharedStore.defaults) private var phoneName = ""
    @State private var nameSent = false

    var body: some View {
        Form {
            Section {
                Picker("Thème", selection: $themeRaw) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .onChange(of: themeRaw) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
            } header: {
                Text("Thème")
            } footer: {
                Text("Les mêmes que le site et Orbis : Saphir, Onyx (noir) et Perle (clair). Le widget suit aussi.")
            }
            Section {
                TextField("Nom de ce téléphone (ex. Sylvian, Magasin)", text: $phoneName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(sendName)
                    .onChange(of: phoneName) { _, new in
                        if new.count > 40 { phoneName = String(new.prefix(40)) }
                        nameSent = false
                    }
                if nameSent { Text("Nom envoyé à Orbismini.").font(.footnote).foregroundStyle(Theme.up) }
            } header: {
                Text("Ce téléphone")
            } footer: {
                Text("Ce nom s’affiche dans Orbis, où l’on choisit quels téléphones reçoivent les demandes de virement et les transferts. Il faut que les notifications soient acceptées (cloche).")
            }
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
            if let quality = UserDefaults.standard.string(forKey: PhotoCapture.lastQualityKey) {
                Section {
                    Text(quality).font(.footnote)
                } header: {
                    Text("Dernière pièce d’identité photographiée")
                } footer: {
                    Text("Sert à régler l’alerte « photo floue » (en dessous de \(Int(PhotoQuality.minSharpness))) et « reflet » (au-dessus de \(Int(PhotoQuality.maxGlare)) %).")
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
        .onDisappear { if !nameSent { sendName() } }
    }

    private func sendName() {
        phoneName = phoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await Push.uploadKnownToken()
            nameSent = SharedStore.defaults.string(forKey: Push.errorKey) == nil && Push.serverSends
        }
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
