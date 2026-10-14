import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab
    /// Pile de l'onglet Matchs : toucher une notification de début de match y pousse le Détail du match (spec
    /// fonctionnalités §2).
    @State private var matchesPath: [MatchRoute] = []
    /// Notifications touchées (l'appli) ; nil : aperçus et tests.
    private let router: NotificationRouter?
    @ReduceMotion var reduceMotion
    /// Zoom carte → Détail (spec finitions §6) : les lignes des cartes en sont les sources, l'écran Détail la destination.
    @Namespace private var zoom

    /// Ce qui relance la reprogrammation des notifications : un autre plan (`reminderSignature`), et chaque passage de la
    /// scène au premier plan ou hors de celui-ci. Au retour, l'autorisation d'iOS a pu être rendue dans les Réglages
    /// d'iOS sans que le plan ait changé : sans cela, rien ne serait reprogrammé avant le prochain changement du plan.
    private struct ReminderKey: Equatable, Sendable {
        let signature: ReminderSignature
        let active: Bool
    }

    init(tab: AppTab = .matches, router: NotificationRouter? = nil) {
        _tab = State(initialValue: tab)
        self.router = router
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack(path: $matchesPath) {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
                        .navigationDestination(for: MatchRoute.self) { route in
                            // Sans ligne source, ou sous « Réduire les animations » : transition standard d'iOS.
                            MatchDetailView(matchId: route.matchId)
                                .zoomTransition(route.sourceID, in: zoom,
                                                enabled: Motion.runs(.zoom, reduceMotion: reduceMotion))
                        }
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack {
                    TeamsView()
                }
            }
        }
        .tint(Palette.accent)
        .onChange(of: router?.pendingMatchId, initial: true) { _, _ in
            openPendingMatch()
        }
        // Notifications de début de match (spec fonctionnalités §2) : reprogrammées dès que le calendrier, les équipes
        // suivies, les révélations ou les réglages changent le plan (`reminderSignature`), et au retour au premier plan.
        // En arrière-plan, `refreshInBackground` et `enterBackground` s'en chargent (un réveil d'iOS n'a pas de scène).
        .task(id: ReminderKey(signature: store.reminderSignature, active: scenePhase == .active)) {
            await store.syncReminders(center: store.reminderCenter)
        }
    }

    /// Notification touchée : onglet Matchs, et le Détail du match par-dessus la liste (transition standard : aucune ligne
    /// de carte n'en est la source).
    private func openPendingMatch() {
        guard let matchId = router?.consume() else { return }
        tab = .matches
        matchesPath = [MatchRoute(matchId: matchId)]
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
