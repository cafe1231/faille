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

    public init(matchId: String, leagueName: String, bestOf: Int, teamCodes: [String], score: [Int]?,
                status: Status, isMasked: Bool) {
        self.matchId = matchId
        self.leagueName = leagueName
        self.bestOf = bestOf
        self.teamCodes = teamCodes
        self.score = score
        self.status = status
        self.isMasked = isMasked
    }
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
            status = .finished(winnerCode: masked ? nil : winnerCode(teams))
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

    /// Vainqueur d'un match terminé : l'équipe marquée `outcome == "win"`, sinon l'unique équipe au plus grand nombre de victoires (> 0), sinon nil.
    static func winnerCode(_ teams: [MatchTeam]) -> String? {
        let marked = teams.filter { $0.result?.outcome == "win" }
        if marked.count == 1 { return marked[0].code }
        let best = teams.map(\.gameWins).max() ?? 0
        guard best > 0 else { return nil }
        let leaders = teams.filter { $0.gameWins == best }
        return leaders.count == 1 ? leaders[0].code : nil
    }

    /// Game en cours : celle marquée `inProgress`, sinon la suivante d'après les victoires.
    static func currentGameNumber(_ event: MatchEvent) -> Int {
        if let game = event.match.games?.first(where: { $0.state == .inProgress }) { return game.number }
        return event.match.teams.reduce(0) { $0 + $1.gameWins } + 1
    }
}
