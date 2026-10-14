import Foundation
import LoLKit
import Testing
@testable import Faille

/// Attend (5 s au plus) qu'une requête soit partie ; sinon enregistre un échec au lieu de bloquer le test.
private func waitForFirstRequest(_ transport: ScriptedTransport, timeout: Duration = .seconds(5)) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while await transport.requests.isEmpty {
        if ContinuousClock.now >= deadline {
            Issue.record("aucune requête n'est partie après \(timeout)")
            return false
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// Nombre de requêtes reçues pour un point d'entrée de l'API (`getLive`, `getSchedule`…).
private func requestCount(_ endpoint: String, in transport: ScriptedTransport) async -> Int {
    await transport.requests.filter { $0.path.hasSuffix("/" + endpoint) }.count
}

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
        let started = await waitForFirstRequest(transport)
        loop.cancel() // même si la requête n'est jamais partie : on ne laisse pas la boucle tourner
        await loop.value
        guard started else { return }
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
        #expect(store.catalog.count == 2) // les équipes, jamais chargées, sont relues aussi
        #expect(store.isFailing == false)
    }

    /// Premier lancement hors ligne : rien n'a jamais réussi, mais un tirer-pour-rafraîchir charge tout, ligues et
    /// équipes comprises, sans attendre le délai de nouvel essai.
    @Test func pullToRefreshAfterAnOfflineFirstLaunchLoadsEverything() async {
        let transport = ScriptedTransport(mode: .failing)
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        await store.refreshDue(opening: true)
        #expect(store.isFailing)
        #expect(store.leagues.isEmpty)

        await transport.setMode(.ok)
        await store.refreshNow()
        #expect(store.leagues.count == 2)
        #expect(store.catalog.count == 2)
        #expect(store.live?.isEmpty == true)
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.isFailing == false)
    }

    // MARK: Une demande de rafraîchissement n'est jamais perdue

    /// Tirer pour rafraîchir pendant un cycle de la boucle : il attend la fin de ce cycle, fait SES requêtes (direct
    /// et calendrier relus une seconde fois), et ne rend la main (fin du spinner) qu'après.
    @Test func pullToRefreshWaitsForTheRunningCycleThenRunsItsOwn() async {
        let files = TemporaryFiles.store()
        files.save(Cached(value: SampleData.leagues, fetchedAt: Date()), to: .leagues)
        let transport = ScriptedTransport(delay: .milliseconds(300))
        let store = AppStore(transport: transport, files: files)
        let loop = Task { await store.poll() }
        guard await waitForFirstRequest(transport) else {
            loop.cancel()
            await loop.value
            return
        }
        // Le premier cycle de la boucle tourne encore : équipes, direct et calendrier, 3 × 0,3 s.
        await store.refreshNow()
        #expect(await requestCount("getTeams", in: transport) == 1)
        #expect(await requestCount("getLive", in: transport) == 2)
        #expect(await requestCount("getSchedule", in: transport) == 2)
        loop.cancel()
        await loop.value
    }

    /// Une ouverture (retour au premier plan) qui tombe pendant un cycle lancé ailleurs (par exemple par un
    /// `toggleFollow`) n'est pas ignorée : elle passe après, et force le direct et le calendrier.
    @Test func anOpeningCycleIsNotDroppedByARunningOne() async {
        let files = TemporaryFiles.store()
        let wanted = ScheduleQuery.leagueIds(follows: FollowList(), leagues: SampleData.leagues)
        files.save(Cached(value: SampleData.leagues, fetchedAt: Date()), to: .leagues)
        files.save(Cached(value: [MatchEvent](), fetchedAt: Date()), to: .live)
        files.save(Cached(value: SchedulePage(leagueIds: wanted, events: []), fetchedAt: Date()), to: .schedule)
        let transport = ScriptedTransport(delay: .milliseconds(300))
        let store = AppStore(transport: transport, files: files)
        // Cycle ordinaire : seules les équipes, jamais chargées, sont dues.
        let running = Task { await store.refreshDue(opening: false) }
        guard await waitForFirstRequest(transport) else {
            running.cancel()
            await running.value
            return
        }
        await store.refreshDue(opening: true)
        #expect(await requestCount("getTeams", in: transport) == 1)
        #expect(await requestCount("getLive", in: transport) == 1)
        #expect(await requestCount("getSchedule", in: transport) == 1)
        await running.value
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

    /// Un direct qui vient d'échouer n'est pas une raison de demander les stats de ses matchs.
    @Test func liveStatsAreNotAskedWhenTheLiveFetchFailed() async {
        let transport = ScriptedTransport(mode: .failing)
        let store = AppStore(transport: transport, files: seededFiles())
        await store.refreshDue(opening: true)
        #expect(store.isFailing)
        #expect(store.live?.count == 2) // le direct en cache reste utilisable
        let windows = await transport.requests.map(\.absoluteString).filter { $0.contains("/window/") }
        #expect(windows.isEmpty)
    }

    /// … mais après un direct relu avec succès, les stats de ses matchs sont bien demandées.
    @Test func liveStatsAreAskedAfterASuccessfulLiveFetch() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let event = try encoder.encode(SampleData.noStatsLive)
        let liveBody = Data(#"{"data":{"schedule":{"events":["#.utf8) + event + Data("]}}}".utf8)
        let transport = ScriptedTransport(extra: { url in
            url.path.hasSuffix("/getLive") ? HTTPResponse(status: 200, body: liveBody) : nil
        })
        let store = AppStore(transport: transport, files: seededFiles())
        await store.refreshDue(opening: true)
        #expect(store.live?.map(\.id) == [SampleData.noStatsMatchId])
        let windows = await transport.requests.map(\.absoluteString).filter { $0.contains("/window/") }
        #expect(windows.count == 1)
    }

    // MARK: Couleurs d'équipe

    /// Un logo qui échoue ne bloque pas les équipes suivantes, et n'est pas réessayé à chaque tick.
    @Test func aLogoThatKeepsFailingDoesNotBlockTheNextTeams() async {
        let broken = "http://static.lolesports.com/teams/broken.png"
        let other = "http://static.lolesports.com/teams/other.png"
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [
            FollowedTeam(id: "a", code: "AAA", name: "Équipe A", image: broken, homeLeagueName: "LEC"),
            FollowedTeam(id: "b", code: "BBB", name: "Équipe B", image: other, homeLeagueName: "LEC"),
        ]), to: .follows)
        let transport = ScriptedTransport(failure: { url in
            if url.absoluteString.contains("broken.png") {
                return URLError(.notConnectedToInternet)
            }
            return nil
        })
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        await store.updateColorsIfNeeded()   // la passe des couleurs vit hors du cycle (étape 4)
        #expect(store.follows.team(id: "a")?.autoColorHex == nil) // en échec : réessayé plus tard
        #expect(store.follows.team(id: "b")?.autoColorHex == RGB.accent.hex) // 404 sur son logo : accent, traitée
        #expect(!store.isFailing) // un logo n'est pas une panne de l'API

        await store.refreshDue(opening: false)
        await store.updateColorsIfNeeded()
        let brokenRequests = await transport.requests.filter { $0.absoluteString.contains("broken.png") }
        #expect(brokenRequests.count == 1)
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

    /// F7 : tant que la relecture échoue encore, la modification de l'utilisateur est appliquée en mémoire mais ne
    /// remplace pas le fichier (l'ancien drapeau « illisible » tombait avant la relecture, donc le fichier était écrasé).
    @Test func userChangeWhileStillUnreadableDoesNotOverwriteTheFile() throws {
        let files = TemporaryFiles.store()
        let original = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")])
        files.save(original, to: .follows)
        let path = files.url(.follows).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        let store = AppStore(transport: StubTransport(failing: true), files: files)
        let g2 = Team(id: "g2", slug: "g2", name: "G2 Esports", code: "G2", image: nil, status: "active", homeLeague: nil)
        store.toggleFollow(g2)                       // la relecture échoue encore (droits retirés)
        #expect(store.follows.teams.map(\.code) == ["G2"])   // appliqué en mémoire
        store.setSpoilerFree(true, id: "g2")         // une seconde modification n'écrit rien non plus
        #expect(store.follows.team(id: "g2")?.spoilerFree == true)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(files.load(FollowList.self, from: .follows) == original)   // le fichier d'origine est intact

        // Le fichier redevient lisible : la modification suivante relit la vraie liste, puis s'y applique.
        store.setSpoilerFree(true, id: "kc")
        let saved = files.load(FollowList.self, from: .follows)
        #expect(saved?.teams.map(\.code) == ["KC"])
        #expect(saved?.team(id: "kc")?.spoilerFree == true)
        // Le drapeau est tombé : les modifications suivantes s'écrivent normalement.
        store.unfollow(id: "kc")
        #expect(files.load(FollowList.self, from: .follows)?.teams.isEmpty == true)
    }

    /// `follows.json` illisible : la liste des équipes suivies, donc des œils (spec §8), est inconnue. Aucune Live
    /// Activity n'est mise à jour ni démarrée avec un contenu démasqué ; la liste relue, les passes reprennent.
    @Test func liveActivitiesDoNotMoveWhileTheFollowsFileIsUnreadable() async throws {
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", spoilerFree: true)]),
                   to: .follows)
        let path = files.url(.follows).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        let store = AppStore(transport: StubTransport(failing: true), files: files)
        #expect(store.followsUnreadable)
        await store.syncLiveActivities(canStart: true)
        await store.syncLiveActivities(canStart: false)
        #expect(store.liveActivities.syncPasses == 0)

        // Le fichier est lisible de nouveau : la prochaine modification de l'utilisateur le relit, le drapeau tombe.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        store.setColorOverride(nil, id: "kc")
        #expect(!store.followsUnreadable)
        await store.syncLiveActivities(canStart: true)
        #expect(store.liveActivities.syncPasses == 1)
    }

    @Test func userChangeWhileSettingsStillUnreadableDoesNotOverwriteTheFile() throws {
        let files = TemporaryFiles.store()
        files.save(AppSettings(revealedMatchIds: ["ancien"]), to: .settings)
        let path = files.url(.settings).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        let store = AppStore(transport: StubTransport(failing: true), files: files)
        store.reveal(matchId: "nouveau")             // la relecture échoue encore
        #expect(store.settings.revealedMatchIds == ["nouveau"])   // appliqué en mémoire
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        #expect(files.load(AppSettings.self, from: .settings)?.revealedMatchIds == ["ancien"])

        store.reveal(matchId: "suivant")             // lisible de nouveau : relue, puis complétée
        #expect(files.load(AppSettings.self, from: .settings)?.revealedMatchIds == ["ancien", "suivant"])
    }

    @Test func fileRemovedWhileUnreadableClearsTheFlagSoTheChangeIsSaved() throws {
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")]), to: .follows)
        let path = files.url(.follows).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }

        let store = AppStore(transport: StubTransport(failing: true), files: files)
        try FileManager.default.removeItem(atPath: path)   // le fichier n'existe plus
        let g2 = Team(id: "g2", slug: "g2", name: "G2 Esports", code: "G2", image: nil, status: "active", homeLeague: nil)
        store.toggleFollow(g2)
        #expect(files.load(FollowList.self, from: .follows)?.teams.map(\.code) == ["G2"])
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
