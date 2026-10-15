import Foundation
import LoLKit

/// Exécute la collecte de saison (spec saison §1.6) : la logique (quoi lire, dans quel ordre, quand réessayer, à quel
/// rythme) est dans LoLKit (`CrawlPlanner`, `CrawlPacer`) ; ici, les requêtes et leur rangement dans `SeasonStore`.
/// Toutes les requêtes passent par le `PacedTransport` du store (2 s entre deux, recul, budget de 300 par session).
@MainActor
struct SeasonCrawler {
    let store: SeasonStore
    let client: LoLClient
    let clock: any CrawlClock

    func run(context: @MainActor () -> SeasonContext) async -> CrawlEnd {
        while !Task.isCancelled {
            let now = await clock.now()
            var current = context()
            current.now = now
            do {
                try await enumerate(current)
                let masked = SeasonMasking.maskedMatchIds(store.matches, follows: current.follows,
                                                          revealed: current.revealed)
                let wanted = SeasonPlanning.wanted(current, byLeague: store.tournaments, standings: store.standings)
                let jobs = CrawlPlanner.jobs(wanted: wanted, matches: store.matches, have: store.games,
                                             failures: store.failures, masked: masked, now: now)
                store.setProgress(remaining: jobs.filter { $0.tier == .a }.count)
                guard let job = jobs.first else { return .done }
                try await read(job, followedTeamIds: Set(current.follows.teams.map(\.id)))
            } catch let stop as CrawlStopped {
                return stop.reason == .budget ? .budget : .failures
            } catch {
                if Task.isCancelled || PacedTransport.isCancellation(error) { return .cancelled }
                // 429, 5xx, réseau : le transport a déjà posé son recul ; on reprend au même endroit.
            }
        }
        return .cancelled
    }

    // MARK: Énumération

    /// Tournois des ligues voulues (24 h), puis résultats et classements de chaque tournoi de la saison déjà commencé :
    /// relus après 30 min s'il est en cours, jamais s'il est terminé et déjà lu. Le catalogue et les ligues du moment
    /// servent à la jointure.
    private func enumerate(_ context: SeasonContext) async throws {
        let now = context.now
        let leagueIds = SeasonPlanning.leagueIds(context)
        var wrote = false
        for leagueId in leagueIds {
            let key = SeasonStore.tournamentsKey(leagueId)
            guard CrawlPlanner.needsRefresh(fetchedAt: store.lastFetch(key), now: now,
                                            maxAge: CrawlPlanner.tournamentsMaxAge) else { continue }
            if let refs = try await fetch(key, now: now, { try await client.tournaments(leagueId: leagueId) }) {
                store.record(tournaments: refs, leagueId: leagueId, at: now)
                wrote = true
            }
        }
        let today = SeasonPlanning.day(now)
        let predecessors = SeasonPlanning.predecessorLeagueIds(context)
        for tournament in SeasonPlanning.startedTournaments(store.tournaments, leagueIds: leagueIds,
                                                            predecessorLeagueIds: predecessors, now: now) {
            // En cours : relu après 30 min ; terminé et déjà lu : jamais relu (`CrawlPlanner.maxAge` nil).
            let maxAge = CrawlPlanner.maxAge(of: tournament, today: today)
            let completedKey = SeasonStore.completedKey(tournament.id)
            // Terminé mais lu pendant qu'il était actif : une relecture (résultats et classement finaux).
            let lateReread = maxAge == nil
                && SeasonPlanning.readWhileActive(lastFetch: store.lastFetch(completedKey), endDate: tournament.endDate)
            if lateReread || CrawlPlanner.needsRefresh(fetchedAt: store.lastFetch(completedKey), now: now, maxAge: maxAge),
               let events = try await fetch(completedKey, now: now, {
                   try await client.completedEvents(tournamentId: tournament.id)
               }) {
                store.record(completed: events, tournamentId: tournament.id, at: now)
                wrote = true
            }
            let standingsKey = SeasonStore.standingsKey(tournament.id)
            let lateStandings = maxAge == nil
                && SeasonPlanning.readWhileActive(lastFetch: store.lastFetch(standingsKey), endDate: tournament.endDate)
            if lateStandings || CrawlPlanner.needsRefresh(fetchedAt: store.lastFetch(standingsKey), now: now, maxAge: maxAge),
               let value = try await fetch(standingsKey, now: now, {
                   try await client.standings(tournamentId: tournament.id)
               }) {
                store.record(standings: value, tournamentId: tournament.id, at: now)
                wrote = true
            }
        }
        // Jointure seulement après une écriture : `run` repasse ici avant chaque game (M17).
        if wrote { store.rejoin(catalog: context.catalog, leagues: context.leagues) }
    }

    /// Une liste de l'énumération. Refus définitif de l'API (4xx hors 429) ou réponse illisible : la liste est notée lue
    /// pour cette session (en mémoire seulement), sans quoi la passe la redemanderait sans fin ; 429, 5xx, réseau :
    /// l'erreur remonte (recul du transport).
    private func fetch<T>(_ key: String, now: Date, _ read: () async throws -> T) async throws -> T? {
        do {
            return try await read()
        } catch {
            if Self.mustPropagate(error) { throw error }
            store.markFetched(key, at: now)
            return nil
        }
    }

    /// Erreurs qui arrêtent ou font reculer la collecte, au lieu d'être rangées comme un échec de la donnée : arrêt de
    /// session, annulation, 429, 5xx, réseau.
    static func mustPropagate(_ error: any Error) -> Bool {
        if error is CrawlStopped || PacedTransport.isCancellation(error) || error is URLError { return true }
        if case let LoLAPIError.http(status) = error { return status == 429 || status >= 500 }
        return false
    }

    // MARK: Une game

    /// Palier A : début de la game (`window` sans `startingTime`) puis sa fin (`liveWindow`, recul compris) ; accepté
    /// seulement avec la frame `finished` (`GameSummary.make`), écrit en un seul fichier. Palier B : LoLKit n'enrichit pas
    /// une game déjà lue, `make` reçoit donc à nouveau le début et la fin, plus la fenêtre à 15 min et la dernière frame
    /// de `details` (4 requêtes), et réécrit le même fichier ; si ni l'une ni l'autre n'est fournie, la game est notée
    /// `noData` (réessai dans 1 h, 3 fois) au lieu d'être redemandée aussitôt.
    /// Erreurs : 404 → `statsDisabled` (définitif) ; 204 → `noData` ; game pas finie → `notFinished` (réessais de
    /// `CrawlPlanner`) ; 400 persistant ou réponse illisible (`CrawlFailure.reason` les range en `http`, jamais
    /// enregistré) → `noData`, sinon la même game serait redemandée sans fin ; 429, 5xx, réseau → l'erreur remonte, le
    /// transport recule, la game sera reprise.
    private func read(_ job: CrawlJob, followedTeamIds: Set<String>) async throws {
        let now = await clock.now()
        do {
            let first = try await client.window(gameId: job.gameId, startingTime: nil)
            let final = try await client.liveWindow(gameId: job.gameId, now: await clock.now())
            switch job.tier {
            case .a:
                guard let summary = GameSummary.make(first: first, final: final, at15: nil, details: nil,
                                                     matchId: job.matchId, number: job.number,
                                                     tournamentId: job.tournamentId, leagueSlug: job.leagueSlug)
                else {
                    store.recordFailure(.notFinished, gameId: job.gameId, at: now)
                    return
                }
                store.record(summary, followedTeamIds: followedTeamIds)
            case .b:
                guard let known = store.games[job.gameId] else { return }
                let start = first.frames.map(\.rfc460Timestamp).min() ?? known.startedAt
                let at15 = try await optional {
                    try await client.window(gameId: job.gameId, startingTime: SeasonPlanning.at15(start))
                }
                let details = try await optional { try await client.details(gameId: job.gameId, now: await clock.now()) }
                guard at15 != nil || details != nil,
                      var enriched = GameSummary.make(first: first, final: final, at15: at15, details: details,
                                                      matchId: job.matchId, number: job.number,
                                                      tournamentId: job.tournamentId, leagueSlug: job.leagueSlug)
                else {
                    store.recordFailure(.noData, gameId: job.gameId, at: now)
                    return
                }
                enriched.result = known.result
                store.record(enriched, followedTeamIds: followedTeamIds)
            }
        } catch {
            if Self.mustPropagate(error) { throw error }
            let reason = CrawlFailure.reason(for: error)
            store.recordFailure(reason == .http ? .noData : reason, gameId: job.gameId, at: now)
        }
    }

    /// Une lecture facultative du palier B : absente (204, 404, 400, illisible) → nil ; arrêt, annulation, 429, 5xx et
    /// réseau remontent.
    private func optional<T>(_ read: () async throws -> T) async throws -> T? {
        do {
            return try await read()
        } catch {
            if Self.mustPropagate(error) { throw error }
            return nil
        }
    }
}
