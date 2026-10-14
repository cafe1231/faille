import Foundation
import LoLKit
import Testing
@testable import Faille

struct DuelModelTests {
    private let catalog = [Team(id: "kc", slug: "kc", name: "KC", code: "KC", image: nil, status: "active", homeLeague: nil,
                                players: [TeamPlayer(id: "p-canna", summonerName: "Canna", image: nil, role: "top")])]

    @Test func aMaskedMatchNeverLendsItsLineupNorItsGameLine() throws {
        let game = try #require(SeasonSamples.games.first { $0.gameId == "g1-kc-g2" })
        // Match masqué : ni sa composition ni ses games (l'appelant passe les games sans les matchs masqués).
        let masked = DuelModel.lineup(teamId: "kc", game: game, masked: true, catalog: catalog, games: [], teamCode: "KC")
        #expect(masked["top"] == DuelPlayer(id: "p-canna", name: "Canna", thisGame: nil))
        #expect(masked["jungle"] == nil)
        let shown = DuelModel.lineup(teamId: "kc", game: game, masked: false, catalog: catalog, games: [game], teamCode: "KC")
        #expect(shown.count == 5)
        #expect(shown["top"]?.name == "Canna")
        #expect(shown["jungle"]?.name == "Yike") // pas au catalogue : préfixe « KC » retiré
        #expect(shown["top"]?.thisGame != nil)
    }

    @Test func pickerSearchesCatalogAndCachedGames() {
        let found = DuelModel.candidates(query: "canna", games: SeasonSamples.games, catalog: catalog)
        #expect(found.map(\.id) == ["p-canna"])
        #expect(DuelModel.candidates(query: "", games: SeasonSamples.games, catalog: catalog).count == 35)
    }
}

/// Duel d'un match masqué (spec saison §3.3) : stats de saison seulement, composition du catalogue, aucune ligne « Cette
/// game ».
@MainActor
@Suite(.serialized)
struct DuelSectionContentTests {
    @Test func aMaskedMatchShowsOnlySeasonStatsFromTheCatalogLineup() {
        let store = AppStore(preview: .withSeason)
        let lines = DuelSection.lines(store: store, teams: SampleData.t1Live.match.teams, selectedGameId: "g1-t1-blg",
                                      masked: true)
        #expect(lines.first?.left?.name == "Doran")
        #expect(lines.allSatisfy { $0.left?.thisGame == nil && $0.right?.thisGame == nil })
    }

    @Test func aRevealedPlayedGameLendsItsLineupAndItsLine() {
        let store = AppStore(preview: .withSeason)
        let teams = SampleData.kcG2Details.match.teams
        let lines = DuelSection.lines(store: store, teams: teams, selectedGameId: "g4-kc-g2", masked: false)
        #expect(lines.count == 5)
        #expect(lines.first?.left?.name == "Canna")
        #expect(lines.first?.right?.name == "BrokenBlade")
        #expect(lines.allSatisfy { $0.left?.thisGame != nil })
    }
}
