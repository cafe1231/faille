import Foundation

public enum LoLAPIError: Error, Equatable, Sendable {
    /// Réponse HTTP inattendue (403 : la clé publique a sans doute changé).
    case http(status: Int)
    /// 404 sur le flux livestats : Riot ne fournit pas les stats de cette game.
    case statsDisabled
    /// Flux livestats vide (game pas encore commencée).
    case noData
}

/// Client de l'API lolesports (non officielle) et du flux livestats.
public struct LoLClient: Sendable {
    /// Clé publique envoyée par le site lolesports.com à chaque visiteur. Ce n'est pas un secret.
    public static let publicAPIKey = "0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z"
    static let apiBase = "https://esports-api.lolesports.com/persisted/gw"
    static let feedBase = "https://feed.lolesports.com/livestats/v1"

    private let transport: any HTTPTransport
    private let language: String

    public init(transport: any HTTPTransport = URLSessionTransport(), language: String = "fr-FR") {
        self.transport = transport
        self.language = language
    }

    public func leagues() async throws -> [League] {
        try await api("getLeagues", as: LeaguesResponse.self).data.leagues.elements
    }

    public func teams() async throws -> [Team] {
        try await api("getTeams", as: TeamsResponse.self).data.teams.elements
    }

    /// Calendrier des ligues demandées (une page, environ ±6 semaines autour d'aujourd'hui).
    public func schedule(leagueIds: [String]) async throws -> [MatchEvent] {
        let query = leagueIds.isEmpty ? [] : [URLQueryItem(name: "leagueId", value: leagueIds.joined(separator: ","))]
        return try await api("getSchedule", query: query, as: ScheduleResponse.self).data.schedule.events.elements
    }

    public func live() async throws -> [MatchEvent] {
        try await api("getLive", as: ScheduleResponse.self).data.schedule.events.elements
    }

    public func eventDetails(matchId: String) async throws -> EventDetails {
        try await api("getEventDetails", query: [URLQueryItem(name: "id", value: matchId)], as: EventDetailsResponse.self).data.event
    }

    /// Frames de stats d'une game. Sans `startingTime`, le flux renvoie le début de la game.
    public func window(gameId: String, startingTime: Date?) async throws -> LiveWindow {
        var components = URLComponents(string: "\(Self.feedBase)/window/\(gameId)")!
        if let startingTime {
            components.queryItems = [URLQueryItem(name: "startingTime", value: LoLDate.format(startingTime))]
        }
        let response = try await transport.get(components.url!, headers: [:])
        switch response.status {
        case 200 where !response.body.isEmpty:
            return try JSONDecoder.lolesports().decode(LiveWindow.self, from: response.body)
        case 200, 204:
            throw LoLAPIError.noData
        case 404:
            throw LoLAPIError.statsDisabled
        default:
            throw LoLAPIError.http(status: response.status)
        }
    }

    private func api<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        var components = URLComponents(string: "\(Self.apiBase)/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "hl", value: language)] + query
        let response = try await transport.get(components.url!, headers: ["x-api-key": Self.publicAPIKey])
        guard response.status == 200 else { throw LoLAPIError.http(status: response.status) }
        return try JSONDecoder.lolesports().decode(T.self, from: response.body)
    }
}

/// Heure à demander au flux livestats : environ 1 min dans le passé, arrondie aux 10 s inférieures.
public enum LiveStatsTime {
    public static let delay: TimeInterval = 60

    public static func startingTime(now: Date) -> Date {
        let seconds = now.timeIntervalSince1970 - delay
        return Date(timeIntervalSince1970: (seconds / 10).rounded(.down) * 10)
    }
}
