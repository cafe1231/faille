import Foundation
import Testing
@testable import LoLKit

/// Pièces de texte des cartes, déplacées de l'appli vers LoLKit à l'étape 3 (les widgets les réutilisent).
@Suite struct CardTextTests {
    @Test func reorderFollowsTheDisplayOrder() {
        #expect(reorder(["C9", "KC"], [1, 0]) == ["KC", "C9"])
        #expect(reorder([0, 1], [1, 0]) == [1, 0])
        #expect(reorder(["KC"], [0, 1]) == nil)          // tailles différentes
        #expect(reorder(["KC", "C9"], [0, 2]) == nil)    // index hors du tableau
    }

    /// Spec §8 : un match masqué n'affiche que son état ; entre deux games, il reste « En direct ».
    @Test func maskedStatusIsOnlyTheState() {
        #expect(Format.maskedStatus(.inGame) == "En direct")
        #expect(Format.maskedStatus(.betweenGames) == "En direct")
        #expect(Format.maskedStatus(.finished) == "Terminé")
        #expect(Format.maskedStatus(.upcoming) == "À venir")
    }

    private func finished(score: [Int]?, masked: Bool) -> ScoreLine {
        ScoreLine(matchId: "m", leagueName: "Mondial", bestOf: 5, teamCodes: ["HLE", "GEN"], score: score,
                  status: .finished(winnerCode: masked ? nil : "GEN"), isMasked: masked)
    }

    @Test func lastRowPutsTheCardTeamOnTheLeftWithItsScore() {
        #expect(Format.lastRow(finished(score: [0, 3], masked: false), order: [1, 0], date: "DATE")
                == "Dernier · GEN 3 – 0 HLE")
        #expect(Format.lastRow(finished(score: [0, 3], masked: false), order: [0, 1], date: "DATE")
                == "Dernier · HLE 0 – 3 GEN")
    }

    @Test func maskedLastRowHasNoResultButTheDate() {
        let text = Format.lastRow(finished(score: nil, masked: true), order: [1, 0], date: "sam. 11 oct. · 09:00")
        #expect(text == "Dernier · GEN vs HLE · Terminé · sam. 11 oct. · 09:00")
        #expect(!text.contains("–"))
    }
}
