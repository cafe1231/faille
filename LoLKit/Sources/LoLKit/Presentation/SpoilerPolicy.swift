import Foundation

/// La règle anti-spoiler, unique pour toutes les surfaces (spec §8).
public enum SpoilerPolicy {
    /// Masqué si au moins une équipe suivie du match est en anti-spoiler, sauf si le match a été révélé.
    public static func isMasked(_ teams: [MatchTeam], matchId: String, follows: FollowList, revealed: Set<String>) -> Bool {
        guard !revealed.contains(matchId) else { return false }
        return follows.followed(in: teams).contains { $0.spoilerFree }
    }
}

/// Ce que l'appli et les widgets ont le droit d'afficher pour un match.
public struct ScoreLine: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case upcoming(Date)
        case live(gameNumber: Int?)
        case finished(winnerCode: String?)
    }

    public let matchId: String
    public let leagueName: String
    public let bestOf: Int
    public let teamCodes: [String]
    /// Victoires de chaque équipe ; `nil` si masqué ou pas commencé.
    public let score: [Int]?
    public let status: Status
    public let isMasked: Bool
}

public enum Presenter {
    public static func scoreLine(for event: MatchEvent, follows: FollowList, revealed: Set<String>) -> ScoreLine {
        let teams = event.match.teams
        let masked = SpoilerPolicy.isMasked(teams, matchId: event.id, follows: follows, revealed: revealed)
        let status: ScoreLine.Status
        let started: Bool
        switch event.state {
        case .inProgress:
            status = .live(gameNumber: masked ? nil : currentGameNumber(event))
            started = true
        case .completed:
            status = .finished(winnerCode: masked ? nil : teams.max { $0.gameWins < $1.gameWins }?.code)
            started = true
        case .unstarted, .unknown:
            status = .upcoming(event.startTime)
            started = false
        }
        return ScoreLine(
            matchId: event.id,
            leagueName: event.league.name,
            bestOf: event.bestOf,
            teamCodes: teams.map(\.code),
            score: (started && !masked) ? teams.map(\.gameWins) : nil,
            status: status,
            isMasked: masked
        )
    }

    /// Game en cours : celle marquée `inProgress`, sinon la suivante d'après les victoires.
    public static func currentGameNumber(_ event: MatchEvent) -> Int {
        if let game = event.match.games?.first(where: { $0.state == .inProgress }) { return game.number }
        return event.match.teams.reduce(0) { $0 + $1.gameWins } + 1
    }
}
