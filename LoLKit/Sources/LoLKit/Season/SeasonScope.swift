import Foundation

/// Périmètre d'un calcul de saison (pilules « Saison 2026 », « LEC Split 3 »… de la page équipe, spec saison §3.1,
/// spec périmètre §2.2) : un ensemble de tournois. `label` est une valeur, pas un texte : l'année (« 2026 ») ou le slug
/// du tournoi. `season` : saison du périmètre ; `isLive` : tournoi en cours aujourd'hui (pilule « · en cours »).
public struct SeasonScope: Sendable, Hashable {
    public let tournamentIds: Set<String>
    public let label: String
    public let season: Int?
    public let isLive: Bool

    public init(tournamentIds: Set<String>, label: String, season: Int? = nil, isLive: Bool = false) {
        self.tournamentIds = tournamentIds
        self.label = label
        self.season = season
        self.isLive = isLive
    }

    /// Saison = année civile (§1.2) : les tournois commencés cette année-là.
    public static func season(_ year: Int, tournaments: [TournamentRef]) -> SeasonScope {
        SeasonScope(tournamentIds: Set(tournaments.filter { $0.year == year }.map(\.id)), label: String(year), season: year)
    }

    /// Un seul tournoi ; `label` = son slug, `season` = sa saison (`SeasonWindow.season(of:)`).
    public static func tournament(_ tournament: TournamentRef) -> SeasonScope {
        SeasonScope(tournamentIds: [tournament.id], label: tournament.slug, season: SeasonWindow.season(of: tournament))
    }

    public func contains(_ match: SeasonMatch) -> Bool {
        tournamentIds.contains(match.tournamentId)
    }
}
