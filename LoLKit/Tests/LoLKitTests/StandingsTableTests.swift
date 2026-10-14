import Foundation
import Testing
@testable import LoLKit

/// Classements et tableaux (spec saison §3.5) sur de vraies réponses `getStandings` : LEC Split 3, Mondial 2025
/// (terminé) et Mondial 2026 (pas commencé) ; masquage anti-spoiler.
@Suite struct StandingsTableTests {
    private static let lec3 = "115548681802226458"
    private static let worlds25 = "113475452383887518"
    private static let worlds26 = "115660540725177488"
    private static let t1 = "98767991853197861"

    private func standings(_ name: String) throws -> Standings {
        try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(name))
            .data.standings.elements[0]
    }

    @Test func leagueTableAndPlayoffs() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_lec3_reduced"))
        #expect(stages.map(\.slug) == ["regular_season", "playoffs"])
        #expect(stages[0].name == "Saison régulière")
        guard case let .table(rows) = stages[0].content else {
            Issue.record("classement attendu")
            return
        }
        #expect(rows.map(\.ordinal) == [1, 2, 3])
        #expect(rows.map(\.team.code) == ["KC", "VIT", "G2"])
        #expect(rows.map(\.wins) == [9, 7, 6])
        #expect(rows.map(\.losses) == [0, 2, 3])
        guard case let .matches(playoffs) = stages[1].content else {
            Issue.record("liste de matchs attendue")
            return
        }
        #expect(playoffs.map(\.id) == ["115548681803406327", "115548681803406333"])
    }

    /// Suisse 2025 recalculé depuis `outcome` : KT et AL 3-0 … FNC et PSG 0-3 (33 matchs).
    @Test func worlds2025Swiss() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_worlds25_reduced"))
        #expect(stages.map(\.slug) == ["play_ins", "swiss", "knockouts"])
        guard case let .swiss(groups) = stages[1].content else {
            Issue.record("système suisse attendu")
            return
        }
        #expect(groups.map(\.record) == ["3-0", "3-1", "3-2", "2-3", "1-3", "0-3"])
        #expect(groups.map { $0.teams.map(\.code) } == [["AL", "KT"], ["G2", "GEN", "HLE"], ["CFO", "T1", "TES"],
                                                       ["BLG", "FLY", "MKOI"], ["100T", "TSW", "VKS"], ["FNC", "PSG"]])
        #expect(groups.flatMap(\.teams).count == 16)
        #expect(groups.flatMap(\.teams).allSatisfy { $0.id != nil && $0.result == nil })
        let records = StandingsTable.swissRecords(try standings("getStandings_worlds25_reduced").stages[1].sections[0].matches)
        #expect(records.first { $0.team.code == "KT" }.map { [$0.wins, $0.losses] } == [3, 0])
    }

    /// Phase finale 2025 : quarts [0-3], demies [4] = vainqueurs de [0] et [1] (T1 contre TES), [5], finale [6].
    @Test func worlds2025Bracket() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_worlds25_reduced"))
        guard case let .bracket(rounds) = stages[2].content else {
            Issue.record("tableau attendu")
            return
        }
        #expect(rounds.map(\.kind) == [.quarterFinal, .semiFinal, .final])
        #expect(rounds.map(\.matches.count) == [4, 2, 1])
        #expect(Set(rounds[1].matches[0].teams.map(\.code)) == ["T1", "TES"])
        #expect(Set(rounds[1].matches[1].teams.map(\.code)) == ["KT", "GEN"])
        #expect(Set(rounds[2].matches[0].teams.map(\.code)) == ["T1", "KT"])
        // Vainqueurs des quarts [0] et [1] = équipes de la demie [4].
        let winners = rounds[0].matches[0...1].compactMap { $0.teams.first { $0.result?.outcome == "win" }?.code }
        #expect(Set(winners) == Set(rounds[1].matches[0].teams.map(\.code)))
        guard case let .matches(playIns) = stages[0].content else {
            Issue.record("liste attendue")
            return
        }
        #expect(playIns.count == 1)
    }

    /// Mondial 2026 avant son début : équipes « TBD » ignorées (aucun bilan), tableau réduit → liste de matchs.
    @Test func worlds2026BeforeItStarts() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_worlds26_reduced"))
        #expect(stages.map(\.slug) == ["play_ins", "swiss", "knockouts"])
        #expect(stages[1].content == .swiss([]))
        guard case let .matches(knockouts) = stages[2].content else {
            Issue.record("liste attendue (2 matchs seulement)")
            return
        }
        #expect(knockouts.count == 2)
        let records = StandingsTable.swissRecords(try standings("getStandings_worlds26_reduced").stages[0].sections[0].matches)
        #expect(records.map(\.team.code) == ["FUR", "MVK", "C9", "KC"])
        #expect(records.allSatisfy { $0.wins == 0 && $0.losses == 0 })
        #expect(StandingsTable.build(standings: Standings(stages: [StandingsStage(id: "vide", name: "", slug: "x",
                                                                                   sections: [])])).isEmpty)
    }

    /// Masqué si une équipe suivie en anti-spoiler y a un match terminé masqué, ou un bilan que les matchs révélés
    /// ne couvrent pas ; la révélation du classement lève le masque sans révéler de match.
    @Test func maskingFollowsTheSpoilerFreeTeams() throws {
        let lec = try standings("getStandings_lec3_reduced")
        var follows = FollowList(teams: [FollowedTeam(id: "111692118851466302", code: "KC", name: "Karmine Corp")])
        #expect(!StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: [],
                                           revealedStandings: []))
        follows.setSpoilerFree(true, id: "111692118851466302")
        #expect(StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: [],
                                          revealedStandings: []))
        // Révéler son match de play-offs ne suffit pas : son bilan 9-0 résume 9 autres matchs.
        #expect(StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: ["115548681803406327"],
                                          revealedStandings: []))
        #expect(!StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: [],
                                           revealedStandings: [Self.lec3]))
        // Une autre équipe en anti-spoiler (T1) ne masque pas la LEC ; le Mondial 2026 (rien de joué) n'est jamais masqué.
        let other = FollowList(teams: [FollowedTeam(id: Self.t1, code: "T1", name: "T1", spoilerFree: true)])
        #expect(!StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: other, revealed: [], revealedStandings: []))
        #expect(!StandingsMasking.isMasked(try standings("getStandings_worlds26_reduced"), tournamentId: Self.worlds26,
                                           follows: follows, revealed: [], revealedStandings: []))
        // Mondial 2025 : T1 en anti-spoiler masque le tableau ; ses 9 matchs révélés le démasquent.
        let worlds = try standings("getStandings_worlds25_reduced")
        #expect(StandingsMasking.isMasked(worlds, tournamentId: Self.worlds25, follows: other, revealed: [],
                                          revealedStandings: []))
        let t1Matches = Set(worlds.allMatches.filter { $0.teams.contains { $0.id == Self.t1 } }.map(\.id))
        #expect(t1Matches.count == 9)
        #expect(!StandingsMasking.isMasked(worlds, tournamentId: Self.worlds25, follows: other, revealed: t1Matches,
                                           revealedStandings: []))
    }
}
