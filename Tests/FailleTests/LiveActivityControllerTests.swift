import Foundation
import LoLKit
import Testing
@testable import Faille

/// Bouton du Détail et choix enregistrés (spec §5.3, §6.4, §10). ActivityKit n'est pas appelé dans les tests hébergés :
/// les décisions sont testées dans LoLKit, ici le câblage et la persistance.
@MainActor
@Suite(.serialized)
struct LiveActivityControllerTests {
    @Test func pinAndRemovalAreSavedAndKeptDisjoint() async {
        let files = TemporaryFiles.store()
        let controller = LiveActivityController(files: files, usesActivityKit: false)
        #expect(controller.pin(matchId: "m1") == .pinned)
        #expect(LiveActivityController(files: files, usesActivityKit: false).choices.pinnedIds == ["m1"])

        await controller.remove(matchId: "m1")
        let reloaded = LiveActivityController(files: files, usesActivityKit: false)
        #expect(reloaded.choices.pinnedIds.isEmpty)
        #expect(reloaded.choices.dismissedIds == ["m1"])

        // Épingler à nouveau annule le retrait.
        #expect(reloaded.pin(matchId: "m1") == .pinned)
        #expect(reloaded.choices.dismissedIds.isEmpty)
    }

    @Test func aFourthPinIsRefusedWhileThreeAreShown() {
        let controller = LiveActivityController(preview: ["a", "b", "c"])
        #expect(controller.pin(matchId: "d") == .full)
        #expect(controller.pin(matchId: "a") == .pinned)
        #expect(controller.choices.pinnedIds == ["a"])
    }

    @Test func theStoreGoesThroughTheController() {
        let store = AppStore(transport: StubTransport(failing: true), files: TemporaryFiles.store())
        #expect(store.pinActivity(matchId: "m1") == .pinned)
        #expect(store.liveActivities.choices.isPinned("m1"))
    }

    /// Démarrage au lancement à froid : la première passe ne diffère que si l'appli a noté des Live Activities
    /// démarrées ET qu'iOS n'en liste aucune ; sinon ouvrir Faille puis verrouiller aussitôt laisserait le match sans
    /// Live Activity (l'arrière-plan ne peut pas en démarrer).
    @Test func theFirstPassOnlyWaitsWhenThereIsSomethingToConfuse() {
        typealias Controller = LiveActivityController
        // Lancement à froid, rien de noté, iOS ne liste rien : on démarre tout de suite.
        #expect(Controller.isListVerified(hasSynced: false, iosListsAny: false, appStartedAny: false))
        // Lancement à froid, des Live Activities notées mais iOS n'en liste aucune : « retirées » ou « pas encore
        // listées » ? La passe suivante tranchera.
        #expect(!Controller.isListVerified(hasSynced: false, iosListsAny: false, appStartedAny: true))
        // iOS en liste : la liste est remplie.
        #expect(Controller.isListVerified(hasSynced: false, iosListsAny: true, appStartedAny: true))
        // Plus la première passe : la liste est sûre, même vide.
        #expect(Controller.isListVerified(hasSynced: true, iosListsAny: false, appStartedAny: true))
        #expect(Controller.isListVerified(hasSynced: true, iosListsAny: false, appStartedAny: false))
    }

    @Test func previewStoreShowsTheKcActivity() {
        #expect(AppStore(preview: .standard).liveActivities.shownMatchIds == [SampleData.kcMatchId])
        #expect(AppStore(preview: .empty).liveActivities.shownMatchIds.isEmpty)
    }

    /// « Épingler » sans direct : la cause qui reste au journal (le reste est journalisé par `sync` lui-même).
    @Test func aPinWithoutLiveIsExplainedByTheLiveList() {
        typealias Controller = LiveActivityController
        #expect(Controller.pinFailureReason(matchId: SampleData.kcMatchId, live: nil) == "direct inconnu")
        #expect(Controller.pinFailureReason(matchId: "inconnu", live: SampleData.live) == "absent du direct")
        #expect(Controller.pinFailureReason(matchId: "inconnu", live: []) == "absent du direct")
        #expect(Controller.pinFailureReason(matchId: SampleData.kcMatchId, live: SampleData.live) == nil)
    }

    // MARK: Relecture des matchs qui ont une Live Activity (`refreshLiveStats`)

    /// Un match épinglé d'équipes non suivies n'a de stats que si sa Live Activity est à l'écran.
    @Test func aShownActivityOfAnUnfollowedLiveMatchGetsItsStats() async {
        let cases: [(shown: Set<String>, windowRequests: Int)] = [([SampleData.noStatsMatchId], 1), ([], 0)]
        for (shown, expected) in cases {
            let transport = ScriptedTransport()
            let files = TemporaryFiles.store()
            files.save(Cached(value: [SampleData.noStatsLive], fetchedAt: Date()), to: .live)
            let store = AppStore(transport: transport, files: files, liveActivities: LiveActivityController(preview: shown))
            #expect(store.follows.teams.isEmpty)
            await store.refreshLiveStats()
            let windows = await transport.requests.filter { $0.absoluteString.contains("/window/") }
            #expect(windows.count == expected, "Live Activity à l'écran : \(shown)")
        }
    }

    /// Un match à l'écran, sorti du direct et pas terminé au calendrier (compétition hors des ligues suivies), est relu
    /// par ses détails : sa série gagnée termine sa Live Activity (`activityContent`).
    @Test func aShownActivityOutsideTheLiveIsReloadedByItsDetails() async throws {
        let transport = ScriptedTransport(extra: Self.detailsResponder(for: Self.outsideMatch(state: .inProgress)))
        let files = TemporaryFiles.store()
        files.save(Cached(value: [SampleData.noStatsLive], fetchedAt: Date()), to: .live)
        let store = AppStore(transport: transport, files: files,
                             liveActivities: LiveActivityController(preview: [Self.outsideMatchId]))
        #expect(store.activityContent(matchId: Self.outsideMatchId) == nil)

        await store.refreshLiveStats()
        let detailRequests = await transport.requests.filter { $0.path.hasSuffix("/getEventDetails") }
        #expect(detailRequests.count == 1)
        #expect(detailRequests.first?.absoluteString.contains("id=\(Self.outsideMatchId)") == true)
        let content = try #require(store.activityContent(matchId: Self.outsideMatchId))
        #expect(content.state.phase == .finished)
    }

    /// Terminé au calendrier : le calendrier suffit, les détails ne sont pas relus.
    @Test func aShownActivityFinishedAtTheScheduleIsNotReloaded() async {
        let outside = Self.outsideMatch(state: .completed)
        let transport = ScriptedTransport(extra: Self.detailsResponder(for: outside))
        let files = TemporaryFiles.store()
        files.save(Cached(value: [SampleData.noStatsLive], fetchedAt: Date()), to: .live)
        files.save(Cached(value: SchedulePage(leagueIds: [], events: [outside]), fetchedAt: Date()), to: .schedule)
        let store = AppStore(transport: transport, files: files,
                             liveActivities: LiveActivityController(preview: [Self.outsideMatchId]))
        await store.refreshLiveStats()
        #expect(await transport.requests.filter { $0.path.hasSuffix("/getEventDetails") }.isEmpty)
    }

    // MARK: Aides

    private static let outsideMatchId = "m-hors-ligues"

    /// Match d'une compétition que le calendrier ne couvre pas : deux équipes avec id, aucune suivie, série gagnée 3-1.
    private static func outsideMatch(state: EventState) -> MatchEvent {
        func team(_ code: String, wins: Int) -> MatchTeam {
            MatchTeam(id: code.lowercased(), name: "Équipe \(code)", code: code, image: nil,
                      result: MatchTeam.Result(outcome: nil, gameWins: wins))
        }
        return MatchEvent(
            startTime: SampleData.date("2026-10-15T10:00:00Z"), state: state, type: "match", blockName: nil,
            league: LeagueRef(id: "hors-ligues", slug: "hors-ligues", name: "Hors ligues", image: nil),
            match: MatchInfo(id: outsideMatchId, teams: [team("AAA", wins: 3), team("BBB", wins: 1)],
                             strategy: Strategy(type: "bestOf", count: 5), games: nil),
            streams: nil
        )
    }

    /// `getEventDetails` de ce match, comme l'API le renvoie.
    private static func detailsResponder(for event: MatchEvent) -> @Sendable (URL) -> HTTPResponse? {
        let encoded = (try? JSONEncoder().encode(EventDetails(event: event))) ?? Data()
        let body = Data(#"{"data":{"event":"#.utf8) + encoded + Data("}}".utf8)
        return { url in
            url.path.hasSuffix("/getEventDetails") ? HTTPResponse(status: 200, body: body) : nil
        }
    }
}
