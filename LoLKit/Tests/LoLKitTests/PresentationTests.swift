import Foundation
import Testing
@testable import LoLKit

@Suite struct SpoilerTests {
    /// KC normal, T1 en anti-spoiler.
    private func follows() throws -> FollowList {
        var list = FollowList()
        list.follow(try catalogTeam("KC"))
        list.follow(try catalogTeam("T1"))
        list.setSpoilerFree(true, id: "98767991853197861")
        return list
    }

    private let liveGames = [
        GameRef(number: 1, id: "g1", state: .completed, teams: nil),
        GameRef(number: 2, id: "g2", state: .inProgress, teams: nil),
    ]

    @Test func spoilerFreeTeamMasksLiveMatch() throws {
        let event = makeEvent(id: "m1", state: .inProgress,
                              teams: [makeTeam("T1", id: "98767991853197861", wins: 1), makeTeam("FLY", id: "f", wins: 0)],
                              games: liveGames)
        let line = Presenter.scoreLine(for: event, follows: try follows(), revealed: [])
        #expect(line.isMasked)
        #expect(line.score == nil)
        #expect(line.status == .live(gameNumber: nil))
        #expect(line.teamCodes == ["T1", "FLY"])
    }

    @Test func revealUnmasks() throws {
        let event = makeEvent(id: "m1", state: .inProgress,
                              teams: [makeTeam("T1", id: "98767991853197861", wins: 1), makeTeam("FLY", id: "f", wins: 0)],
                              games: liveGames)
        let line = Presenter.scoreLine(for: event, follows: try follows(), revealed: ["m1"])
        #expect(!line.isMasked)
        #expect(line.score == [1, 0])
        #expect(line.status == .live(gameNumber: 2))
    }

    @Test func oneSpoilerFreeTeamIsEnoughToMask() throws {
        let teams = [makeTeam("KC", name: "Karmine Corp"), makeTeam("T1", name: "T1")]
        #expect(SpoilerPolicy.isMasked(teams, matchId: "m2", follows: try follows(), revealed: []))
        #expect(!SpoilerPolicy.isMasked([makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")], matchId: "m3", follows: try follows(), revealed: []))
    }

    @Test func finishedMatchHidesWinnerWhenMasked() throws {
        let teams = [makeTeam("T1", id: "98767991853197861", wins: 3), makeTeam("GEN", id: "g", wins: 1)]
        let event = makeEvent(id: "m4", state: .completed, teams: teams)
        #expect(Presenter.scoreLine(for: event, follows: try follows(), revealed: []).status == .finished(winnerCode: nil))
        #expect(Presenter.scoreLine(for: event, follows: try follows(), revealed: ["m4"]).status == .finished(winnerCode: "T1"))
        #expect(Presenter.scoreLine(for: event, follows: try follows(), revealed: ["m4"]).score == [3, 1])
    }

    @Test func maskedFinishedMatchHasNoScore() throws {
        let teams = [makeTeam("T1", id: "98767991853197861", wins: 3), makeTeam("GEN", id: "g", wins: 1)]
        let line = Presenter.scoreLine(for: makeEvent(id: "m4", state: .completed, teams: teams), follows: try follows(), revealed: [])
        #expect(line.isMasked)
        #expect(line.score == nil)
    }

    @Test func revealingOneMatchLeavesTheOthersMasked() throws {
        let m1 = makeEvent(id: "m1", state: .inProgress,
                           teams: [makeTeam("T1", id: "98767991853197861", wins: 1), makeTeam("FLY", id: "f", wins: 0)], games: liveGames)
        let m2 = makeEvent(id: "m2", state: .completed,
                           teams: [makeTeam("T1", id: "98767991853197861", wins: 3), makeTeam("GEN", id: "g", wins: 1)])
        let revealed: Set<String> = ["m1"]
        #expect(!Presenter.scoreLine(for: m1, follows: try follows(), revealed: revealed).isMasked)
        let hidden = Presenter.scoreLine(for: m2, follows: try follows(), revealed: revealed)
        #expect(hidden.isMasked)
        #expect(hidden.score == nil)
    }

    @Test func upcomingHasNoScore() throws {
        let event = makeEvent(id: "m5", state: .unstarted, start: "2026-10-15T18:00:00Z",
                              teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let line = Presenter.scoreLine(for: event, follows: try follows(), revealed: [])
        #expect(line.score == nil)
        #expect(line.status == .upcoming(date("2026-10-15T18:00:00Z")))
        #expect(!line.isMasked)
    }

    @Test func currentGameNumberWithoutGamesUsesWins() {
        let event = makeEvent(id: "m6", state: .inProgress, teams: [makeTeam("A", wins: 2), makeTeam("B", wins: 1)])
        #expect(Presenter.currentGameNumber(event) == 4)
    }

    @Test func completedTieHasNoWinner() throws {
        let teams = [makeTeam("T1", id: "98767991853197861", wins: 1), makeTeam("GEN", id: "g", wins: 1)]
        let event = makeEvent(id: "m7", state: .completed, teams: teams, bestOf: 2)
        #expect(Presenter.scoreLine(for: event, follows: try follows(), revealed: ["m7"]).status == .finished(winnerCode: nil))
    }

    @Test func outcomeDecidesWinnerWhenGameWinsAreTied() throws {
        let teams = [
            MatchTeam(id: "a", name: "Alpha", code: "AAA", image: nil, result: MatchTeam.Result(outcome: "win", gameWins: 0)),
            MatchTeam(id: "b", name: "Beta", code: "BBB", image: nil, result: MatchTeam.Result(outcome: "loss", gameWins: 0)),
        ]
        let event = makeEvent(id: "m8", state: .completed, teams: teams)
        #expect(Presenter.scoreLine(for: event, follows: try follows(), revealed: ["m8"]).status == .finished(winnerCode: "AAA"))
    }

    @Test func winnerCodeWithoutResultIsNil() {
        #expect(Presenter.winnerCode([makeTeam("A"), makeTeam("B")]) == nil)
    }
}

@Suite struct FormatTests {
    @Test func gold() {
        #expect(Format.gold(37442) == "37,4k")
        #expect(Format.gold(35882) == "35,9k")
        #expect(Format.gold(67995) == "68k")
        #expect(Format.gold(850) == "850")
        #expect(Format.goldDiff(1560) == "+1,6k")
        #expect(Format.goldDiff(-800) == "−800")
        #expect(Format.goldDiff(-2100) == "−2,1k")
        #expect(Format.goldDiff(0) == "0")
    }

    @Test func matchDateInFrench() throws {
        let paris = try #require(TimeZone(secondsFromGMT: 2 * 3600))
        #expect(Format.matchDate(date("2026-10-15T18:00:00Z"), timeZone: paris) == "jeu. 15 oct. · 20:00")
        #expect(Format.matchDate(date("2026-08-03T07:05:00Z"), timeZone: paris) == "lun. 3 août · 09:05")
    }

    @Test func countdown() {
        let now = date("2026-10-13T12:00:00Z")
        #expect(Format.countdown(from: now, to: date("2026-10-13T12:45:00Z")) == "45 min")
        #expect(Format.countdown(from: now, to: date("2026-10-14T09:00:00Z")) == "21h")
        #expect(Format.countdown(from: now, to: date("2026-10-16T12:00:00Z")) == "3 j")
        #expect(Format.countdown(from: now, to: date("2026-10-13T11:00:00Z")) == "maintenant")
    }
}
