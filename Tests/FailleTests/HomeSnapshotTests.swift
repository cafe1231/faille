import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Deux résultats d'hier ajoutés au calendrier d'exemple : T1 – HLE (T1 en anti-spoiler : « Terminé · toucher pour
    /// révéler ») et GEN 2 – 0 FUR (score visible).
    private func homeData(_ base: PreviewData) -> PreviewData {
        var data = base
        func team(_ id: String, _ wins: Int, _ won: Bool) -> MatchTeam {
            let catalog = SampleData.catalog.first { $0.id == id }
            return MatchTeam(id: nil, name: catalog?.name ?? id, code: catalog?.code ?? id.uppercased(), image: nil,
                             result: MatchTeam.Result(outcome: won ? "win" : "loss", gameWins: wins))
        }
        func completed(_ id: String, _ start: String, _ a: MatchTeam, _ b: MatchTeam) -> MatchEvent {
            MatchEvent(startTime: SampleData.date(start), state: .completed, type: "match", blockName: "Play-in",
                       league: SampleData.worlds,
                       match: MatchInfo(id: id, teams: [a, b], strategy: Strategy(type: "bestOf", count: 3), games: nil),
                       streams: nil)
        }
        data.schedule += [completed("m-t1-hle-r", "2026-10-14T12:00:00Z", team("t1", 2, true), team("hle", 1, false)),
                          completed("m-gen-fur-r", "2026-10-14T09:00:00Z", team("gen", 2, true), team("fur", 0, false))]
        return data
    }

    private func home(_ data: PreviewData) -> some View {
        NavigationStack { HomeView(openTeams: {}) }
            .environment(AppStore(preview: homeData(data)))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
    }

    /// Accueil avec suivis (spec saison §2.2) : à ne pas rater, direct (T1 – FLY masqué : « En direct » seul), calendrier,
    /// résultats (T1 – HLE « toucher pour révéler »), activité, joueurs en forme.
    @Test func homeWithFollows() async throws {
        let top = try await Snapshot.write(home(.withSeason), named: "25-accueil")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(home(.withSeason).defaultScrollAnchor(.bottom), named: "25-accueil-bas")
        expectNotBlank(bottom)
    }

    /// Sans équipe suivie : « Suis tes équipes pour un accueil sur mesure », et le Mondial quand même.
    @Test func homeWithoutFollows() async throws {
        let url = try await Snapshot.write(home(.withSeasonNoFollows), named: "25b-accueil-sans-suivi")
        expectNotBlank(url)
    }

    /// Collecte en cours : « Les stats arrivent : … games lues sur … ».
    @Test func homeWhileCollecting() async throws {
        let url = try await Snapshot.write(home(.withSeasonCollecting).defaultScrollAnchor(.bottom),
                                           named: "25c-accueil-collecte")
        expectNotBlank(url)
    }
}
