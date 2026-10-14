import Foundation

/// Un tournoi d'une ligue (`getTournamentsForLeague`), ex. `lec_split_3_2026` du 23/07 au 20/09 (spec saison §1.2).
public struct TournamentRef: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let slug: String
    /// Dates « yyyy-MM-dd », telles que l'API les écrit.
    public let startDate: String
    public let endDate: String
    /// Ligue du tournoi : l'API ne le répète pas dans chaque tournoi, `LoLClient.tournaments(leagueId:)` le remplit.
    public var leagueId: String

    public init(id: String, slug: String, startDate: String, endDate: String, leagueId: String) {
        self.id = id
        self.slug = slug
        self.startDate = startDate
        self.endDate = endDate
        self.leagueId = leagueId
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, startDate, endDate, leagueId
    }

    /// Décodage tolérant : seul `id` est indispensable ; un champ absent ou illisible devient une chaîne vide.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = (try? container.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        startDate = (try? container.decodeIfPresent(String.self, forKey: .startDate)) ?? ""
        endDate = (try? container.decodeIfPresent(String.self, forKey: .endDate)) ?? ""
        leagueId = (try? container.decodeIfPresent(String.self, forKey: .leagueId)) ?? ""
    }

    /// Année de début : la saison est l'année civile, un tournoi à cheval compte dans l'année de son début (§1.2).
    public var year: Int? { Int(startDate.prefix(4)) }

    /// Actif si `today` (« yyyy-MM-dd ») est dans [début, fin + 2 jours] (§1.2 : relu au plus toutes les 30 min) ;
    /// terminé sinon (lu une fois, jamais relu). Faux si une date est illisible.
    public func isActive(today: String) -> Bool {
        guard Self.day(startDate) != nil, let end = Self.adding(days: 2, to: endDate) else { return false }
        return startDate <= today && today <= end
    }

    /// « yyyy-MM-dd » + `days` jours (calendrier grégorien, UTC) ; nil si la date est illisible.
    static func adding(days: Int, to string: String) -> String? {
        guard let date = day(string), let moved = utc.date(byAdding: .day, value: days, to: date) else { return nil }
        let parts = utc.dateComponents([.year, .month, .day], from: moved)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func day(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

struct TournamentsResponse: Decodable {
    struct Payload: Decodable {
        let leagues: [LeagueTournaments]
    }

    struct LeagueTournaments: Decodable {
        let tournaments: LossyArray<TournamentRef>
    }

    let data: Payload
}
