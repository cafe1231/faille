import Foundation
import LoLKit
import Testing
@testable import Faille

/// Textes des tableaux (spec saison §3.5).
struct StandingsTests {
    @Test func roundNames() {
        #expect(StandingsTexts.roundName(.quarterFinal) == "Quarts de finale")
        #expect(StandingsTexts.roundName(.final) == "Finale")
    }

    @Test func placeholderTeamsAreToBeDetermined() {
        let tbd = MatchTeam(id: "0", name: "TBD", code: "TBD", image: nil, result: nil)
        let kc = MatchTeam(id: "kc", name: "Karmine Corp", code: "KC", image: nil, result: nil)
        #expect(StandingsTexts.teamLabel(tbd) == "À déterminer")
        #expect(StandingsTexts.teamLabel(kc) == "KC")
    }
}

/// Masquage d'un classement et révélation (qui ne révèle aucun match), sur la saison d'exemple.
@Suite(.serialized)
@MainActor
struct StandingsMaskingWiringTests {
    @Test func worldsStandingsAreMaskedUntilRevealedAndLecIsNot() {
        let store = AppStore(preview: .withSeason)
        #expect(store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.lecSplit3.id))
        store.revealStandings(tournamentId: SeasonSamples.worlds.id)
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        #expect(store.seasonMasked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"]) // aucun match révélé
    }
}
