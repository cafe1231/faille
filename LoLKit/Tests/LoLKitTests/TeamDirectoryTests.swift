import Foundation
import Testing
@testable import LoLKit

@Suite struct TeamDirectoryTests {
    private func team(_ code: String, _ name: String, home: String? = nil, status: String = "active") -> Team {
        Team(id: code.lowercased(), slug: code.lowercased(), name: name, code: code, image: nil, status: status,
             homeLeague: home.map { Team.HomeLeague(name: $0) })
    }

    private func league(_ slug: String, _ name: String, priority: Int? = 1) -> League {
        League(id: slug, slug: slug, name: name, region: nil, image: nil, priority: priority)
    }

    private var catalog: [Team] {
        [
            team("KC", "Karmine Corp", home: "LEC"),
            team("KCB", "Karmine Corp Blue", home: "La Ligue Française"),
            team("SLY", "Solary", home: "La Ligue Française"),
            team("LGN", "Légion", home: "La Ligue Française"),
            team("G2", "G2 Esports", home: "LEC"),
            team("FUR", "FURIA"),
            team("OLD", "Karmine Old", home: "LEC", status: "archived"),
        ]
    }

    private var worldsSchedule: [MatchEvent] {
        [
            makeEvent(id: "1", state: .unstarted, teams: [makeTeam("FUR", name: "FURIA"), makeTeam("KC", name: "Karmine Corp")]),
            makeEvent(id: "2", state: .unstarted, teams: [makeTeam("TBD"), makeTeam("TBD")]),
        ]
    }

    @Test func searchRanksExactCodeThenPrefixThenContains() {
        #expect(TeamDirectory.search("kc", in: catalog).map(\.code) == ["KC", "KCB"])
        #expect(TeamDirectory.search("karmine", in: catalog).map(\.code) == ["KC", "KCB"])
        #expect(TeamDirectory.search("legion", in: catalog).map(\.code) == ["LGN"])
        #expect(TeamDirectory.search("ESPORTS", in: catalog).map(\.code) == ["G2"])
        #expect(TeamDirectory.search("  ", in: catalog).isEmpty)
        #expect(TeamDirectory.search("a", in: catalog, limit: 2).count == 2)
    }

    @Test func leagueTeamsIncludeHomeTeamsAndTeamsSeenInItsSchedule() {
        let lfl = league("lfl", "La Ligue Française")
        #expect(TeamDirectory.teams(in: lfl, catalog: catalog, schedule: []).map(\.code) == ["KCB", "LGN", "SLY"])
        let worlds = league("worlds", "Mondial")
        #expect(TeamDirectory.teams(in: worlds, catalog: catalog, schedule: worldsSchedule).map(\.code) == ["FUR", "KC"])
        #expect(TeamDirectory.teams(in: worlds, catalog: catalog, schedule: []).isEmpty)
    }

    @Test func leaguePillsSkipEmptyLeaguesAndFollowPriorityThenApiOrder() {
        let leagues = [league("worlds", "Mondial"), league("lpl", "LPL"), league("lec", "LEC", priority: 2),
                       league("lfl", "La Ligue Française")]
        #expect(TeamDirectory.leagues(leagues, catalog: catalog, schedule: worldsSchedule).map(\.slug) == ["worlds", "lfl", "lec"])
    }
}
