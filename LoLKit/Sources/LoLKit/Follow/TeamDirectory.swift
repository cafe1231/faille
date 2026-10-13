import Foundation

/// Annuaire de l'onglet Équipes (spec §5.2) : recherche et ligues en pilules.
public enum TeamDirectory {
    /// Équipes actives dont le nom ou le code contient `query` (sans tenir compte de la casse ni des accents).
    /// Ordre : code exact, puis début du code ou du nom, puis le reste ; alphabétique à égalité.
    public static func search(_ query: String, in catalog: [Team], limit: Int = 50) -> [Team] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        let ranked = catalog.compactMap { team -> (rank: Int, name: String, team: Team)? in
            guard team.isActive else { return nil }
            let code = fold(team.code)
            let name = fold(team.name)
            let rank: Int
            if code == needle {
                rank = 0
            } else if code.hasPrefix(needle) || name.hasPrefix(needle) {
                rank = 1
            } else if code.contains(needle) || name.contains(needle) {
                rank = 2
            } else {
                return nil
            }
            return (rank, name, team)
        }
        return ranked
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
            .prefix(limit)
            .map(\.team)
    }

    /// Équipes actives d'une ligue : celles dont c'est la ligue d'attache, plus celles vues dans son calendrier
    /// (indispensable pour le Mondial, le MSI et le First Stand, ligue d'attache de personne). Triées par nom.
    public static func teams(in league: League, catalog: [Team], schedule: [MatchEvent]) -> [Team] {
        let active = catalog.filter(\.isActive)
        var result = active.filter { $0.homeLeague?.name == league.name }
        let playing = schedule
            .filter { $0.league.slug == league.slug }
            .flatMap(\.match.teams)
            .filter { !$0.isPlaceholder }
        if !playing.isEmpty {
            for team in active where !result.contains(where: { $0.id == team.id }) {
                let followed = FollowedTeam(team: team)
                if playing.contains(where: { $0.isSame(as: followed) }) {
                    result.append(team)
                }
            }
        }
        return result.sorted { fold($0.name) < fold($1.name) }
    }

    /// Ligues à proposer en pilules : celles qui ont au moins une équipe, par priorité de l'API puis dans l'ordre de l'API.
    public static func leagues(_ leagues: [League], catalog: [Team], schedule: [MatchEvent]) -> [League] {
        leagues.enumerated()
            .filter { !teams(in: $0.element, catalog: catalog, schedule: schedule).isEmpty }
            .sorted { ($0.element.priority ?? .max, $0.offset) < ($1.element.priority ?? .max, $1.offset) }
            .map(\.element)
    }

    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
