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
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .upcoming)
        #expect(state.gameNumber == 1)
        #expect(state.seriesScore == [0, 0])
        #expect(state.stats == nil)
    }

    @Test func inGameWithStatsAndClock() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"),
                                           firstFrameTime: date("2026-10-04T20:18:26.892Z"),
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
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
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.stats?.map(\.kills) == [6, 7])
        #expect(state.gameClockStart == nil)
    }

    @Test func statsDisabled() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"), firstFrameTime: nil,
                                           statsDisabled: true, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .inGame)
        #expect(!state.statsAvailable)
        #expect(state.stats == nil)
    }

    @Test func betweenGames() {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .betweenGames)
        #expect(state.gameNumber == 2)
        #expect(state.seriesScore == [1, 0])
    }

    @Test func feedFinishedBeforeApiUpdatesWins() throws {
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .betweenGames)
        #expect(state.gameNumber == 2)
    }

    @Test func deciderStaysInGameWhenFeedFinishesFirst() throws {
        let details = makeDetails(wins: [2, 2], games: [(5, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 5)
        #expect(state.stats?.first?.kills == 14)
    }

    @Test func matchPointStaysInGame() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, "g1x", .completed), (2, game1, .inProgress), (3, "g3", .unstarted)], bestOf: 3)
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 2)
    }

    @Test func betweenGamesNeverExceedsBestOf() {
        let details = makeDetails(wins: [1, 1], games: [(1, "a", .completed), (2, "b", .completed)], bestOf: 2)
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .betweenGames)
        #expect(state.gameNumber == 2)
    }

    @Test func snapshotOfAnotherGameIsIgnored() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"), firstFrameTime: nil,
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 2)
        #expect(state.stats == nil)
    }

    @Test func finishedFromRealDetails() throws {
        let details = try JSONDecoder.lolesports()
            .decode(EventDetailsResponse.self, from: Fixture.data("getEventDetails")).data.event
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(state.phase == .finished)
        #expect(state.seriesScore == [3, 1])
        #expect(state.winnerCode == "TLAW")
        #expect(state.gameNumber == nil)
    }

    /// TLAW (équipe de `makeDetails`) suivie en anti-spoiler.
    private func spoilerFreeFollows() -> FollowList {
        FollowList(teams: [FollowedTeam(id: "98926509885559666", code: "TLAW", name: "TLAW", spoilerFree: true)])
    }

    @Test func spoilerFreeStripsEverythingButPhase() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                           follows: spoilerFreeFollows(), revealed: [], now: now)
        #expect(state.phase == .inGame)
        #expect(state.spoilerFree)
        #expect(state.seriesScore == nil)
        #expect(state.gameNumber == nil)
        #expect(state.stats == nil)
        #expect(state.winnerCode == nil)
        #expect(state.gameClockStart == nil)
        #expect(state.gameClockStoppedAt == nil)
    }

    @Test func maskingIsDecidedByTheBuilderFromFollowsAndReveals() throws {
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .inProgress)])
        let revealed = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                              follows: spoilerFreeFollows(), revealed: [details.id], now: now)
        #expect(!revealed.spoilerFree)
        #expect(revealed.seriesScore == [1, 0])

        // Équipe suivie sans anti-spoiler, ou aucune équipe suivie : rien n'est masqué.
        let plain = FollowList(teams: [FollowedTeam(id: "98926509885559666", code: "TLAW", name: "TLAW")])
        for follows in [plain, FollowList()] {
            let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                               follows: follows, revealed: [], now: now)
            #expect(!state.spoilerFree)
            #expect(state.seriesScore == [1, 0])
        }
    }

    @Test func maskedFinishedSeriesKeepsOnlyThePhase() throws {
        let details = try JSONDecoder.lolesports()
            .decode(EventDetailsResponse.self, from: Fixture.data("getEventDetails")).data.event
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                           follows: spoilerFreeFollows(), revealed: [], now: now)
        #expect(state.phase == .finished)
        #expect(state.spoilerFree)
        #expect(state.seriesScore == nil)
        #expect(state.winnerCode == nil)
    }

    @Test func maskedBetweenGamesLooksLikeLive() {
        // Spec §8 : seuls « En direct », « Terminé » et « À venir » sont montrés. « Entre deux games » révélerait qu'une game vient de finir.
        let details = makeDetails(wins: [1, 0], games: [(1, game1, .completed), (2, "g2", .unstarted)])
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                           follows: spoilerFreeFollows(), revealed: [], now: now)
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == nil)
        #expect(state.seriesScore == nil)
        #expect(state.spoilerFree)
    }

    @Test func attributesUseFollowedColors() throws {
        var follows = FollowList()
        let kc = try catalogTeam("KC")
        follows.follow(kc)
        follows.setAutoColor("#5B8CFF", id: kc.id)
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress)],
                                  teams: [("98767991877340524", "C9"), (kc.id, "KC")])
        let attributes = try #require(LiveMatchBuilder.attributes(for: details, follows: follows))
        #expect(attributes.matchId == details.id)
        #expect(attributes.leagueName == "LCS")
        #expect(attributes.bestOf == 5)
        #expect(attributes.teams.map(\.id) == ["98767991877340524", kc.id])
        #expect(attributes.teams.map(\.code) == ["C9", "KC"])
        #expect(attributes.teams.map(\.colorHex) == [nil, "#5B8CFF"])
    }

    @Test func attributesNeedTeamIds() throws {
        let details = EventDetails(
            id: "m", league: LeagueRef(id: nil, slug: "lcs", name: "LCS", image: nil),
            match: EventDetails.Match(strategy: Strategy(type: nil, count: 3),
                                      teams: [makeTeam("KC", id: "111692118851466302"), makeTeam("C9")], games: []),
            streams: nil)
        #expect(LiveMatchBuilder.attributes(for: details, follows: FollowList()) == nil)
    }

    @Test func primaryTeamIsFirstFollowed() throws {
        let kc = try catalogTeam("KC"), t1 = try catalogTeam("T1")
        var follows = FollowList()
        follows.follow(t1)
        follows.follow(kc)
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress)], teams: [(kc.id, "KC"), (t1.id, "T1")])
        let attributes = try #require(LiveMatchBuilder.attributes(for: details, follows: follows))
        #expect(attributes.primaryTeamIndex == 1)   // T1, suivie avant KC, est la 2e équipe du match

        let unfollowed = try #require(LiveMatchBuilder.attributes(for: details, follows: FollowList()))
        #expect(unfollowed.primaryTeamIndex == nil)
    }

    @Test func stateOrderMatchesAttributes() throws {
        // Équipes dans l'ordre inverse des côtés du flux (bleu = TLAW, rouge = LYON).
        let lyon = "99566405941863385", tlaw = "98926509885559666"
        let details = makeDetails(wins: [1, 0], games: [(1, "g0", .completed), (2, game1, .inProgress)],
                                  teams: [(lyon, "LYON"), (tlaw, "TLAW")])
        let attributes = try #require(LiveMatchBuilder.attributes(for: details, follows: FollowList()))
        let snap = try snapshot("window_ingame")
        let state = LiveMatchBuilder.state(details: details, snapshot: snap, firstFrameTime: nil, statsDisabled: false,
                                           follows: FollowList(), revealed: [], now: now)
        #expect(attributes.teams.map(\.id) == [lyon, tlaw])
        let stats = try #require(state.stats)
        #expect(stats == attributes.teams.compactMap { snap.stats(for: $0.id) })
        #expect(stats[0] == snap.red)    // LYON, côté rouge
        #expect(state.seriesScore == [1, 0])
        #expect(state.seriesScore == details.match.teams.map(\.gameWins))
    }

    @Test func payloadStaysSmall() throws {
        let details = makeDetails(wins: [2, 2], games: [(5, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"),
                                           firstFrameTime: date("2026-10-04T20:18:26.892Z"),
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        let attributes = LiveMatchAttributes(matchId: "115565004607949429", leagueName: "Mondial", bestOf: 5, teams: [
            .init(id: "98926509885559666", code: "TLAW", name: "Team Liquid Alienware", colorHex: "#5B8CFF"),
            .init(id: "99566405941863385", code: "LYON", name: "LYON", colorHex: nil),
        ], primaryTeamIndex: 0)
        let stateBytes = try JSONEncoder().encode(state).count
        let attributeBytes = try JSONEncoder().encode(attributes).count
        #expect(stateBytes < 1024)
        #expect(stateBytes + attributeBytes < 4096)
    }
}
