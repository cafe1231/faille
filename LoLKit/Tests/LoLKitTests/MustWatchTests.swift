import Foundation
import Testing
@testable import LoLKit

/// « À ne pas rater » (spec saison §3.6) : candidats, barème, exclusions anti-spoiler, raisons tirées des résultats
/// neutralisées quand le tableau est masqué.
@Suite struct MustWatchTests {
    private static let worlds26 = "115660540725177488"
    private static let c9kc = "115660588583171786"
    private static let furMvk = "115660588583040710"
    private static let kcLast = "115548681803406327"

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    private func catalog() throws -> [Team] {
        try JSONDecoder.lolesports().decode(TeamsResponse.self, from: Fixture.data("getTeams")).data.teams.elements
    }

    private func worlds() throws -> Standings {
        try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(
            "getStandings_worlds26_reduced")).data.standings.elements[0]
    }

    private func kcFollow(spoilerFree: Bool = false) throws -> FollowList {
        var follows = FollowList()
        follows.follow(try catalogTeam("KC"))
        if spoilerFree { follows.setSpoilerFree(true, id: SeasonFixture.kc) }
        return follows
    }

    private func rank(_ schedule: [MatchEvent], follows: FollowList, revealed: Set<String> = [],
                      revealedStandings: Set<String> = [], standings: [String: Standings],
                      seasonMatches: [SeasonMatch] = [], now: Date, limit: Int = 5) throws -> [MustWatchPick] {
        MustWatch.rank(schedule: schedule, follows: follows, revealed: revealed, revealedStandings: revealedStandings,
                       standings: standings, seasonMatches: seasonMatches, catalog: try catalog(), now: now,
                       calendar: paris, limit: limit)
    }

    /// 15/10 à midi : C9 – KC (20:00 à Paris) seul aujourd'hui → on ajoute les prochaines 24 h (FUR – MVK à 01:00) ;
    /// TBD contre TBD exclu. KC suivie : 50 + Mondial 20 + Bo5 10 = 80.
    @Test func worldsDayWithAFollowedTeam() async throws {
        let picks = try rank(try await schedule(), follows: try kcFollow(), standings: [Self.worlds26: try worlds()],
                             now: date("2026-10-15T12:00:00Z"))
        #expect(picks.map(\.event.id) == [Self.c9kc, Self.furMvk])
        #expect(picks.map(\.points) == [80, 30])
        #expect(picks[0].reasons == [MustWatchScore(reason: .followedTeam, points: 50),
                                     MustWatchScore(reason: .international(slug: "worlds"), points: 20),
                                     MustWatchScore(reason: .bestOf5, points: 10)])
        #expect(picks[0].explanation == [.followedTeam, .international(slug: "worlds")])
        // Une ligue suivie ajoute 25 à chacun de ses matchs.
        var withLeague = try kcFollow()
        withLeague.follow(league: League(id: "98767975604431411", slug: "worlds", name: "Mondial", region: nil,
                                         image: nil, priority: 1))
        let leaguePicks = try rank(try await schedule(), follows: withLeague, standings: [:],
                                   now: date("2026-10-15T12:00:00Z"))
        #expect(leaguePicks.map(\.points) == [105, 55])
        #expect(try rank(try await schedule(), follows: try kcFollow(), standings: [:],
                         now: date("2026-10-15T12:00:00Z"), limit: 1).count == 1)
    }

    /// KC en anti-spoiler, dernier match (KC – MKOI) masqué : son prochain match n'est proposé nulle part (F1) ;
    /// révéler ce dernier match le rend.
    @Test func maskedLatestTeamsAreExcluded() async throws {
        let events = try await schedule()
        let now = date("2026-10-15T12:00:00Z")
        let masked = try rank(events, follows: try kcFollow(spoilerFree: true), standings: [:], now: now)
        #expect(masked.map(\.event.id) == [Self.furMvk])
        let revealed = try rank(events, follows: try kcFollow(spoilerFree: true), revealed: [Self.kcLast],
                                standings: [:], now: now)
        #expect(revealed.map(\.event.id) == [Self.c9kc, Self.furMvk])
    }

    // MARK: - Système suisse

    private func team(_ id: String, _ outcome: String? = nil, _ wins: Int = 0) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id, image: nil,
                  result: outcome.map { MatchTeam.Result(outcome: $0, gameWins: wins) })
    }

    private func event(_ id: String, _ a: String, _ b: String, start: String, league: String = "worlds",
                       bestOf: Int = 3, block: String? = nil, state: EventState = .unstarted) -> MatchEvent {
        MatchEvent(startTime: date(start), state: state, type: "match", blockName: block,
                   league: LeagueRef(id: nil, slug: league, name: league, image: nil),
                   match: MatchInfo(id: id, teams: [team(a), team(b)], strategy: Strategy(type: "bestOf", count: bestOf),
                                    games: nil),
                   streams: nil)
    }

    /// Bilans : A 2-0, B 0-2, C 1-1, D 1-1.
    private var swiss: Standings {
        let done: [BracketMatch] = [
            BracketMatch(id: "m1", state: .completed, teams: [team("A", "win", 2), team("C", "loss", 1)]),
            BracketMatch(id: "m2", state: .completed, teams: [team("A", "win", 2), team("D", "loss", 0)]),
            BracketMatch(id: "m3", state: .completed, teams: [team("C", "win", 2), team("B", "loss", 0)]),
            BracketMatch(id: "m4", state: .completed, teams: [team("D", "win", 2), team("B", "loss", 1)]),
        ]
        let next = [("a-b", "A", "B"), ("b-c", "B", "C"), ("c-d", "C", "D")].map {
            BracketMatch(id: $0.0, state: .unstarted, teams: [team($0.1), team($0.2)])
        }
        return Standings(stages: [StandingsStage(id: "s", name: "Système suisse", slug: "swiss",
                                                 sections: [StandingsSection(name: "Suisse", matches: done + next,
                                                                             rankings: [])])])
    }

    private var swissDay: [MatchEvent] {
        [event("c-d", "C", "D", start: "2026-10-20T10:00:00Z"), event("b-c", "B", "C", start: "2026-10-20T12:00:00Z"),
         event("a-b", "A", "B", start: "2026-10-20T14:00:00Z")]
    }

    /// A (2-0) contre B (0-2) : « Tout se joue » 40 ; B contre C : élimination 30 ; C contre D (1-1) : rien.
    @Test func swissStakes() throws {
        let picks = try rank(swissDay, follows: FollowList(), standings: ["w": swiss], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["a-b", "b-c", "c-d"])
        #expect(picks.map(\.points) == [65, 55, 25])
        #expect(picks[0].explanation == [.decider, .international(slug: "worlds")])
        #expect(picks[1].reasons.first == MustWatchScore(reason: .elimination, points: 30))
    }

    /// Tableau masqué (A suivie en anti-spoiler, ses matchs joués masqués) : plus aucune raison tirée des résultats,
    /// pour tous les matchs du tournoi ; révéler le classement les rend.
    @Test func maskedTableNeutralizesResultReasons() throws {
        let follows = FollowList(teams: [FollowedTeam(id: "A", code: "A", name: "A", spoilerFree: true)])
        let picks = try rank(swissDay, follows: follows, standings: ["w": swiss], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["a-b", "c-d", "b-c"])
        #expect(picks.map(\.points) == [75, 25, 25])
        #expect(!picks.flatMap(\.reasons).contains { [.decider, .elimination, .qualification].contains($0.reason) })
        let revealed = try rank(swissDay, follows: follows, revealedStandings: ["w"], standings: ["w": swiss],
                                now: date("2026-10-20T08:00:00Z"))
        #expect(revealed.map(\.points) == [115, 55, 25])
    }

    /// Phase finale à 7 matchs : [6] finale 40, [4-5] demies 30, [0-3] quarts 20 ; sinon d'après le nom du bloc.
    @Test func knockoutRounds() throws {
        let ids = (0..<7).map { "k\($0)" }
        let matches = ids.enumerated().map { index, id in
            BracketMatch(id: id, state: .unstarted, teams: [team("T\(index)a"), team("T\(index)b")])
        }
        let standings = Standings(stages: [StandingsStage(id: "k", name: "Phase finale", slug: "knockouts",
                                                          sections: [StandingsSection(name: "", matches: matches,
                                                                                      rankings: [])])])
        let day = [event("k1", "T1a", "T1b", start: "2026-10-20T10:00:00Z", bestOf: 5),
                   event("k4", "T4a", "T4b", start: "2026-10-20T12:00:00Z", bestOf: 5),
                   event("k6", "T6a", "T6b", start: "2026-10-20T14:00:00Z", bestOf: 5)]
        let picks = try rank(day, follows: FollowList(), standings: ["w": standings], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["k6", "k4", "k1"])
        #expect(picks[0].reasons.map(\.reason) == [.final, .international(slug: "worlds"), .bestOf5])
        #expect(picks[1].reasons.map(\.reason) == [.semiFinal, .international(slug: "worlds"), .bestOf5])
        // À égalité de points, l'ordre de déclaration : international avant le tour.
        #expect(picks[2].reasons.map(\.reason) == [.international(slug: "worlds"), .quarterFinal, .bestOf5])
        #expect(picks.map(\.points) == [70, 60, 50])
        #expect(MustWatch.round(blockName: "Finale")?.reason == .final)
        #expect(MustWatch.round(blockName: "Demi-finales")?.reason == .semiFinal)
        #expect(MustWatch.round(blockName: "Quarts de finale")?.reason == .quarterFinal)
        #expect(MustWatch.round(blockName: "Play-offs")?.reason == .playoffs)
        #expect(MustWatch.round(blockName: "Semaine 2") == nil)
        #expect(MustWatch.round(blockName: nil) == nil)
    }

    /// LEC : KC (1re) contre VIT (2e) = choc du haut de tableau 15 + duel serré 10 + revanche 10 (déjà joué cette
    /// saison) ; KC en anti-spoiler → tableau masqué → ces trois raisons tombent.
    @Test func tableAndRematch() throws {
        let kc = SeasonFixture.kc
        let vit = "99322214695067838"
        func ranked(_ id: String, _ code: String, _ ordinal: Int) -> Ranking {
            Ranking(ordinal: ordinal, teams: [RankedTeam(id: id, code: code, name: code, image: nil, wins: 9 - ordinal,
                                                         losses: ordinal)])
        }
        let lec = Standings(stages: [StandingsStage(
            id: "r", name: "Saison régulière", slug: "regular_season",
            sections: [StandingsSection(
                name: "", matches: [BracketMatch(id: "kc-vit", state: .unstarted,
                                                 teams: [team(kc), team(vit)]),
                                    BracketMatch(id: "g2-fnc", state: .unstarted,
                                                 teams: [team(SeasonFixture.g2), team("fnc")])],
                rankings: [ranked(kc, "KC", 1), ranked(vit, "VIT", 2), ranked(SeasonFixture.g2, "G2", 3),
                           ranked("fnc", "FNC", 7)])])])
        let day = [event("g2-fnc", SeasonFixture.g2, "fnc", start: "2026-10-20T10:00:00Z", league: "lec",
                         block: "Semaine 9"),
                   event("kc-vit", kc, vit, start: "2026-10-20T12:00:00Z", league: "lec", block: "Semaine 9")]
        let seasonMatches = try SeasonFixture.kcMatches()
        let plain = try rank(day, follows: FollowList(), standings: [SeasonFixture.lecSplit3: lec],
                             seasonMatches: seasonMatches, now: date("2026-10-20T08:00:00Z"))
        #expect(plain.map(\.event.id) == ["kc-vit", "g2-fnc"])
        #expect(plain[0].reasons.map(\.reason) == [.topClash, .closeRanks, .rematch, .bestOf3])
        #expect(plain.map(\.points) == [40, 5])
        let masked = try rank(day, follows: FollowList(teams: [FollowedTeam(id: kc, code: "KC", name: "Karmine Corp",
                                                                            spoilerFree: true)]),
                              standings: [SeasonFixture.lecSplit3: lec], seasonMatches: seasonMatches,
                              now: date("2026-10-20T08:00:00Z"))
        #expect(masked[0].reasons.map(\.reason) == [.followedTeam, .bestOf3])
    }

    /// Un match en cours compte (+15) même commencé la veille ; un match au-delà de 24 h n'est pas proposé.
    @Test func candidatesAndLive() throws {
        let day = [event("live", "X", "Y", start: "2026-10-19T21:30:00Z", state: .inProgress),
                   event("later", "Z", "W", start: "2026-10-22T10:00:00Z")]
        let picks = try rank(day, follows: FollowList(), standings: [:], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["live"])
        #expect(picks[0].reasons.map(\.reason) == [.international(slug: "worlds"), .live, .bestOf3])
    }
}
