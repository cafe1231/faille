import Foundation

/// Une carte Vitrail de l'onglet Matchs (spec §5.1) : une par équipe suivie.
public struct TeamCard: Sendable, Equatable, Identifiable {
    public let team: FollowedTeam
    public let live: MatchEvent?
    /// Prochain match du calendrier. Ne jamais l'afficher tel quel : passer par `Presenter.nextLine` (anti-spoiler, spec §8).
    public let next: MatchEvent?
    public let last: MatchEvent?

    public init(team: FollowedTeam, live: MatchEvent?, next: MatchEvent?, last: MatchEvent?) {
        self.team = team
        self.live = live
        self.next = next
        self.last = last
    }

    public var id: String { team.id }
}

public enum TeamCards {
    /// Cartes triées : équipes en direct d'abord (ordre de suivi), puis par date du prochain match, puis ordre de suivi.
    /// Anti-spoiler (spec §8) : une carte dont la ligne « Prochain » est masquée (`Presenter.nextLine` = `.hidden` : dernier
    /// match masqué, ou prochain match contre une autre équipe suivie en anti-spoiler) est triée comme une carte sans
    /// prochain match, pour que l'ordre ne trahisse pas l'existence de ce match.
    /// - Parameter live: réponse de `getLive`, ou `nil` si elle est inconnue (erreur réseau). Connue, elle fait seule foi :
    ///   un match `inProgress` du calendrier absent de `live` n'est pas en direct (calendrier périmé). Inconnue,
    ///   un match `inProgress` du calendrier peut servir de repli.
    /// - Parameter revealed: ids des matchs révélés par l'utilisateur.
    public static func build(follows: FollowList, schedule: [MatchEvent], live: [MatchEvent]?, revealed: Set<String>) -> [TeamCard] {
        let liveIds = Set((live ?? []).map(\.id))
        let cards = follows.teams.map { team -> TeamCard in
            let involves: (MatchEvent) -> Bool = { event in event.match.teams.contains { $0.isSame(as: team) } }
            let liveMatch: MatchEvent?
            if let live {
                liveMatch = live.first(where: involves)
            } else {
                liveMatch = schedule.first { involves($0) && $0.state == .inProgress }
            }
            let next = schedule
                .filter { involves($0) && $0.state == .unstarted && !liveIds.contains($0.id) }
                .min { $0.startTime < $1.startTime }
            let last = schedule
                .filter { involves($0) && $0.state == .completed }
                .max { $0.startTime < $1.startTime }
            return TeamCard(team: team, live: liveMatch, next: next, last: last)
        }
        return cards.enumerated().map { offset, card -> (offset: Int, element: TeamCard, nextStart: Date?) in
            var nextStart: Date?
            if case let .match(event) = Presenter.nextLine(for: card, follows: follows, revealed: revealed) {
                nextStart = event.startTime
            }
            return (offset, card, nextStart)
        }.sorted { a, b in
            switch (a.element.live != nil, b.element.live != nil) {
            case (true, false): return true
            case (false, true): return false
            case (true, true): return a.offset < b.offset
            case (false, false):
                switch (a.nextStart, b.nextStart) {
                case let (x?, y?): return x != y ? x < y : a.offset < b.offset
                case (.some, nil): return true
                case (nil, .some): return false
                case (nil, nil): return a.offset < b.offset
                }
            }
        }.map(\.element)
    }
}
