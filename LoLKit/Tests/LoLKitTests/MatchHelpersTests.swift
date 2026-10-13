import Foundation
import Testing
@testable import LoLKit

@Suite struct MatchHelpersTests {
    @Test func followedTeamGoesLeft() {
        let follows = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1"),
                                         FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")])
        let kcVsT1 = [makeTeam("KC", id: "kc"), makeTeam("T1", id: "t1")]
        #expect(follows.displayOrder(kcVsT1) == [1, 0])
        #expect(follows.displayOrder(kcVsT1, preferring: follows.teams[1]) == [0, 1])
        #expect(follows.displayOrder([makeTeam("G2", id: "g2"), makeTeam("KC", id: "kc")]) == [1, 0])
        #expect(follows.displayOrder([makeTeam("G2", id: "g2"), makeTeam("FNC", id: "fnc")]) == [0, 1])
        #expect(follows.displayOrder([makeTeam("G2", id: "g2")]) == [0])
    }

    @Test func detailsFromALiveEvent() throws {
        let live = try JSONDecoder.lolesports()
            .decode(ScheduleResponse.self, from: Fixture.data("getLive")).data.schedule.events.elements
        let event = try #require(live.first)
        let details = EventDetails(event: event)
        #expect(details.id == event.id)
        #expect(details.match.teams.map(\.code) == ["BRO", "LGD"])
        #expect(details.bestOf == 5)
        #expect(details.statsDisabled)
        #expect(details.currentGame?.number == 1)
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil,
                                           statsDisabled: details.statsDisabled, follows: FollowList(), revealed: [],
                                           now: date("2026-10-13T09:30:00Z"))
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 1)
        #expect(!state.statsAvailable)
    }
}
