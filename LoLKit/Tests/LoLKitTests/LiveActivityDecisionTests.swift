import Foundation
import Testing
@testable import LoLKit

/// Que faire d'une Live Activity en cours à chaque mise à jour (spec §6.3, §6.4).
@Suite struct LiveActivityDecisionTests {
    private let now = date("2026-10-15T17:20:00Z")
    /// Ordre de la Live Activity : KC, puis C9.
    private let attributes = LiveMatchAttributes(
        matchId: "kc-c9", leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "kc", code: "KC", name: "Karmine Corp", colorHex: "#5B8CFF"),
                .init(id: "c9", code: "C9", name: "Cloud9", colorHex: nil)],
        primaryTeamIndex: 0)

    private func state(_ phase: LiveMatchState.Phase = .inGame, score: [Int]? = [1, 0], updatedAt: Date) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: score, gameNumber: phase == .finished ? nil : 2, gameClockStart: nil,
                       gameClockStoppedAt: nil, stats: nil, statsAvailable: true, spoilerFree: false,
                       winnerCode: phase == .finished ? "KC" : nil, updatedAt: updatedAt)
    }

    private func content(_ state: LiveMatchState, teams: [MatchTeam]? = nil) -> LiveActivityContent {
        LiveActivityContent(teams: teams ?? [makeTeam("KC", id: "kc"), makeTeam("C9", id: "c9")],
                            attributes: attributes, state: state)
    }

    private func decide(_ current: LiveMatchState, _ latest: LiveActivityContent?, pinned: Bool = false,
                        mode: LiveActivityMode = .automatic) -> LiveActivityUpdate {
        LiveActivityPlanner.decision(attributes: attributes, current: current, latest: latest, isPinned: pinned,
                                     mode: mode, now: now)
    }

    @Test func newerContentIsSent() {
        let latest = state(score: [2, 0], updatedAt: now)
        #expect(decide(state(updatedAt: now.addingTimeInterval(-60)), content(latest)) == .update(latest))
    }

    @Test func theSameRefreshIsNotSentAgainEvenWithLessData() {
        var current = state(updatedAt: now)
        #expect(decide(current, content(current)) == .keep)
        // Même relecture, mais stats pas encore rechargées (appli relancée hors ligne) : on n'efface rien.
        current.stats = [TeamStats(kills: 7), TeamStats(kills: 4)]
        #expect(decide(current, content(state(updatedAt: now))) == .keep)
    }

    @Test func olderContentNeverReplacesNewer() {
        #expect(decide(state(updatedAt: now), content(state(score: [0, 0], updatedAt: now.addingTimeInterval(-120)))) == .keep)
    }

    @Test func aRevealOrAMaskIsSentWithoutANewRefresh() {
        let revealed = state(updatedAt: now)
        let masked = revealed.masked()
        #expect(decide(masked, content(revealed)) == .update(revealed))
        #expect(decide(revealed, content(masked)) == .update(masked))
    }

    @Test func nothingNewKeepsTheActivityAsItIs() {
        #expect(decide(state(updatedAt: now), nil) == .keep)
    }

    @Test func aFinishedMatchEndsAndStaysAnHour() {
        let finished = state(.finished, score: [3, 1], updatedAt: now)
        #expect(decide(state(updatedAt: now.addingTimeInterval(-60)), content(finished))
                == .end(finished, dismissAt: now.addingTimeInterval(3600)))
    }

    @Test func manualModeEndsWhatIsNotPinned() {
        let current = state(updatedAt: now)
        #expect(decide(current, content(current), mode: .manual) == .end(current, dismissAt: nil))
        let latest = state(score: [2, 0], updatedAt: now.addingTimeInterval(60))
        #expect(decide(current, content(latest), pinned: true, mode: .manual) == .update(latest))
    }

    @Test func theLatestStateIsPutBackInTheActivityTeamOrder() {
        let swapped = state(score: [0, 2], updatedAt: now.addingTimeInterval(60))   // source : C9 puis KC
        let expected = state(score: [2, 0], updatedAt: now.addingTimeInterval(60))
        #expect(decide(state(updatedAt: now), content(swapped, teams: [makeTeam("C9", id: "c9"), makeTeam("KC", id: "kc")]))
                == .update(expected))
    }
}
