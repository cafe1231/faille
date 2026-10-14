import LoLKit
import SwiftUI

/// Destination de navigation : le Détail d'un match (branchée dans `RootView` à la Task 11).
struct MatchRoute: Hashable {
    let matchId: String
}

/// Onglet Matchs, version B (spec §5.1) : « Mes équipes », une carte Vitrail par équipe suivie, tirer pour rafraîchir.
/// Finitions : cartes qui arrivent en cascade à la première apparition, insertions, retraits et changements d'ordre
/// animés, bandeau d'erreur qui glisse du haut, retour haptique à la fin du tirer-pour-rafraîchir.
struct MatchesView: View {
    @Environment(AppStore.self) private var store
    let openTeams: () -> Void
    @ReduceMotion var reduceMotion
    /// Retour haptique du tirer-pour-rafraîchir.
    @State private var haptics = HapticTrigger()
    /// La cascade d'apparition a eu lieu : une seule fois, à la première apparition de l'écran (pas au retour du Détail,
    /// où la ligne vers laquelle le zoom se referme doit rester visible, ni en changeant d'onglet).
    @State private var cascaded = false

    var body: some View {
        let cards = store.cards
        // Sous « Réduire les animations », pas de cascade : les cartes sont là d'emblée.
        let cardsShown = cascaded || !Motion.runs(.cascade, reduceMotion: reduceMotion)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Mes équipes", subtitle: cards.isEmpty ? Format.followCount(0) : store.cardsSubtitle(cards))
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                        .transition(Motion.bannerTransition(reduceMotion: reduceMotion))
                }
                if cards.isEmpty {
                    WelcomeCard(action: openTeams)
                } else {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        TeamCardView(card: card)
                            .cascadeIn(index: index, shown: cardsShown)
                            .transition(Motion.listTransition(reduceMotion: reduceMotion))
                    }
                }
            }
            // Bandeau (spec finitions §11) et cartes (§7) : seules ces deux valeurs animent l'écran.
            .animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: store.isFailing)
            .animation(Motion.animation(.list, reduceMotion: reduceMotion), value: cards.map(\.id))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .haptics(haptics)
        .onAppear { cascaded = true }
        .abyssBackground()
        .navigationTitle("Matchs")
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Tirer pour rafraîchir, puis son retour (spec finitions §3) : succès si l'API a répondu, avertissement sinon.
    /// Une méthode de la vue (isolée au fil principal) : l'action de `.refreshable` est `@Sendable`.
    /// Pas de retour si le geste a été annulé (l'utilisateur a quitté l'écran, ou relancé le rafraîchissement).
    private func refresh() async {
        await store.refreshNow()
        guard !Task.isCancelled else { return }
        haptics.play(store.isFailing ? .refreshFailed : .refreshSucceeded)
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
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }
}

#Preview {
    NavigationStack { MatchesView(openTeams: {}) }.environment(AppStore(preview: .standard))
}
