import Foundation
import Testing
@testable import LoLKit

@Suite struct LiveWindowTests {
    private let tlaw = "98926509885559666"
    private let lyon = "99566405941863385"

    private func window(_ name: String) throws -> LiveWindow {
        try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data(name))
    }

    @Test func inGameSnapshot() throws {
        let snap = try #require(try window("window_ingame").latestSnapshot())
        #expect(snap.gameId == "115565004607949430")
        #expect(snap.phase == .inGame)
        #expect(snap.timestamp == date("2026-10-04T20:38:29.593Z"))
        // La première frame précède la dernière : `firstFrameTime` et `latestSnapshot` ne peuvent pas être confondus.
        #expect(try window("window_ingame").firstFrameTime == date("2026-10-04T20:38:29.592Z"))
        #expect(snap.blueTeamId == tlaw)
        #expect(snap.blue == TeamStats(kills: 7, gold: 37442, towers: 3, inhibitors: 0, barons: 0, dragons: ["chemtech", "ocean"]))
        #expect(snap.red == TeamStats(kills: 6, gold: 35882, towers: 0, inhibitors: 0, barons: 0, dragons: ["cloud"]))
        #expect(snap.stats(for: lyon) == snap.red)
        #expect(snap.stats(for: "inconnu") == nil)

        let jungle = try #require(snap.players(for: tlaw)?[1])
        #expect(jungle == PlayerLine(role: "jungle", champion: "LeeSin", name: "TLAW Josedeodo",
                                     level: 12, kills: 3, deaths: 1, assists: 3, creepScore: 169, gold: 8359))
        #expect(snap.redPlayers.count == 5)
    }

    @Test func finishedSnapshot() throws {
        let snap = try #require(try window("window_finished").latestSnapshot())
        #expect(snap.phase == .finished)
        #expect(snap.blue.barons == 1)
        #expect(snap.blue.inhibitors == 1)
        #expect(snap.blue.towers == 8)
        #expect(snap.blue.dragons.count == 4)
        #expect(snap.red.gold == 60332)
    }

    @Test func pregameGivesGameStart() throws {
        let pregame = try window("window_pregame")
        #expect(pregame.firstFrameTime == date("2026-10-04T20:18:26.892Z"))
        #expect(pregame.latestSnapshot()?.blue.gold == 0)
    }

    @Test func emptyWindowHasNoSnapshot() throws {
        let json = #"""
        {"esportsGameId":"1","gameMetadata":{"blueTeamMetadata":{"esportsTeamId":"a","participantMetadata":[]},
         "redTeamMetadata":{"esportsTeamId":"b","participantMetadata":[]}},"frames":[]}
        """#
        let empty = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Data(json.utf8))
        #expect(empty.latestSnapshot() == nil)
        #expect(empty.firstFrameTime == nil)
    }

    @Test func pausedStateIsRecognised() {
        #expect(GamePhase(apiValue: "paused") == .paused)
        #expect(GamePhase(apiValue: "in_game") == .inGame)
        #expect(GamePhase(apiValue: "finished") == .finished)
        #expect(GamePhase(apiValue: "nouveau") == .inGame)
    }
}
