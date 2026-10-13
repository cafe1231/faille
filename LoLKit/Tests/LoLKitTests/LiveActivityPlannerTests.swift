import Testing
@testable import LoLKit

@Suite struct LiveActivityPlannerTests {
    private func follows() throws -> FollowList {
        var list = FollowList()
        for code in ["KC", "T1", "GEN"] { list.follow(try catalogTeam(code)) }
        return list
    }

    private let gen = makeEvent(id: "gen", state: .inProgress, teams: [makeTeam("GEN", id: "100205573495116443"), makeTeam("X", id: "x")])
    private let t1 = makeEvent(id: "t1", state: .inProgress, teams: [makeTeam("T1", id: "98767991853197861"), makeTeam("FLY", id: "f")])
    private let kc = makeEvent(id: "kc", state: .inProgress, teams: [makeTeam("KC", id: "111692118851466302"), makeTeam("C9", id: "c")])
    private let other = makeEvent(id: "other", state: .inProgress, teams: [makeTeam("BRO", id: "b"), makeTeam("LGD", id: "l")])

    @Test func automaticFollowsFollowOrder() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, other], follows: try follows(), mode: .automatic, pinned: [], dismissed: [])
        #expect(plan == ["kc", "t1", "gen"])
    }

    @Test func dismissedMatchesAreNotRecreated() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc], follows: try follows(), mode: .automatic, pinned: [], dismissed: ["t1"])
        #expect(plan == ["kc", "gen"])
    }

    @Test func pinnedComeFirstAndCountTowardsTheLimit() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, other], follows: try follows(), mode: .automatic, pinned: ["other"], dismissed: [])
        #expect(plan == ["other", "kc", "t1"])
    }

    @Test func manualOnlyKeepsLivePinned() throws {
        let list = try follows()
        #expect(LiveActivityPlanner.plan(live: [gen, t1], follows: list, mode: .manual, pinned: ["gen", "fini"], dismissed: []) == ["gen"])
        #expect(LiveActivityPlanner.plan(live: [gen, t1], follows: list, mode: .manual, pinned: [], dismissed: []).isEmpty)
    }

    @Test func neverMoreThanThree() throws {
        let both = makeEvent(id: "both", state: .inProgress, teams: [makeTeam("T1", id: "98767991853197861"), makeTeam("GEN", id: "100205573495116443")])
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, both], follows: try follows(), mode: .automatic, pinned: [], dismissed: [])
        #expect(plan.count == LiveActivityPlanner.maxConcurrent)
        #expect(plan == ["kc", "t1", "both"])
    }
}
