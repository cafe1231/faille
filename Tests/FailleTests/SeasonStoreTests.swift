import Foundation
import LoLKit
import Testing
@testable import Faille

// MARK: Faux monde lolesports

/// Horloge virtuelle : `sleep` avance l'heure sans attendre ; garde chaque attente demandée.
private actor VirtualClock: CrawlClock {
    private(set) var current: Date
    private(set) var sleeps: [TimeInterval] = []

    init(_ start: Date) {
        current = start
    }

    func now() async -> Date {
        current
    }

    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        sleeps.append(seconds)
        current = current.addingTimeInterval(seconds)
    }
}

/// Un match joué du faux monde : ses équipes (avec id), leurs victoires, ses games jouées (préfixe de `games`).
private struct FakeMatch {
    let id: String
    let start: String
    let teams: [(id: String, code: String, wins: Int)]
    var gameIds: [String] {
        (1...teams.reduce(0) { $0 + $1.wins }).map { "\(id)-g\($0)" }
    }
}

/// Faux API + flux livestats : une ligue (LEC) et le Mondial, un tournoi chacun, les matchs donnés ; `window` d'une game
/// sans `startingTime` → sa première frame, avec → sa frame `finished` ; `details` → 404. Garde les URL demandées.
private actor FakeLoLWorld: HTTPTransport {
    private(set) var requests: [URL] = []
    let lec: [FakeMatch]
    let worlds: [FakeMatch]
    /// Games dont le flux répond 404 (stats désactivées par Riot).
    let disabled: Set<String>
    /// Statut forcé pour les N premières requêtes `window` (503 : panne).
    private var failingWindows: Int

    init(lec: [FakeMatch], worlds: [FakeMatch] = [], disabled: Set<String> = [], failingWindows: Int = 0) {
        self.lec = lec
        self.worlds = worlds
        self.disabled = disabled
        self.failingWindows = failingWindows
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        let path = url.path(percentEncoded: false)
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        if path.hasSuffix("/getTournamentsForLeague") {
            let lecLeague = query["leagueId"] == "98767991302996019"
            let tournament = lecLeague
                ? #"{"id":"t-lec","slug":"lec_split_3_2026","startDate":"2026-07-23","endDate":"2026-09-20"}"#
                : #"{"id":"t-worlds","slug":"worlds_2026","startDate":"2026-10-01","endDate":"2026-11-15"}"#
            return ok(#"{"data":{"leagues":[{"tournaments":[\#(tournament)]}]}}"#)
        }
        if path.hasSuffix("/getCompletedEvents") {
            let matches = query["tournamentId"] == "t-lec" ? lec : worlds
            return ok(#"{"data":{"schedule":{"events":[\#(matches.map(Self.event).joined(separator: ","))]}}}"#)
        }
        if path.hasSuffix("/getStandings") {
            let matches = query["tournamentId"] == "t-lec" ? lec : worlds
            let bracket = matches.map(Self.bracket).joined(separator: ",")
            return ok(#"{"data":{"standings":[{"stages":[{"id":"s1","name":"Saison","slug":"regular_season","sections":[{"name":"Saison","matches":[\#(bracket)],"rankings":[]}]}]}]}}"#)
        }
        if path.contains("/livestats/v1/details/") {
            return HTTPResponse(status: 404, body: Data())
        }
        if path.contains("/livestats/v1/window/") {
            if failingWindows > 0 {
                failingWindows -= 1
                return HTTPResponse(status: 503, body: Data())
            }
            let gameId = String(path.split(separator: "/").last ?? "")
            if disabled.contains(gameId) { return HTTPResponse(status: 404, body: Data()) }
            let first = query["startingTime"] == nil
            return ok(Self.window(gameId: gameId, finished: !first))
        }
        return HTTPResponse(status: 404, body: Data())
    }

    private func ok(_ body: String) -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(body.utf8))
    }

    private static func team(_ team: (id: String, code: String, wins: Int), withId: Bool, won: Bool) -> String {
        let id = withId ? #""id":"\#(team.id)","slug":"\#(team.id)","# : ""
        return #"{\#(id)"name":"\#(team.code) Esports","code":"\#(team.code)","image":null,"result":{"outcome":"\#(won ? "win" : "loss")","gameWins":\#(team.wins)}}"#
    }

    private static func event(_ match: FakeMatch) -> String {
        let best = match.teams.map(\.wins).max() ?? 0
        let teams = match.teams.map { team($0, withId: false, won: $0.wins == best) }.joined(separator: ",")
        // Une game listée de plus, jamais jouée (comme l'API : games[] liste aussi les games inutiles).
        let games = (match.gameIds + ["\(match.id)-unneeded"]).map { #"{"id":"\#($0)","vods":[]}"# }.joined(separator: ",")
        return #"{"startTime":"\#(match.start)","blockName":"Semaine 1","league":{"name":"LEC"},"match":{"id":"\#(match.id)","type":"normal","teams":[\#(teams)],"strategy":{"type":"bestOf","count":3}},"games":[\#(games)]}"#
    }

    private static func bracket(_ match: FakeMatch) -> String {
        let best = match.teams.map(\.wins).max() ?? 0
        let teams = match.teams.map { team($0, withId: true, won: $0.wins == best) }.joined(separator: ",")
        return #"{"id":"\#(match.id)","state":"completed","previousMatchIds":[],"flags":[],"teams":[\#(teams)]}"#
    }

    private static func window(gameId: String, finished: Bool) -> String {
        let time = finished ? "2026-09-01T18:35:00.000Z" : "2026-09-01T18:00:00.000Z"
        let side = #""inhibitors":0,"towers":5,"barons":0,"dragons":[],"participants":[]"#
        return #"{"esportsGameId":"\#(gameId)","esportsMatchId":"m","gameMetadata":{"patchVersion":"16.17.1","blueTeamMetadata":{"esportsTeamId":"kc","participantMetadata":[]},"redTeamMetadata":{"esportsTeamId":"g2","participantMetadata":[]}},"frames":[{"rfc460Timestamp":"\#(time)","gameState":"\#(finished ? "finished" : "in_game")","blueTeam":{"totalGold":60000,"totalKills":12,\#(side)},"redTeam":{"totalGold":55000,"totalKills":7,\#(side)}}]}"#
    }
}

/// Transport qui garde la première requête en vol jusqu'à `release()` (puis répond 503), les suivantes répondent 200 :
/// une réponse qui arrive après `beginSession()`.
private actor GateTransport: HTTPTransport {
    private var entered = false
    private var open = false
    private var waiter: CheckedContinuation<Void, Never>?

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        if open { return HTTPResponse(status: 200, body: Data()) }
        entered = true
        await withCheckedContinuation { waiter = $0 }
        return HTTPResponse(status: 503, body: Data())
    }

    var hasEntered: Bool {
        entered
    }

    func release() {
        open = true
        waiter?.resume()
        waiter = nil
    }
}

/// Une game d'exemple sous un autre id, un autre début et une autre version de schéma (JSON modifié : les champs de
/// `GameSummary` sont des `let`).
private func sampleGame(id: String, startedAt: TimeInterval? = nil, version: Int? = nil) throws -> (GameSummary, Data) {
    guard let base = SeasonSamples.games.first else { throw CocoaError(.fileReadCorruptFile) }
    let data = try JSONEncoder().encode(base)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    object["gameId"] = id
    if let startedAt { object["startedAt"] = startedAt }
    if let version { object["v"] = version }
    let edited = try JSONSerialization.data(withJSONObject: object)
    return (try JSONDecoder().decode(GameSummary.self, from: edited), edited)
}

private let lecId = "98767991302996019"
private let worldsId = "98767975604431411"
private let today = LoLDate.parse("2026-10-15T15:00:00Z")!

private let leagues = [
    League(id: worldsId, slug: "worlds", name: "Mondial", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: lecId, slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1),
]

private let kcTeam = Team(id: "kc", slug: "kc", name: "KC Esports", code: "KC", image: nil, status: "active",
                          homeLeague: Team.HomeLeague(name: "LEC"))

private func context(follows: FollowList, revealed: Set<String> = [], opened: String? = nil) -> SeasonContext {
    SeasonContext(follows: follows, leagues: leagues, catalog: [kcTeam], revealed: revealed, openedTeamId: opened, now: today)
}

private func kcFollowed(spoilerFree: Bool = false) -> FollowList {
    FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "KC Esports", homeLeagueName: "LEC",
                                    spoilerFree: spoilerFree)])
}

/// Matchs de KC en LEC, du plus ancien au plus récent (2-0 chacun), et un match sans KC.
private let lecMatches = [
    FakeMatch(id: "m1", start: "2026-08-01T17:00:00Z", teams: [("kc", "KC", 2), ("g2", "G2", 0)]),
    FakeMatch(id: "m2", start: "2026-08-08T17:00:00Z", teams: [("kc", "KC", 2), ("vit", "VIT", 1)]),
    FakeMatch(id: "m3", start: "2026-08-15T17:00:00Z", teams: [("sk", "SK", 0), ("kc", "KC", 2)]),
    FakeMatch(id: "m4", start: "2026-08-22T17:00:00Z", teams: [("th", "TH", 2), ("g2", "G2", 1)]),
]

@MainActor
private func makeStore(_ world: FakeLoLWorld, clock: VirtualClock, root: URL = TemporaryFiles.directory()) -> SeasonStore {
    SeasonStore(transport: world, cache: DiskCache(root: root), clock: clock)
}

private func gameIds(_ requests: [URL]) -> [String] {
    requests.filter { $0.path.contains("/window/") }.map { String($0.path.split(separator: "/").last ?? "") }
}

// MARK: Tests

/// Collecte de saison (spec saison §1.6) : ordre, cadence, budget, anti-spoiler, reprise, échecs.
@MainActor
struct SeasonStoreTests {
    @Test func followedTeamGamesAreReadMostRecentFirstAfterTheEnumeration() async throws {
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: VirtualClock(today))
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .done)
        let requests = await world.requests
        // Énumération d'abord : tournois du Mondial et de la LEC, puis résultats et classements de chaque tournoi.
        #expect(requests.prefix(6).allSatisfy { !$0.path.contains("/livestats/") })
        // Puis le palier A des games de KC (m3, m2, m1 : la plus récente d'abord), deux requêtes par game, jamais m4 (sans
        // KC) ni la game listée mais pas jouée…
        let feed = gameIds(requests)
        #expect(Array(feed.prefix(14)) == ["m3-g1", "m3-g1", "m3-g2", "m3-g2", "m2-g1", "m2-g1", "m2-g2", "m2-g2",
                                           "m2-g3", "m2-g3", "m1-g1", "m1-g1", "m1-g2", "m1-g2"])
        // … puis le palier B (équipe suivie, tournoi en cours) : début, fin et fenêtre à 15 min de chaque game (LoLKit
        // réduit la game à nouveau), et `details`.
        #expect(Array(feed.dropFirst(14)) == ["m3-g1", "m3-g1", "m3-g1", "m3-g2", "m3-g2", "m3-g2", "m2-g1", "m2-g1",
                                              "m2-g1", "m2-g2", "m2-g2", "m2-g2", "m2-g3", "m2-g3", "m2-g3", "m1-g1",
                                              "m1-g1", "m1-g1", "m1-g2", "m1-g2", "m1-g2"])
        #expect(requests.filter { $0.path.contains("/details/") }.count == 7)
        #expect(store.games.count == 7)
        #expect(store.games.values.allSatisfy { $0.enriched })
        #expect(store.games["m3-g2"]?.durationSeconds == 2100)
        #expect(store.matches.count == 4)
    }

    @Test func twoRequestsAreAlwaysAtLeastTwoSecondsApart() async throws {
        let clock = VirtualClock(today)
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: clock)
        await store.crawl { context(follows: kcFollowed()) }
        let sent = try #require(await store.paced?.sentAt)
        #expect(sent.count == (await world.requests.count))
        for (earlier, later) in zip(sent, sent.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= CrawlPacer.baseInterval)
        }
    }

    @Test func aSessionStopsAtItsBudgetOfThreeHundredRequests() async throws {
        // 160 matchs de KC à 1 game : 6 requêtes d'énumération + 2 par game dépassent le budget.
        let many = (0..<160).map { index in
            FakeMatch(id: "b\(index)", start: "2026-08-01T\(String(format: "%02d", index % 24)):00:00Z",
                      teams: [("kc", "KC", 1), ("g2", "G2", 0)])
        }
        let world = FakeLoLWorld(lec: many)
        let store = makeStore(world, clock: VirtualClock(today))
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .budget)
        #expect(await world.requests.count == CrawlPacer.sessionRequestBudget)
        #expect(store.stopReason == .budget)
        // Nouvelle session : le budget repart.
        await store.beginSession()
        #expect(await store.paced?.sent == 0)
        #expect(store.stopReason == nil)
    }

    @Test func screensKeepASmallReserveAfterTheCrawlBudgetIsSpent() async throws {
        let many = (0..<160).map { index in
            FakeMatch(id: "b\(index)", start: "2026-08-01T\(String(format: "%02d", index % 24)):00:00Z",
                      teams: [("kc", "KC", 1), ("g2", "G2", 0)])
        }
        let world = FakeLoLWorld(lec: many)
        let store = makeStore(world, clock: VirtualClock(today))
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .budget)
        for index in 0..<25 { await store.loadStandings(tournamentId: "t-extra\(index)") }
        // Un classement ouvert se lit malgré l'arrêt de la collecte, dans la limite de la réserve (20 par session).
        #expect(await world.requests.count == CrawlPacer.sessionRequestBudget + PacedTransport.onDemandBudget)
        #expect(store.standings["t-extra0"] != nil)
        #expect(store.standings["t-extra24"] == nil)
        #expect(store.stopReason == .budget)
    }

    @Test func aLateResponseFromAnOldSessionDoesNotSlowTheNewOne() async throws {
        let clock = VirtualClock(today)
        let gate = GateTransport()
        let paced = PacedTransport(base: gate, clock: clock)
        let url = try #require(URL(string: "https://example.com/a"))
        let old = Task { try? await paced.get(url, headers: [:]) }
        while !(await gate.hasEntered) { await Task.yield() }
        await paced.beginSession()
        await gate.release()
        _ = await old.value
        // Le 503 de l'ancienne session n'a posé ni recul ni échec sur la nouvelle.
        _ = try await paced.get(url, headers: [:])
        #expect(await clock.sleeps.isEmpty)
        #expect(await paced.sent == 1)
        #expect(await paced.stopReason == nil)
    }

    @Test func aSecondCrawlWhileOneRunsReturnsAtOnce() async throws {
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: VirtualClock(today))
        let first = Task { @MainActor in await store.crawl { context(follows: kcFollowed()) } }
        let second = Task { @MainActor in await store.crawl { context(follows: kcFollowed()) } }
        let ends = [await first.value, await second.value]
        #expect(ends.contains(.done))
        #expect(ends.contains(.cancelled))
        #expect(!store.progress.running)
        // Chaque game lue une seule fois : m1-g1 = 2 requêtes de palier A + 3 de palier B.
        #expect(gameIds(await world.requests).filter { $0 == "m1-g1" }.count == 5)
    }

    @Test func aTournamentReadWhileActiveIsReadOnceMoreAfterItEnds() async throws {
        let root = TemporaryFiles.directory()
        let early = try #require(LoLDate.parse("2026-09-10T12:00:00Z"))
        let store = makeStore(FakeLoLWorld(lec: lecMatches), clock: VirtualClock(early), root: root)
        await store.crawl { context(follows: kcFollowed()) }
        let read = try #require(store.lastFetch(SeasonStore.completedKey("t-lec")))
        #expect(SeasonPlanning.day(read) == "2026-09-10")
        func lecListReads(_ requests: [URL]) -> [String] {
            requests.filter { $0.query?.contains("tournamentId=t-lec") == true }
                .map { $0.path.split(separator: "/").last.map(String.init) ?? "" }.sorted()
        }
        // Reprise le 15/10 : le split est fini, ses résultats et son classement finaux sont relus UNE fois…
        let second = FakeLoLWorld(lec: lecMatches)
        let resumed = makeStore(second, clock: VirtualClock(today), root: root)
        await resumed.crawl { context(follows: kcFollowed()) }
        #expect(lecListReads(await second.requests) == ["getCompletedEvents", "getStandings"])
        // … et plus jamais.
        let third = FakeLoLWorld(lec: lecMatches)
        let again = makeStore(third, clock: VirtualClock(today.addingTimeInterval(3_600)), root: root)
        await again.crawl { context(follows: kcFollowed()) }
        #expect(lecListReads(await third.requests).isEmpty)
    }

    @Test func rereadHelperOnlyAsksForACopyReadWhileActive() throws {
        let during = try #require(LoLDate.parse("2026-09-10T12:00:00Z"))
        let grace = try #require(LoLDate.parse("2026-09-22T23:00:00Z"))
        let after = try #require(LoLDate.parse("2026-09-23T00:30:00Z"))
        #expect(SeasonPlanning.plusDays("2026-09-30", 2) == "2026-10-02")
        #expect(SeasonPlanning.readWhileActive(lastFetch: nil, endDate: "2026-09-20"))
        #expect(SeasonPlanning.readWhileActive(lastFetch: during, endDate: "2026-09-20"))
        #expect(SeasonPlanning.readWhileActive(lastFetch: grace, endDate: "2026-09-20"))
        #expect(!SeasonPlanning.readWhileActive(lastFetch: after, endDate: "2026-09-20"))
        #expect(!SeasonPlanning.readWhileActive(lastFetch: during, endDate: ""))
    }

    @Test func theJoinCanBeGivenRightAfterTheDiskIsRead() async throws {
        let root = TemporaryFiles.directory()
        let first = makeStore(FakeLoLWorld(lec: lecMatches), clock: VirtualClock(today), root: root)
        await first.crawl { context(follows: kcFollowed()) }
        let resumed = makeStore(FakeLoLWorld(lec: lecMatches), clock: VirtualClock(today), root: root)
        await resumed.loadFromDisk()
        // Sans ligues, la jointure ne connaît pas le slug : il vient avec `rejoin(catalog:leagues:)`.
        #expect(resumed.matches.count == 4)
        #expect(resumed.matches.allSatisfy { $0.leagueSlug.isEmpty })
        resumed.rejoin(catalog: [kcTeam], leagues: leagues)
        #expect(resumed.matches.allSatisfy { $0.leagueSlug == "lec" })
    }

    @Test func theNewestGameIsNeverEvictedWhenTheDiskIsFull() throws {
        let store = SeasonStore(preview: SeasonPreview())
        for index in 0..<CrawlPlanner.diskLimit {
            store.record(try sampleGame(id: "old-\(index)", startedAt: 1_000_000 + Double(index)).0, followedTeamIds: [])
        }
        // Une game plus ancienne que toutes les autres, écrite à l'instant : la plus ancienne n'est pas elle.
        let late = try sampleGame(id: "late", startedAt: 10).0
        store.record(late, followedTeamIds: [])
        #expect(store.games["late"] != nil)
    }

    @Test func unreadableFilesAreIgnoredAndANewerSchemaGameIsNeverOverwritten() async throws {
        let root = TemporaryFiles.directory()
        let cache = DiskCache(root: root)
        cache.write(Data("pas du json".utf8), to: "season/games/broken.json")
        cache.write(Data("{".utf8), to: "season/completed/t-x.json")
        cache.write(Data("[]".utf8), to: "season/standings/t-x.json")
        cache.write(Data("".utf8), to: "season/tournaments/l.json")
        cache.write(Data("pas du json".utf8), to: "season/crawl.json")
        let newer = try sampleGame(id: "future", version: GameSummary.schemaVersion + 1)
        cache.write(newer.1, to: SeasonDisk.gamePath("future"))
        let known = try sampleGame(id: "known")
        cache.write(known.1, to: SeasonDisk.gamePath("known"))

        let store = makeStore(FakeLoLWorld(lec: []), clock: VirtualClock(today), root: root)
        await store.loadFromDisk()
        #expect(store.isLoaded)
        #expect(Set(store.games.keys) == ["known"])
        #expect(store.matches.isEmpty)

        // La game du futur relue par la collecte reste en mémoire mais son fichier n'est pas réécrit.
        let reread = try sampleGame(id: "future")
        store.record(reread.0, followedTeamIds: [])
        #expect(store.games["future"] != nil)
        let stored = try #require(cache.data(SeasonDisk.gamePath("future")))
        #expect(stored == newer.1)
    }

    @Test func aMaskedMatchIsNeverRequestedUntilItIsRevealed() async throws {
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: VirtualClock(today))
        // KC en anti-spoiler : tous ses matchs masqués sauf m2, révélé.
        await store.crawl { context(follows: kcFollowed(spoilerFree: true), revealed: ["m2"]) }
        let read = Set(gameIds(await world.requests))
        #expect(read == ["m2-g1", "m2-g2", "m2-g3"])
        #expect(!(await world.requests).contains { $0.absoluteString.contains("m1-") || $0.absoluteString.contains("m3-") })
        // Révéler m3 le rend éligible à la passe suivante.
        await store.crawl { context(follows: kcFollowed(spoilerFree: true), revealed: ["m2", "m3"]) }
        #expect(Set(gameIds(await world.requests)).isSuperset(of: ["m3-g1", "m3-g2"]))
        #expect(!Set(gameIds(await world.requests)).contains("m1-g1"))
    }

    @Test func theDiskIsTheStateAResumedCrawlSkipsWhatIsKnown() async throws {
        let root = TemporaryFiles.directory()
        let first = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(first, clock: VirtualClock(today), root: root)
        await store.crawl { context(follows: kcFollowed()) }
        // Relance de l'appli : un nouveau store, le même dossier ; plus aucune requête de game, ni de tournoi terminé.
        let second = FakeLoLWorld(lec: lecMatches)
        let resumed = makeStore(second, clock: VirtualClock(today.addingTimeInterval(3_600)), root: root)
        await resumed.loadFromDisk()
        #expect(resumed.games.count == 7)
        #expect(resumed.matches.count == 4)
        let end = await resumed.crawl { context(follows: kcFollowed()) }
        #expect(end == .done)
        let again = await second.requests
        #expect(gameIds(again).isEmpty)
        // LEC Split 3 est terminé : ses résultats ne sont jamais relus ; seuls les tournois du Mondial (en cours, lus il y a
        // plus de 30 min) le sont.
        #expect(!again.contains { $0.query?.contains("tournamentId=t-lec") == true })
    }

    @Test func statsDisabledGamesAreRecordedAndNeverAskedAgain() async throws {
        let world = FakeLoLWorld(lec: [lecMatches[0]], disabled: ["m1-g2"])
        let store = makeStore(world, clock: VirtualClock(today))
        await store.crawl { context(follows: kcFollowed()) }
        #expect(store.failures["m1-g2"]?.reason == .statsDisabled)
        #expect(store.games["m1-g1"] != nil)
        let before = gameIds(await world.requests).count
        await store.crawl { context(follows: kcFollowed()) }
        #expect(gameIds(await world.requests).count == before)
    }

    @Test func serverErrorsBackOffThenStopTheSessionAfterFiveInARow() async throws {
        let clock = VirtualClock(today)
        let world = FakeLoLWorld(lec: [lecMatches[0]], failingWindows: 5)
        let store = makeStore(world, clock: clock)
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .failures)
        // Après chaque 503 : 4, 8, 16 puis 32 s d'attente avant la requête suivante.
        let sleeps = await clock.sleeps
        #expect(sleeps.suffix(4) == [4, 8, 16, 32])
        #expect(store.games.isEmpty)
        #expect(store.failures.isEmpty) // une panne n'est pas un échec de game
        // Après l'arrêt pour échecs, les écrans n'envoient rien et le store dit pourquoi.
        #expect(store.stopReason == .failures)
        let before = await world.requests.count
        await store.loadStandings(tournamentId: "t-extra")
        #expect(await world.requests.count == before)
    }

    @Test func planningHelpers() {
        #expect(SeasonPlanning.day(today) == "2026-10-15")
        #expect(SeasonPlanning.year(today) == 2026)
        #expect(SeasonPlanning.at15(LoLDate.parse("2026-09-06T15:17:23.939Z")!) == LoLDate.parse("2026-09-06T15:32:20Z")!)
        let refs = ["l": [
            TournamentRef(id: "s3", slug: "lec_split_3_2026", startDate: "2026-07-23", endDate: "2026-09-20", leagueId: "l"),
            TournamentRef(id: "late", slug: "lec_finals_2026", startDate: "2026-12-01", endDate: "2026-12-10", leagueId: "l"),
            TournamentRef(id: "s1", slug: "lec_split_1_2026", startDate: "2026-01-16", endDate: "2026-03-01", leagueId: "l"),
            TournamentRef(id: "old", slug: "lec_summer_2025", startDate: "2025-08-02", endDate: "2025-09-29", leagueId: "l"),
        ]]
        // Saison 2026, déjà commencée (le tournoi de décembre n'a rien à lire), du plus récent au plus ancien.
        #expect(SeasonPlanning.startedTournaments(refs, leagueIds: ["l"], now: today).map(\.id) == ["s3", "s1"])
        // Entre deux splits : le dernier commencé compte comme « en cours ».
        #expect(SeasonPlanning.currentTournamentIds(refs, leagueIds: ["l"], now: today) == ["s3"])
        // La ligue d'attache d'une équipe ouverte (non suivie) est énumérée.
        let opened = SeasonContext(follows: FollowList(), leagues: leagues, catalog: [kcTeam], revealed: [],
                                   openedTeamId: "kc", now: today)
        #expect(SeasonPlanning.leagueIds(opened) == [worldsId, lecId])
    }

    @Test func tournamentLabels() {
        func label(_ slug: String) -> String {
            SeasonLabels.tournament(TournamentRef(id: "x", slug: slug, startDate: "", endDate: "", leagueId: ""))
        }
        #expect(label("lec_split_3_2026") == "LEC Split 3")
        #expect(label("worlds_2026") == "Mondial")
        #expect(label("first_stand_2026") == "First Stand")
        #expect(label("lck_split_2_playoffs_2026") == "LCK Split 2 Play-offs")
        #expect(SeasonLabels.season(year: "2026") == "Saison 2026")
    }

    @Test func samplesAreConsistentWithTheAppSampleData() {
        let preview = SeasonSamples.standard
        // Chaque game jouée d'exemple existe, et les ids de games de KC 1 – 3 G2 sont ceux de `SampleData`.
        let ids = Set(preview.games.map(\.gameId))
        #expect(preview.matches.allSatisfy { $0.playedGameIds.allSatisfy(ids.contains) })
        #expect(preview.matches.first { $0.id == SampleData.kcG2MatchId }?.playedGameIds
                == ["g1-kc-g2", "g2-kc-g2", "g3-kc-g2", "g4-kc-g2"])
        // T1 est en anti-spoiler dans les aperçus : ses matchs d'exemple sont masqués.
        let masked = SeasonMasking.maskedMatchIds(preview.matches, follows: SampleData.follows, revealed: [])
        #expect(masked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
        // Valeur attendue (déterministe) : 1 740 + 137 × graine (601 mod 7 = 6 pour « g1-kc-g2 »).
        #expect(SeasonSamples.games.first { $0.gameId == "g1-kc-g2" }?.durationSeconds == 2_562)
    }
}
