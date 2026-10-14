import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Accessibilité et langue (spec saison §3.8) : scores lus, catalogue fr/en, Dynamic Type.
/// Les tests tournent en français (`-testLanguage fr`, `ios.yml`) ; l'anglais est lu directement dans `en.lproj`.
@MainActor
struct AccessibilityTests {
    @Test func scoresAreSpoken() {
        let teams = SampleData.kcG2Details.match.teams
        #expect(ScoreRow.spoken(teams: teams, score: [1, 3]) == "Karmine Corp 1, G2 Esports 3")
        #expect(ScoreRow.spoken(teams: teams, score: nil) == "Karmine Corp contre G2 Esports")
    }

    /// Le catalogue est compilé dans l'appli, en français et en anglais.
    @Test func catalogIsBundled() {
        #expect(Bundle.main.localizations.contains("en"))
        #expect(Bundle.main.localizations.contains("fr"))
    }

    /// Texte anglais d'une clé exacte du catalogue (format compris).
    private func english(_ key: String) -> String? {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let bundle = Bundle(path: path) else {
            return nil
        }
        let value = bundle.localizedString(forKey: key, value: "\u{0}absent", table: nil)
        return value == "\u{0}absent" ? nil : value
    }

    /// Une dizaine de clés exactes, dont des clés à format : `%lld` (entier), `%@` (texte) et leur ordre.
    @Test func englishCatalogHasExactKeys() {
        #expect(english("Accueil") == "Home")
        #expect(english("Équipes") == "Teams")
        #expect(english("À ne pas rater") == "Don't miss")
        #expect(english("En direct maintenant") == "Live now")
        #expect(english("Classement masqué") == "Standings hidden")
        #expect(english("toucher pour révéler") == "tap to reveal")
        #expect(english("%@ %lld, %@ %lld") == "%@ %lld, %@ %lld")
        #expect(english("%@ contre %@") == "%@ vs %@")
        #expect(english("Page %lld sur 3") == "Page %lld of 3")
        #expect(english("Saison %@") == "Season %@")
        #expect(english("%@ : %lld victoires d'affilée") == "%@: %lld wins in a row")
        #expect(english("Prochain · %@") == "Next · %@")
    }

    /// Les clés des textes lus à voix haute (`spoken`) existent en anglais, avec leurs formats.
    @Test func spokenKeysAreTranslated() {
        #expect(english("%@ : %@ à %@") == "%@: %@ to %@")
        #expect(english("Kills %lld à %lld, écart de gold %@, drakes %lld à %lld, tours %lld à %lld")
            == "Kills %lld to %lld, gold lead %@, drakes %lld to %lld, towers %lld to %lld")
    }
}

extension ApercuTests {
    /// Accueil en très grand texte (`accessibility2`, le plafond de `.sora`) : rien ne doit être coupé de façon illisible.
    @Test func homeWithLargeText() async throws {
        let view = NavigationStack { HomeView(openTeams: {}) }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
            .environment(\.dynamicTypeSize, .accessibility2)
        let url = try await Snapshot.write(view, named: "34-grand-texte")
        expectNotBlank(url)
    }
}
