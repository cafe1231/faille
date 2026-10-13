import Foundation
import LoLKit
import Testing
@testable import Faille

/// Ce que lisent les widgets (spec §4.4, §7) et quand l'appli leur demande de relire (spec §7, §8).
@MainActor
struct WidgetDataTests {
    @Test func widgetsReadWhatTheAppWrote() {
        let directory = TemporaryFiles.directory()
        let files = FileStore(directory: directory)
        let fetchedAt = SampleData.date("2026-10-15T17:05:00Z")
        files.save(SampleData.follows, to: .follows)
        files.save(AppSettings(revealedMatchIds: [SampleData.t1MatchId]), to: .settings)
        files.save(Cached(value: SchedulePage(leagueIds: ["98767975604431411"], events: SampleData.schedule),
                          fetchedAt: fetchedAt), to: .schedule)
        files.save(Cached(value: SampleData.live, fetchedAt: fetchedAt), to: .live)

        let input = WidgetInput.load(from: FileStore(directory: directory, readOnly: true))
        #expect(input.follows == SampleData.follows)
        #expect(input.settings.revealedMatchIds == [SampleData.t1MatchId])
        #expect(input.schedule?.value.events == SampleData.schedule)
        #expect(input.schedule?.fetchedAt == fetchedAt)
        #expect(input.live?.value == SampleData.live)
    }

    @Test func widgetsShowNothingBeforeTheAppHasWrittenAnything() {
        let input = WidgetInput.load(from: FileStore(directory: TemporaryFiles.directory(), readOnly: true))
        #expect(input == WidgetInput())
        #expect(WidgetTimeline.content(at: Date(), input: input).teams.isEmpty)
    }

    @Test func refreshingTheScheduleReloadsTheWidgetsOnce() async {
        let store = AppStore(transport: ScriptedTransport(), files: TemporaryFiles.store())
        #expect(store.widgetReloadRequests == 0)
        await store.refreshDue(opening: true)
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.widgetReloadRequests == 1)
    }

    @Test func aFailedRefreshDoesNotReloadTheWidgets() async {
        let store = AppStore(transport: ScriptedTransport(mode: .failing), files: TemporaryFiles.store())
        await store.refreshDue(opening: true)
        #expect(store.isFailing)
        #expect(store.widgetReloadRequests == 0)
    }

    @Test func revealingAMatchReloadsTheWidgets() {
        let store = AppStore(transport: ScriptedTransport(), files: TemporaryFiles.store())
        store.reveal(matchId: SampleData.t1MatchId)
        #expect(store.widgetReloadRequests == 1)
    }
}
