/// Ce qu'une carte a le droit d'annoncer comme « prochain » match (spec §8).
///
/// L'existence ou l'adversaire du prochain match trahit le résultat d'un match masqué (élimination, tableau, Swiss) :
/// tant que le dernier match en direct ou terminé de l'équipe est masqué, la carte n'affiche qu'une ligne fixe
/// « Prochain · masqué », qu'un prochain match existe ou non. Il en va de même quand le prochain match oppose l'équipe
/// à une AUTRE équipe suivie en anti-spoiler : « GEN vs T1 » ne s'annonce nulle part avant d'être révélé.
public enum NextLine: Sendable, Equatable {
    /// Rien n'est annoncé, ligne fixe « Prochain · masqué » : le dernier match de l'équipe est masqué, ou son prochain
    /// match l'oppose à une autre équipe suivie en anti-spoiler (et n'est pas révélé).
    case hidden
    /// Aucun prochain match connu (et rien à cacher).
    case none
    /// Le prochain match, à afficher normalement.
    case match(MatchEvent)
}

extension Presenter {
    /// Ligne « Prochain » d'une carte : `.hidden` si le dernier match de l'équipe (celui de `card.live`, sinon `card.last`)
    /// est masqué et non révélé, ou si son prochain match l'oppose à une autre équipe suivie en anti-spoiler et n'est pas
    /// révélé ; sinon `.match` / `.none` selon `card.next`.
    public static func nextLine(for card: TeamCard, follows: FollowList, revealed: Set<String>) -> NextLine {
        if let latest = card.live ?? card.last,
           SpoilerPolicy.isMasked(latest.match.teams, matchId: latest.id, follows: follows, revealed: revealed) {
            return .hidden
        }
        guard let next = card.next else { return .none }
        // Prochain match masqué par une AUTRE équipe suivie en anti-spoiler (« GEN vs T1 » sur la carte de GEN) : son
        // existence trahirait la progression de cette équipe. L'équipe de la carte est couverte par la règle ci-dessus.
        if !revealed.contains(next.id),
           follows.followed(in: next.match.teams).contains(where: { $0.spoilerFree && $0.id != card.team.id }) {
            return .hidden
        }
        return .match(next)
    }
}
