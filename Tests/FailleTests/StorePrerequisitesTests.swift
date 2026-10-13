import Foundation
import LoLKit
import Testing
@testable import Faille

/// Attend (5 s au plus) qu'une requête soit partie ; sinon enregistre un échec au lieu de bloquer le test.
private func waitForRequest(_ transport: ScriptedTransport) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while await transport.requests.isEmpty {
        if ContinuousClock.now >= deadline {
            Issue.record("aucune requête n'est partie après 5 s")
            return false
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// Une tâche d'action a-t-elle vu son annulation ? (nil tant qu'elle n'a pas fini)
@MainActor
private final class CancellationProbe {
    var cancelled: Bool?
}

/// Prérequis de l'étape 4 dans le store : contenu des Live Activities daté de la dernière relecture réussie, couleurs
/// d'équipe hors du cycle gardé, tâches des actions liées à la scène.
@MainActor
@Suite(.serialized)
struct StorePrerequisitesTests {
    /// `lastUpdate` de `PreviewData.standard` : dernière relecture réussie du direct et du calendrier.
    private let lastRefresh = SampleData.date("2026-10-15T15:05:00Z")

    // MARK: Contenu des Live Activities

    @Test func activityContentIsDatedFromTheLastGoodRefreshNotFromTheClockAnchor() throws {
        let content = try #require(AppStore(preview: .standard).activityContent(matchId: SampleData.kcMatchId))
        #expect(content.attributes?.teams.map(\.code) == ["KC", "C9"])
        #expect(content.attributes?.primaryTeamIndex == 0)
        #expect(content.state.phase == .inGame)
        #expect(content.state.updatedAt == lastRefresh)
        #expect(content.state.staleDate == lastRefresh.addingTimeInterval(LiveMatchState.staleAfter))
        // Le chrono reste ancré sur la réception de la frame (18:42 de jeu « maintenant »), pas sur `updatedAt`.
        let start = try #require(content.state.gameClockStart)
        #expect(abs(start.timeIntervalSinceNow + 1122) < 60)
    }

    @Test func activityContentAppliesTheSpoilerPolicy() throws {
        let content = try #require(AppStore(preview: .standard).activityContent(matchId: SampleData.t1MatchId))
        #expect(content.state.spoilerFree)
        #expect(content.state.seriesScore == nil)
        #expect(content.state.stats == nil)
    }

    @Test func aMatchOutOfTheLiveIsFinishedOnlyWhenTheScheduleSaysSo() throws {
        let store = AppStore(preview: .standard)
        let finished = try #require(store.activityContent(matchId: "m-gen-hle"))
        #expect(finished.state.phase == .finished)
        #expect(finished.state.winnerCode == "GEN")
        #expect(finished.attributes == nil)                  // le calendrier ne donne pas d'id d'équipe
        #expect(finished.state.updatedAt == lastRefresh)
        #expect(store.activityContent(matchId: "m-gen-fur") == nil)   // à venir : rien de neuf pour une Live Activity
        #expect(store.activityContent(matchId: "inconnu") == nil)
    }

    /// Un match ni dans le direct ni au calendrier (compétition hors des ligues suivies, équipe plus suivie) n'est
    /// terminé que si ses détails (`getEventDetails`) montrent une série gagnée.
    @Test func aMatchKnownOnlyByItsDetailsIsFinishedWhenItsSeriesIsWon() throws {
        func store(wins: (Int, Int)) -> AppStore {
            let event = Self.detailsOnlyMatch(id: "m-hors-ligues", wins: wins)
            var data = PreviewData()
            data.details = [event.id: EventDetails(event: event)]
            return AppStore(preview: data)
        }
        let won = try #require(store(wins: (3, 1)).activityContent(matchId: "m-hors-ligues"))
        #expect(won.state.phase == .finished)
        #expect(won.state.winnerCode == "AAA")
        #expect(won.attributes?.teams.map(\.code) == ["AAA", "BBB"])   // les détails donnent des ids : démarrable
        #expect(store(wins: (1, 1)).activityContent(matchId: "m-hors-ligues") == nil)
    }

    // MARK: Couleurs d'équipe hors du cycle gardé

    @Test func logosAreFetchedOutsideTheRefreshCycle() async {
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp",
                         image: "http://static.lolesports.com/teams/kc-test.png", homeLeagueName: "LEC"),
        ]), to: .follows)
        let transport = ScriptedTransport()
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        #expect(await transport.requests.filter { $0.absoluteString.hasSuffix("kc-test.png") }.isEmpty)

        await store.updateColorsIfNeeded()
        #expect(await transport.requests.filter { $0.absoluteString.hasSuffix("kc-test.png") }.count == 1)
        #expect(store.follows.team(id: "kc")?.autoColorHex == RGB.accent.hex)   // 404 sur le logo : accent
    }

    // MARK: Tâches des actions liées à la scène

    @Test func actionTasksEndWithTheForegroundLoop() async {
        let transport = ScriptedTransport(delay: .seconds(30))
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        let loop = Task { await store.poll() }
        guard await waitForRequest(transport) else {
            loop.cancel()
            await loop.value
            return
        }
        let g2 = Team(id: "g2", slug: "g2", name: "G2 Esports", code: "G2", image: nil, status: "active", homeLeague: nil)
        store.toggleFollow(g2)               // son rafraîchissement attend la fin du cycle en cours
        #expect(store.sceneTaskCount == 1)
        loop.cancel()                        // la scène quitte le premier plan
        await loop.value
        #expect(store.sceneTaskCount == 0)
    }

    @Test func endingTheSceneCancelsItsActionTasks() async {
        let store = AppStore(transport: StubTransport(failing: true), files: TemporaryFiles.store())
        let probe = CancellationProbe()
        store.runWithScene {
            try? await Task.sleep(for: .seconds(30))
            probe.cancelled = Task.isCancelled
        }
        #expect(store.sceneTaskCount == 1)
        store.endScene()
        #expect(store.sceneTaskCount == 0)
        let deadline = ContinuousClock.now + .seconds(5)
        while probe.cancelled == nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(probe.cancelled == true)
    }

    // MARK: Aides

    /// Match terminé d'une compétition que le calendrier ne couvre pas : deux équipes avec id, aucune suivie.
    private static func detailsOnlyMatch(id: String, wins: (Int, Int)) -> MatchEvent {
        func team(_ code: String, wins: Int) -> MatchTeam {
            MatchTeam(id: code.lowercased(), name: "Équipe \(code)", code: code, image: nil,
                      result: MatchTeam.Result(outcome: nil, gameWins: wins))
        }
        return MatchEvent(
            startTime: SampleData.date("2026-10-15T10:00:00Z"), state: .completed, type: "match", blockName: nil,
            league: LeagueRef(id: "hors-ligues", slug: "hors-ligues", name: "Hors ligues", image: nil),
            match: MatchInfo(id: id, teams: [team("AAA", wins: wins.0), team("BBB", wins: wins.1)],
                             strategy: Strategy(type: "bestOf", count: 5), games: nil),
            streams: nil
        )
    }
}
