import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    @Test func teamsScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .teams).environment(AppStore(preview: .standard)), named: "03-equipes")
        expectNotBlank(url)
    }
}
