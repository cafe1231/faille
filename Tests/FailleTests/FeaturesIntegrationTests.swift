import Foundation
import LoLKit
import Testing
@testable import Faille

/// Fonctionnalités branchées dans le store et le Détail (spec fonctionnalités) : rien pour un match masqué, sorts
/// d'invocateur seulement pour un match terminé, patch du flux gardé, réglages des notifications enregistrés, aperçus
/// cohérents.
@MainActor
@Suite(.serialized)
struct FeaturesIntegrationTests {
    private static let matchId = "M1"

    /// `getEventDetails` d'un Bo3 KC – C9 : game 1 jouée, game 2 dans l'état demandé, game 3 inutile. `stats` : le
    /// `statsStatus` du stream (« enabled » ou « disabled »).
    private static func detailsJSON(game2: String, stats: String) -> String {
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

    /// Fenêtre `window` de la game g2 (patch 16.19), une frame terminée.
    private static let windowJSON = """
    {"esportsGameId":"g2","esportsMatchId":"M1","gameMetadata":{"patchVersion":"16.19.300.1",\
    "blueTeamMetadata":{"esportsTeamId":"kc","participantMetadata":[]},\
    "redTeamMetadata":{"esportsTeamId":"c9","participantMetadata":[]}},\
    "frames":[{"rfc460Timestamp":"2026-10-04T20:53:40.101Z","gameState":"finished",\
    "blueTeam":{"totalGold":60000,"inhibitors":2,"towers":9,"barons":1,"totalKills":18,"dragons":[],"participants":[]},\
    "redTeam":{"totalGold":50000,"inhibitors":0,"towers":3,"barons":0,"totalKills":7,"dragons":[],"participants":[]}}]}
    """

    /// Store branché sur un faux réseau (détails du match, fenêtre de g2) qui garde toutes les requêtes ; détails chargés.
    private static func makeStore(game2: String, spoilerFree: Bool,
                                  stats: String = "enabled") async -> (AppStore, ScriptedTransport) {
        let details = detailsJSON(game2: game2, stats: stats)
        let window = windowJSON
        let transport = ScriptedTransport(extra: { url in
            if url.path.hasSuffix("/getEventDetails") { return HTTPResponse(status: 200, body: Data(details.utf8)) }
            if url.path.hasSuffix("/window/g2") { return HTTPResponse(status: 200, body: Data(window.utf8)) }
            return nil
        })
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", spoilerFree: spoilerFree)]),
                   to: .follows)
        let store = AppStore(transport: transport, files: files)
        await store.loadDetails(matchId: matchId)
        return (store, transport)
    }

    /// Anti-spoiler (spec fonctionnalités, principes) : pour un match masqué, ni fil, ni détails, ni Data Dragon, ni
    /// Leaguepedia — aucune requête en dehors de `getEventDetails`.
    @Test func maskedMatchLoadsNoFeature() async {
        let (store, transport) = await Self.makeStore(game2: "completed", spoilerFree: true)
        let model = MatchDetailModel(matchId: Self.matchId)
        #expect(model.featureGame(store: store) == nil)
        await model.loadTimeline(store: store)
        await model.followDetails(store: store)
        await model.loadDataDragon(store: store)
        await model.lookUpSpells(store: store)
        let requests = await transport.requests
        #expect(!requests.isEmpty)
        #expect(requests.allSatisfy { $0.path.hasSuffix("/getEventDetails") })
        #expect(store.timelines.replayFrames.isEmpty)
        #expect(store.gameDetails.details.isEmpty)
    }

    @Test func revealedPlayedGameIsTheFeatureGame() async {
        let (store, _) = await Self.makeStore(game2: "completed", spoilerFree: true)
        store.reveal(matchId: Self.matchId)
        let model = MatchDetailModel(matchId: Self.matchId)
        #expect(model.featureGame(store: store)?.id == "g2")
        model.selectedGameNumber = 3 // game inutile : la game affichée reste g2
        #expect(model.featureGame(store: store)?.id == "g2")
    }

    /// Riot ne fournit pas les stats (`statsStatus: disabled`) : pas de game des fonctionnalités, donc ni fil, ni détails,
    /// ni requête de plus.
    @Test func statsDisabledMatchHasNoFeatureGame() async {
        let (store, transport) = await Self.makeStore(game2: "completed", spoilerFree: false, stats: "disabled")
        #expect(store.details[Self.matchId]?.statsDisabled == true)
        let model = MatchDetailModel(matchId: Self.matchId)
        #expect(model.featureGame(store: store) == nil)
        await model.loadTimeline(store: store)
        await model.followDetails(store: store)
        await model.loadDataDragon(store: store)
        #expect(await transport.requests.allSatisfy { $0.path.hasSuffix("/getEventDetails") })
        #expect(store.gameDetails.details.isEmpty)
    }

    /// Les détails par joueur d'une game jouée ne sont définitifs qu'une fois sa frame `finished` lue : avant, la boucle de
    /// 60 s continue (`FeatureKey.detailsFinal`).
    @Test func detailsAreFinalOnceTheFinishedFrameIsRead() async throws {
        let (store, _) = await Self.makeStore(game2: "completed", spoilerFree: false)
        let model = MatchDetailModel(matchId: Self.matchId)
        let game = try #require(model.featureGame(store: store))
        #expect(!model.detailsAreFinal(game, store: store))
        await store.loadWindow(gameId: "g2", inProgress: false)
        #expect(model.detailsAreFinal(game, store: store))
        // Une game en cours n'est jamais définitive, même avec une frame `finished` en mémoire.
        let (live, _) = await Self.makeStore(game2: "inProgress", spoilerFree: false)
        let liveGame = try #require(MatchDetailModel(matchId: Self.matchId).featureGame(store: live))
        #expect(!model.detailsAreFinal(liveGame, store: live))
    }

    /// Sorts d'invocateur : jamais pendant que le match se joue (le wiki n'aurait que des games partielles).
    @Test func spellsWaitForTheEndOfTheMatch() async {
        let (store, transport) = await Self.makeStore(game2: "inProgress", spoilerFree: false)
        let model = MatchDetailModel(matchId: Self.matchId)
        await model.lookUpSpells(store: store)
        #expect(await transport.requests.allSatisfy { $0.host() != "lol.fandom.com" && !$0.path.contains("/window/") })
    }

    /// Ni tant qu'une game reste à jouer (match pas encore terminé au calendrier).
    @Test func spellsWaitWhileAGameIsStillToPlay() async {
        let (store, transport) = await Self.makeStore(game2: "unstarted", spoilerFree: false)
        let model = MatchDetailModel(matchId: Self.matchId)
        await model.lookUpSpells(store: store)
        #expect(await transport.requests.allSatisfy { $0.host() != "lol.fandom.com" && !$0.path.contains("/window/") })
    }

    /// Le patch du flux d'une game lue est gardé : il donne la version Data Dragon de ses images.
    @Test func loadedWindowKeepsItsPatch() async {
        let (store, _) = await Self.makeStore(game2: "completed", spoilerFree: false)
        await store.loadWindow(gameId: "g2", inProgress: false)
        #expect(store.snapshots["g2"]?.phase == .finished)
        #expect(store.patches["g2"] == "16.19.300.1")
    }

    @Test func reminderSettingsAreSavedAndReloaded() {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: ScriptedTransport(mode: .failing), files: files)
        #expect(store.settings.matchRemindersEnabled == false)
        store.setMatchReminders(enabled: true)
        store.setMatchReminderLead(30 * 60)
        let reloaded = AppStore(transport: ScriptedTransport(mode: .failing), files: files)
        #expect(reloaded.settings.matchRemindersEnabled)
        #expect(reloaded.settings.matchReminderLead == 1800)
    }

    /// Les aperçus racontent la même game partout : la dernière frame du fil de la game terminée est celle des stats.
    @Test func previewSamplesAgreeWithTheStats() throws {
        let frames = TimelineSamples.frames(.redWins, start: SampleData.kcG2GameStart, final: SampleData.kcG2Final)
        #expect(frames.last == SampleData.kcG2Final)
        let store = AppStore(preview: .standard)
        #expect(!store.timelines.events(gameId: SampleData.kcSnapshot.gameId).isEmpty)
        #expect(store.gameDetails.details[SampleData.kcG2Final.gameId] != nil)
        #expect(store.summonerSpells.spells[SampleData.kcG2Final.gameId]?.count == 10)
        let games = try #require(store.details[SampleData.kcG2MatchId]?.match.games)
        #expect(games.compactMap { WatchLinks.replay($0, masked: false) }.count == 4)
    }

    /// « Regarder » : le match en direct non masqué (KC) l'a, en français ; le match masqué (T1) ne l'a pas.
    @Test func watchOnlyForTheUnmaskedLiveMatch() {
        let store = AppStore(preview: .standard)
        let kc = SampleData.kcLive
        let t1 = SampleData.t1Live
        let kcWatch = WatchLinks.live(kc.streams, inProgress: true, masked: store.isMasked(kc.match.teams, matchId: kc.id))
        #expect(kcWatch?.preferred.locale == "fr-FR")
        let t1Masked = store.isMasked(t1.match.teams, matchId: t1.id)
        #expect(t1Masked)
        // Mêmes streams, match masqué : aucun bouton.
        #expect(WatchLinks.live(kc.streams, inProgress: true, masked: t1Masked) == nil)
    }
}
