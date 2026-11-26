import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class AlertModel: ObservableObject {
    @Published var state: AlertState?
    @Published var above = ""
    @Published var below = ""
    @Published var move = ""
    @Published var message: String?
    @Published var bad = false
    @Published var busy = false
    @Published var permission: UNAuthorizationStatus = .notDetermined

    func load() async {
        permission = await Push.status()
        if Config.isDemo {
            fill(DemoData.alert)
            return
        }
        busy = true
        defer { busy = false }
        do {
            fill(try await DataService.alert(client: .app))
            message = nil
        } catch APIError.needsLogin {
            AppModel.shared.needLogin()
        } catch {
            say(error.localizedDescription, bad: true)
        }
    }

    func save(clear: Bool = false) async {
        let values: AlertForm.Values
        if clear {
            values = .init()
        } else {
            switch AlertForm.validate(above: above, below: below, move: move, price: state?.price) {
            case .failure(let e): return say(e.message, bad: true)
            case .success(let v): values = v
            }
        }
        guard !Config.isDemo else { return say("Exemple : rien n’est enregistré.", bad: false) }
        busy = true
        defer { busy = false }
        let settings = AlertSettings(above: values.above, below: values.below, move: values.move,
                                     updated: DateParser.iso(), hits: state?.hits ?? [])
        do {
            fill(try await DataService.alert(client: .app, settings: settings))
            say(values == .init() ? "Alerte retirée." : "Alerte enregistrée.", bad: false)
        } catch APIError.needsLogin {
            AppModel.shared.needLogin()
        } catch {
            say(error.localizedDescription, bad: true)
        }
    }

    func allowNotifications() async {
        _ = await Push.ask()
        permission = await Push.status()
    }

    private func fill(_ s: AlertState) {
        state = s
        above = s.above.map { Fmt.decimal($0) } ?? ""
        below = s.below.map { Fmt.decimal($0) } ?? ""
        move = s.move.map { Fmt.decimal($0, digits: 1, minDigits: 0) } ?? ""
    }

    private func say(_ text: String, bad: Bool) {
        message = text
        self.bad = bad
    }
}

struct AlerteView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = AlertModel()

    var body: some View {
        Form {
            priceSection
            settingsSection
            actionsSection
            hitsSection
            notifications
        }
        .orbisminiBackground()
        .navigationTitle("Alerte de cours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() } } }
        .task { await model.load() }
    }

    @ViewBuilder
    private var priceSection: some View {
        if let price = model.state?.price {
            Section {
                LabeledContent("Cours actuel", value: Fmt.kilo(price))
            } footer: {
                Text("Or pur, BullionVault. Le serveur contrôle le cours toutes les 10 minutes en semaine.")
            }
        }
    }

    private var settingsTitle: String {
        model.state?.mode == "orbis" ? "Alerte commune avec Orbis" : "Alerte de ce téléphone"
    }

    private var settingsSection: some View {
        Section {
            field("Au-dessus de", text: $model.above, unit: "€/kg", hint: "121 000")
            field("En dessous de", text: $model.below, unit: "€/kg", hint: "112 000")
            field("Variation sur 24 h", text: $model.move, unit: "%", hint: "2")
        } header: {
            Text(settingsTitle)
        } footer: {
            Text("Un seuil passé sonne une fois puis s’efface. La variation reste en place (une alerte par sens toutes les 20 heures au plus).")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await model.save() }
            } label: {
                HStack {
                    Text("Enregistrer l’alerte").bold()
                    Spacer()
                    if model.busy { ProgressView() }
                }
            }
            .disabled(model.busy)
            if model.state?.isActive == true {
                Button("Retirer l’alerte", role: .destructive) { Task { await model.save(clear: true) } }
                    .disabled(model.busy)
            }
            if let message = model.message {
                Text(message).font(.footnote).foregroundStyle(model.bad ? Theme.down : Theme.up)
            }
        }
    }

    private var lastHits: [AlertState.Hit] { Array((model.state?.hits ?? []).reversed().prefix(5)) }

    @ViewBuilder
    private var hitsSection: some View {
        if !lastHits.isEmpty {
            Section("Dernières alertes") {
                ForEach(lastHits) { h in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title).font(.subheadline)
                        Text(Self.detail(h)).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private static func detail(_ h: AlertState.Hit) -> String {
        var parts: [String] = []
        if let p = h.price { parts.append("Cours " + Fmt.kilo(p)) }
        if let d = DateParser.parse(h.at) { parts.append(Fmt.dayTime(d)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var notifications: some View {
        Section {
            switch model.permission {
            case .notDetermined:
                Button("Recevoir les alertes sur cet iPhone") { Task { await model.allowNotifications() } }
            case .denied:
                Text("Notifications refusées pour Orbismini.")
                Button("Ouvrir les réglages de l’iPhone") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            default:
                if Push.serverSends {
                    Label("Les alertes arrivent dans l’application.", systemImage: "checkmark.circle")
                        .foregroundStyle(Theme.up)
                } else {
                    Text("Le serveur n’envoie pas encore les notifications de l’application : les alertes passent toujours par ntfy.")
                        .font(.footnote)
                }
            }
            if !Push.serverSends, let channel = model.state?.channel {
                LabeledContent("Canal ntfy") {
                    Text(channel).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        } header: {
            Text("Notifications")
        }
    }

    private func field(_ title: String, text: Binding<String>, unit: String, hint: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(hint, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
            Text(unit).foregroundStyle(Theme.muted)
        }
    }
}
