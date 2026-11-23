import SwiftUI

/// Onglet Cours : la page « Cours » du site (courbes de l’or et de l’argent, pièces et lingots),
/// avec l’alerte de cours et les réglages de l’application en haut.
struct CoursView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        NavigationStack {
            WebModuleView(view: "cours", title: "Cours")
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
}
