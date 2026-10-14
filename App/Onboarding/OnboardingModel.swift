import Foundation
import LoLKit

enum OnboardingModel {
    /// Équipes du Mondial 2026 (spec saison §3.7) : celles des classements du Mondial (ids réels, jamais « TBD »), trouvées
    /// dans le catalogue ; à défaut, celles que `TeamDirectory` rattache au Mondial (catalogue + calendrier). Par nom.
    static func worldsTeams(catalog: [Team], worldsStandings: Standings?, fallback: [Team]) -> [Team] {
        let ids = Set((worldsStandings?.stages ?? [])
            .flatMap { $0.sections.flatMap { $0.matches.flatMap(\.teams) } }
            .compactMap(\.id)
            .filter { $0 != "0" })
        let fromStandings = catalog.filter { ids.contains($0.id) }
        let teams = fromStandings.isEmpty ? fallback : fromStandings
        return teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
