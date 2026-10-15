import Foundation
@testable import LoLKit

/// Fixtures réelles du périmètre (`Fixtures/season/perimetre/`, capturées le 15/10/2026, spec périmètre §1).
enum PerimetreFixture {
    static let worlds2026 = "115660540725177488"
    static let worlds2025 = "113475452383887518"
    static let worlds2024 = "112966669920590211"
    static let demaciaCup2026 = "117133773242499009"
    /// Ligues capturées (`getTournamentsForLeague_<slug>.json`).
    static let leagueSlugs = ["worlds", "msi", "first_stand", "demacia_cup", "lec", "lck", "emea_masters"]

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures/season/perimetre") else {
            throw Fixture.Missing(name: "season/perimetre/\(name)")
        }
        return try Data(contentsOf: url)
    }

    /// Tournois d'une ligue, dans l'ordre de l'API (du plus récent au plus ancien) ; `leagueId` = le slug de la ligue.
    static func tournaments(_ leagueSlug: String) throws -> [TournamentRef] {
        let response = try JSONDecoder.lolesports()
            .decode(TournamentsResponse.self, from: data("getTournamentsForLeague_\(leagueSlug)"))
        return response.data.leagues.flatMap(\.tournaments.elements).map { tournament in
            var copy = tournament
            copy.leagueId = leagueSlug
            return copy
        }
    }

    /// Tous les tournois des 7 ligues capturées, par slug de tournoi.
    static func tournamentsBySlug() throws -> [String: TournamentRef] {
        var bySlug: [String: TournamentRef] = [:]
        for league in leagueSlugs {
            for tournament in try tournaments(league) { bySlug[tournament.slug] = tournament }
        }
        return bySlug
    }

    struct ReducedTeam: Decodable {
        let code: String
        let name: String
        let gameWins: Int
    }

    struct ReducedMatch: Decodable {
        let matchId: String
        let startTime: Date
        let blockName: String?
        let teams: [ReducedTeam]
        let playedGameIds: [String]
    }

    struct ReducedTournament: Decodable {
        let matchCount: Int
        let playedGames: Int
        /// Absent pour les tournois sans KC ni G2 mesurés en volume seulement.
        let kcG2Matches: [ReducedMatch]?
    }

    /// `completed_kc_g2_2024_2026_reduced.json`, par slug de tournoi.
    static func reduced() throws -> [String: ReducedTournament] {
        try JSONDecoder.lolesports()
            .decode([String: ReducedTournament].self, from: data("completed_kc_g2_2024_2026_reduced"))
    }

    /// Les matchs de KC et G2 (2025-2026, internationaux compris) en `SeasonMatch`, du plus récent au plus ancien ;
    /// `MatchTeam.id` = code (« KC », « G2 »…), `stageSlug` nil, Bo déduit du score.
    static func kcG2Matches() throws -> [SeasonMatch] {
        let bySlug = try tournamentsBySlug()
        return try reduced().flatMap { slug, tournament -> [SeasonMatch] in
            guard let ref = bySlug[slug] else { return [] }
            return (tournament.kcG2Matches ?? []).map { match in
                SeasonMatch(id: match.matchId, tournamentId: ref.id, leagueSlug: ref.leagueId, stageSlug: nil,
                            startTime: match.startTime, blockName: match.blockName,
                            bestOf: 2 * (match.teams.map(\.gameWins).max() ?? 1) - 1,
                            teams: match.teams.map { team in
                                MatchTeam(id: team.code, name: team.name, code: team.code, image: nil,
                                          result: MatchTeam.Result(outcome: nil, gameWins: team.gameWins))
                            },
                            playedGameIds: match.playedGameIds)
            }
        }.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
    }

    static func standings(_ name: String) throws -> Standings {
        try JSONDecoder.lolesports().decode(StandingsResponse.self, from: data(name)).data.standings.elements[0]
    }
}
