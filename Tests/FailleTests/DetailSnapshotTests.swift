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

    /// Squelettes de chargement (spec finitions §10), figés comme tous les aperçus : Détail, puis « Toutes les ligues ».
    @Test func loadingSkeletons() async throws {
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Chargement", subtitle: "Squelettes · Détail et catalogue")
                SectionLabel(text: "Détail d'un match")
                DetailLoadingSkeleton()
                SectionLabel(text: "Toutes les ligues")
                LeagueLoadingSkeleton()
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "15-chargement")
        expectNotBlank(url)
    }
}
