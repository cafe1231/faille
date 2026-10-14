import Foundation
import LoLKit

/// Une ligne de la section « Ligues » de l'onglet Matchs (spec saison §3.5).
struct LeagueRowContent: Equatable, Sendable, Identifiable {
    enum Next: Equatable, Sendable {
        case match(MatchEvent)
        /// Le prochain match oppose une équipe suivie en anti-spoiler dont le dernier match est masqué (règle C).
        case hidden
        case none
    }

    let league: FollowedLeague
    let next: Next
    /// Tournoi en cours de la ligue (lien « Classement ») ; nil tant qu'il n'est pas connu.
    let tournamentId: String?
    var id: String { league.id }
}

enum LeagueRows {
    static func rows(follows: FollowList, schedule: [MatchEvent], revealed: Set<String>,
                     maskedLatestTeamIds: Set<String>, currentTournamentIds: [String: String], now: Date) -> [LeagueRowContent] {
        follows.leagues.map { league in
            let upcoming = schedule
                .filter { $0.league.slug == league.slug && $0.state == .unstarted && $0.startTime >= now }
                .min { $0.startTime < $1.startTime }
            let next: LeagueRowContent.Next
            if let upcoming {
                let rulesC = !revealed.contains(upcoming.id) && follows.followed(in: upcoming.match.teams).contains {
                    $0.spoilerFree && maskedLatestTeamIds.contains($0.id)
                }
                next = rulesC ? .hidden : .match(upcoming)
            } else {
                next = .none
            }
            return LeagueRowContent(league: league, next: next, tournamentId: currentTournamentIds[league.id])
        }
    }
}
