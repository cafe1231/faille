import Foundation
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

    @Test func startingTimeIsOneMinuteBackRoundedToTenSeconds() {
        #expect(LiveStatsTime.startingTime(now: date("2026-10-13T12:00:37Z")) == date("2026-10-13T11:59:30Z"))
        #expect(LiveStatsTime.startingTime(now: date("2026-10-13T12:00:00Z")) == date("2026-10-13T11:59:00Z"))
    }
}
