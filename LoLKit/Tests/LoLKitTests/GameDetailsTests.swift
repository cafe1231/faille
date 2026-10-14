import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli lit `details` avec la seule API publique.
import LoLKit

/// Flux `livestats/v1/details` (spec fonctionnalités §3). Fixture : vraie réponse de la game 1 de la finale LCS
/// (TLAW – LYON, 04/10/2026), `startingTime=2026-10-04T20:38:20.000Z`, réduite à sa première et sa dernière frame.
@Suite struct GameDetailsTests {
    private static let gameId = "115565004607949430"

    /// Réponse réelle du flux `details` (14/10/2026, Demacia Cup) quand la fenêtre demandée est trop récente.
    private let aheadOfBroadcast = #"{"httpStatus":400,"errorCode":"BAD_QUERY_PARAMETER","message":"disallowed window with end time less than 80 sec old (was 21.34 sec old). requested window: [2026-10-14T11:28:50Z, 2026-10-14T11:29:00Z]) ahead of broadcast. current time: 2026-10-14T11:29:21.337178735Z","implementationDetails":"filtered"}"#

    @Test func decodesTheRealDetails() async throws {
        let fake = FakeTransport()
        try await fake.on("details/\(Self.gameId)", fixture: "details_ingame")
        let details = try await LoLClient(transport: fake).details(gameId: Self.gameId,
                                                                   startingTime: date("2026-10-04T20:38:20Z"))
        let request = try #require(await fake.requests.first)
        #expect(request.url.host == "feed.lolesports.com")
        #expect(request.url.path == "/livestats/v1/details/115565004607949430")
        #expect(queryValue(request.url, "startingTime") == "2026-10-04T20:38:20.000Z")
        #expect(request.headers["x-api-key"] == nil)

        #expect(details.frames.count == 2)
        #expect(details.latestFrame?.rfc460Timestamp == date("2026-10-04T20:38:29.593Z"))
        #expect(details.latestFrame?.participants.map(\.participantId) == Array(1...10))
        #expect(details.frames.first?.participants.first?.totalGoldEarned == 7502)

        // Joueur 1 (TLAW Morgan, Ambessa, haut).
        let morgan = try #require(details.latest(participantId: 1))
        #expect(morgan.level == 14)
        #expect(morgan.kills == 0)
        #expect(morgan.deaths == 1)
        #expect(morgan.assists == 0)
        #expect(morgan.creepScore == 204)
        #expect(morgan.totalGoldEarned == 7520)
        #expect(morgan.killParticipation == 0)
        #expect(abs((morgan.championDamageShare ?? 0) - 0.2743) < 0.0001)
        #expect(morgan.wardsPlaced == 7)
        #expect(morgan.wardsDestroyed == 0)
        #expect(morgan.items == [1054, 2031, 6692, 1001, 3364, 3071, 1036])
        #expect(morgan.perkMetadata == PerkMetadata(styleId: 8400, subStyleId: 8300,
                                                    perks: [8437, 8401, 8444, 8451, 8345, 8347, 5008, 5011]))
        #expect(morgan.perkMetadata?.keystone == 8437)
        #expect(morgan.abilities.joined() == "QWEQQRQEQEREEW")

        // Joueur 2 (TLAW Josedeodo, Lee Sin) : mêmes valeurs que sa ligne dans window_ingame (12, 3/1/3, 169 CS, 8359).
        let josedeodo = try #require(details.latest(participantId: 2))
        #expect(josedeodo.level == 12)
        #expect(josedeodo.kills == 3)
        #expect(josedeodo.deaths == 1)
        #expect(josedeodo.assists == 3)
        #expect(josedeodo.creepScore == 169)
        #expect(josedeodo.totalGoldEarned == 8359)
        #expect(abs((josedeodo.killParticipation ?? 0) - 0.8571) < 0.0001)
        #expect(josedeodo.wardsDestroyed == 8)
        #expect(details.latest(participantId: 99) == nil)
        #expect(LoLClient.detailsInterval == 60)
    }

    @Test func stepsBackLikeTheWindow() async throws {
        let fake = FakeTransport()
        try await fake.on("startingTime=2026-10-13T11:59:00", status: 400, body: aheadOfBroadcast)
        try await fake.on("details/step-back-details", fixture: "details_ingame")
        let client = LoLClient(transport: fake)

        let details = try await client.details(gameId: "step-back-details", now: date("2026-10-13T12:00:37Z"))
        #expect(details.frames.count == 2)
        let urls = await fake.requests.map(\.url)
        #expect(urls.compactMap { queryValue($0, "startingTime") } == ["2026-10-13T11:59:00.000Z", "2026-10-13T11:58:50.000Z"])

        // Le délai accepté (100 s) est retenu : la lecture suivante ne refait pas l'essai refusé.
        _ = try await client.details(gameId: "step-back-details", now: date("2026-10-13T12:00:57Z"))
        #expect(await fake.requests.count == 3)
        #expect(queryValue(try #require(await fake.requests.last?.url), "startingTime") == "2026-10-13T11:59:10.000Z")
    }

    @Test func windowAndDetailsShareTheAcceptedDelay() async throws {
        let fake = FakeTransport()
        try await fake.on("startingTime=2026-10-13T11:59:00", status: 400, body: aheadOfBroadcast)
        try await fake.on("window/shared-delay", fixture: "window_ingame")
        try await fake.on("details/shared-delay", fixture: "details_ingame")
        let client = LoLClient(transport: fake)

        _ = try await client.liveWindow(gameId: "shared-delay", now: date("2026-10-13T12:00:37Z"))
        _ = try await client.details(gameId: "shared-delay", now: date("2026-10-13T12:00:57Z"))
        let last = try #require(await fake.requests.last?.url)
        #expect(last.path == "/livestats/v1/details/shared-delay")
        // Une seule requête `details`, directement au délai retenu par `window` (100 s).
        #expect(await fake.requests.filter { $0.url.path.contains("/details/") }.count == 1)
        #expect(queryValue(last, "startingTime") == "2026-10-13T11:59:10.000Z")
    }

    @Test func detailsErrors() async throws {
        let fake = FakeTransport()
        try await fake.on("details/404", status: 404, body: "Stats are disabled for game 404")
        try await fake.on("details/204", status: 204)
        try await fake.on("details/always-ahead", status: 400, body: aheadOfBroadcast)
        let client = LoLClient(transport: fake)

        await #expect(throws: LoLAPIError.statsDisabled) { try await client.details(gameId: "404", startingTime: nil) }
        await #expect(throws: LoLAPIError.noData) { try await client.details(gameId: "204", startingTime: nil) }
        await #expect(throws: LoLAPIError.statsDisabled) {
            try await client.details(gameId: "404", now: date("2026-10-13T12:00:37Z"))
        }
        let before = await fake.requests.count
        await #expect(throws: LoLAPIError.http(status: 400)) {
            try await client.details(gameId: "always-ahead", now: date("2026-10-13T12:00:37Z"))
        }
        #expect(await fake.requests.count - before == LiveStatsTime.delays.count)
    }

    @Test func toleratesMissingFields() throws {
        let json = #"{"frames":[{"rfc460Timestamp":"2026-10-04T20:38:29.593Z","participants":[{"participantId":3,"items":"?"}]}]}"#
        let details = try JSONDecoder.lolesports().decode(GameDetails.self, from: Data(json.utf8))
        let player = try #require(details.latest(participantId: 3))
        #expect(player.items.isEmpty)
        #expect(player.abilities.isEmpty)
        #expect(player.perkMetadata == nil)
        #expect(player.level == 0)
        #expect(player.championDamageShare == nil)
    }
}
