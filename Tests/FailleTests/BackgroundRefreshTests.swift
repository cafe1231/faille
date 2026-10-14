import Foundation
import LoLKit
import Testing
@testable import Faille

/// Arrière-plan (spec §6.4) : clés de l'Info.plist, et rien de réel dans les aperçus et les tests.
@MainActor
struct BackgroundRefreshTests {
    @Test func infoPlistAllowsLiveActivitiesAndTheBackgroundRefresh() {
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(identifiers == [BackgroundRefresh.identifier])
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("fetch") == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true)
    }

    @Test func thePreviewStoreDoesNothingInBackground() async {
        let store = AppStore(preview: .standard)
        await store.refreshInBackground()   // ni réseau, ni ActivityKit, ni demande à iOS
        await store.enterBackground()
        #expect(store.schedule == SampleData.schedule)
        #expect(store.liveActivities.shownMatchIds == [SampleData.kcMatchId])
    }
}
