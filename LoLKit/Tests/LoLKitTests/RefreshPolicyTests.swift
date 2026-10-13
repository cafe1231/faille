import Foundation
import Testing
@testable import LoLKit

@Suite struct RefreshPolicyTests {
    private let now = date("2026-10-15T12:00:00Z")

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    /// Tout a réussi il y a `seconds` secondes, calendrier demandé avec les bonnes ligues.
    private func fresh(_ seconds: TimeInterval = 5) -> RefreshInput {
        let dates = Dictionary(uniqueKeysWithValues: DataKind.allCases.map { ($0, ago(seconds)) })
        return RefreshInput(now: now, lastSuccess: dates, lastAttempt: dates, scheduleLeagueIds: ["1"], wantedLeagueIds: ["1"])
    }

    @Test func emptyStateFetchesEverythingButScheduleWithoutLeagues() {
        #expect(RefreshPolicy.due(RefreshInput(now: now)) == [.leagues, .teams, .live])
        #expect(RefreshPolicy.due(RefreshInput(now: now, wantedLeagueIds: ["1"])) == [.leagues, .teams, .schedule, .live])
    }

    @Test func freshDataIsNotRefetched() {
        #expect(RefreshPolicy.due(fresh()).isEmpty)
    }

    @Test func eachKindHasItsInterval() {
        var input = fresh()
        input.lastSuccess = [.leagues: ago(23 * 3600), .teams: ago(25 * 3600), .schedule: ago(31 * 60), .live: ago(61)]
        input.lastAttempt = input.lastSuccess
        #expect(RefreshPolicy.due(input) == [.teams, .schedule, .live])

        input.lastSuccess = [.leagues: ago(23 * 3600), .teams: ago(23 * 3600), .schedule: ago(29 * 60), .live: ago(59)]
        input.lastAttempt = input.lastSuccess
        #expect(RefreshPolicy.due(input).isEmpty)
    }

    @Test func openingForcesScheduleAndLiveButNotTwiceInARow() {
        var input = fresh(20)
        input.opening = true
        #expect(RefreshPolicy.due(input) == [.schedule, .live])

        input = fresh(5)
        input.opening = true
        #expect(RefreshPolicy.due(input).isEmpty)
    }

    @Test func newLeaguesOrAMatchLeavingLiveForceTheSchedule() {
        var input = fresh(20)
        input.wantedLeagueIds = ["1", "2"]
        #expect(RefreshPolicy.due(input) == [.schedule])
        input.scheduleLeagueIds = ["2", "1"]
        #expect(RefreshPolicy.due(input).isEmpty)
        input.matchLeftLive = true
        #expect(RefreshPolicy.due(input) == [.schedule])
    }

    @Test func failedAttemptWaitsTheRetryDelay() {
        var input = fresh()
        input.lastSuccess[.live] = ago(120)
        input.lastAttempt[.live] = ago(30)
        #expect(RefreshPolicy.due(input).isEmpty)
        input.lastAttempt[.live] = ago(61)
        #expect(RefreshPolicy.due(input) == [.live])
    }

    @Test func clockMovedBackRefetches() {
        var input = fresh()
        input.lastSuccess[.live] = now.addingTimeInterval(3600)
        input.lastAttempt[.live] = now.addingTimeInterval(3600)
        #expect(RefreshPolicy.due(input) == [.live])
    }

    @Test func futureSuccessStillWaitsRetryDelayAfterFailure() {
        var input = fresh()
        input.lastSuccess[.live] = now.addingTimeInterval(3600)
        input.lastAttempt[.live] = ago(30)
        input.lastSuccess[.leagues] = now.addingTimeInterval(3600)
        input.lastAttempt[.leagues] = ago(30)
        #expect(!RefreshPolicy.due(input).contains(.live))
        #expect(!RefreshPolicy.due(input).contains(.leagues))
        input.lastAttempt[.live] = ago(61)
        #expect(RefreshPolicy.due(input).contains(.live))
    }

    @Test func leftLiveDetectsDisappearedMatches() {
        let a = makeEvent(id: "a", state: .inProgress, teams: [makeTeam("KC"), makeTeam("G2")])
        let b = makeEvent(id: "b", state: .inProgress, teams: [makeTeam("T1"), makeTeam("GEN")])
        #expect(!RefreshPolicy.leftLive(previous: nil, current: [a]))
        #expect(RefreshPolicy.leftLive(previous: [a, b], current: [a]))
        #expect(!RefreshPolicy.leftLive(previous: [a], current: [a, b]))
    }

    @Test func cachedLiveIsTrustedForTenMinutes() {
        let event = makeEvent(id: "a", state: .inProgress, teams: [makeTeam("KC"), makeTeam("G2")])
        #expect(RefreshPolicy.usableLive(Cached(value: [event], fetchedAt: ago(5 * 60)), now: now) == [event])
        #expect(RefreshPolicy.usableLive(Cached(value: [event], fetchedAt: ago(11 * 60)), now: now) == nil)
        #expect(RefreshPolicy.usableLive(Cached(value: [event], fetchedAt: now.addingTimeInterval(120)), now: now) == nil)
        #expect(RefreshPolicy.usableLive(nil, now: now) == nil)
    }
}
