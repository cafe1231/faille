import Foundation

/// Construit les données de la Live Activity à partir de l'API (spec §6).
public enum LiveMatchBuilder {
    public static func attributes(for event: MatchEvent, follows: FollowList) -> LiveMatchAttributes {
        LiveMatchAttributes(
            matchId: event.id,
            leagueName: event.league.name,
            bestOf: event.bestOf,
            teams: event.match.teams.map { team in
                let followed = follows.teams.first { team.isSame(as: $0) }
                return LiveMatchAttributes.Side(id: team.id ?? team.code, code: team.code, name: team.name, colorHex: followed?.colorHex)
            }
        )
    }

    /// - Parameters:
    ///   - snapshot: dernière frame du flux pour la game en cours (ignorée si elle concerne une autre game).
    ///   - firstFrameTime: première frame de la game en cours (fenêtre demandée sans `startingTime`).
    ///   - statsDisabled: `MatchEvent.statsDisabled` ou 404 sur le flux.
    public static func state(
        details: EventDetails,
        snapshot: GameSnapshot?,
        firstFrameTime: Date?,
        statsDisabled: Bool,
        spoilerFree: Bool,
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
        if phase == .inGame, !statsDisabled, let snap {
            let perTeam = teams.compactMap { team in team.id.flatMap { snap.stats(for: $0) } }
            stats = perTeam.count == teams.count ? perTeam : nil
            if let firstFrameTime {
                clockStart = now.addingTimeInterval(-snap.timestamp.timeIntervalSince(firstFrameTime))
            }
        }

        let state = LiveMatchState(
            phase: phase,
            seriesScore: wins,
            gameNumber: gameNumber,
            gameClockStart: clockStart,
            stats: stats,
            statsAvailable: !statsDisabled,
            spoilerFree: false,
            winnerCode: phase == .finished ? Presenter.winnerCode(teams) : nil,
            updatedAt: now
        )
        return spoilerFree ? state.masked() : state
    }
}
