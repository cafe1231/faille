import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Écran verrouillé (spec §7) : en ligne, rectangulaire et rond, dans quatre états.
    @Test func lockScreenWidgets() throws {
        let board = LockScreenBoard(states: [
            BoardState(caption: "En direct · KC", content: WidgetSamples.live),
            BoardState(caption: "En direct masqué · T1", content: WidgetSamples.maskedLive),
            BoardState(caption: "À venir · GEN", content: WidgetSamples.upcoming),
            BoardState(caption: "Aucune équipe suivie", content: WidgetSamples.empty),
        ])
        let url = try WidgetRender.write(board, size: WidgetSize.screen, named: "09-widgets-verrouille")
        expectNotBlank(url)
    }

    /// Écran d'accueil (spec §7) : quatre petits widgets (une équipe chacun) et deux moyens.
    @Test func homeScreenWidgets() throws {
        let board = HomeScreenBoard(
            smalls: [
                SmallState(caption: "KC · en direct", team: WidgetSamples.live.team(id: "kc")),
                SmallState(caption: "T1 · en direct masqué", team: WidgetSamples.live.team(id: "t1")),
                SmallState(caption: "GEN · prochain", team: WidgetSamples.live.team(id: "gen")),
                SmallState(caption: "T1 · prochain masqué", team: WidgetSamples.upcoming.team(id: "t1")),
            ],
            mediums: [
                BoardState(caption: "Mes équipes · en direct", content: WidgetSamples.live),
                BoardState(caption: "Mes équipes · le lendemain", content: WidgetSamples.upcoming),
            ]
        )
        let url = try WidgetRender.write(board, size: WidgetSize.screen, named: "10-widgets-accueil")
        expectNotBlank(url)
    }

    /// Chaque famille dessine vraiment quelque chose : une vue vide passerait inaperçue sur une planche dont le fond
    /// pèse déjà son poids.
    @Test func everyWidgetFamilyDrawsItsContent() {
        let content = WidgetSamples.live
        #expect(WidgetRender.inkRatio(InlineWidgetView(content: content), size: WidgetSize.inline) > 0.01)
        #expect(WidgetRender.inkRatio(RectangularWidgetView(content: content), size: WidgetSize.rectangular) > 0.01)
        #expect(WidgetRender.inkRatio(CircularWidgetView(content: content), size: WidgetSize.circular) > 0.01)
        #expect(WidgetRender.inkRatio(SmallWidgetView(team: content.team(id: "kc")), size: WidgetSize.small) > 0.01)
        #expect(WidgetRender.inkRatio(MediumWidgetView(content: content), size: WidgetSize.medium) > 0.01)
    }
}

/// Les exemples des planches et de la galerie couvrent chaque état : direct, masqué, à venir, rien.
struct WidgetSampleTests {
    @Test func samplesCoverEveryState() {
        #expect(WidgetSamples.live.lines.map(\.matchId) == [SampleData.kcMatchId, SampleData.t1MatchId, "m-gen-fur"])
        #expect(WidgetSamples.live.headline?.status == .live(score: [1, 0], gameNumber: 2))
        #expect(WidgetSamples.maskedLive.headline?.isMasked == true)
        #expect(WidgetSamples.upcoming.headline?.matchId == "m-gen-fur")
        #expect(WidgetSamples.upcoming.team(id: "t1")?.next == .hidden)
        #expect(WidgetSamples.empty.teams.isEmpty)
    }
}
