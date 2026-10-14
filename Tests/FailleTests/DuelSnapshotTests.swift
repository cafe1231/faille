import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Duel libre Caps – Canna (spec saison §3.3) : barres en miroir, champions favoris (vignettes de repli).
    @Test func playerDuel() async throws {
        let view = NavigationStack { DuelView(left: .player("p-canna"), right: .player("p-caps")) }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        let url = try await Snapshot.write(view, named: "27-duel")
        expectNotBlank(url)
    }

    /// Duel du match T1 – FLY (masqué : T1 en anti-spoiler) : effectifs du catalogue, stats de saison sans les matchs
    /// masqués (« — »), aucune ligne « Cette game ».
    @Test func duelOfAMaskedMatch() async throws {
        let view = NavigationStack {
            ScrollView {
                DuelSection(matchId: SampleData.t1MatchId, teams: SampleData.t1Live.match.teams, selectedGameId: nil,
                            masked: true)
                    .padding(16)
            }
            .abyssBackground()
        }
        .environment(AppStore(preview: .withSeason))
        let url = try await Snapshot.write(view, named: "27b-duel-masque")
        expectNotBlank(url)
    }
}
