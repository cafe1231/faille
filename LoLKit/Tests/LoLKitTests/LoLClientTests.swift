import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import LoLKit

@Suite struct LoLClientTests {
    @Test func leaguesSendKeyAndLanguage() async throws {
        let fake = FakeTransport()
        try await fake.on("getLeagues", fixture: "getLeagues")
        let leagues = try await LoLClient(transport: fake).leagues()
        #expect(leagues.count == 51)

        let request = try #require(await fake.requests.first)
        #expect(request.url.path == "/persisted/gw/getLeagues")
        #expect(queryValue(request.url, "hl") == "fr-FR")
        #expect(request.headers["x-api-key"] == LoLClient.publicAPIKey)
    }

    @Test func scheduleJoinsLeagueIds() async throws {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        let events = try await LoLClient(transport: fake).schedule(leagueIds: ["98767975604431411", "98767991302996019"])
        #expect(events.count == 6)
        let url = try #require(await fake.requests.first?.url)
        #expect(queryValue(url, "leagueId") == "98767975604431411,98767991302996019")
    }

    @Test func liveTeamsAndDetails() async throws {
        let fake = FakeTransport()
        try await fake.on("getLive", fixture: "getLive")
        try await fake.on("getTeams", fixture: "getTeams")
        try await fake.on("getEventDetails", fixture: "getEventDetails")
        let client = LoLClient(transport: fake)

        #expect(try await client.live().first?.statsDisabled == true)
        #expect(try await client.teams().count == 9)
        let details = try await client.eventDetails(matchId: "115565004607949429")
        #expect(details.match.teams.map(\.code) == ["TLAW", "LYON"])
        let url = try #require(await fake.requests.last?.url)
        #expect(queryValue(url, "id") == "115565004607949429")
    }

    @Test func windowUsesStartingTimeAndNoKey() async throws {
        let fake = FakeTransport()
        try await fake.on("window/115565004607949430", fixture: "window_ingame")
        let window = try await LoLClient(transport: fake)
            .window(gameId: "115565004607949430", startingTime: date("2026-10-04T20:38:20Z"))
        #expect(window.latestSnapshot()?.blue.kills == 7)

        let request = try #require(await fake.requests.first)
        #expect(request.url.host == "feed.lolesports.com")
        #expect(queryValue(request.url, "startingTime") == "2026-10-04T20:38:20.000Z")
        #expect(request.headers["x-api-key"] == nil)
    }

    @Test func windowErrors() async throws {
        let fake = FakeTransport()
        try await fake.on("window/404", status: 404, body: "Stats are disabled for game 404")
        try await fake.on("window/204", status: 204)
        try await fake.on("window/500", status: 500)
        let client = LoLClient(transport: fake)

        await #expect(throws: LoLAPIError.statsDisabled) { try await client.window(gameId: "404", startingTime: nil) }
        await #expect(throws: LoLAPIError.noData) { try await client.window(gameId: "204", startingTime: nil) }
        await #expect(throws: LoLAPIError.http(status: 500)) { try await client.window(gameId: "500", startingTime: nil) }
    }

    @Test func apiErrorStatus() async throws {
        let fake = FakeTransport()
        try await fake.on("getLive", status: 403, body: "{\"message\":\"Forbidden\"}")
        await #expect(throws: LoLAPIError.http(status: 403)) { try await LoLClient(transport: fake).live() }
    }

    @Test func realTransportIgnoresTheHTTPCache() throws {
        // LoLKit a son propre cache disque : un getLive venu du cache HTTP masquerait le mode avion.
        let url = try #require(URL(string: "https://esports-api.lolesports.com/persisted/gw/getLive?hl=fr-FR"))
        let request = URLSessionTransport.makeRequest(url, headers: ["x-api-key": "k"])
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.timeoutInterval == 15)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "k")
    }

    @Test func startingTimeIsTheDelayBackRoundedToTenSeconds() {
        #expect(LiveStatsTime.delays.first == 90)
        #expect(LiveStatsTime.startingTime(now: date("2026-10-13T12:00:37Z")) == date("2026-10-13T11:59:00Z"))
        #expect(LiveStatsTime.startingTime(now: date("2026-10-13T12:00:00Z")) == date("2026-10-13T11:58:30Z"))
        #expect(LiveStatsTime.startingTime(now: date("2026-10-13T12:00:37Z"), delay: 120) == date("2026-10-13T11:58:30Z"))
    }

    /// Réponse réelle du flux (14/10/2026, Demacia Cup) quand la fenêtre demandée est trop récente.
    private let aheadOfBroadcast = #"{"httpStatus":400,"errorCode":"BAD_QUERY_PARAMETER","message":"disallowed window with end time less than 80 sec old (was -9.73 sec old). requested window: [2026-10-14T09:37:30Z, 2026-10-14T09:37:40Z]) ahead of broadcast."}"#

    @Test func liveWindowStepsBackWhenTheFeedIsAheadOfTheBroadcast() async throws {
        let fake = FakeTransport()
        try await fake.on("startingTime=2026-10-13T11:59:00", status: 400, body: aheadOfBroadcast)
        try await fake.on("window/step-back", fixture: "window_ingame")
        let client = LoLClient(transport: fake)

        let window = try await client.liveWindow(gameId: "step-back", now: date("2026-10-13T12:00:37Z"))
        #expect(window.latestSnapshot()?.blue.kills == 7)
        let urls = await fake.requests.map(\.url)
        #expect(urls.compactMap { queryValue($0, "startingTime") } == ["2026-10-13T11:59:00.000Z", "2026-10-13T11:58:50.000Z"])

        // Le délai qui a marché (100 s) est retenu pour cette game : la relecture suivante ne refait pas l'essai refusé.
        _ = try await client.liveWindow(gameId: "step-back", now: date("2026-10-13T12:00:57Z"))
        let next = try #require(await fake.requests.last?.url)
        #expect(await fake.requests.count == 3)
        #expect(queryValue(next, "startingTime") == "2026-10-13T11:59:10.000Z")
    }

    @Test func liveWindowGivesUpAfterTheLongestDelay() async throws {
        let fake = FakeTransport()
        try await fake.on("window/always-ahead", status: 400, body: aheadOfBroadcast)
        await #expect(throws: LoLAPIError.http(status: 400)) {
            try await LoLClient(transport: fake).liveWindow(gameId: "always-ahead", now: date("2026-10-13T12:00:37Z"))
        }
        #expect(await fake.requests.count == LiveStatsTime.delays.count)
    }

    @Test func liveWindowDoesNotRetryOtherErrors() async throws {
        let fake = FakeTransport()
        try await fake.on("window/no-stats", status: 404, body: "Stats are disabled")
        await #expect(throws: LoLAPIError.statsDisabled) {
            try await LoLClient(transport: fake).liveWindow(gameId: "no-stats", now: date("2026-10-13T12:00:37Z"))
        }
        #expect(await fake.requests.count == 1)
    }
}
