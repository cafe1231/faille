import Foundation
import LoLKit

/// Un joueur d'un côté du duel : son id (`esportsPlayerId`), son nom affiché, et sa ligne de la game affichée si elle est
/// jouée et non masquée.
struct DuelPlayer: Equatable, Sendable {
    let id: String
    let name: String
    let thisGame: PlayerGameLine?
}

/// Une ligne poste contre poste (spec saison §3.3).
struct DuelLine: Equatable, Sendable, Identifiable {
    let role: String
    let left: DuelPlayer?
    let right: DuelPlayer?
    var id: String { role }
}

/// Assemblage des duels pour l'écran (spec saison §3.3) ; les règles (effectif, remplaçant, barres) sont dans LoLKit
/// (`Duel.lineup`, `Duel.players`).
enum DuelModel {
    /// Composition d'une équipe pour le duel : celle de la game affichée si elle est jouée ET non masquée, sinon
    /// `Duel.lineup` (effectif du catalogue, règle du remplaçant, repli sur la game la plus récente de l'équipe).
    /// Anti-spoiler : pour un match masqué, rien n'est lu dans ce match — ni composition, ni ligne « Cette game ».
    /// - Parameter games: games lues **sans les matchs masqués** (comme l'exige `Duel.lineup`).
    static func lineup(teamId: String, game: GameSummary?, masked: Bool, catalog: [Team], games: [GameSummary],
                       teamCode: String?) -> [String: DuelPlayer] {
        if !masked, let line = game?.line(teamId: teamId) {
            return Dictionary(line.players.map { player in
                (player.role, DuelPlayer(id: player.playerId,
                                         name: SeasonNames.player(player.playerId, raw: player.name, teamCode: teamCode,
                                                                  catalog: catalog),
                                         thisGame: player))
            }, uniquingKeysWith: { first, _ in first })
        }
        return Dictionary(Duel.lineup(teamId: teamId, catalog: catalog, games: games).compactMap { slot in
            slot.playerId.map { id in
                (slot.role, DuelPlayer(id: id, name: SeasonNames.player(id, raw: slot.name ?? id, teamCode: teamCode,
                                                                        catalog: catalog),
                                       thisGame: nil))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Lignes dans l'ordre des postes (`Duel.roles`) ; un poste vide des deux côtés n'a pas de ligne.
    static func lines(left: [String: DuelPlayer], right: [String: DuelPlayer]) -> [DuelLine] {
        Duel.roles.compactMap { role in
            guard left[role] != nil || right[role] != nil else { return nil }
            return DuelLine(role: role, left: left[role], right: right[role])
        }
    }

    /// Joueurs proposés par le sélecteur « Changer » : ceux des games en cache et des effectifs du catalogue, sans doublon,
    /// filtrés par la recherche (pseudo), triés par nom.
    static func candidates(query: String, games: [GameSummary], catalog: [Team], limit: Int = 40) -> [DuelPlayer] {
        var seen: [String: DuelPlayer] = [:]
        for team in catalog {
            for player in team.players ?? [] where seen[player.id] == nil {
                seen[player.id] = DuelPlayer(id: player.id, name: player.summonerName, thisGame: nil)
            }
        }
        for game in games {
            for player in game.blue.players + game.red.players where seen[player.playerId] == nil && !player.playerId.isEmpty {
                seen[player.playerId] = DuelPlayer(id: player.playerId, name: player.name, thisGame: nil)
            }
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return seen.values
            .filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
            .prefix(limit).map { $0 }
    }
}
