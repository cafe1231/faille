import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    @Test func matchesScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: .standard)), named: "01-matchs")
        expectNotBlank(url)
    }

    @Test func matchesWelcome() async throws {
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: .empty)), named: "02-matchs-vide")
        expectNotBlank(url)
    }

    @Test func matchesOffline() async throws {
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: .failing)), named: "08-bandeau-erreur")
        expectNotBlank(url)
    }
}
