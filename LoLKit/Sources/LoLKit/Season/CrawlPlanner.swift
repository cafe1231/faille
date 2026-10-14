import Foundation

/// Une game à lire par la collecte (spec saison §1.6).
public struct CrawlJob: Sendable, Equatable {
    /// Palier A : `window` sans `startingTime` + `window` après la fin (obligatoire). Palier B : `window` à 15 min +
    /// `details` (enrichissement).
    public enum Tier: String, Sendable, Equatable {
        case a = "A"
        case b = "B"
    }

    public let gameId: String
    public let matchId: String
    public let tournamentId: String
    public let leagueSlug: String
    /// N° de la game dans la série.
    public let number: Int
    public let tier: Tier
    /// Groupe de priorité, 0 = le plus urgent (voir `CrawlPlanner.jobs`).
    public let priority: Int

    public init(gameId: String, matchId: String, tournamentId: String, leagueSlug: String, number: Int, tier: Tier,
                priority: Int) {
        self.gameId = gameId
        self.matchId = matchId
        self.tournamentId = tournamentId
        self.leagueSlug = leagueSlug
        self.number = number
        self.tier = tier
        self.priority = priority
    }
}

/// Ce que la collecte doit couvrir (§1.6), rempli par l'appli.
public struct CrawlWanted: Sendable, Equatable {
    /// Équipe dont la page est ouverte (priorité 0 si elle n'est pas suivie : tournoi en cours seulement).
    public let openedTeamId: String?
    public let followedTeamIds: [String]
    /// Matchs de l'étape en cours du Mondial (`CrawlPlanner.currentStageMatchIds`).
    public let worldsStageMatchIds: Set<String>
    public let followedLeagueSlugs: [String]
    /// Tournois en cours : celui de chaque ligue concernée et l'international en cours.
    public let currentTournamentIds: Set<String>

    public init(openedTeamId: String?, followedTeamIds: [String], worldsStageMatchIds: Set<String>,
                followedLeagueSlugs: [String], currentTournamentIds: Set<String>) {
        self.openedTeamId = openedTeamId
        self.followedTeamIds = followedTeamIds
        self.worldsStageMatchIds = worldsStageMatchIds
        self.followedLeagueSlugs = followedLeagueSlugs
        self.currentTournamentIds = currentTournamentIds
    }
}

/// Échec de lecture d'une game (`cache/season/crawl.json`, seul état à mémoriser : le reste, c'est le disque).
public struct CrawlFailure: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable, Equatable {
        /// 404 : Riot ne fournit pas les stats de cette game → définitif.
        case statsDisabled
        /// 204 / vide → réessai après 1 h, 3 fois au plus.
        case noData
        /// Pas de frame `finished` → réessai après 1 h, 3 fois au plus.
        case notFinished
        /// 429, 5xx, réseau : suit le recul de `CrawlPacer`, jamais un échec de la game.
        case http
    }

    public var reason: Reason
    public var attempts: Int
    public var lastAttempt: Date

    public init(reason: Reason, attempts: Int, lastAttempt: Date) {
        self.reason = reason
        self.attempts = attempts
        self.lastAttempt = lastAttempt
    }

    /// Réessais de `noData` / `notFinished`, et délai entre deux essais.
    public static let maxAttempts = 3
    public static let retryDelay: TimeInterval = 3600

    /// Plus jamais réessayée : stats désactivées, ou 3 essais sans données / sans fin (« N games sans stats »).
    public var isFinal: Bool {
        switch reason {
        case .statsDisabled: true
        case .noData, .notFinished: attempts >= Self.maxAttempts
        case .http: false
        }
    }

    /// Peut-on retenter la game à `now` ?
    public func allowsRetry(now: Date) -> Bool {
        switch reason {
        case .http: true
        case .statsDisabled: false
        case .noData, .notFinished: !isFinal && now.timeIntervalSince(lastAttempt) >= Self.retryDelay
        }
    }

    /// Échec à enregistrer après une lecture ratée (`http` : rien, la game n'est pas en cause).
    public static func record(_ reason: Reason, previous: CrawlFailure?, now: Date) -> CrawlFailure? {
        guard reason != .http else { return previous }
        let attempts = previous?.reason == reason ? (previous?.attempts ?? 0) + 1 : 1
        return CrawlFailure(reason: reason, attempts: attempts, lastAttempt: now)
    }

    /// Raison d'une erreur de `LoLClient` : 404 → `statsDisabled`, vide → `noData`, le reste → `http`.
    public static func reason(for error: any Error) -> Reason {
        switch error as? LoLAPIError {
        case .statsDisabled: .statsDisabled
        case .noData: .noData
        default: .http
        }
    }
}

/// Planification pure de la collecte progressive (§1.6) : quelles games lire, dans quel ordre. L'appli exécute (au
/// premier plan seulement, avec `CrawlPacer`) ; l'état, c'est le disque (une game est faite si son `GameSummary`
/// existe) plus `crawl.json` pour les échecs.
public enum CrawlPlanner {
    /// Ordre des groupes : 0 page ouverte (équipe non suivie, tournoi en cours) ; 1 équipes suivies, saison entière ;
    /// 2 étape en cours du Mondial ; 3 ligues suivies, tournoi en cours puis précédents ; 4 palier B des équipes suivies
    /// (tournois en cours). Dans un groupe : tournoi en cours d'abord, puis le match le plus récent, puis le n° de game.
    /// **Jamais de job pour un match de `masked`** ; une game en échec n'est reprise que si `allowsRetry(now:)`.
    public static func jobs(wanted: CrawlWanted, matches: [SeasonMatch], have: [String: GameSummary],
                            failures: [String: CrawlFailure], masked: Set<String>, now: Date) -> [CrawlJob] {
        let followed = Set(wanted.followedTeamIds)
        let leagues = Set(wanted.followedLeagueSlugs)
        var best: [String: (job: CrawlJob, current: Bool, start: Date)] = [:]
        for match in matches where !masked.contains(match.id) && match.startTime <= now {
            let current = wanted.currentTournamentIds.contains(match.tournamentId)
            let teamIds = Set(match.teams.compactMap(\.id))
            var groups: [Int] = []
            if let opened = wanted.openedTeamId, !followed.contains(opened), teamIds.contains(opened), current {
                groups.append(0)
            }
            let involvesFollowed = !teamIds.isDisjoint(with: followed)
            if involvesFollowed { groups.append(1) }
            if wanted.worldsStageMatchIds.contains(match.id) { groups.append(2) }
            if leagues.contains(match.leagueSlug) { groups.append(3) }
            for (index, gameId) in match.playedGameIds.enumerated() {
                if let failure = failures[gameId], !failure.allowsRetry(now: now) { continue }
                let job: CrawlJob
                if let summary = have[gameId] {
                    guard !summary.enriched, involvesFollowed, current else { continue }
                    job = CrawlJob(gameId: gameId, matchId: match.id, tournamentId: match.tournamentId,
                                   leagueSlug: match.leagueSlug, number: index + 1, tier: .b, priority: 4)
                } else {
                    guard let group = groups.min() else { continue }
                    job = CrawlJob(gameId: gameId, matchId: match.id, tournamentId: match.tournamentId,
                                   leagueSlug: match.leagueSlug, number: index + 1, tier: .a, priority: group)
                }
                if let existing = best[gameId], existing.job.priority <= job.priority { continue }
                best[gameId] = (job, current, match.startTime)
            }
        }
        return best.values.sorted { a, b in
            if a.job.priority != b.job.priority { return a.job.priority < b.job.priority }
            if a.current != b.current { return a.current }
            if a.start != b.start { return a.start > b.start }
            if a.job.matchId != b.job.matchId { return a.job.matchId < b.job.matchId }
            return a.job.number < b.job.number
        }.map(\.job)
    }

    /// Tournois de la saison `year` (année civile, §1.2), du plus récent au plus ancien.
    public static func seasonTournaments(_ tournaments: [TournamentRef], year: Int) -> [TournamentRef] {
        tournaments.filter { $0.year == year }.sorted { ($0.startDate, $0.id) > ($1.startDate, $1.id) }
    }

    /// Tournoi en cours d'une ligue : l'actif (`isActive`), sinon le dernier commencé ; nil si aucun n'a commencé.
    public static func currentTournament(_ tournaments: [TournamentRef], today: String) -> TournamentRef? {
        let started = tournaments.filter { !$0.startDate.isEmpty && $0.startDate <= today }
            .sorted { ($0.startDate, $0.id) > ($1.startDate, $1.id) }
        return started.first { $0.isActive(today: today) } ?? started.first
    }

    /// Matchs de l'étape en cours du Mondial (§1.6, groupe 2) : l'étape qui contient le premier match non `completed`
    /// (dans l'ordre de l'API) ; si tout est joué, la dernière étape. Équipes encore inconnues comprises (rien à lire).
    public static func currentStageMatchIds(_ standings: Standings) -> Set<String> {
        let stage = standings.stages.first { stage in
            stage.sections.contains { $0.matches.contains { $0.state != .completed } }
        } ?? standings.stages.last
        return Set(stage?.sections.flatMap { $0.matches.map(\.id) } ?? [])
    }

    /// Budget disque (§1.7) : au-delà de `limit` games, ids à supprimer — les plus anciennes (`startedAt`) qui ne
    /// concernent aucune équipe suivie. Une game d'une équipe suivie n'est jamais supprimée (le cache peut alors
    /// dépasser la limite).
    public static let diskLimit = 2_000

    public static func evictions(_ games: [GameSummary], followedTeamIds: Set<String>,
                                 limit: Int = diskLimit) -> [String] {
        guard games.count > limit else { return [] }
        let removable = games
            .filter { !followedTeamIds.contains($0.blue.teamId) && !followedTeamIds.contains($0.red.teamId) }
            .sorted { ($0.startedAt, $0.gameId) < ($1.startedAt, $1.gameId) }
        return removable.prefix(games.count - limit).map(\.gameId)
    }

    /// Fraîcheur de l'énumération (§1.2) : tournois d'une ligue 24 h ; résultats et classements d'un tournoi actif
    /// 30 min ; d'un tournoi terminé, jamais relus (nil).
    public static let tournamentsMaxAge: TimeInterval = 86_400
    public static let activeTournamentMaxAge: TimeInterval = 1_800

    public static func maxAge(of tournament: TournamentRef, today: String) -> TimeInterval? {
        tournament.isActive(today: today) ? activeTournamentMaxAge : nil
    }

    /// À relire ? Pas de copie → oui ; `maxAge` nil → jamais ; sinon âge ≥ `maxAge` (ou horloge qui a reculé).
    public static func needsRefresh(fetchedAt: Date?, now: Date, maxAge: TimeInterval?) -> Bool {
        guard let fetchedAt else { return true }
        guard let maxAge else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age < 0 || age >= maxAge
    }
}
