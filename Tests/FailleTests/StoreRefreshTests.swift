import Foundation
import LoLKit
import Testing
@testable import Faille

/// Cadence, annulation, échecs et protection des fichiers du store (spec §4.1, §4.4, §10 et décisions du contrôleur).
@MainActor
@Suite(.serialized)
struct StoreRefreshTests {
    // MARK: Annulation (R-T3)

    /// Une requête annulée n'est pas une panne : ni bandeau, ni tentative ratée qui retarderait le cycle suivant.
    @Test(arguments: [ScriptedTransport.Mode.urlCancelled, .swiftCancelled])
    func cancelledRequestsAreNotFailures(mode: ScriptedTransport.Mode) async {
        let transport = ScriptedTransport(mode: mode)
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        await store.refreshDue(opening: true)
        #expect(store.isFailing == false)
        #expect(store.bannerText == nil)
        #expect(store.leagues.isEmpty)

        // Si la tentative annulée comptait comme ratée, rien ne serait dû avant 60 s.
        await transport.setMode(.ok)
        await store.refreshDue(opening: true)
        #expect(store.leagues.count == 2)
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.isFailing == false)
    }

    /// Annuler la boucle (scène qui quitte le premier plan) annule la requête en vol, sans bandeau ni nouvelle requête.
    @Test func cancellingThePollLoopEndsCleanly() async {
        let transport = ScriptedTransport(delay: .seconds(30))
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        let loop = Task { await store.poll() }
        while await transport.requests.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        loop.cancel()
        await loop.value
        #expect(store.isFailing == false)
        #expect(await transport.requests.count == 1)
    }

    // MARK: Cadence (R-T1a, R-T1b)

    /// `lastSuccess` date le DÉBUT de la tentative : le direct (60 s) ne glisse pas de la durée de la requête.
    @Test func lastSuccessIsTheStartOfTheAttempt() async throws {
        let transport = ScriptedTransport(delay: .milliseconds(400))
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        await store.refreshDue(opening: true)
        let end = Date()
        let liveStart = try #require(store.lastSuccess[.live])
        // Le direct est parti 0,4 s avant sa réponse, puis le calendrier a pris 0,4 s : au moins 0,8 s avant la fin
        // (une date prise à la réponse n'en donnerait que 0,4).
        #expect(end.timeIntervalSince(liveStart) >= 0.7)
    }

    /// Tirer pour rafraîchir agit même dans la minute qui suit un échec ; une ouverture ordinaire, non.
    @Test func pullToRefreshActsRightAfterAFailure() async {
        let files = TemporaryFiles.store()
        files.save(Cached(value: SampleData.leagues, fetchedAt: Date()), to: .leagues)
        let transport = ScriptedTransport(mode: .failing)
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        #expect(store.isFailing)

        await transport.setMode(.ok)
        await store.refreshDue(opening: true) // moins de 60 s après l'échec : rien n'est dû
        #expect(store.schedule.isEmpty)
        #expect(store.live == nil)

        await store.refreshNow()
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.live?.isEmpty == true)
        #expect(store.isFailing == false)
    }

    // MARK: Stats des cartes (R-I2)

    private static func windowJSON(gameId: String, blue: String, red: String) -> Data {
        func team(_ gold: Int) -> String {
            #"{"totalGold":\#(gold),"inhibitors":0,"towers":0,"barons":0,"totalKills":0,"dragons":[],"participants":[]}"#
        }
        func frame(_ time: String) -> String {
            #"{"rfc460Timestamp":"\#(time)","gameState":"in_game","blueTeam":\#(team(2500)),"redTeam":\#(team(2500))}"#
        }
        let metadata = #"{"patchVersion":"15.1","blueTeamMetadata":{"esportsTeamId":"\#(blue)","participantMetadata":[]},"redTeamMetadata":{"esportsTeamId":"\#(red)","participantMetadata":[]}}"#
        let frames = [frame("2026-10-15T17:02:00.000Z"), frame("2026-10-15T17:20:42.000Z")].joined(separator: ",")
        return Data(#"{"esportsGameId":"\#(gameId)","esportsMatchId":"m","gameMetadata":\#(metadata),"frames":[\#(frames)]}"#.utf8)
    }

    private func seededFiles() -> FileStore {
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [
            FollowedTeam(id: "bro", code: "BRO", name: "HANJIN BRION"),
            FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true),
        ]), to: .follows)
        files.save(Cached(value: [SampleData.noStatsLive, SampleData.t1Live], fetchedAt: Date()), to: .live)
        return files
    }

    /// Un match en cours dont Riot ne fournit pas les stats est quand même interrogé (pour le chrono) ; un 404
    /// arrête les tentatives ; un match masqué n'est jamais interrogé.
    @Test func gamesWithoutStatsAreStillAskedOnceAndMaskedMatchesNever() async {
        let transport = ScriptedTransport()
        let store = AppStore(transport: transport, files: seededFiles())
        #expect(store.live?.count == 2)

        await store.refreshLiveStats()
        let windows = await transport.requests.map(\.absoluteString).filter { $0.contains("/window/") }
        #expect(windows.count == 1)
        #expect(windows.first?.contains("/window/g2-bro-lgd") == true)
        #expect(store.statsUnavailable == ["g2-bro-lgd"])

        await store.refreshLiveStats()
        #expect(await transport.requests.count == 1)
    }

    /// Quand le flux répond malgré `statsDisabled`, l'état donne le chrono mais ni stats ni « stats disponibles ».
    @Test func clockWorksWithoutStats() async {
        let body = Self.windowJSON(gameId: "g2-bro-lgd", blue: "bro", red: "lgd")
        let transport = ScriptedTransport(extra: { url in
            url.absoluteString.contains("/window/g2-bro-lgd") ? HTTPResponse(status: 200, body: body) : nil
        })
        let store = AppStore(transport: transport, files: seededFiles())
        await store.refreshLiveStats()
        #expect(store.statsUnavailable.isEmpty)

        let state = store.liveState(for: SampleData.noStatsLive)
        #expect(state.phase == .inGame)
        #expect(state.gameClockStart != nil)
        #expect(state.stats == nil)
        #expect(!state.statsAvailable)
    }

    // MARK: Fichiers illisibles (R-T5)

    /// Fichier existant mais illisible au niveau E/S (droits retirés) : pas de liste vide par défaut écrite par-dessus,
    /// et la vraie liste est relue avant la première modification de l'utilisateur.
    @Test func unreadableFollowsAreNeverReplacedByDefaults() async throws {
        let files = TemporaryFiles.store()
        let original = FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", spoilerFree: true),
            FollowedTeam(id: "t1", code: "T1", name: "T1"),
        ])
        files.save(original, to: .follows)
        let path = files.url(.follows).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        let store = AppStore(transport: StubTransport(), files: files)
        #expect(store.follows.teams.isEmpty)
        await store.refreshDue(opening: true) // cycle complet : aucune écriture automatique
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(files.load(FollowList.self, from: .follows) == original)

        // Le fichier est de nouveau lisible quand l'utilisateur agit : sa liste est rechargée AVANT la modification.
        let g2 = Team(id: "g2", slug: "g2", name: "G2 Esports", code: "G2", image: nil, status: "active", homeLeague: nil)
        store.toggleFollow(g2)
        #expect(files.load(FollowList.self, from: .follows)?.teams.map(\.code) == ["KC", "T1", "G2"])
    }

    @Test func unreadableSettingsKeepRevealedMatches() throws {
        let files = TemporaryFiles.store()
        files.save(AppSettings(revealedMatchIds: ["ancien"]), to: .settings)
        let path = files.url(.settings).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        let store = AppStore(transport: StubTransport(), files: files)
        #expect(store.settings.revealedMatchIds.isEmpty)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        store.reveal(matchId: "nouveau")
        #expect(files.load(AppSettings.self, from: .settings)?.revealedMatchIds == ["ancien", "nouveau"])
    }
}
