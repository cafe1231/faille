import Foundation

/// Une carte Vitrail de l'onglet Matchs (spec §5.1) : une par équipe suivie.
public struct TeamCard: Sendable, Equatable, Identifiable {
    public let team: FollowedTeam
    public let live: MatchEvent?
    /// Prochain match du calendrier. Ne jamais l'afficher tel quel : passer par `Presenter.nextLine` (anti-spoiler, spec §8).
    public let next: MatchEvent?
    public let last: MatchEvent?
    /// `next` suit un match masqué d'une équipe en anti-spoiler dans la même compétition internationale
    /// (`BracketMasking`) : `Presenter.nextLine` ne l'annonce pas (« Prochain · masqué »).
    public let nextBracketMasked: Bool
    /// `live` suit un match masque d'une equipe en anti-spoiler dans la meme competition internationale : il s'affiche
    /// comme un match masque (« En direct » sans score, `Presenter.scoreLine(bracketMasked:)`) jusqu'a revelation.
    public let liveBracketMasked: Bool
    /// Idem pour `last` : « Dernier · ... · Termine » sans resultat.
    public let lastBracketMasked: Bool

    public init(team: FollowedTeam, live: MatchEvent?, next: MatchEvent?, last: MatchEvent?,
                nextBracketMasked: Bool = false, liveBracketMasked: Bool = false, lastBracketMasked: Bool = false) {
        self.nextBracketMasked = nextBracketMasked
        self.liveBracketMasked = liveBracketMasked
        self.lastBracketMasked = lastBracketMasked
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
    /// match masqué, ou prochain match contre une autre équipe suivie en anti-spoiler au dernier match masqué) est triée
    /// comme une carte sans prochain match, pour que l'ordre ne trahisse pas l'existence de ce match.
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
        let baseMaskedLatest = Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: revealed)
        // Progression de tableau (I-1 généralisé) : le prochain match d'une carte qui suit un match masqué d'une équipe
        // en anti-spoiler dans la même compétition internationale n'est pas annoncé.
        let bracketHidden = BracketMasking.hiddenIds(schedule: schedule + (live ?? []), maskedTeamIds: baseMaskedLatest,
                                                     follows: follows, revealed: revealed)
        // Un match en direct ou termine de la carte place apres ce match masque ne montre pas non plus son score.
        let shownCards = bracketHidden.isEmpty ? cards : cards.map { card in
            let nextHidden = card.next.map { bracketHidden.contains($0.id) } ?? false
            let liveHidden = card.live.map { bracketHidden.contains($0.id) } ?? false
            let lastHidden = card.last.map { bracketHidden.contains($0.id) } ?? false
            guard nextHidden || liveHidden || lastHidden else { return card }
            return TeamCard(team: card.team, live: card.live, next: card.next, last: card.last,
                            nextBracketMasked: nextHidden, liveBracketMasked: liveHidden, lastBracketMasked: lastHidden)
        }
        let maskedLatest = Presenter.maskedLatestTeamIds(shownCards, follows: follows, revealed: revealed)
        return shownCards.enumerated().map { offset, card -> (offset: Int, element: TeamCard, nextStart: Date?) in
            var nextStart: Date?
            if case let .match(event) = Presenter.nextLine(for: card, follows: follows, revealed: revealed,
                                                           maskedLatestTeamIds: maskedLatest) {
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
