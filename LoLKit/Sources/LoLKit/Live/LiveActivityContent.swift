import Foundation

/// Contenu d'une Live Activity à un instant (spec §4.3, §6) : les attributs pour la démarrer, l'état (anti-spoiler
/// compris) et les équipes de la source dans l'ordre de cet état — pour le ramener à l'ordre fixé au démarrage.
public struct LiveActivityContent: Sendable, Equatable {
    /// Équipes de la source (`getLive`, calendrier…), dans l'ordre de `state.seriesScore` et `state.stats`.
    public let teams: [MatchTeam]
    /// Attributs pour démarrer une Live Activity ; nil si une équipe n'a pas d'id (calendrier) : on n'en démarre pas.
    public let attributes: LiveMatchAttributes?
    public let state: LiveMatchState

    public init(teams: [MatchTeam], attributes: LiveMatchAttributes?, state: LiveMatchState) {
        self.teams = teams
        self.attributes = attributes
        self.state = state
    }

    /// Contenu tiré de détails de match : attributs de `LiveMatchBuilder.attributes` (couleurs et équipe principale
    /// d'après les équipes suivies), équipes dans l'ordre des détails, donc de `state`.
    public init(details: EventDetails, state: LiveMatchState, follows: FollowList) {
        self.init(teams: details.match.teams,
                  attributes: LiveMatchBuilder.attributes(for: details, follows: follows),
                  state: state)
    }
}

extension LiveMatchState {
    /// Score de série et stats remis dans l'ordre des équipes de `attributes` (fixé au démarrage de la Live Activity) :
    /// chaque équipe est reconnue par son id, sinon son nom (sans la casse), sinon, en dernier recours, son code.
    /// Le repli par code n'est sûr qu'à l'intérieur d'un même match de deux équipes (spec §4.2 : plusieurs équipes
    /// actives partagent le même code, jamais le code seul entre équipes quelconques) : les deux équipes d'un match
    /// se distinguent par leur code, mais `teams` doit être celles du match des `attributes`, pas d'un autre match.
    /// Inchangé si une équipe n'est pas reconnue.
    public func aligned(from teams: [MatchTeam], to attributes: LiveMatchAttributes) -> LiveMatchState {
        guard teams.count == attributes.teams.count else { return self }
        var order: [Int] = []
        for side in attributes.teams {
            guard let index = teams.firstIndex(where: { Self.isSame($0, side) }), !order.contains(index) else {
                return self
            }
            order.append(index)
        }
        var copy = self
        copy.seriesScore = seriesScore.flatMap { reorder($0, order) }
        copy.stats = stats.flatMap { reorder($0, order) }
        return copy
    }

    static func isSame(_ team: MatchTeam, _ side: LiveMatchAttributes.Side) -> Bool {
        if let id = team.id { return id == side.id }
        if team.name.lowercased() == side.name.lowercased() { return true }
        return team.code == side.code
    }
}
