import Foundation
import LoLKit
import Testing
@testable import Faille

/// Lueur d'équipe (spec finitions §12) : seulement pour un match en direct non masqué, jamais sur une carte masquée.
@MainActor
struct MatchesMotionTests {
    private func state(_ phase: LiveMatchState.Phase, spoilerFree: Bool) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: spoilerFree ? nil : [1, 0], gameNumber: spoilerFree ? nil : 2,
                       gameClockStart: nil, gameClockStoppedAt: nil, stats: nil, statsAvailable: true,
                       spoilerFree: spoilerFree, winnerCode: nil, updatedAt: Date())
    }

    @Test func onlyAnUnmaskedLiveMatchMakesTheCardGlow() {
        #expect(TeamCardView.glows(state(.inGame, spoilerFree: false)))
        #expect(TeamCardView.glows(state(.betweenGames, spoilerFree: false)))
        #expect(!TeamCardView.glows(state(.inGame, spoilerFree: true)))
        #expect(!TeamCardView.glows(state(.finished, spoilerFree: false)))
        #expect(!TeamCardView.glows(state(.upcoming, spoilerFree: false)))
        #expect(!TeamCardView.glows(nil))
    }

    /// Révélation (I1) : la carte garde la place de la ligne de stats (squelette) tant que la première frame n'est pas
    /// arrivée ; jamais pour un état masqué, sans stats fournies, entre deux games ou une fois les stats là.
    @Test func theCardKeepsTheStatsLineWhileTheFirstFrameIsPending() {
        func cardState(_ phase: LiveMatchState.Phase, spoilerFree: Bool = false, available: Bool = true,
                       stats: [TeamStats]? = nil) -> LiveMatchState {
            LiveMatchState(phase: phase, seriesScore: spoilerFree ? nil : [1, 0], gameNumber: spoilerFree ? nil : 2,
                           gameClockStart: nil, gameClockStoppedAt: nil, stats: stats, statsAvailable: available,
                           spoilerFree: spoilerFree, winnerCode: nil, updatedAt: Date())
        }
        let team = TeamStats(kills: 3, gold: 5000, towers: 1, inhibitors: 0, barons: 0, dragons: [])
        #expect(TeamCardView.showsStatsSkeleton(cardState(.inGame)))
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.inGame, stats: [team, team])))
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.inGame, available: false)))
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.betweenGames)))
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.finished)))
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.upcoming)))
        // Anti-spoiler (spec §8) : un état masqué (stats nil, phase « en direct ») ne montre jamais ce squelette.
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.inGame, spoilerFree: true)))
        #expect(!TeamCardView.showsStatsSkeleton(cardState(.inGame).masked()))
    }

    /// Cartes de l'aperçu : KC (en direct, non masqué) brille ; T1 (en direct, anti-spoiler) et GEN (à venir) non.
    @Test func inThePreviewOnlyKCGlows() throws {
        let store = AppStore(preview: .standard)
        func glows(_ code: String) throws -> Bool {
            let card = try #require(store.cards.first { $0.team.code == code })
            return TeamCardView.glows(card.live.map { store.liveState(for: $0).displayed(for: $0) })
        }
        #expect(try glows("KC"))
        #expect(try !glows("T1"))
        #expect(try !glows("GEN"))
    }
}
