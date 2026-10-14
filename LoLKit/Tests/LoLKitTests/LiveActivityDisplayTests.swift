import Foundation
import Testing
@testable import LoLKit

/// Ce qu'affiche la Live Activity dans chaque état (spec §6.1-§6.3) ; masquée, rien ne fuit (spec §8).
@Suite struct LiveActivityDisplayTests {
    private let now = date("2026-10-15T17:20:42Z")
    /// C9 d'abord dans l'API ; KC, suivie, est l'équipe principale : elle passe à gauche.
    private let attributes = LiveMatchAttributes(
        matchId: "m", leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "c9", code: "C9", name: "Cloud9", colorHex: nil),
                .init(id: "kc", code: "KC", name: "Karmine Corp", colorHex: "#5B8CFF")],
        primaryTeamIndex: 1)
    /// Dans l'ordre de l'API : C9 puis KC.
    private let stats = [
        TeamStats(kills: 4, gold: 30_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        TeamStats(kills: 7, gold: 32_400, towers: 3, inhibitors: 0, barons: 0, dragons: ["infernal", "ocean"]),
    ]

    private func state(_ phase: LiveMatchState.Phase = .inGame, score: [Int]? = [0, 1], game: Int? = 2,
                       start: Date? = nil, stoppedAt: Date? = nil, stats: [TeamStats]? = nil,
                       statsAvailable: Bool = true, winner: String? = nil) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: score, gameNumber: game, gameClockStart: start,
                       gameClockStoppedAt: stoppedAt, stats: stats, statsAvailable: statsAvailable, spoilerFree: false,
                       winnerCode: winner, updatedAt: now)
    }

    private func display(_ state: LiveMatchState, stale: Bool = false) -> LiveActivityDisplay {
        LiveActivityDisplay(attributes: attributes, state: state, isStale: stale)
    }

    @Test func inGameShowsTheFollowedTeamOnTheLeftWithClockAndFiveRows() {
        let start = now.addingTimeInterval(-1122)
        let shown = display(state(start: start, stats: stats))
        #expect(shown.teams == [.init(code: "KC", colorHex: "#5B8CFF"), .init(code: "C9", colorHex: nil)])
        #expect(shown.tintHex == "#5B8CFF")
        #expect(shown.header == "Mondial · Bo5 · Game 2")
        #expect(shown.score == [1, 0])
        #expect(shown.compactScore == "1-0")
        #expect(shown.gameNumber == 2)
        #expect(shown.status == .clock(.running(since: start)))
        #expect(shown.message == nil)
        #expect(!shown.faded)
        #expect(!shown.isMasked)
        #expect(shown.rows == [
            .init(stat: .kills, left: "7", right: "4", lead: nil, leader: nil, compact: "7–4"),
            .init(stat: .gold, left: "32,4k", right: "30,3k", lead: "+2,1k", leader: 0, compact: "+2,1k"),
            .init(stat: .towers, left: "3", right: "1", lead: nil, leader: nil, compact: "3–1"),
            .init(stat: .drakes, left: "2", right: "1", lead: nil, leader: nil, compact: "2–1"),
            .init(stat: .barons, left: "0", right: "0", lead: nil, leader: nil, compact: "0–0"),
        ])
    }

    @Test func clockStopsAtTheStopDateAndNeedsAStart() {
        let start = now.addingTimeInterval(-1122)
        #expect(display(state(start: start, stoppedAt: now, stats: stats)).status == .clock(.stopped("18:42")))
        // Une date d'arrêt sans date de début : pas de chrono du tout (journal LoLKit).
        #expect(display(state(stoppedAt: now, stats: stats)).status == .live)
    }

    @Test func staleReplacesTheClockAndFadesTheStats() {
        let shown = display(state(start: now.addingTimeInterval(-1122), stats: stats), stale: true)
        #expect(shown.status == .stale(since: now))
        #expect(shown.faded)
        #expect(shown.rows.count == 5)
        #expect(LiveActivityDisplay.Status.stale(since: now).label == "màj")
    }

    @Test func maskedShowsOnlyThatItIsLive() {
        let shown = display(state(start: now, stats: stats).masked())
        #expect(shown.isMasked)
        #expect(shown.score == nil)
        #expect(shown.compactScore == nil)
        #expect(shown.gameNumber == nil)
        #expect(shown.header == "Mondial · Bo5")
        #expect(shown.status == .live)
        #expect(shown.rows.isEmpty)
        #expect(shown.message == .masked)
        #expect(LiveActivityDisplay.Message.masked.text == "Sans spoiler ·")
        #expect(LiveActivityDisplay.Message.masked.accent == "ouvre l'appli pour révéler")
        // Entre deux games ou terminé, masqué : jamais plus que « En direct » / « Terminé ».
        #expect(display(state(.betweenGames, score: [0, 2], game: 3).masked()).status == .live)
        let finished = display(state(.finished, score: [1, 3], game: nil, winner: "KC").masked())
        #expect(finished.status == .finished)
        #expect(finished.header == "Mondial · Bo5")
    }

    @Test func betweenGamesAnnouncesTheNextGame() {
        let shown = display(state(.betweenGames, score: [0, 2], game: 3, stats: stats))
        #expect(shown.score == [2, 0])
        #expect(shown.header == "Mondial · Bo5 · Game 3")
        #expect(shown.status == .betweenGames)
        #expect(shown.rows.isEmpty)
        #expect(shown.message == .nextGame(3))
        #expect(shown.message?.text == "La game 3 commence dans quelques minutes")
    }

    @Test func liveBeforeTheFirstGameAnnouncesGameOne() {
        let shown = display(state(.upcoming, score: [0, 0], game: 1))
        #expect(shown.status == .live)
        #expect(shown.message == .nextGame(1))
    }

    @Test func finishedShowsTheWinnerEvenWhenStale() {
        let shown = display(state(.finished, score: [1, 3], game: nil, winner: "KC"), stale: true)
        #expect(shown.score == [3, 1])
        #expect(shown.header == "Mondial · Bo5 · terminé")
        #expect(shown.status == .victory("KC"))
        #expect(shown.status.label == "Victoire KC")
        #expect(shown.message == .leavingSoon)
        #expect(!shown.faded)
        #expect(display(state(.finished, score: [0, 0], game: nil)).status == .finished)
    }

    @Test func statsUnavailableOrNotYetLoaded() {
        let start = now.addingTimeInterval(-1330)
        let unavailable = display(state(start: start, statsAvailable: false))
        #expect(unavailable.status == .clock(.running(since: start)))
        #expect(unavailable.message == .statsUnavailable)
        #expect(unavailable.message?.text == "Stats live non fournies par Riot pour ce match")
        #expect(display(state(start: start)).message == .statsPending)
    }

    @Test func noFollowedTeamMeansNeutralGlassAndApiOrder() {
        let neutral = LiveMatchAttributes(matchId: "m", leagueName: "LFL", bestOf: 3,
                                          teams: [.init(id: "kcb", code: "KCB", name: "Karmine Corp Blue", colorHex: nil),
                                                  .init(id: "sly", code: "SLY", name: "Solary", colorHex: nil)],
                                          primaryTeamIndex: nil)
        let shown = LiveActivityDisplay(attributes: neutral, state: state(score: [1, 0]), isStale: false)
        #expect(shown.tintHex == nil)
        #expect(shown.teams.map(\.code) == ["KCB", "SLY"])
        #expect(shown.score == [1, 0])
        #expect(shown.header == "LFL · Bo3 · Game 2")
    }

    @Test func labels() {
        #expect(LiveActivityDisplay.Stat.allCases.map(\.label) == ["Kills", "Gold", "Tours", "Drakes", "Barons"])
        #expect(LiveActivityDisplay.Status.live.label == "En direct")
        #expect(LiveActivityDisplay.Status.betweenGames.label == "entre deux games")
        #expect(LiveActivityDisplay.Status.finished.label == "Terminé")
        #expect(LiveActivityDisplay.Status.clock(.stopped("1:00")).label == nil)
        #expect(LiveActivityDisplay.Message.statsPending.text == "Stats en attente du flux de Riot")
        #expect(LiveActivityDisplay.Message.leavingSoon.text == "Se retire de l'écran verrouillé au bout d'une heure")
        #expect(LiveActivityDisplay.Message.nextGame(2).accent == nil)
    }
}
