import Foundation
import LoLKit
import Testing
@testable import Faille

/// Bloc « Diagnostic Live Activity » de À propos : sans Mac ni journal lisible depuis Windows, c'est ce qui dit, sur
/// l'iPhone, pourquoi une Live Activity n'est pas apparue ou ne bouge pas en arrière-plan.
@MainActor
@Suite(.serialized)
struct LiveActivityDiagnosticTests {
    private typealias DiagnosticText = LiveActivityDiagnosticText
    /// Octobre : Paris est à UTC+2 (heure d'été).
    private let paris = TimeZone(identifier: "Europe/Paris") ?? .gmt
    private let now = SampleData.date("2026-10-15T17:30:00Z")

    private func lines(enabled: Bool = true, failure: StartFailure? = nil,
                       background: BackgroundDiagnostic = BackgroundDiagnostic()) -> [DiagnosticText.Line] {
        DiagnosticText.lines(enabled: enabled, failure: failure, background: background, now: now, timeZone: paris)
    }

    // MARK: Texte

    @Test func unknownThingsAreDashes() {
        let shown = lines()
        #expect(shown.map(\.title) == ["Live Activities autorisées", "Dernier échec de démarrage",
                                       "Dernier réveil en arrière-plan", "Dernière demande de réveil"])
        #expect(shown.map(\.value) == ["oui", "—", "—", "—"])
        #expect(lines(enabled: false).first?.value == "non")
    }

    @Test func knownThingsAreLocalHours() {
        let failure = StartFailure(matchId: "m1", reason: "contenu ou ids d'équipe manquants",
                                   date: SampleData.date("2026-10-15T17:05:00Z"))
        let requested = WakeRequest(at: SampleData.date("2026-10-15T17:15:00Z"),
                                    outcome: .requested(SampleData.date("2026-10-15T17:30:00Z")))
        let shown = lines(failure: failure,
                          background: BackgroundDiagnostic(lastWake: SampleData.date("2026-10-15T17:14:00Z"),
                                                           lastRequest: requested))
        #expect(shown.map(\.value) == ["oui", "19:05 · m1 · contenu ou ids d'équipe manquants", "19:14",
                                       "19:15 · demandé pour 19:30"])
    }

    @Test func aRefusedOrUselessWakeRequestSaysWhy() {
        let at = SampleData.date("2026-10-15T17:15:00Z")
        let refused = BackgroundDiagnostic(lastRequest: WakeRequest(at: at, outcome: .refused("trop de demandes en attente")))
        #expect(lines(background: refused).last?.value == "19:15 · refusé : trop de demandes en attente")
        let nothing = BackgroundDiagnostic(lastRequest: WakeRequest(at: at, outcome: .nothingToWatch))
        #expect(lines(background: nothing).last?.value == "19:15 · aucun match suivi en direct")
    }

    /// Le diagnostic est enregistré : un réveil d'un autre jour porte sa date, sinon il se lirait comme celui d'aujourd'hui.
    @Test func anotherDayCarriesItsDate() {
        let yesterday = SampleData.date("2026-10-14T21:05:00Z")   // 23:05 à Paris, la veille
        #expect(DiagnosticText.stamp(yesterday, now: now, timeZone: paris) == "14/10 23:05")
        #expect(DiagnosticText.stamp(now, now: now, timeZone: paris) == "19:30")
        // Même jour UTC, mais déjà le lendemain à Paris : le fuseau local décide.
        let lateEvening = SampleData.date("2026-10-15T22:30:00Z")   // 00:30 le 16 à Paris
        #expect(DiagnosticText.stamp(lateEvening, now: now, timeZone: paris) == "16/10 00:30")
    }

    @Test func aWakeRefusalIsExplainedInFrench() {
        func reason(_ code: Int) -> String {
            BackgroundRefresh.refusalReason(NSError(domain: "BGTaskSchedulerErrorDomain", code: code))
        }
        #expect(reason(1).hasPrefix("indisponible"))
        #expect(reason(2) == "trop de demandes en attente")
        #expect(reason(3).hasPrefix("non autorisé"))
        #expect(reason(9) == "erreur 9")
        #expect(BackgroundRefresh.refusalReason(NSError(domain: "autre", code: 1)).contains("autre"))
    }

    // MARK: Échecs de démarrage

    @Test func aStartFailureIsKeptForTheDiagnostic() {
        let controller = LiveActivityController(files: TemporaryFiles.store(), usesActivityKit: false)
        #expect(controller.lastStartFailure == nil)
        controller.recordStartFailure("m1", "limite atteinte", now: now)
        #expect(controller.lastStartFailure == StartFailure(matchId: "m1", reason: "limite atteinte", date: now))
        // Le dernier échec remplace le précédent.
        controller.recordStartFailure("m2", "autorisation retirée", now: now.addingTimeInterval(10))
        #expect(controller.lastStartFailure?.matchId == "m2")
        #expect(controller.lastStartFailure?.date == now.addingTimeInterval(10))
    }

    /// « Épingler » sans direct (inconnu, ou sans ce match) : seule trace sur l'iPhone.
    @Test func aPinWithoutLiveSetsTheLastStartFailure() {
        let controller = LiveActivityController(files: TemporaryFiles.store(), usesActivityKit: false)
        controller.reportPinWithoutActivity(matchId: "m1", live: nil, now: now)
        #expect(controller.lastStartFailure == StartFailure(matchId: "m1", reason: "direct inconnu", date: now))
        controller.reportPinWithoutActivity(matchId: "m2", live: SampleData.live, now: now)
        #expect(controller.lastStartFailure?.reason == "absent du direct")
        #expect(controller.lastStartFailure?.matchId == "m2")
    }

    @Test func aPinNothingExplainsLeavesNoFailure() {
        // Le direct liste le match : si rien ne s'affiche, la cause est un échec que `sync` note lui-même.
        let controller = LiveActivityController(files: TemporaryFiles.store(), usesActivityKit: false)
        controller.reportPinWithoutActivity(matchId: SampleData.kcMatchId, live: SampleData.live, now: now)
        #expect(controller.lastStartFailure == nil)
        // La Live Activity est à l'écran : rien à signaler.
        let shown = LiveActivityController(preview: ["m1"])
        shown.reportPinWithoutActivity(matchId: "m1", live: nil, now: now)
        #expect(shown.lastStartFailure == nil)
    }

    @Test func pinningThroughTheStoreWithoutLiveShowsInTheDiagnostic() async {
        let store = AppStore(transport: StubTransport(failing: true), files: TemporaryFiles.store())
        #expect(store.pinActivity(matchId: "m1") == .pinned)
        let deadline = ContinuousClock.now + .seconds(5)
        while store.liveActivities.lastStartFailure == nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.liveActivities.lastStartFailure?.matchId == "m1")
        #expect(store.liveActivities.lastStartFailure?.reason == "direct inconnu")
        let failureLine = store.liveActivityDiagnosticLines()[1].value
        #expect(failureLine.hasSuffix("· m1 · direct inconnu"))
    }

    // MARK: Réveils d'arrière-plan

    @Test func theWakeRequestIsRecordedWithWhatWasAsked() {
        let followed = AppStore(preview: .standard)   // un match suivi en direct, une Live Activity à l'écran
        followed.scheduleBackgroundRefresh(now: now)
        #expect(followed.backgroundDiagnostic.lastRequest
                == WakeRequest(at: now, outcome: .requested(now.addingTimeInterval(LiveActivityPlanner.backgroundInterval))))

        let nothing = AppStore(preview: .empty)       // rien de suivi, aucune Live Activity
        nothing.scheduleBackgroundRefresh(now: now)
        #expect(nothing.backgroundDiagnostic.lastRequest == WakeRequest(at: now, outcome: .nothingToWatch))
    }

    /// iOS relance l'appli pour un réveil : ce que la mémoire de ce processus a vu est relu à la prochaine ouverture.
    @Test func aBackgroundWakeIsRecordedAndSurvivesARelaunch() async throws {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: StubTransport(failing: true), files: files)
        #expect(store.backgroundDiagnostic == BackgroundDiagnostic())
        let before = Date()
        await store.refreshInBackground()
        let wake = try #require(store.backgroundDiagnostic.lastWake)
        #expect(wake >= before)
        let request = try #require(store.backgroundDiagnostic.lastRequest)
        #expect(request.at >= before)
        // Rien de suivi ici : la demande de réveil est un « rien à surveiller ».
        #expect(request.outcome == .nothingToWatch)

        let relaunched = AppStore(transport: StubTransport(failing: true), files: files)
        let reloadedWake = try #require(relaunched.backgroundDiagnostic.lastWake)
        #expect(abs(reloadedWake.timeIntervalSince(wake)) < 0.001)
        #expect(relaunched.backgroundDiagnostic.lastRequest?.outcome == .nothingToWatch)
    }

    @Test func theStoreBuildsTheFourLines() {
        let store = AppStore(preview: .standard)
        store.recordBackgroundWake(at: now)
        let shown = store.liveActivityDiagnosticLines(now: now)
        #expect(shown.count == 4)
        #expect(shown[0].value == "oui")
        #expect(shown[1].value == "—")
        #expect(shown[2].value != "—")
        #expect(shown[3].value == "—")
    }
}
