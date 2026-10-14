import Foundation

/// Vainqueur de chaque game jouée d'une série (spec saison §1.4). L'API ne le donne nulle part : on part des victoires
/// de la série (`gameWins`, exactes) et, pour les games qu'elles ne tranchent pas, des tours détruites à la frame finale
/// (cohérent avec les scores de série sur 30 games sur 31, mesuré sur KC, LEC Split 3).
public enum GameWinners {
    /// Écart de tours minimal pour déduire un vainqueur.
    public static let minimumTowerMargin = 3

    /// Résultat de chaque game de `playedGameIds` (clé : id de game), dans cet ordre de règles :
    /// 1. Bo1 → le vainqueur du match (exact) ;
    /// 2. une équipe a gagné toutes les games → toutes à elle (exact) ;
    /// 3. la dernière game → le vainqueur de la série (exact) ;
    /// 4. les autres : l'équipe A doit en gagner `w` ; marge = tours(A) − tours(B) ; A reçoit les `w` games de plus
    ///    grande marge. **Déduit** si chaque game attribuée à A a une marge ≥ 3 et chaque game attribuée à B une
    ///    marge ≤ −3 (l'attribution est alors unique) ; sinon, ou s'il manque un résumé, **inconnu** pour ces games.
    /// Rien n'est rendu si les deux équipes n'ont pas d'id ou si les victoires ne correspondent pas aux games jouées.
    /// - Parameters:
    ///   - teams: les deux équipes du match, avec id et `result.gameWins`.
    ///   - playedGameIds: games jouées dans l'ordre (`CompletedMatch.playedGameIds`).
    ///   - summaries: résumés en cache, par id de game.
    public static func assign(teams: [MatchTeam], playedGameIds: [String],
                              summaries: [String: GameSummary]) -> [String: GameResult] {
        guard teams.count == 2, let a = teams[0].id, let b = teams[1].id, !playedGameIds.isEmpty else { return [:] }
        let winsA = teams[0].gameWins
        let winsB = teams[1].gameWins
        guard winsA + winsB == playedGameIds.count, winsA != winsB else { return [:] }
        let seriesWinner = winsA > winsB ? a : b
        var results: [String: GameResult] = [:]
        // Règles 1 et 2 (un Bo1 est une série gagnée sans perdre de game).
        if winsA == 0 || winsB == 0 {
            for game in playedGameIds { results[game] = GameResult(winnerTeamId: seriesWinner, basis: .exact) }
            return results
        }
        // Règle 3.
        let last = playedGameIds[playedGameIds.count - 1]
        results[last] = GameResult(winnerTeamId: seriesWinner, basis: .exact)
        // Règle 4.
        let rest = Array(playedGameIds.dropLast())
        let needA = winsA - (seriesWinner == a ? 1 : 0)
        let margins = rest.compactMap { game -> (game: String, margin: Int)? in
            guard let summary = summaries[game], let lineA = summary.line(teamId: a),
                  let lineB = summary.line(teamId: b) else { return nil }
            return (game, lineA.towers - lineB.towers)
        }
        guard margins.count == rest.count else {
            for game in rest { results[game] = .unknown }
            return results
        }
        let ranked = margins.enumerated().sorted { ($0.element.margin, -$0.offset) > ($1.element.margin, -$1.offset) }
            .map(\.element)
        let toA = ranked.prefix(needA)
        let toB = ranked.dropFirst(needA)
        let sure = toA.allSatisfy { $0.margin >= minimumTowerMargin } && toB.allSatisfy { $0.margin <= -minimumTowerMargin }
        for entry in toA {
            results[entry.game] = sure ? GameResult(winnerTeamId: a, basis: .inferred) : .unknown
        }
        for entry in toB {
            results[entry.game] = sure ? GameResult(winnerTeamId: b, basis: .inferred) : .unknown
        }
        return results
    }

    /// `summaries` avec le résultat de `assign` reporté dans les games de ce match (les autres inchangées).
    public static func apply(teams: [MatchTeam], playedGameIds: [String],
                             to summaries: [String: GameSummary]) -> [String: GameSummary] {
        var updated = summaries
        for (game, result) in assign(teams: teams, playedGameIds: playedGameIds, summaries: summaries) {
            updated[game]?.result = result
        }
        return updated
    }
}
