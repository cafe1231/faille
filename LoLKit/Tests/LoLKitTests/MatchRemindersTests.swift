import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli programme les notifications avec la seule API publique.
import LoLKit

/// Notifications de début de match (spec fonctionnalités §2) : seulement ce que `Presenter.nextLine` montre (F1 + C).
@Suite struct MatchRemindersTests {
    private static let kcId = "111692118851466302"
    private static let c9Id = "98767991877340524"
    /// C9 vs KC, Mondial, Play-ins, Bo5, 15/10/2026 18:00 UTC (fixture `getSchedule`).
    private static let worldsMatch = "115660588583171786"
    /// Dernier match de KC dans la fixture : KC 0 – 3 MKOI, terminé le 19/09.
    private static let kcLast = "115548681803406327"

    /// Vrai calendrier (fixture `getSchedule` : LEC + Mondial), lu par le client public.
    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    private func follows(_ codes: [String], spoilerFree: Set<String> = []) throws -> FollowList {
        var list = FollowList()
        for code in codes {
            let team = try catalogTeam(code)
            list.follow(team)
            if spoilerFree.contains(code) { list.setSpoilerFree(true, id: team.id) }
        }
        return list
    }

    @Test func remindsTheNextMatchOfAFollowedTeam() async throws {
        let reminders = MatchReminders.plan(schedule: try await schedule(), follows: try follows(["KC"]), revealed: [],
                                            now: date("2026-10-15T12:00:00Z"), lead: MatchReminders.defaultLead)
        #expect(reminders == [MatchReminder(id: "match-start-115660588583171786", matchId: Self.worldsMatch,
                                            fireDate: date("2026-10-15T17:45:00Z"), title: "KC vs C9 dans 15 min",
                                            subtitle: "Mondial · Play-ins · Bo5")])
        #expect(MatchReminders.identifier(matchId: Self.worldsMatch) == reminders.first?.id)
    }

    @Test func leadSetsTheTimeAndTheText() async throws {
        let events = try await schedule()
        let list = try follows(["KC"])
        let now = date("2026-10-15T12:00:00Z")
        #expect(MatchReminders.leadOptions == [300, 900, 1800])
        let five = try #require(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 300).first)
        #expect(five.fireDate == date("2026-10-15T17:55:00Z"))
        #expect(five.title == "KC vs C9 dans 5 min")
        let thirty = try #require(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 1800).first)
        #expect(thirty.fireDate == date("2026-10-15T17:30:00Z"))
        #expect(thirty.title == "KC vs C9 dans 30 min")
    }

    @Test func nothingOnceTheFireDateHasPassed() async throws {
        let events = try await schedule()
        let list = try follows(["KC"])
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [],
                                    now: date("2026-10-15T17:45:00Z"), lead: 900).isEmpty)
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [],
                                    now: date("2026-10-15T17:44:59Z"), lead: 900).count == 1)
    }

    /// Règle F1 : KC en anti-spoiler, son dernier match (KC – MKOI) masqué → pas de notification de son prochain match.
    @Test func maskedLastMatchHidesTheReminder() async throws {
        let events = try await schedule()
        let list = try follows(["KC"], spoilerFree: ["KC"])
        let now = date("2026-10-15T12:00:00Z")
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900).isEmpty)
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: ["autre"], now: now, lead: 900).isEmpty)
        // Révéler le dernier match de KC rend la notification.
        let revealed = MatchReminders.plan(schedule: events, follows: list, revealed: [Self.kcLast], now: now, lead: 900)
        #expect(revealed.map(\.matchId) == [Self.worldsMatch])
    }

    /// Règle C : KC suivie normalement, son prochain adversaire C9 suivi en anti-spoiler avec un dernier match masqué
    /// → « KC vs C9 » trahirait que C9 joue encore : pas de notification, ni pour KC ni pour C9.
    @Test func followedOpponentWithAMaskedLastMatchHidesTheReminder() async throws {
        let c9Last = MatchEvent(
            startTime: date("2026-10-10T18:00:00Z"), state: .completed, type: "match", blockName: "Play-ins",
            league: LeagueRef(id: "98767975604431411", slug: "worlds", name: "Mondial", image: nil),
            match: MatchInfo(id: "c9-last",
                             teams: [MatchTeam(id: nil, name: "Cloud9 Kia", code: "C9", image: nil,
                                               result: MatchTeam.Result(outcome: "win", gameWins: 3)),
                                     MatchTeam(id: nil, name: "FlyQuest", code: "FLY", image: nil,
                                               result: MatchTeam.Result(outcome: "loss", gameWins: 1))],
                             strategy: Strategy(type: "bestOf", count: 5), games: nil),
            streams: nil)
        let events = try await schedule() + [c9Last]
        let list = try follows(["KC", "C9"], spoilerFree: ["C9"])
        let now = date("2026-10-15T12:00:00Z")
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900).isEmpty)
        let revealed = MatchReminders.plan(schedule: events, follows: list, revealed: ["c9-last"], now: now, lead: 900)
        #expect(revealed.map(\.title) == ["KC vs C9 dans 15 min"])
    }

    @Test func oneReminderPerMatchWhenBothTeamsAreFollowed() async throws {
        // C9 suivie en premier : elle passe à gauche.
        let reminders = MatchReminders.plan(schedule: try await schedule(), follows: try follows(["C9", "KC"]),
                                            revealed: [], now: date("2026-10-15T12:00:00Z"), lead: 900)
        #expect(reminders.map(\.title) == ["C9 vs KC dans 15 min"])
    }

    @Test func onlyTheNextMatchOfEachTeam() throws {
        let kc = MatchTeam(id: nil, name: "Karmine Corp", code: "KC", image: nil, result: nil)
        let g2 = MatchTeam(id: nil, name: "G2 Esports", code: "G2", image: nil, result: nil)
        let events = [
            makeEvent(id: "later", state: .unstarted, start: "2026-10-21T16:00:00Z", teams: [g2, kc]),
            makeEvent(id: "sooner", state: .unstarted, start: "2026-10-20T16:00:00Z", teams: [kc, g2]),
        ]
        let reminders = MatchReminders.plan(schedule: events, follows: try follows(["KC"]), revealed: [],
                                            now: date("2026-10-15T12:00:00Z"), lead: 900)
        #expect(reminders.map(\.matchId) == ["sooner"])
    }

    @Test func atMostSixtyNearestFirst() {
        let teams = (0..<65).map { FollowedTeam(id: "t\($0)", code: "T\($0)", name: "Team \($0)") }
        let base = date("2026-10-20T00:00:00Z")
        let events = (0..<65).reversed().map { index in
            MatchEvent(startTime: base.addingTimeInterval(Double(index) * 3600), state: .unstarted, type: "match",
                       blockName: nil,
                       league: LeagueRef(id: "1", slug: "lec", name: "LEC", image: nil),
                       match: MatchInfo(id: "m\(index)",
                                        teams: [MatchTeam(id: "t\(index)", name: "Team \(index)", code: "T\(index)",
                                                          image: nil, result: nil),
                                                MatchTeam(id: "o\(index)", name: "Other \(index)", code: "O\(index)",
                                                          image: nil, result: nil)],
                                        strategy: Strategy(type: "bestOf", count: 3), games: nil),
                       streams: nil)
        }
        let reminders = MatchReminders.plan(schedule: events, follows: FollowList(teams: teams), revealed: [],
                                            now: date("2026-10-15T12:00:00Z"), lead: 900)
        #expect(reminders.count == MatchReminders.maxCount)
        #expect(reminders.map(\.matchId) == (0..<60).map { "m\($0)" })
        // Sans bloc : « LEC · Bo3 ».
        #expect(reminders.first?.subtitle == "LEC · Bo3")
        #expect(reminders.first?.title == "T0 vs O0 dans 15 min")
    }
}
