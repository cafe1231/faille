import Foundation
import LoLKit

/// Prochains matchs d'une page d'équipe (spec saison §3.1) : jamais lus directement dans le calendrier — le premier passe
/// par `Presenter.nextLine` (règles F1 et C), les suivants seulement si l'équipe n'est pas en anti-spoiler et qu'aucun
/// n'oppose l'équipe à une autre équipe suivie en anti-spoiler dont le dernier match est masqué.
enum UpcomingLines: Equatable, Sendable {
    /// « Prochain · masqué », et rien d'autre.
    case hidden
    case none
    case matches([MatchEvent])
}

/// Ligne « Classement » de la page d'équipe (spec saison §3.1, §3.5).
enum StandingLine: Equatable, Sendable {
    /// « Classement masqué · toucher pour révéler ».
    case masked(tournamentId: String)
    /// « 1er · 9-0 » (saison régulière classée).
    case ranked(tournamentId: String, ordinal: Int, wins: Int, losses: Int)
    /// Système suisse : « 2-1 ».
    case record(tournamentId: String, record: String)
}

/// Logique de la page d'équipe qui ne dépend pas de l'écran (testée sans interface).
enum TeamPageModel {
    /// L'équipe vue comme une équipe suivie (pour `TeamCards` / `Presenter.nextLine`) : sa fiche de suivi si elle est
    /// suivie, sinon une fiche construite depuis le catalogue (jamais enregistrée).
    static func asFollowed(_ teamId: String, follows: FollowList, catalog: [Team], fallback: MatchTeam?) -> FollowedTeam? {
        if let followed = follows.team(id: teamId) { return followed }
        if let team = catalog.first(where: { $0.id == teamId }) { return FollowedTeam(team: team) }
        guard let fallback else { return nil }
        return FollowedTeam(id: teamId, code: fallback.code, name: fallback.name, image: fallback.image)
    }

    static func upcoming(team: FollowedTeam, schedule: [MatchEvent], live: [MatchEvent]?, follows: FollowList,
                         revealed: Set<String>, maskedLatestTeamIds: Set<String>, limit: Int = 3) -> UpcomingLines {
        guard let card = TeamCards.build(follows: FollowList(teams: [team]), schedule: schedule, live: live,
                                         revealed: revealed).first else { return .none }
        switch Presenter.nextLine(for: card, follows: follows, revealed: revealed, maskedLatestTeamIds: maskedLatestTeamIds) {
        case .hidden:
            return .hidden
        case .none:
            return .none
        case let .match(next):
            // Anti-spoiler : une équipe en anti-spoiler n'annonce que son prochain match (la suite d'un tableau trahirait
            // des résultats à venir dès qu'ils tombent).
            if follows.team(id: team.id)?.spoilerFree == true { return .matches([next]) }
            let later = schedule
                .filter { event in
                    event.id != next.id && event.state == .unstarted && event.startTime >= next.startTime
                        && event.match.teams.contains { $0.isSame(as: team) }
                }
                .sorted { $0.startTime < $1.startTime }
                .filter { event in
                    revealed.contains(event.id) || !follows.followed(in: event.match.teams).contains {
                        $0.spoilerFree && $0.id != team.id && maskedLatestTeamIds.contains($0.id)
                    }
                }
            return .matches([next] + later.prefix(max(0, limit - 1)))
        }
    }

    /// Adversaire du prochain match montré (face-à-face), seulement si la ligne est un vrai match : son id dans le match
    /// (direct), sinon l'équipe du catalogue de même nom ou de même logo (le calendrier n'a pas d'id d'équipe) ; jamais
    /// « TBD ».
    static func nextOpponentId(_ lines: UpcomingLines, team: FollowedTeam, catalog: [Team]) -> String? {
        guard case let .matches(events) = lines, let next = events.first,
              let opponent = next.match.teams.first(where: { !$0.isSame(as: team) && !$0.isPlaceholder }) else { return nil }
        if let id = opponent.id { return id }
        return catalog.first { candidate in
            candidate.name.lowercased() == opponent.name.lowercased()
                || (opponent.image != nil && candidate.image == opponent.image)
        }?.id
    }

    /// Ligne de classement de l'équipe dans un tournoi : rang de la saison régulière, sinon bilan du système suisse
    /// (`StandingsTable`), sinon rien ; masquée si `masked`.
    static func standing(teamId: String, tournamentId: String, standings: Standings?, masked: Bool) -> StandingLine? {
        guard let standings else { return nil }
        if masked { return .masked(tournamentId: tournamentId) }
        for stage in StandingsTable.build(standings: standings).reversed() {
            switch stage.content {
            case let .table(rows):
                if let row = rows.first(where: { $0.team.id == teamId }) {
                    return .ranked(tournamentId: tournamentId, ordinal: row.ordinal, wins: row.wins, losses: row.losses)
                }
            case let .swiss(groups):
                if let group = groups.first(where: { $0.teams.contains { $0.id == teamId } }) {
                    return .record(tournamentId: tournamentId, record: group.record)
                }
            case .bracket, .matches:
                continue
            }
        }
        return nil
    }

    /// Effectif (spec saison §3.1) : joueurs du catalogue, dans l'ordre des postes.
    static func roster(_ team: Team?) -> [TeamPlayer] {
        let order = ["top", "jungle", "mid", "bottom", "support"]
        return (team?.players ?? []).sorted {
            (order.firstIndex(of: $0.role ?? "") ?? order.count, $0.summonerName)
                < (order.firstIndex(of: $1.role ?? "") ?? order.count, $1.summonerName)
        }
    }

    /// La saison de l'équipe n'a que des matchs masqués : « Stats masquées · 12 matchs masqués » à la place des stats.
    static func allMasked(_ season: TeamSeason) -> Bool {
        season.maskedMatches > 0 && season.seriesWins + season.seriesLosses == 0
    }
}
