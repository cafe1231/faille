import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    @Test func settingsScreen() async throws {
        let url = try await Snapshot.write(SettingsView().environment(AppStore(preview: .standard)), named: "07-reglages")
        expectNotBlank(url)
    }

    /// À propos, avec le bloc « Diagnostic Live Activity » rempli (un échec de démarrage, un réveil, une demande).
    @Test func aboutScreen() async throws {
        let store = AppStore(preview: .standard)
        let now = Date()
        store.liveActivities.recordStartFailure("113475290172419872", "contenu ou ids d'équipe manquants",
                                                now: now.addingTimeInterval(-600))
        store.recordBackgroundWake(at: now.addingTimeInterval(-900))
        store.scheduleBackgroundRefresh(now: now.addingTimeInterval(-900))
        let url = try await Snapshot.write(NavigationStack { AboutView() }.environment(store), named: "07b-a-propos")
        expectNotBlank(url)
    }
}
