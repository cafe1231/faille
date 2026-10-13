import LoLKit
import SwiftUI

/// Destination de navigation : le Détail d'un match (branchée dans `RootView` à la Task 11).
struct MatchRoute: Hashable {
    let matchId: String
}

/// Onglet Matchs, version B (spec §5.1) : « Mes équipes », une carte Vitrail par équipe suivie, tirer pour rafraîchir.
struct MatchesView: View {
    @Environment(AppStore.self) private var store
    let openTeams: () -> Void

    var body: some View {
        let cards = store.cards
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Mes équipes", subtitle: cards.isEmpty ? Format.followCount(0) : Format.cardsSubtitle(cards))
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                }
                if cards.isEmpty {
                    WelcomeCard(action: openTeams)
                } else {
                    ForEach(cards) { card in
                        TeamCardView(card: card)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.refreshNow() }
        .abyssBackground()
        .navigationTitle("Matchs")
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Aucune équipe suivie : message d'accueil et bouton vers l'onglet Équipes (spec §5.1).
struct WelcomeCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bienvenue dans Faille")
                .font(Typo.headline)
            Text("Suis tes équipes pour voir ici leurs matchs en direct, le prochain et le dernier résultat.")
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
            Button(action: action) {
                HStack(spacing: 6) {
                    IconView(icon: .star, size: 15)
                    Text("Choisir mes équipes")
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.abyss)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Palette.accent, in: Capsule())
                .shadow(color: Palette.accent.opacity(0.35), radius: 9, y: 6)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }
}

#Preview {
    NavigationStack { MatchesView(openTeams: {}) }.environment(AppStore(preview: .standard))
}
