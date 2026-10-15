import Foundation
import Testing
@testable import LoLKit

/// Onglet Accueil, logique pure (spec saison §2) : activité récente sur la vraie saison de KC, direct, résultats,
/// bandeau, joueurs en forme ; rien d'un match masqué.
@Suite struct HomeFeedTests {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var kcFollow: FollowList {
        FollowList(teams: [FollowedTeam(id: SeasonFixture.kc, code: "KC", name: "Karmine Corp")])
    }

    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    private func activity(now: String, follows: FollowList? = nil, schedule: [MatchEvent] = [],
                          revealed: Set<String> = [], masked: Set<String>? = nil) throws -> [ActivityItem] {
        let follows = follows ?? kcFollow
        let matches = try SeasonFixture.kcMatches()
        return HomeFeed.activity(
            matches: matches, games: try SeasonFixture.kcGames(), schedule: schedule, follows: follows,
            revealed: revealed,
            masked: masked ?? SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: revealed),
            now: date(now))
    }

    /// 28/07 : record de kills (KC 27, G2 – KC game 3 du 26/07) et 3 victoires d'affilée.
    @Test func killRecordAndStreak() throws {
        let items = try activity(now: "2026-07-28T12:00:00Z")
        #expect(items.map(\.kind) == [
            .killRecord(gameId: "115548681803406290", teamId: SeasonFixture.kc, kills: 27),
            .streak(teamId: SeasonFixture.kc, kind: .wins, count: 3),
        ])
        #expect(items[0].date == date("2026-07-26T20:19:09.910Z"))
    }

    /// 05/08 : la game de 48:42 contre TH (> 45 min) et 5 victoires d'affilée ; le record du 26/07 a plus de 7 jours.
    @Test func longGameAndLongerStreak() throws {
        let items = try activity(now: "2026-08-05T12:00:00Z")
        #expect(items.map(\.kind) == [
            .longGame(gameId: "115548681803406141", seconds: 2922),
            .streak(teamId: SeasonFixture.kc, kind: .wins, count: 5),
        ])
    }

    /// Match G2 – KC du 26/07 masqué : ni son record, ni la série (le match le plus récent est masqué).
    @Test func maskedMatchesProduceNothing() throws {
        let items = try activity(now: "2026-07-28T12:00:00Z", masked: ["115548681803406287"])
        #expect(items.map(\.kind) == [.killRecord(gameId: "115548681803406272", teamId: SeasonFixture.kc, kills: 24)])
        var spoilerFree = kcFollow
        spoilerFree.setSpoilerFree(true, id: SeasonFixture.kc)
        #expect(try activity(now: "2026-07-28T12:00:00Z", follows: spoilerFree).isEmpty)
    }

    /// 06/09 à 20:00 : KC 1-3 G2 fini à 18:31 (fin de sa dernière game) → « vient de finir » ; masqué → rien,
    /// révélé → de nouveau.
    @Test func justFinished() async throws {
        let events = try await schedule()
        let items = try activity(now: "2026-09-06T20:00:00Z", schedule: events)
        #expect(items.map(\.kind) == [.justFinished(matchId: SeasonFixture.match303)])
        #expect(items.first?.date == date("2026-09-06T18:31:34.815Z"))
        #expect(try activity(now: "2026-09-07T01:00:00Z", schedule: events).isEmpty)
        var spoilerFree = kcFollow
        spoilerFree.setSpoilerFree(true, id: SeasonFixture.kc)
        #expect(try activity(now: "2026-09-06T20:00:00Z", follows: spoilerFree, schedule: events).isEmpty)
        // Révélé : le match revient (et ses games aussi : record de kills de G2 dans la game 304, les autres masquées).
        #expect(try activity(now: "2026-09-06T20:00:00Z", follows: spoilerFree, schedule: events,
                             revealed: [SeasonFixture.match303]).map(\.kind)
                == [.justFinished(matchId: SeasonFixture.match303),
                    .killRecord(gameId: SeasonFixture.game304, teamId: SeasonFixture.g2, kills: 23)])
        // Ni équipe ni ligue suivie : rien.
        #expect(try activity(now: "2026-09-06T20:00:00Z", follows: FollowList(), schedule: events).isEmpty)
    }

    /// Game de 23:20 gagnée par l'équipe menée de 6 623 gold à 15 min, avec un joueur à 12 kills.
    @Test func comebackBigGameAndFastGame() throws {
        let reference = try SeasonFixture.summary304()
        let star = PlayerGameLine(playerId: "star", name: "KC Star", role: "mid", champion: "Ahri", level: 16, kills: 12,
                                  deaths: 1, assists: 4, creepScore: 200, gold: 12_000)
        let game = GameSummary(
            gameId: "g", matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
            startedAt: date("2026-10-10T15:00:00Z"), endedAt: date("2026-10-10T15:23:20Z"), durationSeconds: 1400,
            result: GameResult(winnerTeamId: SeasonFixture.kc, basis: .exact),
            blue: TeamGameLine(teamId: SeasonFixture.kc, kills: 30, gold: 60_000, towers: 9, inhibitors: 2, barons: 1,
                               dragons: [], gold15: 20_000, players: [star]),
            red: TeamGameLine(teamId: SeasonFixture.g2, kills: 10, gold: 50_000, towers: 3, inhibitors: 0, barons: 0,
                              dragons: [], gold15: reference.red.gold15, players: []),
            enriched: true)
        let items = HomeFeed.activity(matches: [], games: ["g": game], schedule: [], follows: FollowList(), revealed: [],
                                      masked: [], now: date("2026-10-10T16:00:00Z"))
        #expect(items.map(\.kind) == [
            .killRecord(gameId: "g", teamId: SeasonFixture.kc, kills: 30),
            .bigGame(gameId: "g", playerId: "star", kills: 12),
            .fastGame(gameId: "g", seconds: 1400),
            .comeback15(gameId: "g", teamId: SeasonFixture.kc, deficit: 6_623),
        ])
        // Vainqueur seulement déduit : pas de « comeback ».
        var inferred = game
        inferred.result = GameResult(winnerTeamId: SeasonFixture.kc, basis: .inferred)
        #expect(!HomeFeed.activity(matches: [], games: ["g": inferred], schedule: [], follows: FollowList(),
                                   revealed: [], masked: [], now: date("2026-10-10T16:00:00Z"))
            .contains { if case .comeback15 = $0.kind { true } else { false } })
        // Au plus 6 éléments.
        let many = (0..<8).map { index in
            GameSummary(gameId: "f\(index)", matchId: "m\(index)", tournamentId: "t", leagueSlug: "lec", number: 1,
                        patch: nil, startedAt: game.startedAt, endedAt: game.endedAt.addingTimeInterval(Double(index)),
                        durationSeconds: 1400, result: .unknown, blue: game.blue, red: game.red, enriched: false)
        }
        #expect(HomeFeed.activity(matches: [], games: Dictionary(uniqueKeysWithValues: many.map { ($0.gameId, $0) }),
                                  schedule: [], follows: FollowList(), revealed: [], masked: [],
                                  now: date("2026-10-10T16:00:00Z")).count == HomeFeed.activityLimit)
    }

    @Test func liveOrderFollowedTeamsThenLeaguesThenInternationals() {
        let other = makeEvent(id: "other", state: .inProgress, start: "2026-10-15T10:00:00Z",
                              teams: [makeTeam("A"), makeTeam("B")])
        let lck = MatchEvent(startTime: date("2026-10-15T09:00:00Z"), state: .inProgress, type: "match", blockName: nil,
                             league: LeagueRef(id: "lck", slug: "lck", name: "LCK", image: nil),
                             match: MatchInfo(id: "lck", teams: [makeTeam("T1"), makeTeam("GEN")], strategy: nil,
                                              games: nil),
                             streams: nil)
        let kc = makeEvent(id: "kc", state: .inProgress, start: "2026-10-15T11:00:00Z",
                           teams: [makeTeam("KC", id: SeasonFixture.kc), makeTeam("C9")])
        var follows = kcFollow
        follows.follow(league: League(id: "lck", slug: "lck", name: "LCK", region: nil, image: nil, priority: nil))
        #expect(HomeFeed.live([other, lck, kc], follows: follows).map(\.id) == ["kc", "lck", "other"])
        #expect(HomeFeed.followedMatchIds([other, lck, kc], follows: follows) == ["kc", "lck"])
    }

    /// Le sous-titre « N matchs aujourd'hui » compte la liste du jour : calendrier fusionné au direct (le direct fait foi
    /// pour un match qu'il connaît, et apporte ceux que le calendrier n'a pas encore).
    @Test func todayCountMergesTheLiveList() {
        let now = date("2026-10-15T12:00:00Z")
        let scheduled = makeEvent(id: "a", state: .unstarted, start: "2026-10-15T15:00:00Z",
                                  teams: [makeTeam("A"), makeTeam("B")])
        let known = makeEvent(id: "b", state: .inProgress, start: "2026-10-15T11:00:00Z",
                              teams: [makeTeam("C"), makeTeam("D")])
        let liveOnly = makeEvent(id: "c", state: .inProgress, start: "2026-10-15T10:00:00Z",
                                 teams: [makeTeam("E"), makeTeam("F")])
        func input(live: [MatchEvent]?) -> HomeFeed.Input {
            HomeFeed.Input(now: now, calendar: paris, schedule: [scheduled, known], live: live, follows: FollowList(),
                           revealed: [], revealedStandings: [], seasonMatches: [], games: [:], standings: [:], catalog: [])
        }
        #expect(HomeFeed.build(input(live: [known, liveOnly])).todayCount == 3)
        #expect(HomeFeed.build(input(live: nil)).todayCount == 2)
        #expect(HomeFeed.build(input(live: [])).todayCount == 2)
    }

    /// Résultats des 72 dernières heures, suivis d'abord, 8 au plus.
    @Test func recentResults() {
        let now = date("2026-10-15T20:00:00Z")
        let old = makeEvent(id: "old", state: .completed, start: "2026-10-12T19:00:00Z", teams: [makeTeam("A"), makeTeam("B")])
        let recent = makeEvent(id: "recent", state: .completed, start: "2026-10-15T15:00:00Z",
                               teams: [makeTeam("A"), makeTeam("B")])
        let kc = makeEvent(id: "kc", state: .completed, start: "2026-10-13T21:00:00Z",
                           teams: [makeTeam("KC", id: SeasonFixture.kc), makeTeam("C9")])
        let upcoming = makeEvent(id: "next", state: .unstarted, start: "2026-10-16T15:00:00Z",
                                 teams: [makeTeam("A"), makeTeam("B")])
        #expect(HomeFeed.recentResults(schedule: [old, recent, kc, upcoming], follows: kcFollow, now: now).map(\.id)
                == ["kc", "recent"])
        let many = (0..<10).map {
            makeEvent(id: "r\($0)", state: .completed, start: "2026-10-15T1\($0):00:00Z", teams: [makeTeam("A"), makeTeam("B")])
        }
        #expect(HomeFeed.recentResults(schedule: many, follows: FollowList(), now: now).count == 8)
    }

    /// Joueurs en forme : semaine (2 games) ou saison (5 games).
    @Test func topPlayersByPeriod() throws {
        let game = try SeasonFixture.summary304()
        let games = [game.gameId: game]
        #expect(HomeFeed.topPlayers(games: games, masked: [], metric: .kda, period: .week,
                                    now: date("2026-09-08T00:00:00Z")).isEmpty)
        #expect(HomeFeed.topPlayers(games: games, masked: [], metric: .kda, period: .season,
                                    now: date("2026-09-08T00:00:00Z")).isEmpty)
        var second = try SeasonFixture.summary304()
        second = GameSummary(gameId: "copie", matchId: "m2", tournamentId: second.tournamentId, leagueSlug: "lec",
                             number: 2, patch: nil, startedAt: date("2026-09-07T15:00:00Z"),
                             endedAt: date("2026-09-07T15:33:51Z"), durationSeconds: 2031, result: .unknown,
                             blue: second.blue, red: second.red, enriched: true)
        let week = HomeFeed.topPlayers(games: [game.gameId: game, "copie": second], masked: [], metric: .kda,
                                       period: .week, now: date("2026-09-08T00:00:00Z"))
        #expect(week.count == 5)
        #expect(week.first?.name == "G2 Labrov")
        #expect(week.first?.games == 2)
    }

    /// Accueil complet sur le calendrier réel, le 15/10 à midi : « À ne pas rater » C9 – KC, bandeau, 1 match
    /// aujourd'hui (FUR – MVK tombe le 16 à Paris), pas de direct, pas de résultat récent.
    @Test func buildTheHome() async throws {
        let events = try await schedule()
        var follows = FollowList()
        follows.follow(try catalogTeam("KC"))
        let sections = HomeFeed.build(HomeFeed.Input(
            now: date("2026-10-15T12:00:00Z"), calendar: paris, schedule: events, live: [], follows: follows,
            revealed: [], revealedStandings: [], seasonMatches: try SeasonFixture.kcMatches(),
            games: try SeasonFixture.kcGames(), standings: [:], catalog: []))
        #expect(sections.mustWatch.first?.event.id == "115660588583171786")
        #expect(sections.mustWatch.count == 2)
        #expect(sections.live.isEmpty)
        #expect(sections.week.map(\.dayNumber) == [14, 15, 16, 17, 18, 19, 20])
        #expect(sections.week[1].marker == .followed)
        #expect(sections.todayCount == 1)
        #expect(sections.recentResults.isEmpty)
        // Rien de récent dans la saison de KC au 15/10 (dernier match le 19/09, série de 2 défaites).
        #expect(sections.activity.isEmpty)
    }
}
