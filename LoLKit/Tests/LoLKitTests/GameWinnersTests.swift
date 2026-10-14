import Foundation
import Testing
@testable import LoLKit

/// Vainqueur par game (spec saison §1.4) et nom affiché d'un joueur (§1.5).
@Suite struct GameWinnersTests {
    private func team(_ id: String, wins: Int) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id.uppercased(), image: nil, result: MatchTeam.Result(outcome: nil, gameWins: wins))
    }

    /// Game de test : `towersA` pour l'équipe « a » (bleue), `towersB` pour « b ».
    private func game(_ id: String, _ towersA: Int, _ towersB: Int) -> GameSummary {
        func line(_ team: String, _ towers: Int) -> TeamGameLine {
            TeamGameLine(teamId: team, kills: 0, gold: 0, towers: towers, inhibitors: 0, barons: 0, dragons: [],
                         gold15: nil, players: [])
        }
        return GameSummary(gameId: id, matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
                           startedAt: date("2026-09-06T15:00:00Z"), endedAt: date("2026-09-06T15:30:00Z"),
                           durationSeconds: 1800, result: .unknown, blue: line("a", towersA), red: line("b", towersB),
                           enriched: false)
    }

    @Test func exactRules() {
        // Bo1.
        #expect(GameWinners.assign(teams: [team("a", wins: 0), team("b", wins: 1)], playedGameIds: ["g1"], summaries: [:])
                == ["g1": GameResult(winnerTeamId: "b", basis: .exact)])
        // 2-0 : tout à « a », sans résumé.
        #expect(GameWinners.assign(teams: [team("a", wins: 2), team("b", wins: 0)], playedGameIds: ["g1", "g2"],
                                   summaries: [:])
                == ["g1": GameResult(winnerTeamId: "a", basis: .exact), "g2": GameResult(winnerTeamId: "a", basis: .exact)])
        // 2-1 : la dernière game au vainqueur de la série, même sans résumé ; les autres inconnues sans résumé.
        let partial = GameWinners.assign(teams: [team("a", wins: 2), team("b", wins: 1)], playedGameIds: ["g1", "g2", "g3"],
                                         summaries: ["g1": game("g1", 9, 2)])
        #expect(partial == ["g1": .unknown, "g2": .unknown, "g3": GameResult(winnerTeamId: "a", basis: .exact)])
    }

    @Test func inferredFromTowerMargins() {
        let teams = [team("a", wins: 2), team("b", wins: 2)]
        // « b » gagne la série (dernière game g5) ; « a » doit gagner 2 games parmi g1-g4.
        let summaries = ["g1": game("g1", 9, 2), "g2": game("g2", 1, 8), "g3": game("g3", 11, 3), "g4": game("g4", 2, 9)]
        #expect(GameWinners.assign(teams: [team("a", wins: 2), team("b", wins: 3)],
                                   playedGameIds: ["g1", "g2", "g3", "g4", "g5"], summaries: summaries)
                == ["g1": GameResult(winnerTeamId: "a", basis: .inferred), "g3": GameResult(winnerTeamId: "a", basis: .inferred),
                    "g2": GameResult(winnerTeamId: "b", basis: .inferred), "g4": GameResult(winnerTeamId: "b", basis: .inferred),
                    "g5": GameResult(winnerTeamId: "b", basis: .exact)])
        // Victoires incohérentes avec les games jouées (2-2 pour 5 games) : rien.
        #expect(GameWinners.assign(teams: teams, playedGameIds: ["g1", "g2", "g3", "g4", "g5"], summaries: summaries).isEmpty)
        // Sans id d'équipe : rien.
        let noId = MatchTeam(id: nil, name: "A", code: "A", image: nil, result: MatchTeam.Result(outcome: nil, gameWins: 1))
        #expect(GameWinners.assign(teams: [noId, team("b", wins: 0)], playedGameIds: ["g1"], summaries: [:]).isEmpty)
    }

    /// Marge trop faible (< 3 tours) ou égalité à la frontière : inconnu, jamais une estimation fragile.
    @Test func closeMarginsStayUnknown() {
        let teams = [team("a", wins: 1), team("b", wins: 2)]
        let close = ["g1": game("g1", 8, 6), "g2": game("g2", 2, 9)]
        #expect(GameWinners.assign(teams: teams, playedGameIds: ["g1", "g2", "g3"], summaries: close)
                == ["g1": .unknown, "g2": .unknown, "g3": GameResult(winnerTeamId: "b", basis: .exact)])
        let tie = ["g1": game("g1", 8, 8), "g2": game("g2", 8, 8)]
        #expect(GameWinners.assign(teams: teams, playedGameIds: ["g1", "g2", "g3"], summaries: tie)["g1"] == .unknown)
    }

    /// KC, LEC Split 3 (31 games réelles) : 21 exactes, 10 déduites, 0 inconnue, toutes cohérentes avec les séries ;
    /// la game 304 (KC 1-3 G2, game 1) est à G2, « déduit ».
    @Test func kcLecSplit3() throws {
        let rows = try SeasonFixture.kcIndex()
        var summaries = Dictionary(uniqueKeysWithValues: try SeasonFixture.kcSummaries().map { ($0.gameId, $0) })
        let byMatch = Dictionary(grouping: rows, by: \.match)
        #expect(byMatch.count == 12)
        for (_, games) in byMatch {
            let ordered = games.sorted { $0.n < $1.n }
            summaries = GameWinners.apply(teams: SeasonFixture.teams(of: ordered), playedGameIds: ordered.map(\.game),
                                          to: summaries)
        }
        let results = summaries.values.map(\.result)
        #expect(results.filter { $0.basis == .exact }.count == 21)
        #expect(results.filter { $0.basis == .inferred }.count == 10)
        #expect(results.filter { $0.basis == .unknown }.isEmpty)
        #expect(summaries[SeasonFixture.game304]?.result == GameResult(winnerTeamId: SeasonFixture.g2, basis: .inferred))
        for (_, games) in byMatch {
            let teams = SeasonFixture.teams(of: games)
            for entry in teams {
                let won = games.filter { summaries[$0.game]?.result.winnerTeamId == entry.id }.count
                #expect(won == entry.gameWins)
            }
        }
    }

    @Test func playerDisplayNameDropsOnlyTheTeamCode() {
        #expect(PlayerName.display("KC Canna", teamCode: "KC") == "Canna")
        #expect(PlayerName.display("G2 Hans Sama", teamCode: "G2") == "Hans Sama")
        #expect(PlayerName.display("Hans Sama", teamCode: "G2") == "Hans Sama")
        #expect(PlayerName.display("KCB Lucky", teamCode: "KC") == "KCB Lucky")
        #expect(PlayerName.display("KC Canna", teamCode: nil) == "KC Canna")
        #expect(PlayerName.display("KC ", teamCode: "KC") == "KC ")
    }
}
