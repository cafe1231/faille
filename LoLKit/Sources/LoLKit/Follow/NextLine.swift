/// Ce qu'une carte a le droit d'annoncer comme « prochain » match (spec §8).
///
/// L'existence ou l'adversaire du prochain match trahit le résultat d'un match masqué (élimination, tableau, Swiss) :
/// tant que le dernier match en direct ou terminé de l'équipe est masqué, la carte n'affiche qu'une ligne fixe
/// « Prochain · masqué », qu'un prochain match existe ou non.
public enum NextLine: Sendable, Equatable {
    /// Le dernier match en direct ou terminé est masqué : ligne fixe, rien n'est annoncé.
    case hidden
    /// Aucun prochain match connu (et rien à cacher).
    case none
    /// Le prochain match, à afficher normalement.
    case match(MatchEvent)
}

extension Presenter {
    /// Ligne « Prochain » d'une carte : `.hidden` si le dernier match de l'équipe (celui de `card.live`, sinon `card.last`)
    /// est masqué et non révélé ; sinon `.match` / `.none` selon `card.next`.
    public static func nextLine(for card: TeamCard, follows: FollowList, revealed: Set<String>) -> NextLine {
        if let latest = card.live ?? card.last,
           SpoilerPolicy.isMasked(latest.match.teams, matchId: latest.id, follows: follows, revealed: revealed) {
            return .hidden
        }
        guard let next = card.next else { return .none }
        return .match(next)
    }
}
