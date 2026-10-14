import Foundation
import LoLKit
import Testing
@testable import Faille

struct OnboardingModelTests {
    private static func team(_ id: String, _ name: String) -> Team {
        Team(id: id, slug: id, name: name, code: id.uppercased(), image: nil, status: "active", homeLeague: nil)
    }

    private static func side(_ id: String) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id == "0" ? "TBD" : id.uppercased(), image: nil, result: nil)
    }

    private let catalog = [team("t1", "T1"), team("kc", "Karmine Corp"), team("g2", "G2 Esports"), team("fly", "FlyQuest")]

    /// Équipes du Mondial : celles des classements (jamais l'équipe « TBD » d'id « 0 »), par nom.
    @Test func worldsTeamsComeFromTheStandings() {
        let standings = Standings(stages: [StandingsStage(id: "s", name: "Système suisse", slug: "swiss", sections: [
            StandingsSection(name: "Suisse", matches: [
                BracketMatch(id: "m1", state: .completed, teams: [Self.side("t1"), Self.side("kc")]),
                BracketMatch(id: "m2", state: .unstarted, teams: [Self.side("g2"), Self.side("0")]),
            ], rankings: []),
        ])])
        let teams = OnboardingModel.worldsTeams(catalog: catalog, worldsStandings: standings, fallback: [])
        #expect(teams.map(\.id) == ["g2", "kc", "t1"])
    }

    /// Sans classement (pas encore lu) : les équipes que l'annuaire rattache au Mondial.
    @Test func withoutStandingsTheDirectoryIsTheFallback() {
        let teams = OnboardingModel.worldsTeams(catalog: catalog, worldsStandings: nil, fallback: [catalog[3], catalog[1]])
        #expect(teams.map(\.id) == ["fly", "kc"])
    }
}
