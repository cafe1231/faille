import Foundation
@testable import LoLKit

extension SeasonFixture {
    /// Les 12 matchs de KC (LEC Split 3) tirés de l'index réel, avec les ids d'équipe ; début du match = début de sa
    /// première game ; Bo3 ou Bo5 d'après le score (Bo5 = play-offs).
    static func kcMatches() throws -> [SeasonMatch] {
        let byMatch = Dictionary(grouping: try kcIndex(), by: \.match)
        return byMatch.values.map { rows in
            let ordered = rows.sorted { $0.n < $1.n }
            let sides = teams(of: ordered)
            let bestOf = 2 * (sides.map(\.gameWins).max() ?? 1) - 1
            return SeasonMatch(id: ordered[0].match, tournamentId: lecSplit3, leagueSlug: "lec",
                               stageSlug: bestOf == 5 ? "playoffs" : "regular_season", startTime: ordered[0].start,
                               blockName: nil, bestOf: bestOf, teams: sides, playedGameIds: ordered.map(\.game))
        }.sorted { $0.startTime < $1.startTime }
    }

    /// Les 31 games de KC par id, vainqueur rejoué par `GameWinners` (21 exactes, 10 déduites).
    static func kcGames() throws -> [String: GameSummary] {
        var games = Dictionary(uniqueKeysWithValues: try kcSummaries().map { ($0.gameId, $0) })
        for match in try kcMatches() {
            games = GameWinners.apply(teams: match.teams, playedGameIds: match.playedGameIds, to: games)
        }
        return games
    }
}
