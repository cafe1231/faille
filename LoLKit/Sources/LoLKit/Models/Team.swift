/// Une équipe du catalogue (`getTeams`). `homeLeague.name` correspond à `League.name`.
public struct Team: Codable, Sendable, Equatable, Identifiable {
    public struct HomeLeague: Codable, Sendable, Equatable {
        public let name: String
        public let region: String?

        public init(name: String, region: String? = nil) {
            self.name = name
            self.region = region
        }
    }

    public let id: String
    public let slug: String
    public let name: String
    public let code: String
    public let image: String?
    public let status: String?
    public let homeLeague: HomeLeague?
    /// Effectif (`players[]` du catalogue, spec saison §1.5) ; nil si l'API n'en donne pas ou s'il est illisible.
    public let players: [TeamPlayer]?

    public init(id: String, slug: String, name: String, code: String, image: String?, status: String?, homeLeague: HomeLeague?,
                players: [TeamPlayer]? = nil) {
        self.id = id
        self.slug = slug
        self.name = name
        self.code = code
        self.image = image
        self.status = status
        self.homeLeague = homeLeague
        self.players = players
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, code, image, status, homeLeague, players
    }

    /// Mêmes exigences qu'avant l'effectif ; `players` absent ou illisible → nil (l'équipe reste dans le catalogue),
    /// un joueur illisible est ignoré.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        code = try container.decode(String.self, forKey: .code)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        homeLeague = try container.decodeIfPresent(HomeLeague.self, forKey: .homeLeague)
        players = (try? container.decodeIfPresent(LossyArray<TeamPlayer>.self, forKey: .players))?.elements
    }

    public var isActive: Bool { status == "active" }
}

/// Un joueur de l'effectif d'une équipe (`getTeams` : `players[]`). `id` = `esportsPlayerId` du flux livestats.
public struct TeamPlayer: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let summonerName: String
    public let image: String?
    /// `top`, `jungle`, `mid`, `bottom`, `support` (ou autre valeur de l'API, ex. `none`).
    public let role: String?

    public init(id: String, summonerName: String, image: String?, role: String?) {
        self.id = id
        self.summonerName = summonerName
        self.image = image
        self.role = role
    }

    private enum CodingKeys: String, CodingKey {
        case id, summonerName, image, role
    }

    /// `id` et `summonerName` indispensables ; photo et rôle illisibles → nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        summonerName = try container.decode(String.self, forKey: .summonerName)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
    }
}

struct TeamsResponse: Decodable {
    struct Payload: Decodable {
        let teams: LossyArray<Team>
    }

    let data: Payload
}
