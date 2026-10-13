import Foundation
import Testing
@testable import LoLKit

/// Le JSON de la Live Activity est un contrat : l'appli (v1) et le futur serveur de push (phase 2) l'échangent.
/// `live_contract.json` est la référence ; ces tests cassent si un nom de clé, un format de date ou une phase change.
@Suite struct LiveContractTests {
    private struct Contract: Codable, Equatable {
        let attributes: LiveMatchAttributes
        let state: LiveMatchState
    }

    private let lyon = "99566405941863385"
    private let tlaw = "98926509885559666"
    private let game = "115565004607949430"
    private let now = date("2026-10-04T20:39:30Z")

    private var expected: Contract {
        Contract(
            attributes: LiveMatchAttributes(
                matchId: "115565004607949429", leagueName: "LCS", bestOf: 5,
                teams: [
                    .init(id: lyon, code: "LYON", name: "LYON", colorHex: "#FF5C7A"),
                    .init(id: tlaw, code: "TLAW", name: "Team Liquid Alienware", colorHex: "#5B8CFF"),
                ],
                primaryTeamIndex: 1),
            state: LiveMatchState(
                phase: .inGame, seriesScore: [1, 0], gameNumber: 2,
                gameClockStart: Date(timeIntervalSinceReferenceDate: 813_414_000),
                gameClockStoppedAt: nil,
                stats: [
                    TeamStats(kills: 6, gold: 35882, towers: 0, inhibitors: 0, barons: 0, dragons: ["cloud"]),
                    TeamStats(kills: 7, gold: 37442, towers: 3, inhibitors: 0, barons: 0, dragons: ["chemtech", "ocean"]),
                ],
                statsAvailable: true, spoilerFree: false, winnerCode: nil,
                updatedAt: Date(timeIntervalSinceReferenceDate: 813_415_300)))
    }

    private func golden() throws -> String {
        try String(decoding: Fixture.data("live_contract"), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snapshot(_ name: String) throws -> GameSnapshot {
        try #require(try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data(name)).latestSnapshot())
    }

    @Test func encodingMatchesTheGoldenFile() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(expected), as: UTF8.self)
        #expect(json == (try golden()))
    }

    @Test func goldenFileDecodesToTheExpectedValues() throws {
        let decoded = try JSONDecoder().decode(Contract.self, from: Data(try golden().utf8))
        #expect(decoded == expected)
    }

    @Test func unknownPhaseDecodesAsInGame() throws {
        let json = #"{"phase":"nouvellePhase","statsAvailable":true,"spoilerFree":false,"updatedAt":813415300}"#
        let state = try JSONDecoder().decode(LiveMatchState.self, from: Data(json.utf8))
        #expect(state.phase == .inGame)
        #expect(state.gameClockStoppedAt == nil)
    }

    @Test func rawPhasesArePinned() throws {
        let phases: [LiveMatchState.Phase] = [.upcoming, .inGame, .betweenGames, .finished]
        let raw = try JSONDecoder().decode([String].self, from: JSONEncoder().encode(phases))
        #expect(raw == ["upcoming", "inGame", "betweenGames", "finished"])
    }

    @Test func everyOptionalKeyIsPinned() throws {
        var state = expected.state
        state.gameClockStoppedAt = Date(timeIntervalSinceReferenceDate: 813_415_000)
        state.winnerCode = "TLAW"
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        let keys = try #require(object as? [String: Any]).keys.sorted()
        #expect(keys == ["gameClockStart", "gameClockStoppedAt", "gameNumber", "phase", "seriesScore",
                         "spoilerFree", "stats", "statsAvailable", "updatedAt", "winnerCode"])
    }

    @Test func clockStopsWhenTheFeedIsFinishedOrPaused() throws {
        let details = makeDetails(wins: [2, 2], games: [(5, game, .inProgress)])
        let finished = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_finished"), firstFrameTime: nil,
                                              statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(finished.phase == .inGame)
        #expect(finished.gameClockStoppedAt == now)

        let running = try snapshot("window_ingame")
        let live = LiveMatchBuilder.state(details: details, snapshot: running, firstFrameTime: nil,
                                          statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(live.gameClockStoppedAt == nil)

        let paused = GameSnapshot(gameId: running.gameId, phase: .paused, timestamp: running.timestamp,
                                  blueTeamId: running.blueTeamId, redTeamId: running.redTeamId,
                                  blue: running.blue, red: running.red,
                                  bluePlayers: running.bluePlayers, redPlayers: running.redPlayers)
        let stopped = LiveMatchBuilder.state(details: details, snapshot: paused, firstFrameTime: nil,
                                             statsDisabled: false, follows: FollowList(), revealed: [], now: now)
        #expect(stopped.gameClockStoppedAt == now)
    }

    @Test func clockRunsEvenWhenStatsAreDisabled() throws {
        // Spec §6.3 : sans stats, la Live Activity affiche quand même score + chrono + message.
        let details = makeDetails(wins: [0, 0], games: [(1, game, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"),
                                           firstFrameTime: date("2026-10-04T20:18:26.892Z"),
                                           statsDisabled: true, follows: FollowList(), revealed: [], now: now)
        #expect(state.stats == nil)
        #expect(!state.statsAvailable)
        let clock = try #require(state.gameClockStart)
        #expect(abs(clock.timeIntervalSince(now.addingTimeInterval(-1202.701))) < 0.01)
    }

    @Test func maskedClearsTheClockStop() {
        var state = expected.state
        state.gameClockStoppedAt = now
        let masked = state.masked()
        #expect(masked.gameClockStart == nil)
        #expect(masked.gameClockStoppedAt == nil)
    }
}
