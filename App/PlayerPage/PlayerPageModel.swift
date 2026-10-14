import Foundation
import LoLKit

/// Identité d'un joueur pour sa page (spec saison §3.4) : pseudo du catalogue s'il est connu, sinon celui du flux sans
/// le préfixe d'équipe ; équipe et rôle de sa game la plus récente ; photo du catalogue.
struct PlayerIdentity: Equatable, Sendable {
    let playerId: String
    let name: String
    let role: String?
    let teamId: String?
    let image: String?
}

enum PlayerPageModel {
    static func identity(_ playerId: String, catalog: [Team], games: [GameSummary]) -> PlayerIdentity? {
        let latest = games
            .compactMap { game -> (GameSummary, TeamGameLine, PlayerGameLine)? in
                for line in [game.blue, game.red] {
                    if let player = line.players.first(where: { $0.playerId == playerId }) { return (game, line, player) }
                }
                return nil
            }
            .max { $0.0.startedAt < $1.0.startedAt }
        for team in catalog {
            if let player = team.players?.first(where: { $0.id == playerId }) {
                return PlayerIdentity(playerId: playerId, name: player.summonerName,
                                      role: latest?.2.role ?? player.role, teamId: latest?.1.teamId ?? team.id,
                                      image: player.image)
            }
        }
        guard let latest else { return nil }
        let code = catalog.first { $0.id == latest.1.teamId }?.code
        return PlayerIdentity(playerId: playerId, name: PlayerName.display(latest.2.name, teamCode: code),
                              role: latest.2.role, teamId: latest.1.teamId, image: nil)
    }

    /// Meilleure game montrée seulement si son match n'est pas masqué (spec saison §3.4) ; `SeasonStats.player` exclut
    /// déjà les matchs masqués, ce contrôle est une ceinture de plus.
    static func bestGame(_ season: PlayerSeason?, masked: Set<String>) -> GameRefLine? {
        guard let best = season?.bestGame, !masked.contains(best.matchId) else { return nil }
        return best
    }

    /// « N matchs masqués » sur la page d'un joueur (ruling I-9) : les matchs de saison masqués de son équipe, comptés
    /// d'après les `SeasonMatch` (jamais d'après ses games, que la collecte ne lit pas pour un match masqué).
    static func maskedMatchCount(teamId: String?, matches: [SeasonMatch], masked: Set<String>) -> Int {
        guard let teamId else { return 0 }
        return Set(matches.filter { masked.contains($0.id) && $0.involves(teamId) }.map(\.id)).count
    }
}
