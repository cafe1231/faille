import Foundation

/// Une raison de regarder un match (spec saison §3.6). Une valeur : l'appli formule (« Tes équipes », « Élimination en
/// jeu »…) et l'explique dans « Comment c'est calculé ».
public enum MustWatchReason: Sendable, Equatable, Hashable {
    /// « Tes équipes » : +50 par équipe suivie (100 au plus).
    case followedTeam
    /// « Ta ligue » : +25.
    case followedLeague
    /// « Mondial », « MSI », « First Stand » (slug de la ligue) : +20.
    case international(slug: String)
    /// Suisse : une équipe à 2 défaites, +30.
    case elimination
    /// Suisse : une équipe à 2 victoires, +30.
    case qualification
    /// Suisse : les deux à la fois (« Tout se joue »), +40 au lieu de 60.
    case decider
    /// Phase finale : +40 / +30 / +20 ; play-offs d'une ligue : +20.
    case final
    case semiFinal
    case quarterFinal
    case playoffs
    /// « Choc du haut de tableau » : les deux équipes dans le top 3 du classement, +15.
    case topClash
    /// « Duel serré » : écart de rang ≤ 1, +10.
    case closeRanks
    /// « Revanche » : déjà affrontées cette saison (dernier match non masqué), +10.
    case rematch
    /// « Derby » : même ligue d'attache, à un international, +10.
    case derby
    /// Bo5 +10, Bo3 +5.
    case bestOf5
    case bestOf3
    /// « En direct » : +15.
    case live
}

/// Une raison et ses points.
public struct MustWatchScore: Sendable, Equatable {
    public let reason: MustWatchReason
    public let points: Int

    public init(reason: MustWatchReason, points: Int) {
        self.reason = reason
        self.points = points
    }
}

/// Un match proposé, ses points et ses raisons (les plus fortes d'abord).
public struct MustWatchPick: Sendable, Equatable, Identifiable {
    public let event: MatchEvent
    public let points: Int
    public let reasons: [MustWatchScore]

    public init(event: MatchEvent, points: Int, reasons: [MustWatchScore]) {
        self.event = event
        self.points = points
        self.reasons = reasons
    }

    public var id: String { event.id }

    /// Ligne d'explication : les 2 raisons qui rapportent le plus (« Tes équipes · Élimination en jeu »).
    public var explanation: [MustWatchReason] { reasons.prefix(2).map(\.reason) }
}

/// « À ne pas rater » (spec saison §3.6) : les matchs du jour classés par enjeu, score transparent en points entiers.
public enum MustWatch {
    /// Matchs proposés, par points décroissants puis heure de début.
    /// - Candidats : matchs en cours, et matchs à venir commençant aujourd'hui (jour local de `calendar`) ; moins de 3
    ///   → on ajoute ceux des prochaines 24 h. Exclus : un match d'une équipe suivie en anti-spoiler dont le dernier
    ///   match est masqué (règles F1 / C généralisées, `Presenter.maskedLatestTeamIds`), et « TBD contre TBD ».
    /// - Anti-spoiler : les raisons tirées de résultats (suisse, classement, revanche) valent 0 pour tous les matchs
    ///   d'un tournoi dont le tableau est masqué (`StandingsMasking`) : l'ordre ne trahit rien.
    /// - Parameters:
    ///   - standings: classements des tournois en cours, par id de tournoi (un match y est retrouvé par son id).
    ///   - seasonMatches: matchs joués de la saison (revanche).
    ///   - catalog: catalogue `getTeams` (ids d'équipe et ligues d'attache quand le classement ne les donne pas).
    public static func rank(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>,
                            revealedStandings: Set<String>, standings: [String: Standings], seasonMatches: [SeasonMatch],
                            catalog: [Team], now: Date, calendar: Calendar, limit: Int) -> [MustWatchPick] {
        let cards = TeamCards.build(follows: follows, schedule: schedule, live: nil, revealed: revealed)
        let maskedLatest = Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: revealed)
        let eligible = schedule.filter { event in
            guard event.state == .unstarted || event.state == .inProgress else { return false }
            if event.match.teams.allSatisfy(\.isPlaceholder) { return false }
            return !follows.followed(in: event.match.teams).contains { maskedLatest.contains($0.id) }
        }
        var candidates = eligible.filter { $0.state == .inProgress || calendar.isDate($0.startTime, inSameDayAs: now) }
        if candidates.count < 3 {
            let horizon = now.addingTimeInterval(24 * 3600)
            candidates += eligible.filter { event in
                event.state == .unstarted && event.startTime > now && event.startTime <= horizon
                    && !candidates.contains { $0.id == event.id }
            }
        }
        let maskedTables = Set(standings.filter { tournamentId, table in
            StandingsMasking.isMasked(table, tournamentId: tournamentId, follows: follows, revealed: revealed,
                                      revealedStandings: revealedStandings)
        }.keys)
        let picks = candidates.map { event in
            let reasons = score(event, follows: follows, revealed: revealed, standings: standings,
                                maskedTables: maskedTables, seasonMatches: seasonMatches, catalog: catalog)
            return MustWatchPick(event: event, points: reasons.reduce(0) { $0 + $1.points }, reasons: reasons)
        }
        return Array(picks.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.event.startTime != b.event.startTime { return a.event.startTime < b.event.startTime }
            return a.event.id < b.event.id
        }.prefix(limit))
    }

    /// Raisons d'un match, les plus fortes d'abord (ordre de déclaration à égalité).
    static func score(_ event: MatchEvent, follows: FollowList, revealed: Set<String>, standings: [String: Standings],
                      maskedTables: Set<String>, seasonMatches: [SeasonMatch], catalog: [Team]) -> [MustWatchScore] {
        var reasons: [MustWatchScore] = []
        let followedCount = min(2, follows.followed(in: event.match.teams).count)
        if followedCount > 0 { reasons.append(MustWatchScore(reason: .followedTeam, points: 50 * followedCount)) }
        if follows.league(slug: event.league.slug) != nil {
            reasons.append(MustWatchScore(reason: .followedLeague, points: 25))
        }
        let international = League.internationalSlugs.contains(event.league.slug)
        if international {
            reasons.append(MustWatchScore(reason: .international(slug: event.league.slug), points: 20))
        }
        let found = standings.first { $0.value.match(id: event.id) != nil }
        let bracket = found?.value.match(id: event.id)
        // Ids d'équipe : ceux du tableau s'il les connaît, sinon le catalogue (nom, logo).
        let bracketIds = bracket?.teams.filter { !$0.isPlaceholder }.compactMap(\.id) ?? []
        let teamIds = bracketIds.count == 2
            ? bracketIds
            : event.match.teams.map { SeasonMatch.resolve($0, in: catalog) }.compactMap(\.id)
        let resultsAllowed = found.map { !maskedTables.contains($0.key) } ?? true
        if let found, let stage = found.value.stage(containing: event.id) {
            let stageMatches = stage.sections.flatMap(\.matches)
            if stage.slug == "swiss", resultsAllowed {
                let records = StandingsTable.swissRecords(stageMatches).filter { record in
                    record.team.id.map { teamIds.contains($0) } ?? false
                }
                let eliminating = records.contains { $0.losses == 2 }
                let qualifying = records.contains { $0.wins == 2 }
                switch (eliminating, qualifying) {
                case (true, true): reasons.append(MustWatchScore(reason: .decider, points: 40))
                case (true, false): reasons.append(MustWatchScore(reason: .elimination, points: 30))
                case (false, true): reasons.append(MustWatchScore(reason: .qualification, points: 30))
                case (false, false): break
                }
            }
            if stage.slug == "knockouts", stageMatches.count == 7, let index = stageMatches.firstIndex(where: { $0.id == event.id }) {
                switch index {
                case 6: reasons.append(MustWatchScore(reason: .final, points: 40))
                case 4, 5: reasons.append(MustWatchScore(reason: .semiFinal, points: 30))
                default: reasons.append(MustWatchScore(reason: .quarterFinal, points: 20))
                }
            } else if let round = round(blockName: event.blockName) {
                reasons.append(round)
            }
            let ranks = found.value.stages.flatMap { $0.sections.flatMap(\.rankings) }
            if resultsAllowed, teamIds.count == 2,
               let first = ranks.first(where: { $0.teams.contains { $0.id == teamIds[0] } })?.ordinal,
               let second = ranks.first(where: { $0.teams.contains { $0.id == teamIds[1] } })?.ordinal {
                if first <= 3 && second <= 3 { reasons.append(MustWatchScore(reason: .topClash, points: 15)) }
                if abs(first - second) <= 1 { reasons.append(MustWatchScore(reason: .closeRanks, points: 10)) }
            }
        } else if let round = round(blockName: event.blockName) {
            reasons.append(round)
        }
        if resultsAllowed, teamIds.count == 2,
           let last = seasonMatches.filter({ $0.involves(teamIds[0]) && $0.involves(teamIds[1]) && $0.id != event.id })
               .max(by: { $0.startTime < $1.startTime }),
           !SpoilerPolicy.isMasked(last.teams, matchId: last.id, follows: follows, revealed: revealed) {
            reasons.append(MustWatchScore(reason: .rematch, points: 10))
        }
        if international, teamIds.count == 2 {
            let homes = teamIds.map { id in catalog.first { $0.id == id }?.homeLeague?.name }
            if let home = homes[0], home == homes[1] { reasons.append(MustWatchScore(reason: .derby, points: 10)) }
        }
        if event.bestOf == 5 { reasons.append(MustWatchScore(reason: .bestOf5, points: 10)) }
        if event.bestOf == 3 { reasons.append(MustWatchScore(reason: .bestOf3, points: 5)) }
        if event.state == .inProgress { reasons.append(MustWatchScore(reason: .live, points: 15)) }
        return reasons.enumerated().sorted { a, b in
            a.element.points != b.element.points ? a.element.points > b.element.points : a.offset < b.offset
        }.map(\.element)
    }

    /// Tour d'après le nom du bloc (« Finale », « Demi-finales », « Quarts de finale », « Play-offs »).
    static func round(blockName: String?) -> MustWatchScore? {
        guard let name = blockName?.lowercased() else { return nil }
        if name.contains("demi") || name.contains("semi") { return MustWatchScore(reason: .semiFinal, points: 30) }
        if name.contains("quart") || name.contains("quarter") { return MustWatchScore(reason: .quarterFinal, points: 20) }
        if name.contains("finale") || name == "final" || name == "finals" { return MustWatchScore(reason: .final, points: 40) }
        if name.contains("play-off") || name.contains("playoff") { return MustWatchScore(reason: .playoffs, points: 20) }
        return nil
    }
}
