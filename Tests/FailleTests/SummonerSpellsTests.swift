import Foundation
import LoLKit
import Testing
@testable import Faille

/// Deux games d'un match terminé : champions (ids Data Dragon du flux, noms Leaguepedia) et début de chaque game.
private let games: [(id: String, start: String, champions: [(feed: String, wiki: String, spells: String)])] = [
    ("G1", "2026-10-04T18:02:00.000Z", [
        ("KSante", "K'Sante", "Flash,Teleport"), ("LeeSin", "Lee Sin", "Flash,Smite"), ("Ahri", "Ahri", "Flash,Ignite"),
        ("Kalista", "Kalista", "Flash,Heal"), ("Rakan", "Rakan", "Flash,Ignite"), ("Gnar", "Gnar", "Flash,Teleport"),
        ("Vi", "Vi", "Flash,Smite"), ("Orianna", "Orianna", "Flash,Teleport"), ("Varus", "Varus", "Flash,Cleanse"),
        ("Braum", "Braum", "Flash,Exhaust"),
    ]),
    ("G2", "2026-10-04T18:55:00.000Z", [
        ("Rumble", "Rumble", "Flash,Teleport"), ("XinZhao", "Xin Zhao", "Flash,Smite"), ("Taliyah", "Taliyah", "Flash,Ignite"),
        ("Kaisa", "Kai'Sa", "Flash,Heal"), ("Rell", "Rell", "Flash,Ignite"), ("Renekton", "Renekton", "Flash,Teleport"),
        ("Sejuani", "Sejuani", "Flash,Smite"), ("Azir", "Azir", "Flash,Teleport"), ("Ezreal", "Ezreal", "Flash,Heal"),
        ("Nautilus", "Nautilus", "Flash,Ignite"),
    ]),
]

/// Fenêtre de début d'une game (forme réelle de `window` : 5 joueurs par équipe, une frame).
private func openingJSON(_ game: (id: String, start: String, champions: [(feed: String, wiki: String, spells: String)])) -> String {
    func team(_ id: String, _ offset: Int) -> String {
        let players = (0..<5).map { index in
            #"{"participantId":\#(offset + index),"summonerName":"P\#(offset + index)","championId":"\#(game.champions[offset + index - 1].feed)","role":"top"}"#
        }
        return #"{"esportsTeamId":"\#(id)","participantMetadata":[\#(players.joined(separator: ","))]}"#
    }
    let frameTeam = #"{"totalGold":2500,"inhibitors":0,"towers":0,"barons":0,"totalKills":0,"dragons":[],"participants":[]}"#
    return #"{"esportsGameId":"\#(game.id)","esportsMatchId":"M1","gameMetadata":{"patchVersion":"16.18.819.1060","blueTeamMetadata":\#(team("kc", 1)),"redTeamMetadata":\#(team("g2", 6))},"frames":[{"rfc460Timestamp":"\#(game.start)","gameState":"in_game","blueTeam":\#(frameTeam),"redTeam":\#(frameTeam)}]}"#
}

/// Réponse Cargo de Leaguepedia pour les games données (forme réelle de `ScoreboardPlayers`).
private func scoreboardJSON(_ ids: [String]) -> String {
    let rows = games.filter { ids.contains($0.id) }.flatMap { game in
        game.champions.map { champion in
            let date = game.start.replacingOccurrences(of: "T", with: " ").prefix(19)
            return #"{"title":{"GameId":"Worlds_\#(game.id)","Link":"Joueur","Champion":"\#(champion.wiki)","SummonerSpells":"\#(champion.spells)","DateTime UTC":"\#(date)"}}"#
        }
    }
    return #"{"cargoquery":[\#(rows.joined(separator: ","))]}"#
}

/// Faux réseau : débuts des games G1 et G2, et Leaguepedia qui répond `wiki` (games trouvées, ou refus). `feedStatus` :
/// état HTTP du flux pour une game (404 : stats coupées par Riot ; 204 : rien dans le flux) au lieu de son début.
private func spellsTransport(feedStatus: [String: Int] = [:], wiki: @escaping @Sendable () -> String) -> ScriptedTransport {
    ScriptedTransport(extra: { url in
        if url.host() == "lol.fandom.com" {
            return HTTPResponse(status: 200, body: Data(wiki().utf8))
        }
        for game in games where url.path.hasSuffix("/window/\(game.id)") {
            if let status = feedStatus[game.id] {
                return HTTPResponse(status: status, body: Data())
            }
            return HTTPResponse(status: 200, body: Data(openingJSON(game).utf8))
        }
        return nil
    })
}

/// Faux réseau dont la première requête du flux reste suspendue jusqu'à `release()` ; rendue, elle échoue comme une
/// requête annulée si sa tâche l'est (le vrai réseau ne rend la main qu'après coup). Tout le reste passe au faux réseau de
/// base.
private actor HeldFirstFeedTransport: HTTPTransport {
    private(set) var requests: [URL] = []
    private let base: ScriptedTransport
    private var holdsFirst = true
    private var released = false
    private var held: CheckedContinuation<Void, Never>?

    init(base: ScriptedTransport) {
        self.base = base
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        if holdsFirst, url.path.contains("/window/") {
            holdsFirst = false
            if !released {
                await withCheckedContinuation { held = $0 }
            }
            try Task.checkCancellation()
        }
        return try await base.get(url, headers: headers)
    }

    func release() {
        released = true
        held?.resume()
        held = nil
    }
}

/// Faux réseau dont la première requête Leaguepedia reste suspendue jusqu'à `release()`, sans tenir compte de l'annulation
/// de la tâche qui l'attend. Le reste passe au faux réseau de base.
private actor HeldFirstWikiTransport: HTTPTransport {
    private(set) var requests: [URL] = []
    private let base: ScriptedTransport
    private var holdsFirst = true
    private var released = false
    private var held: CheckedContinuation<Void, Never>?

    init(base: ScriptedTransport) {
        self.base = base
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        if holdsFirst, url.host() == "lol.fandom.com" {
            holdsFirst = false
            if !released {
                await withCheckedContinuation { held = $0 }
            }
        }
        return try await base.get(url, headers: headers)
    }

    func release() {
        released = true
        held?.resume()
        held = nil
    }
}

/// Sorts d'invocateur des games terminées (spec fonctionnalités §3) : une requête Leaguepedia par match, jamais avant
/// 30 min après la fin, une heure au moins entre deux essais, gardés sur disque.
@MainActor
@Suite(.serialized)
struct SummonerSpellsTests {
    private static let end = LoLDate.parse("2026-10-04T19:30:00.000Z")!

    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-spells-\(UUID().uuidString)", isDirectory: true))
    }

    private static func wikiRequests(_ transport: ScriptedTransport) async -> Int {
        await transport.requests.filter { $0.host() == "lol.fandom.com" }.count
    }

    @Test func scheduleWaitsForTheEndAndSpacesAttempts() {
        let start = Self.end.addingTimeInterval(-1_800)
        #expect(SpellSchedule.earliestAttempt(matchEnd: Self.end, lastGameStart: start) == Self.end.addingTimeInterval(1_800))
        // Fin inconnue : début de la dernière game + 1 h 15 (fin estimée) + 30 min.
        #expect(SpellSchedule.earliestAttempt(matchEnd: nil, lastGameStart: start) == start.addingTimeInterval(6_300))
        let earliest = Self.end.addingTimeInterval(1_800)
        var policy = SpellLookupPolicy()
        #expect(!SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(-60)))
        #expect(SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest))
        policy.record(now: earliest, outcome: .failure)
        // La règle de LoLKit permettrait un essai 10 min plus tard ; l'appli attend une heure.
        #expect(!SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(30 * 60)))
        #expect(SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(3_600)))
        policy.record(now: earliest.addingTimeInterval(3_600), outcome: .success)
        #expect(!SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(9 * 3_600)))
        #expect(SpellSchedule.center(of: [Self.end, Self.end.addingTimeInterval(7_200)]) == Self.end.addingTimeInterval(3_600))
        #expect(SpellSchedule.center(of: []) == nil)
    }

    @Test func oneWikiRequestCoversTheWholeMatchAndIsKept() async {
        let cache = Self.cache()
        let transport = spellsTransport { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: cache)
        let now = Self.end.addingTimeInterval(3_600)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now)
        #expect(await Self.wikiRequests(transport) == 1)
        #expect(store.spells(gameId: "G1", championId: "LeeSin") == ["SummonerFlash", "SummonerSmite"])
        #expect(store.spells(gameId: "G2", championId: "Kaisa") == ["SummonerFlash", "SummonerHeal"])

        // Trouvés : plus jamais de requête, ni ici ni au prochain lancement.
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now.addingTimeInterval(7_200))
        let offline = ScriptedTransport(mode: .failing)
        let reopened = SummonerSpellsStore(transport: offline, cache: cache)
        await reopened.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now.addingTimeInterval(9_000))
        #expect(reopened.spells(gameId: "G1", championId: "Vi") == ["SummonerFlash", "SummonerSmite"])
        #expect(await offline.requests.isEmpty)
        #expect(await Self.wikiRequests(transport) == 1)
    }

    /// L'écran relance la recherche (la fin du match devient connue) pendant que l'ancienne, annulée, attend encore sa
    /// requête : la nouvelle attend la sortie de l'ancienne, puis fait son travail — elle n'est pas perdue — et le wiki
    /// n'est interrogé qu'une fois.
    @Test func aSecondLookUpWaitsForTheCancelledOneInsteadOfBeingLost() async throws {
        let transport = HeldFirstFeedTransport(base: spellsTransport { scoreboardJSON(["G1", "G2"]) })
        let store = SummonerSpellsStore(transport: transport, cache: Self.cache())
        let now = Self.end.addingTimeInterval(3_600)
        let first = Task { await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: now) }
        let deadline = ContinuousClock.now + .seconds(10)
        while await transport.requests.isEmpty {
            try #require(ContinuousClock.now < deadline, "la première recherche n'a pas demandé le flux")
            try await Task.sleep(for: .milliseconds(10))
        }
        first.cancel()
        let second = Task { await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now) }
        // L'ancienne n'est pas sortie : la nouvelle attend, sans rien demander.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await transport.requests.count == 1)
        #expect(store.spells.isEmpty)

        await transport.release()
        await first.value
        await second.value
        #expect(store.spells(gameId: "G1", championId: "LeeSin") == ["SummonerFlash", "SummonerSmite"])
        #expect(store.spells(gameId: "G2", championId: "Kaisa") == ["SummonerFlash", "SummonerHeal"])
        let wiki = await transport.requests.filter { $0.host() == "lol.fandom.com" }.count
        #expect(wiki == 1)
    }

    /// L'écran annule sa recherche (la fin du match devient connue) alors que la requête au wiki est partie : elle va à son
    /// terme, ses sorts sont publiés et l'essai est noté pour ce qu'il est — la relance ne demande rien de plus.
    @Test func aCancelledLookUpStillRecordsItsRealWikiOutcome() async throws {
        let cache = Self.cache()
        let transport = HeldFirstWikiTransport(base: spellsTransport { scoreboardJSON(["G1", "G2"]) })
        let store = SummonerSpellsStore(transport: transport, cache: cache)
        let now = Self.end.addingTimeInterval(3_600)
        let first = Task { await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: now) }
        let deadline = ContinuousClock.now + .seconds(10)
        while await transport.requests.filter({ $0.host() == "lol.fandom.com" }).isEmpty {
            try #require(ContinuousClock.now < deadline, "la requête au wiki n'est pas partie")
            try await Task.sleep(for: .milliseconds(10))
        }
        first.cancel()
        let second = Task { await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now) }
        try await Task.sleep(for: .milliseconds(100))
        await transport.release()
        await first.value
        await second.value

        #expect(store.spells(gameId: "G1", championId: "LeeSin") == ["SummonerFlash", "SummonerSmite"])
        #expect(store.spells(gameId: "G2", championId: "Kaisa") == ["SummonerFlash", "SummonerHeal"])
        let wiki = await transport.requests.filter { $0.host() == "lol.fandom.com" }.count
        #expect(wiki == 1)
        let record = try #require(cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1")))
        #expect(record.policy.attempts == 1)
        #expect(record.policy.succeeded)
    }

    /// Trop tôt (moins de 30 min après la fin connue) : aucune requête, même au flux.
    @Test func tooEarlyAsksNothing() async {
        let transport = spellsTransport { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: Self.cache())
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: Self.end.addingTimeInterval(600))
        #expect(await transport.requests.isEmpty)
        #expect(store.spells.isEmpty)
    }

    /// Fin inconnue : les débuts des games sont lus (flux), mais le wiki attend la fin estimée (début de la dernière game
    /// + 1 h 15) + 30 min, soit 1 h 45 après ce début.
    @Test func unknownEndWaitsForTheEstimate() async {
        let transport = spellsTransport { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: Self.cache())
        let lastStart = LoLDate.parse("2026-10-04T18:55:00.000Z")!
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: lastStart.addingTimeInterval(3_600))
        #expect(await transport.requests.count == 2)
        #expect(await Self.wikiRequests(transport) == 0)
        // 1 h 30 : l'ancienne estimation (1 h) aurait déjà interrogé le wiki, pas celle de 1 h 15.
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: lastStart.addingTimeInterval(5_400))
        #expect(await Self.wikiRequests(transport) == 0)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: lastStart.addingTimeInterval(6_300))
        #expect(await Self.wikiRequests(transport) == 1)
        #expect(await transport.requests.count == 3) // débuts déjà connus
    }

    /// Refus du wiki : noté ; pas de nouvel essai avant une heure ; une game absente du wiki garde l'autre.
    @Test func refusalAndMissingGameAreAttemptsWithoutLoops() async {
        let cache = Self.cache()
        let refusing = spellsTransport { #"{"error":{"code":"ratelimited","info":"Rate limit"}}"# }
        let store = SummonerSpellsStore(transport: refusing, cache: cache)
        let first = Self.end.addingTimeInterval(1_800)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: first)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: first.addingTimeInterval(2_400))
        #expect(await Self.wikiRequests(refusing) == 1)
        #expect(cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1"))?.policy.lastWasRateLimited == true)

        let partial = spellsTransport { scoreboardJSON(["G1"]) }
        let later = SummonerSpellsStore(transport: partial, cache: cache)
        await later.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: first.addingTimeInterval(3_600))
        #expect(await Self.wikiRequests(partial) == 1)
        #expect(later.spells(gameId: "G1", championId: "Ahri") == ["SummonerFlash", "SummonerDot"])
        #expect(later.spells(gameId: "G2", championId: "Azir") == nil)
        let record = cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1"))
        #expect(record?.policy.attempts == 2)
        #expect(record?.policy.succeeded == false)
    }

    /// Une game dont Riot n'a pas les stats (404 sur le flux, ou flux vide) est laissée de côté : une seule requête au
    /// wiki pour les autres, le succès ne l'attend pas, et son début n'est plus jamais redemandé.
    @Test(arguments: [404, 204])
    func aGameWithoutFeedStatsIsSkippedAndNeverAskedAgain(status: Int) async {
        let cache = Self.cache()
        let transport = spellsTransport(feedStatus: ["G2": status]) { scoreboardJSON(["G1"]) }
        let store = SummonerSpellsStore(transport: transport, cache: cache)
        let now = Self.end.addingTimeInterval(3_600)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now)
        #expect(await Self.wikiRequests(transport) == 1)
        #expect(store.spells(gameId: "G1", championId: "Ahri") == ["SummonerFlash", "SummonerDot"])
        #expect(store.spells(gameId: "G2", championId: "Azir") == nil)
        let record = cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1"))
        #expect(record?.skipped == ["G2"])
        #expect(record?.policy.attempts == 1)
        #expect(record?.policy.succeeded == true)

        // Ni cette ouverture, ni la suivante (même après un nouveau lancement) ne redemandent quoi que ce soit.
        let requestsSoFar = await transport.requests.count
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now.addingTimeInterval(7_200))
        #expect(await transport.requests.count == requestsSoFar)
        let offline = ScriptedTransport(mode: .failing)
        let reopened = SummonerSpellsStore(transport: offline, cache: cache)
        await reopened.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now.addingTimeInterval(9_000))
        #expect(reopened.spells(gameId: "G1", championId: "Ahri") == ["SummonerFlash", "SummonerDot"])
        #expect(await offline.requests.isEmpty)
    }

    /// Aucune game n'a de stats : rien à chercher dans le wiki, aucun essai noté.
    @Test func whenNoGameHasFeedStatsTheWikiIsNeverAsked() async {
        let cache = Self.cache()
        let transport = spellsTransport(feedStatus: ["G1": 404, "G2": 404]) { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: cache)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: Self.end.addingTimeInterval(3_600))
        #expect(await Self.wikiRequests(transport) == 0)
        #expect(store.spells.isEmpty)
        let record = cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1"))
        #expect(record?.skipped == ["G1", "G2"])
        #expect(record?.policy.attempts == 0)
    }

    /// Un fichier d'une version précédente (sans `skipped`) ou en partie illisible garde ce qui se lit (spec §4.2).
    @Test func recordDecodingIsTolerant() throws {
        let old = #"{"spells":{"G1":{"Ahri":["SummonerFlash","SummonerDot"]}},"openings":{}}"#
        let decoded = try JSONDecoder().decode(SpellRecord.self, from: Data(old.utf8))
        #expect(decoded.spells["G1"]?["Ahri"] == ["SummonerFlash", "SummonerDot"])
        #expect(decoded.skipped.isEmpty)
        #expect(decoded.policy == SpellLookupPolicy())

        let damaged = #"{"skipped":3,"openings":"x","spells":{"G2":{"Azir":["SummonerFlash"]}}}"#
        let partial = try JSONDecoder().decode(SpellRecord.self, from: Data(damaged.utf8))
        #expect(partial.spells["G2"]?["Azir"] == ["SummonerFlash"])
        #expect(partial.skipped.isEmpty)
        #expect(partial.openings.isEmpty)

        // Aller-retour complet.
        var record = SpellRecord()
        record.skipped = ["G3"]
        record.spells = ["G1": ["Ahri": ["SummonerFlash"]]]
        record.policy.record(now: Date(timeIntervalSinceReferenceDate: 1_000), outcome: .rateLimited)
        let again = try JSONDecoder().decode(SpellRecord.self, from: JSONEncoder().encode(record))
        #expect(again == record)
    }

    @Test func previewStoreNeverAsks() async {
        let store = SummonerSpellsStore(preview: ["G1": ["LeeSin": ["SummonerFlash", "SummonerSmite"]]])
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: Self.end.addingTimeInterval(86_400))
        #expect(store.spells(gameId: "G1", championId: "LeeSin") == ["SummonerFlash", "SummonerSmite"])
        #expect(store.spells(gameId: "G2", championId: "Azir") == nil)
    }
}
