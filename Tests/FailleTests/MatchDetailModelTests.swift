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
    private func makeStore(game2: String, stats: String, spoilerFree: Bool = false) async -> (AppStore, ScriptedTransport) {
        let json = detailsJSON(game2: game2, stats: stats)
        let transport = ScriptedTransport(extra: { url in
            url.path.hasSuffix("/getEventDetails") ? HTTPResponse(status: 200, body: Data(json.utf8)) : nil
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
}
