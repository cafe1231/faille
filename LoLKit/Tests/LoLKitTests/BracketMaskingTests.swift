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

    // MARK: Calendrier, équipes suivies sans anti-spoiler, Live Activities

    private func followsWithBlg() -> FollowList {
        FollowList(teams: [FollowedTeam(id: Self.t1Id, code: "T1", name: "T1", spoilerFree: true),
                           FollowedTeam(id: "blg", code: "BLG", name: "BLG")])
    }

    /// Match d'une page du calendrier, absent du calendrier en cache.
    private func pageOnlyMatch() -> MatchEvent {
        makeEvent(id: "page", state: .unstarted, start: "2026-10-25T10:00:00Z",
                  teams: [makeTeam("GEN", id: "gen"), makeTeam("KC", id: "kc")])
    }

    @Test func aMatchOnlyInACalendarPageIsHiddenAfterTheMaskedQuarter() {
        let page = [pageOnlyMatch()]
        let cached = [schedule()[0]]  // seul le quart masqué est en cache
        let shown = BracketMasking.visible(page + cached, context: cached, maskedTeamIds: [Self.t1Id],
                                           follows: follows(), revealed: [])
        #expect(shown.map(\.id) == ["quart"])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let days = CalendarMonth.days(events: shown, month: date("2026-10-15T10:00:00Z"), calendar: calendar,
                                      followed: [], now: date("2026-10-15T10:00:00Z"))
        #expect(!days.contains { $0.matchIds.contains("page") })
        #expect(days.contains { $0.matchIds.contains("quart") })
    }

    @Test func revealingTheQuarterRestoresTheCalendarPageMatch() {
        let cached = [schedule()[0]]
        let shown = BracketMasking.visible([pageOnlyMatch()] + cached, context: cached, maskedTeamIds: [Self.t1Id],
                                           follows: follows(), revealed: ["quart"])
        #expect(Set(shown.map(\.id)) == ["quart", "page"])
    }

    @Test func aFollowedTeamWithoutSpoilerFreeHasItsNextLineHidden() {
        let cards = TeamCards.build(follows: followsWithBlg(), schedule: schedule(), live: nil, revealed: [])
        let maskedLatest = Presenter.maskedLatestTeamIds(cards, follows: followsWithBlg(), revealed: [])
        let blg = cards.first { $0.team.id == "blg" }!
        // BLG a un dernier match ("quart", perdu contre T1, masqué pour T1 seulement) : on isole le prochain match.
        #expect(blg.nextBracketMasked)
        #expect(Presenter.nextLine(for: blg, follows: followsWithBlg(), revealed: [], maskedLatestTeamIds: maskedLatest)
            == .hidden)
    }

    @Test func revealingTheQuarterRestoresTheNextLine() {
        let cards = TeamCards.build(follows: followsWithBlg(), schedule: schedule(), live: nil, revealed: ["quart"])
        let maskedLatest = Presenter.maskedLatestTeamIds(cards, follows: followsWithBlg(), revealed: ["quart"])
        let blg = cards.first { $0.team.id == "blg" }!
        #expect(!blg.nextBracketMasked)
        guard case let .match(next) = Presenter.nextLine(for: blg, follows: followsWithBlg(), revealed: ["quart"],
                                                         maskedLatestTeamIds: maskedLatest) else {
            Issue.record("la ligne « Prochain » doit revenir"); return
        }
        #expect(next.id == "demi")
    }

    @Test func aFollowedTeamGetsNoReminderForTheHiddenBracketMatch() {
        let now = date("2026-10-15T12:00:00Z")
        let hidden = MatchReminders.plan(schedule: schedule(), follows: followsWithBlg(), revealed: [], now: now,
                                         lead: MatchReminders.defaultLead)
        #expect(hidden.isEmpty)
        let revealed = MatchReminders.plan(schedule: schedule(), follows: followsWithBlg(), revealed: ["quart"],
                                           now: now, lead: MatchReminders.defaultLead)
        #expect(revealed.map(\.matchId) == ["demi"])
    }

    @Test func aLiveMatchOfTheBracketIsDroppedFromTheLiveActivities() {
        let live = [makeEvent(id: "demi-live", state: .inProgress, start: "2026-10-20T10:00:00Z",
                              teams: [makeTeam("BLG", id: "blg", wins: 1), makeTeam("GEN", id: "gen", wins: 0)])]
        let kept = BracketMasking.visible(live, context: schedule(), maskedTeamIds: [Self.t1Id], follows: follows(),
                                          revealed: [])
        #expect(kept.isEmpty)
        let revealed = BracketMasking.visible(live, context: schedule(), maskedTeamIds: [Self.t1Id], follows: follows(),
                                              revealed: ["quart"])
        #expect(revealed.map(\.id) == ["demi-live"])
    }
}
