import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func teamPage(_ teamId: String, _ data: PreviewData) -> some View {
        NavigationStack { TeamPageView(teamId: teamId) }
            .environment(AppStore(preview: data))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
    }

    /// Page de KC (spec saison §3.1) : bilan, forme, effectif, moyennes, champions ; classement du Mondial masqué (T1, en
    /// anti-spoiler, y figure avec des matchs masqués).
    @Test func teamPage() async throws {
        let top = try await Snapshot.write(teamPage("kc", .withSeason), named: "26-equipe")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(teamPage("kc", .withSeason).defaultScrollAnchor(.bottom), named: "26-equipe-bas")
        expectNotBlank(bottom)
    }

    /// T1 en anti-spoiler, tous ses matchs masqués : « Stats masquées · 3 matchs masqués », « Prochain · masqué ».
    @Test func teamPageMasked() async throws {
        let url = try await Snapshot.write(teamPage("t1", .withSeason), named: "26b-equipe-masquee")
        expectNotBlank(url)
    }

    /// Disque de la saison pas encore lu : squelettes.
    @Test func teamPageLoading() async throws {
        let url = try await Snapshot.write(teamPage("kc", .withSeasonLoading), named: "26c-equipe-chargement")
        expectNotBlank(url)
    }
}
