import Foundation
import Testing
@testable import LoLKit

/// L'ordre des équipes d'une Live Activity est fixé à son démarrage ; chaque mise à jour y est ramenée (étape 4).
@Suite struct LiveActivityContentTests {
    private let tlaw = "98926509885559666"
    private let lyon = "99566405941863385"
    private let now = date("2026-10-04T20:39:30Z")

    /// Ordre de la Live Activity : TLAW, puis LYON.
    private var attributes: LiveMatchAttributes {
        LiveMatchAttributes(matchId: "115565004607949429", leagueName: "LCS", bestOf: 5,
                            teams: [.init(id: tlaw, code: "TLAW", name: "Team Liquid Alienware", colorHex: nil),
                                    .init(id: lyon, code: "LYON", name: "LYON", colorHex: nil)],
                            primaryTeamIndex: nil)
    }

    private func state(score: [Int]?, stats: [TeamStats]?) -> LiveMatchState {
        LiveMatchState(phase: .inGame, seriesScore: score, gameNumber: 2, gameClockStart: nil, gameClockStoppedAt: nil,
                       stats: stats, statsAvailable: true, spoilerFree: false, winnerCode: nil, updatedAt: now)
    }

    @Test func alignedPutsScoreAndStatsInTheActivityOrderById() {
        let source = [makeTeam("LYON", id: lyon), makeTeam("TLAW", id: tlaw)]
        let aligned = state(score: [1, 0], stats: [TeamStats(kills: 6), TeamStats(kills: 7)])
            .aligned(from: source, to: attributes)
        #expect(aligned.seriesScore == [0, 1])
        #expect(aligned.stats?.map(\.kills) == [7, 6])
    }

    @Test func scheduleTeamsWithoutIdsAreRecognisedByName() {
        let source = [makeTeam("LYON", name: "LYON"), makeTeam("TLAW", name: "Team Liquid Alienware")]
        #expect(state(score: [3, 1], stats: nil).aligned(from: source, to: attributes).seriesScore == [1, 3])
    }

    @Test func unknownTeamsLeaveTheStateUntouched() {
        let original = state(score: [1, 0], stats: nil)
        #expect(original.aligned(from: [makeTeam("X", id: "x"), makeTeam("Y", id: "y")], to: attributes) == original)
        #expect(original.aligned(from: [makeTeam("TLAW", id: tlaw)], to: attributes) == original)
    }

    @Test func aMaskedStateStaysMasked() {
        let masked = state(score: [1, 0], stats: nil).masked()
        #expect(masked.aligned(from: [makeTeam("LYON", id: lyon), makeTeam("TLAW", id: tlaw)], to: attributes) == masked)
    }

    @Test func contentFromDetailsCarriesAttributesAndTheSourceOrder() {
        let details = makeDetails(wins: [1, 0], games: [(2, "g2", .inProgress)])
        let built = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                           follows: FollowList(), revealed: [], now: now)
        let content = LiveActivityContent(details: details, state: built, follows: FollowList())
        #expect(content.teams.map(\.code) == ["TLAW", "LYON"])
        #expect(content.attributes?.teams.map(\.id) == [tlaw, lyon])
        #expect(content.state == built)
        // Calendrier : pas d'id d'équipe, donc pas d'attributs (on ne démarre jamais une Live Activity sans ids).
        let schedule = EventDetails(event: makeEvent(id: "m", state: .completed, teams: [makeTeam("KC"), makeTeam("C9")]))
        #expect(LiveActivityContent(details: schedule, state: built, follows: FollowList()).attributes == nil)
    }
}
