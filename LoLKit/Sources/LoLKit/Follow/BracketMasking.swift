import Foundation

/// Progression d'un tableau (spec §8, règle I-1 généralisée à la compétition) : une compétition internationale
/// (`League.internationalSlugs`) où un match d'une équipe en anti-spoiler est masqué ne doit rien laisser entendre de la
/// suite. La demi-finale de deux AUTRES équipes, programmée après ce match, dirait que l'équipe masquée est éliminée.
public enum BracketMasking {
    /// Ids des matchs d'une ligue internationale, non révélés, dont le début est postérieur au dernier match masqué (non
    /// révélé, en cours ou terminé) d'une équipe de `maskedTeamIds` dans la même ligue. Quel que soit leur état : le
    /// consommateur choisit (ligne « Match à venir · masqué », absence d'une liste, pas de notification).
    /// - Parameter maskedTeamIds: `Presenter.maskedLatestTeamIds` (équipes suivies dont le dernier match est masqué).
    public static func hiddenIds(schedule: [MatchEvent], maskedTeamIds: Set<String>, follows: FollowList,
                                 revealed: Set<String>) -> Set<String> {
        guard !maskedTeamIds.isEmpty else { return [] }
        var threshold: [String: Date] = [:]
        for event in schedule
        where League.internationalSlugs.contains(event.league.slug) && event.state != .unstarted
            && event.match.teams.contains(where: { $0.id.map(maskedTeamIds.contains) ?? false })
            && SpoilerPolicy.isMasked(event.match.teams, matchId: event.id, follows: follows, revealed: revealed) {
            let slug = event.league.slug
            threshold[slug] = max(threshold[slug] ?? event.startTime, event.startTime)
        }
        guard !threshold.isEmpty else { return [] }
        return Set(schedule.filter { event in
            guard !revealed.contains(event.id), let limit = threshold[event.league.slug] else { return false }
            return event.startTime > limit
        }.map(\.id))
    }

    /// `events` sans les matchs que la progression du tableau cache. Le seuil (dernier match masqué d'une ligue) se
    /// cherche dans `events` ET dans `context` (calendrier, direct, pages du calendrier fusionnés) : un match d'une page
    /// de mois absent du calendrier en cache est caché comme les autres, même si le match masqué n'est que dans `context`.
    public static func visible(_ events: [MatchEvent], context: [MatchEvent], maskedTeamIds: Set<String>,
                               follows: FollowList, revealed: Set<String>) -> [MatchEvent] {
        guard !maskedTeamIds.isEmpty else { return events }
        let hidden = hiddenIds(schedule: events + context, maskedTeamIds: maskedTeamIds, follows: follows,
                               revealed: revealed)
        return hidden.isEmpty ? events : events.filter { !hidden.contains($0.id) }
    }
}
