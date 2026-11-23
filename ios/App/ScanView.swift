import SwiftUI

/// PC d’Orbis vus depuis ce téléphone (même connexion internet que le magasin).
@MainActor
final class PeersModel: ObservableObject {
    struct Peer: Decodable, Identifiable {
        let pc: String
        let name: String
        var id: String { pc }
    }
    private struct Answer: Decodable { let peers: [Peer] }

    @Published var peers: [Peer]?
    @Published var error: String?

    func load() async {
        if Config.isDemo {
            peers = [Peer(pc: "exemple", name: "PC Accueil (exemple)")]
            return
        }
        do {
            let client = APIClient.app
            peers = try await client.json(Answer.self, client.request("/api/orbiscan/peers")).peers
            error = nil
        } catch APIError.needsLogin {
            AppModel.shared.needLogin()
        } catch {
            self.error = error.localizedDescription
        }
    }

    var summary: String {
        if let error, peers == nil { return error }
        guard let peers else { return "Recherche des PC du magasin…" }
        switch peers.count {
        case 0: return "Aucun PC du magasin sur cette connexion"
        case 1: return "Relié à " + peers[0].name
        default: return peers.count.description + " PC du magasin : " + peers.map(\.name).joined(separator: ", ")
        }
    }
    var found: Bool { !(peers ?? []).isEmpty }
}

/// Écran Scan : tout ce qui passe par l’appareil photo.
struct ScanView: View {
    @StateObject private var model = PeersModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    NavigationLink {
                        WebModuleView(path: "/orbiscan/", title: "Orbiscan")
                    } label: {
                        ScanCard(icon: "doc.viewfinder", title: "Orbiscan",
                                 text: "Pièce d’identité, RIB, facture, pièce : envoyées chiffrées au PC",
                                 status: model.summary, ok: model.found)
                    }
                    NavigationLink {
                        WebModuleView(view: "scan", title: "Pièce inconnue")
                    } label: {
                        ScanCard(icon: "questionmark.circle", title: "Pièce inconnue",
                                 text: "Photo de la pièce dans un cercle, recherche dans le catalogue")
                    }
                    NavigationLink {
                        WebModuleView(view: "ticket", title: "Ticket de frais")
                    } label: {
                        ScanCard(icon: "fuelpump", title: "Ticket de frais",
                                 text: "Carburant, péage, restaurant, parking")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .orbisminiBackground()
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.load() }
            .task { await model.load() }
        }
    }
}

private struct ScanCard: View {
    let icon: String
    let title: String
    let text: String
    var status: String? = nil
    var ok = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.gold)
                .frame(width: 44, height: 44)
                .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                Text(text).font(.footnote).foregroundStyle(Theme.muted)
                if let status {
                    Label(status, systemImage: ok ? "checkmark.circle.fill" : "wifi.exclamationmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ok ? Theme.up : Theme.muted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
        }
        .padding(14)
        .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line.opacity(0.6), lineWidth: 0.5))
    }
}
