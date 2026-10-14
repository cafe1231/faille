import Foundation

/// Un poste d'une composition de duel : le joueur retenu (nil si personne n'est connu à ce poste).
public struct DuelSlot: Sendable, Equatable {
    public let role: String
    public let playerId: String?
    /// Nom du catalogue (« Canna ») ou nom brut du flux si le joueur ne vient que d'une game.
    public let name: String?
    public let image: String?

    public init(role: String, playerId: String?, name: String?, image: String?) {
        self.role = role
        self.playerId = playerId
        self.name = name
        self.image = image
    }
}

/// Une stat comparée dans un duel (barres en miroir, spec saison §3.3).
public enum DuelMetric: Sendable, Equatable, CaseIterable {
    case kda
    case csPerMin
    case goldPerMin
    case damageShare
    case killParticipation

    public func value(of player: PlayerSeason) -> Double? {
        switch self {
        case .kda: player.kda
        case .csPerMin: player.csPerMin
        case .goldPerMin: player.goldPerMin
        case .damageShare: player.damageShare
        case .killParticipation: player.killParticipation
        }
    }
}

/// Une barre en miroir : valeurs (nil = « — ») et largeurs relatives (valeur / max des deux, 0 si inconnue).
public struct DuelBar: Sendable, Equatable {
    public let metric: DuelMetric
    public let left: Double?
    public let right: Double?
    public let leftRatio: Double
    public let rightRatio: Double

    public init(metric: DuelMetric, left: Double?, right: Double?, leftRatio: Double, rightRatio: Double) {
        self.metric = metric
        self.left = left
        self.right = right
        self.leftRatio = leftRatio
        self.rightRatio = rightRatio
    }
}

/// Duel de deux joueurs : leurs saisons (nil sans game lue) et les barres.
public struct PlayerDuel: Sendable, Equatable {
    public let left: PlayerSeason?
    public let right: PlayerSeason?
    public let bars: [DuelBar]

    public init(left: PlayerSeason?, right: PlayerSeason?, bars: [DuelBar]) {
        self.left = left
        self.right = right
        self.bars = bars
    }
}

/// Duels de joueurs, poste par poste (spec saison §3.3). Anti-spoiler : `games` et `masked` comme pour `SeasonStats`
/// (match masqué → seulement les stats de saison, aucune donnée de ce match ; c'est l'appli qui n'affiche pas la ligne
/// « Cette game » d'un match masqué).
public enum Duel {
    /// Postes dans l'ordre d'affichage.
    public static let roles = ["top", "jungle", "mid", "bottom", "support"]

    /// Composition d'une équipe pour un duel : l'effectif du catalogue, poste par poste ; deux joueurs au même poste →
    /// celui qui a le plus de games dans `games`, à égalité le premier listé (§1.5). Sans effectif au catalogue pour un
    /// poste : le joueur de ce poste dans la game la plus récente de l'équipe.
    /// - Parameter games: games lues, déjà privées des matchs masqués.
    public static func lineup(teamId: String, catalog: [Team], games: [GameSummary]) -> [DuelSlot] {
        let roster = catalog.first { $0.id == teamId }?.players ?? []
        var played: [String: Int] = [:]
        for summary in games {
            for line in summary.line(teamId: teamId)?.players ?? [] { played[line.playerId, default: 0] += 1 }
        }
        let latest = games.filter { $0.line(teamId: teamId) != nil }.max { $0.startedAt < $1.startedAt }
        return roles.map { role in
            let candidates = roster.filter { $0.role == role }
            if let chosen = candidates.enumerated().max(by: { a, b in
                (played[a.element.id] ?? 0, -a.offset) < (played[b.element.id] ?? 0, -b.offset)
            })?.element {
                return DuelSlot(role: role, playerId: chosen.id, name: chosen.summonerName, image: chosen.image)
            }
            if let line = latest?.line(teamId: teamId)?.players.first(where: { $0.role == role }) {
                return DuelSlot(role: role, playerId: line.playerId, name: line.name, image: nil)
            }
            return DuelSlot(role: role, playerId: nil, name: nil, image: nil)
        }
    }

    /// Duel de deux joueurs quelconques sur leurs games lues non masquées (toute la saison donnée).
    public static func players(left: String, right: String, games: [GameSummary], masked: Set<String>) -> PlayerDuel {
        let a = SeasonStats.player(left, games: games, masked: masked, since: nil)
        let b = SeasonStats.player(right, games: games, masked: masked, since: nil)
        let bars = DuelMetric.allCases.map { metric -> DuelBar in
            let x = a.flatMap { metric.value(of: $0) }
            let y = b.flatMap { metric.value(of: $0) }
            let top = max(x ?? 0, y ?? 0)
            return DuelBar(metric: metric, left: x, right: y, leftRatio: top > 0 ? (x ?? 0) / top : 0,
                           rightRatio: top > 0 ? (y ?? 0) / top : 0)
        }
        return PlayerDuel(left: a, right: b, bars: bars)
    }
}
