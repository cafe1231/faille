import Foundation

/// Un match terminé d'un tournoi (`getCompletedEvents?tournamentId=`), réduit à ce que la saison utilise : pas de
/// vods, pas d'id d'équipe (l'API n'en donne pas ici, `SeasonMatch.join` les retrouve). Encodé tel quel dans
/// `cache/season/completed/<tournamentId>.json` (`Cached<[CompletedMatch]>`).
public struct CompletedMatch: Codable, Sendable, Equatable, Identifiable {
    public let matchId: String
    public let startTime: Date
    public let blockName: String?
    public let bestOf: Int
    /// Équipes sans id, avec `result.gameWins`.
    public let teams: [MatchTeam]
    /// TOUTES les games listées par l'API, jouées ou non, dans l'ordre.
    public let gameIds: [String]

    public init(matchId: String, startTime: Date, blockName: String?, bestOf: Int, teams: [MatchTeam],
                gameIds: [String]) {
        self.matchId = matchId
        self.startTime = startTime
        self.blockName = blockName
        self.bestOf = bestOf
        self.teams = teams
        self.gameIds = gameIds
    }

    public var id: String { matchId }

    /// Games réellement jouées : les `Σ gameWins` premières de `gameIds` (règle vérifiée sur 280 matchs, spec §1.2).
    public var playedGameIds: [String] { Array(gameIds.prefix(teams.reduce(0) { $0 + $1.gameWins })) }
}

/// Forme de l'API : `events[] {startTime, blockName, league, match {id, teams, strategy}, games [{id, vods}]}`.
struct CompletedEventsResponse: Decodable {
    struct Payload: Decodable {
        let schedule: Schedule
    }

    struct Schedule: Decodable {
        let events: LossyArray<Event>
    }

    /// Un événement. `startTime` et `match.id` sont indispensables ; le reste a une valeur neutre.
    struct Event: Decodable {
        let completed: CompletedMatch

        private enum Keys: String, CodingKey {
            case startTime, blockName, match, games
        }

        private enum MatchKeys: String, CodingKey {
            case id, teams, strategy
        }

        private struct GameId: Decodable {
            let id: String
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let match = try container.nestedContainer(keyedBy: MatchKeys.self, forKey: .match)
            let teams = (try? match.decodeIfPresent(LossyArray<MatchTeam>.self, forKey: .teams))?.elements ?? []
            let strategy = try? match.decodeIfPresent(Strategy.self, forKey: .strategy)
            let games = (try? container.decodeIfPresent(LossyArray<GameId>.self, forKey: .games))?.elements ?? []
            completed = CompletedMatch(
                matchId: try match.decode(String.self, forKey: .id),
                startTime: try container.decode(Date.self, forKey: .startTime),
                blockName: try? container.decodeIfPresent(String.self, forKey: .blockName),
                bestOf: strategy?.count ?? 1,
                teams: teams,
                gameIds: games.map(\.id)
            )
        }
    }

    let data: Payload
}
