import Foundation
import LoLKit

/// Une frame du fil gardée sur disque : la forme de `GameSnapshot` en JSON (`GameSnapshot` n'est pas `Codable`), relue
/// avec les inits publics de LoLKit.
struct CachedFrame: Codable, Sendable, Equatable {
    struct Player: Codable, Sendable, Equatable {
        let role: String
        let champion: String
        let name: String
        let level: Int
        let kills: Int
        let deaths: Int
        let assists: Int
        let creepScore: Int
        let gold: Int

        init(_ line: PlayerLine) {
            role = line.role
            champion = line.champion
            name = line.name
            level = line.level
            kills = line.kills
            deaths = line.deaths
            assists = line.assists
            creepScore = line.creepScore
            gold = line.gold
        }

        var line: PlayerLine {
            PlayerLine(role: role, champion: champion, name: name, level: level, kills: kills, deaths: deaths,
                       assists: assists, creepScore: creepScore, gold: gold)
        }
    }

    let gameId: String
    /// `GamePhase.rawValue` (`inGame`, `paused`, `finished`).
    let phase: String
    let timestamp: Date
    let blueTeamId: String
    let redTeamId: String
    let blue: TeamStats
    let red: TeamStats
    let bluePlayers: [Player]
    let redPlayers: [Player]

    init(_ snapshot: GameSnapshot) {
        gameId = snapshot.gameId
        phase = snapshot.phase.rawValue
        timestamp = snapshot.timestamp
        blueTeamId = snapshot.blueTeamId
        redTeamId = snapshot.redTeamId
        blue = snapshot.blue
        red = snapshot.red
        bluePlayers = snapshot.bluePlayers.map(Player.init)
        redPlayers = snapshot.redPlayers.map(Player.init)
    }

    var snapshot: GameSnapshot {
        GameSnapshot(gameId: gameId, phase: GamePhase(rawValue: phase) ?? .inGame, timestamp: timestamp,
                     blueTeamId: blueTeamId, redTeamId: redTeamId, blue: blue, red: red,
                     bluePlayers: bluePlayers.map(\.line), redPlayers: redPlayers.map(\.line))
    }
}

/// Relecture d'une game gardée sur disque (`replays/<gameId>.json`).
struct ReplayRecord: Codable, Sendable, Equatable {
    /// Première frame de la game (fenêtre lue sans `startingTime`) : le 0:00 du temps de jeu.
    var firstFrame: Date
    /// Première frame de la game, puis la dernière frame de chaque fenêtre de la relecture, dans l'ordre.
    var frames: [CachedFrame]
    /// Début de la dernière fenêtre lue : la relecture reprend au pas suivant.
    var lastStep: Date?
    /// La frame `finished` est lue : plus aucune requête pour cette game.
    var complete: Bool
}

/// Calendrier de la relecture d'une game (spec fonctionnalités §4) : une fenêtre `window` par minute pleine depuis le
/// début, comme la capture `window_replay.json` de LoLKit ; on garde la dernière frame de chacune (≈ 35 requêtes pour une
/// game de 35 min).
enum ReplaySchedule {
    /// Au plus 90 pas (90 min de jeu) : une relecture ne tourne jamais sans fin.
    static let maxSteps = 90
    /// Pause entre deux requêtes : le flux n'a montré aucune limite à ≈ 1 requête/s (spec §4.1), on reste en dessous.
    static let pause: Duration = .milliseconds(500)

    /// Débuts des fenêtres à lire : les minutes pleines à partir de `firstFrame`, après `after` (reprise d'une relecture),
    /// jusqu'à `until` compris (game en cours : `LiveStatsTime.startingTime(now:)`, jamais en avance sur la diffusion) ;
    /// `maxSteps` au plus depuis le début de la game.
    static func steps(firstFrame: Date, after: Date?, until: Date?) -> [Date] {
        let firstMinute = (firstFrame.timeIntervalSince1970 / 60).rounded(.up) * 60
        var steps: [Date] = []
        for index in 0..<maxSteps {
            let step = Date(timeIntervalSince1970: firstMinute + Double(index) * 60)
            if let after, step <= after { continue }
            if let until, step > until { break }
            steps.append(step)
        }
        return steps
    }
}
