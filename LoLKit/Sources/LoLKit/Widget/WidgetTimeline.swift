import Foundation

/// Planning des widgets (spec §7) : ce qu'ils montrent à chaque date, calculé seulement à partir des fichiers de
/// l'appli. Toutes les lignes passent par `Presenter.scoreLine` et `Presenter.nextLine` : les règles anti-spoiler
/// (spec §8) sont celles de l'appli.
///
/// Le cache vieillit pendant que l'appli dort. À la date d'une entrée, la source du « en direct » a trois états :
/// (a) un `getLive` en cache de moins de `RefreshPolicy.liveTrust` ; (b) à défaut, un calendrier de moins de `liveTrust`,
/// dont les matchs en cours servent de repli ; (c) rien de fiable. En (a) et (b), les widgets font comme l'appli : un
/// match `unstarted` dont l'heure prévue est passée reste « à venir » (compte à rebours à zéro). En (c) seulement, ils
/// sont plus stricts que l'appli : un match commencé (en cours dans le calendrier, ou heure de début passée) a une issue
/// inconnue ; il n'est ni en direct ni à venir, et compte comme dernier match de ses équipes, pour que la ligne
/// « Prochain » d'une équipe en anti-spoiler reste « masqué » (règle F1). L'appli, elle, l'afficherait encore
/// « Prochain » : elle se rafraîchit à l'ouverture, pas l'extension, qui ne doit pas annoncer un match que rien ne
/// confirme plus.
public enum WidgetTimeline {
    /// Rechargement au plus tard 30 min après le calcul (spec §7), ou au prochain début de match s'il est plus proche.
    public static let reloadInterval: TimeInterval = 30 * 60
    /// Les entrées couvrent les 6 h qui viennent : si iOS tarde à recharger, le widget reste juste.
    public static let horizon: TimeInterval = 6 * 3600
    /// Pas du compte à rebours pendant la dernière heure avant un match.
    public static let countdownStep: TimeInterval = 5 * 60

    /// Ce que montrent les widgets à `date`.
    public static func content(at date: Date, input: WidgetInput) -> WidgetContent {
        let follows = input.follows
        let revealed = input.settings.revealedMatchIds
        let source = liveSource(at: date, input: input)
        let schedule = presumed(input.schedule?.value.events ?? [], at: date, source: source)
        let cards = TeamCards.build(follows: follows, schedule: schedule, live: source.live, revealed: revealed)

        var liveLines: [WidgetLine] = []
        var upcoming: [WidgetLine] = []
        var next: [String: WidgetTeam.Next] = [:]
        for card in cards {
            if let event = card.live,
               let line = makeLine(for: event, card: card, follows: follows, revealed: revealed), line.isLive {
                next[card.team.id] = .live(line)
                if !liveLines.contains(where: { $0.matchId == line.matchId }) {
                    liveLines.append(line)
                }
            }
            // Jamais `card.next` directement : la ligne « Prochain » passe par LoLKit (anti-spoiler, spec §8).
            let shown: WidgetTeam.Next
            switch Presenter.nextLine(for: card, follows: follows, revealed: revealed) {
            case .hidden:
                shown = .hidden
            case .none:
                shown = .noMatch
            case let .match(event):
                if let line = makeLine(for: event, card: card, follows: follows, revealed: revealed), !line.isLive {
                    shown = .match(line)
                    if !upcoming.contains(where: { $0.matchId == line.matchId }) {
                        upcoming.append(line)
                    }
                } else {
                    shown = .noMatch
                }
            }
            if next[card.team.id] == nil {
                next[card.team.id] = shown
            }
        }
        let byStart = upcoming.enumerated().sorted { a, b in
            let x = a.element.upcomingStart ?? .distantFuture
            let y = b.element.upcomingStart ?? .distantFuture
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
        return WidgetContent(
            date: date,
            teams: follows.teams.map { WidgetTeam(team: $0, next: next[$0.id] ?? .noMatch) },
            lines: liveLines + byStart
        )
    }

    /// Dates des entrées : maintenant ; le début de chaque match à venir d'une équipe suivie ; les paliers de son compte
    /// à rebours (chaque heure pleine avant le début, puis toutes les 5 min pendant la dernière heure) ; la fin de
    /// confiance du direct et du calendrier. Toutes dans `[now, now + horizon]`, triées, sans doublon.
    public static func entryDates(now: Date, input: WidgetInput) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        func add(_ date: Date) {
            if date > now && date <= end {
                dates.insert(date)
            }
        }
        for start in upcomingStarts(input) where start > now {
            add(start)
            for hours in 1..<48 {
                add(start.addingTimeInterval(-Double(hours) * 3600))
            }
            for steps in 1..<12 {
                add(start.addingTimeInterval(-Double(steps) * countdownStep))
            }
        }
        // Passé cette date, « en direct » n'est plus cru : l'entrée suivante ne l'affiche plus.
        if let live = input.live {
            add(live.fetchedAt.addingTimeInterval(RefreshPolicy.liveTrust + 1))
        }
        if let schedule = input.schedule {
            add(schedule.fetchedAt.addingTimeInterval(RefreshPolicy.liveTrust + 1))
        }
        return dates.sorted()
    }

    /// Prochain rechargement (spec §7) : au prochain début de match d'une équipe suivie, au plus tard dans 30 min.
    public static func reloadDate(now: Date, input: WidgetInput) -> Date {
        let latest = now.addingTimeInterval(reloadInterval)
        guard let next = upcomingStarts(input).filter({ $0 > now }).min() else { return latest }
        return min(next, latest)
    }

    // MARK: - Interne

    /// Débuts des matchs pas encore commencés (dans le cache) d'au moins une équipe suivie.
    static func upcomingStarts(_ input: WidgetInput) -> [Date] {
        (input.schedule?.value.events ?? [])
            .filter { $0.state == .unstarted && input.follows.involves($0.match.teams) }
            .map(\.startTime)
    }

    /// D'où vient le « en direct » à une date (voir l'en-tête de `WidgetTimeline`).
    enum LiveSource: Equatable {
        /// (a) `getLive` en cache, assez récent pour faire foi.
        case liveCache([MatchEvent])
        /// (b) Pas de direct fiable, mais un calendrier assez récent : ses matchs en cours servent de repli.
        case freshSchedule
        /// (c) Rien de fiable : personne n'est donné pour en direct, un vieux calendrier ne dit plus qui joue.
        case nothingReliable

        /// Réponse de `getLive` pour `TeamCards.build` ; nil quand elle est inconnue (les cartes se replient alors sur
        /// les matchs en cours du calendrier, comme dans l'appli).
        var live: [MatchEvent]? {
            switch self {
            case let .liveCache(events): return events
            case .freshSchedule: return nil
            case .nothingReliable: return []
            }
        }

        /// Une donnée fraîche existe : ce qu'elle ne dit pas ne permet pas de présumer un match commencé.
        var isReliable: Bool {
            if case .nothingReliable = self { return false }
            return true
        }
    }

    static func liveSource(at date: Date, input: WidgetInput) -> LiveSource {
        if let live = RefreshPolicy.usableLive(input.live, now: date) {
            return .liveCache(live)
        }
        if let schedule = input.schedule {
            let age = schedule.age(now: date)
            if age >= 0 && age <= RefreshPolicy.liveTrust {
                return .freshSchedule
            }
        }
        return .nothingReliable
    }

    /// Le calendrier vu à `date`. Un match commencé que rien de frais ne confirme devient « terminé » : en cours dans
    /// un calendrier qui ne fait plus foi, ou en cours dans le calendrier mais absent d'un direct frais. Un match
    /// `unstarted` dont l'heure est passée n'est présumé commencé que dans le cas (c) : avec une donnée fraîche, il
    /// reste « à venir », comme sur la carte de l'appli. Un match présumé terminé n'est plus ni en direct ni à venir,
    /// mais reste le dernier match de ses équipes : si l'une est en anti-spoiler, leur ligne « Prochain » reste
    /// masquée (spec §8).
    static func presumed(_ events: [MatchEvent], at date: Date, source: LiveSource) -> [MatchEvent] {
        let liveIds = Set((source.live ?? []).map(\.id))
        return events.map { event in
            if liveIds.contains(event.id) { return event }
            let started: Bool
            switch event.state {
            case .inProgress: started = source.live != nil
            case .unstarted: started = !source.isReliable && event.startTime <= date
            case .completed, .unknown: started = false
            }
            guard started else { return event }
            return MatchEvent(startTime: event.startTime, state: .completed, type: event.type, blockName: event.blockName,
                              league: event.league, match: event.match, streams: event.streams)
        }
    }

    /// Ligne d'un match pour la carte d'une équipe : ordre d'affichage (l'équipe de la carte à gauche), score et
    /// numéro de game de `Presenter.scoreLine` (nil si masqué). nil pour un match terminé : les widgets ne montrent
    /// que le direct et l'à-venir.
    static func makeLine(for event: MatchEvent, card: TeamCard, follows: FollowList,
                         revealed: Set<String>) -> WidgetLine? {
        let scoreLine = Presenter.scoreLine(for: event, follows: follows, revealed: revealed)
        let order = follows.displayOrder(event.match.teams, preferring: card.team)
        let teams = reorder(event.match.teams, order) ?? event.match.teams
        let status: WidgetLine.Status
        switch scoreLine.status {
        case let .live(gameNumber):
            status = .live(score: scoreLine.score.flatMap { reorder($0, order) }, gameNumber: gameNumber)
        case let .upcoming(start):
            status = .upcoming(start)
        case .finished:
            return nil
        }
        return WidgetLine(
            matchId: event.id,
            leagueName: event.league.name,
            codes: teams.map(\.code),
            colorHexes: teams.map { team in follows.teams.first { team.isSame(as: $0) }?.colorHex },
            status: status,
            isMasked: scoreLine.isMasked
        )
    }
}
