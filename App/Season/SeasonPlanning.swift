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

extension SeasonContext {
    /// Périmètre du tour (spec périmètre §3.1), recalculé depuis `now`.
    var window: SeasonWindow { SeasonWindow(now: now) }
}

/// Ce que l'appli assemble autour de `CrawlPlanner` (spec saison §1.2, §1.6 ; spec périmètre §3.1) : quelles ligues
/// énumérer, quels tournois de la fenêtre `SeasonWindow` lire (commencés), ce que veut la collecte. Les règles elles-mêmes
/// (fenêtre, tournoi en cours, étape en cours, fraîcheur, budget disque) sont dans LoLKit. Pur.
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

    /// Un tournoi aujourd'hui terminé dont la dernière lecture date de son temps actif (jusqu'à 2 jours après sa fin,
    /// comme `CrawlPlanner.maxAge`) n'a pas ses résultats ni son classement finaux : une relecture, une seule (la
    /// lecture suivante date d'après la fin). Jamais lu : à lire de toute façon. Pur.
    static func readWhileActive(lastFetch: Date?, endDate: String) -> Bool {
        guard let lastFetch else { return true }
        guard let end = plusDays(endDate, 2) else { return false }
        return day(lastFetch) <= end
    }

    /// « 2026-09-20 » + 2 → « 2026-09-22 » (nil si la date est illisible).
    static func plusDays(_ day: String, _ days: Int) -> String? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let start = utc.date(from: components),
              let end = utc.date(byAdding: .day, value: days, to: start) else { return nil }
        return Self.day(end)
    }

    /// 2026 : la saison est l'année civile (spec saison §1.2).
    static func year(_ date: Date) -> Int {
        utc.component(.year, from: date)
    }

    /// Ligues du calendrier de l'appli (`ScheduleQuery`), ligues suivies, ligue d'attache de l'équipe ouverte.
    private static func baseLeagueIds(_ context: SeasonContext) -> [String] {
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

    /// Ligues à énumérer : la base, plus les compétitions complètes (`SeasonWindow.completeLeagueSlugs`, ids lus dans
    /// `getLeagues` par slug, jamais en dur), plus les prédécesseurs des ligues de la base (saison N − 1 seule).
    static func leagueIds(_ context: SeasonContext) -> [String] {
        var ids = baseLeagueIds(context)
        for league in context.leagues where SeasonWindow.completeLeagueSlugs.contains(league.slug) && !ids.contains(league.id) {
            ids.append(league.id)
        }
        let predecessors = predecessorLeagueIds(context)
        for league in context.leagues where predecessors.contains(league.id) && !ids.contains(league.id) {
            ids.append(league.id)
        }
        return ids
    }

    /// Ligues lues seulement pour la saison N − 1 d'une ligue renommée (`SeasonWindow.predecessors`) : LTA North et Cross
    /// pour la LCS, LTA South et Cross pour le CBLOL ; jamais une ligue déjà voulue pour elle-même.
    static func predecessorLeagueIds(_ context: SeasonContext) -> Set<String> {
        let base = Set(baseLeagueIds(context))
        let slugs = context.leagues.filter { base.contains($0.id) }.flatMap { SeasonWindow.predecessors[$0.slug] ?? [] }
        return Set(context.leagues.filter { slugs.contains($0.slug) && !base.contains($0.id) }.map(\.id))
    }

    /// Tournois du périmètre de ces ligues déjà commencés (un tournoi à venir n'a ni résultat ni classement à lire), du
    /// plus récent au plus ancien ; d'une ligue prédécesseur, seulement ceux de la saison N − 1. Aucun tournoi `.outside`.
    static func startedTournaments(_ byLeague: [String: [TournamentRef]], leagueIds: [String],
                                   predecessorLeagueIds: Set<String> = [], now: Date) -> [TournamentRef] {
        let window = SeasonWindow(now: now)
        let today = day(now)
        let candidates = leagueIds.flatMap { leagueId in
            (byLeague[leagueId] ?? []).filter {
                !predecessorLeagueIds.contains(leagueId) || window.placement(of: $0) == .previous
            }
        }
        return window.tournaments(candidates).filter { !$0.startDate.isEmpty && $0.startDate <= today }
    }

    /// Tournois « en cours » (un par ligue : `CrawlPlanner.currentTournament`, l'actif sinon le dernier commencé).
    static func currentTournamentIds(_ byLeague: [String: [TournamentRef]], leagueIds: [String], now: Date) -> Set<String> {
        let today = day(now)
        return Set(leagueIds.compactMap { CrawlPlanner.currentTournament(byLeague[$0] ?? [], today: today)?.id })
    }

    /// Ce que veut la collecte (`CrawlWanted`, spec périmètre §3.2) : équipe ouverte, équipes suivies, étape en cours de
    /// chaque tournoi complet en cours, ligues suivies, tournois en cours (hors prédécesseurs), tournois du périmètre, de
    /// la saison N − 1 et des compétitions complètes.
    static func wanted(_ context: SeasonContext, byLeague: [String: [TournamentRef]],
                       standings: [String: Standings]) -> CrawlWanted {
        let ids = leagueIds(context)
        let window = context.window
        let today = day(context.now)
        let predecessors = predecessorLeagueIds(context)
        let completeLeagueIds = Set(context.leagues.filter { SeasonWindow.completeLeagueSlugs.contains($0.slug) }.map(\.id))
        var allowed = Set<String>(), previous = Set<String>(), complete = Set<String>()
        for leagueId in ids {
            for tournament in window.tournaments(byLeague[leagueId] ?? []) {
                let placement = window.placement(of: tournament)
                if predecessors.contains(leagueId) && placement != .previous { continue }
                allowed.insert(tournament.id)
                if placement == .previous { previous.insert(tournament.id) }
                if completeLeagueIds.contains(leagueId) { complete.insert(tournament.id) }
            }
        }
        let liveStage = completeLeagueIds.filter(ids.contains)
            .flatMap { byLeague[$0] ?? [] }
            .filter { window.contains($0) && $0.isActive(today: today) }
            .compactMap { standings[$0.id] }
            .reduce(into: Set<String>()) { $0.formUnion(CrawlPlanner.currentStageMatchIds($1)) }
        return CrawlWanted(openedTeamId: context.openedTeamId,
                           followedTeamIds: context.follows.teams.map(\.id),
                           liveCompleteStageMatchIds: liveStage,
                           followedLeagueSlugs: context.follows.leagues.map(\.slug),
                           currentTournamentIds: currentTournamentIds(byLeague, leagueIds: ids.filter { !predecessors.contains($0) },
                                                                      now: context.now),
                           allowedTournamentIds: allowed,
                           previousSeasonTournamentIds: previous,
                           completeTournamentIds: complete)
    }

    /// Heure de la fenêtre « à 15 min » du palier B : début de la game + 900 s, arrondi aux 10 s inférieures (le flux
    /// refuse un `startingTime` qui n'est pas un multiple de 10 s).
    static func at15(_ startedAt: Date) -> Date {
        let seconds = startedAt.timeIntervalSince1970 + 900
        return Date(timeIntervalSince1970: (seconds / 10).rounded(.down) * 10)
    }
}
