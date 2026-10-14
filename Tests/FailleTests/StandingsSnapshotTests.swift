import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func standings(_ tournamentId: String, store: AppStore) -> some View {
        NavigationStack { StandingsView(tournamentId: tournamentId) }.environment(store)
    }

    /// LEC Split 3 : saison régulière classée (KC 1er, ligne teintée), play-offs.
    @Test func leagueStandings() async throws {
        let url = try await Snapshot.write(standings(SeasonSamples.lecSplit3.id, store: AppStore(preview: .withSeason)),
                                           named: "29-classement")
        expectNotBlank(url)
    }

    /// Mondial : T1 (anti-spoiler) y figure avec des matchs masqués → « Classement masqué · toucher pour révéler ».
    @Test func maskedStandings() async throws {
        let url = try await Snapshot.write(standings(SeasonSamples.worlds.id, store: AppStore(preview: .withSeason)),
                                           named: "29b-classement-masque")
        expectNotBlank(url)
    }

    /// Mondial révélé : play-ins, système suisse à venir.
    @Test func revealedWorldsBracket() async throws {
        let store = AppStore(preview: .withSeason)
        store.revealStandings(tournamentId: SeasonSamples.worlds.id)
        let url = try await Snapshot.write(standings(SeasonSamples.worlds.id, store: store), named: "29c-tableau-mondial")
        expectNotBlank(url)
    }
}
