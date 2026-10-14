import Foundation
import Testing
@testable import LoLKit

/// Suivre une ligue et nouveaux réglages (spec saison §3.5, §3.7) : liste des suivis, calendrier, notifications,
/// décodage tolérant des fichiers d'avant ce lot.
@Suite struct LeagueFollowTests {
    private let lec = League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: "http://lec.png",
                             priority: 3)
    private let lck = League(id: "98767991310872058", slug: "lck", name: "LCK", region: "KOREA", image: nil, priority: 2)
    private let worlds = League(id: "98767975604431411", slug: "worlds", name: "Mondial", region: nil, image: nil,
                                priority: 1)

    @Test func followAndUnfollowALeague() {
        var list = FollowList()
        list.follow(league: lec)
        list.follow(league: lec)
        list.follow(league: lck)
        #expect(list.leagues.map(\.slug) == ["lec", "lck"])
        #expect(list.leagues[0] == FollowedLeague(id: lec.id, slug: "lec", name: "LEC", image: "http://lec.png"))
        #expect(!list.leagues[0].notifyStarts)
        #expect(list.containsLeague(id: lck.id))
        #expect(list.league(slug: "lck")?.name == "LCK")
        list.setNotifyStarts(true, leagueId: lck.id)
        #expect(list.league(slug: "lck")?.notifyStarts == true)
        list.unfollowLeague(id: lec.id)
        #expect(list.leagues.map(\.slug) == ["lck"])
        #expect(list.teams.isEmpty)
    }

    /// `follows.json` d'avant ce lot (sans `leagues`) : les équipes restent, aucune ligue. Une ligue illisible est
    /// ignorée, les autres sont gardées ; un interrupteur illisible vaut « désactivé ».
    @Test func followListDecodesTolerantly() throws {
        let old = #"{"teams":[{"id":"111692118851466302","code":"KC","name":"Karmine Corp"}]}"#
        let decoded = try JSONDecoder().decode(FollowList.self, from: Data(old.utf8))
        #expect(decoded.teams.map(\.code) == ["KC"])
        #expect(decoded.leagues.isEmpty)

        let mixed = #"""
        {"teams":[],"leagues":[{"id":"1","slug":"lec","name":"LEC","notifyStarts":"oui"},{"slug":"sans-id"},
                                {"id":"2","slug":"lck","name":"LCK","notifyStarts":true,"image":42}]}
        """#
        let leagues = try JSONDecoder().decode(FollowList.self, from: Data(mixed.utf8)).leagues
        #expect(leagues == [FollowedLeague(id: "1", slug: "lec", name: "LEC"),
                            FollowedLeague(id: "2", slug: "lck", name: "LCK", notifyStarts: true)])
        let notALeagueList = #"{"teams":[],"leagues":"lec"}"#
        #expect(try JSONDecoder().decode(FollowList.self, from: Data(notALeagueList.utf8)).leagues.isEmpty)
    }

    @Test func followListRoundTripsWithItsLeagues() throws {
        var list = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")])
        list.follow(league: lck)
        list.setNotifyStarts(true, leagueId: lck.id)
        #expect(try JSONDecoder().decode(FollowList.self, from: JSONEncoder().encode(list)) == list)
    }

    /// Le calendrier demande aussi les ligues suivies (dans l'ordre de `getLeagues`).
    @Test func scheduleQueryIncludesFollowedLeagues() {
        let leagues = [worlds, lck, lec]
        var list = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", homeLeagueName: "LEC")])
        #expect(ScheduleQuery.leagueIds(follows: list, leagues: leagues) == [worlds.id, lec.id])
        list.follow(league: lck)
        #expect(ScheduleQuery.leagueIds(follows: list, leagues: leagues) == [worlds.id, lck.id, lec.id])
        #expect(ScheduleQuery.leagueIds(follows: FollowList(), leagues: leagues) == [worlds.id])
    }

    private func match(_ id: String, start: String, league: String = "lck", teams: [MatchTeam],
                       state: EventState = .unstarted) -> MatchEvent {
        MatchEvent(startTime: date(start), state: state, type: "match", blockName: "Semaine 3",
                   league: LeagueRef(id: nil, slug: league, name: league.uppercased(), image: nil),
                   match: MatchInfo(id: id, teams: teams, strategy: Strategy(type: "bestOf", count: 3), games: nil),
                   streams: nil)
    }

    /// Ligue suivie avec `notifyStarts` : chaque match à venir est notifié ; sans l'interrupteur, rien.
    @Test func notifyStartsRemindsEveryMatchOfTheLeague() {
        let events = [
            match("t1-gen", start: "2026-10-20T08:00:00Z", teams: [makeTeam("T1"), makeTeam("GEN")]),
            match("hle-dk", start: "2026-10-20T10:00:00Z", teams: [makeTeam("HLE"), makeTeam("DK")]),
            match("lec", start: "2026-10-20T16:00:00Z", league: "lec", teams: [makeTeam("G2"), makeTeam("FNC")]),
            match("tbd", start: "2026-10-21T08:00:00Z", teams: [makeTeam("TBD"), makeTeam("TBD")]),
            match("past", start: "2026-10-15T08:00:00Z", teams: [makeTeam("NS"), makeTeam("BRO")], state: .completed),
        ]
        var list = FollowList()
        list.follow(league: lck)
        let now = date("2026-10-19T12:00:00Z")
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900).isEmpty)
        list.setNotifyStarts(true, leagueId: lck.id)
        let reminders = MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900)
        #expect(reminders.map(\.matchId) == ["t1-gen", "hle-dk"])
        #expect(reminders[0].title == "T1 vs GEN dans 15 min")
        #expect(reminders[0].subtitle == "LCK · Semaine 3 · Bo3")
        #expect(reminders[0].fireDate == date("2026-10-20T07:45:00Z"))
        // Heure de notification passée : rien.
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: date("2026-10-20T07:50:00Z"),
                                    lead: 900).map(\.matchId) == ["hle-dk"])
    }

    /// Un match de la ligue avec une équipe suivie garde la règle des équipes (F1 + C) : jamais notifié quand
    /// `Presenter.nextLine` le cache, et une seule fois sinon.
    @Test func followedTeamsKeepTheNextLineRule() {
        let t1 = MatchTeam(id: "t1", name: "T1", code: "T1", image: nil, result: nil)
        let gen = MatchTeam(id: "gen", name: "Gen.G", code: "GEN", image: nil, result: nil)
        let last = match("t1-last", start: "2026-10-18T08:00:00Z",
                         teams: [MatchTeam(id: "t1", name: "T1", code: "T1", image: nil,
                                           result: MatchTeam.Result(outcome: "win", gameWins: 2)),
                                 makeTeam("DK", wins: 0)], state: .completed)
        let next = match("t1-gen", start: "2026-10-20T08:00:00Z", teams: [t1, gen])
        let later = match("t1-hle", start: "2026-10-22T08:00:00Z", teams: [t1, makeTeam("HLE")])
        var list = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1")])
        list.follow(league: lck)
        list.setNotifyStarts(true, leagueId: lck.id)
        let now = date("2026-10-19T12:00:00Z")
        // T1 suivie normalement : son prochain match une fois, pas le suivant (règle des équipes : le prochain seul).
        #expect(MatchReminders.plan(schedule: [last, next, later], follows: list, revealed: [], now: now, lead: 900)
                    .map(\.matchId) == ["t1-gen"])
        // T1 en anti-spoiler, dernier match masqué (F1) : rien pour T1, même par la ligue.
        list.setSpoilerFree(true, id: "t1")
        #expect(MatchReminders.plan(schedule: [last, next, later], follows: list, revealed: [], now: now, lead: 900)
                    .isEmpty)
    }

    /// Réglages d'avant ce lot : onboarding non fait, aucun classement révélé ; valeurs illisibles → par défaut.
    @Test func newSettingsDecodeTolerantly() throws {
        let defaults = AppSettings()
        #expect(!defaults.onboardingDone)
        #expect(defaults.revealedStandingIds.isEmpty)
        let old = #"{"liveActivityMode":"manual","revealedMatchIds":["m1"],"matchRemindersEnabled":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.liveActivityMode == .manual)
        #expect(decoded.matchRemindersEnabled)
        #expect(!decoded.onboardingDone)
        #expect(decoded.revealedStandingIds.isEmpty)
        let odd = #"{"onboardingDone":"oui","revealedStandingIds":"t1"}"#
        let oddDecoded = try JSONDecoder().decode(AppSettings.self, from: Data(odd.utf8))
        #expect(!oddDecoded.onboardingDone && oddDecoded.revealedStandingIds.isEmpty)

        var settings = AppSettings(onboardingDone: true, revealedStandingIds: ["115548681802226458"])
        settings.revealedStandingIds.insert("115660540725177488")
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }
}
