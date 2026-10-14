import Foundation

/// Périmètre d'un calcul de saison (pilules « Saison 2026 », « LEC Split 3 »… de la page équipe, spec saison §3.1) :
/// un ensemble de tournois. `label` est une valeur, pas un texte : l'année (« 2026 ») ou le slug du tournoi.
public struct SeasonScope: Sendable, Hashable {
    public let tournamentIds: Set<String>
    public let label: String

    public init(tournamentIds: Set<String>, label: String) {
        self.tournamentIds = tournamentIds
        self.label = label
    }

    /// Saison = année civile (§1.2) : les tournois commencés cette année-là.
    public static func season(_ year: Int, tournaments: [TournamentRef]) -> SeasonScope {
        SeasonScope(tournamentIds: Set(tournaments.filter { $0.year == year }.map(\.id)), label: String(year))
    }

    /// Un seul tournoi ; `label` = son slug.
    public static func tournament(_ tournament: TournamentRef) -> SeasonScope {
        SeasonScope(tournamentIds: [tournament.id], label: tournament.slug)
    }

    public func contains(_ match: SeasonMatch) -> Bool {
        tournamentIds.contains(match.tournamentId)
    }
}
