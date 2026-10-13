import Foundation

/// Partie fixe d'une Live Activity, donnée à son démarrage (spec §4.3).
public struct LiveMatchAttributes: Codable, Sendable, Equatable, Hashable {
    public struct Side: Codable, Sendable, Equatable, Hashable {
        public let id: String
        public let code: String
        public let name: String
        /// Couleur de l'équipe si elle est suivie, sinon `nil` (verre neutre).
        public let colorHex: String?

        public init(id: String, code: String, name: String, colorHex: String?) {
            self.id = id
            self.code = code
            self.name = name
            self.colorHex = colorHex
        }
    }

    public let matchId: String
    public let leagueName: String
    public let bestOf: Int
    /// Dans l'ordre de `EventDetails.match.teams`, comme `LiveMatchState.seriesScore` et `stats`.
    public let teams: [Side]
    /// Index (dans `teams`) de l'équipe suivie depuis le plus longtemps : c'est sa couleur qui teinte la Live Activity.
    /// `nil` si aucune équipe du match n'est suivie.
    public let primaryTeamIndex: Int?

    public init(matchId: String, leagueName: String, bestOf: Int, teams: [Side], primaryTeamIndex: Int?) {
        self.matchId = matchId
        self.leagueName = leagueName
        self.bestOf = bestOf
        self.teams = teams
        self.primaryTeamIndex = primaryTeamIndex
    }
}

/// Partie dynamique d'une Live Activity. Même JSON pour l'appli (v1) et le serveur de push (phase 2).
public struct LiveMatchState: Codable, Sendable, Equatable, Hashable {
    public enum Phase: String, Codable, Sendable, Hashable {
        case upcoming, inGame, betweenGames, finished
    }

    /// Au-delà, la Live Activity affiche « màj il y a X min ».
    public static let staleAfter: TimeInterval = 180

    public var phase: Phase
    /// Victoires des deux équipes, dans l'ordre de `LiveMatchAttributes.teams`.
    public var seriesScore: [Int]?
    public var gameNumber: Int?
    /// Début estimé de la game en heure de l'appareil : le chrono s'affiche avec un minuteur natif.
    public var gameClockStart: Date?
    /// Stats des deux équipes, dans l'ordre de `LiveMatchAttributes.teams`.
    public var stats: [TeamStats]?
    public var statsAvailable: Bool
    public var spoilerFree: Bool
    public var winnerCode: String?
    public var updatedAt: Date

    public init(phase: Phase, seriesScore: [Int]?, gameNumber: Int?, gameClockStart: Date?, stats: [TeamStats]?,
                statsAvailable: Bool, spoilerFree: Bool, winnerCode: String?, updatedAt: Date) {
        self.phase = phase
        self.seriesScore = seriesScore
        self.gameNumber = gameNumber
        self.gameClockStart = gameClockStart
        self.stats = stats
        self.statsAvailable = statsAvailable
        self.spoilerFree = spoilerFree
        self.winnerCode = winnerCode
        self.updatedAt = updatedAt
    }

    public var staleDate: Date { updatedAt.addingTimeInterval(Self.staleAfter) }

    /// Version sans spoiler : seule la phase reste (« En direct », « Terminé »…).
    public func masked() -> LiveMatchState {
        var copy = self
        copy.seriesScore = nil
        copy.gameNumber = nil
        copy.gameClockStart = nil
        copy.stats = nil
        copy.winnerCode = nil
        copy.spoilerFree = true
        return copy
    }
}
