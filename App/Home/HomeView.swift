import SwiftUI

/// Onglet Accueil (spec saison §2) — coquille d'I1, remplie par A3.
struct HomeView: View {
    /// Espace de noms du zoom carte → Détail (`RootView`) ; nil (aperçus Xcode) : pas de zoom.
    var zoom: Namespace.ID? = nil
    /// Aller à l'onglet Équipes (carte « Suis tes équipes »).
    let openTeams: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(String(localized: "Accueil"), subtitle: String(localized: "Bientôt disponible"))
                NoteCard(icon: .clock, text: String(localized: "Bientôt disponible"))
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}
