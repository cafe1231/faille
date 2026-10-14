import Foundation

/// Une ligne de `ScoreboardPlayers` (Leaguepedia) : un joueur d'une game terminée.
public struct ScoreboardRow: Sendable, Equatable {
    /// Identifiant de la game chez Leaguepedia (ex. « LCS/2026 Season/Summer Playoffs_Finals_1_1 »).
    public let gameId: String
    /// Page du joueur (ex. « Josedeodo »).
    public let link: String?
    /// Nom Leaguepedia du champion (ex. « Lee Sin »).
    public let champion: String
    /// Noms anglais des sorts d'invocateur, dans l'ordre du wiki (ex. « Flash », « Smite »).
    public let summonerSpells: [String]
    /// Début de la game (`DateTime_UTC`, à la minute).
    public let dateTime: Date?

    public init(gameId: String, link: String?, champion: String, summonerSpells: [String], dateTime: Date?) {
        self.gameId = gameId
        self.link = link
        self.champion = champion
        self.summonerSpells = summonerSpells
        self.dateTime = dateTime
    }
}

/// Retrouve une game du flux dans Leaguepedia (spec fonctionnalités §3) : même ensemble de 10 champions, début à ± 3 h.
public enum SpellMatcher {
    /// Écart maximal entre le début de la game (flux) et `DateTime_UTC` (wiki).
    public static let window: TimeInterval = 3 * 3600

    /// Noms Leaguepedia → ids Data Dragon des sorts d'invocateur de la Faille.
    static let spellIds = [
        "Barrier": "SummonerBarrier", "Cleanse": "SummonerBoost", "Exhaust": "SummonerExhaust",
        "Flash": "SummonerFlash", "Ghost": "SummonerHaste", "Heal": "SummonerHeal", "Ignite": "SummonerDot",
        "Smite": "SummonerSmite", "Teleport": "SummonerTeleport", "Clarity": "SummonerMana",
    ]

    /// Id Data Dragon d'un sort nommé par Leaguepedia (« Ignite » → « SummonerDot ») ; nil si inconnu (pas d'image inventée).
    public static func dataDragonSpellId(_ name: String) -> String? {
        spellIds[name.trimmingCharacters(in: .whitespaces)]
    }

    /// Sorts d'invocateur de la game dont les champions sont exactement `champions` (comparés par `ChampionKey`) et dont le
    /// début est à `window` au plus de `around` ; la plus proche dans le temps s'il y en a plusieurs. nil si aucune (le
    /// wiki n'a pas encore la game) ou si `champions` contient un doublon.
    /// - Parameters:
    ///   - champions: ids Data Dragon du flux (`participantMetadata[].championId`), les 10 de la game.
    ///   - around: début de la game (`LiveWindow.firstFrameTime` de la fenêtre lue sans `startingTime`).
    /// - Returns: ids Data Dragon des sorts (« SummonerFlash ») par id de champion tel que donné dans `champions`.
    public static func match(champions: [String], around: Date, rows: [ScoreboardRow]) -> [String: [String]]? {
        var wanted: [String: String] = [:]
        for champion in champions { wanted[ChampionKey.normalized(champion)] = champion }
        guard !wanted.isEmpty, wanted.count == champions.count else { return nil }

        let candidates = Dictionary(grouping: rows, by: \.gameId).compactMap { gameId, players
            -> (gameId: String, distance: TimeInterval, players: [ScoreboardRow])? in
            guard let start = players.compactMap(\.dateTime).first else { return nil }
            let distance = abs(start.timeIntervalSince(around))
            let keys = players.map { ChampionKey.normalized($0.champion) }
            guard distance <= window, keys.count == wanted.count, Set(keys) == Set(wanted.keys) else { return nil }
            return (gameId, distance, players)
        }
        guard let best = candidates.min(by: { ($0.distance, $0.gameId) < ($1.distance, $1.gameId) }) else { return nil }

        var spells: [String: [String]] = [:]
        for player in best.players {
            guard let champion = wanted[ChampionKey.normalized(player.champion)] else { continue }
            spells[champion] = player.summonerSpells.compactMap(dataDragonSpellId)
        }
        return spells
    }
}
