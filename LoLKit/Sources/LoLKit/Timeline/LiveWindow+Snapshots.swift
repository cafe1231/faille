extension LiveWindow {
    /// Un `GameSnapshot` par frame, dans l'ordre du flux (le dernier est `latestSnapshot()`). Sert à rejouer une relecture
    /// mise en cache (une frame par pas de 60 s) dans `GameTimeline` et `GoldSeries`.
    public func snapshots() -> [GameSnapshot] {
        let blueMeta = gameMetadata.blueTeamMetadata
        let redMeta = gameMetadata.redTeamMetadata
        return frames.map { frame in
            GameSnapshot(
                gameId: esportsGameId,
                phase: GamePhase(apiValue: frame.gameState),
                timestamp: frame.rfc460Timestamp,
                blueTeamId: blueMeta.esportsTeamId,
                redTeamId: redMeta.esportsTeamId,
                blue: TeamStats(frame.blueTeam),
                red: TeamStats(frame.redTeam),
                bluePlayers: PlayerLine.lines(frame.blueTeam.participants, metadata: blueMeta.participantMetadata),
                redPlayers: PlayerLine.lines(frame.redTeam.participants, metadata: redMeta.participantMetadata)
            )
        }
    }
}
