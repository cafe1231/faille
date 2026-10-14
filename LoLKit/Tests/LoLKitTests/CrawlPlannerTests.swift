import Foundation
import Testing
@testable import LoLKit

/// Collecte progressive (spec saison §1.6, §1.7) : ordre des jobs, anti-spoiler, échecs, cadence, budget, cache.
@Suite struct CrawlPlannerTests {
    private static let lec3 = "115548681802226458"
    private static let lec1 = "115548424304940735"
    private static let worlds = "115660540725177488"
    private static let lck3 = "lck3"
    private static let lck1 = "lck1"
    private let now = date("2026-10-20T12:00:00Z")

    private func team(_ id: String, wins: Int) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id, image: nil, result: MatchTeam.Result(outcome: nil, gameWins: wins))
    }

    private func match(_ id: String, _ tournament: String, _ league: String, _ start: String, _ a: String, _ b: String,
                       games: Int = 2) -> SeasonMatch {
        SeasonMatch(id: id, tournamentId: tournament, leagueSlug: league, stageSlug: nil, startTime: date(start),
                    blockName: nil, bestOf: 3, teams: [team(a, wins: 2), team(b, wins: games - 2)],
                    playedGameIds: (1...games).map { "\(id)-g\($0)" })
    }

    private var matches: [SeasonMatch] {
        [
            match("kc-g2", Self.lec3, "lec", "2026-09-06T15:00:00Z", "KC", "G2", games: 3),
            match("kc-vit", Self.lec3, "lec", "2026-07-24T17:30:00Z", "KC", "VIT"),
            match("kc-old", Self.lec1, "lec", "2026-02-01T17:00:00Z", "KC", "FNC"),
            match("kc-sk", Self.lec3, "lec", "2026-08-29T15:00:00Z", "KC", "SK"),
            match("fnc-th", Self.lec3, "lec", "2026-08-30T15:00:00Z", "FNC", "TH"),
            match("fnc-old", Self.lec1, "lec", "2026-02-02T15:00:00Z", "FNC", "TH"),
            match("t1-gen", Self.worlds, "worlds", "2026-10-18T09:00:00Z", "T1", "GEN"),
            match("hle-dk", Self.lck3, "lck", "2026-08-20T09:00:00Z", "HLE", "DK"),
            match("hle-old", Self.lck1, "lck", "2026-02-20T09:00:00Z", "HLE", "DK"),
            match("ns-bro", Self.lck3, "lck", "2026-10-25T09:00:00Z", "NS", "BRO"),
            match("g2-th", Self.lec3, "lec", "2026-08-01T15:00:00Z", "G2", "TH"),
        ]
    }

    private var wanted: CrawlWanted {
        CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC"], worldsStageMatchIds: ["t1-gen"],
                    followedLeagueSlugs: ["lck"], currentTournamentIds: [Self.lec3, Self.worlds, Self.lck3])
    }

    private func summary(_ gameId: String, _ blue: String, _ red: String, enriched: Bool = false) -> GameSummary {
        func line(_ id: String) -> TeamGameLine {
            TeamGameLine(teamId: id, kills: 0, gold: 0, towers: 0, inhibitors: 0, barons: 0, dragons: [], gold15: nil,
                         players: [])
        }
        return GameSummary(gameId: gameId, matchId: "m", tournamentId: Self.lec3, leagueSlug: "lec", number: 1,
                           patch: nil, startedAt: date("2026-09-06T15:00:00Z"), endedAt: date("2026-09-06T15:30:00Z"),
                           durationSeconds: 1800, result: .unknown, blue: line(blue), red: line(red), enriched: enriched)
    }

    /// Page ouverte (FNC, tournoi en cours) → équipes suivies (le plus récent d'abord, tournoi en cours avant les
    /// précédents) → Mondial → ligues suivies → palier B ; masqué jamais ; à venir et hors périmètre jamais.
    @Test func jobsFollowThePriorityOrder() {
        let have = ["kc-g2-g1": summary("kc-g2-g1", "KC", "G2"), "kc-g2-g2": summary("kc-g2-g2", "G2", "KC", enriched: true)]
        let jobs = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: have, failures: [:], masked: ["kc-sk"], now: now)
        #expect(jobs.map(\.gameId) == [
            "fnc-th-g1", "fnc-th-g2",
            "kc-g2-g3", "kc-vit-g1", "kc-vit-g2", "kc-old-g1", "kc-old-g2",
            "t1-gen-g1", "t1-gen-g2",
            "hle-dk-g1", "hle-dk-g2", "hle-old-g1", "hle-old-g2",
            "kc-g2-g1",
        ])
        #expect(jobs.map(\.priority) == [0, 0, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 4])
        #expect(jobs.last?.tier == .b)
        #expect(jobs.dropLast().allSatisfy { $0.tier == .a })
        #expect(jobs[2] == CrawlJob(gameId: "kc-g2-g3", matchId: "kc-g2", tournamentId: Self.lec3, leagueSlug: "lec",
                                    number: 3, tier: .a, priority: 1))
        // Jamais un match masqué, ni un match à venir (NS-BRO), ni un match que rien ne demande (G2-TH).
        #expect(!jobs.contains { $0.matchId == "kc-sk" || $0.matchId == "ns-bro" || $0.matchId == "g2-th" })
        // Une ancienne game de FNC (tournoi précédent) n'est pas demandée pour une page ouverte.
        #expect(!jobs.contains { $0.matchId == "fnc-old" })
    }

    /// Révéler le match le rend éligible au passage suivant ; suivre l'équipe ouverte la fait passer au groupe 1.
    @Test func revealingOrFollowingChangesThePlan() {
        let revealed = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: [:], failures: [:], masked: [], now: now)
        #expect(revealed.contains { $0.matchId == "kc-sk" })
        let followFnc = CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC", "FNC"], worldsStageMatchIds: [],
                                    followedLeagueSlugs: [], currentTournamentIds: [Self.lec3])
        let jobs = CrawlPlanner.jobs(wanted: followFnc, matches: matches, have: [:], failures: [:], masked: [], now: now)
        #expect(jobs.allSatisfy { $0.priority == 1 })
        #expect(jobs.contains { $0.matchId == "fnc-old" })
    }

    /// Échecs : 404 définitif ; 204 / pas de fin → réessai après 1 h, 3 fois au plus ; `http` → toujours repris.
    @Test func failuresAreRetriedByTheRules() {
        let soon = now.addingTimeInterval(-30 * 60)
        let hourAgo = now.addingTimeInterval(-61 * 60)
        let failures: [String: CrawlFailure] = [
            "kc-vit-g1": CrawlFailure(reason: .statsDisabled, attempts: 1, lastAttempt: hourAgo),
            "kc-vit-g2": CrawlFailure(reason: .noData, attempts: 1, lastAttempt: soon),
            "kc-old-g1": CrawlFailure(reason: .notFinished, attempts: 2, lastAttempt: hourAgo),
            "kc-old-g2": CrawlFailure(reason: .noData, attempts: 3, lastAttempt: hourAgo),
            "kc-g2-g1": CrawlFailure(reason: .http, attempts: 4, lastAttempt: now),
        ]
        let ids = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: [:], failures: failures, masked: [], now: now)
            .map(\.gameId)
        #expect(!ids.contains("kc-vit-g1") && !ids.contains("kc-vit-g2") && !ids.contains("kc-old-g2"))
        #expect(ids.contains("kc-old-g1") && ids.contains("kc-g2-g1"))
        #expect(failures["kc-vit-g1"]?.isFinal == true)
        #expect(failures["kc-old-g2"]?.isFinal == true)
        #expect(failures["kc-old-g1"]?.isFinal == false)
        #expect(failures["kc-g2-g1"]?.isFinal == false)
    }

    @Test func recordingFailures() {
        let first = CrawlFailure.record(.noData, previous: nil, now: now)
        #expect(first == CrawlFailure(reason: .noData, attempts: 1, lastAttempt: now))
        let second = CrawlFailure.record(.noData, previous: first, now: now.addingTimeInterval(3600))
        #expect(second?.attempts == 2)
        #expect(CrawlFailure.record(.notFinished, previous: second, now: now)?.attempts == 1)
        // Erreur HTTP : la game n'est pas en cause, l'échec précédent est gardé tel quel.
        #expect(CrawlFailure.record(.http, previous: nil, now: now) == nil)
        #expect(CrawlFailure.record(.http, previous: second, now: now) == second)
        #expect(CrawlFailure.reason(for: LoLAPIError.statsDisabled) == .statsDisabled)
        #expect(CrawlFailure.reason(for: LoLAPIError.noData) == .noData)
        #expect(CrawlFailure.reason(for: LoLAPIError.http(status: 503)) == .http)
        #expect(CrawlFailure.reason(for: URLError(.timedOut)) == .http)
    }

    /// `crawl.json` : `[gameId: CrawlFailure]`, `JSONEncoder` par défaut.
    @Test func failuresRoundTrip() throws {
        let failures = ["g1": CrawlFailure(reason: .notFinished, attempts: 2, lastAttempt: now)]
        #expect(try JSONDecoder().decode([String: CrawlFailure].self, from: JSONEncoder().encode(failures)) == failures)
    }

    /// 2 s entre deux requêtes ; recul 4, 8, 16, 32 s ; arrêt au 5e échec d'affilée ; une réponse remet à 2 s.
    @Test func pacerBacksOffAndStops() {
        var pacer = CrawlPacer()
        #expect(pacer.canRequest)
        let outcomes: [CrawlPacer.Outcome] = [.answered, .retryable, .retryable, .answered,
                                              .retryable, .retryable, .retryable, .retryable, .retryable]
        var decisions: [CrawlPacer.Decision] = []
        for outcome in outcomes { decisions.append(pacer.next(after: outcome)) }
        #expect(decisions == [.wait(2), .wait(4), .wait(8), .wait(2), .wait(4), .wait(8), .wait(16), .wait(32),
                              .stop(.failures)])
        #expect(!pacer.canRequest)
        #expect(pacer.requestsMade == 9)
        #expect(pacer.consecutiveFailures == 5)
    }

    /// 300 requêtes par session (≈ 150 games au palier A) : la 300e arrête la collecte.
    @Test func pacerStopsAtTheSessionBudget() {
        var pacer = CrawlPacer()
        #expect(CrawlPacer.sessionRequestBudget == 300)
        var decisions: [CrawlPacer.Decision] = []
        for _ in 1..<300 { decisions.append(pacer.next(after: .answered)) }
        #expect(decisions.allSatisfy { $0 == .wait(2) })
        #expect(pacer.canRequest)
        let last = pacer.next(after: .answered)
        #expect(last == .stop(.budget))
        #expect(!pacer.canRequest)
        var small = CrawlPacer(budget: 2)
        let first = small.next(after: .retryable)
        let second = small.next(after: .answered)
        #expect(first == .wait(4))
        #expect(second == .stop(.budget))
    }

    @Test func outcomeOfARequest() {
        #expect(CrawlPacer.outcome(of: nil) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.noData) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.statsDisabled) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.http(status: 400)) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.http(status: 429)) == .retryable)
        #expect(CrawlPacer.outcome(of: LoLAPIError.http(status: 503)) == .retryable)
        #expect(CrawlPacer.outcome(of: URLError(.notConnectedToInternet)) == .retryable)
    }

    /// Saison 2026 de la LEC (fixture réelle) : 3 splits ; le 14/10 le split 3 est fini, il reste « le dernier commencé ».
    @Test func seasonAndCurrentTournaments() async throws {
        let fake = FakeTransport()
        try await fake.on("getTournamentsForLeague", body: String(decoding: try SeasonFixture.data(
            "getTournamentsForLeague_lec_reduced"), as: UTF8.self))
        let tournaments = try await LoLClient(transport: fake).tournaments(leagueId: "98767991302996019")
        #expect(CrawlPlanner.seasonTournaments(tournaments, year: 2026).map(\.slug)
                == ["lec_split_3_2026", "lec_split_2_2026", "lec_split_1_2026"])
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2026-10-14")?.slug == "lec_split_3_2026")
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2026-04-10")?.slug == "lec_split_2_2026")
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2026-03-15")?.slug == "lec_split_1_2026")
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2020-01-01") == nil)
    }

    /// Étape en cours du Mondial : celle du premier match non terminé ; tout terminé → la dernière étape.
    @Test func currentWorldsStage() throws {
        let worlds = try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(
            "getStandings_worlds26_reduced")).data.standings.elements[0]
        #expect(CrawlPlanner.currentStageMatchIds(worlds) == ["115660588583040710", "115660588583171786"])
        let lec = try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(
            "getStandings_lec3_reduced")).data.standings.elements[0]
        #expect(CrawlPlanner.currentStageMatchIds(lec) == ["115548681803406327", "115548681803406333"])
        #expect(CrawlPlanner.currentStageMatchIds(Standings(stages: [])).isEmpty)
    }

    /// Budget disque : 2 000 games ; au-delà, les plus anciennes sans équipe suivie, jamais une game d'équipe suivie.
    @Test func diskBudgetKeepsFollowedTeams() {
        func game(_ id: String, _ start: String, _ blue: String) -> GameSummary {
            let base = summary(id, blue, "X")
            return GameSummary(gameId: id, matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
                               startedAt: date(start), endedAt: date(start).addingTimeInterval(1800),
                               durationSeconds: 1800, result: .unknown, blue: base.blue, red: base.red, enriched: false)
        }
        let games = [game("old-kc", "2026-01-01T10:00:00Z", "KC"), game("old", "2026-01-02T10:00:00Z", "G2"),
                     game("mid", "2026-03-01T10:00:00Z", "T1"), game("new", "2026-09-01T10:00:00Z", "GEN")]
        #expect(CrawlPlanner.diskLimit == 2_000)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC"], limit: 2) == ["old", "mid"])
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC", "G2", "T1", "GEN"], limit: 2).isEmpty)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: [], limit: 4).isEmpty)
    }

    /// Tournois 24 h ; tournoi actif 30 min ; tournoi terminé jamais relu ; pas de copie → à lire.
    @Test func enumerationRefresh() {
        let active = TournamentRef(id: "w", slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-11-15", leagueId: "")
        let done = TournamentRef(id: "s3", slug: "lec_split_3_2026", startDate: "2026-07-23", endDate: "2026-09-20", leagueId: "")
        #expect(CrawlPlanner.maxAge(of: active, today: "2026-10-20") == 1_800)
        #expect(CrawlPlanner.maxAge(of: done, today: "2026-10-20") == nil)
        let fetched = date("2026-10-20T12:00:00Z")
        #expect(CrawlPlanner.needsRefresh(fetchedAt: nil, now: fetched, maxAge: nil))
        #expect(!CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(1_799), maxAge: 1_800))
        #expect(CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(1_800), maxAge: 1_800))
        #expect(!CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(1e7), maxAge: nil))
        #expect(CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(-60),
                                          maxAge: CrawlPlanner.tournamentsMaxAge))
        #expect(CrawlPlanner.tournamentsMaxAge == 86_400)
    }
}
