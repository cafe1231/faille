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

    /// W5 : un tableau révélé n'affiche pas le score d'un match encore masqué ailleurs (« vs »), seulement ceux qui ne
    /// le sont pas ou qui sont révélés.
    @Test func aRevealedBracketHidesTheScoreOfAMaskedMatch() {
        func team(_ id: String, _ wins: Int) -> MatchTeam {
            MatchTeam(id: id, name: id, code: id.uppercased(), image: nil, result: .init(outcome: nil, gameWins: wins))
        }
        let follows = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)])
        let masked = BracketMatch(id: "m1", state: .completed, teams: [team("t1", 3), team("blg", 1)])
        let open = BracketMatch(id: "m2", state: .completed, teams: [team("kc", 3), team("blg", 1)])
        #expect(!BracketMatchRow.showsScore(masked, follows: follows, revealed: []))
        #expect(BracketMatchRow.showsScore(masked, follows: follows, revealed: ["m1"]))
        #expect(BracketMatchRow.showsScore(open, follows: follows, revealed: []))
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
