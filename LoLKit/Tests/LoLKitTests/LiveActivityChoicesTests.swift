import Foundation
import Testing
@testable import LoLKit

/// Épinglés, retirés à la main, démarrés par l'appli (spec §6.4) ; épinglés et retirés restent disjoints.
@Suite struct LiveActivityChoicesTests {
    private let now = date("2026-10-15T17:00:00Z")

    @Test func pinAndDismissStayDisjoint() {
        var choices = LiveActivityChoices()
        choices.pin("a", now: now)
        #expect(choices.isPinned("a"))
        choices.dismiss("a", now: now)
        #expect(!choices.isPinned("a"))
        #expect(choices.dismissedIds == ["a"])
        choices.pin("a", now: now)
        #expect(choices.isPinned("a"))
        #expect(choices.dismissedIds.isEmpty)
    }

    @Test func pinnedComeInPinOrder() {
        var choices = LiveActivityChoices()
        choices.pin("b", now: now)
        choices.pin("a", now: now.addingTimeInterval(10))
        choices.pin("b", now: now.addingTimeInterval(20))   // déjà épinglé : garde sa place
        #expect(choices.pinnedIds == ["b", "a"])
    }

    @Test func activitiesThatVanishedWithoutTheAppAreDismissed() {
        var choices = LiveActivityChoices()
        choices.markStarted("a", now: now)
        choices.markStarted("b", now: now)
        choices.pin("b", now: now)
        choices.reconcile(running: ["a"], now: now.addingTimeInterval(60))
        #expect(choices.dismissedIds == ["b"])
        #expect(!choices.isPinned("b"))
        #expect(choices.started.keys.sorted() == ["a"])
    }

    @Test func endedByTheAppIsNotADismissal() {
        var choices = LiveActivityChoices()
        choices.markStarted("a", now: now)
        choices.markEnded("a")
        choices.reconcile(running: [], now: now.addingTimeInterval(60))
        #expect(choices.dismissedIds.isEmpty)
        #expect(choices.started.isEmpty)
    }

    @Test func aRecentActivityMissingFromRunningIsNotDismissedYet() {
        var choices = LiveActivityChoices()
        choices.markStarted("a", now: now)
        choices.reconcile(running: [], now: now.addingTimeInterval(10))
        #expect(choices.dismissedIds.isEmpty)
        #expect(choices.started.keys.sorted() == ["a"])
    }

    @Test func aMissingActivityStartedAMinuteAgoIsDismissed() {
        var choices = LiveActivityChoices()
        choices.markStarted("a", now: now)
        choices.reconcile(running: [], now: now.addingTimeInterval(60))
        #expect(choices.dismissedIds == ["a"])
        #expect(choices.started.isEmpty)
    }

    @Test func marksOlderThanADayAreForgotten() {
        var choices = LiveActivityChoices()
        choices.pin("old", now: now)
        choices.dismiss("gone", now: now)
        choices.markStarted("run", now: now)
        #expect(choices.pruned(now: now.addingTimeInterval(3600)) == choices)
        #expect(choices.pruned(now: now.addingTimeInterval(LiveActivityChoices.retention + 1)) == LiveActivityChoices())
    }

    @Test func decodingIsTolerant() throws {
        var choices = LiveActivityChoices()
        choices.pin("a", now: now)
        choices.dismiss("b", now: now)
        let data = try JSONEncoder().encode(choices)
        #expect(try JSONDecoder().decode(LiveActivityChoices.self, from: data) == choices)
        #expect(try JSONDecoder().decode(LiveActivityChoices.self, from: Data("{}".utf8)) == LiveActivityChoices())
        let partial = try JSONDecoder().decode(LiveActivityChoices.self,
                                               from: Data(#"{"pinned":{"a":813415300},"dismissed":"illisible"}"#.utf8))
        #expect(partial.pinnedIds == ["a"])
        #expect(partial.dismissedIds.isEmpty)
    }
}
