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

    private func home(_ data: PreviewData, now: String = "2026-10-15T15:05:00Z") -> some View {
        NavigationStack { HomeView(openTeams: {}) }
            .environment(AppStore(preview: homeData(data)))
            .environment(\.seasonNow, SampleData.date(now))
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

    /// Collecte en cours : « Les stats arrivent : … games lues sur … ». La liste « Semaine » doit être vide pour que la
    /// ligne s'affiche (sinon la planche est celle de 25-bas) : « maintenant » est donc 13 jours après la dernière game
    /// lue du Mondial (11 octobre), hors de la semaine glissante.
    @Test func homeWhileCollecting() async throws {
        let url = try await Snapshot.write(
            home(.withSeasonCollecting, now: "2026-10-24T15:05:00Z").defaultScrollAnchor(.bottom),
            named: "25c-accueil-collecte")
        expectNotBlank(url)
    }

    /// Accueil en anglais (saison 15 : jamais regardé). Les `Text` suivent la langue de l'environnement ; les chaînes
    /// construites par `String(localized:)` suivent celle du processus (français sur la CI).
    @Test func homeInEnglish() async throws {
        let url = try await Snapshot.write(home(.withSeason).environment(\.locale, Locale(identifier: "en")),
                                           named: "35-accueil-anglais")
        expectNotBlank(url)
    }

    /// Accueil au plafond du texte (`accessibility5`), en plus de `accessibility2` (34) : en bas de page aussi.
    @Test func homeWithLargestText() async throws {
        let view = home(.withSeason).environment(\.dynamicTypeSize, .accessibility5)
        let top = try await Snapshot.write(view, named: "36-accueil-ax5")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(view.defaultScrollAnchor(.bottom), named: "36-accueil-ax5-bas")
        expectNotBlank(bottom)
    }
}
