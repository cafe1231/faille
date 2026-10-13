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

    public init(id: String, slug: String, name: String, code: String, image: String?, status: String?, homeLeague: HomeLeague?) {
        self.id = id
        self.slug = slug
        self.name = name
        self.code = code
        self.image = image
        self.status = status
        self.homeLeague = homeLeague
    }

    public var isActive: Bool { status == "active" }
}

struct TeamsResponse: Decodable {
    struct Payload: Decodable {
        let teams: LossyArray<Team>
    }

    let data: Payload
}
