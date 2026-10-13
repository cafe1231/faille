extension EventDetails {
    /// Détails reconstitués depuis un match de `getLive`, qui donne déjà ids d'équipe, victoires et games :
    /// les cartes de l'onglet Matchs n'ont ainsi pas besoin d'un appel `getEventDetails` par match.
    public init(event: MatchEvent) {
        self.init(
            id: event.id,
            league: event.league,
            match: Match(strategy: event.match.strategy, teams: event.match.teams, games: event.match.games ?? []),
            streams: event.streams
        )
    }

    /// Riot ne fournit pas les stats live de ce match (même règle que `MatchEvent.statsDisabled`).
    public var statsDisabled: Bool {
        streams?.contains { $0.statsStatus == "disabled" } ?? false
    }

    /// Game en cours, sinon nil.
    public var currentGame: GameRef? {
        match.games.first { $0.state == .inProgress }
    }
}
