import Foundation
import Testing
@testable import LoLKit

@Suite struct LeagueTeamTests {
    @Test func decodesLeagues() throws {
        let leagues = try JSONDecoder.lolesports()
            .decode(LeaguesResponse.self, from: Fixture.data("getLeagues")).data.leagues.elements
        #expect(leagues.count == 51)
        #expect(leagues.first?.slug == "worlds")
        #expect(leagues.first?.name == "Mondial")
        #expect(leagues.first(where: { $0.slug == "lfl" })?.name == "La Ligue Française")
        #expect(leagues.first(where: { $0.slug == "lec" })?.id == "98767991302996019")
    }

    @Test func decodesTeams() throws {
        let teams = try JSONDecoder.lolesports()
            .decode(TeamsResponse.self, from: Fixture.data("getTeams")).data.teams.elements
        #expect(teams.count == 9)
        let kc = try #require(teams.first { $0.code == "KC" })
        #expect(kc.id == "111692118851466302")
        #expect(kc.name == "Karmine Corp")
        #expect(kc.homeLeague == Team.HomeLeague(name: "LEC", region: "EMEA"))
        #expect(kc.isActive)
        #expect(teams.first { $0.code == "TBDD" }?.isActive == false)
        #expect(teams.first { $0.code == "NXB" }?.homeLeague == nil)
        #expect(teams.first { $0.code == "SLY" }?.homeLeague?.name == "La Ligue Française")
    }

    @Test func skipsUnreadableElements() throws {
        let json = #"{"data":{"leagues":[{"id":"1","slug":"a","name":"A"},{"slug":"sans-id"},{"id":"3","slug":"c","name":"C"}]}}"#
        let leagues = try JSONDecoder.lolesports()
            .decode(LeaguesResponse.self, from: Data(json.utf8)).data.leagues.elements
        #expect(leagues.map(\.id) == ["1", "3"])
    }

    @Test func parsesAndFormatsDates() throws {
        let withFraction = try #require(LoLDate.parse("2026-10-04T20:38:29.593Z"))
        let plain = try #require(LoLDate.parse("2026-10-15T18:00:00Z"))
        #expect(plain.timeIntervalSince(withFraction) > 0)
        #expect(LoLDate.parse("pas une date") == nil)
        #expect(LoLDate.format(try #require(LoLDate.parse("2026-10-04T20:38:20Z"))) == "2026-10-04T20:38:20.000Z")
    }
}
