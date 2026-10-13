import Foundation
import Testing
@testable import LoLKit

@Suite struct LiveMatchBuilderTests {
    private let game1 = "115565004607949430"
    private let now = date("2026-10-04T20:39:30Z")

    private func snapshot(_ name: String) throws -> GameSnapshot {
        try #require(try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data(name)).latestSnapshot())
    }

    @Test func upcoming() {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .unstarted), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .upcoming)
        #expect(state.gameNumber == 1)
        #expect(state.seriesScore == [0, 0])
        #expect(state.stats == nil)
    }

    @Test func inGameWithStatsAndClock() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"),
                                           firstFrameTime: date("2026-10-04T20:18:26.892Z"),
                                           statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 1)
        #expect(state.statsAvailable)
        #expect(state.stats == [
            TeamStats(kills: 7, gold: 37442, towers: 3, inhibitors: 0, barons: 0, dragons: ["chemtech", "ocean"]),
            TeamStats(kills: 6, gold: 35882, towers: 0, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        ])
        // 20:38:29.593 − 20:18:26.892 = 1202,701 s de jeu au moment de la frame.
        let clock = try #require(state.gameClockStart)
        #expect(abs(clock.timeIntervalSince(now.addingTimeInterval(-1202.701))) < 0.01)
        #expect(state.updatedAt == now)
        #expect(state.staleDate == now.addingTimeInterval(180))
    }

    @Test func statsFollowTeamOrderNotSides() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress)],
                                  teams: [("99566405941863385", "LYON"), ("98926509885559666", "TLAW")])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"), firstFrameTime: nil,
                                           statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.stats?.map(\.kills) == [6, 7])
        #expect(state.gameClockStart == nil)
    }

    @Test func statsDisabled() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"), firstFrameTime: nil,
                                           statsDisabled: true, spoilerFree: false, now: now)
        #expect(state.phase == .inGame)
        #expect(!state.statsAvailable)
        #expect(state.stats == nil)
    }

    @Test func betweenGames() {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .betweenGames)
        #expect(state.gameNumber == 2)
        #expect(state.seriesScore == [1, 0])
    }

    @Test func feedFinishedBeforeApiUpdatesWins() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                           statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .betweenGames)
        #expect(state.gameNumber == 2)
    }

    @Test func deciderStaysInGameWhenFeedFinishesFirst() throws {
        let details = makeDetails(wins: [2, 2], games: [(5, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                           statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 5)
        #expect(state.stats?.first?.kills == 14)
    }

    @Test func matchPointStaysInGame() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, "g1x", .completed), (2, game1, .inProgress), (3, "g3", .unstarted)], bestOf: 3)
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                           statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 2)
    }

    @Test func betweenGamesNeverExceedsBestOf() {
        let details = makeDetails(wins: [1, 1], games: [(1, "a", .completed), (2, "b", .completed)], bestOf: 2)
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .betweenGames)
        #expect((state.gameNumber ?? 0) <= 2)
    }

    @Test func snapshotOfAnotherGameIsIgnored() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"), firstFrameTime: nil,
                                           statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 2)
        #expect(state.stats == nil)
    }

    @Test func finishedFromRealDetails() throws {
        let details = try JSONDecoder.lolesports()
            .decode(EventDetailsResponse.self, from: Fixture.data("getEventDetails")).data.event
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, spoilerFree: false, now: now)
        #expect(state.phase == .finished)
        #expect(state.seriesScore == [3, 1])
        #expect(state.winnerCode == "TLAW")
        #expect(state.gameNumber == nil)
    }

    @Test func spoilerFreeStripsEverythingButPhase() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, spoilerFree: true, now: now)
        #expect(state.phase == .inGame)
        #expect(state.spoilerFree)
        #expect(state.seriesScore == nil)
        #expect(state.gameNumber == nil)
        #expect(state.stats == nil)
        #expect(state.winnerCode == nil)
        #expect(state.gameClockStart == nil)
    }

    @Test func attributesUseFollowedColors() throws {
        var follows = FollowList()
        let kc = try catalogTeam("KC")
        follows.follow(kc)
        follows.setAutoColor("#5B8CFF", id: kc.id)
        let event = makeEvent(id: "115660588583171786", state: .inProgress,
                              teams: [makeTeam("C9", id: "98767991877340524", name: "Cloud9 Kia"), makeTeam("KC", id: kc.id, name: "Karmine Corp")])
        let attributes = LiveMatchBuilder.attributes(for: event, follows: follows)
        #expect(attributes.matchId == "115660588583171786")
        #expect(attributes.leagueName == "Mondial")
        #expect(attributes.bestOf == 5)
        #expect(attributes.teams.map(\.code) == ["C9", "KC"])
        #expect(attributes.teams.map(\.colorHex) == [nil, "#5B8CFF"])
    }

    @Test func payloadStaysSmall() throws {
        let details = makeDetails(wins: [2, 2], games: [(5, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"),
                                           firstFrameTime: date("2026-10-04T20:18:26.892Z"),
                                           statsDisabled: false, spoilerFree: false, now: now)
        let attributes = LiveMatchAttributes(matchId: "115565004607949429", leagueName: "Mondial", bestOf: 5, teams: [
            .init(id: "98926509885559666", code: "TLAW", name: "Team Liquid Alienware", colorHex: "#5B8CFF"),
            .init(id: "99566405941863385", code: "LYON", name: "LYON", colorHex: nil),
        ])
        let stateBytes = try JSONEncoder().encode(state).count
        let attributeBytes = try JSONEncoder().encode(attributes).count
        #expect(stateBytes < 1024)
        #expect(stateBytes + attributeBytes < 4096)
    }
}
