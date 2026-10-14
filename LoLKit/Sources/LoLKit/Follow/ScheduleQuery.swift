/// Quelles ligues demander à `getSchedule`.
public enum ScheduleQuery {
    /// Ligues d'attache des équipes suivies + ligues suivies + compétitions internationales, dans l'ordre de
    /// `getLeagues`.
    public static func leagueIds(follows: FollowList, leagues: [League]) -> [String] {
        let homeNames = Set(follows.teams.compactMap(\.homeLeagueName))
        let followedIds = Set(follows.leagues.map(\.id))
        return leagues
            .filter { League.internationalSlugs.contains($0.slug) || homeNames.contains($0.name) || followedIds.contains($0.id) }
            .map(\.id)
    }
}
