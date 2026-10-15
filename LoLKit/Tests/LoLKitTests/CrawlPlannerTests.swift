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
        CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC"], liveCompleteStageMatchIds: ["t1-gen"],
                    followedLeagueSlugs: ["lck"], currentTournamentIds: [Self.lec3, Self.worlds, Self.lck3],
                    allowedTournamentIds: [Self.lec3, Self.lec1, Self.worlds, Self.lck3, Self.lck1])
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
        let followFnc = CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC", "FNC"], liveCompleteStageMatchIds: [],
                                    followedLeagueSlugs: [], currentTournamentIds: [Self.lec3],
                                    allowedTournamentIds: [Self.lec3, Self.lec1, Self.worlds, Self.lck3, Self.lck1])
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
        #expect(CrawlPlanner.diskLimit == 4_000)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC"], allowedTournamentIds: ["t"],
                                       previousSeasonTournamentIds: [], limit: 2) == ["old", "mid"])
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC", "G2", "T1", "GEN"], allowedTournamentIds: ["t"],
                                       previousSeasonTournamentIds: [], limit: 2).isEmpty)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: [], allowedTournamentIds: ["t"],
                                       previousSeasonTournamentIds: [], limit: 4).isEmpty)
    }

    /// Spec périmètre §6.1 test 15 : KC suivie, rien en cache, aucun masque — 221 jobs palier A : les 113 games de 2026
    /// (groupe 1) puis les 108 de 2025 (groupe 6) ; jamais un match de `worlds_2024`, même fourni.
    @Test func kcTwoSeasonsComeInPriorityOrder() throws {
        let window = try #require(SeasonWindow(today: "2026-10-15"))
        let bySlug = try PerimetreFixture.tournamentsBySlug()
        let allowed = Set(window.tournaments(Array(bySlug.values)).map(\.id))
        let previousKC = Set(["lec_winter_2025", "lec_spring_2025", "lec_summer_2025", "first_stand_2025"]
            .compactMap { bySlug[$0]?.id })
        #expect(previousKC.count == 4)
        let worlds24 = SeasonMatch(id: "kc-worlds24", tournamentId: PerimetreFixture.worlds2024, leagueSlug: "worlds",
                                   stageSlug: nil, startTime: date("2024-10-05T12:00:00Z"), blockName: nil, bestOf: 1,
                                   teams: [team("KC", wins: 1), team("T1", wins: 0)], playedGameIds: ["kc-worlds24-g1"])
        let matches = try PerimetreFixture.kcG2Matches() + [worlds24]
        func wanted(allowing ids: Set<String>) -> CrawlWanted {
            CrawlWanted(openedTeamId: nil, followedTeamIds: ["KC"], liveCompleteStageMatchIds: [], followedLeagueSlugs: [],
                        currentTournamentIds: [Self.lec3, Self.worlds], allowedTournamentIds: ids,
                        previousSeasonTournamentIds: previousKC)
        }
        let at = date("2026-10-15T12:00:00Z")
        let jobs = CrawlPlanner.jobs(wanted: wanted(allowing: allowed), matches: matches, have: [:], failures: [:],
                                     masked: [], now: at)
        #expect(jobs.count == 221)
        #expect(jobs.allSatisfy { $0.tier == .a })
        #expect(jobs.prefix(113).allSatisfy { $0.priority == 1 })
        #expect(jobs.suffix(108).allSatisfy { $0.priority == 6 })
        #expect(!jobs.contains { $0.tournamentId == PerimetreFixture.worlds2024 })
        // Le même match, autorisé, serait lu : c'est bien la fenêtre qui l'écarte.
        let unbounded = CrawlPlanner.jobs(wanted: wanted(allowing: allowed.union([PerimetreFixture.worlds2024])),
                                          matches: matches, have: [:], failures: [:], masked: [], now: at)
        #expect(unbounded.contains { $0.gameId == "kc-worlds24-g1" })
    }

    /// Spec périmètre §6.1 test 15 (suite) : Demacia Cup 2026 en cours, ligue complète non suivie — l'étape en cours
    /// (`playoffs`, 7 matchs dont 5 joués, 23 games) en groupe 2, les étapes déjà jouées (39 games) en groupe 5.
    @Test func liveCompleteTournamentStageComesFirst() throws {
        let standings = try PerimetreFixture.standings("getStandings_demacia_cup_2026")
        let stage = CrawlPlanner.currentStageMatchIds(standings)
        #expect(stage.count == 7)
        #expect(stage.contains("117133830110912093"))
        let played = standings.stages.flatMap { $0.sections.flatMap(\.matches) }.filter { $0.state == .completed }
        #expect(played.count == 25)
        let matches = played.map { match in
            let games = match.teams.reduce(0) { $0 + $1.gameWins }
            return SeasonMatch(id: match.id, tournamentId: PerimetreFixture.demaciaCup2026, leagueSlug: "demacia_cup",
                               stageSlug: nil, startTime: date("2026-10-10T10:00:00Z"), blockName: nil, bestOf: 5,
                               teams: match.teams, playedGameIds: (1...games).map { "\(match.id)-g\($0)" })
        }
        let wanted = CrawlWanted(openedTeamId: nil, followedTeamIds: [], liveCompleteStageMatchIds: stage,
                                 followedLeagueSlugs: [], currentTournamentIds: [PerimetreFixture.demaciaCup2026],
                                 allowedTournamentIds: [PerimetreFixture.demaciaCup2026],
                                 completeTournamentIds: [PerimetreFixture.demaciaCup2026])
        let jobs = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: [:], failures: [:], masked: [],
                                     now: date("2026-10-15T12:00:00Z"))
        #expect(jobs.count == 62)
        #expect(jobs.prefix(23).allSatisfy { $0.priority == 2 })
        #expect(jobs.suffix(39).allSatisfy { $0.priority == 5 })
    }

    /// Groupes 5-8 après les 0-4 : complet en cours, suivies N − 1, complets terminés, ligues suivies N − 1.
    @Test func historyGroupsComeAfterTheCurrentSeason() {
        let wanted = CrawlWanted(openedTeamId: nil, followedTeamIds: ["KC"], liveCompleteStageMatchIds: [],
                                 followedLeagueSlugs: ["lck"], currentTournamentIds: ["t-dc"],
                                 allowedTournamentIds: ["t25", "t-lck25", "t-msi25", "t-dc"],
                                 previousSeasonTournamentIds: ["t25", "t-lck25", "t-msi25"],
                                 completeTournamentIds: ["t-msi25", "t-dc"])
        let list = [
            match("fol-25", "t25", "lec", "2025-08-02T15:00:00Z", "KC", "FNC"),
            match("lg-25", "t-lck25", "lck", "2025-08-03T09:00:00Z", "HLE", "DK"),
            match("cmp-done", "t-msi25", "msi", "2025-07-01T09:00:00Z", "GEN", "BLG"),
            match("cmp-live", "t-dc", "demacia_cup", "2026-10-10T09:00:00Z", "BFX", "JDG"),
        ]
        let jobs = CrawlPlanner.jobs(wanted: wanted, matches: list, have: [:], failures: [:], masked: [], now: now)
        #expect(jobs.map(\.matchId) == ["cmp-live", "cmp-live", "fol-25", "fol-25", "cmp-done", "cmp-done", "lg-25", "lg-25"])
        #expect(jobs.map(\.priority) == [5, 5, 6, 6, 7, 7, 8, 8])
    }

    /// Spec périmètre §6.1 test 16 : hors fenêtre toujours supprimé (même d'une équipe suivie, même sous la limite) ;
    /// au-delà de la limite, la saison N − 1 des équipes non suivies d'abord (la plus ancienne d'abord), puis N.
    @Test func diskBudgetDropsOutsideGamesThenThePreviousSeason() {
        func game(_ id: String, _ tournament: String, _ start: String, _ blue: String) -> GameSummary {
            let base = summary(id, blue, "X")
            return GameSummary(gameId: id, matchId: "m", tournamentId: tournament, leagueSlug: "lec", number: 1,
                               patch: nil, startedAt: date(start), endedAt: date(start).addingTimeInterval(1800),
                               durationSeconds: 1800, result: .unknown, blue: base.blue, red: base.red, enriched: false)
        }
        let outside = [game("w24-1", "w24", "2024-10-01T10:00:00Z", "KC"), game("w24-2", "w24", "2024-10-01T11:00:00Z", "KC"),
                       game("w24-3", "w24", "2024-10-01T12:00:00Z", "KC")]
        let inside = [game("k26", "t26", "2026-05-01T10:00:00Z", "KC"), game("n26", "t26", "2026-01-10T10:00:00Z", "G2"),
                      game("n25a", "t25", "2025-08-01T10:00:00Z", "G2"), game("n25b", "t25", "2026-01-12T10:00:00Z", "T1")]
        func evict(_ games: [GameSummary], limit: Int) -> [String] {
            CrawlPlanner.evictions(games, followedTeamIds: ["KC"], allowedTournamentIds: ["t26", "t25"],
                                   previousSeasonTournamentIds: ["t25"], limit: limit)
        }
        #expect(evict(outside + inside, limit: 10) == ["w24-1", "w24-2", "w24-3"])
        #expect(evict(inside, limit: 3) == ["n25a"])
        // `n25b` (N − 1, 12/01/2026) part avant `n26` (N, 10/01/2026), bien que plus récente.
        #expect(evict(inside, limit: 2) == ["n25a", "n25b"])
        #expect(evict(inside, limit: 1) == ["n25a", "n25b", "n26"])
        // Une game d'équipe suivie dans la fenêtre n'est jamais supprimée.
        #expect(evict(inside, limit: 0) == ["n25a", "n25b", "n26"])
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
