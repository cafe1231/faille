import Foundation

/// Fenêtre d'environ 10 s de frames du flux `livestats/v1/window/{gameId}`.
public struct LiveWindow: Codable, Sendable, Equatable {
    public let esportsGameId: String
    public let esportsMatchId: String?
    public let gameMetadata: GameMetadata
    public let frames: [WindowFrame]
}

public struct GameMetadata: Codable, Sendable, Equatable {
    public let patchVersion: String?
    public let blueTeamMetadata: TeamMetadata
    public let redTeamMetadata: TeamMetadata
}

public struct TeamMetadata: Codable, Sendable, Equatable {
    public let esportsTeamId: String
    public let participantMetadata: [ParticipantMetadata]
}

public struct ParticipantMetadata: Codable, Sendable, Equatable {
    public let participantId: Int
    /// Id du joueur, le même que `TeamPlayer.id` de `getTeams` (identité d'un joueur, spec saison §1.5) ; absent des
    /// vieilles captures.
    public let esportsPlayerId: String?
    public let summonerName: String?
    public let championId: String?
    public let role: String?
}

public struct WindowFrame: Codable, Sendable, Equatable {
    public let rfc460Timestamp: Date
    /// `in_game`, `paused` ou `finished`.
    public let gameState: String
    public let blueTeam: FrameTeam
    public let redTeam: FrameTeam
}

public struct FrameTeam: Codable, Sendable, Equatable {
    public let totalGold: Int
    public let inhibitors: Int
    public let towers: Int
    public let barons: Int
    public let totalKills: Int
    public let dragons: [String]
    public let participants: [FrameParticipant]
}

public struct FrameParticipant: Codable, Sendable, Equatable {
    public let participantId: Int
    public let totalGold: Int
    public let level: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
}
