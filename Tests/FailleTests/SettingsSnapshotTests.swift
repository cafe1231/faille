import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    @Test func settingsScreen() async throws {
        let url = try await Snapshot.write(SettingsView().environment(AppStore(preview: .standard)), named: "07-reglages")
        expectNotBlank(url)
    }
}
