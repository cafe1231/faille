import Foundation
import LoLKit

/// Fichiers de la saison sous `cache/season/` (spec saison §1.7), dans le `DiskCache` des fonctionnalités (exclu de la
/// sauvegarde iCloud) : une game jouée par fichier (au-delà de 4 000, `CrawlPlanner.evictions` ; rien d'avant N − 1) ;
/// les tournois d'une ligue, les résultats et classements d'un tournoi (fraîcheur : `CrawlPlanner.needsRefresh`) ; les
/// échecs de la collecte.
struct SeasonDisk: Sendable {
    let cache: DiskCache

    static func gamePath(_ gameId: String) -> String { "season/games/\(gameId).json" }
    static func tournamentsPath(_ leagueId: String) -> String { "season/tournaments/\(leagueId).json" }
    static func completedPath(_ tournamentId: String) -> String { "season/completed/\(tournamentId).json" }
    static func standingsPath(_ tournamentId: String) -> String { "season/standings/\(tournamentId).json" }
    static let failuresPath = "season/crawl.json"

    /// Tout ce que le disque connaît de la saison, lu en une fois au lancement (hors du fil principal).
    struct Snapshot: Sendable {
        var games: [String: GameSummary] = [:]
        var tournaments: [String: Cached<[TournamentRef]>] = [:]
        var completed: [String: Cached<[CompletedMatch]>] = [:]
        var standings: [String: Cached<Standings>] = [:]
        var failures: [String: CrawlFailure] = [:]
        /// Games d'un schéma plus récent que le nôtre : ignorées, et jamais réécrites par un recrawl.
        var newerGameIds: Set<String> = []
        /// Tournois écartés par la fenêtre (listes filtrées, fichiers supprimés) : jamais relus.
        var outsideTournamentIds: Set<String> = []
        /// Fichiers du Détail lus par `SeasonPurge` (0 quand le marqueur est à jour).
        var detailFilesRead = 0
    }

    private struct SchemaProbe: Decodable {
        let v: Int
    }

    /// Lecture complète, puis purge hors fenêtre (spec périmètre §3.3) : listes de tournois filtrées (et réécrites),
    /// résultats, classements et games hors fenêtre supprimés, échecs orphelins oubliés, caches du Détail purgés une fois
    /// par fenêtre (`SeasonPurge`). Une game d'un schéma plus récent que celui que l'appli connaît est ignorée (pas
    /// supprimée : une version suivante de l'appli la relira, `GameSummary.decodeStored`) ; un fichier illisible aussi.
    func load(window: SeasonWindow) -> Snapshot {
        var snapshot = Snapshot()
        let decoder = JSONDecoder()
        for (id, data) in files(in: "season/games") {
            guard let game = GameSummary.decodeStored(data) else {
                if let probe = try? decoder.decode(SchemaProbe.self, from: data), probe.v > GameSummary.schemaVersion {
                    snapshot.newerGameIds.insert(id)
                }
                continue
            }
            snapshot.games[id] = game
        }
        // Listes de tournois : filtrées par la fenêtre, réécrites si elles contenaient des tournois hors fenêtre.
        var known: [String: TournamentRef] = [:]
        for (leagueId, data) in files(in: "season/tournaments") {
            guard let cached = try? decoder.decode(Cached<[TournamentRef]>.self, from: data) else { continue }
            for tournament in cached.value { known[tournament.id] = tournament }
            let kept = window.tournaments(cached.value)
            if kept.count != cached.value.count {
                snapshot.outsideTournamentIds.formUnion(Set(cached.value.map(\.id)).subtracting(kept.map(\.id)))
                save(tournaments: Cached(value: kept, fetchedAt: cached.fetchedAt), leagueId: leagueId)
            }
            snapshot.tournaments[leagueId] = Cached(value: kept, fetchedAt: cached.fetchedAt)
        }
        for (id, data) in files(in: "season/completed") {
            snapshot.completed[id] = try? decoder.decode(Cached<[CompletedMatch]>.self, from: data)
        }
        for (id, data) in files(in: "season/standings") {
            snapshot.standings[id] = try? decoder.decode(Cached<Standings>.self, from: data)
        }
        // Résultats et classements hors fenêtre : les deux fichiers de chaque id.
        let lastMatchStart = snapshot.completed.compactMapValues { $0.value.map(\.startTime).max() }
        let outside = window.outsideTournamentIds(Set(snapshot.completed.keys).union(snapshot.standings.keys),
                                                  tournaments: known, lastMatchStart: lastMatchStart)
        for id in outside {
            for path in [Self.completedPath(id), Self.standingsPath(id)] {
                if let url = cache.url(path) { try? FileManager.default.removeItem(at: url) }
            }
            snapshot.completed[id] = nil
            snapshot.standings[id] = nil
        }
        snapshot.outsideTournamentIds.formUnion(outside)
        // Games hors fenêtre (jamais une game d'un schéma plus récent : elle n'est pas dans `games`).
        let outsideGames = window.outsideGameIds(Array(snapshot.games.values), tournaments: known)
        deleteGames(outsideGames)
        for id in outsideGames { snapshot.games[id] = nil }
        // Échecs : seulement ceux des games qu'un match restant référence.
        let failures = cache.load([String: CrawlFailure].self, from: Self.failuresPath) ?? [:]
        let referenced = Set(snapshot.completed.values.flatMap { $0.value.flatMap(\.gameIds) })
        snapshot.failures = failures.filter { referenced.contains($0.key) }
        if snapshot.failures.count != failures.count { save(failures: snapshot.failures) }
        snapshot.detailFilesRead = SeasonPurge(cache: cache).run(window: window)
        return snapshot
    }

    func save(_ game: GameSummary) {
        cache.save(game, to: Self.gamePath(game.gameId))
    }

    func save(tournaments: Cached<[TournamentRef]>, leagueId: String) {
        cache.save(tournaments, to: Self.tournamentsPath(leagueId))
    }

    func save(completed: Cached<[CompletedMatch]>, tournamentId: String) {
        cache.save(completed, to: Self.completedPath(tournamentId))
    }

    func save(standings: Cached<Standings>, tournamentId: String) {
        cache.save(standings, to: Self.standingsPath(tournamentId))
    }

    func save(failures: [String: CrawlFailure]) {
        cache.save(failures, to: Self.failuresPath)
    }

    func deleteGames(_ ids: [String]) {
        for id in ids {
            if let url = cache.url(Self.gamePath(id)) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Fichiers `<id>.json` d'un sous-dossier, par id.
    private func files(in folder: String) -> [(String, Data)] {
        guard let url = cache.url(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
        else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = try? Data(contentsOf: url.appendingPathComponent(name)) else { return nil }
            return (String(name.dropLast(".json".count)), data)
        }
    }
}
