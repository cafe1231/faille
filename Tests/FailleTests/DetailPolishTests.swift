import Foundation
import LoLKit
import Testing
@testable import Faille

/// Finitions du Détail (lot qualité, audit pixel B-D1, B-D2, B-D5, B-D10, B-G7, D.1 « Étape 4 ») : décisions de mise en
/// page testables sans rendu (fonctions statiques de vues : acteur principal).
@MainActor
struct DetailPolishTests {
    private static let points = [
        GoldPoint(gameTime: 0, difference: 0),
        GoldPoint(gameTime: 600, difference: 1_200),
        GoldPoint(gameTime: 1_920, difference: -3_400),
    ]

    /// B-D1 : l'axe des temps s'arrête au dernier point d'une game jouée, une minute plus loin au plus en direct.
    @Test func timeAxisEndsAtTheLastPoint() {
        #expect(GoldChartData.timeDomain(Self.points, live: false) == 0...1_920)
        #expect(GoldChartData.timeDomain(Self.points, live: true) == 0...1_980)
        // Aucun point (ou un seul à zéro) : un domaine non vide, pour que Swift Charts ait une échelle.
        #expect(GoldChartData.timeDomain([], live: false) == 0...60)
        #expect(GoldChartData.timeDomain([GoldPoint(gameTime: 0, difference: 0)], live: false) == 0...60)
    }

    /// B-D2 : pas de « 0' » dans l'angle bas gauche (il touchait le libellé du bas de l'axe vertical) ; les minutes
    /// suivantes s'écrivent « 10' », « 20' ».
    @Test func timeLabelsSkipTheOrigin() {
        #expect(GoldChartData.timeLabel(0) == nil)
        #expect(GoldChartData.timeLabel(600) == "10'")
        #expect(GoldChartData.timeLabel(1_200) == "20'")
    }

    /// B-D2 : le bas de l'axe vertical porte le signe moins typographique (U+2212), jamais un trait d'union.
    @Test func goldAxisUsesTheMinusSign() {
        #expect(Format.goldDiff(-3_000) == "\u{2212}3k")
        #expect(!Format.goldDiff(-16_000).contains("-"))
    }

    /// B-D5 : un objet sans nom (catalogue absent) garde son identifiant brut, sans séparateur de milliers.
    @Test func itemFallbackNameHasNoGroupingSeparator() {
        let name = PlayerSheet.fallbackItemName(6_692)
        #expect(name.contains("6692"))
        #expect(!name.contains("6 692"))
        #expect(!name.contains("6\u{202F}692"))
        #expect(!name.contains("6,692"))
    }

    /// B-D10 : deux emplacements de sorts d'invocateur par ligne de joueur, vides quand le sort n'est pas connu.
    @Test func summonerSlotsAlwaysTwo() {
        #expect(PlayerBuildRow.spellSlots([]) == [nil, nil])
        #expect(PlayerBuildRow.spellSlots(["SummonerSmite"]) == ["SummonerSmite", nil])
        #expect(PlayerBuildRow.spellSlots(["SummonerFlash", "SummonerSmite"]) == ["SummonerFlash", "SummonerSmite"])
        #expect(PlayerBuildRow.spellSlots(["A", "B", "C"]) == ["A", "B"])
    }

    /// B-G7 et D.1 (Étape 4) : la note du bouton « Épingler » n'existe que quand iOS les a coupées ou que l'écran
    /// verrouillé est plein ; aucune note sinon.
    @Test func pinNoteOnlyWhenRefused() {
        #expect(LiveActivityPinButton.note(enabled: true, refused: nil) == nil)
        #expect(LiveActivityPinButton.note(enabled: true, refused: .pinned) == nil)
        let disabled = LiveActivityPinButton.note(enabled: false, refused: nil)
        #expect(disabled != nil)
        #expect(LiveActivityPinButton.note(enabled: true, refused: .disabled) == disabled)
        let full = LiveActivityPinButton.note(enabled: true, refused: .full)
        #expect(full != nil)
        #expect(full != disabled)
    }
}
