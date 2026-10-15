import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Écran verrouillé (spec §6.1, §6.3) : la Live Activity dans chacun de ses états.
    @Test func liveActivityLockScreen() throws {
        let url = try WidgetRender.write(LiveActivityBoard(states: LiveBoardState.lockScreen),
                                         size: LiveActivityBoard.size, named: "12-live-activity")
        expectNotBlank(url)
    }

    /// Dynamic Island (spec §6.2) : compacte, minimale et déployée.
    @Test func dynamicIsland() throws {
        let url = try WidgetRender.write(DynamicIslandBoard(states: LiveBoardState.island),
                                         size: WidgetSize.screen, named: "13-dynamic-island")
        expectNotBlank(url)
    }

    /// iOS tronque une Live Activity de plus de 160 pt ; chaque vue de la Dynamic Island dessine vraiment quelque chose.
    @Test func liveActivityFitsAndDraws() {
        var heights: [String: CGFloat] = [:]
        for state in LiveBoardState.lockScreenChecked {
            let height = WidgetRender.idealHeight(LiveActivityLockView(display: state.display), width: 360)
            heights[state.caption] = height
            #expect(height > 40 && height <= 160, "\(state.caption) : \(height) pt")
        }
        // La mesure voit les lignes de stats : la Live Activity en jeu (5 lignes) est plus haute que celle d'un simple message.
        #expect((heights["En jeu · KC"] ?? 0) > (heights["Entre deux games"] ?? .infinity),
                "la mesure ne voit pas les lignes de stats : \(heights)")
        let display = LiveActivitySamples.inGame
        #expect(WidgetRender.inkRatio(IslandCompactView(display: display, side: 0), size: CGSize(width: 60, height: 36)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandCompactView(display: display, side: 1), size: CGSize(width: 60, height: 36)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandMinimalView(display: display), size: CGSize(width: 36, height: 36)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandCenterView(display: display), size: CGSize(width: 160, height: 60)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandBottomView(display: display), size: CGSize(width: 320, height: 24)) > 0.01)
    }

    /// Sous ce seuil de pixels dessinés, un morceau de la Live Activity est considéré comme vide (même seuil que les widgets).
    private static let drawnInk = 0.005

    /// Les planches ont un fond, et la vue de l'écran verrouillé porte le sien : une vue vide passerait donc
    /// `expectNotBlank` comme le contrôle de hauteur. Chaque morceau de chaque état est rendu seul, sur fond
    /// transparent, et doit dessiner quelque chose.
    @Test func everyPieceOfEveryStateDrawsItsContent() {
        for state in LiveBoardState.lockScreenChecked {
            let display = state.display
            let name = state.caption
            expectDrawn(LiveActivityScoreRow(display: display), CGSize(width: 340, height: 28), "score · \(name)")
            expectDrawn(LiveActivityStatusView(status: display.status), CGSize(width: 150, height: 16), "état · \(name)")
            if !display.rows.isEmpty {
                expectDrawn(LiveActivityStatRows(rows: display.rows, teams: display.teams), CGSize(width: 340, height: 84),
                            "stats · \(name)")
            }
            if let message = display.message {
                expectDrawn(LiveActivityMessageView(message: message), CGSize(width: 340, height: 16), "message · \(name)")
            }
        }
        for state in LiveBoardState.island {
            let display = state.display
            let name = state.caption
            expectDrawn(IslandCompactView(display: display, side: 0), CGSize(width: 60, height: 36), "compacte gauche · \(name)")
            expectDrawn(IslandCompactView(display: display, side: 1), CGSize(width: 60, height: 36), "compacte droite · \(name)")
            expectDrawn(IslandMinimalView(display: display), CGSize(width: 36, height: 36), "minimale · \(name)")
            expectDrawn(IslandTeamView(side: display.teams.first), CGSize(width: 64, height: 50), "équipe gauche · \(name)")
            expectDrawn(IslandTeamView(side: display.teams.last), CGSize(width: 64, height: 50), "équipe droite · \(name)")
            expectDrawn(IslandCenterView(display: display), CGSize(width: 160, height: 60), "centre · \(name)")
            expectDrawn(IslandBottomView(display: display), CGSize(width: 320, height: 24), "bas · \(name)")
        }
    }

    private func expectDrawn(_ view: some View, _ size: CGSize, _ label: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        let ratio = WidgetRender.inkRatio(view, size: size)
        #expect(ratio > Self.drawnInk, "\(label) : \(ratio) de pixels dessinés", sourceLocation: sourceLocation)
    }
}

/// Largeur réservée au chrono de la Dynamic Island déployée (B-W1).
struct IslandTimerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func shortWidthBeforeFiftyMinutes() {
        let since = now.addingTimeInterval(-18 * 60 - 42)
        #expect(IslandTimer.width(status: .clock(.running(since: since)), now: now) == IslandTimer.short)
    }

    @Test func longWidthFromFiftyMinutes() {
        let since = now.addingTimeInterval(-3_000)
        #expect(IslandTimer.width(status: .clock(.running(since: since)), now: now) == IslandTimer.long)
        let hour = now.addingTimeInterval(-3_725)
        #expect(IslandTimer.width(status: .clock(.running(since: hour)), now: now) == IslandTimer.long)
    }

    @Test func otherStatusesKeepTheLongWidth() {
        #expect(IslandTimer.width(status: .live, now: now) == IslandTimer.long)
        #expect(IslandTimer.width(status: .clock(.stopped("24:30")), now: now) == IslandTimer.long)
    }
}

/// Icônes de statut (B-W3, B-W4).
struct LiveActivityIconTests {
    @Test func stoppedClockShowsPauseNotLive() {
        #expect(LiveActivityStatusView.icon(for: .clock(.stopped("24:30"))) == .pause)
        #expect(LiveActivityStatusView.icon(for: .clock(.running(since: Date()))) == .live)
        #expect(LiveActivityStatusView.icon(for: .live) == .live)
        #expect(LiveActivityStatusView.icon(for: .betweenGames) == .pause)
    }

    @Test func maskedCompactIslandShowsLiveIconOnTheRightOnly() {
        #expect(IslandCompactView.showsLiveIcon(side: 1, wins: nil, isMasked: true))
        #expect(!IslandCompactView.showsLiveIcon(side: 0, wins: nil, isMasked: true))
        #expect(!IslandCompactView.showsLiveIcon(side: 1, wins: 1, isMasked: false))
        #expect(!IslandCompactView.showsLiveIcon(side: 1, wins: nil, isMasked: false))
    }
}

/// Les exemples des planches couvrent chaque état de la spec §6.3.
struct LiveActivitySampleTests {
    @Test func samplesCoverEveryState() {
        #expect(LiveActivitySamples.inGame.rows.count == 5)
        #expect(LiveActivitySamples.clockStopped.status == .clock(.stopped("24:30")))
        #expect(LiveActivitySamples.masked.isMasked)
        #expect(LiveActivitySamples.masked.score == nil)
        if case .stale = LiveActivitySamples.stale.status {} else { Issue.record("l'exemple « pas fraîche » ne l'est pas") }
        #expect(LiveActivitySamples.betweenGames.status == .betweenGames)
        #expect(LiveActivitySamples.finished.status == .victory("KC"))
        #expect(LiveActivitySamples.statsUnavailable.message == .statsUnavailable)
        #expect(LiveActivitySamples.statsUnavailable.tintHex == nil)
        #expect(LiveActivitySamples.longLeagueBetweenGames.header == "Prime League Pro Division · Bo3 · Game 2")
        #expect(LiveActivitySamples.longLeagueBetweenGames.status == .betweenGames)
        if case .stale = LiveActivitySamples.longLeagueStale.status {} else { Issue.record("l'exemple « ligue longue pas fraîche » ne l'est pas") }
    }
}
