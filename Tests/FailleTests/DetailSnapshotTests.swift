import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func detail(_ matchId: String) -> some View {
        NavigationStack { MatchDetailView(matchId: matchId) }.environment(AppStore(preview: .standard))
    }

    @Test func detailWithStats() async throws {
        let url = try await Snapshot.write(detail(SampleData.kcMatchId), named: "04-detail")
        expectNotBlank(url)
    }

    /// Le bas du Détail de KC (comme `00-da-bas`) : le bouton « Retirer de l'écran verrouillé » (KC a une Live Activity
    /// dans l'aperçu).
    @Test func detailWithStatsBottom() async throws {
        let url = try await Snapshot.write(detail(SampleData.kcMatchId).defaultScrollAnchor(.bottom), named: "04-detail-bas")
        expectNotBlank(url)
    }

    @Test func detailWithoutStats() async throws {
        let url = try await Snapshot.write(detail(SampleData.noStatsMatchId), named: "05-detail-sans-stats")
        expectNotBlank(url)
    }

    @Test func detailMasked() async throws {
        let url = try await Snapshot.write(detail(SampleData.t1MatchId), named: "06-detail-masque")
        expectNotBlank(url)
    }
}
