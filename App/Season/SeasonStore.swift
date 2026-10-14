import Foundation
import LoLKit
import Observation

/// Avancement de la collecte, pour « Les stats arrivent : 12 games lues sur 40 » (spec saison §2.2).
struct CrawlProgress: Sendable, Equatable {
    /// Games lues (sur disque).
    var read = 0
    /// Games que la collecte veut encore lire (palier A), d'après le dernier plan.
    var remaining = 0
    /// Une passe de collecte tourne.
    var running = false
}

/// Fin d'une passe de collecte.
enum CrawlEnd: Equatable, Sendable {
    /// Plus rien à lire.
    case done
    /// Budget de la session épuisé (300 requêtes).
    case budget
    /// 5 échecs d'affilée : arrêt jusqu'à la prochaine session.
    case failures
    /// Scène quittée.
    case cancelled
    /// Store d'aperçu : aucune requête.
    case inert
}

/// Données figées d'un `SeasonStore` d'aperçu (planches PNG, #Preview) : rien n'est lu sur le disque ni sur le réseau.
struct SeasonPreview: Sendable {
    var tournaments: [TournamentRef] = []
    var matches: [SeasonMatch] = []
    var games: [GameSummary] = []
    var standings: [String: Standings] = [:]
    var failures: [String: CrawlFailure] = [:]
    var progress = CrawlProgress()
    var isLoaded = true
}

/// Statistiques de saison (spec saison §1) : les `GameSummary` des games jouées (gardés pour toujours sur disque), les
/// tournois, résultats et classements, et la collecte progressive qui les remplit au premier plan. Les agrégats
/// (`TeamSeason`, `PlayerSeason`…) sont calculés par LoLKit à la lecture, jamais stockés ; ceux des équipes sont mémoïsés
/// tant qu'aucune game n'arrive. Anti-spoiler : la collecte ne demande jamais rien pour un match masqué
/// (`SeasonMasking` → `CrawlPlanner`), et chaque agrégat reçoit les matchs masqués à exclure.
@MainActor
@Observable
final class SeasonStore {
    // MARK: Données

    private(set) var games: [String: GameSummary] = [:]
    /// Tournois de chaque ligue (par id de ligue), du plus récent au plus ancien.
    private(set) var tournaments: [String: [TournamentRef]] = [:]
    /// Classements de chaque tournoi lu (par id de tournoi).
    private(set) var standings: [String: Standings] = [:]
    /// Matchs joués de tous les tournois lus (jointure résultats + classements, `SeasonMatch.join`).
    private(set) var matches: [SeasonMatch] = []
    private(set) var failures: [String: CrawlFailure] = [:]
    /// Le disque a été lu : avant, les écrans montrent leurs squelettes.
    private(set) var isLoaded = false
    private(set) var progress = CrawlProgress()
    /// Change à chaque game lue ou tournoi relu : clé de mémoïsation des écrans (Accueil).
    private(set) var version = 0
    /// Équipe dont la page est ouverte (collecte priorité 0 si elle n'est pas suivie).
    private(set) var openedTeamId: String?
    /// Pourquoi la collecte de la session s'est arrêtée (budget, échecs d'affilée) ; nil tant qu'elle peut continuer. Les
    /// écrans le disent (« Réseau indisponible, réessaie plus tard » après `.failures`).
    private(set) var stopReason: CrawlPacer.StopReason?

    // MARK: Interne

    @ObservationIgnored private var completed: [String: [CompletedMatch]] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var joinCatalog: [Team] = []
    @ObservationIgnored private var joinLeagues: [League] = []
    @ObservationIgnored private var teamMemo: [TeamSeasonKey: TeamSeason] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var wakeRequested = false
    @ObservationIgnored private var schedulePages: [String: SchedulePageResult] = [:]
    /// Games du disque d'un schéma plus récent : ignorées, jamais réécrites (une version suivante les relira).
    @ObservationIgnored private var newerGameIds: Set<String> = []
    let disk: SeasonDisk?
    let paced: PacedTransport?
    let clock: any CrawlClock

    /// - Parameters:
    ///   - transport: réseau de l'appli ; la collecte l'enveloppe dans un `PacedTransport` (cadence, recul, budget).
    ///   - cache: `cache/` de l'appli ; la saison vit sous `cache/season/`.
    ///   - clock: horloge des attentes (tests : horloge virtuelle).
    init(transport: any HTTPTransport, cache: DiskCache, clock: any CrawlClock = SystemCrawlClock()) {
        disk = SeasonDisk(cache: cache)
        paced = PacedTransport(base: transport, clock: clock)
        self.clock = clock
    }

    /// Aperçus : données figées, aucune requête, aucun fichier.
    init(preview: SeasonPreview) {
        disk = nil
        paced = nil
        clock = SystemCrawlClock()
        games = Dictionary(preview.games.map { ($0.gameId, $0) }, uniquingKeysWith: { first, _ in first })
        tournaments = Dictionary(grouping: preview.tournaments, by: \.leagueId)
        standings = preview.standings
        matches = preview.matches.sorted { $0.startTime > $1.startTime }
        failures = preview.failures
        progress = preview.progress
        isLoaded = preview.isLoaded
    }

    var isPreview: Bool {
        paced == nil
    }

    // MARK: Lecture du disque

    /// Lit `cache/season/` une fois, hors du fil principal (≈ 2 000 petits fichiers au plus), puis publie tout d'un coup.
    /// Les appels suivants attendent la première lecture.
    func loadFromDisk() async {
        if let loading {
            await loading.value
            return
        }
        guard let disk else {
            isLoaded = true
            return
        }
        let task = Task {
            let snapshot = await Task.detached(priority: .utility) { disk.load() }.value
            self.publish(snapshot)
        }
        loading = task
        await task.value
    }

    private func publish(_ snapshot: SeasonDisk.Snapshot) {
        games.merge(snapshot.games) { current, _ in current }
        for (leagueId, cached) in snapshot.tournaments where tournaments[leagueId] == nil {
            tournaments[leagueId] = cached.value
            fetchedAt[Self.tournamentsKey(leagueId)] = cached.fetchedAt
        }
        for (tournamentId, cached) in snapshot.completed where completed[tournamentId] == nil {
            completed[tournamentId] = cached.value
            fetchedAt[Self.completedKey(tournamentId)] = cached.fetchedAt
        }
        for (tournamentId, cached) in snapshot.standings where standings[tournamentId] == nil {
            standings[tournamentId] = cached.value
            fetchedAt[Self.standingsKey(tournamentId)] = cached.fetchedAt
        }
        failures.merge(snapshot.failures) { current, _ in current }
        newerGameIds.formUnion(snapshot.newerGameIds)
        rejoin()
        isLoaded = true
        version += 1
    }

    // MARK: Lectures pour les vues

    func tournament(id: String) -> TournamentRef? {
        tournaments.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    /// Matchs joués d'une équipe (id), du plus récent au plus ancien.
    func matches(ofTeam teamId: String) -> [SeasonMatch] {
        matches.filter { $0.teams.contains { $0.id == teamId } }
    }

    /// Games sans résumé en échec définitif de collecte (« N games sans stats ») ; une game lue au palier A dont le palier
    /// B échoue n'en fait pas partie.
    var withoutStats: Set<String> {
        Set(failures.filter { $0.value.isFinal && games[$0.key] == nil }.keys)
    }

    /// Bilan, forme, moyennes… d'une équipe sur un périmètre (`SeasonStats.team`), sans ses matchs masqués ; mémoïsé tant
    /// qu'aucune game n'arrive et que le jour ne change pas.
    func teamSeason(_ teamId: String, scope: SeasonScope, masked: Set<String>, now: Date) -> TeamSeason {
        let key = TeamSeasonKey(teamId: teamId, scope: scope, masked: masked, version: version,
                                day: SeasonPlanning.day(now))
        if let known = teamMemo[key] { return known }
        let value = SeasonStats.team(teamId, matches: matches, games: games, scope: scope, masked: masked, now: now,
                                     withoutStats: withoutStats)
        if teamMemo.count > 64 { teamMemo.removeAll() }
        teamMemo[key] = value
        return value
    }

    /// Stats de saison d'un joueur sur un périmètre (nil : toute la saison connue), sans les matchs masqués.
    func player(_ playerId: String, scope: SeasonScope?, masked: Set<String>) -> PlayerSeason? {
        let pool = scope.map { scope in games.values.filter { scope.tournamentIds.contains($0.tournamentId) } }
            ?? Array(games.values)
        return SeasonStats.player(playerId, games: pool, masked: masked, since: nil)
    }

    /// Périmètres d'une équipe (spec saison §3.1) : la saison (`SeasonScope.season`) puis un par tournoi de l'année où
    /// elle a joué (`SeasonScope.tournament`), du plus récent au plus ancien ; aucun si elle n'a joué aucun match connu.
    /// Les libellés sont des valeurs (année, slug) : l'écran les formule (`SeasonLabels.scope`).
    func scopes(forTeam teamId: String, now: Date) -> [SeasonScope] {
        let ids = Set(matches(ofTeam: teamId).map(\.tournamentId))
        let played = CrawlPlanner.seasonTournaments(tournaments.values.flatMap { $0 }, year: SeasonPlanning.year(now))
            .filter { ids.contains($0.id) }
        guard !played.isEmpty else { return [] }
        return [SeasonScope.season(SeasonPlanning.year(now), tournaments: played)] + played.map(SeasonScope.tournament)
    }

    /// Tournoi en cours de l'équipe (classement de sa page) : le plus récent de l'année où elle a joué.
    func currentTournament(forTeam teamId: String, now: Date) -> TournamentRef? {
        let ids = Set(matches(ofTeam: teamId).map(\.tournamentId))
        return tournaments.values.flatMap { $0 }
            .filter { ids.contains($0.id) && $0.startDate <= SeasonPlanning.day(now) }
            .max { ($0.startDate, $0.id) < ($1.startDate, $1.id) }
    }

    // MARK: Page d'équipe ouverte, réveil de la collecte

    /// Page d'équipe ouverte : la collecte passe d'abord par son tournoi en cours (priorité 0) si elle n'est pas suivie.
    func open(teamId: String) {
        openedTeamId = teamId
        wake()
    }

    /// Page fermée : la priorité 0 s'arrête (seulement si c'est bien elle qui était ouverte).
    func close(teamId: String) {
        if openedTeamId == teamId { openedTeamId = nil }
    }

    /// Quelque chose a changé ce que veut la collecte (suivi, révélation, page ouverte) : la boucle de la scène relance
    /// une passe sans attendre ses 30 min.
    func wake() {
        wakeRequested = true
    }

    /// Attente de la boucle de la scène entre deux passes : rend la main à un réveil (`wake`), après `maxSeconds`, ou à
    /// l'annulation de la tâche (scène quittée).
    func waitForWake(maxSeconds: TimeInterval) async {
        var waited: TimeInterval = 0
        while !wakeRequested && waited < maxSeconds && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
            waited += RefreshPolicy.tick
        }
        wakeRequested = false
    }

    /// Nouvelle session au premier plan (`AppStore.poll`) : budget et recul de la collecte remis à zéro.
    func beginSession() async {
        await paced?.beginSession()
        stopReason = nil
    }

    /// Relève la raison d'arrêt du transport (après une passe ou une requête à la demande).
    private func refreshStopReason() async {
        stopReason = await paced?.stopReason
    }

    // MARK: Collecte

    /// Une passe de collecte (spec saison §1.6), au premier plan seulement : énumération (tournois, résultats,
    /// classements), puis une game à la fois dans l'ordre de `CrawlPlanner` — replanifié après chaque game avec le
    /// contexte du moment (`context`). Rend la main quand il n'y a plus rien à lire, quand le budget de la session est
    /// épuisé, après 5 échecs d'affilée, ou quand la tâche est annulée.
    @discardableResult
    func crawl(context: @MainActor () -> SeasonContext) async -> CrawlEnd {
        guard let paced else { return .inert }
        // Une seule passe à la fois : une boucle relancée pendant qu'une ancienne s'annule ne lit pas deux fois la même
        // game, et le `defer` de l'ancienne ne remet pas `running` à faux sous la nouvelle (M9).
        guard !progress.running else { return .cancelled }
        progress.running = true
        defer { progress.running = false }
        await loadFromDisk()
        let crawler = SeasonCrawler(store: self, client: LoLClient(transport: paced), clock: clock)
        let end = await crawler.run(context: context)
        await refreshStopReason()
        return end
    }

    /// Une page `older` / `newer` du calendrier (spec saison §3.2), gardée en mémoire pour la session ; nil si elle n'a
    /// pas pu être lue. Passe par le transport de la collecte (cadence et budget communs).
    func schedulePage(leagueIds: [String], token: String?) async -> SchedulePageResult? {
        let key = leagueIds.joined(separator: ",") + "#" + (token ?? "")
        if let known = schedulePages[key] { return known }
        guard let paced else { return nil }
        let page = try? await LoLClient(transport: OnDemandTransport(paced: paced))
            .schedulePage(leagueIds: leagueIds, pageToken: token)
        await refreshStopReason()
        guard let page else { return nil }
        schedulePages[key] = page
        return page
    }

    /// Classement d'un tournoi ouvert à l'écran et pas encore lu par la collecte : une requête, au rythme de la collecte,
    /// par la réserve à la demande (une vingtaine par session, même après l'arrêt `.budget` de la collecte).
    func loadStandings(tournamentId: String) async {
        guard standings[tournamentId] == nil, let paced else { return }
        let loaded = try? await LoLClient(transport: OnDemandTransport(paced: paced))
            .standings(tournamentId: tournamentId)
        await refreshStopReason()
        guard let value = loaded else { return }
        record(standings: value, tournamentId: tournamentId, at: await clock.now())
    }

    // MARK: Écritures (collecte)

    static func tournamentsKey(_ leagueId: String) -> String { "tournaments/\(leagueId)" }
    static func completedKey(_ tournamentId: String) -> String { "completed/\(tournamentId)" }
    static func standingsKey(_ tournamentId: String) -> String { "standings/\(tournamentId)" }

    func lastFetch(_ key: String) -> Date? {
        fetchedAt[key]
    }

    /// Liste refusée par l'API ou illisible : notée lue pour la session (mémoire seulement), sans quoi la passe la
    /// redemanderait sans fin.
    func markFetched(_ key: String, at date: Date) {
        fetchedAt[key] = date
    }

    func record(tournaments value: [TournamentRef], leagueId: String, at date: Date) {
        tournaments[leagueId] = value
        fetchedAt[Self.tournamentsKey(leagueId)] = date
        disk?.save(tournaments: Cached(value: value, fetchedAt: date), leagueId: leagueId)
    }

    func record(completed value: [CompletedMatch], tournamentId: String, at date: Date) {
        completed[tournamentId] = value
        fetchedAt[Self.completedKey(tournamentId)] = date
        disk?.save(completed: Cached(value: value, fetchedAt: date), tournamentId: tournamentId)
    }

    func record(standings value: Standings, tournamentId: String, at date: Date) {
        standings[tournamentId] = value
        fetchedAt[Self.standingsKey(tournamentId)] = date
        disk?.save(standings: Cached(value: value, fetchedAt: date), tournamentId: tournamentId)
        rejoin()
    }

    /// Jointure résultats + classements de chaque tournoi lu (`SeasonMatch.join`), avec le catalogue et les ligues du
    /// moment ; recalcule les vainqueurs des séries complètes.
    func rejoin(catalog: [Team]? = nil, leagues: [League]? = nil) {
        if let catalog { joinCatalog = catalog }
        if let leagues { joinLeagues = leagues }
        var all: [SeasonMatch] = []
        for (tournamentId, events) in completed {
            let leagueId = tournament(id: tournamentId)?.leagueId
            let slug = joinLeagues.first { $0.id == leagueId }?.slug ?? ""
            all += SeasonMatch.join(completed: events, standings: standings[tournamentId], tournamentId: tournamentId,
                                    leagueSlug: slug, catalog: joinCatalog)
        }
        let sorted = all.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        if sorted != matches {
            matches = sorted
            teamMemo.removeAll()
            version += 1
        }
    }

    /// Une game lue (palier A, ou B qui réécrit le même fichier) : en mémoire, sur disque ; vainqueurs de sa série
    /// rejoués si toutes ses games jouées sont là ; games anciennes d'équipes non suivies supprimées au-delà de 2 000.
    func record(_ game: GameSummary, followedTeamIds: Set<String>) {
        games[game.gameId] = game
        failures[game.gameId] = nil
        persist(game)
        assignWinners(matchId: game.matchId)
        // Jamais la game qu'on vient d'écrire : sinon elle serait relue en boucle jusqu'au budget (M11).
        let excess = CrawlPlanner.evictions(Array(games.values), followedTeamIds: followedTeamIds)
            .filter { $0 != game.gameId }
        if !excess.isEmpty {
            for id in excess { games[id] = nil }
            disk?.deleteGames(excess)
        }
        progress.read = games.count
        teamMemo.removeAll()
        version += 1
    }

    /// Échec d'une game (`CrawlFailure.record` : essais comptés par raison ; `http` n'est jamais enregistré).
    func recordFailure(_ reason: CrawlFailure.Reason, gameId: String, at date: Date) {
        failures[gameId] = CrawlFailure.record(reason, previous: failures[gameId], now: date)
        disk?.save(failures: failures)
    }

    func setProgress(remaining: Int) {
        progress.read = games.count
        progress.remaining = remaining
    }

    /// `GameWinners.apply` dès que toutes les games jouées du match sont en cache (spec saison §1.6) ; seules les games
    /// dont le résultat change sont réécrites.
    private func assignWinners(matchId: String) {
        guard let match = matches.first(where: { $0.id == matchId }),
              match.playedGameIds.allSatisfy({ games[$0] != nil }) else { return }
        let updated = GameWinners.apply(teams: match.teams, playedGameIds: match.playedGameIds, to: games)
        for gameId in match.playedGameIds {
            guard let game = updated[gameId], game.result != games[gameId]?.result else { continue }
            games[gameId] = game
            persist(game)
        }
    }

    /// Écrit une game sur disque, sauf si le fichier est d'un schéma plus récent (on ne l'écrase pas).
    private func persist(_ game: GameSummary) {
        guard !newerGameIds.contains(game.gameId) else { return }
        disk?.save(game)
    }
}

/// Clé de mémoïsation d'un `TeamSeason`.
private struct TeamSeasonKey: Hashable {
    let teamId: String
    let scope: SeasonScope
    let masked: Set<String>
    let version: Int
    let day: String
}
