/// Anti-spoiler du socle (spec saison §1.8) : quels matchs de la saison sont masqués.
public enum SeasonMasking {
    /// Ids des matchs masqués : `SpoilerPolicy.isMasked` sur les équipes du match (avec id quand il est connu), sauf
    /// match révélé. À passer en `masked` à `SeasonStats`, `Duel`, `HomeFeed` et `CrawlPlanner` (aucune requête pour
    /// un match masqué).
    public static func maskedMatchIds(_ matches: [SeasonMatch], follows: FollowList, revealed: Set<String>) -> Set<String> {
        Set(matches.filter { SpoilerPolicy.isMasked($0.teams, matchId: $0.id, follows: follows, revealed: revealed) }
            .map(\.id))
    }
}
