import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Fil des événements et courbe de l'écart de gold (spec fonctionnalités §4, §5) : la game en direct d'exemple (KC en
    /// tête), puis une game jouée gagnée par l'équipe de droite (courbe sous zéro), et le gabarit de chargement.
    @Test func timelineBoard() async throws {
        let live = SampleData.kcSnapshot
        let store = TimelineStore(preview: [
            live.gameId: TimelineSamples.frames(.kcLive, start: SampleData.kcGameStart, final: live) + [live],
            "fini": TimelineSamples.frames(.redWins, start: SampleData.kcGameStart, final: GameSnapshot(
                gameId: "fini", phase: .finished, timestamp: live.timestamp, blueTeamId: "kc", redTeamId: "c9",
                blue: live.blue, red: live.red, bluePlayers: live.bluePlayers, redPlayers: live.redPlayers)),
        ])
        let teams = [TimelineTeam(id: "kc", code: "KC", tint: Palette.team("#5B8CFF")),
                     TimelineTeam(id: "c9", code: "C9", tint: Palette.secondary)]
        func chart(_ gameId: String) -> GoldChartCard {
            GoldChartCard(points: store.goldPoints(gameId: gameId, orientedTo: "kc"),
                          markers: store.events(gameId: gameId).filter(TimelineText.isMarker), teams: teams)
        }
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Fil et courbe", subtitle: "En direct · game jouée · chargement")
                chart(live.gameId)
                TimelineCard(events: store.events(gameId: live.gameId), teams: teams)
                chart("fini")
                GoldChartCard(points: [], markers: [], teams: teams, loading: true)
                TimelineCard(events: [], teams: teams, loading: true)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "19-fil-et-courbe")
        expectNotBlank(url)
        // La planche dépasse l'écran : la seconde capture montre le bas (courbe d'une game jouée et gabarits).
        let bottom = try await Snapshot.write(board.defaultScrollAnchor(.bottom), named: "19-fil-et-courbe-bas")
        expectNotBlank(bottom)
    }
}
