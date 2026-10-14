import Foundation

/// Réponse de `livestats/v1/details/{gameId}` : environ 10 s de frames, chacune avec le détail des 10 joueurs (objets,
/// runes, ordre de montée des sorts, part des dégâts…). Pas de `gameMetadata` ici : champion, pseudo et côté se lisent
/// dans `LiveWindow.gameMetadata` par `participantId` (1-5 bleu, 6-10 rouge). Lourd : l'appli ne le lit qu'avec le Détail
/// ouvert, au plus toutes les 60 s, jamais pour un match masqué (spec fonctionnalités §3).
public struct GameDetails: Codable, Sendable, Equatable {
    public let frames: [DetailsFrame]

    public init(frames: [DetailsFrame]) {
        self.frames = frames
    }

    /// Dernière frame : l'état le plus récent.
    public var latestFrame: DetailsFrame? { frames.last }

    /// Détail du joueur `participantId` à la dernière frame ; nil s'il n'y figure pas.
    public func latest(participantId: Int) -> ParticipantDetails? {
        latestFrame?.participants.first { $0.participantId == participantId }
    }
}

public struct DetailsFrame: Codable, Sendable, Equatable {
    public let rfc460Timestamp: Date
    public let participants: [ParticipantDetails]

    public init(rfc460Timestamp: Date, participants: [ParticipantDetails]) {
        self.rfc460Timestamp = rfc460Timestamp
        self.participants = participants
    }
}

/// Runes d'un joueur : arbre principal (`styleId`), arbre secondaire (`subStyleId`) et runes choisies (`perks`, la première
/// est la rune principale ; les dernières sont des fragments de stats, absents de `runesReforged.json`).
public struct PerkMetadata: Codable, Sendable, Equatable {
    public let styleId: Int
    public let subStyleId: Int
    public let perks: [Int]

    public init(styleId: Int, subStyleId: Int, perks: [Int]) {
        self.styleId = styleId
        self.subStyleId = subStyleId
        self.perks = perks
    }

    /// Rune principale (clé de voûte).
    public var keystone: Int? { perks.first }
}

/// Un joueur dans une frame de `details`.
public struct ParticipantDetails: Codable, Sendable, Equatable {
    public let participantId: Int
    public let level: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let totalGoldEarned: Int
    /// Participation aux kills de l'équipe, de 0 à 1.
    public let killParticipation: Double?
    /// Part des dégâts aux champions de l'équipe, de 0 à 1.
    public let championDamageShare: Double?
    public let wardsPlaced: Int?
    public let wardsDestroyed: Int?
    /// Ids d'objets dans l'ordre du flux, balise comprise (`ItemCatalog.inventory` la met à part).
    public let items: [Int]
    public let perkMetadata: PerkMetadata?
    /// Ordre de montée des sorts : « Q », « W », « E », « R ».
    public let abilities: [String]

    public init(participantId: Int, level: Int, kills: Int, deaths: Int, assists: Int, creepScore: Int,
                totalGoldEarned: Int, killParticipation: Double?, championDamageShare: Double?, wardsPlaced: Int?,
                wardsDestroyed: Int?, items: [Int], perkMetadata: PerkMetadata?, abilities: [String]) {
        self.participantId = participantId
        self.level = level
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.totalGoldEarned = totalGoldEarned
        self.killParticipation = killParticipation
        self.championDamageShare = championDamageShare
        self.wardsPlaced = wardsPlaced
        self.wardsDestroyed = wardsDestroyed
        self.items = items
        self.perkMetadata = perkMetadata
        self.abilities = abilities
    }

    private enum CodingKeys: String, CodingKey {
        case participantId, level, kills, deaths, assists, creepScore, totalGoldEarned, killParticipation
        case championDamageShare, wardsPlaced, wardsDestroyed, items, perkMetadata, abilities
    }

    /// Décodage tolérant : seul `participantId` est indispensable ; un champ absent ou illisible prend une valeur neutre.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        participantId = try container.decode(Int.self, forKey: .participantId)
        level = (try? container.decodeIfPresent(Int.self, forKey: .level)) ?? 0
        kills = (try? container.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
        deaths = (try? container.decodeIfPresent(Int.self, forKey: .deaths)) ?? 0
        assists = (try? container.decodeIfPresent(Int.self, forKey: .assists)) ?? 0
        creepScore = (try? container.decodeIfPresent(Int.self, forKey: .creepScore)) ?? 0
        totalGoldEarned = (try? container.decodeIfPresent(Int.self, forKey: .totalGoldEarned)) ?? 0
        killParticipation = try? container.decodeIfPresent(Double.self, forKey: .killParticipation)
        championDamageShare = try? container.decodeIfPresent(Double.self, forKey: .championDamageShare)
        wardsPlaced = try? container.decodeIfPresent(Int.self, forKey: .wardsPlaced)
        wardsDestroyed = try? container.decodeIfPresent(Int.self, forKey: .wardsDestroyed)
        items = (try? container.decodeIfPresent([Int].self, forKey: .items)) ?? []
        perkMetadata = try? container.decodeIfPresent(PerkMetadata.self, forKey: .perkMetadata)
        abilities = (try? container.decodeIfPresent([String].self, forKey: .abilities)) ?? []
    }
}
