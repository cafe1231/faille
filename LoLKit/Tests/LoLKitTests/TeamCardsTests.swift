import Foundation
import Testing
@testable import LoLKit

@Suite struct TeamCardsTests {
    private func schedule() throws -> [MatchEvent] {
        try JSONDecoder.lolesports()
            .decode(ScheduleResponse.self, from: Fixture.data("getSchedule")).data.schedule.events.elements
    }

    private func follows(_ codes: [String]) throws -> FollowList {
        var list = FollowList()
        for code in codes { list.follow(try catalogTeam(code)) }
        return list
    }

    @Test func nextAndLastFromRealSchedule() throws {
        let cards = TeamCards.build(follows: try follows(["KC", "G2", "T1"]), schedule: try schedule(), live: [])
        #expect(cards.map(\.team.code) == ["KC", "G2", "T1"])

        let kc = cards[0]
        #expect(kc.live == nil)
        #expect(kc.next?.id == "115660588583171786")   // C9 vs KC, Mondial, 15/10
        #expect(kc.last?.id == "115548681803406327")   // KC 0-3 MKOI, 19/09

        #expect(cards[1].next == nil)
        #expect(cards[1].last?.id == "115548681803406333")  // G2 3-0 MKOI, 20/09
        #expect(cards[2].next == nil && cards[2].last == nil)
    }

    @Test func liveTeamsComeFirstInFollowOrder() throws {
        let list = try follows(["KC", "G2", "T1"])
        let t1Live = makeEvent(id: "live-t1", state: .inProgress, teams: [makeTeam("T1", id: "98767991853197861"), makeTeam("FLY", id: "x")])
        let g2Live = makeEvent(id: "live-g2", state: .inProgress, teams: [makeTeam("G2", id: "98767991926151025"), makeTeam("FUR", id: "y")])
        let cards = TeamCards.build(follows: list, schedule: try schedule(), live: [t1Live, g2Live])
        #expect(cards.map(\.team.code) == ["G2", "T1", "KC"])
        #expect(cards[0].live?.id == "live-g2")
        #expect(cards[1].live?.id == "live-t1")
    }

    @Test func liveMatchIsNotAlsoNext() throws {
        let list = try follows(["KC"])
        let kcLive = makeEvent(id: "115660588583171786", state: .inProgress,
                               teams: [makeTeam("C9", id: "98767991877340524"), makeTeam("KC", id: "111692118851466302")])
        let card = try #require(TeamCards.build(follows: list, schedule: try schedule(), live: [kcLive]).first)
        #expect(card.live?.id == "115660588583171786")
        #expect(card.next == nil)
    }

    @Test func scheduleInProgressIsUsedWhenLiveIsUnavailable() throws {
        let list = try follows(["KC"])
        let inProgress = makeEvent(id: "m", state: .inProgress, teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let card = try #require(TeamCards.build(follows: list, schedule: [inProgress], live: nil).first)
        #expect(card.live?.id == "m")
    }

    @Test func staleInProgressIsIgnoredWhenLiveIsKnown() throws {
        // `getLive` répond et ne contient pas ce match : le calendrier est périmé, le match n'est plus en direct.
        let list = try follows(["KC"])
        let inProgress = makeEvent(id: "m", state: .inProgress, teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let card = try #require(TeamCards.build(follows: list, schedule: [inProgress], live: []).first)
        #expect(card.live == nil)
        #expect(card.next == nil)
        #expect(card.last == nil)
    }

    @Test func teamsWithNextMatchAreSortedByDate() throws {
        let list = try follows(["T1", "GEN"])
        let later = makeEvent(id: "a", state: .unstarted, start: "2026-10-20T10:00:00Z", teams: [makeTeam("T1", name: "T1"), makeTeam("X")])
        let sooner = makeEvent(id: "b", state: .unstarted, start: "2026-10-16T10:00:00Z", teams: [makeTeam("GEN", name: "Gen.G Esports"), makeTeam("Y")])
        #expect(TeamCards.build(follows: list, schedule: [later, sooner], live: []).map(\.team.code) == ["GEN", "T1"])
    }
}
