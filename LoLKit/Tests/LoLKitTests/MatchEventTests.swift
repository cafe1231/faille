import Foundation
import Testing
@testable import LoLKit

@Suite struct MatchEventTests {
    @Test func decodesSchedule() throws {
        let events = try JSONDecoder.lolesports()
            .decode(ScheduleResponse.self, from: Fixture.data("getSchedule")).data.schedule.events.elements
        #expect(events.count == 6)

        let first = events[0]
        #expect(first.id == "115548681803406303")
        #expect(first.startTime == date("2026-09-06T15:00:00Z"))
        #expect(first.state == .completed)
        #expect(first.league.slug == "lec")
        #expect(first.bestOf == 5)
        #expect(first.match.teams.map(\.code) == ["KC", "G2"])
        #expect(first.match.teams.map(\.gameWins) == [1, 3])
        #expect(first.match.teams[0].id == nil)
        #expect(first.match.teams[0].name == "Karmine Corp")

        let worlds = events[3]
        #expect(worlds.state == .unstarted)
        #expect(worlds.league.name == "Mondial")
        #expect(worlds.blockName == "Play-ins")
        #expect(worlds.match.teams.map(\.code) == ["C9", "KC"])

        #expect(events[5].match.teams.allSatisfy { $0.isPlaceholder })
    }

    @Test func decodesLive() throws {
        let events = try JSONDecoder.lolesports()
            .decode(ScheduleResponse.self, from: Fixture.data("getLive")).data.schedule.events.elements
        let live = try #require(events.first)
        #expect(events.count == 1)
        #expect(live.id == "117133830110912111")
        #expect(live.state == .inProgress)
        #expect(live.statsDisabled)
        #expect(live.match.teams.map(\.id) == ["105505619546859895", "99566404846951820"])
        let games = try #require(live.match.games)
        #expect(games.count == 5)
        #expect(games[0].id == "117133830110912112")
        #expect(games[0].state == .inProgress)
        #expect(games[1].state == .unstarted)
    }

    @Test func decodesEventDetails() throws {
        let details = try JSONDecoder.lolesports()
            .decode(EventDetailsResponse.self, from: Fixture.data("getEventDetails")).data.event
        #expect(details.id == "115565004607949429")
        #expect(details.bestOf == 5)
        #expect(details.match.teams.map(\.code) == ["TLAW", "LYON"])
        #expect(details.match.teams.map(\.gameWins) == [3, 1])
        #expect(details.match.games[0].teams?.first == GameRef.Side(id: "98926509885559666", side: "blue"))
        #expect(details.match.games[4].state == .unneeded)
    }

    @Test func toleratesUnknownStatesAndNonMatchEvents() throws {
        let json = #"""
        {"data":{"schedule":{"events":[
          {"startTime":"2026-10-15T18:00:00Z","state":"postponed","type":"match","league":{"slug":"worlds","name":"Mondial"},
           "match":{"id":"1","teams":[{"name":"A","code":"A"},{"name":"B","code":"B"}],"strategy":{"type":"bestOf","count":3}}},
          {"startTime":"2026-10-15T20:00:00Z","state":"unstarted","type":"show","league":{"slug":"worlds","name":"Mondial"}}
        ]}}}
        """#
        let events = try JSONDecoder.lolesports()
            .decode(ScheduleResponse.self, from: Data(json.utf8)).data.schedule.events.elements
        #expect(events.count == 1)
        #expect(events[0].state == .unknown)
        #expect(events[0].bestOf == 3)
        #expect(events[0].statsDisabled == false)
    }
}
