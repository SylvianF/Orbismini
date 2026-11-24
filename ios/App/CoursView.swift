import SwiftUI

/// Onglet Cours : la page « Cours » du site (courbes de l’or et de l’argent, pièces et lingots).
struct CoursView: View {
    var body: some View {
        NavigationStack {
            WebModuleView(view: "cours", title: "Cours").tabHeader("Cours")
        }
    }
}
