import Foundation
import LoLKit

/// Détails par joueur d'exemple (aperçus et tests, aucune requête) : objets, runes et ordre des sorts typiques du rôle de
/// chaque joueur d'une frame, construits avec les inits publics de LoLKit.
enum BuildSamples {
    private struct Kit: Sendable {
        let items: [Int]
        let perks: PerkMetadata
        let abilities: [String]
        let damageShare: Double
        let wards: Int
    }

    private static let mid = Kit(
        items: [6655, 3020, 3157, 1058, 3340],
        perks: PerkMetadata(styleId: 8200, subStyleId: 8300, perks: [8229, 8226, 8210, 8237, 8345, 8347, 5008, 5008]),
        abilities: ["Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"],
        damageShare: 0.31, wards: 9
    )

    private static let kits: [String: Kit] = [
        "top": Kit(items: [3071, 3047, 3053, 1029, 3340],
                   perks: PerkMetadata(styleId: 8400, subStyleId: 8300,
                                       perks: [8437, 8401, 8444, 8451, 8345, 8347, 5008, 5011]),
                   abilities: ["Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"],
                   damageShare: 0.22, wards: 8),
        "jungle": Kit(items: [6692, 3111, 3071, 1036, 3364],
                      perks: PerkMetadata(styleId: 8000, subStyleId: 8400,
                                          perks: [8010, 9111, 9104, 8299, 8444, 8453, 5005, 5008]),
                      abilities: ["Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"],
                      damageShare: 0.16, wards: 14),
        "mid": mid,
        "bottom": Kit(items: [3031, 3006, 3094, 1038, 3363],
                      perks: PerkMetadata(styleId: 8000, subStyleId: 8100,
                                          perks: [8008, 9111, 9104, 8017, 8135, 8106, 5005, 5008]),
                      abilities: ["Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"],
                      damageShare: 0.27, wards: 10),
        "support": Kit(items: [3190, 3158, 2055, 3364],
                       perks: PerkMetadata(styleId: 8400, subStyleId: 8300,
                                           perks: [8439, 8463, 8473, 8242, 8345, 8347, 5008, 5001]),
                       abilities: ["E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"],
                       damageShare: 0.06, wards: 31),
    ]

    /// Détails d'une frame : un joueur par ligne du flux (bleu 1-5, rouge 6-10), objets, runes et sorts de son rôle,
    /// ordre de montée coupé à son niveau.
    static func details(for snapshot: GameSnapshot) -> GameDetails {
        let lines = snapshot.bluePlayers + snapshot.redPlayers
        let blueKills = max(1, snapshot.blue.kills)
        let redKills = max(1, snapshot.red.kills)
        let participants = lines.enumerated().map { index, line in
            let kit = kits[line.role.lowercased()] ?? mid
            let teamKills = index < 5 ? blueKills : redKills
            return ParticipantDetails(
                participantId: index + 1, level: line.level, kills: line.kills, deaths: line.deaths,
                assists: line.assists, creepScore: line.creepScore, totalGoldEarned: line.gold,
                killParticipation: min(1, Double(line.kills + line.assists) / Double(teamKills)),
                championDamageShare: kit.damageShare, wardsPlaced: kit.wards, wardsDestroyed: kit.wards / 4,
                items: kit.items, perkMetadata: kit.perks, abilities: Array(kit.abilities.prefix(line.level))
            )
        }
        return GameDetails(frames: [DetailsFrame(rfc460Timestamp: snapshot.timestamp, participants: participants)])
    }
}
