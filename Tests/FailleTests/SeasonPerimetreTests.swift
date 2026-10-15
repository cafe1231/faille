import Foundation
import LoLKit
import Testing
@testable import Faille

// MARK: Fixtures du périmètre (dossier `perimetre` du paquet de tests)

private final class PerimetreBundle {}

private let today = LoLDate.parse("2026-10-15T15:00:00Z")!
private let worldsId = "98767975604431411"
private let lecId = "98767991302996019"
private let msiId = "98767991325878492"
private let firstStandId = "113464388705111224"
private let demaciaId = "117126995932274206"
private let worlds2026 = "115660540725177488"
private let worlds2025 = "113475452383887518"
private let worlds2024 = "112966669920590211"
private let demacia2026 = "117133773242499009"

private enum PerimetreFiles {
    struct Missing: Error { let name: String }

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: PerimetreBundle.self)
            .url(forResource: name, withExtension: "json", subdirectory: "perimetre") else { throw Missing(name: name) }
        return try Data(contentsOf: url)
    }

    private struct TournamentsFile: Decodable {
        struct Payload: Decodable { let leagues: [League] }
        struct League: Decodable { let tournaments: [TournamentRef] }
        let data: Payload
    }

    /// Tournois d'une ligue (`getTournamentsForLeague_<slug>.json`) avec leur `leagueId`.
    static func tournaments(_ slug: String, leagueId: String) throws -> [TournamentRef] {
        try JSONDecoder().decode(TournamentsFile.self, from: data("getTournamentsForLeague_\(slug)")).data.leagues
            .flatMap(\.tournaments)
            .map { TournamentRef(id: $0.id, slug: $0.slug, startDate: $0.startDate, endDate: $0.endDate, leagueId: leagueId) }
    }

    static func allTournaments() throws -> [TournamentRef] {
        try tournaments("worlds", leagueId: worldsId) + tournaments("lec", leagueId: lecId)
            + tournaments("msi", leagueId: msiId) + tournaments("first_stand", leagueId: firstStandId)
            + tournaments("demacia_cup", leagueId: demaciaId)
    }

    struct ReducedTeam: Decodable { let code: String; let name: String; let gameWins: Int }
    struct ReducedMatch: Decodable {
        let matchId: String
        let startTime: String
        let blockName: String?
        let teams: [ReducedTeam]
        let playedGameIds: [String]
    }
    struct ReducedTournament: Decodable { let kcG2Matches: [ReducedMatch]? }

    /// Matchs réels de KC et G2 par id de tournoi.
    static func reducedByTournamentId() throws -> [String: [ReducedMatch]] {
        let bySlug = Dictionary(try allTournaments().map { ($0.slug, $0.id) }, uniquingKeysWith: { first, _ in first })
        let reduced = try JSONDecoder().decode([String: ReducedTournament].self,
                                               from: data("completed_kc_g2_2024_2026_reduced"))
        var result: [String: [ReducedMatch]] = [:]
        for (slug, tournament) in reduced {
            guard let id = bySlug[slug], let matches = tournament.kcG2Matches, !matches.isEmpty else { continue }
            result[id] = matches
        }
        return result
    }

    /// `SeasonMatch` de KC et G2 (ids d'équipe = code), pour un store d'aperçu.
    static func kcG2Matches() throws -> [SeasonMatch] {
        try reducedByTournamentId().flatMap { tournamentId, matches in
            matches.map { match in
                SeasonMatch(id: match.matchId, tournamentId: tournamentId, leagueSlug: "", stageSlug: nil,
                            startTime: LoLDate.parse(match.startTime)!, blockName: match.blockName,
                            bestOf: 2 * (match.teams.map(\.gameWins).max() ?? 1) - 1,
                            teams: match.teams.map {
                                MatchTeam(id: $0.code, name: $0.name, code: $0.code, image: nil,
                                          result: MatchTeam.Result(outcome: nil, gameWins: $0.gameWins))
                            },
                            playedGameIds: match.playedGameIds)
            }
        }
    }

    /// Réponse `getCompletedEvents` (forme de l'API, équipes sans id) construite depuis la fixture réduite.
    static func completedEvents(_ matches: [ReducedMatch]) -> Data {
        let events = matches.map { match in
            let best = match.teams.map(\.gameWins).max() ?? 0
            let teams = match.teams.map {
                #"{"name":"\#($0.name)","code":"\#($0.code)","image":null,"result":{"outcome":"\#($0.gameWins == best ? "win" : "loss")","gameWins":\#($0.gameWins)}}"#
            }.joined(separator: ",")
            let games = match.playedGameIds.map { #"{"id":"\#($0)","vods":[]}"# }.joined(separator: ",")
            return #"{"startTime":"\#(match.startTime)","blockName":"\#(match.blockName ?? "")","league":{"name":"x"},"match":{"id":"\#(match.matchId)","type":"normal","teams":[\#(teams)],"strategy":{"type":"bestOf","count":\#(max(1, 2 * best - 1))}},"games":[\#(games)]}"#
        }.joined(separator: ",")
        return Data(#"{"data":{"schedule":{"events":[\#(events)]}}}"#.utf8)
    }
}

/// Horloge virtuelle : `sleep` avance l'heure sans attendre.
private actor PerimetreClock: CrawlClock {
    private var current: Date
    init(_ start: Date) { current = start }
    func now() async -> Date { current }
    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        current = current.addingTimeInterval(seconds)
    }
}

/// Faux lolesports servant les fixtures réelles : tournois des 5 ligues, résultats de KC et G2, classement de la Demacia
/// Cup ; flux livestats → 404 (stats désactivées : une requête par game). Garde les URL.
private actor PerimetreWorld: HTTPTransport {
    private(set) var requests: [URL] = []
    private let completed: [String: Data]
    private let leagueFixtures = [worldsId: "worlds", lecId: "lec", msiId: "msi", firstStandId: "first_stand",
                                  demaciaId: "demacia_cup"]

    init(completed: [String: Data]) {
        self.completed = completed
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        let path = url.path(percentEncoded: false)
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        if path.hasSuffix("/getTournamentsForLeague"), let name = leagueFixtures[query["leagueId"] ?? ""] {
            return HTTPResponse(status: 200, body: try PerimetreFiles.data("getTournamentsForLeague_\(name)"))
        }
        if path.hasSuffix("/getCompletedEvents") {
            return HTTPResponse(status: 200, body: completed[query["tournamentId"] ?? ""]
                ?? Data(#"{"data":{"schedule":{"events":[]}}}"#.utf8))
        }
        if path.hasSuffix("/getStandings") {
            if query["tournamentId"] == demacia2026 {
                return HTTPResponse(status: 200, body: try PerimetreFiles.data("getStandings_demacia_cup_2026"))
            }
            return HTTPResponse(status: 200, body: Data(#"{"data":{"standings":[]}}"#.utf8))
        }
        return HTTPResponse(status: 404, body: Data())
    }
}

private let perimetreLeagues = [
    League(id: worldsId, slug: "worlds", name: "Mondial", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: lecId, slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1),
    League(id: msiId, slug: "msi", name: "MSI", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: firstStandId, slug: "first_stand", name: "First Stand", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: demaciaId, slug: "demacia_cup", name: "DCGI", region: "INTERNATIONAL", image: nil, priority: 1),
]

private let karmine = Team(id: "kc", slug: "karmine-corp", name: "Karmine Corp", code: "KC", image: nil, status: "active",
                           homeLeague: Team.HomeLeague(name: "LEC"))

private func line(_ teamId: String) -> TeamGameLine {
    TeamGameLine(teamId: teamId, kills: 10, gold: 60_000, towers: 8, inhibitors: 1, barons: 1, dragons: [], gold15: nil,
                 players: [])
}

private func game(id: String, tournamentId: String, startedAt: String) -> GameSummary {
    let start = LoLDate.parse(startedAt)!
    return GameSummary(gameId: id, matchId: "m-\(id)", tournamentId: tournamentId, leagueSlug: "lec", number: 1,
                       patch: nil, startedAt: start, endedAt: start.addingTimeInterval(1_800), durationSeconds: 1_800,
                       result: .unknown, blue: line("kc"), red: line("g2"), enriched: false)
}

@MainActor
@Suite(.serialized)
struct SeasonPerimetreTests {
    /// Spec périmètre §6.2 test 18 : premier lancement — tout ce qui date d'avant 2025 part, une seule fois.
    @Test func theFirstLaunchPurgesEverythingBefore2025Once() async throws {
        let cache = DiskCache(root: TemporaryFiles.directory())
        let worlds = try PerimetreFiles.tournaments("worlds", leagueId: worldsId)
        #expect(worlds.count == 11)
        cache.save(Cached(value: worlds, fetchedAt: today), to: SeasonDisk.tournamentsPath(worldsId))
        cache.save(game(id: "115548681803406304", tournamentId: "115548681802226458", startedAt: "2026-09-06T15:17:23.939Z"),
                   to: SeasonDisk.gamePath("115548681803406304"))
        cache.save(game(id: "112966669924194882", tournamentId: worlds2024, startedAt: "2024-11-02T14:35:43.676Z"),
                   to: SeasonDisk.gamePath("112966669924194882"))
        cache.save(Cached(value: [CompletedMatch](), fetchedAt: today), to: SeasonDisk.completedPath(worlds2024))
        cache.save(Cached(value: Standings(stages: []), fetchedAt: today), to: SeasonDisk.standingsPath(worlds2024))
        cache.save(ReplayRecord(firstFrame: LoLDate.parse("2024-11-02T14:35:43.676Z")!, frames: [], lastStep: nil,
                                complete: true), to: "replays/112966669924194882.json")
        cache.save(ReplayRecord(firstFrame: LoLDate.parse("2026-09-06T15:17:23.939Z")!, frames: [], lastStep: nil,
                                complete: true), to: "replays/115548681803406304.json")
        cache.write(Data("pas du json".utf8), to: "replays/illisible.json")

        let store = SeasonStore(transport: StubTransport(), cache: cache, clock: PerimetreClock(today))
        await store.loadFromDisk()

        for path in [SeasonDisk.gamePath("112966669924194882"), SeasonDisk.completedPath(worlds2024),
                     SeasonDisk.standingsPath(worlds2024), "replays/112966669924194882.json"] {
            #expect(cache.data(path) == nil, "\(path) aurait dû être supprimé")
        }
        #expect(cache.data("replays/illisible.json") != nil)
        #expect(cache.data("replays/115548681803406304.json") != nil)
        #expect(cache.data(SeasonDisk.gamePath("115548681803406304")) != nil)
        let rewritten = try #require(cache.load(Cached<[TournamentRef]>.self, from: SeasonDisk.tournamentsPath(worldsId)))
        #expect(rewritten.value.map(\.id) == [worlds2026, worlds2025])
        #expect(cache.load(SeasonPurge.Marker.self, from: SeasonPurge.markerPath)
                == SeasonPurge.Marker(v: 1, startDay: "2025-01-01"))
        #expect(Set(store.games.keys) == ["115548681803406304"])
        #expect(store.tournaments[worldsId]?.count == 2)
        #expect(store.isOutsideWindow(tournamentId: worlds2024))
        // Second lancement : marqueur à jour → aucun fichier du Détail relu.
        let again = SeasonDisk(cache: cache).load(window: SeasonWindow(now: today))
        #expect(again.detailFilesRead == 0)
    }

    /// Spec périmètre §6.2 test 19 : une passe complète pour KC suivie — rien de 2024, une énumération par ligue, la
    /// Demacia Cup (complète, non suivie) lue, 2 s entre deux requêtes, arrêt à 300.
    @Test func aFullPassForKarmineCorpNeverTouches2024() async throws {
        let completed = try PerimetreFiles.reducedByTournamentId().mapValues(PerimetreFiles.completedEvents)
        let world = PerimetreWorld(completed: completed)
        let store = SeasonStore(transport: world, cache: DiskCache(root: TemporaryFiles.directory()),
                                clock: PerimetreClock(today))
        let follows = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", homeLeagueName: "LEC")])
        let end = await store.crawl {
            SeasonContext(follows: follows, leagues: perimetreLeagues, catalog: [karmine], revealed: [],
                          openedTeamId: nil, now: today)
        }
        #expect(end == .budget)
        let urls = await world.requests.map(\.absoluteString)
        #expect(urls.count == CrawlPacer.sessionRequestBudget)
        #expect(!urls.contains { $0.contains(worlds2024) })
        for leagueId in [worldsId, lecId, msiId, firstStandId, demaciaId] {
            #expect(urls.filter { $0.contains("getTournamentsForLeague") && $0.contains(leagueId) }.count == 1)
        }
        #expect(urls.contains { $0.contains("getCompletedEvents") && $0.contains(demacia2026) })
        let sent = try #require(await store.paced?.sentAt)
        for (earlier, later) in zip(sent, sent.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= CrawlPacer.baseInterval)
        }
        // Les games demandées sont toutes des games réelles de KC ou de G2 (2025-2026).
        let known = Set(try PerimetreFiles.reducedByTournamentId().values.flatMap { $0.flatMap(\.playedGameIds) })
        let windows = urls.filter { $0.contains("/window/") }
            .compactMap { URL(string: $0)?.path.split(separator: "/").last.map(String.init) }
        #expect(!windows.isEmpty)
        #expect(Set(windows).isSubset(of: known))
    }

    /// Spec périmètre §6.2 test 20 : le store n'expose que la fenêtre.
    @Test func theStoreOnlyExposesTheWindow() throws {
        let cache = DiskCache(root: TemporaryFiles.directory())
        let store = SeasonStore(transport: StubTransport(), cache: cache, clock: PerimetreClock(today))
        store.record(tournaments: try PerimetreFiles.tournaments("worlds", leagueId: worldsId), leagueId: worldsId, at: today)
        #expect(store.tournaments[worldsId]?.map(\.id) == [worlds2026, worlds2025])
        #expect(store.isOutsideWindow(tournamentId: worlds2024))
        let old = CompletedMatch(matchId: "m-2024", startTime: LoLDate.parse("2024-11-02T14:00:00Z")!, blockName: nil,
                                 bestOf: 5, teams: [], gameIds: [])
        store.record(completed: [old], tournamentId: worlds2024, at: today)
        #expect(store.matches.isEmpty)
        #expect(cache.data(SeasonDisk.completedPath(worlds2024)) == nil)
        store.record(game(id: "g-2024", tournamentId: worlds2024, startedAt: "2024-11-02T14:35:43.676Z"), followedTeamIds: [])
        #expect(store.games["g-2024"] == nil)
        #expect(SeasonPlanning.currentTournamentIds(store.tournaments, leagueIds: [worldsId], now: today) == [worlds2026])

        // Pilules de KC (spec test 10) sur un store d'aperçu nourri des vrais matchs.
        let preview = SeasonStore(preview: SeasonPreview(tournaments: try PerimetreFiles.allTournaments(),
                                                         matches: try PerimetreFiles.kcG2Matches()))
        #expect(preview.scopes(forTeam: "KC", now: today).map(\.label) == [
            "2026", "lec_split_3_2026", "msi_2026", "lec_split_2_2026", "lec_split_1_2026",
            "2025", "lec_summer_2025", "lec_spring_2025", "first_stand_2025", "lec_winter_2025",
        ])
        #expect(preview.referenceSeason(forTeams: ["KC"], now: today) == 2026)
        #expect(preview.referenceSeason(forTeams: ["KC"], now: LoLDate.parse("2027-01-05T12:00:00Z")!) == 2026)
        #expect(preview.matches(inSeason: 2025).filter { $0.involves("KC") }.count == 40)
        #expect(preview.matches(inSeason: 2026).filter { $0.involves("KC") }.count == 46)
        #expect(preview.seasonScope(2025).tournamentIds.count == 6)
    }

    /// Appartenance à une saison par tournoi (jamais par la date de la game).
    @Test func gamesBelongToTheSeasonOfTheirTournament() throws {
        let tournaments = try PerimetreFiles.allTournaments()
        let lecWinter2025 = "113475994398658012"
        let lecSplit3 = "115548681802226458"
        let preview = SeasonStore(preview: SeasonPreview(
            tournaments: tournaments,
            games: [game(id: "g26", tournamentId: lecSplit3, startedAt: "2026-09-06T15:17:23.939Z"),
                    game(id: "g25", tournamentId: lecWinter2025, startedAt: "2025-01-18T17:09:12.350Z")]))
        #expect(preview.games(inSeason: 2025).map(\.gameId) == ["g25"])
        #expect(preview.games(inSeason: 2026).map(\.gameId) == ["g26"])
        #expect(preview.season(ofTournament: lecWinter2025) == 2025)
    }

    /// Énumération : ligues complètes (Demacia Cup) et prédécesseurs (LCS → LTA North / Cross, saison N − 1 seule).
    @Test func planningEnumeratesCompleteLeaguesAndPredecessors() {
        let lcsId = "98767991299243165"
        let ltaNId = "113470291645289904"
        let ltaCrossId = "113475149040947852"
        let lcs = League(id: lcsId, slug: "lcs", name: "LCS", region: "AMÉRIQUE DU NORD", image: nil, priority: 1)
        let leagues = [
            perimetreLeagues[0], perimetreLeagues[1], lcs,
            League(id: ltaNId, slug: "lta_n", name: "LTA North", region: "AMERICAS", image: nil, priority: 1),
            League(id: ltaCrossId, slug: "lta_cross", name: "LTA Cross-Conference", region: "AMERICAS", image: nil, priority: 1),
            perimetreLeagues[4],
        ]
        let context = SeasonContext(follows: FollowList(leagues: [FollowedLeague(league: lcs)]), leagues: leagues,
                                    catalog: [], revealed: [], openedTeamId: nil, now: today)
        #expect(Set(SeasonPlanning.leagueIds(context)) == [worldsId, lcsId, demaciaId, ltaNId, ltaCrossId])
        #expect(SeasonPlanning.predecessorLeagueIds(context) == [ltaNId, ltaCrossId])
        let byLeague: [String: [TournamentRef]] = [
            worldsId: [
                TournamentRef(id: worlds2026, slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-11-15", leagueId: worldsId),
                TournamentRef(id: worlds2025, slug: "worlds_2025", startDate: "2025-10-14", endDate: "2025-11-09", leagueId: worldsId),
                TournamentRef(id: worlds2024, slug: "worlds_2024", startDate: "2024-09-24", endDate: "2024-11-02", leagueId: worldsId),
            ],
            lcsId: [TournamentRef(id: "lcs-26", slug: "lcs_split_3_2026", startDate: "2026-07-25", endDate: "2026-09-14", leagueId: lcsId)],
            ltaNId: [TournamentRef(id: "ltan-25", slug: "lta_n_split_3_2025", startDate: "2025-07-26", endDate: "2025-09-14", leagueId: ltaNId)],
        ]
        let started = SeasonPlanning.startedTournaments(byLeague, leagueIds: SeasonPlanning.leagueIds(context),
                                                        predecessorLeagueIds: SeasonPlanning.predecessorLeagueIds(context),
                                                        now: today)
        #expect(started.map(\.id) == [worlds2026, "lcs-26", worlds2025, "ltan-25"])
        let wanted = SeasonPlanning.wanted(context, byLeague: byLeague, standings: [:])
        #expect(wanted.allowedTournamentIds == [worlds2026, worlds2025, "lcs-26", "ltan-25"])
        #expect(wanted.previousSeasonTournamentIds == [worlds2025, "ltan-25"])
        #expect(wanted.completeTournamentIds == [worlds2026, worlds2025])
        #expect(!wanted.currentTournamentIds.contains("ltan-25"))
    }
}
