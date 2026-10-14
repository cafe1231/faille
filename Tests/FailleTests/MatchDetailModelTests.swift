import Foundation
import LoLKit
import Testing
@testable import Faille

/// Boucle de l'écran Détail : quelles requêtes `window` partent selon l'état du match (R-I2) et jamais pour un match
/// masqué (anti-spoiler, spec §8).
@MainActor
@Suite(.serialized)
struct MatchDetailModelTests {
    private let matchId = "M1"

    /// `getEventDetails` d'un Bo3 KC – C9 : game 1 jouée (KC 1 – 0), game 2 dans l'état demandé, game 3 inutile.
    private func detailsJSON(game2: String, stats: String) -> String {
        let sides = #"[{"id":"kc","side":"blue"},{"id":"c9","side":"red"}]"#
        return """
        {"data":{"event":{"id":"M1","type":"match","league":{"id":"1","slug":"worlds","name":"Mondial","image":null},\
        "match":{"strategy":{"type":"bestOf","count":3},\
        "teams":[{"id":"kc","name":"Karmine Corp","code":"KC","image":null,"result":{"outcome":null,"gameWins":1}},\
        {"id":"c9","name":"Cloud9 Kia","code":"C9","image":null,"result":{"outcome":null,"gameWins":0}}],\
        "games":[{"number":1,"id":"g1","state":"completed","teams":\(sides)},\
        {"number":2,"id":"g2","state":"\(game2)","teams":\(sides)},\
        {"number":3,"id":"g3","state":"unneeded","teams":\(sides)}]},\
        "streams":[{"statsStatus":"\(stats)"}]}}}
        """
    }

    /// Store branché sur un faux réseau qui sert ces détails et répond 404 au flux `window` ; détails déjà chargés.
    private func makeStore(game2: String, stats: String, spoilerFree: Bool = false,
                           windowFails: Bool = false) async -> (AppStore, ScriptedTransport) {
        let json = detailsJSON(game2: game2, stats: stats)
        let transport = ScriptedTransport(extra: { url in
            url.path.hasSuffix("/getEventDetails") ? HTTPResponse(status: 200, body: Data(json.utf8)) : nil
        }, failure: { url in
            // Erreur réseau (et non 404) sur le flux `window` : le chargement échoue sans refus connu.
            windowFails && url.path.contains("/window/") ? URLError(.notConnectedToInternet) : nil
        })
        let files = TemporaryFiles.store()
        if spoilerFree {
            files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", spoilerFree: true)]),
                       to: .follows)
        }
        let store = AppStore(transport: transport, files: files)
        await store.loadDetails(matchId: matchId)
        return (store, transport)
    }

    private func windowRequests(_ transport: ScriptedTransport) async -> [URL] {
        await transport.requests.filter { $0.path.contains("/window/") }
    }

    // MARK: Requêtes du flux

    /// R-I2 : une game en cours est interrogée même quand Riot n'en fournit pas les stats (le chrono en dépend) ; le
    /// 404 arrête ensuite les nouvelles tentatives.
    @Test func liveGameWithoutStatsStillFeedsTheClock() async {
        let (store, transport) = await makeStore(game2: "inProgress", stats: "disabled")
        #expect(store.details[matchId]?.statsDisabled == true)
        let model = MatchDetailModel(matchId: matchId)
        await model.loadSelectedGame(store: store)
        let requests = await windowRequests(transport)
        #expect(requests.contains { $0.path.hasSuffix("/window/g2") })
        #expect(store.statsUnavailable.contains("g2"))
        #expect(store.snapshots["g2"] == nil)

        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).count == requests.count)
    }

    /// Une game terminée sans stats n'est pas interrogée.
    @Test func finishedGameWithoutStatsIsNotQueried() async {
        let (store, transport) = await makeStore(game2: "completed", stats: "disabled")
        let model = MatchDetailModel(matchId: matchId)
        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).isEmpty)
    }

    /// Une game terminée avec stats : les dernières frames sont demandées (`startingTime` récent), pas le début.
    @Test func finishedGameWithStatsAsksForTheLastFrames() async {
        let (store, transport) = await makeStore(game2: "completed", stats: "enabled")
        let model = MatchDetailModel(matchId: matchId)
        await model.loadSelectedGame(store: store)
        let requests = await windowRequests(transport)
        #expect(requests.count == 1)
        #expect(requests.first?.path.hasSuffix("/window/g2") == true)
        #expect(requests.first?.query?.contains("startingTime=") == true)
    }

    /// Une game pas commencée n'est pas interrogée.
    @Test func unstartedGameIsNotQueried() async {
        let (store, transport) = await makeStore(game2: "unstarted", stats: "enabled")
        let model = MatchDetailModel(matchId: matchId)
        model.selectedGameNumber = 2
        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).isEmpty)
    }

    /// Anti-spoiler (spec §8) : aucune requête de stats tant que le match est masqué, puis la game en cours est
    /// interrogée dès que l'utilisateur le révèle.
    @Test func maskedMatchIsNeverQueriedUntilRevealed() async {
        let (store, transport) = await makeStore(game2: "inProgress", stats: "enabled", spoilerFree: true)
        let model = MatchDetailModel(matchId: matchId)
        let teams = store.details[matchId]?.match.teams ?? []
        #expect(store.isMasked(teams, matchId: matchId))
        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).isEmpty)

        store.reveal(matchId: matchId)
        #expect(store.isMasked(teams, matchId: matchId) == false)
        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).contains { $0.path.hasSuffix("/window/g2") })
    }

    // MARK: Premier chargement de la game affichée

    /// M6 : tant que la game affichée n'a pas fini son premier chargement, l'écran montre un squelette et non
    /// « indisponibles » ; elle est « chargée » une fois la réponse reçue, même refusée (404).
    @Test func aGameIsLoadedOnceItsFirstLoadIsDone() async throws {
        let (store, transport) = await makeStore(game2: "completed", stats: "enabled")
        let details = try #require(store.details[matchId])
        let model = MatchDetailModel(matchId: matchId)
        let game = try #require(model.selectedGame(in: details))
        #expect(!model.hasLoaded(game))
        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).isEmpty == false)
        #expect(model.hasLoaded(game))
        // Les autres games ne sont pas chargées pour autant.
        let other = try #require(details.match.games.first { $0.number == 1 })
        #expect(!model.hasLoaded(other))
    }

    /// Un échec réseau finit aussi le premier chargement : pas de squelette éternel ; la boucle de 10 s réessaie.
    @Test func aFailedFirstLoadStillEndsTheSkeleton() async throws {
        let (store, _) = await makeStore(game2: "completed", stats: "enabled", windowFails: true)
        let details = try #require(store.details[matchId])
        let model = MatchDetailModel(matchId: matchId)
        let game = try #require(model.selectedGame(in: details))
        await model.loadSelectedGame(store: store)
        #expect(store.snapshots[game.id] == nil)
        #expect(!store.statsUnavailable.contains(game.id))
        #expect(model.hasLoaded(game))
    }

    /// Une game sans stats annoncées (aucune requête) est elle aussi « chargée » : l'écran sait déjà quoi dire.
    @Test func aGameWithoutStatsIsLoadedWithoutAnyRequest() async throws {
        let (store, transport) = await makeStore(game2: "completed", stats: "disabled")
        let details = try #require(store.details[matchId])
        let model = MatchDetailModel(matchId: matchId)
        let game = try #require(model.selectedGame(in: details))
        await model.loadSelectedGame(store: store)
        #expect(await windowRequests(transport).isEmpty)
        #expect(model.hasLoaded(game))
    }

    /// Anti-spoiler (spec §8) : un match masqué n'est jamais chargé, donc aucune game n'est « chargée » avant la
    /// révélation ; elle l'est dès que la révélation l'a chargée.
    @Test func aMaskedMatchLoadsNothingUntilRevealed() async throws {
        let (store, _) = await makeStore(game2: "inProgress", stats: "enabled", spoilerFree: true)
        let details = try #require(store.details[matchId])
        let model = MatchDetailModel(matchId: matchId)
        let game = try #require(model.selectedGame(in: details))
        await model.loadSelectedGame(store: store)
        #expect(!model.hasLoaded(game))
        store.reveal(matchId: matchId)
        await model.loadSelectedGame(store: store)
        #expect(model.hasLoaded(game))
    }

    /// Un chargement interrompu (autre game choisie, écran quitté) n'est pas un premier chargement fini.
    @Test func aCancelledLoadIsNotALoadedGame() async throws {
        let (store, _) = await makeStore(game2: "completed", stats: "enabled")
        let details = try #require(store.details[matchId])
        let model = MatchDetailModel(matchId: matchId)
        let game = try #require(model.selectedGame(in: details))
        let task = Task { await model.loadSelectedGame(store: store) }
        task.cancel()
        await task.value
        #expect(!model.hasLoaded(game))
    }

    // MARK: Game affichée

    @Test func selectedGameFollowsTheChoiceThenTheLiveGameThenTheLastPlayed() async throws {
        let (live, _) = await makeStore(game2: "inProgress", stats: "enabled")
        let liveDetails = try #require(live.details[matchId])
        let model = MatchDetailModel(matchId: matchId)
        #expect(model.selectedGame(in: liveDetails)?.number == 2) // la game en cours
        model.selectedGameNumber = 1
        #expect(model.selectedGame(in: liveDetails)?.number == 1) // le choix de l'utilisateur
        model.selectedGameNumber = 3
        #expect(model.selectedGame(in: liveDetails)?.number == 2) // une game inutile n'existe pas
        model.selectedGameNumber = 9
        #expect(model.selectedGame(in: liveDetails)?.number == 2) // numéro inconnu : retour à la game en cours

        let (done, _) = await makeStore(game2: "completed", stats: "enabled")
        let doneDetails = try #require(done.details[matchId])
        model.selectedGameNumber = nil
        #expect(model.selectedGame(in: doneDetails)?.number == 2) // la dernière jouée

        let (between, _) = await makeStore(game2: "unstarted", stats: "enabled")
        let betweenDetails = try #require(between.details[matchId])
        #expect(model.selectedGame(in: betweenDetails)?.number == 1) // entre deux games : la dernière jouée
    }

    // MARK: Rechargement à l'ouverture

    /// Calendrier où le match M1 est TERMINÉ (KC 2 – 0), au format de `getSchedule`.
    private let completedScheduleJSON = """
    {"data":{"schedule":{"events":[{"startTime":"2026-10-20T16:00:00Z","state":"completed","type":"match",\
    "blockName":"Quarts de finale","league":{"name":"Mondial","slug":"worlds"},\
    "match":{"id":"M1","teams":[{"name":"Karmine Corp","code":"KC","result":{"outcome":"win","gameWins":2}},\
    {"name":"Cloud9 Kia","code":"C9","result":{"outcome":"loss","gameWins":0}}],\
    "strategy":{"type":"bestOf","count":3}}}]}}}
    """

    /// Un match mis en cache « entre deux games » puis rouvert une fois terminé (l'événement est `completed`, plus
    /// aucune game en cours) : l'ouverture relit toujours `getEventDetails`, sinon score, phase et pilules restent périmés.
    @Test func openingAMatchAlwaysReloadsItsDetails() async throws {
        let stale = detailsJSON(game2: "unstarted", stats: "enabled")
        let schedule = completedScheduleJSON
        let transport = ScriptedTransport(extra: { url in
            if url.path.hasSuffix("/getEventDetails") { return HTTPResponse(status: 200, body: Data(stale.utf8)) }
            if url.path.hasSuffix("/getSchedule") { return HTTPResponse(status: 200, body: Data(schedule.utf8)) }
            return nil
        })
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        await store.refreshDue(opening: true)
        await store.loadDetails(matchId: matchId)
        // Situation de départ : détails périmés (entre deux games, aucune game en cours) pour un match terminé.
        #expect(store.event(id: matchId)?.state == .completed)
        let details = try #require(store.details[matchId])
        #expect(details.currentGame == nil)
        let before = await detailsRequestCount(transport)
        #expect(before == 1)

        // La première passe de la boucle finit par la game affichée (g1, terminée) : le flux `window` est alors demandé.
        let loop = Task { await MatchDetailModel(matchId: matchId).run(store: store) }
        let deadline = ContinuousClock.now + .seconds(5)
        while await windowRequests(transport).isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        loop.cancel()
        await loop.value
        #expect(await windowRequests(transport).isEmpty == false, "la première passe n'est pas arrivée au flux `window`")
        #expect(await detailsRequestCount(transport) == before + 1)
    }

    /// Tant que le match est en cours, les détails sont relus à la cadence du direct (60 s) sur celle de l'écran (10 s).
    @Test func liveDetailsAreReloadedEverySixCycles() {
        #expect(MatchDetailModel.reloadEvery == 6)
    }

    private func detailsRequestCount(_ transport: ScriptedTransport) async -> Int {
        await transport.requests.filter { $0.path.hasSuffix("/getEventDetails") }.count
    }
}
