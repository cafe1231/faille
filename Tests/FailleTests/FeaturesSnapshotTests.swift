import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func featureDetail(_ matchId: String) -> some View {
        NavigationStack { MatchDetailView(matchId: matchId) }.environment(AppStore(preview: .standard))
    }

    /// Détail d'un match en direct révélé (spec fonctionnalités §1, §3-§5) : « Regarder », draft, stats, courbe de gold,
    /// joueurs avec icônes, objets et runes (vignettes de repli : aucun réseau), fil de la game. Trois captures : haut,
    /// milieu, bas.
    @Test func detailLiveWithFeatures() async throws {
        let top = try await Snapshot.write(featureDetail(SampleData.kcMatchId), named: "21-detail-direct")
        expectNotBlank(top)
        let middle = try await Snapshot.write(featureDetail(SampleData.kcMatchId).defaultScrollAnchor(.center),
                                              named: "21-detail-direct-milieu")
        expectNotBlank(middle)
        let bottom = try await Snapshot.write(featureDetail(SampleData.kcMatchId).defaultScrollAnchor(.bottom),
                                              named: "21-detail-direct-bas")
        expectNotBlank(bottom)
    }

    /// Détail d'un match terminé (KC 1 – 3 G2, game 4) : « Revoir la game 4 », draft, courbe sous zéro (G2 a gagné),
    /// joueurs avec leurs sorts d'invocateur (Leaguepedia), fil complet.
    @Test func detailFinishedWithFeatures() async throws {
        let top = try await Snapshot.write(featureDetail(SampleData.kcG2MatchId), named: "22-detail-termine")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(featureDetail(SampleData.kcG2MatchId).defaultScrollAnchor(.bottom),
                                              named: "22-detail-termine-bas")
        expectNotBlank(bottom)
    }

    /// Fiche du jungler de G2 (game 4 terminée) : sorts d'invocateur de Leaguepedia, ordre des sorts, part des dégâts.
    @Test func playerSheetOfAFinishedGame() async throws {
        let store = AppStore(preview: .standard)
        let game = try #require(store.details[SampleData.kcG2MatchId]?.match.games.first { $0.number == 4 })
        let rows = PlayerBuilds.rows(snapshot: SampleData.kcG2Final, details: store.gameDetails.details[game.id],
                                     teamId: "g2")
        let item = PlayerSheetItem(player: rows[1], teamCode: "G2", tint: nil,
                                   context: PlayersSection.context(store: store, game: game), finished: true)
        let url = try await Snapshot.write(PlayerSheet(item: item).environment(\.dataDragon, store.dataDragon),
                                           named: "23-fiche-joueur")
        expectNotBlank(url)
    }

    /// Carte de KC en direct avec sa pastille « Regarder » (spec fonctionnalités §1).
    @Test func cardWithWatchButton() async throws {
        let store = AppStore(preview: .standard)
        let card = try #require(store.cards.first { $0.team.id == "kc" })
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Carte", subtitle: "En direct · Regarder")
                TeamCardView(card: card)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .environment(store)
        let url = try await Snapshot.write(board, named: "24-carte-regarder")
        expectNotBlank(url)
    }
}
