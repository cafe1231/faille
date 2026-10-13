import Foundation
import Testing
@testable import LoLKit

@Suite struct CacheTests {
    @Test func scheduleRoundTripsThroughDefaultJSON() throws {
        let events = [
            makeEvent(id: "1", state: .completed, teams: [makeTeam("KC", wins: 3), makeTeam("G2", wins: 1)]),
            makeEvent(id: "2", state: .inProgress, teams: [makeTeam("T1", id: "t1"), makeTeam("GEN", id: "gen")],
                      games: [GameRef(number: 1, id: "g1", state: .inProgress, teams: [GameRef.Side(id: "t1", side: "blue")])],
                      statsDisabled: true),
        ]
        let cached = Cached(value: SchedulePage(leagueIds: ["98767975604431411"], events: events),
                            fetchedAt: date("2026-10-15T12:00:00Z"))
        let decoded = try JSONDecoder().decode(Cached<SchedulePage>.self, from: JSONEncoder().encode(cached))
        #expect(decoded == cached)
        let live = try #require(decoded.value.events.last)
        #expect(live.statsDisabled)
        #expect(live.match.games?.first?.state == .inProgress)
    }

    @Test func catalogRoundTripsThroughDefaultJSON() throws {
        let leagues = [League(id: "1", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1)]
        let teams = [Team(id: "kc", slug: "karmine-corp", name: "Karmine Corp", code: "KC", image: "http://kc.png",
                          status: "active", homeLeague: Team.HomeLeague(name: "LEC", region: "EMEA"))]
        let at = date("2026-10-15T12:00:00Z")
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        #expect(try decoder.decode(Cached<[League]>.self, from: encoder.encode(Cached(value: leagues, fetchedAt: at))).value == leagues)
        #expect(try decoder.decode(Cached<[Team]>.self, from: encoder.encode(Cached(value: teams, fetchedAt: at))).value == teams)
    }

    @Test func ageCountsFromFetchDate() {
        let cached = Cached(value: [String](), fetchedAt: date("2026-10-15T12:00:00Z"))
        #expect(cached.age(now: date("2026-10-15T12:01:30Z")) == 90)
        #expect(cached.age(now: date("2026-10-15T11:59:00Z")) == -60)
    }

    @Test func unreadableCacheThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Cached<SchedulePage>.self, from: Data(#"{"value":1}"#.utf8))
        }
    }
}
