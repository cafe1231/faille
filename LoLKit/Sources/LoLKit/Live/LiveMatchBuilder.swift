import Foundation

/// Construit les données de la Live Activity à partir de l'API (spec §6).
public enum LiveMatchBuilder {
    /// Attributs construits depuis `getEventDetails`, comme l'état : les équipes sont dans le même ordre que
    /// `state(...).seriesScore` et `.stats`. `nil` si une équipe n'a pas d'id (pas de repli sur le code, spec §4.2).
    public static func attributes(for details: EventDetails, follows: FollowList) -> LiveMatchAttributes? {
        let matchTeams = details.match.teams
        var sides: [LiveMatchAttributes.Side] = []
        for team in matchTeams {
            guard let id = team.id else { return nil }
            let followed = follows.teams.first { team.isSame(as: $0) }
            sides.append(LiveMatchAttributes.Side(id: id, code: team.code, name: team.name, colorHex: followed?.colorHex))
        }
        // L'équipe suivie depuis le plus longtemps (ordre de `FollowList.teams`) qui joue ce match.
        let primary = follows.teams.lazy
            .compactMap { followed in matchTeams.firstIndex { $0.isSame(as: followed) } }
            .first
        return LiveMatchAttributes(
            matchId: details.id,
            leagueName: details.league.name,
            bestOf: details.bestOf,
            teams: sides,
            primaryTeamIndex: primary
        )
    }

    /// - Parameters:
    ///   - snapshot: dernière frame du flux pour la game en cours (ignorée si elle concerne une autre game).
    ///   - firstFrameTime: première frame de la game en cours (fenêtre demandée sans `startingTime`).
    ///   - statsDisabled: `MatchEvent.statsDisabled` ou 404 sur le flux.
    ///   - follows: équipes suivies ; l'anti-spoiler est appliqué ici (`SpoilerPolicy`), jamais laissé à l'appelant.
    ///   - revealed: ids de matchs que l'utilisateur a choisi de révéler.
    public static func state(
        details: EventDetails,
        snapshot: GameSnapshot?,
        firstFrameTime: Date?,
        statsDisabled: Bool,
        follows: FollowList,
        revealed: Set<String>,
        now: Date
    ) -> LiveMatchState {
        let teams = details.match.teams
        let wins = teams.map(\.gameWins)
        let played = wins.reduce(0, +)
        let needed = details.bestOf / 2 + 1
        let current = details.match.games.first { $0.state == .inProgress }
        let snap = snapshot.flatMap { $0.gameId == current?.id ? $0 : nil }
        let feedFinished = snap?.phase == .finished

        // Le flux peut annoncer la fin d'une game qui décide peut-être la série avant que l'API ne mette à jour les victoires :
        // on reste « en direct » jusqu'à ce que l'API tranche.
        let seriesMayBeOver = feedFinished && (wins.max() ?? 0) >= needed - 1

        let phase: LiveMatchState.Phase
        if (wins.max() ?? 0) >= needed {
            phase = .finished
        } else if current != nil && (!feedFinished || seriesMayBeOver) {
            phase = .inGame
        } else if played > 0 || current != nil {
            phase = .betweenGames
        } else {
            phase = .upcoming
        }

        let gameNumber: Int?
        switch phase {
        case .upcoming: gameNumber = 1
        case .inGame: gameNumber = current?.number
        case .betweenGames: gameNumber = min(details.bestOf, max(played + 1, (current?.number ?? 0) + (feedFinished ? 1 : 0)))
        case .finished: gameNumber = nil
        }

        var stats: [TeamStats]?
        var clockStart: Date?
        var clockStoppedAt: Date?
        if phase == .inGame, let snap {
            // Le chrono ne dépend pas des stats : sans stats, la Live Activity montre quand même score + chrono (spec §6.3).
            if !statsDisabled {
                let perTeam = teams.compactMap { team in team.id.flatMap { snap.stats(for: $0) } }
                stats = perTeam.count == teams.count ? perTeam : nil
            }
            if let firstFrameTime {
                clockStart = now.addingTimeInterval(-snap.timestamp.timeIntervalSince(firstFrameTime))
            }
            // Game en pause ou terminée côté flux : le chrono s'arrête à l'instant de la dernière mise à jour.
            if snap.phase == .paused || snap.phase == .finished {
                clockStoppedAt = now
            }
        }

        let state = LiveMatchState(
            phase: phase,
            seriesScore: wins,
            gameNumber: gameNumber,
            gameClockStart: clockStart,
            gameClockStoppedAt: clockStoppedAt,
            stats: stats,
            statsAvailable: !statsDisabled,
            spoilerFree: false,
            winnerCode: phase == .finished ? Presenter.winnerCode(teams) : nil,
            updatedAt: now
        )
        let masked = SpoilerPolicy.isMasked(teams, matchId: details.id, follows: follows, revealed: revealed)
        return masked ? state.masked() : state
    }
}
