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

    // MARK: Live Activities déjà à l'écran (étape 4)

    @Test func existingActivitiesKeepTheirPlaceAndCountTowardsTheLimit() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, other], follows: try follows(), mode: .automatic,
                                            pinned: [], dismissed: [], active: ["other"])
        #expect(plan == ["other", "kc", "t1"])
    }

    @Test func aFinishedMatchStillOnScreenTakesASlot() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc], follows: try follows(), mode: .automatic,
                                            pinned: [], dismissed: [], active: ["fini"])
        #expect(plan == ["fini", "kc", "t1"])
    }

    @Test func nothingNewWhenThreeAreAlreadyShown() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc], follows: try follows(), mode: .automatic,
                                            pinned: ["kc"], dismissed: [], active: ["a", "b", "c"])
        #expect(plan == ["a", "b", "c"])
    }

    @Test func pinnedGetTheFreeSlotsBeforeAutomatic() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, other], follows: try follows(), mode: .automatic,
                                            pinned: ["other"], dismissed: [], active: ["kc"])
        #expect(plan == ["kc", "other", "t1"])
    }

    @Test func manualModeOnlyAddsLivePinnedNextToExistingOnes() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1], follows: try follows(), mode: .manual,
                                            pinned: ["gen"], dismissed: [], active: ["t1"])
        #expect(plan == ["t1", "gen"])
    }

    /// Spec §6.4 : réveil en arrière-plan toutes les 15 min tant qu'un match suivi est en direct (ou qu'une Live
    /// Activity est à l'écran, pour la terminer).
    @Test func backgroundRefreshOnlyWhileAFollowedMatchIsLiveOrAnActivityIsShown() throws {
        let now = date("2026-10-15T17:00:00Z")
        let list = try follows()
        let soon = now.addingTimeInterval(LiveActivityPlanner.backgroundInterval)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: [kc], follows: list, hasActivities: false) == soon)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: [other], follows: list, hasActivities: false) == nil)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: [other], follows: list, hasActivities: true) == soon)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: nil, follows: list, hasActivities: false) == nil)
        #expect(LiveActivityPlanner.backgroundInterval == 900)
    }
}
