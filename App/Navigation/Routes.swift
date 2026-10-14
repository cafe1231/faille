import SwiftUI

/// Page d'une équipe (spec saison §3.1).
struct TeamRoute: Hashable, Sendable {
    let teamId: String
}

/// Page d'un joueur (spec saison §3.4), par `esportsPlayerId`.
struct PlayerRoute: Hashable, Sendable {
    let playerId: String
}

/// Classements et tableaux d'un tournoi (spec saison §3.5).
struct StandingsRoute: Hashable, Sendable {
    let tournamentId: String
}

/// Calendrier complet (spec saison §3.2).
struct CalendarRoute: Hashable, Sendable {}

/// Un côté d'un duel choisi librement (spec saison §3.3).
enum DuelSide: Hashable, Sendable {
    case player(String)
    case team(String)
}

/// Duel de deux joueurs ou de deux équipes (spec saison §3.3).
struct DuelRoute: Hashable, Sendable {
    let left: DuelSide
    let right: DuelSide
}

/// Navigation de la racine.
enum RootNavigation {
    /// Notification touchée (spec fonctionnalités §2, inchangé) : onglet Matchs, Détail du match par-dessus la liste
    /// (transition standard : aucune ligne de carte n'en est la source).
    static func deepLink(matchId: String) -> (tab: AppTab, route: MatchRoute) {
        (.matches, MatchRoute(matchId: matchId))
    }
}

/// Destinations communes aux trois onglets (spec saison §2.1) : le Détail (zoom depuis la ligne touchée, inchangé), et les
/// écrans de la saison.
private struct FailleDestinations: ViewModifier {
    let zoom: Namespace.ID
    @ReduceMotion var reduceMotion

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: MatchRoute.self) { route in
                // Sans ligne source, ou sous « Réduire les animations » : transition standard d'iOS.
                MatchDetailView(matchId: route.matchId)
                    .zoomTransition(route.sourceID, in: zoom, enabled: Motion.runs(.zoom, reduceMotion: reduceMotion))
            }
            .navigationDestination(for: TeamRoute.self) { TeamPageView(teamId: $0.teamId) }
            .navigationDestination(for: PlayerRoute.self) { PlayerPageView(playerId: $0.playerId) }
            .navigationDestination(for: StandingsRoute.self) { StandingsView(tournamentId: $0.tournamentId) }
            .navigationDestination(for: CalendarRoute.self) { _ in SeasonCalendarView() }
            .navigationDestination(for: DuelRoute.self) { DuelView(left: $0.left, right: $0.right) }
    }
}

extension View {
    /// À poser sur la racine de chaque `NavigationStack` de l'appli.
    func failleDestinations(zoom: Namespace.ID) -> some View {
        modifier(FailleDestinations(zoom: zoom))
    }
}
