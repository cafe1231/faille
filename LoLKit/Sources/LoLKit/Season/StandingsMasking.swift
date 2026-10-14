/// Anti-spoiler des classements et tableaux (spec saison §3.5) : un classement contient tous les résultats.
public enum StandingsMasking {
    /// Masqué si une équipe suivie en anti-spoiler y figure et qu'un de ses matchs terminés (ou en cours) de ce tournoi
    /// est masqué, sauf révélation explicite du classement (`revealedStandings` = `AppSettings.revealedStandingIds`).
    /// Une équipe classée avec un bilan non nul compte aussi : son bilan résume des matchs que le tableau ne liste pas
    /// forcément, il est masqué tant que tous ses matchs listés et terminés ne sont pas révélés et au moins aussi
    /// nombreux que son bilan. Révéler le classement ne révèle aucun match.
    public static func isMasked(_ standings: Standings, tournamentId: String, follows: FollowList, revealed: Set<String>,
                                revealedStandings: Set<String>) -> Bool {
        guard !revealedStandings.contains(tournamentId) else { return false }
        let played = standings.allMatches.filter { $0.state == .completed || $0.state == .inProgress }
        if played.contains(where: { SpoilerPolicy.isMasked($0.teams, matchId: $0.id, follows: follows, revealed: revealed) }) {
            return true
        }
        for team in standings.stages.flatMap({ $0.sections.flatMap(\.rankings) }).flatMap(\.teams)
        where team.wins + team.losses > 0 {
            guard let followed = follows.team(id: team.id), followed.spoilerFree else { continue }
            let revealedOwn = played.filter { match in
                match.teams.contains { $0.id == team.id } && revealed.contains(match.id)
            }
            if revealedOwn.count < team.wins + team.losses { return true }
        }
        return false
    }
}
