import Foundation

/// Une game d'un joueur (5 dernières games, meilleure game de la page joueur, spec saison §3.4).
public struct GameRefLine: Sendable, Equatable {
    public let gameId: String
    public let matchId: String
    public let teamId: String
    public let startedAt: Date
    public let champion: String
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let gold: Int
    /// Victoire de son équipe ; nil si le vainqueur de la game est inconnu.
    public let won: Bool?
    /// Vainqueur déduit (« estimé »).
    public let winEstimated: Bool

    public init(gameId: String, matchId: String, teamId: String, startedAt: Date, champion: String, kills: Int,
                deaths: Int, assists: Int, creepScore: Int, gold: Int, won: Bool?, winEstimated: Bool) {
        self.gameId = gameId
        self.matchId = matchId
        self.teamId = teamId
        self.startedAt = startedAt
        self.champion = champion
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.gold = gold
        self.won = won
        self.winEstimated = winEstimated
    }

    /// (K + A) / max(1, D).
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
}

/// Saison d'un joueur (§1.5), calculée à la lecture sur les games lues de ses matchs non masqués.
public struct PlayerSeason: Sendable, Equatable {
    public let playerId: String
    /// Nom brut du flux dans sa game la plus récente (« KC Canna ») : l'appli affiche `TeamPlayer.summonerName` du
    /// catalogue, sinon `PlayerName.display(name, teamCode:)`.
    public let name: String
    public let role: String
    /// Équipe de sa game la plus récente.
    public let teamId: String
    public let games: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    /// Σ CS / Σ minutes ; Σ gold / Σ minutes ; Σ (K + A) / Σ kills de l'équipe.
    public let csPerMin: Double
    public let goldPerMin: Double
    public let killParticipation: Double
    /// Moyenne sur les `damageShareGames` games enrichies ; nil sans aucune (« — »).
    public let damageShare: Double?
    public let damageShareGames: Int
    public let champions: [ChampionUse]
    /// KDA le plus haut, puis le plus de kills, puis la plus récente.
    public let bestGame: GameRefLine?
    /// 5 dernières games, la plus récente d'abord.
    public let recent: [GameRefLine]

    public init(playerId: String, name: String, role: String, teamId: String, games: Int, kills: Int, deaths: Int,
                assists: Int, csPerMin: Double, goldPerMin: Double, killParticipation: Double, damageShare: Double?,
                damageShareGames: Int, champions: [ChampionUse], bestGame: GameRefLine?, recent: [GameRefLine]) {
        self.playerId = playerId
        self.name = name
        self.role = role
        self.teamId = teamId
        self.games = games
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.csPerMin = csPerMin
        self.goldPerMin = goldPerMin
        self.killParticipation = killParticipation
        self.damageShare = damageShare
        self.damageShareGames = damageShareGames
        self.champions = champions
        self.bestGame = bestGame
        self.recent = recent
    }

    /// (K + A) / max(1, D) sur la somme (pas la moyenne des ratios).
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
}

/// Classement des « Joueurs en forme » (Accueil, spec saison §2.2 n° 6).
public enum PlayerMetric: Sendable, Equatable, CaseIterable {
    case kda
    /// Kills moyens par game.
    case kills
    case csPerMin

    public func value(of player: PlayerSeason) -> Double {
        switch self {
        case .kda: player.kda
        case .kills: Double(player.kills) / Double(max(1, player.games))
        case .csPerMin: player.csPerMin
        }
    }
}
