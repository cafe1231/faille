import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    @Test func teamsScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .teams).environment(AppStore(preview: .standard)), named: "03-equipes")
        expectNotBlank(url)
    }

    /// Catalogue pas encore chargé, API qui répond (spec finitions §10) : squelettes des pilules et des lignes sous
    /// « Toutes les ligues », au lieu de « Chargement des ligues… ».
    @Test func teamsLoading() async throws {
        let store = AppStore(preview: PreviewData(follows: SampleData.follows))
        let url = try await Snapshot.write(RootView(tab: .teams).environment(store), named: "03b-equipes-chargement")
        expectNotBlank(url)
    }
}
