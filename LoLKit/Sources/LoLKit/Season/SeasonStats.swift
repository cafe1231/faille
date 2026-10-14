import Foundation

/// Agrégats de saison (spec saison §1.5, §1.8), purs et calculés à la lecture : rien n'est stocké. Toutes les fonctions
/// prennent `masked` (ids de match, `SeasonMasking.maskedMatchIds`) : un match masqué ne compte nulle part.
public enum SeasonStats {
    /// Saison de l'équipe `teamId` dans `scope`.
    /// - Parameters:
    ///   - matches: matchs joués (`SeasonMatch.join`), dans n'importe quel ordre ; seuls ceux du périmètre, joués par
    ///     l'équipe (par id) et commencés avant `now` comptent.
    ///   - games: `GameSummary` en cache par id de game (résultats déjà rejoués par `GameWinners`).
    ///   - withoutStats: games en échec définitif de collecte (`CrawlFailure` final) : « N games sans stats ».
    public static func team(_ teamId: String, matches: [SeasonMatch], games: [String: GameSummary], scope: SeasonScope,
                            masked: Set<String>, now: Date, withoutStats: Set<String> = []) -> TeamSeason {
        let played = matches
            .filter { scope.contains($0) && $0.involves(teamId) && $0.startTime <= now }
            .sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        let visible = played.filter { !masked.contains($0.id) }
        var seriesWins = 0, seriesLosses = 0, gameWins = 0, gameLosses = 0
        for match in visible {
            guard let (own, other) = score(match, teamId) else { continue }
            gameWins += own
            gameLosses += other
            if own > other { seriesWins += 1 } else if other > own { seriesLosses += 1 }
        }
        let form = played.suffix(5).map { match -> FormPip in
            if masked.contains(match.id) { return FormPip(matchId: match.id, outcome: .masked) }
            let won = score(match, teamId).map { $0.own > $0.other } ?? false
            return FormPip(matchId: match.id, outcome: won ? .win : .loss)
        }
        var counted: [GameSummary] = []
        var pending = 0, without = 0
        for match in visible {
            for gameId in match.playedGameIds {
                if let summary = games[gameId], summary.line(teamId: teamId) != nil {
                    counted.append(summary)
                } else if withoutStats.contains(gameId) {
                    without += 1
                } else {
                    pending += 1
                }
            }
        }
        var dragonTypes: [String: Int] = [:]
        for summary in counted {
            for dragon in summary.line(teamId: teamId)?.dragons ?? [] { dragonTypes[dragon, default: 0] += 1 }
        }
        let lines = counted.flatMap { summary in
            (summary.line(teamId: teamId)?.players ?? []).map { (summary: summary, teamId: teamId, line: $0) }
        }
        return TeamSeason(
            teamId: teamId, scope: scope, seriesWins: seriesWins, seriesLosses: seriesLosses, gameWins: gameWins,
            gameLosses: gameLosses, streak: streak(teamId, matches: played, masked: masked), form: Array(form),
            gamesCounted: counted.count, gamesPending: pending, gamesWithoutStats: without,
            maskedMatches: played.count - visible.count, averages: averages(teamId, counted),
            dragonTypes: dragonTypes, champions: Array(championUses(lines).prefix(8)))
    }

    /// Série en cours de l'équipe sur `matches` (séries, du plus récent) ; nil si elle fait moins de 2 matchs ou si le
    /// match le plus récent est masqué (la série « en cours » est alors inconnue). S'arrête au premier match masqué.
    public static func streak(_ teamId: String, matches: [SeasonMatch], masked: Set<String>) -> Streak? {
        let ordered = matches.filter { $0.involves(teamId) }.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        var kind: Streak.Kind?
        var count = 0
        for match in ordered {
            guard !masked.contains(match.id), let (own, other) = score(match, teamId), own != other else { break }
            let current: Streak.Kind = own > other ? .wins : .losses
            if let kind, kind != current { break }
            kind = current
            count += 1
        }
        guard let kind, count >= 2 else { return nil }
        return Streak(kind: kind, count: count)
    }

    /// Saison d'un joueur sur les games données (toutes équipes), masquées exclues ; `since` : games commencées à
    /// partir de cette date (« Semaine »). nil s'il n'a aucune game.
    public static func player(_ playerId: String, games: [GameSummary], masked: Set<String>,
                              since: Date?) -> PlayerSeason? {
        let entries = games
            .filter { summary in !masked.contains(summary.matchId) && (since.map { summary.startedAt >= $0 } ?? true) }
            .compactMap { summary in summary.player(playerId).map { (summary: summary, team: $0.team, line: $0.line) } }
            .sorted { ($0.summary.startedAt, $0.summary.gameId) > ($1.summary.startedAt, $1.summary.gameId) }
        guard let latest = entries.first else { return nil }
        let minutes = entries.reduce(0.0) { $0 + Double($1.summary.durationSeconds) / 60 }
        let kills = entries.reduce(0) { $0 + $1.line.kills }
        let deaths = entries.reduce(0) { $0 + $1.line.deaths }
        let assists = entries.reduce(0) { $0 + $1.line.assists }
        let teamKills = entries.reduce(0) { $0 + $1.team.kills }
        let shares = entries.compactMap(\.line.damageShare)
        let refs = entries.map { entry in
            gameRef(entry.summary, teamId: entry.team.teamId, line: entry.line)
        }
        let best = refs.enumerated().max { a, b in
            (a.element.kda, a.element.kills, -a.offset) < (b.element.kda, b.element.kills, -b.offset)
        }?.element
        return PlayerSeason(
            playerId: playerId, name: latest.line.name, role: latest.line.role, teamId: latest.team.teamId,
            games: entries.count, kills: kills, deaths: deaths, assists: assists,
            csPerMin: minutes > 0 ? Double(entries.reduce(0) { $0 + $1.line.creepScore }) / minutes : 0,
            goldPerMin: minutes > 0 ? Double(entries.reduce(0) { $0 + $1.line.gold }) / minutes : 0,
            killParticipation: teamKills > 0 ? Double(kills + assists) / Double(teamKills) : 0,
            damageShare: shares.isEmpty ? nil : shares.reduce(0, +) / Double(shares.count),
            damageShareGames: shares.count,
            champions: championUses(entries.map { (summary: $0.summary, teamId: $0.team.teamId, line: $0.line) }),
            bestGame: best, recent: Array(refs.prefix(5)))
    }

    /// Joueurs en forme (§2.2 n° 6) : au moins `minGames` games (2 sur la semaine, 5 sur la saison), triés par
    /// `metric` décroissant, puis par nombre de games, puis par nom.
    public static func topPlayers(games: [GameSummary], masked: Set<String>, metric: PlayerMetric, since: Date?,
                                  minGames: Int, limit: Int) -> [PlayerSeason] {
        let ids = Set(games.flatMap { ($0.blue.players + $0.red.players).map(\.playerId) }.filter { !$0.isEmpty })
        return ids.compactMap { player($0, games: games, masked: masked, since: since) }
            .filter { $0.games >= minGames }
            .sorted { a, b in
                let (x, y) = (metric.value(of: a), metric.value(of: b))
                if x != y { return x > y }
                if a.games != b.games { return a.games > b.games }
                return (a.name, a.playerId) < (b.name, b.playerId)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Face-à-face des équipes `a` et `b` sur `matches` (séries gagnées), masqués exclus et comptés.
    public static func headToHead(_ a: String, _ b: String, matches: [SeasonMatch], masked: Set<String>) -> HeadToHead {
        let meetings = matches.filter { $0.involves(a) && $0.involves(b) }
            .sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        let visible = meetings.filter { !masked.contains($0.id) }
        var winsA = 0, winsB = 0
        for match in visible {
            guard let (own, other) = score(match, a) else { continue }
            if own > other { winsA += 1 } else if other > own { winsB += 1 }
        }
        return HeadToHead(teamA: a, teamB: b, winsA: winsA, winsB: winsB, matchIds: visible.map(\.id),
                          maskedMatches: meetings.count - visible.count)
    }

    // MARK: - Détails

    /// Victoires de l'équipe et de son adversaire dans la série ; nil si l'équipe n'y joue pas.
    static func score(_ match: SeasonMatch, _ teamId: String) -> (own: Int, other: Int)? {
        guard let own = match.teams.first(where: { $0.id == teamId }) else { return nil }
        let other = match.teams.filter { $0.id != teamId }.reduce(0) { $0 + $1.gameWins }
        return (own.gameWins, other)
    }

    static func averages(_ teamId: String, _ games: [GameSummary]) -> TeamAverages? {
        guard !games.isEmpty else { return nil }
        let count = Double(games.count)
        func mean(_ value: (GameSummary) -> Int) -> Double { Double(games.reduce(0) { $0 + value($1) }) / count }
        let diffs = games.compactMap { summary -> Int? in
            guard let own = summary.line(teamId: teamId)?.gold15,
                  let other = summary.opponentLine(of: teamId)?.gold15 else { return nil }
            return own - other
        }
        return TeamAverages(
            kills: mean { $0.line(teamId: teamId)?.kills ?? 0 },
            deaths: mean { $0.opponentLine(of: teamId)?.kills ?? 0 },
            gold: mean { $0.line(teamId: teamId)?.gold ?? 0 },
            towers: mean { $0.line(teamId: teamId)?.towers ?? 0 },
            dragons: mean { $0.line(teamId: teamId)?.dragons.count ?? 0 },
            barons: mean { $0.line(teamId: teamId)?.barons ?? 0 },
            inhibitors: mean { $0.line(teamId: teamId)?.inhibitors ?? 0 },
            durationSeconds: mean(\.durationSeconds),
            gold15Diff: diffs.isEmpty ? nil : Double(diffs.reduce(0, +)) / Double(diffs.count),
            gold15Games: diffs.count)
    }

    /// Champions par nombre de games (puis par nom) ; une victoire = la game gagnée par l'équipe du joueur (vainqueur
    /// exact ou déduit ; « estimé » si au moins une victoire est déduite).
    static func championUses(_ lines: [(summary: GameSummary, teamId: String, line: PlayerGameLine)]) -> [ChampionUse] {
        var byChampion: [String: (games: Int, wins: Int, estimated: Bool)] = [:]
        for (summary, team, line) in lines where !line.champion.isEmpty {
            var entry = byChampion[line.champion] ?? (0, 0, false)
            entry.games += 1
            if summary.result.winnerTeamId == team, summary.result.basis != .unknown {
                entry.wins += 1
                if summary.result.basis == .inferred { entry.estimated = true }
            }
            byChampion[line.champion] = entry
        }
        return byChampion
            .map { ChampionUse(champion: $0.key, games: $0.value.games, wins: $0.value.wins, winsEstimated: $0.value.estimated) }
            .sorted { $0.games != $1.games ? $0.games > $1.games : $0.champion < $1.champion }
    }

    static func gameRef(_ summary: GameSummary, teamId: String, line: PlayerGameLine) -> GameRefLine {
        let known = summary.result.basis != .unknown && summary.result.winnerTeamId != nil
        return GameRefLine(gameId: summary.gameId, matchId: summary.matchId, teamId: teamId,
                           startedAt: summary.startedAt, champion: line.champion, kills: line.kills,
                           deaths: line.deaths, assists: line.assists, creepScore: line.creepScore, gold: line.gold,
                           won: known ? summary.result.winnerTeamId == teamId : nil,
                           winEstimated: summary.result.basis == .inferred)
    }
}
