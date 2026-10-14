import Foundation
import Testing
@testable import LoLKit

/// Duels de joueurs (spec saison §3.3) : composition poste par poste et barres en miroir.
@Suite struct DuelTests {
    private func kcCatalog() throws -> [Team] {
        try JSONDecoder.lolesports().decode(TeamsResponse.self, from: SeasonFixture.data("getTeams_karmine-corp"))
            .data.teams.elements
    }

    /// Effectif du catalogue, dans l'ordre des postes (le catalogue liste « bottom » avant « mid »).
    @Test func lineupFollowsTheRolesOrder() throws {
        let slots = Duel.lineup(teamId: SeasonFixture.kc, catalog: try kcCatalog(), games: [])
        #expect(slots.map(\.role) == Duel.roles)
        #expect(slots.map(\.name) == ["Canna", "Yike", "kyeahoo", "Caliste", "Busio"])
        #expect(slots[0].playerId == "103495716771322725")
        #expect(slots[0].image == "http://static.lolesports.com/players/1774651372836_canna.png")
    }

    /// Deux joueurs au même poste : celui qui a le plus de games ; à égalité le premier listé.
    @Test func substituteWithMoreGamesIsChosen() throws {
        let game = try SeasonFixture.summary304()
        let roster = [TeamPlayer(id: "sub", summonerName: "Remplaçant", image: nil, role: "top"),
                      TeamPlayer(id: "103495716771322725", summonerName: "Canna", image: nil, role: "top")]
        let team = Team(id: SeasonFixture.kc, slug: "karmine-corp", name: "Karmine Corp", code: "KC", image: nil,
                        status: "active", homeLeague: nil, players: roster)
        #expect(Duel.lineup(teamId: SeasonFixture.kc, catalog: [team], games: [game])[0].name == "Canna")
        #expect(Duel.lineup(teamId: SeasonFixture.kc, catalog: [team], games: [])[0].name == "Remplaçant")
    }

    /// Sans effectif au catalogue : la composition de la game la plus récente (noms bruts du flux).
    @Test func lineupFallsBackToTheLatestGame() throws {
        let slots = Duel.lineup(teamId: SeasonFixture.g2, catalog: try kcCatalog(), games: [try SeasonFixture.summary304()])
        #expect(slots.map(\.name) == ["G2 BrokenBlade", "G2 SkewMond", "G2 Caps", "G2 Hans Sama", "G2 Labrov"])
        #expect(Duel.lineup(teamId: "inconnue", catalog: [], games: []).allSatisfy { $0.playerId == nil })
    }

    /// Canna contre BrokenBlade sur la game 304 : KDA 2,0 contre 4,5 ; part des dégâts 22,78 % contre 12,19 %.
    @Test func mirroredBars() throws {
        let game = try SeasonFixture.summary304()
        let duel = Duel.players(left: "103495716771322725", right: "99566406047571736", games: [game], masked: [])
        #expect(duel.left?.name == "KC Canna")
        #expect(duel.right?.name == "G2 BrokenBlade")
        #expect(duel.bars.map(\.metric) == DuelMetric.allCases)
        let kda = duel.bars[0]
        #expect(kda.left == 2 && kda.right == 4.5)
        #expect(abs(kda.leftRatio - 2 / 4.5) < 1e-9 && kda.rightRatio == 1)
        let damage = try #require(duel.bars.first { $0.metric == .damageShare })
        #expect(damage.left == 0.2278 && damage.right == 0.1219)
        #expect(damage.leftRatio == 1)
        let participation = try #require(duel.bars.first { $0.metric == .killParticipation })
        #expect(abs((participation.right ?? 0) - 9.0 / 23.0) < 1e-9)
    }

    /// Match masqué : aucune stat de ce match (ici la seule game) → « — » des deux côtés, barres vides.
    @Test func maskedGamesGiveNoBars() throws {
        let game = try SeasonFixture.summary304()
        let duel = Duel.players(left: "103495716771322725", right: "99566406047571736", games: [game],
                                masked: [SeasonFixture.match303])
        #expect(duel.left == nil && duel.right == nil)
        #expect(duel.bars.allSatisfy { $0.left == nil && $0.right == nil && $0.leftRatio == 0 && $0.rightRatio == 0 })
        // Palier A : part des dégâts « — », les autres barres restent.
        let tierA = Duel.players(left: "103495716771322725", right: "99566406047571736",
                                 games: [try SeasonFixture.summary304(enriched: false)], masked: [])
        let damage = try #require(tierA.bars.first { $0.metric == .damageShare })
        #expect(damage.left == nil && damage.right == nil && damage.leftRatio == 0)
        #expect(tierA.bars[0].left == 2)
    }
}
