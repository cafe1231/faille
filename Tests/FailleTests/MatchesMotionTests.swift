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
