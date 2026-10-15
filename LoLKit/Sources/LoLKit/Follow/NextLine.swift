/// Ce qu'une carte a le droit d'annoncer comme « prochain » match (spec §8).
///
/// L'existence ou l'adversaire du prochain match trahit le résultat d'un match masqué (élimination, tableau, Swiss) :
/// tant que le dernier match en direct ou terminé de l'équipe est masqué, la carte n'affiche qu'une ligne fixe
/// « Prochain · masqué », qu'un prochain match existe ou non. Il en va de même quand le prochain match oppose l'équipe
/// à une AUTRE équipe suivie en anti-spoiler dont le dernier match est masqué : « GEN vs T1 » ne s'annonce nulle part
/// avant d'être révélé, puisque cette ligne apprendrait que T1 joue encore (règle C).
public enum NextLine: Sendable, Equatable {
    /// Rien n'est annoncé, ligne fixe « Prochain · masqué » : le dernier match de l'équipe est masqué (règle F1), ou son
    /// prochain match l'oppose à une autre équipe suivie en anti-spoiler dont le dernier match est masqué (règle C), et
    /// n'est pas révélé.
    case hidden
    /// Aucun prochain match connu (et rien à cacher).
    case none
    /// Le prochain match, à afficher normalement.
    case match(MatchEvent)
}

extension Presenter {
    /// Ids des équipes dont le dernier match (celui de `card.live`, sinon `card.last`, comme pour la règle F1) est masqué
    /// et non révélé. À calculer une fois sur TOUTES les cartes, puis à passer à `nextLine` : une équipe sans carte dans
    /// `cards` n'y figure pas.
    public static func maskedLatestTeamIds(_ cards: [TeamCard], follows: FollowList, revealed: Set<String>) -> Set<String> {
        Set(cards.compactMap { card in
            guard latestIsMasked(card, follows: follows, revealed: revealed) else { return nil }
            return card.team.id
        })
    }

    /// Le dernier match de la carte (`live`, sinon `last`) est masque et non revele : par l'anti-spoiler de l'equipe, ou
    /// par la progression du tableau (`liveBracketMasked` / `lastBracketMasked`).
    static func latestIsMasked(_ card: TeamCard, follows: FollowList, revealed: Set<String>) -> Bool {
        guard let latest = card.live ?? card.last else { return false }
        if SpoilerPolicy.isMasked(latest.match.teams, matchId: latest.id, follows: follows, revealed: revealed) { return true }
        let bracket = card.live != nil ? card.liveBracketMasked : card.lastBracketMasked
        return bracket && !revealed.contains(latest.id)
    }

    /// Ligne « Prochain » d'une carte. `.hidden` dans deux cas, sinon `.match` / `.none` selon `card.next` :
    /// - règle F1 : le dernier match de l'équipe (celui de `card.live`, sinon `card.last`) est masqué et non révélé ;
    /// - règle C : son prochain match, non révélé, l'oppose à une AUTRE équipe suivie en anti-spoiler dont le dernier
    ///   match est masqué (son id est dans `maskedLatestTeamIds`). Si cette équipe n'a pas de dernier match masqué, le
    ///   match s'annonce normalement : il ne trahit rien, et la règle reste symétrique entre les deux cartes.
    /// - Parameter maskedLatestTeamIds: `Presenter.maskedLatestTeamIds` de toutes les cartes affichées ensemble.
    public static func nextLine(for card: TeamCard, follows: FollowList, revealed: Set<String>,
                                maskedLatestTeamIds: Set<String>) -> NextLine {
        if latestIsMasked(card, follows: follows, revealed: revealed) {
            return .hidden
        }
        guard let next = card.next else { return .none }
        // Suite d'un tableau international dont un match d'une équipe en anti-spoiler est masqué (`BracketMasking`).
        if card.nextBracketMasked, !revealed.contains(next.id) {
            return .hidden
        }
        // L'équipe de la carte est couverte par la règle ci-dessus ; les autres équipes suivies du match comptent si elles
        // sont en anti-spoiler et que leur dernier match est masqué.
        if !revealed.contains(next.id),
           follows.followed(in: next.match.teams).contains(where: {
               $0.spoilerFree && $0.id != card.team.id && maskedLatestTeamIds.contains($0.id)
           }) {
            return .hidden
        }
        return .match(next)
    }
}
