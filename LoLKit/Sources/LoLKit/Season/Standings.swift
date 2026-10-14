import Foundation

/// Classements et tableaux d'un tournoi (`getStandings?tournamentId=`) : étapes → sections → matchs (avec ids d'équipe
/// et résultats) et classements. Encodé tel quel dans `cache/season/standings/<tournamentId>.json`.
public struct Standings: Codable, Sendable, Equatable {
    public let stages: [StandingsStage]

    public init(stages: [StandingsStage]) {
        self.stages = stages
    }

    private enum CodingKeys: String, CodingKey {
        case stages
    }

    /// Une étape illisible est ignorée ; `stages` absent → aucune étape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stages = (try? container.decodeIfPresent(LossyArray<StandingsStage>.self, forKey: .stages))?.elements ?? []
    }

    /// Tous les matchs de toutes les étapes, dans l'ordre de l'API.
    public var allMatches: [BracketMatch] {
        stages.flatMap { $0.sections.flatMap(\.matches) }
    }

    /// Étape qui contient le match `matchId` ; nil s'il n'y figure pas.
    public func stage(containing matchId: String) -> StandingsStage? {
        stages.first { stage in stage.sections.contains { $0.matches.contains { $0.id == matchId } } }
    }

    /// Le match `matchId` ; nil s'il n'y figure pas.
    public func match(id matchId: String) -> BracketMatch? {
        allMatches.first { $0.id == matchId }
    }
}

/// Une étape : `regular_season`, `playoffs`, `play_ins`, `swiss`, `knockouts`…
public struct StandingsStage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let slug: String
    public let sections: [StandingsSection]

    public init(id: String, name: String, slug: String, sections: [StandingsSection]) {
        self.id = id
        self.name = name
        self.slug = slug
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, sections
    }

    /// Seul `id` est indispensable ; nom et slug absents → chaîne vide, sections illisibles ignorées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        slug = (try? container.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        sections = (try? container.decodeIfPresent(LossyArray<StandingsSection>.self, forKey: .sections))?.elements ?? []
    }
}

public struct StandingsSection: Codable, Sendable, Equatable {
    public let name: String
    public let matches: [BracketMatch]
    /// Vide pour le Mondial (jamais de `rankings`, mesuré sur 2025 et 2026) et les play-offs.
    public let rankings: [Ranking]

    public init(name: String, matches: [BracketMatch], rankings: [Ranking]) {
        self.name = name
        self.matches = matches
        self.rankings = rankings
    }

    private enum CodingKeys: String, CodingKey {
        case name, matches, rankings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        matches = (try? container.decodeIfPresent(LossyArray<BracketMatch>.self, forKey: .matches))?.elements ?? []
        rankings = (try? container.decodeIfPresent(LossyArray<Ranking>.self, forKey: .rankings))?.elements ?? []
    }
}

/// Un match d'un tableau, avec les ids d'équipe. Équipe pas encore connue : `id "0"`, `code "TBD"`, `result` nil
/// (`MatchTeam.isPlaceholder`).
public struct BracketMatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let state: EventState
    public let teams: [MatchTeam]

    public init(id: String, state: EventState, teams: [MatchTeam]) {
        self.id = id
        self.state = state
        self.teams = teams
    }

    private enum CodingKeys: String, CodingKey {
        case id, state, teams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = (try? container.decodeIfPresent(EventState.self, forKey: .state)) ?? .unknown
        teams = (try? container.decodeIfPresent(LossyArray<MatchTeam>.self, forKey: .teams))?.elements ?? []
    }
}

/// Une place du classement (ex aequo possibles : plusieurs équipes au même `ordinal`).
public struct Ranking: Codable, Sendable, Equatable {
    public let ordinal: Int
    public let teams: [RankedTeam]

    public init(ordinal: Int, teams: [RankedTeam]) {
        self.ordinal = ordinal
        self.teams = teams
    }

    private enum CodingKeys: String, CodingKey {
        case ordinal, teams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ordinal = (try? container.decodeIfPresent(Int.self, forKey: .ordinal)) ?? 0
        teams = (try? container.decodeIfPresent(LossyArray<RankedTeam>.self, forKey: .teams))?.elements ?? []
    }
}

/// Une équipe classée et son bilan de séries (`record {wins, losses}` dans l'API, aplati ici).
public struct RankedTeam: Codable, Sendable, Equatable {
    public let id: String
    public let code: String
    public let name: String
    public let image: String?
    public let wins: Int
    public let losses: Int

    public init(id: String, code: String, name: String, image: String?, wins: Int, losses: Int) {
        self.id = id
        self.code = code
        self.name = name
        self.image = image
        self.wins = wins
        self.losses = losses
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, image, record
    }

    private struct Record: Codable {
        var wins: Int?
        var losses: Int?
    }

    /// Seul `id` est indispensable ; `record` absent → 0-0.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        let record = try? container.decodeIfPresent(Record.self, forKey: .record)
        wins = record?.wins ?? 0
        losses = record?.losses ?? 0
    }

    /// Même forme que l'API (`record` imbriqué) : le cache se relit avec le même décodeur.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(Record(wins: wins, losses: losses), forKey: .record)
    }
}

struct StandingsResponse: Decodable {
    struct Payload: Decodable {
        let standings: LossyArray<Standings>
    }

    let data: Payload
}
