/// Une ligue ou compétition (`getLeagues`). `name` est en français avec `hl=fr-FR` (« Mondial »).
public struct League: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
    public let region: String?
    public let image: String?
    public let priority: Int?

    /// Compétitions internationales toujours incluses dans le calendrier.
    public static let internationalSlugs: Set<String> = ["worlds", "msi", "first_stand"]
}

struct LeaguesResponse: Decodable {
    struct Payload: Decodable {
        let leagues: LossyArray<League>
    }

    let data: Payload
}
