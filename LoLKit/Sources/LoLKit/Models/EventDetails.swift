/// Détails d'un match (`getEventDetails`) : équipes avec id, victoires, et toutes les games.
public struct EventDetails: Codable, Sendable, Equatable, Identifiable {
    public struct Match: Codable, Sendable, Equatable {
        public let strategy: Strategy?
        public let teams: [MatchTeam]
        public let games: [GameRef]

        public init(strategy: Strategy?, teams: [MatchTeam], games: [GameRef]) {
            self.strategy = strategy
            self.teams = teams
            self.games = games
        }
    }

    public let id: String
    public let league: LeagueRef
    public let match: Match
    public let streams: [StreamInfo]?

    public init(id: String, league: LeagueRef, match: Match, streams: [StreamInfo]?) {
        self.id = id
        self.league = league
        self.match = match
        self.streams = streams
    }

    public var bestOf: Int { match.strategy?.count ?? 1 }
}

struct EventDetailsResponse: Decodable {
    struct Payload: Decodable {
        let event: EventDetails
    }

    let data: Payload
}
