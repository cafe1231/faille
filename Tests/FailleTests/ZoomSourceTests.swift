import Foundation
import LoLKit
import Testing
@testable import Faille

/// Zoom carte → Détail (spec finitions §6) : l'identifiant de source réunit la carte (équipe), la ligne et le match.
@MainActor
struct ZoomSourceTests {
    /// Chaque ligne de chaque carte a sa propre source, même quand deux cartes montrent le même match (KC et C9 suivies :
    /// KC – C9 en direct sur les deux cartes).
    @Test func everyCardRowHasItsOwnSource() {
        var data = PreviewData.standard
        data.follows = FollowList(teams: SampleData.follows.teams + [
            FollowedTeam(id: "c9", code: "C9", name: "Cloud9 Kia", homeLeagueName: "LCS", autoColorHex: "#4FC3F7"),
        ])
        let store = AppStore(preview: data)
        var routes: [MatchRoute] = []
        for card in store.cards {
            if let live = card.live {
                routes.append(MatchRoute(teamId: card.team.id, row: .live, matchId: live.id))
            }
            if case let .match(next) = store.nextLine(for: card) {
                routes.append(MatchRoute(teamId: card.team.id, row: .next, matchId: next.id))
            }
            if let last = card.last {
                routes.append(MatchRoute(teamId: card.team.id, row: .last, matchId: last.id))
            }
        }
        let ids = routes.compactMap(\.sourceID)
        #expect(ids.count == routes.count)
        #expect(Set(ids).count == ids.count)
        // Le même match sur deux cartes : deux sources, une seule destination.
        let kcC9 = routes.filter { $0.matchId == SampleData.kcMatchId }
        #expect(kcC9.count == 2)
        #expect(Set(kcC9.map(\.sourceID)).count == 2)
    }

    @Test func theSourceNamesTheCardTheRowAndTheMatch() {
        let route = MatchRoute(teamId: "kc", row: .live, matchId: "m1")
        #expect(route.matchId == "m1")
        #expect(route.sourceID != MatchRoute(teamId: "c9", row: .live, matchId: "m1").sourceID)
        #expect(route.sourceID != MatchRoute(teamId: "kc", row: .last, matchId: "m1").sourceID)
        #expect(route.sourceID != MatchRoute(teamId: "kc", row: .live, matchId: "m2").sourceID)
        // Sans source : transition standard.
        #expect(MatchRoute(matchId: "m1").sourceID == nil)
    }
}
