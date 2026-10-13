/// Détails d'un match (`getEventDetails`) : équipes avec id, victoires, et toutes les games.
public struct EventDetails: Codable, Sendable, Equatable, Identifiable {
    public struct Match: Codable, Sendable, Equatable {
        public let strategy: Strategy?
        public let teams: [MatchTeam]
        public let games: [GameRef]
    }

    public let id: String
    public let league: LeagueRef
    public let match: Match
    public let streams: [StreamInfo]?

    public var bestOf: Int { match.strategy?.count ?? 1 }
}

struct EventDetailsResponse: Decodable {
    struct Payload: Decodable {
        let event: EventDetails
    }

    let data: Payload
}
