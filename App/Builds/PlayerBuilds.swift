import Foundation
import LoLKit

/// Un joueur de la section « Joueurs » (spec fonctionnalités §3) : sa ligne du flux `window` (rôle, champion, pseudo,
/// niveau, KDA, CS, gold), jointe à son détail du flux `details` (objets, runes, ordre des sorts, part des dégâts…) par
/// `participantId`.
struct PlayerBuild: Identifiable, Equatable, Sendable {
    let participantId: Int
    let line: PlayerLine
    /// nil tant que `details` n'est pas lu (les objets et les runes restent alors des cases vides).
    let details: ParticipantDetails?

    var id: Int { participantId }

    /// Niveau le plus frais : celui de `details` s'il est là.
    var level: Int { details?.level ?? line.level }
}

/// Assemblage de la draft et des builds à partir des données déjà chargées (aucune requête ici).
enum PlayerBuilds {
    /// Balises (Totem de vision, Altération : longue-vue, Lentille de l'oracle), quand le catalogue des objets manque.
    static let knownTrinkets: Set<Int> = [3340, 3363, 3364]

    /// Joueurs d'une équipe dans l'ordre du flux, qui donne toujours les joueurs par `participantId` : bleu = 1 à 5,
    /// rouge = 6 à 10. [] si l'équipe ne joue pas cette game.
    static func rows(snapshot: GameSnapshot, details: GameDetails?, teamId: String) -> [PlayerBuild] {
        let first: Int
        let lines: [PlayerLine]
        if teamId == snapshot.blueTeamId {
            first = 1
            lines = snapshot.bluePlayers
        } else if teamId == snapshot.redTeamId {
            first = 6
            lines = snapshot.redPlayers
        } else {
            return []
        }
        return lines.enumerated().map { index, line in
            PlayerBuild(participantId: first + index, line: line, details: details?.latest(participantId: first + index))
        }
    }

    /// Draft : les champions (ids Data Dragon) de chaque équipe, dans l'ordre donné ([] pour une équipe absente).
    static func draft(snapshot: GameSnapshot, teamIds: [String]) -> [[String]] {
        teamIds.map { snapshot.players(for: $0)?.map(\.champion) ?? [] }
    }

    /// Objets d'un joueur, balise à part : par le catalogue Data Dragon (tag « Trinket ») s'il est chargé, sinon par les
    /// ids des balises connues.
    static func inventory(_ items: [Int], catalog: ItemCatalog?) -> ItemCatalog.Inventory {
        if let catalog { return catalog.inventory(items) }
        let trinket = items.first { knownTrinkets.contains($0) }
        return ItemCatalog.Inventory(items: items.filter { $0 != trinket }, trinket: trinket)
    }

    /// Les six cases d'objets (vides à la fin).
    static func slots(_ inventory: ItemCatalog.Inventory) -> [Int?] {
        (0..<6).map { inventory.items.indices.contains($0) ? inventory.items[$0] : nil }
    }

    /// Sorts d'invocateur à montrer : ceux de Leaguepedia (game terminée) ; à défaut, Châtiment pour le jungler — tout
    /// jungler le prend (sans lui, pas d'objet de jungle), ce n'est pas une donnée du flux mais une déduction sûre, qui ne
    /// révèle rien ; sinon aucun.
    static func summonerSpells(role: String, leaguepedia: [String]?) -> [String] {
        if let leaguepedia, !leaguepedia.isEmpty { return leaguepedia }
        return role.lowercased() == "jungle" ? ["SummonerSmite"] : []
    }

    /// « 27 % » ; « — » si la valeur manque.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((min(max(value, 0), 1) * 100).rounded())) %"
    }
}
