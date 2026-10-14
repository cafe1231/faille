import Foundation

/// Vainqueur d'une game (spec saison §1.4) : l'API ne le donne nulle part, `GameWinners.assign` le déduit de la série.
public struct GameResult: Codable, Sendable, Equatable {
    public enum Basis: String, Codable, Sendable, Equatable {
        /// Certain : Bo1, série gagnée sans perdre de game, ou dernière game de la série.
        case exact
        /// Déduit des tours détruites : à étiqueter « estimé ».
        case inferred
        /// Inconnu : pas toutes les games en cache, ou marges trop proches.
        case unknown

        /// Valeur inconnue (version plus récente) → `.unknown`.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Basis(rawValue: raw) ?? .unknown
        }
    }

    public var winnerTeamId: String?
    public var basis: Basis

    public init(winnerTeamId: String?, basis: Basis) {
        self.winnerTeamId = winnerTeamId
        self.basis = basis
    }

    public static let unknown = GameResult(winnerTeamId: nil, basis: .unknown)
}

/// Une game jouée, réduite à ses valeurs utiles (~2,2 Ko palier A, ~3,2 Ko palier B) et gardée pour toujours dans
/// `cache/season/games/<gameId>.json` (spec saison §1.5, §1.7). Jamais le JSON brut du flux.
public struct GameSummary: Codable, Sendable, Equatable, Identifiable {
    /// Version du schéma : un fichier d'une version plus récente est ignoré (`decodeStored`), une plus ancienne relue
    /// telle quelle (champs manquants à nil). Le même JSON servira à la synchronisation avec le serveur (phase 2).
    public static let schemaVersion = 1

    public let v: Int
    public let gameId: String
    public let matchId: String
    public let tournamentId: String
    public let leagueSlug: String
    /// N° de la game dans la série (1 = première).
    public let number: Int
    /// « 16.17.810.4348 »
    public let patch: String?
    /// Première frame du flux (début de la game).
    public let startedAt: Date
    /// Frame `finished`.
    public let endedAt: Date
    /// `endedAt − startedAt`, arrondi à la seconde.
    public var durationSeconds: Int
    /// Recalculé par `GameWinners.assign` quand toutes les games jouées de la série sont en cache.
    public var result: GameResult
    public let blue: TeamGameLine
    public let red: TeamGameLine
    /// Palier B lu (gold et CS à 15 min, part des dégâts, balises).
    public let enriched: Bool

    public init(v: Int = GameSummary.schemaVersion, gameId: String, matchId: String, tournamentId: String,
                leagueSlug: String, number: Int, patch: String?, startedAt: Date, endedAt: Date, durationSeconds: Int,
                result: GameResult, blue: TeamGameLine, red: TeamGameLine, enriched: Bool) {
        self.v = v
        self.gameId = gameId
        self.matchId = matchId
        self.tournamentId = tournamentId
        self.leagueSlug = leagueSlug
        self.number = number
        self.patch = patch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.result = result
        self.blue = blue
        self.red = red
        self.enriched = enriched
    }

    public var id: String { gameId }

    /// Ligne de l'équipe `teamId` ; nil si elle ne joue pas cette game.
    public func line(teamId: String) -> TeamGameLine? {
        if blue.teamId == teamId { return blue }
        if red.teamId == teamId { return red }
        return nil
    }

    /// Ligne de l'adversaire de `teamId` ; nil si `teamId` ne joue pas cette game.
    public func opponentLine(of teamId: String) -> TeamGameLine? {
        if blue.teamId == teamId { return red }
        if red.teamId == teamId { return blue }
        return nil
    }

    /// Le joueur `playerId` et son équipe ; nil s'il ne joue pas cette game.
    public func player(_ playerId: String) -> (team: TeamGameLine, line: PlayerGameLine)? {
        for team in [blue, red] {
            if let line = team.players.first(where: { $0.playerId == playerId }) { return (team, line) }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case v, gameId, matchId, tournamentId, leagueSlug, number, patch, startedAt, endedAt, durationSeconds, result
        case blue, red, enriched
    }

    /// Décodage tolérant : `gameId`, `startedAt`, `endedAt`, `blue` et `red` sont indispensables ; le reste prend une
    /// valeur neutre (`v` absent = 1, résultat inconnu, palier A).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? container.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        gameId = try container.decode(String.self, forKey: .gameId)
        matchId = (try? container.decodeIfPresent(String.self, forKey: .matchId)) ?? ""
        tournamentId = (try? container.decodeIfPresent(String.self, forKey: .tournamentId)) ?? ""
        leagueSlug = (try? container.decodeIfPresent(String.self, forKey: .leagueSlug)) ?? ""
        number = (try? container.decodeIfPresent(Int.self, forKey: .number)) ?? 0
        patch = try? container.decodeIfPresent(String.self, forKey: .patch)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationSeconds = (try? container.decodeIfPresent(Int.self, forKey: .durationSeconds))
            ?? Int(endedAt.timeIntervalSince(startedAt).rounded())
        result = (try? container.decodeIfPresent(GameResult.self, forKey: .result)) ?? .unknown
        blue = try container.decode(TeamGameLine.self, forKey: .blue)
        red = try container.decode(TeamGameLine.self, forKey: .red)
        enriched = (try? container.decodeIfPresent(Bool.self, forKey: .enriched)) ?? false
    }

    /// Lecture d'un fichier du cache (`JSONDecoder` par défaut) : nil s'il est illisible ou d'un schéma plus récent
    /// que `schemaVersion` (ignoré, pas supprimé : une version plus récente de l'appli le relira).
    public static func decodeStored(_ data: Data) -> GameSummary? {
        guard let summary = try? JSONDecoder().decode(GameSummary.self, from: data),
              summary.v <= schemaVersion else { return nil }
        return summary
    }

    /// Écart toléré entre la frame retenue et début + 900 s pour « à 15 min » (spec §1.3 ; mesuré : 0,04 s).
    public static let at15Tolerance: TimeInterval = 15

    /// Réduit une game jouée (spec §1.3) :
    /// - `first` : `window` sans `startingTime` (sa première frame = début de la game) ;
    /// - `final` : `window` demandée après la fin, qui doit contenir une frame `finished` (sinon nil : « jamais de
    ///   chiffre inventé ») — les stats finales sont celles de la première frame `finished` ;
    /// - `at15` (palier B) : fenêtre autour de début + 900 s ; la frame la plus proche est retenue si l'écart est
    ///   ≤ 15 s, sinon gold et CS à 15 min restent nil ;
    /// - `details` (palier B) : dernière frame de `details` → part des dégâts (arrondie à 4 décimales) et balises.
    /// `enriched` = un des deux du palier B fourni. `result` = inconnu (voir `GameWinners`).
    /// - Returns: nil si `final` n'a pas de frame `finished`, si `first` n'a pas de frame ou si les deux fenêtres ne
    ///   sont pas de la même game.
    public static func make(first: LiveWindow, final: LiveWindow, at15: LiveWindow?, details: GameDetails?,
                            matchId: String, number: Int, tournamentId: String, leagueSlug: String) -> GameSummary? {
        guard first.esportsGameId == final.esportsGameId,
              let start = first.frames.map(\.rfc460Timestamp).min(),
              let end = final.frames.first(where: { $0.gameState == "finished" }) else { return nil }
        var frame15: WindowFrame?
        if let at15 {
            let target = start.addingTimeInterval(900)
            frame15 = at15.frames
                .min { abs($0.rfc460Timestamp.timeIntervalSince(target)) < abs($1.rfc460Timestamp.timeIntervalSince(target)) }
                .flatMap { abs($0.rfc460Timestamp.timeIntervalSince(target)) <= at15Tolerance ? $0 : nil }
        }
        let detailsFrame = details?.latestFrame
        func line(_ metadata: TeamMetadata, _ team: FrameTeam, _ team15: FrameTeam?) -> TeamGameLine {
            let players = metadata.participantMetadata.compactMap { meta -> PlayerGameLine? in
                guard let stats = team.participants.first(where: { $0.participantId == meta.participantId }) else {
                    return nil
                }
                let at15 = team15?.participants.first { $0.participantId == meta.participantId }
                let more = detailsFrame?.participants.first { $0.participantId == meta.participantId }
                return PlayerGameLine(
                    playerId: meta.esportsPlayerId ?? "", name: meta.summonerName ?? "", role: meta.role ?? "",
                    champion: meta.championId ?? "", level: stats.level, kills: stats.kills, deaths: stats.deaths,
                    assists: stats.assists, creepScore: stats.creepScore, gold: stats.totalGold,
                    damageShare: more?.championDamageShare.map { ($0 * 10_000).rounded() / 10_000 },
                    wardsPlaced: more?.wardsPlaced, wardsDestroyed: more?.wardsDestroyed,
                    gold15: at15?.totalGold, creepScore15: at15?.creepScore)
            }
            return TeamGameLine(teamId: metadata.esportsTeamId, kills: team.totalKills, gold: team.totalGold,
                                towers: team.towers, inhibitors: team.inhibitors, barons: team.barons,
                                dragons: team.dragons, gold15: team15?.totalGold, players: players)
        }
        let metadata = final.gameMetadata
        return GameSummary(
            gameId: final.esportsGameId, matchId: matchId, tournamentId: tournamentId, leagueSlug: leagueSlug,
            number: number, patch: metadata.patchVersion ?? first.gameMetadata.patchVersion,
            startedAt: start, endedAt: end.rfc460Timestamp,
            durationSeconds: Int(end.rfc460Timestamp.timeIntervalSince(start).rounded()),
            result: .unknown,
            blue: line(metadata.blueTeamMetadata, end.blueTeam, frame15?.blueTeam),
            red: line(metadata.redTeamMetadata, end.redTeam, frame15?.redTeam),
            enriched: at15 != nil || details != nil)
    }
}

/// Une équipe dans une game : stats finales, gold à 15 min (palier B) et ses 5 joueurs dans l'ordre du flux.
public struct TeamGameLine: Codable, Sendable, Equatable {
    public let teamId: String
    public let kills: Int
    public let gold: Int
    public let towers: Int
    public let inhibitors: Int
    public let barons: Int
    /// Types dans l'ordre (« ocean », « mountain », « cloud », « infernal », « hextech », « chemtech », « elder »).
    public let dragons: [String]
    public let gold15: Int?
    /// Ordre du flux : top, jungle, mid, bottom, support.
    public let players: [PlayerGameLine]

    public init(teamId: String, kills: Int, gold: Int, towers: Int, inhibitors: Int, barons: Int, dragons: [String],
                gold15: Int?, players: [PlayerGameLine]) {
        self.teamId = teamId
        self.kills = kills
        self.gold = gold
        self.towers = towers
        self.inhibitors = inhibitors
        self.barons = barons
        self.dragons = dragons
        self.gold15 = gold15
        self.players = players
    }

    private enum CodingKeys: String, CodingKey {
        case teamId, kills, gold, towers, inhibitors, barons, dragons, gold15, players
    }

    /// `teamId` indispensable ; compteurs absents → 0, listes absentes → vides.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamId = try container.decode(String.self, forKey: .teamId)
        kills = (try? container.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
        gold = (try? container.decodeIfPresent(Int.self, forKey: .gold)) ?? 0
        towers = (try? container.decodeIfPresent(Int.self, forKey: .towers)) ?? 0
        inhibitors = (try? container.decodeIfPresent(Int.self, forKey: .inhibitors)) ?? 0
        barons = (try? container.decodeIfPresent(Int.self, forKey: .barons)) ?? 0
        dragons = (try? container.decodeIfPresent([String].self, forKey: .dragons)) ?? []
        gold15 = try? container.decodeIfPresent(Int.self, forKey: .gold15)
        players = (try? container.decodeIfPresent(LossyArray<PlayerGameLine>.self, forKey: .players))?.elements ?? []
    }
}

/// Un joueur dans une game.
public struct PlayerGameLine: Codable, Sendable, Equatable {
    /// `esportsPlayerId` du flux = `TeamPlayer.id`.
    public let playerId: String
    /// `summonerName` brut du flux (« KC Canna ») ; affichage : `PlayerName.display` ou le catalogue.
    public let name: String
    /// « top », « jungle », « mid », « bottom », « support ».
    public let role: String
    /// Id Data Dragon (« KSante »).
    public let champion: String
    public let level: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let gold: Int
    /// Palier B : part des dégâts aux champions de l'équipe (0-1), balises posées / détruites.
    public let damageShare: Double?
    public let wardsPlaced: Int?
    public let wardsDestroyed: Int?
    /// Palier B : gold et CS à 15 min.
    public let gold15: Int?
    public let creepScore15: Int?

    public init(playerId: String, name: String, role: String, champion: String, level: Int, kills: Int, deaths: Int,
                assists: Int, creepScore: Int, gold: Int, damageShare: Double? = nil, wardsPlaced: Int? = nil,
                wardsDestroyed: Int? = nil, gold15: Int? = nil, creepScore15: Int? = nil) {
        self.playerId = playerId
        self.name = name
        self.role = role
        self.champion = champion
        self.level = level
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.gold = gold
        self.damageShare = damageShare
        self.wardsPlaced = wardsPlaced
        self.wardsDestroyed = wardsDestroyed
        self.gold15 = gold15
        self.creepScore15 = creepScore15
    }

    private enum CodingKeys: String, CodingKey {
        case playerId, name, role, champion, level, kills, deaths, assists, creepScore, gold, damageShare, wardsPlaced
        case wardsDestroyed, gold15, creepScore15
    }

    /// `playerId` indispensable ; texte absent → chaîne vide, compteur absent → 0, valeur du palier B absente → nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(String.self, forKey: .playerId)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? ""
        champion = (try? container.decodeIfPresent(String.self, forKey: .champion)) ?? ""
        level = (try? container.decodeIfPresent(Int.self, forKey: .level)) ?? 0
        kills = (try? container.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
        deaths = (try? container.decodeIfPresent(Int.self, forKey: .deaths)) ?? 0
        assists = (try? container.decodeIfPresent(Int.self, forKey: .assists)) ?? 0
        creepScore = (try? container.decodeIfPresent(Int.self, forKey: .creepScore)) ?? 0
        gold = (try? container.decodeIfPresent(Int.self, forKey: .gold)) ?? 0
        damageShare = try? container.decodeIfPresent(Double.self, forKey: .damageShare)
        wardsPlaced = try? container.decodeIfPresent(Int.self, forKey: .wardsPlaced)
        wardsDestroyed = try? container.decodeIfPresent(Int.self, forKey: .wardsDestroyed)
        gold15 = try? container.decodeIfPresent(Int.self, forKey: .gold15)
        creepScore15 = try? container.decodeIfPresent(Int.self, forKey: .creepScore15)
    }
}
