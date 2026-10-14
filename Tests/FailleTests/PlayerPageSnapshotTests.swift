import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func playerPage(_ playerId: String) -> some View {
        NavigationStack { PlayerPageView(playerId: playerId) }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
    }

    /// Page de Caps (spec saison §3.4) : moyennes, champions (vignettes de repli), meilleure game, 5 dernières games.
    @Test func playerPage() async throws {
        let url = try await Snapshot.write(playerPage("p-caps"), named: "28-joueur")
        expectNotBlank(url)
    }

    /// Faker (T1 en anti-spoiler) : « Stats masquées · 3 matchs masqués ».
    @Test func playerPageMasked() async throws {
        let url = try await Snapshot.write(playerPage("p-faker"), named: "28b-joueur-masque")
        expectNotBlank(url)
    }
}
