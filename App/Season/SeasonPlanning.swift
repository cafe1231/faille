import Foundation
import LoLKit

/// Ce que la collecte doit savoir de l'appli à chaque tour (relu à chaque game : suivre une équipe, ouvrir une page
/// d'équipe ou révéler un match change aussitôt la suite).
struct SeasonContext: Sendable {
    var follows: FollowList
    var leagues: [League]
    var catalog: [Team]
    var revealed: Set<String>
    var openedTeamId: String?
    var now: Date
}

/// Ce que l'appli assemble autour de `CrawlPlanner` (spec saison §1.2, §1.6) : quelles ligues énumérer, quels tournois de
/// la saison lire (commencés), ce que veut la collecte. Les règles elles-mêmes (saison, tournoi en cours, étape en cours
/// du Mondial, fraîcheur, budget disque) sont dans LoLKit. Pur.
enum SeasonPlanning {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// « 2026-10-15 » (jour UTC : les dates des tournois de l'API sont des jours sans fuseau).
    static func day(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 2026 : la saison est l'année civile (spec saison §1.2).
    static func year(_ date: Date) -> Int {
        utc.component(.year, from: date)
    }

    /// Ligues à énumérer : celles du calendrier de l'appli (ligues d'attache des équipes suivies, ligues suivies,
    /// compétitions internationales — `ScheduleQuery`), plus la ligue d'attache de l'équipe dont la page est ouverte.
    static func leagueIds(_ context: SeasonContext) -> [String] {
        var ids = ScheduleQuery.leagueIds(follows: context.follows, leagues: context.leagues)
        for id in context.follows.leagues.map(\.id) where !ids.contains(id) {
            ids.append(id)
        }
        if let opened = context.openedTeamId,
           let home = context.catalog.first(where: { $0.id == opened })?.homeLeague?.name,
           let league = context.leagues.first(where: { $0.name == home }), !ids.contains(league.id) {
            ids.append(league.id)
        }
        return ids
    }

    /// Tournois de la saison de ces ligues déjà commencés (un tournoi à venir n'a ni résultat ni classement à lire), du
    /// plus récent au plus ancien (`CrawlPlanner.seasonTournaments`).
    static func startedTournaments(_ byLeague: [String: [TournamentRef]], leagueIds: [String], now: Date) -> [TournamentRef] {
        let today = day(now)
        return CrawlPlanner.seasonTournaments(leagueIds.flatMap { byLeague[$0] ?? [] }, year: year(now))
            .filter { !$0.startDate.isEmpty && $0.startDate <= today }
    }

    /// Tournois « en cours » (un par ligue : `CrawlPlanner.currentTournament`, l'actif sinon le dernier commencé).
    static func currentTournamentIds(_ byLeague: [String: [TournamentRef]], leagueIds: [String], now: Date) -> Set<String> {
        let today = day(now)
        return Set(leagueIds.compactMap { CrawlPlanner.currentTournament(byLeague[$0] ?? [], today: today)?.id })
    }

    /// Ce que veut la collecte (`CrawlWanted`) : équipe ouverte, équipes suivies, étape en cours du Mondial
    /// (`CrawlPlanner.currentStageMatchIds`), ligues suivies, tournois en cours.
    static func wanted(_ context: SeasonContext, byLeague: [String: [TournamentRef]],
                       standings: [String: Standings]) -> CrawlWanted {
        let ids = leagueIds(context)
        let worldsIds = context.leagues.filter { $0.slug == "worlds" }.map(\.id)
        let stage = currentTournamentIds(byLeague, leagueIds: worldsIds, now: context.now)
            .compactMap { standings[$0] }
            .reduce(into: Set<String>()) { $0.formUnion(CrawlPlanner.currentStageMatchIds($1)) }
        return CrawlWanted(openedTeamId: context.openedTeamId,
                           followedTeamIds: context.follows.teams.map(\.id),
                           worldsStageMatchIds: stage,
                           followedLeagueSlugs: context.follows.leagues.map(\.slug),
                           currentTournamentIds: currentTournamentIds(byLeague, leagueIds: ids, now: context.now))
    }

    /// Heure de la fenêtre « à 15 min » du palier B : début de la game + 900 s, arrondi aux 10 s inférieures (le flux
    /// refuse un `startingTime` qui n'est pas un multiple de 10 s).
    static func at15(_ startedAt: Date) -> Date {
        let seconds = startedAt.timeIntervalSince1970 + 900
        return Date(timeIntervalSince1970: (seconds / 10).rounded(.down) * 10)
    }
}
