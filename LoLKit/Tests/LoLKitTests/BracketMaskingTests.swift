import Foundation
import Testing
@testable import LoLKit

/// I-1 généralisé : un match masqué d'une équipe en anti-spoiler dans une compétition internationale cache la suite du
/// tableau (la demi-finale de deux autres équipes dirait que l'équipe est éliminée).
@Suite struct BracketMaskingTests {
    private static let t1Id = "t1-id"

    private func follows(notify: Bool = false) -> FollowList {
        FollowList(teams: [FollowedTeam(id: Self.t1Id, code: "T1", name: "T1", spoilerFree: true)],
                   leagues: notify ? [FollowedLeague(id: "98767975604431411", slug: "worlds", name: "Mondial",
                                                     notifyStarts: true)] : [])
    }

    /// Quart masqué de T1 (terminé), puis demi-finale BLG–GEN (à venir) et un match d'une autre ligue.
    private func schedule() -> [MatchEvent] {
        [makeEvent(id: "quart", state: .completed, start: "2026-10-10T10:00:00Z",
                   teams: [makeTeam("T1", id: Self.t1Id, wins: 3), makeTeam("BLG", id: "blg", wins: 1)]),
         makeEvent(id: "demi", state: .unstarted, start: "2026-10-20T10:00:00Z",
                   teams: [makeTeam("BLG", id: "blg"), makeTeam("GEN", id: "gen")]),
         makeEvent(id: "avant", state: .completed, start: "2026-10-09T10:00:00Z",
                   teams: [makeTeam("KC", id: "kc", wins: 1), makeTeam("GEN", id: "gen", wins: 0)])]
    }

    @Test func laterMatchesOfTheSameInternationalLeagueAreHidden() {
        let hidden = BracketMasking.hiddenIds(schedule: schedule(), maskedTeamIds: [Self.t1Id], follows: follows(),
                                              revealed: [])
        #expect(hidden == ["demi"])
    }

    @Test func revealingTheMaskedMatchLiftsIt() {
        let hidden = BracketMasking.hiddenIds(schedule: schedule(), maskedTeamIds: [Self.t1Id], follows: follows(),
                                              revealed: ["quart"])
        #expect(hidden.isEmpty)
    }

    @Test func domesticLeaguesAreNotConcerned() {
        let domestic = schedule().map { event in
            MatchEvent(startTime: event.startTime, state: event.state, type: event.type, blockName: event.blockName,
                       league: LeagueRef(id: "lec", slug: "lec", name: "LEC", image: nil), match: event.match,
                       streams: event.streams)
        }
        #expect(BracketMasking.hiddenIds(schedule: domestic, maskedTeamIds: [Self.t1Id], follows: follows(),
                                         revealed: []).isEmpty)
    }

    @Test func noMaskedTeamHidesNothing() {
        #expect(BracketMasking.hiddenIds(schedule: schedule(), maskedTeamIds: [], follows: follows(), revealed: []).isEmpty)
    }

    @Test func recentResultsDropTheHiddenOnes() {
        let events = schedule() + [makeEvent(id: "finie", state: .completed, start: "2026-10-14T10:00:00Z",
                                             teams: [makeTeam("BLG", id: "blg", wins: 2), makeTeam("GEN", id: "gen", wins: 0)])]
        let now = date("2026-10-15T10:00:00Z")
        let ids = HomeFeed.recentResults(schedule: events, follows: follows(), now: now, hiddenIds: ["finie"]).map(\.id)
        #expect(!ids.contains("finie"))
    }

    @Test func notificationsOfAFollowedLeagueSkipTheHiddenMatches() {
        let plan = MatchReminders.plan(schedule: schedule(), follows: follows(notify: true), revealed: [],
                                       now: date("2026-10-15T12:00:00Z"), lead: MatchReminders.defaultLead)
        #expect(plan.isEmpty)
        let revealed = MatchReminders.plan(schedule: schedule(), follows: follows(notify: true), revealed: ["quart"],
                                           now: date("2026-10-15T12:00:00Z"), lead: MatchReminders.defaultLead)
        #expect(revealed.map(\.matchId) == ["demi"])
    }
}
