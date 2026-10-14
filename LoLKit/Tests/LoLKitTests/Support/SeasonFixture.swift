import Foundation
@testable import LoLKit

/// Fixtures réelles réduites de la saison (`Fixtures/season/`, capturées le 14/10/2026, spec saison §1.1).
enum SeasonFixture {
    static let lecSplit3 = "115548681802226458"
    static let kc = "111692118851466302"
    static let g2 = "98767991926151025"
    /// Game de référence : LEC S3, play-offs, 06/09, KC 1-3 G2, game 1 (KC bleu).
    static let game304 = "115548681803406304"
    static let match303 = "115548681803406303"

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/season") else {
            throw Fixture.Missing(name: "season/\(name)")
        }
        return try Data(contentsOf: url)
    }

    static func window(_ name: String) throws -> LiveWindow {
        try JSONDecoder.lolesports().decode(LiveWindow.self, from: data(name))
    }

    static func details(_ name: String) throws -> GameDetails {
        try JSONDecoder.lolesports().decode(GameDetails.self, from: data(name))
    }

    /// `GameSummary` de la game 304 lu depuis les vraies fenêtres (palier B si `enriched`).
    static func summary304(enriched: Bool = true) throws -> GameSummary {
        let made = GameSummary.make(
            first: try window("window_first_115548681803406304"),
            final: try window("window_final_115548681803406304"),
            at15: enriched ? try window("window_15min_115548681803406304") : nil,
            details: enriched ? try details("details_final_115548681803406304") : nil,
            matchId: match303, number: 1, tournamentId: lecSplit3, leagueSlug: "lec")
        guard let made else { throw Fixture.Missing(name: "GameSummary 304") }
        return made
    }

    /// Une ligne de `crawl_kc_lec3_tierA_index.json` : une game de KC (LEC Split 3, palier A réel), stats d'équipe finales.
    struct IndexRow: Decodable {
        struct SeriesEntry: Decodable {
            let code: String
            let wins: Int

            init(from decoder: any Decoder) throws {
                var container = try decoder.unkeyedContainer()
                code = try container.decode(String.self)
                wins = try container.decode(Int.self)
            }
        }

        struct TeamLine: Decodable {
            let totalGold: Int
            let inhibitors: Int
            let towers: Int
            let barons: Int
            let totalKills: Int
            let dragons: [String]
        }

        let match: String
        let n: Int
        let game: String
        let series: [SeriesEntry]
        let start: Date
        let end: Date
        /// `finished` (29 games) ou `in_game` (2 games dont le flux s'arrête avant la frame `finished`).
        let state: String
        let blueId: String
        let redId: String
        let blueTeam: TeamLine
        let redTeam: TeamLine
    }

    /// Les 31 games de KC, dans l'ordre chronologique.
    static func kcIndex() throws -> [IndexRow] {
        try JSONDecoder.lolesports().decode([IndexRow].self, from: data("crawl_kc_lec3_tierA_index"))
    }

    /// Les 31 games de KC en `GameSummary` (palier A, sans joueurs : l'index ne garde que les stats d'équipe),
    /// résultat inconnu.
    static func kcSummaries() throws -> [GameSummary] {
        try kcIndex().map(summary)
    }

    static func summary(_ row: IndexRow) -> GameSummary {
        func line(_ id: String, _ team: IndexRow.TeamLine) -> TeamGameLine {
            TeamGameLine(teamId: id, kills: team.totalKills, gold: team.totalGold, towers: team.towers,
                         inhibitors: team.inhibitors, barons: team.barons, dragons: team.dragons, gold15: nil, players: [])
        }
        return GameSummary(gameId: row.game, matchId: row.match, tournamentId: lecSplit3, leagueSlug: "lec",
                           number: row.n, patch: nil, startedAt: row.start, endedAt: row.end,
                           durationSeconds: Int(row.end.timeIntervalSince(row.start).rounded()), result: .unknown,
                           blue: line(row.blueId, row.blueTeam), red: line(row.redId, row.redTeam), enriched: false)
    }

    /// Les deux équipes d'un match de l'index (KC et son adversaire, ordre de la série), avec id et victoires.
    static func teams(of rows: [IndexRow]) -> [MatchTeam] {
        let first = rows[0]
        let opponent = first.blueId == kc ? first.redId : first.blueId
        return first.series.map { entry in
            MatchTeam(id: entry.code == "KC" ? kc : opponent, name: entry.code, code: entry.code, image: nil,
                      result: MatchTeam.Result(outcome: nil, gameWins: entry.wins))
        }
    }
}
