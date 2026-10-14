import Foundation

/// Série en cours d'une équipe (séries de matchs, du plus récent ; spec saison §1.5).
public struct Streak: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case wins
        case losses
    }

    public let kind: Kind
    public let count: Int

    public init(kind: Kind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

/// Une pastille de forme : victoire, défaite, ou match masqué (pastille neutre à sa place, §1.8).
public struct FormPip: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case win
        case loss
        case masked
    }

    public let matchId: String
    public let outcome: Outcome

    public init(matchId: String, outcome: Outcome) {
        self.matchId = matchId
        self.outcome = outcome
    }
}

/// Un champion joué : nombre de games et victoires (vainqueur exact ou déduit ; une game au vainqueur inconnu n'est
/// comptée ni en victoire ni en défaite). `winsEstimated` : au moins une game au vainqueur déduit (« estimé »).
public struct ChampionUse: Sendable, Equatable {
    public let champion: String
    public let games: Int
    public let wins: Int
    public let winsEstimated: Bool

    public init(champion: String, games: Int, wins: Int, winsEstimated: Bool) {
        self.champion = champion
        self.games = games
        self.wins = wins
        self.winsEstimated = winsEstimated
    }
}

/// Moyennes par game d'une équipe (games lues seulement). Morts = kills adverses.
public struct TeamAverages: Sendable, Equatable {
    public let kills: Double
    public let deaths: Double
    public let gold: Double
    public let towers: Double
    public let dragons: Double
    public let barons: Double
    public let inhibitors: Double
    public let durationSeconds: Double
    /// Écart de gold moyen à 15 min (équipe − adversaire) sur les `gold15Games` games enrichies ; nil sans aucune.
    public let gold15Diff: Double?
    public let gold15Games: Int

    public init(kills: Double, deaths: Double, gold: Double, towers: Double, dragons: Double, barons: Double,
                inhibitors: Double, durationSeconds: Double, gold15Diff: Double?, gold15Games: Int) {
        self.kills = kills
        self.deaths = deaths
        self.gold = gold
        self.towers = towers
        self.dragons = dragons
        self.barons = barons
        self.inhibitors = inhibitors
        self.durationSeconds = durationSeconds
        self.gold15Diff = gold15Diff
        self.gold15Games = gold15Games
    }
}

/// Saison d'une équipe dans un périmètre (§1.5), calculée à la lecture, jamais stockée. Bilans depuis les victoires de
/// série (exactes) ; moyennes depuis les games lues. Matchs masqués exclus de tout, comptés dans `maskedMatches`.
public struct TeamSeason: Sendable, Equatable {
    public let teamId: String
    public let scope: SeasonScope
    public let seriesWins: Int
    public let seriesLosses: Int
    public let gameWins: Int
    public let gameLosses: Int
    /// Série en cours (≥ 2) ; nil si plus courte, ou si le match le plus récent est masqué.
    public let streak: Streak?
    /// 5 derniers matchs, du plus ancien au plus récent (le plus récent à droite).
    public let form: [FormPip]
    /// Games jouées des matchs non masqués : lues, à lire, sans stats (échec définitif de la collecte).
    public let gamesCounted: Int
    public let gamesPending: Int
    public let gamesWithoutStats: Int
    /// Matchs masqués (jamais un nombre de games : il trahirait la longueur de la série, §1.8).
    public let maskedMatches: Int
    public let averages: TeamAverages?
    /// Drakes par type sur les games lues.
    public let dragonTypes: [String: Int]
    /// 8 champions les plus joués par l'équipe, par nombre de games.
    public let champions: [ChampionUse]

    public init(teamId: String, scope: SeasonScope, seriesWins: Int, seriesLosses: Int, gameWins: Int, gameLosses: Int,
                streak: Streak?, form: [FormPip], gamesCounted: Int, gamesPending: Int, gamesWithoutStats: Int,
                maskedMatches: Int, averages: TeamAverages?, dragonTypes: [String: Int], champions: [ChampionUse]) {
        self.teamId = teamId
        self.scope = scope
        self.seriesWins = seriesWins
        self.seriesLosses = seriesLosses
        self.gameWins = gameWins
        self.gameLosses = gameLosses
        self.streak = streak
        self.form = form
        self.gamesCounted = gamesCounted
        self.gamesPending = gamesPending
        self.gamesWithoutStats = gamesWithoutStats
        self.maskedMatches = maskedMatches
        self.averages = averages
        self.dragonTypes = dragonTypes
        self.champions = champions
    }
}

/// Face-à-face de deux équipes sur les matchs donnés (séries), masqués exclus et comptés.
public struct HeadToHead: Sendable, Equatable {
    public let teamA: String
    public let teamB: String
    public let winsA: Int
    public let winsB: Int
    /// Matchs comptés, du plus récent au plus ancien.
    public let matchIds: [String]
    public let maskedMatches: Int

    public init(teamA: String, teamB: String, winsA: Int, winsB: Int, matchIds: [String], maskedMatches: Int) {
        self.teamA = teamA
        self.teamB = teamB
        self.winsA = winsA
        self.winsB = winsB
        self.matchIds = matchIds
        self.maskedMatches = maskedMatches
    }
}
