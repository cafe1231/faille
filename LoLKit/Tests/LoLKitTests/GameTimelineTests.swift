import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli construit le fil et la courbe avec la seule API publique.
import LoLKit

/// Fil des événements (spec fonctionnalités §4) et courbe de l'écart de gold (§5). Fixture `window_replay` : vraie
/// relecture à pas de 60 s de la game 1 de la finale LCS (TLAW bleu – LYON rouge, 04/10/2026), une frame par pas
/// (dernière frame de chaque fenêtre `startingTime` = 20:19:00, 20:20:00 … 20:54:00), capturée le 14/10/2026.
@Suite struct GameTimelineTests {
    private static let tlaw = "98926509885559666"
    private static let lyon = "99566405941863385"

    private func window(_ name: String) throws -> LiveWindow {
        try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data(name))
    }

    /// Début de la game : première frame de la fenêtre lue sans `startingTime` (20:18:26.892).
    private func gameStart() throws -> Date {
        try #require(try window("window_pregame").firstFrameTime)
    }

    private func line(_ event: TimelineEvent) -> String {
        let code = event.teamId == Self.tlaw ? "TLAW" : "LYON"
        let what: String
        switch event.kind {
        case .kills: what = "+\(event.count) kills" + (event.players.isEmpty ? "" : " (\(event.players.joined(separator: ", ")))")
        case let .dragon(type): what = "drake \(type)"
        case .baron: what = "+\(event.count) baron"
        case .tower: what = "+\(event.count) tours"
        case .inhibitor: what = "+\(event.count) inhib"
        }
        return "\(Format.clock(event.gameTime)) \(code) \(what)"
    }

    // Frames synthétiques (les cas que la vraie relecture ne couvre pas).
    private static let syntheticStart = "2026-10-04T20:18:26Z"

    private func player(_ name: String, kills: Int) -> PlayerLine {
        PlayerLine(role: "mid", champion: "Ahri", name: name, level: 6, kills: kills, deaths: 0, assists: 0,
                   creepScore: 50, gold: 3000)
    }

    private func snap(_ at: String, blue: TeamStats = TeamStats(), red: TeamStats = TeamStats(), redTeamId: String = "red",
                      bluePlayers: [PlayerLine] = []) -> GameSnapshot {
        GameSnapshot(gameId: "g", phase: .inGame, timestamp: date(at), blueTeamId: "blue", redTeamId: redTeamId,
                     blue: blue, red: red, bluePlayers: bluePlayers, redPlayers: [])
    }

    @Test func replaySnapshots() throws {
        let replay = try window("window_replay")
        let snapshots = replay.snapshots()
        #expect(snapshots.count == 36)
        #expect(snapshots.first?.timestamp == date("2026-10-04T20:19:09.466Z"))
        #expect(snapshots.last == replay.latestSnapshot())
        #expect(snapshots.last?.phase == .finished)
        #expect(snapshots.last?.blue == TeamStats(kills: 14, gold: 67995, towers: 8, inhibitors: 1, barons: 1,
                                                  dragons: ["chemtech", "ocean", "cloud", "cloud"]))
        #expect(snapshots[13].redPlayers.map(\.name) == ["LYON Dhokla", "LYON Inspired", "LYON Saint", "LYON Berserker",
                                                         "LYON Isles"])
    }

    @Test func timelineOfTheWholeGame() throws {
        let events = GameTimeline.events(from: try window("window_replay").snapshots(), firstFrameTime: try gameStart())
        #expect(events.map(line) == [
            "2:42 LYON +1 kills (LYON Saint)",
            "4:42 TLAW +1 kills (TLAW Josedeodo)",
            "6:42 TLAW +2 kills (TLAW Josedeodo, TLAW Yeon)",
            "6:42 TLAW drake chemtech",
            "9:42 TLAW +1 kills (TLAW Yeon)",
            "12:42 TLAW +1 kills (TLAW CoreJJ)",
            "12:42 TLAW drake ocean",
            "13:42 TLAW +2 kills (TLAW Josedeodo, TLAW CoreJJ)",
            "13:42 LYON +4 kills (LYON Inspired, LYON Saint, LYON Berserker)",
            "15:42 LYON +1 kills (LYON Inspired)",
            "17:42 TLAW +1 tours",
            "18:42 TLAW +2 tours",
            "18:42 LYON drake cloud",
            "22:42 TLAW +2 kills (TLAW Josedeodo, TLAW Quid)",
            "22:42 LYON +2 kills (LYON Dhokla, LYON Saint)",
            "23:43 LYON drake cloud",
            "23:43 LYON +1 tours",
            "24:43 LYON +1 kills (LYON Saint)",
            "27:42 TLAW +1 tours",
            "29:42 TLAW drake cloud",
            "30:43 LYON +1 kills (LYON Saint)",
            "30:43 LYON +2 tours",
            "32:42 TLAW +1 baron",
            "34:42 TLAW +5 kills (TLAW Morgan, TLAW Josedeodo, TLAW Quid, TLAW Yeon)",
            "34:42 TLAW drake cloud",
            "35:13 TLAW +4 tours",
            "35:13 TLAW +1 inhib",
        ])
    }

    @Test func firstFrameIsOnlyAReference() throws {
        // Ouverture tardive : la première frame lue (30:43) a déjà 9 kills bleus ; rien n'est inventé avant elle.
        let late = Array(try window("window_replay").snapshots()[30...])
        let events = GameTimeline.events(from: late, firstFrameTime: try gameStart())
        #expect(events.map(line) == [
            "32:42 TLAW +1 baron",
            "34:42 TLAW +5 kills (TLAW Morgan, TLAW Josedeodo, TLAW Quid, TLAW Yeon)",
            "34:42 TLAW drake cloud",
            "35:13 TLAW +4 tours",
            "35:13 TLAW +1 inhib",
        ])
        // L'ordre de remise n'importe pas ; une seule frame ne donne rien.
        #expect(GameTimeline.events(from: late.reversed(), firstFrameTime: try gameStart()) == events)
        #expect(GameTimeline.events(from: [late[0]], firstFrameTime: try gameStart()).isEmpty)
        #expect(GameTimeline.events(from: [], firstFrameTime: try gameStart()).isEmpty)
    }

    @Test func unattributableKillsHaveNoNames() {
        let start = date(Self.syntheticStart)
        let before = snap("2026-10-04T20:28:26Z", blue: TeamStats(kills: 3, towers: 3),
                          bluePlayers: [player("A", kills: 1), player("B", kills: 2)])
        // L'équipe gagne 2 kills mais un seul joueur en gagne 1 : « +2 kills » sans nom ; une tour en moins : rien.
        let after = snap("2026-10-04T20:28:36Z", blue: TeamStats(kills: 5, towers: 2),
                         bluePlayers: [player("A", kills: 2), player("B", kills: 2)])
        let events = GameTimeline.events(from: [before, after], firstFrameTime: start)
        #expect(events == [TimelineEvent(gameTime: 610, teamId: "blue", kind: .kills, count: 2, players: [])])
    }

    @Test func killsWithAnUnreliablePlayerListHaveNoNames() {
        let start = date(Self.syntheticStart)
        let before = snap("2026-10-04T20:28:26Z", blue: TeamStats(kills: 3),
                          bluePlayers: [player("A", kills: 1), player("B", kills: 2)])
        func events(after players: [PlayerLine]) -> [TimelineEvent] {
            let after = snap("2026-10-04T20:28:36Z", blue: TeamStats(kills: 4), bluePlayers: players)
            return GameTimeline.events(from: [before, after], firstFrameTime: start)
        }
        let anonymous = [TimelineEvent(gameTime: 610, teamId: "blue", kind: .kills, count: 1)]
        // Témoin : mêmes joueurs, A gagne le kill de l'équipe.
        #expect(events(after: [player("A", kills: 2), player("B", kills: 2)])
                == [TimelineEvent(gameTime: 610, teamId: "blue", kind: .kills, count: 1, players: ["A"])])
        // Effectif différent d'une frame à l'autre (joueur manquant ou en trop) : pas de suivi par position, pas de nom.
        #expect(events(after: [player("A", kills: 2)]) == anonymous)
        #expect(events(after: [player("A", kills: 2), player("B", kills: 2), player("C", kills: 0)]) == anonymous)
        // Pseudo qui change entre les deux frames (même position) : pas de nom.
        #expect(events(after: [player("A2", kills: 2), player("B", kills: 2)]) == anonymous)
        // Pseudo vide des deux côtés (métadonnées absentes) : pas de nom.
        let unnamedBefore = snap("2026-10-04T20:28:26Z", blue: TeamStats(kills: 3),
                                 bluePlayers: [player("", kills: 1), player("B", kills: 2)])
        let unnamedAfter = snap("2026-10-04T20:28:36Z", blue: TeamStats(kills: 4),
                                bluePlayers: [player("", kills: 2), player("B", kills: 2)])
        #expect(GameTimeline.events(from: [unnamedBefore, unnamedAfter], firstFrameTime: start) == anonymous)
    }

    @Test func severalDragonsInOneStepAreSeparateEventsInOrder() {
        let start = date(Self.syntheticStart)
        let before = snap("2026-10-04T20:28:26Z", red: TeamStats(dragons: ["ocean"]))
        let after = snap("2026-10-04T20:29:26Z", red: TeamStats(dragons: ["ocean", "cloud", "infernal"]))
        #expect(GameTimeline.events(from: [before, after], firstFrameTime: start) == [
            TimelineEvent(gameTime: 660, teamId: "red", kind: .dragon("cloud"), count: 1),
            TimelineEvent(gameTime: 660, teamId: "red", kind: .dragon("infernal"), count: 1),
        ])
    }

    @Test func aDropIsNeverAnEvent() {
        let start = date(Self.syntheticStart)
        let high = TeamStats(kills: 5, towers: 4, inhibitors: 1, barons: 1, dragons: ["ocean", "cloud"])
        let low = TeamStats(kills: 4, towers: 3, inhibitors: 0, barons: 0, dragons: ["ocean"])
        // Frame incohérente (kills, tours, inhibiteurs, barons, drakes en baisse) des deux côtés : rien.
        let drop = GameTimeline.events(from: [snap("2026-10-04T20:28:26Z", blue: high, red: high),
                                              snap("2026-10-04T20:29:26Z", blue: low, red: low)], firstFrameTime: start)
        #expect(drop.isEmpty)
        // Une baisse n'empêche pas de relever les vraies hausses du même pas.
        var mixed = low
        mixed.barons = 2
        #expect(GameTimeline.events(from: [snap("2026-10-04T20:28:26Z", blue: high),
                                           snap("2026-10-04T20:29:26Z", blue: mixed)], firstFrameTime: start)
                == [TimelineEvent(gameTime: 660, teamId: "blue", kind: .baron, count: 1)])
    }

    @Test func framesAtTheSameInstantKeepTheirGivenOrder() {
        let start = date(Self.syntheticStart)
        let first = snap("2026-10-04T20:28:26Z", blue: TeamStats(kills: 0, gold: 1000))
        let one = snap("2026-10-04T20:29:26Z", blue: TeamStats(kills: 1, gold: 1100))
        let two = snap("2026-10-04T20:29:26Z", blue: TeamStats(kills: 2, gold: 1200))
        // Même horodatage : l'ordre de remise départage (résultat déterministe, pas celui d'un tri sans garantie).
        #expect(GameTimeline.events(from: [first, one, two], firstFrameTime: start) == [
            TimelineEvent(gameTime: 660, teamId: "blue", kind: .kills, count: 1),
            TimelineEvent(gameTime: 660, teamId: "blue", kind: .kills, count: 1),
        ])
        #expect(GameTimeline.events(from: [first, two, one], firstFrameTime: start)
                == [TimelineEvent(gameTime: 660, teamId: "blue", kind: .kills, count: 2)])
        #expect(GoldSeries.points(from: [first, one, two], firstFrameTime: start, orientedTo: nil).map(\.difference)
                == [1000, 1100, 1200])
        #expect(GoldSeries.points(from: [first, two, one], firstFrameTime: start, orientedTo: nil).map(\.difference)
                == [1000, 1200, 1100])
    }

    @Test func goldCurveOfTheWholeGame() throws {
        let snapshots = try window("window_replay").snapshots()
        let points = GoldSeries.points(from: snapshots, firstFrameTime: try gameStart(), orientedTo: Self.tlaw)
        let expected: [(String, Int)] = [
            ("0:42", 0), ("1:42", 79), ("2:42", -619), ("3:43", -599), ("4:42", -90), ("5:42", -416), ("6:42", 744),
            ("7:42", 618), ("8:42", 799), ("9:42", 1705), ("10:42", 1437), ("11:42", 1750), ("12:42", 2852),
            ("13:42", 620), ("14:42", 862), ("15:42", 200), ("16:42", 200), ("17:42", 494), ("18:42", 1370),
            ("19:42", 1570), ("20:42", 1786), ("21:43", 1801), ("22:42", 1502), ("23:43", 1100), ("24:43", 484),
            ("25:42", 448), ("26:42", 790), ("27:42", 1242), ("28:42", 1162), ("29:42", 1437), ("30:43", 70),
            ("31:42", 329), ("32:42", 1122), ("33:42", 1810), ("34:42", 5674), ("35:13", 7663),
        ]
        #expect(points.map { Format.clock($0.gameTime) } == expected.map(\.0))
        #expect(points.map(\.difference) == expected.map(\.1))

        // Réorientée vers LYON (côté rouge) : l'écart change de signe ; sans équipe ou équipe inconnue : bleu − rouge.
        let lyon = GoldSeries.points(from: snapshots, firstFrameTime: try gameStart(), orientedTo: Self.lyon)
        #expect(lyon.map(\.difference) == expected.map { -$0.1 })
        #expect(GoldSeries.points(from: snapshots, firstFrameTime: try gameStart(), orientedTo: nil) == points)
        #expect(GoldSeries.points(from: snapshots.reversed(), firstFrameTime: try gameStart(), orientedTo: "autre") == points)
    }

    @Test func goldOrientationIsDecidedFrameByFrame() {
        let start = date(Self.syntheticStart)
        // Le côté rouge change d'une frame à l'autre : chaque point s'oriente d'après les équipes de sa propre frame.
        let first = snap("2026-10-04T20:28:26Z", blue: TeamStats(gold: 3000), red: TeamStats(gold: 2000), redTeamId: "r1")
        let second = snap("2026-10-04T20:29:26Z", blue: TeamStats(gold: 5000), red: TeamStats(gold: 4500), redTeamId: "r2")
        func differences(_ teamId: String?) -> [Int] {
            GoldSeries.points(from: [first, second], firstFrameTime: start, orientedTo: teamId).map(\.difference)
        }
        #expect(differences("r2") == [1000, -500])
        #expect(differences("r1") == [-1000, 500])
        #expect(differences("blue") == [1000, 500])
        #expect(differences(nil) == [1000, 500])
    }
}
