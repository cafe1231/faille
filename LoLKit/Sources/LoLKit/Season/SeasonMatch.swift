import Foundation

/// Un match joué de la saison : l'événement de `getCompletedEvents` (ids des games) joint au match de même id dans
/// `getStandings` (ids d'équipe, `outcome`, étape) — spec saison §1.2. Jamais stocké : recalculé à la lecture.
public struct SeasonMatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let tournamentId: String
    public let leagueSlug: String
    /// Étape de `getStandings` qui contient le match (`regular_season`, `swiss`, `knockouts`…) ; nil si absent.
    public let stageSlug: String?
    public let startTime: Date
    public let blockName: String?
    public let bestOf: Int
    /// Équipes avec id quand il est connu : `SpoilerPolicy.isMasked` s'applique directement.
    public let teams: [MatchTeam]
    public let playedGameIds: [String]

    public init(id: String, tournamentId: String, leagueSlug: String, stageSlug: String?, startTime: Date,
                blockName: String?, bestOf: Int, teams: [MatchTeam], playedGameIds: [String]) {
        self.id = id
        self.tournamentId = tournamentId
        self.leagueSlug = leagueSlug
        self.stageSlug = stageSlug
        self.startTime = startTime
        self.blockName = blockName
        self.bestOf = bestOf
        self.teams = teams
        self.playedGameIds = playedGameIds
    }

    /// Vrai si l'équipe `teamId` joue ce match (par id : une équipe sans id n'est rattachée à rien).
    public func involves(_ teamId: String) -> Bool {
        teams.contains { $0.id == teamId }
    }

    /// Jointure (§1.2, « jointure par id de match ») : équipes, résultats et étape du match de même id dans
    /// `standings` ; à défaut, équipes de `getCompletedEvents` rapprochées du catalogue par `MatchTeam.isSame` (nom,
    /// logo ; jamais le code seul), une équipe active d'abord. Une équipe introuvable garde `id` nil : le match ne
    /// compte pas dans son bilan (pas de faux chiffre). Ordre : celui de `completed`.
    public static func join(completed: [CompletedMatch], standings: Standings?, tournamentId: String,
                            leagueSlug: String, catalog: [Team]) -> [SeasonMatch] {
        completed.map { match in
            let stage = standings?.stage(containing: match.matchId)
            let bracket = standings?.match(id: match.matchId)
            let teams: [MatchTeam]
            if let bracket, bracket.teams.count == match.teams.count, !bracket.teams.contains(where: \.isPlaceholder) {
                teams = bracket.teams
            } else {
                teams = match.teams.map { resolve($0, in: catalog) }
            }
            return SeasonMatch(id: match.matchId, tournamentId: tournamentId, leagueSlug: leagueSlug,
                               stageSlug: stage?.slug, startTime: match.startTime, blockName: match.blockName,
                               bestOf: match.bestOf, teams: teams, playedGameIds: match.playedGameIds)
        }
    }

    /// L'équipe avec l'id du catalogue (actives d'abord), ou telle quelle si rien ne correspond.
    static func resolve(_ team: MatchTeam, in catalog: [Team]) -> MatchTeam {
        guard team.id == nil, !team.isPlaceholder else { return team }
        let matches: (Team) -> Bool = { team.isSame(as: FollowedTeam(team: $0)) }
        guard let found = catalog.first(where: { $0.isActive && matches($0) }) ?? catalog.first(where: matches) else {
            return team
        }
        return MatchTeam(id: found.id, name: team.name, code: team.code, image: team.image, result: team.result)
    }
}
