import Foundation

/// Stats d'une équipe dans une game.
public struct TeamStats: Codable, Sendable, Equatable, Hashable {
    public var kills: Int
    public var gold: Int
    public var towers: Int
    public var inhibitors: Int
    public var barons: Int
    /// Types des drakes tués, dans l'ordre (`infernal`, `ocean`, `cloud`, `mountain`, `hextech`, `chemtech`, `elder`).
    public var dragons: [String]

    public init(kills: Int = 0, gold: Int = 0, towers: Int = 0, inhibitors: Int = 0, barons: Int = 0, dragons: [String] = []) {
        self.kills = kills
        self.gold = gold
        self.towers = towers
        self.inhibitors = inhibitors
        self.barons = barons
        self.dragons = dragons
    }

    init(_ team: FrameTeam) {
        self.init(kills: team.totalKills, gold: team.totalGold, towers: team.towers,
                  inhibitors: team.inhibitors, barons: team.barons, dragons: team.dragons)
    }
}

/// Une ligne joueur de l'écran Détail.
public struct PlayerLine: Sendable, Equatable {
    public let role: String
    public let champion: String
    public let name: String
    public let level: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let gold: Int

    public init(role: String, champion: String, name: String, level: Int, kills: Int, deaths: Int,
                assists: Int, creepScore: Int, gold: Int) {
        self.role = role
        self.champion = champion
        self.name = name
        self.level = level
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.gold = gold
    }

    static func lines(_ participants: [FrameParticipant], metadata: [ParticipantMetadata]) -> [PlayerLine] {
        participants.map { participant in
            let meta = metadata.first { $0.participantId == participant.participantId }
            return PlayerLine(
                role: meta?.role ?? "",
                champion: meta?.championId ?? "?",
                name: meta?.summonerName ?? "",
                level: participant.level,
                kills: participant.kills,
                deaths: participant.deaths,
                assists: participant.assists,
                creepScore: participant.creepScore,
                gold: participant.totalGold
            )
        }
    }
}

public enum GamePhase: String, Sendable, Equatable {
    case inGame, paused, finished

    init(apiValue: String) {
        switch apiValue {
        case "finished": self = .finished
        case "paused": self = .paused
        default: self = .inGame
        }
    }
}

/// État d'une game à la dernière frame reçue, côté bleu et côté rouge.
public struct GameSnapshot: Sendable, Equatable {
    public let gameId: String
    public let phase: GamePhase
    public let timestamp: Date
    public let blueTeamId: String
    public let redTeamId: String
    public let blue: TeamStats
    public let red: TeamStats
    public let bluePlayers: [PlayerLine]
    public let redPlayers: [PlayerLine]

    public init(gameId: String, phase: GamePhase, timestamp: Date, blueTeamId: String, redTeamId: String,
                blue: TeamStats, red: TeamStats, bluePlayers: [PlayerLine], redPlayers: [PlayerLine]) {
        self.gameId = gameId
        self.phase = phase
        self.timestamp = timestamp
        self.blueTeamId = blueTeamId
        self.redTeamId = redTeamId
        self.blue = blue
        self.red = red
        self.bluePlayers = bluePlayers
        self.redPlayers = redPlayers
    }

    /// Stats de l'équipe `teamId`, quel que soit son côté.
    public func stats(for teamId: String) -> TeamStats? {
        if teamId == blueTeamId { return blue }
        if teamId == redTeamId { return red }
        return nil
    }

    public func players(for teamId: String) -> [PlayerLine]? {
        if teamId == blueTeamId { return bluePlayers }
        if teamId == redTeamId { return redPlayers }
        return nil
    }
}

extension LiveWindow {
    /// Dernière frame de la fenêtre, avec champions et rôles des joueurs.
    public func latestSnapshot() -> GameSnapshot? {
        guard let frame = frames.last else { return nil }
        return GameSnapshot(
            gameId: esportsGameId,
            phase: GamePhase(apiValue: frame.gameState),
            timestamp: frame.rfc460Timestamp,
            blueTeamId: gameMetadata.blueTeamMetadata.esportsTeamId,
            redTeamId: gameMetadata.redTeamMetadata.esportsTeamId,
            blue: TeamStats(frame.blueTeam),
            red: TeamStats(frame.redTeam),
            bluePlayers: PlayerLine.lines(frame.blueTeam.participants, metadata: gameMetadata.blueTeamMetadata.participantMetadata),
            redPlayers: PlayerLine.lines(frame.redTeam.participants, metadata: gameMetadata.redTeamMetadata.participantMetadata)
        )
    }

    /// Horodatage de la première frame : le début de la game si la fenêtre a été demandée sans `startingTime`.
    public var firstFrameTime: Date? { frames.first?.rfc460Timestamp }
}
