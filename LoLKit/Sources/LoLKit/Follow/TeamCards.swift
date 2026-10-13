/// Une carte Vitrail de l'onglet Matchs (spec §5.1) : une par équipe suivie.
public struct TeamCard: Sendable, Equatable, Identifiable {
    public let team: FollowedTeam
    public let live: MatchEvent?
    public let next: MatchEvent?
    public let last: MatchEvent?

    public var id: String { team.id }
}

public enum TeamCards {
    /// Cartes triées : équipes en direct d'abord (ordre de suivi), puis par date du prochain match, puis ordre de suivi.
    public static func build(follows: FollowList, schedule: [MatchEvent], live: [MatchEvent]) -> [TeamCard] {
        let liveIds = Set(live.map(\.id))
        let cards = follows.teams.map { team -> TeamCard in
            let involves: (MatchEvent) -> Bool = { event in event.match.teams.contains { $0.isSame(as: team) } }
            let liveMatch = live.first(where: involves)
                ?? schedule.first { involves($0) && $0.state == .inProgress }
            let next = schedule
                .filter { involves($0) && $0.state == .unstarted && !liveIds.contains($0.id) }
                .min { $0.startTime < $1.startTime }
            let last = schedule
                .filter { involves($0) && $0.state == .completed }
                .max { $0.startTime < $1.startTime }
            return TeamCard(team: team, live: liveMatch, next: next, last: last)
        }
        return cards.enumerated().sorted { a, b in
            switch (a.element.live != nil, b.element.live != nil) {
            case (true, false): return true
            case (false, true): return false
            case (true, true): return a.offset < b.offset
            case (false, false):
                switch (a.element.next?.startTime, b.element.next?.startTime) {
                case let (x?, y?): return x != y ? x < y : a.offset < b.offset
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.offset < b.offset
                }
            }
        }.map(\.element)
    }
}
