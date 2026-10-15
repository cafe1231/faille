import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func onboarding(page: Int, teams: [Team]? = nil) -> some View {
        OnboardingView(teams: teams ?? Array(SampleData.catalog.prefix(8)), leagues: SampleData.leagues,
                       followedTeams: SampleData.catalog.filter { ["kc", "t1"].contains($0.id) }, followedLeagueIds: [SampleData.leagues[2].id],
                       spoilerFreeIds: ["t1"], search: { _ in [] }, onToggleTeam: { _ in }, onToggleLeague: { _ in },
                       onSetSpoilerFree: { _, _ in }, onDone: {}, initialPage: page)
    }

    /// Les trois écrans du premier lancement (spec saison §3.7) : exemple vivant (figé), choix des équipes et ligues
    /// (KC, T1 et la LEC suivies), anti-spoiler (T1 masquée).
    @Test func onboardingPages() async throws {
        for page in 0..<3 {
            let url = try await Snapshot.write(onboarding(page: page), named: "32-onboarding-\(page + 1)")
            expectNotBlank(url)
        }
    }

    /// Catalogue pas encore lu (audit D.1, saison 7) : page 2 avec le squelette de la grille et sa note.
    @Test func onboardingCatalogueVide() async throws {
        let url = try await Snapshot.write(onboarding(page: 1, teams: []), named: "32-onboarding-2-vide")
        expectNotBlank(url)
    }
}
