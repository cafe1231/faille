import Foundation
import LoLKit
import Testing
@testable import Faille

private let now = SampleData.date("2026-10-15T15:05:00Z")

private func upcoming(_ id: String, _ start: String, _ a: (String, String), _ b: (String, String),
                      league: LeagueRef = SampleData.worlds) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: .unstarted, type: "match", blockName: nil, league: league,
               match: MatchInfo(id: id, teams: [MatchTeam(id: a.0, name: a.1, code: a.0.uppercased(), image: nil, result: nil),
                                                MatchTeam(id: b.0, name: b.1, code: b.0.uppercased(), image: nil, result: nil)],
                                strategy: Strategy(type: "bestOf", count: 3), games: nil),
               streams: nil)
}

struct LeagueRowsTests {
    @Test func leagueRowHidesANextMatchAgainstAMaskedSpoilerFreeTeam() {
        let lck = FollowedLeague(id: "lck-id", slug: "lck", name: "LCK")
        let league = LeagueRef(id: "lck-id", slug: "lck", name: "LCK", image: nil)
        let match = upcoming("n", "2026-10-16T08:00:00Z", ("t1", "T1"), ("hle", "HLE"), league: league)
        let follows = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)], leagues: [lck])
        let hidden = LeagueRows.rows(follows: follows, schedule: [match], revealed: [], maskedLatestTeamIds: ["t1"],
                                     currentTournamentIds: [:], now: now)
        #expect(hidden.map(\.next) == [.hidden])
        let shown = LeagueRows.rows(follows: follows, schedule: [match], revealed: [], maskedLatestTeamIds: [],
                                    currentTournamentIds: ["lck-id": "t-lck"], now: now)
        #expect(shown.map(\.next) == [.match(match)])
        #expect(shown.first?.tournamentId == "t-lck")
    }
}
