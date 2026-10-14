import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Draft, section « Joueurs » enrichie et fiche d'un joueur (spec fonctionnalités §3), sur la game d'exemple avec ses
    /// détails d'exemple ; sans version Data Dragon : vignettes de repli (aucun réseau). Le jungler montre son Châtiment.
    @Test func buildsBoard() async throws {
        let snapshot = SampleData.kcSnapshot
        let details = BuildSamples.details(for: snapshot)
        let rows = [PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "kc"),
                    PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "c9")]
        let teams = SampleData.live[0].match.teams
        let kc = Palette.team("#5B8CFF")
        let draft = PlayerBuilds.draft(snapshot: snapshot, teamIds: ["kc", "c9"])
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Joueurs", subtitle: "Draft · builds · fiche")
                DraftStrip(teams: [DraftTeam(code: "KC", tint: kc, champions: draft[0]),
                                   DraftTeam(code: "C9", tint: nil, champions: draft[1])], version: nil)
                BuildPlayersPanel(teams: teams, rows: rows, context: BuildContext(), selection: .constant(0),
                                  onSelect: { _, _ in })
                BuildPlayersSkeleton()
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "20-joueurs")
        expectNotBlank(url)

        let jungler = PlayerSheetItem(player: rows[0][1], teamCode: "KC", tint: kc, context: BuildContext(),
                                      finished: false)
        let sheet = try await Snapshot.write(PlayerSheet(item: jungler), named: "20b-fiche-joueur")
        expectNotBlank(sheet)
    }
}
