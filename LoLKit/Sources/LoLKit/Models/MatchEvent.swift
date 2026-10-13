import Foundation

/// État d'un match dans le calendrier. Une valeur inconnue de l'API devient `.unknown`.
public enum EventState: String, Codable, Sendable, Equatable {
    case unstarted, inProgress, completed, unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventState(rawValue: raw) ?? .unknown
    }
}

public struct LeagueRef: Codable, Sendable, Equatable {
    public let id: String?
    public let slug: String
    public let name: String
    public let image: String?
}

/// Une équipe dans un match. `getSchedule` ne donne pas `id`, `getLive` et `getEventDetails` oui.
public struct MatchTeam: Codable, Sendable, Equatable {
    public struct Result: Codable, Sendable, Equatable {
        public let outcome: String?
        public let gameWins: Int?

        public init(outcome: String?, gameWins: Int?) {
            self.outcome = outcome
            self.gameWins = gameWins
        }
    }

    public let id: String?
    public let name: String
    public let code: String
    public let image: String?
    public let result: Result?

    public init(id: String?, name: String, code: String, image: String?, result: Result?) {
        self.id = id
        self.name = name
        self.code = code
        self.image = image
        self.result = result
    }

    /// Victoires dans la série (0 si inconnu).
    public var gameWins: Int { result?.gameWins ?? 0 }

    /// Équipe pas encore connue (« TBD »).
    public var isPlaceholder: Bool { code == "TBD" }
}

public struct Strategy: Codable, Sendable, Equatable {
    public let type: String?
    public let count: Int
}

/// Une game d'un match.
public struct GameRef: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable, Equatable {
        case unstarted, inProgress, completed, unneeded, unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = State(rawValue: raw) ?? .unknown
        }
    }

    public struct Side: Codable, Sendable, Equatable {
        public let id: String
        public let side: String
    }

    public let number: Int
    public let id: String
    public let state: State
    public let teams: [Side]?
}

public struct StreamInfo: Codable, Sendable, Equatable {
    public let statsStatus: String?
}

public struct MatchInfo: Codable, Sendable, Equatable {
    public let id: String
    public let teams: [MatchTeam]
    public let strategy: Strategy?
    public let games: [GameRef]?
}

/// Un match du calendrier (`getSchedule`) ou en cours (`getLive`).
public struct MatchEvent: Codable, Sendable, Equatable, Identifiable {
    public let startTime: Date
    public let state: EventState
    public let type: String
    public let blockName: String?
    public let league: LeagueRef
    public let match: MatchInfo
    public let streams: [StreamInfo]?

    /// Identifiant du match (le même dans toutes les routes de l'API).
    public var id: String { match.id }

    /// Nombre de games maximum (Bo1, Bo3, Bo5).
    public var bestOf: Int { match.strategy?.count ?? 1 }

    /// Riot ne fournit pas les stats live de ce match (spec §4.1 : c'est `statsStatus` qui fait foi).
    public var statsDisabled: Bool {
        streams?.contains { $0.statsStatus == "disabled" } ?? false
    }
}

/// Forme commune de `getSchedule` et `getLive`.
struct ScheduleResponse: Decodable {
    struct Payload: Decodable {
        let schedule: Schedule
    }

    struct Schedule: Decodable {
        let events: LossyArray<MatchEvent>
    }

    let data: Payload
}
