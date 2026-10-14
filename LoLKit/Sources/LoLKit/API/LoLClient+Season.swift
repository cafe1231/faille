import Foundation

/// Une page de `getSchedule` et ses jetons de pagination (calendrier complet, spec saison §3.2) : `older` / `newer`
/// sont les `pageToken` des pages voisines ; `newer` nil = rien de plus récent.
public struct SchedulePageResult: Sendable, Equatable {
    public let events: [MatchEvent]
    public let older: String?
    public let newer: String?

    public init(events: [MatchEvent], older: String?, newer: String?) {
        self.events = events
        self.older = older
        self.newer = newer
    }
}

extension LoLClient {
    /// Tournois d'une ligue, du plus récent au plus ancien (`getTournamentsForLeague`), `leagueId` rempli.
    public func tournaments(leagueId: String) async throws -> [TournamentRef] {
        let response = try await api("getTournamentsForLeague", query: [URLQueryItem(name: "leagueId", value: leagueId)],
                                     as: TournamentsResponse.self)
        return response.data.leagues.flatMap(\.tournaments.elements).map { tournament in
            var filled = tournament
            filled.leagueId = leagueId
            return filled
        }
    }

    /// Matchs terminés d'un tournoi avec les ids de toutes leurs games (`getCompletedEvents`). Pas d'id d'équipe.
    public func completedEvents(tournamentId: String) async throws -> [CompletedMatch] {
        try await api("getCompletedEvents", query: [URLQueryItem(name: "tournamentId", value: tournamentId)],
                      as: CompletedEventsResponse.self).data.schedule.events.elements.map(\.completed)
    }

    /// Classements et tableaux d'un tournoi (`getStandings`) ; aucune étape si l'API n'en donne pas.
    public func standings(tournamentId: String) async throws -> Standings {
        try await api("getStandings", query: [URLQueryItem(name: "tournamentId", value: tournamentId)],
                      as: StandingsResponse.self).data.standings.elements.first ?? Standings(stages: [])
    }

    /// Une page du calendrier (80 matchs) : sans `pageToken`, la page autour d'aujourd'hui (comme `schedule`).
    public func schedulePage(leagueIds: [String], pageToken: String?) async throws -> SchedulePageResult {
        var query = leagueIds.isEmpty ? [] : [URLQueryItem(name: "leagueId", value: leagueIds.joined(separator: ","))]
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        let schedule = try await api("getSchedule", query: query, as: SchedulePageResponse.self).data.schedule
        return SchedulePageResult(events: schedule.events.elements, older: schedule.pages?.older,
                                  newer: schedule.pages?.newer)
    }
}

/// `getSchedule` avec `pages {older, newer}`.
struct SchedulePageResponse: Decodable {
    struct Payload: Decodable {
        let schedule: Schedule
    }

    struct Schedule: Decodable {
        let pages: Pages?
        let events: LossyArray<MatchEvent>
    }

    struct Pages: Decodable {
        let older: String?
        let newer: String?
    }

    let data: Payload
}
