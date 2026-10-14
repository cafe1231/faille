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
        try await feed("window", gameId: gameId, startingTime: startingTime, as: LiveWindow.self)
    }

    /// Dernières frames d'une game en cours. Le flux refuse (400 « ahead of broadcast ») une fenêtre dont la fin a moins
    /// de 80 s (mesuré le 14/10/2026 à 0,5 s près sur 78 requêtes) : on recule par paliers (`steppingBack`).
    public func liveWindow(gameId: String, now: Date) async throws -> LiveWindow {
        try await steppingBack(gameId: gameId, now: now) { startingTime in
            try await window(gameId: gameId, startingTime: startingTime)
        }
    }

    /// Lecture d'une route du flux livestats (`window`, `details`), sans clé : 200 vide ou 204 = pas encore de données,
    /// 404 = stats désactivées par Riot pour cette game.
    func feed<T: Decodable & Sendable>(_ route: String, gameId: String, startingTime: Date?,
                                       as type: T.Type) async throws -> T {
        var components = URLComponents(string: "\(Self.feedBase)/\(route)/\(gameId)")!
        if let startingTime {
            components.queryItems = [URLQueryItem(name: "startingTime", value: LoLDate.format(startingTime))]
        }
        let response = try await transport.get(components.url!, headers: [:])
        switch response.status {
        case 200 where !response.body.isEmpty:
            return try JSONDecoder.lolesports().decode(T.self, from: response.body)
        case 200, 204:
            throw LoLAPIError.noData
        case 404:
            throw LoLAPIError.statsDisabled
        default:
            throw LoLAPIError.http(status: response.status)
        }
    }

    /// Recul commun à `liveWindow` et `details(gameId:now:)` : essaie `read` avec les délais de `LiveStatsTime.delays`, à
    /// partir du dernier délai accepté pour cette game, passe au suivant sur un 400, et retient le premier accepté. Les
    /// deux routes partagent cette mémoire (même flux, même seuil de 80 s).
    func steppingBack<T: Sendable>(gameId: String, now: Date,
                                   _ read: (Date) async throws -> T) async throws -> T {
        let first = await LiveStatsTime.memory.delayIndex(for: gameId)
        for index in first..<LiveStatsTime.delays.count {
            do {
                let value = try await read(LiveStatsTime.startingTime(now: now, delay: LiveStatsTime.delays[index]))
                await LiveStatsTime.memory.remember(index, for: gameId)
                return value
            } catch LoLAPIError.http(status: 400) {
                continue
            }
        }
        throw LoLAPIError.http(status: 400)
    }

    private func api<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        var components = URLComponents(string: "\(Self.apiBase)/\(endpoint)")!
        components.queryItems = [URLQueryItem(name: "hl", value: language)] + query
        let response = try await transport.get(components.url!, headers: ["x-api-key": Self.publicAPIKey])
        guard response.status == 200 else { throw LoLAPIError.http(status: response.status) }
        return try JSONDecoder.lolesports().decode(T.self, from: response.body)
    }
}

/// Heure à demander au flux livestats : un délai dans le passé, arrondi aux 10 s inférieures. Le flux refuse une fenêtre
/// trop récente (en avance sur la diffusion) : `LoLClient.liveWindow` et `LoLClient.details(gameId:now:)` essaient ces
/// délais dans l'ordre.
public enum LiveStatsTime {
    /// 90 s : fin de fenêtre entre 80 et 90 s, la donnée la plus fraîche que le flux accepte ; 100 s couvre une horloge
    /// en retard d'une seconde ; les paliers suivants, un seuil plus long sur un autre match.
    public static let delays: [TimeInterval] = [90, 100, 120, 180, 300, 600]

    public static func startingTime(now: Date, delay: TimeInterval = delays[0]) -> Date {
        let seconds = now.timeIntervalSince1970 - delay
        return Date(timeIntervalSince1970: (seconds / 10).rounded(.down) * 10)
    }

    /// Délai accepté par game, gardé pour la durée du processus (le seuil ne change pas pendant un match) ; partagé par
    /// `window` et `details`.
    static let memory = DelayMemory()

    actor DelayMemory {
        private var indexByGame: [String: Int] = [:]

        func delayIndex(for gameId: String) -> Int { indexByGame[gameId] ?? 0 }

        func remember(_ index: Int, for gameId: String) { indexByGame[gameId] = index }
    }
}
