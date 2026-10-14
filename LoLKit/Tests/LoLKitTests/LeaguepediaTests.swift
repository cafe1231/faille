import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli interroge Leaguepedia et rapproche les games avec la seule API publique.
import LoLKit

// Fixture `leaguepedia_scoreboard.json` : reconstruite le 14/10/2026 à partir de valeurs réelles, sans aucune requête
// (le wiki limite les requêtes depuis ce poste : « ratelimited »), donc sans empreinte sha256. Format d'une réponse Cargo
// `ScoreboardPlayers`, 13 lignes :
// - la game 1 de la finale LCS (TLAW – LYON, 04/10/2026, `DateTime UTC` 20:18:00), 10 lignes : champions et sorts d'après
//   les attentes du plan (capturées par le rédacteur sur le wiki) ; `Link` = pseudos de `window_ingame` sans l'équipe ;
// - un leurre de 3 lignes : la game KC – MKOI du 19/09/2026 (17:17:00), telle que le wiki l'a renvoyée le 14/10/2026
//   (capturée par le contrôleur : Busio/Karma, Caliste/Ezreal, kyeahoo/LeBlanc). Son `GameId` (« LEC/2026 Season/Summer
//   Playoffs_Round 2_1_1 ») est illustratif.
// `leaguepedia_ratelimited.json` est une vraie réponse du wiki, du 14/10/2026.

/// Sorts d'invocateur des games terminées (spec fonctionnalités §3), sans réseau : tout passe par `FakeTransport`, qui rend
/// la réponse enregistrée quelle que soit la requête. `around` = début de la game 1 de la finale LCS (TLAW – LYON,
/// 04/10/2026 20:18:26 UTC).
@Suite struct LeaguepediaTests {
    /// Début de la game 1 de la finale LCS : première frame de `window_pregame`.
    private static let lcsStart = date("2026-10-04T20:18:26.892Z")
    private static let lcsGame = "LCS/2026 Season/Summer Playoffs_Finals_1_1"
    private static let decoyGame = "LEC/2026 Season/Summer Playoffs_Round 2_1_1"

    /// Les 10 champions de la game, tels que le flux les donne (`window_ingame`, ids Data Dragon).
    private func lcsChampions() throws -> [String] {
        let window = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data("window_ingame"))
        let metadata = window.gameMetadata.blueTeamMetadata.participantMetadata
            + window.gameMetadata.redTeamMetadata.participantMetadata
        return metadata.compactMap(\.championId)
    }

    private func rows() async throws -> [ScoreboardRow] {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_scoreboard")
        return try await LeaguepediaClient(transport: fake).scoreboard(around: Self.lcsStart)
    }

    @Test func queriesTheScoreboardAroundTheGameStart() async throws {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_scoreboard")
        let rows = try await LeaguepediaClient(transport: fake).scoreboard(around: Self.lcsStart)

        let request = try #require(await fake.requests.first)
        #expect(request.url.host == "lol.fandom.com")
        #expect(request.url.path == "/api.php")
        #expect(queryValue(request.url, "action") == "cargoquery")
        #expect(queryValue(request.url, "format") == "json")
        #expect(queryValue(request.url, "tables") == "ScoreboardPlayers")
        #expect(queryValue(request.url, "fields") == "GameId,Link,Champion,SummonerSpells,DateTime_UTC")
        #expect(queryValue(request.url, "where")
                == "DateTime_UTC >= '2026-10-04 17:18:26' AND DateTime_UTC <= '2026-10-04 23:18:26'")
        #expect(queryValue(request.url, "limit") == "500")
        #expect(request.headers["User-Agent"] == "Faille (usage personnel)")
        #expect(request.headers["x-api-key"] == nil)

        #expect(rows.count == 13)
        #expect(rows.first == ScoreboardRow(gameId: Self.lcsGame, link: "Berserker", champion: "Yunara",
                                            summonerSpells: ["Exhaust", "Flash"], dateTime: date("2026-10-04T20:18:00Z")))
        #expect(rows.filter { $0.gameId == Self.lcsGame }.count == 10)
        #expect(rows.last == ScoreboardRow(gameId: Self.decoyGame, link: "kyeahoo", champion: "LeBlanc",
                                           summonerSpells: ["Teleport", "Flash"], dateTime: date("2026-09-19T17:17:00Z")))
        #expect(rows.filter { $0.gameId == Self.decoyGame }.count == 3)
    }

    @Test func summonerSpellsOfTheLCSFinalGameOne() async throws {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_scoreboard")
        let spells = try await LeaguepediaClient(transport: fake)
            .summonerSpells(champions: try lcsChampions(), around: Self.lcsStart)
        // « Renata Glasc », « K'Sante », « Lee Sin » du wiki retrouvent « Renata », « KSante », « LeeSin » du flux.
        #expect(spells == [
            "Ambessa": ["SummonerTeleport", "SummonerFlash"],
            "LeeSin": ["SummonerFlash", "SummonerSmite"],
            "Orianna": ["SummonerTeleport", "SummonerFlash"],
            "Kalista": ["SummonerFlash", "SummonerBarrier"],
            "Renata": ["SummonerFlash", "SummonerHeal"],
            "KSante": ["SummonerFlash", "SummonerTeleport"],
            "Trundle": ["SummonerSmite", "SummonerFlash"],
            "Syndra": ["SummonerTeleport", "SummonerFlash"],
            "Yunara": ["SummonerExhaust", "SummonerFlash"],
            "Lulu": ["SummonerHeal", "SummonerFlash"],
        ])
    }

    @Test func theDecoyGameHasItsOwnDraftAndTime() async throws {
        let rows = try await rows()
        let decoyStart = date("2026-09-19T17:17:30Z")
        // KC – MKOI : « LeBlanc » du wiki retrouve « Leblanc » du flux (id Data Dragon).
        #expect(SpellMatcher.match(champions: ["Karma", "Ezreal", "Leblanc"], around: decoyStart, rows: rows) == [
            "Karma": ["SummonerHeal", "SummonerFlash"],
            "Ezreal": ["SummonerFlash", "SummonerExhaust"],
            "Leblanc": ["SummonerTeleport", "SummonerFlash"],
        ])
        // Le même draft pendant la finale LCS (quinze jours plus tard), ou la finale LCS à l'heure du leurre : rien.
        #expect(SpellMatcher.match(champions: ["Karma", "Ezreal", "Leblanc"], around: Self.lcsStart, rows: rows) == nil)
        #expect(SpellMatcher.match(champions: try lcsChampions(), around: decoyStart, rows: rows) == nil)
        // Le leurre ne perturbe pas la finale LCS : ses 10 champions, pas ceux du leurre.
        #expect(SpellMatcher.match(champions: try lcsChampions(), around: Self.lcsStart, rows: rows)?.count == 10)
    }

    @Test func noMatchOutsideThreeHoursOrWithOtherChampions() async throws {
        let rows = try await rows()
        let champions = try lcsChampions()
        // `DateTime UTC` de la game : 20:18:00 ; ± 3 h comprises.
        #expect(SpellMatcher.match(champions: champions, around: date("2026-10-04T23:18:00Z"), rows: rows) != nil)
        #expect(SpellMatcher.match(champions: champions, around: date("2026-10-04T23:18:01Z"), rows: rows) == nil)
        #expect(SpellMatcher.match(champions: champions, around: date("2026-10-04T17:18:00Z"), rows: rows) != nil)
        // Un champion différent (Ezreal au lieu de Kalista) : pas la même game.
        let other = champions.map { $0 == "Kalista" ? "Ezreal" : $0 }
        #expect(SpellMatcher.match(champions: other, around: Self.lcsStart, rows: rows) == nil)
        // Neuf champions seulement, ou un doublon : rien.
        #expect(SpellMatcher.match(champions: Array(champions.dropLast()), around: Self.lcsStart, rows: rows) == nil)
        #expect(SpellMatcher.match(champions: champions + ["Lulu"], around: Self.lcsStart, rows: rows) == nil)
        #expect(SpellMatcher.match(champions: champions, around: Self.lcsStart, rows: []) == nil)
    }

    @Test func closestGameWinsWhenTheSameDraftIsPlayedTwice() {
        let draft = ["A", "B"]
        let rows = ["early": "2026-10-04T18:00:00Z", "late": "2026-10-04T20:30:00Z"].flatMap { id, start in
            draft.map { ScoreboardRow(gameId: id, link: nil, champion: $0, summonerSpells: [id == "late" ? "Heal" : "Ghost"],
                                      dateTime: date(start)) }
        }
        #expect(SpellMatcher.match(champions: draft, around: date("2026-10-04T20:00:00Z"), rows: rows)
                == ["A": ["SummonerHeal"], "B": ["SummonerHeal"]])
    }

    @Test func unknownSpellNameIsIgnored() {
        let rows = [ScoreboardRow(gameId: "g", link: nil, champion: "Lulu", summonerSpells: ["Mark", "Flash"],
                                  dateTime: date("2026-10-04T20:18:00Z"))]
        #expect(SpellMatcher.match(champions: ["Lulu"], around: date("2026-10-04T20:18:26Z"), rows: rows)
                == ["Lulu": ["SummonerFlash"]])
    }

    @Test func emptyAndUnreadableResponses() async throws {
        // Le wiki n'a pas (encore) la game : réponse valide mais vide → pas de sorts, pas d'erreur.
        let empty = FakeTransport()
        try await empty.on("lol.fandom.com", body: #"{"cargoquery":[]}"#)
        #expect(try await LeaguepediaClient(transport: empty).scoreboard(around: Self.lcsStart) == [])
        #expect(try await LeaguepediaClient(transport: empty).summonerSpells(champions: ["Lulu"], around: Self.lcsStart) == nil)
        // Lignes illisibles ou incomplètes (sans champion, valeur de mauvais type) ignorées ; date illisible → nil.
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", body: """
            {"cargoquery":[{"title":{"GameId":"a"}}, 42,
            {"title":{"GameId":"a","Champion":"Lulu","SummonerSpells":"Heal,Flash","DateTime UTC":"2026-10-04 20:18:00"}},
            {"title":{"GameId":"b","Champion":"Orianna","DateTime UTC":"hier"}}]}
            """)
        #expect(try await LeaguepediaClient(transport: fake).scoreboard(around: Self.lcsStart) == [
            ScoreboardRow(gameId: "a", link: nil, champion: "Lulu", summonerSpells: ["Heal", "Flash"],
                          dateTime: date("2026-10-04T20:18:00Z")),
            ScoreboardRow(gameId: "b", link: nil, champion: "Orianna", summonerSpells: [], dateTime: nil),
        ])
    }

    @Test func rateLimitAndHTTPErrors() async throws {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_ratelimited")
        await #expect(throws: LeaguepediaError.rateLimited) {
            try await LeaguepediaClient(transport: fake).summonerSpells(champions: ["Lulu"], around: Self.lcsStart)
        }
        let down = FakeTransport()
        try await down.on("lol.fandom.com", status: 503, body: "Service Unavailable")
        await #expect(throws: LeaguepediaError.http(status: 503)) {
            try await LeaguepediaClient(transport: down).scoreboard(around: Self.lcsStart)
        }
        let other = FakeTransport()
        try await other.on("lol.fandom.com", body: #"{"error":{"code":"badquery","info":"..."}}"#)
        await #expect(throws: LeaguepediaError.api(code: "badquery")) {
            try await LeaguepediaClient(transport: other).scoreboard(around: Self.lcsStart)
        }
    }

    @Test func championNamesAreComparedLikeDataDragonIds() {
        #expect(ChampionKey.normalized("LeBlanc") == ChampionKey.normalized("Leblanc"))
        #expect(ChampionKey.normalized("Wukong") == ChampionKey.normalized("MonkeyKing"))
        #expect(ChampionKey.normalized("K'Sante") == ChampionKey.normalized("KSante"))
        #expect(ChampionKey.normalized("Lee Sin") == ChampionKey.normalized("LeeSin"))
        #expect(ChampionKey.normalized("Renata Glasc") == ChampionKey.normalized("Renata"))
        #expect(ChampionKey.normalized("Nunu & Willump") == ChampionKey.normalized("Nunu"))
        #expect(ChampionKey.normalized("Dr. Mundo") == "drmundo")
        #expect(ChampionKey.normalized("Kai'Sa") == "kaisa")
        #expect(ChampionKey.normalized("Jarvan IV") == "jarvaniv")
        #expect(ChampionKey.normalized("Lee Sin") != ChampionKey.normalized("Lee"))
    }

    @Test func summonerSpellNamesBecomeDataDragonIds() {
        #expect(SpellMatcher.dataDragonSpellId("Flash") == "SummonerFlash")
        #expect(SpellMatcher.dataDragonSpellId("Ignite") == "SummonerDot")
        #expect(SpellMatcher.dataDragonSpellId("Cleanse") == "SummonerBoost")
        #expect(SpellMatcher.dataDragonSpellId("Ghost") == "SummonerHaste")
        #expect(SpellMatcher.dataDragonSpellId(" Teleport") == "SummonerTeleport")
        #expect(SpellMatcher.dataDragonSpellId("Mark") == nil)
    }
}

/// Règle stricte envers le wiki (qui nous limite) : une game, trois essais au plus, jamais deux à moins de 10 min, 30 min
/// après un refus, plus du tout après un succès. Fonction pure : l'appli garde l'état par match dans son cache disque.
@Suite struct SpellLookupPolicyTests {
    private let start = date("2026-10-14T12:00:00Z")

    private func later(_ minutes: Double, _ seconds: Double = 0) -> Date {
        start.addingTimeInterval(minutes * 60 + seconds)
    }

    @Test func theFirstAttemptIsAllowed() {
        let policy = SpellLookupPolicy()
        #expect(policy.canAttempt(now: start))
        #expect(policy.attempts == 0)
        #expect(policy.lastAttempt == nil)
        #expect(!policy.lastWasRateLimited)
        #expect(!policy.succeeded)
    }

    @Test func theLimitsAreThreeAttemptsTenMinutesAndThirtyMinutes() {
        #expect(SpellLookupPolicy.maxAttempts == 3)
        #expect(SpellLookupPolicy.minimumGap == 600)
        #expect(SpellLookupPolicy.retryAfterRefusal == 1800)
    }

    @Test func neverAgainAfterASuccess() {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .success)
        #expect(policy.succeeded)
        #expect(policy.attempts == 1)
        #expect(policy.lastAttempt == start)
        #expect(!policy.lastWasRateLimited)
        for now in [later(0), later(10), later(30), later(24 * 60), later(30 * 24 * 60)] {
            #expect(!policy.canAttempt(now: now))
        }
        // Un résultat tardif d'un autre essai ne défait pas le succès.
        policy.record(now: later(60), outcome: .failure)
        #expect(policy.succeeded)
    }

    @Test func afterARefusalTheWikiIsLeftAloneForThirtyMinutes() {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .rateLimited)
        #expect(policy.lastWasRateLimited)
        #expect(!policy.succeeded)
        #expect(!policy.canAttempt(now: start))
        #expect(!policy.canAttempt(now: later(10)))
        #expect(!policy.canAttempt(now: later(29)))
        #expect(!policy.canAttempt(now: later(29, 59)))
        #expect(policy.canAttempt(now: later(30)))
        #expect(policy.canAttempt(now: later(31)))
    }

    @Test func evenWithoutARefusalTwoAttemptsAreTenMinutesApart() {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .failure)
        #expect(!policy.lastWasRateLimited)
        #expect(!policy.canAttempt(now: start))
        #expect(!policy.canAttempt(now: later(9, 59)))
        #expect(policy.canAttempt(now: later(10)))
    }

    @Test func atMostThreeAttemptsPerMatchRefusalsIncluded() {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .failure)
        policy.record(now: later(10), outcome: .rateLimited)
        #expect(policy.attempts == 2)
        #expect(policy.canAttempt(now: later(40)))
        policy.record(now: later(40), outcome: .failure)
        #expect(policy.attempts == 3)
        #expect(policy.lastAttempt == later(40))
        #expect(!policy.lastWasRateLimited)
        #expect(!policy.succeeded)
        for now in [later(50), later(70), later(24 * 60), later(30 * 24 * 60)] {
            #expect(!policy.canAttempt(now: now))
        }

        var refused = SpellLookupPolicy()
        for index in 0..<3 { refused.record(now: later(Double(index) * 30), outcome: .rateLimited) }
        #expect(refused.attempts == 3)
        #expect(!refused.canAttempt(now: later(24 * 60)))
    }

    @Test func aSuccessAfterTwoFailuresIsStillRecorded() {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .failure)
        policy.record(now: later(10), outcome: .rateLimited)
        policy.record(now: later(40), outcome: .success)
        #expect(policy.succeeded)
        #expect(policy.attempts == 3)
        #expect(!policy.lastWasRateLimited)
    }

    @Test func aClockGoingBackwardsDoesNotUnlockAnAttempt() {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .failure)
        #expect(!policy.canAttempt(now: later(-5)))
        #expect(!policy.canAttempt(now: later(-60)))
    }

    @Test func theStateSurvivesTheDiskCache() throws {
        var policy = SpellLookupPolicy()
        policy.record(now: start, outcome: .failure)
        policy.record(now: later(10), outcome: .rateLimited)
        let decoded = try JSONDecoder().decode(SpellLookupPolicy.self, from: JSONEncoder().encode(policy))
        #expect(decoded == policy)
        #expect(decoded.attempts == 2)
        #expect(decoded.lastAttempt == later(10))
        #expect(decoded.lastWasRateLimited)
        #expect(!decoded.canAttempt(now: later(39)))
        #expect(decoded.canAttempt(now: later(40)))

        let done = SpellLookupPolicy(attempts: 1, lastAttempt: start, lastWasRateLimited: false, succeeded: true)
        #expect(try JSONDecoder().decode(SpellLookupPolicy.self, from: JSONEncoder().encode(done)) == done)
    }

    @Test func aMissingOrUnreadableFieldFallsBackToTheNeutralValue() throws {
        // Décodage tolérant (spec §4.2) : un cache abîmé repart de zéro plutôt que de tout perdre.
        #expect(try JSONDecoder().decode(SpellLookupPolicy.self, from: Data("{}".utf8)) == SpellLookupPolicy())
        let partial = try JSONDecoder().decode(SpellLookupPolicy.self, from: Data(#"{"attempts":2,"succeeded":"oui"}"#.utf8))
        #expect(partial == SpellLookupPolicy(attempts: 2))
    }
}
