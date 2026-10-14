import Foundation
import LoLKit

/// Fichiers de la saison sous `cache/season/` (spec saison §1.7), dans le `DiskCache` des fonctionnalités (exclu de la
/// sauvegarde iCloud) : une game jouée par fichier, gardée pour toujours (au-delà de 2 000, `CrawlPlanner.evictions`) ;
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
    }

    /// Lecture complète. Une game d'un schéma plus récent que celui que l'appli connaît est ignorée (pas supprimée : une
    /// version suivante de l'appli la relira, `GameSummary.decodeStored`) ; un fichier illisible aussi.
    func load() -> Snapshot {
        var snapshot = Snapshot()
        let decoder = JSONDecoder()
        for (id, data) in files(in: "season/games") {
            guard let game = GameSummary.decodeStored(data) else { continue }
            snapshot.games[id] = game
        }
        for (id, data) in files(in: "season/tournaments") {
            snapshot.tournaments[id] = try? decoder.decode(Cached<[TournamentRef]>.self, from: data)
        }
        for (id, data) in files(in: "season/completed") {
            snapshot.completed[id] = try? decoder.decode(Cached<[CompletedMatch]>.self, from: data)
        }
        for (id, data) in files(in: "season/standings") {
            snapshot.standings[id] = try? decoder.decode(Cached<Standings>.self, from: data)
        }
        snapshot.failures = cache.load([String: CrawlFailure].self, from: Self.failuresPath) ?? [:]
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
