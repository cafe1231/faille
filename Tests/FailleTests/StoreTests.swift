import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Store branché sur `StubTransport` et un dossier temporaire : chargement, disque, panne (spec §4.4, §10).
@MainActor
@Suite(.serialized)
struct StoreTests {
    @Test func firstRefreshLoadsAndPersistsEverything() async throws {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: StubTransport(), files: files)
        await store.refreshDue(opening: true)
        #expect(store.leagues.count == 2)
        #expect(store.catalog.count == 2)
        #expect(store.live?.isEmpty == true)
        // Ligues chargées dans le même cycle : le calendrier (Mondial) suit aussitôt.
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.isFailing == false)

        // Un nouveau store relit tout depuis le disque, sans réseau.
        let offline = AppStore(transport: StubTransport(failing: true), files: files)
        #expect(offline.catalog.count == 2)
        #expect(offline.schedule.map(\.id) == ["300"])
        #expect(offline.leaguePills.map(\.slug) == ["worlds", "lec"])
    }

    @Test func followIsSavedAndFailuresKeepCachedData() async throws {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: StubTransport(), files: files)
        await store.refreshDue(opening: true)
        let kc = try #require(store.catalog.first(where: { $0.code == "KC" }))
        store.toggleFollow(kc)
        store.setSpoilerFree(true, id: kc.id)

        let failing = AppStore(transport: StubTransport(failing: true), files: files)
        #expect(failing.follows.teams.map(\.code) == ["KC"])
        #expect(failing.follows.teams.first?.spoilerFree == true)
        await failing.refreshDue(opening: true)
        #expect(failing.isFailing)
        #expect(failing.schedule.map(\.id) == ["300"])
        #expect(failing.bannerText?.hasPrefix("lolesports ne répond pas") == true)
        #expect(failing.cards.first?.next?.id == "300")
    }

    /// Les tests hébergés ne doivent déclencher ni interface ni réseau : `FailleApp` se fie à ce drapeau.
    @Test func hostAppKnowsItIsUnderTest() {
        #expect(RunEnvironment.isTesting)
    }

    // MARK: Store d'aperçu (#Preview et captures d'écran des tâches suivantes)

    @Test func previewStoreMatchesTheMockups() {
        let store = AppStore(preview: .standard)
        // KC et T1 en direct (ordre de suivi), GEN avec un prochain match.
        #expect(store.cards.map(\.team.code) == ["KC", "T1", "GEN"])
        #expect(store.event(id: SampleData.kcMatchId)?.id == SampleData.kcMatchId)
        #expect(store.bannerText == nil)
        #expect(store.lastUpdate == SampleData.date("2026-10-15T15:05:00Z"))
        // L'équipe suivie donne sa teinte, l'adversaire non suivi reste en verre neutre.
        #expect(store.tint(for: SampleData.kcLive.match.teams[0]) != nil)
        #expect(store.tint(for: SampleData.kcLive.match.teams[1]) == nil)
    }

    @Test func previewStoreAppliesTheSpoilerPolicy() {
        let store = AppStore(preview: .standard)
        #expect(store.isMasked(SampleData.t1Live.match.teams, matchId: SampleData.t1MatchId))
        #expect(store.scoreLine(SampleData.t1Live).score == nil)
        let masked = store.liveState(for: SampleData.t1Live)
        #expect(masked.spoilerFree)
        #expect(masked.stats == nil)
        #expect(masked.seriesScore == nil)

        #expect(!store.isMasked(SampleData.kcLive.match.teams, matchId: SampleData.kcMatchId))
        #expect(store.scoreLine(SampleData.kcLive).score == [1, 0])
    }

    @Test func previewStoreBuildsTheLiveStateWithStatsAndClock() {
        let store = AppStore(preview: .standard)
        let state = store.liveState(for: SampleData.kcLive)
        #expect(state.phase == .inGame)
        #expect(state.seriesScore == [1, 0])
        #expect(state.gameNumber == 2)
        #expect(state.stats?.map(\.kills) == [7, 4])
        #expect(state.statsAvailable)
        #expect(state.gameClockStart != nil)
        // Pas de stats fournies par Riot : l'état le dit, il n'invente rien.
        #expect(!store.liveState(for: SampleData.noStatsLive).statsAvailable)
    }

    @Test func failingPreviewShowsTheBannerWithTheLastUpdate() {
        let store = AppStore(preview: .failing)
        #expect(store.bannerText?.hasPrefix("lolesports ne répond pas · màj ") == true)
        #expect(AppStore(preview: .empty).cards.isEmpty)
    }
}
