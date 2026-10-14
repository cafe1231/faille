import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Branchements de la saison dans les écrans existants (spec saison §2.1, §3.3, §3.5, §3.6, §3.7).
@MainActor
@Suite(.serialized)
struct SeasonWiringTests {
    /// L'onboarding ne s'ouvre que dans l'appli (routeur de notifications présent), au premier lancement.
    @Test func onboardingIsPresentedOnlyInTheAppAtFirstLaunch() {
        let fresh = AppStore(transport: StubTransport(), files: TemporaryFiles.store())
        #expect(RootView.presentsOnboarding(store: fresh, hasRouter: true))
        #expect(!RootView.presentsOnboarding(store: fresh, hasRouter: false))   // aperçus et tests
        fresh.completeOnboarding()
        #expect(!RootView.presentsOnboarding(store: fresh, hasRouter: true))
        #expect(!RootView.presentsOnboarding(store: AppStore(preview: .standard), hasRouter: true)) // suivis : non
        fresh.endScene()
    }
}

extension ApercuTests {
    /// Détail de KC 1 – 3 G2 (game 4, révélé) avec la section « Duel » sous les stats (spec saison §3.3) : composition de
    /// la game, ligne « Cette game ».
    @Test func detailWithDuel() async throws {
        let view = NavigationStack { MatchDetailView(matchId: SampleData.kcG2MatchId) }
            .environment(AppStore(preview: .withSeason))
        let url = try await Snapshot.write(view.defaultScrollAnchor(.bottom), named: "33-detail-duel")
        expectNotBlank(url)
    }

    /// Onglet Matchs avec « À ne pas rater » en tête et la section « Ligues » (Mondial suivi).
    @Test func matchesWithMustWatchAndLeagues() async throws {
        var data = PreviewData.withSeason
        let worlds = SampleData.leagues[0]
        data.follows = FollowList(teams: SampleData.follows.teams,
                                  leagues: [FollowedLeague(id: worlds.id, slug: worlds.slug, name: worlds.name, image: nil,
                                                           notifyStarts: false)])
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: data)),
                                           named: "33b-matchs-saison")
        expectNotBlank(url)
    }
}
