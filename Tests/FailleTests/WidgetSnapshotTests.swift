import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Écran verrouillé (spec §7) : en ligne, rectangulaire et rond, dans cinq états.
    @Test func lockScreenWidgets() throws {
        let board = LockScreenBoard(states: [
            BoardState(caption: "En direct · KC", content: WidgetSamples.live),
            BoardState(caption: "En direct masqué · T1", content: WidgetSamples.maskedLive),
            BoardState(caption: "À venir · GEN", content: WidgetSamples.upcoming),
            BoardState(caption: "Prochain masqué · T1", content: WidgetSamples.hidden),
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
                MediumState(caption: "Mes équipes · en direct", content: WidgetSamples.live),
                MediumState(caption: "Mes équipes · le lendemain", content: WidgetSamples.upcoming),
            ]
        )
        let url = try WidgetRender.write(board, size: WidgetSize.screen, named: "10-widgets-accueil")
        expectNotBlank(url)
    }

    /// Moyen widget (spec §7) sur les deux largeurs d'iPhone : quatre lignes en 364 × 170 et en 338 × 158, une équipe
    /// masquée seule, aucune équipe.
    @Test func mediumWidgets() throws {
        let board = HomeScreenBoard(
            smalls: [],
            mediums: [
                MediumState(caption: "Quatre lignes · 364 × 170", content: WidgetSamples.live, size: WidgetSize.medium),
                MediumState(caption: "Quatre lignes · 338 × 158", content: WidgetSamples.live, size: WidgetSize.mediumCompact),
                MediumState(caption: "Équipe masquée seule · 338 × 158", content: WidgetSamples.hidden,
                            size: WidgetSize.mediumCompact),
                MediumState(caption: "Aucune équipe suivie · 338 × 158", content: WidgetSamples.empty,
                            size: WidgetSize.mediumCompact),
            ]
        )
        let url = try WidgetRender.write(board, size: WidgetSize.screen, named: "11-widgets-moyen")
        expectNotBlank(url)
    }
}

extension ApercuTests {
    /// Sous ce seuil de pixels dessinés, une vue de widget est considérée comme vide (le plus petit état réel dépasse 1 %).
    private static let minimumInk = 0.005

    /// Les planches ont un fond : une vue de widget vide passerait donc `expectNotBlank`. Les contrôles suivants
    /// rendent chaque vue seule, sur fond transparent, et exigent qu'elle dessine quelque chose.
    private var inkStates: [(name: String, content: WidgetContent)] {
        [
            ("en direct", WidgetSamples.live),
            ("direct masqué", WidgetSamples.maskedLive),
            ("à venir", WidgetSamples.upcoming),
            ("caché", WidgetSamples.hidden),
            ("vide", WidgetSamples.empty),
        ]
    }

    @Test func theInkMeterSeesAnEmptyViewAsEmpty() {
        #expect(WidgetRender.inkRatio(Color.clear, size: WidgetSize.small) == 0)
        #expect(WidgetRender.inkRatio(EmptyView(), size: WidgetSize.medium) == 0)
    }

    @Test func everyStateOfEveryAccessoryAndMediumFamilyDrawsItsContent() {
        for (name, content) in inkStates {
            expectInk(InlineWidgetView(content: content), WidgetSize.inline, "inline · \(name)")
            expectInk(RectangularWidgetView(content: content), WidgetSize.rectangular, "rectangulaire · \(name)")
            expectInk(CircularWidgetView(content: content), WidgetSize.circular, "rond · \(name)")
            expectInk(MediumWidgetView(content: content), WidgetSize.medium, "moyen 364 × 170 · \(name)")
            expectInk(MediumWidgetView(content: content), WidgetSize.mediumCompact, "moyen 338 × 158 · \(name)")
        }
    }

    @Test func everyStateOfTheSmallFamilyDrawsItsContent() {
        let live = WidgetSamples.live
        let smalls: [(String, WidgetTeam?)] = [
            ("KC en direct", live.team(id: "kc")),
            ("T1 en direct masqué", live.team(id: "t1")),
            ("GEN prochain", live.team(id: "gen")),
            ("T1 prochain masqué", WidgetSamples.upcoming.team(id: "t1")),
            ("aucun match", WidgetTeam(team: SampleData.follows.teams[0], next: .noMatch)),
            ("aucune équipe", WidgetSamples.empty.team(id: nil)),
        ]
        for (name, team) in smalls {
            expectInk(SmallWidgetView(team: team), WidgetSize.small, "petit · \(name)")
        }
        expectInk(SmallWidgetView(team: nil, appGroupMissing: true), WidgetSize.small, "petit · groupe d'apps introuvable")
    }

    /// Le moyen widget tient dans sa case, marges comprises, sur les deux largeurs d'iPhone, même avec quatre lignes de
    /// direct (les plus hautes : pastille « en direct » de 18 pt).
    @Test func theMediumWidgetFitsFourRowsInEverySize() {
        let line: (Int) -> WidgetLine = { index in
            WidgetLine(matchId: "live-\(index)", leagueName: "Mondial", codes: ["KC", "C9"], colorHexes: ["#5B8CFF", nil],
                       status: .live(score: [1, 0], gameNumber: 2), isMasked: false)
        }
        let fourLive = WidgetContent(date: WidgetSamples.now, teams: [], lines: (1...4).map(line))
        let oneLine = WidgetContent(date: WidgetSamples.now, teams: [], lines: [line(1)])
        #expect(WidgetText.mediumRows(WidgetSamples.live).count == WidgetText.mediumRowLimit)
        #expect(WidgetText.mediumRows(fourLive).count == WidgetText.mediumRowLimit)
        let contents = [("quatre lignes en direct", fourLive), ("exemple en direct", WidgetSamples.live),
                        ("le lendemain", WidgetSamples.upcoming), ("équipe masquée seule", WidgetSamples.hidden),
                        ("aucune équipe", WidgetSamples.empty)]
        for size in [WidgetSize.medium, WidgetSize.mediumCompact] {
            let width = size.width - 2 * WidgetSize.homeMargin
            let available = size.height - 2 * WidgetSize.homeMargin
            let one = WidgetRender.idealHeight(MediumWidgetView(content: oneLine), width: width)
            let tall = WidgetRender.idealHeight(MediumWidgetView(content: fourLive), width: width)
            #expect(tall > one, "la mesure ne voit pas les lignes en plus (\(tall) pt contre \(one) pt)")
            for (name, content) in contents {
                let height = WidgetRender.idealHeight(MediumWidgetView(content: content), width: width)
                #expect(height <= available, "\(name) : \(height) pt dans \(available) pt (\(Int(size.width)) × \(Int(size.height)))")
            }
        }
    }

    private func expectInk(_ view: some View, _ size: CGSize, _ label: String,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        let ratio = WidgetRender.inkRatio(view, size: size)
        #expect(ratio > Self.minimumInk, "\(label) : \(ratio) de pixels dessinés", sourceLocation: sourceLocation)
    }
}

/// Les exemples des planches et de la galerie couvrent chaque état : direct, masqué, à venir, caché, rien.
struct WidgetSampleTests {
    @Test func samplesCoverEveryState() {
        #expect(WidgetSamples.live.lines.map(\.matchId) == [SampleData.kcMatchId, SampleData.t1MatchId, "m-gen-fur", "m-kc-blg"])
        #expect(WidgetSamples.live.headline?.status == .live(score: [1, 0], gameNumber: 2))
        #expect(WidgetSamples.maskedLive.headline?.isMasked == true)
        #expect(WidgetSamples.upcoming.lines.map(\.matchId) == ["m-gen-fur", "m-kc-blg"])
        #expect(WidgetSamples.upcoming.headline?.matchId == "m-gen-fur")
        #expect(WidgetSamples.upcoming.team(id: "t1")?.next == .hidden)
        #expect(WidgetSamples.hidden.lines.isEmpty)
        #expect(WidgetSamples.hidden.teams.map(\.next) == [.hidden])
        #expect(WidgetSamples.empty.teams.isEmpty)
    }

    /// Le moyen widget de l'exemple en direct montre quatre lignes ; le lendemain, deux matchs puis la ligne masquée de T1.
    @Test func theMediumSamplesFillTheirRows() {
        #expect(WidgetText.mediumRows(WidgetSamples.live).map(\.id)
                == [SampleData.kcMatchId, SampleData.t1MatchId, "m-gen-fur", "m-kc-blg"])
        #expect(WidgetText.mediumRows(WidgetSamples.upcoming).map(\.id) == ["m-gen-fur", "m-kc-blg", "hidden-t1"])
        #expect(WidgetText.mediumRows(WidgetSamples.hidden).map(\.id) == ["hidden-t1"])
        #expect(WidgetText.mediumRows(WidgetSamples.empty).isEmpty)
    }
}
