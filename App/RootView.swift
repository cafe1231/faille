import SwiftUI

/// Onglets de l'appli (spec §5, spec saison §2.1) : Accueil (par défaut), Matchs, Équipes. Barre flottante en Liquid
/// Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case home, matches, teams
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab
    /// Piles des onglets (spec saison §2.1). Toucher une notification de début de match pousse le Détail du match dans
    /// celle de Matchs (spec fonctionnalités §2, inchangé).
    @State private var homePath = NavigationPath()
    @State private var matchesPath = NavigationPath()
    @State private var teamsPath = NavigationPath()
    /// Premier lancement (spec saison §3.7), décidé une fois à l'apparition : suivre une équipe pendant l'onboarding ne
    /// le ferme pas.
    @State private var showsOnboarding = false
    /// Notifications touchées (l'appli) ; nil : aperçus et tests.
    private let router: NotificationRouter?
    /// Zoom carte → Détail (spec finitions §6) : les lignes des cartes en sont les sources, l'écran Détail la destination.
    @Namespace private var zoom

    /// Ce qui relance la reprogrammation des notifications : un autre plan (`reminderSignature`), et chaque passage de la
    /// scène au premier plan ou hors de celui-ci. Au retour, l'autorisation d'iOS a pu être rendue dans les Réglages
    /// d'iOS sans que le plan ait changé : sans cela, rien ne serait reprogrammé avant le prochain changement du plan.
    private struct ReminderKey: Equatable, Sendable {
        let signature: ReminderSignature
        let active: Bool
    }

    init(tab: AppTab = .home, router: NotificationRouter? = nil) {
        _tab = State(initialValue: tab)
        self.router = router
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Accueil", image: Icon.home.assetName, value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView(zoom: zoom, openTeams: { tab = .teams })
                        .failleDestinations(zoom: zoom)
                }
            }
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack(path: $matchesPath) {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
                        .failleDestinations(zoom: zoom)
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack(path: $teamsPath) {
                    TeamsView()
                        .failleDestinations(zoom: zoom)
                }
            }
        }
        .tint(Palette.accent)
        // Icônes de champions des écrans de saison (`ChampionIcon`) : le store Data Dragon de l'appli.
        .environment(\.dataDragon, store.dataDragon)
        .onAppear {
            if Self.presentsOnboarding(store: store, hasRouter: router != nil) {
                store.beginOnboarding()
                showsOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingHost(onDone: {
                store.completeOnboarding()
                showsOnboarding = false
            })
            .environment(store)
        }
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
        let link = RootNavigation.deepLink(matchId: matchId)
        tab = link.tab
        matchesPath = NavigationPath([link.route])
    }
}

extension RootView {
    /// L'onboarding s'ouvre dans l'appli seulement (elle seule passe un routeur de notifications : jamais dans les
    /// aperçus ni les tests), au premier lancement (`showsOnboarding` : pas fait, rien de suivi).
    static func presentsOnboarding(store: AppStore, hasRouter: Bool) -> Bool {
        hasRouter && store.showsOnboarding
    }
}

/// L'onboarding branché sur le store : équipes du Mondial (classements, sinon annuaire), ligues des pilules, recherche
/// dans le catalogue ; chaque toucher suit tout de suite (spec saison §3.7).
private struct OnboardingHost: View {
    @Environment(AppStore.self) private var store
    let onDone: () -> Void

    var body: some View {
        let worlds = store.leagues.first { $0.slug == "worlds" }
        let standings = worlds.flatMap { store.currentTournamentId(leagueId: $0.id) }.flatMap { store.season.standings[$0] }
        let teams = OnboardingModel.worldsTeams(catalog: store.catalog, worldsStandings: standings,
                                                fallback: worlds.map { store.teams(in: $0) } ?? [])
        OnboardingView(teams: teams, leagues: store.leaguePills,
                       followedTeams: store.catalog.filter { store.follows.contains(id: $0.id) },
                       followedLeagueIds: Set(store.follows.leagues.map(\.id)),
                       spoilerFreeIds: Set(store.follows.teams.filter(\.spoilerFree).map(\.id)),
                       search: { store.search($0) },
                       onToggleTeam: { store.toggleFollow($0) },
                       onToggleLeague: { store.toggleFollowLeague($0) },
                       onSetSpoilerFree: { id, on in store.setSpoilerFree(on, id: id) },
                       onDone: onDone)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
