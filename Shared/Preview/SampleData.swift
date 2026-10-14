import Foundation
import LoLKit

/// Données figées d'un `AppStore` d'aperçu (#Preview et tests d'images) : rien n'est lu sur le disque ni sur le réseau.
struct PreviewData {
    var follows = FollowList()
    var settings = AppSettings()
    var leagues: [League] = []
    var catalog: [Team] = []
    var schedule: [MatchEvent] = []
    var live: [MatchEvent]? = []
    var details: [String: EventDetails] = [:]
    var snapshots: [String: GameSnapshot] = [:]
    var firstFrames: [String: Date] = [:]
    var statsUnavailable: Set<String> = []
    var isFailing = false
    var lastUpdate: Date?
    /// Matchs dont la Live Activity est à l'écran (bouton du Détail).
    var activityMatchIds: Set<String> = []
    /// Saison d'exemple (spec saison), traduite par `AppStore(preview:)` en `SeasonSamples` (dans l'appli) ; aucune par
    /// défaut : les planches existantes ne changent pas.
    var season: SeasonSample = .none

    /// Comme les maquettes : KC en direct avec stats, T1 en direct masqué (anti-spoiler), GEN à venir.
    static var standard: PreviewData {
        PreviewData(
            follows: SampleData.follows,
            leagues: SampleData.leagues,
            catalog: SampleData.catalog,
            schedule: SampleData.schedule,
            live: SampleData.live,
            details: Dictionary(uniqueKeysWithValues: SampleData.live.map { ($0.id, EventDetails(event: $0)) })
                .merging([SampleData.kcG2MatchId: SampleData.kcG2Details]) { live, _ in live },
            snapshots: [SampleData.kcSnapshot.gameId: SampleData.kcSnapshot,
                        SampleData.kcG2Final.gameId: SampleData.kcG2Final],
            firstFrames: [SampleData.kcSnapshot.gameId: SampleData.kcGameStart],
            lastUpdate: SampleData.date("2026-10-15T15:05:00Z"),
            activityMatchIds: [SampleData.kcMatchId]
        )
    }

    /// Premier lancement : aucune équipe suivie.
    static var empty: PreviewData {
        PreviewData(leagues: SampleData.leagues, catalog: SampleData.catalog, schedule: SampleData.schedule,
                    live: SampleData.live)
    }

    /// L'API ne répond plus : données en cache et bandeau.
    static var failing: PreviewData {
        var data = standard
        data.isFailing = true
        return data
    }

    /// Comme `standard`, avec la saison d'exemple complète (KC, GEN ; T1 en anti-spoiler, ses matchs masqués).
    static var withSeason: PreviewData {
        var data = standard
        data.season = .standard
        return data
    }

    /// Collecte en cours : seules les games du Mondial sont lues.
    static var withSeasonCollecting: PreviewData {
        var data = standard
        data.season = .collecting
        return data
    }

    /// Disque de la saison pas encore lu : squelettes.
    static var withSeasonLoading: PreviewData {
        var data = standard
        data.season = .loading
        return data
    }

    /// Aucune équipe suivie, saison connue (Accueil « Suis tes équipes », premier lancement).
    static var withSeasonNoFollows: PreviewData {
        var data = empty
        data.season = .standard
        return data
    }
}

/// Saison d'exemple d'un `AppStore` d'aperçu (les données vivent dans l'appli : `SeasonSamples`).
enum SeasonSample: Sendable {
    case none, standard, collecting, loading
}

/// Matchs, équipes et stats d'exemple, construits uniquement avec les inits publics de LoLKit.
enum SampleData {
    static let kcMatchId = "m-kc-c9"
    static let t1MatchId = "m-t1-fly"
    static let noStatsMatchId = "m-bro-lgd"
    /// KC 1 – 3 G2, match terminé du calendrier : Détail « terminé » des aperçus (rediffusions, sorts d'invocateur).
    static let kcG2MatchId = "m-kc-g2"

    static func date(_ iso: String) -> Date {
        LoLDate.parse(iso) ?? Date(timeIntervalSince1970: 0)
    }

    static let worlds = LeagueRef(id: "98767975604431411", slug: "worlds", name: "Mondial", image: nil)

    static let leagues: [League] = [
        League(id: "98767975604431411", slug: "worlds", name: "Mondial", region: "INTERNATIONAL", image: nil, priority: 1),
        League(id: "105266103462388553", slug: "lfl", name: "La Ligue Française", region: "EMEA", image: nil, priority: 1),
        League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1),
        League(id: "98767991310872058", slug: "lck", name: "LCK", region: "CORÉE", image: nil, priority: 1),
        League(id: "98767991314006698", slug: "lpl", name: "LPL", region: "CHINE", image: nil, priority: 1),
    ]

    static let catalog: [Team] = [
        team("kc", "KC", "Karmine Corp", "LEC", players: roster([("p-canna", "Canna", "top"), ("p-yike", "Yike", "jungle"),
                                                                 ("p-kyeahoo", "kyeahoo", "mid"),
                                                                 ("p-caliste", "Caliste", "bottom"),
                                                                 ("p-busio", "Busio", "support")])),
        team("g2", "G2", "G2 Esports", "LEC", players: roster([("p-bb", "BrokenBlade", "top"),
                                                               ("p-skewmond", "SkewMond", "jungle"),
                                                               ("p-caps", "Caps", "mid"), ("p-hans", "Hans Sama", "bottom"),
                                                               ("p-labrov", "Labrov", "support")])),
        team("t1", "T1", "T1", "LCK", players: roster([("p-doran", "Doran", "top"), ("p-oner", "Oner", "jungle"),
                                                       ("p-faker", "Faker", "mid"), ("p-gumayusi", "Gumayusi", "bottom"),
                                                       ("p-keria", "Keria", "support")])),
        team("gen", "GEN", "Gen.G", "LCK"),
        team("hle", "HLE", "Hanwha Life Esports", "LCK"),
        team("kcb", "KCB", "Karmine Corp Blue", "La Ligue Française"),
        team("sly", "SLY", "Solary", "La Ligue Française"),
        team("blg", "BLG", "Bilibili Gaming", "LPL"),
        team("c9", "C9", "Cloud9 Kia", "LCS"),
        team("fly", "FLY", "FlyQuest", "LCS"),
        team("fur", "FUR", "FURIA", nil),
    ]

    static var follows: FollowList {
        FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", homeLeagueName: "LEC", autoColorHex: "#5B8CFF"),
            FollowedTeam(id: "t1", code: "T1", name: "T1", homeLeagueName: "LCK", spoilerFree: true, autoColorHex: "#FF5C7A"),
            FollowedTeam(id: "gen", code: "GEN", name: "Gen.G", homeLeagueName: "LCK", autoColorHex: "#FFB454"),
        ])
    }

    /// KC 1 – 0 C9, game 2 en cours (forme `getLive` : ids d'équipe et games).
    static let kcLive = MatchEvent(
        startTime: date("2026-10-15T16:00:00Z"), state: .inProgress, type: "match", blockName: "Play-in",
        league: worlds,
        match: MatchInfo(id: kcMatchId, teams: [side("kc", wins: 1), side("c9", wins: 0)],
                         strategy: Strategy(type: "bestOf", count: 5),
                         games: games(count: 5, current: 2, blue: "kc", red: "c9")),
        // Comme `getLive` : des streams en plusieurs langues (« Regarder » choisit le français, spec fonctionnalités §1).
        streams: [
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "riotgames", locale: "en-US"),
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR"),
            StreamInfo(statsStatus: "enabled", provider: "youtube", parameter: "lolesports", locale: "en-US"),
        ]
    )

    /// T1 – FLY en cours : T1 est en anti-spoiler, le match est masqué partout.
    static let t1Live = MatchEvent(
        startTime: date("2026-10-15T17:00:00Z"), state: .inProgress, type: "match", blockName: "Play-in",
        league: worlds,
        match: MatchInfo(id: t1MatchId, teams: [side("t1", wins: 0), side("fly", wins: 0)],
                         strategy: Strategy(type: "bestOf", count: 5),
                         games: games(count: 5, current: 1, blue: "t1", red: "fly")),
        streams: [StreamInfo(statsStatus: "enabled")]
    )

    /// Match d'équipes non suivies dont Riot ne fournit pas les stats (comme la fixture getLive).
    static let noStatsLive = MatchEvent(
        startTime: date("2026-10-15T09:00:00Z"), state: .inProgress, type: "match", blockName: "Quarts de finale",
        league: LeagueRef(id: "117126995932274206", slug: "demacia_cup", name: "DCGI", image: nil),
        match: MatchInfo(
            id: noStatsMatchId,
            teams: [
                MatchTeam(id: "bro", name: "HANJIN BRION", code: "BRO", image: nil,
                          result: MatchTeam.Result(outcome: nil, gameWins: 1)),
                MatchTeam(id: "lgd", name: "LGD GAMING", code: "LGD", image: nil,
                          result: MatchTeam.Result(outcome: nil, gameWins: 0)),
            ],
            strategy: Strategy(type: "bestOf", count: 5),
            games: games(count: 5, current: 2, blue: "bro", red: "lgd")
        ),
        streams: [StreamInfo(statsStatus: "disabled")]
    )

    static var live: [MatchEvent] {
        [kcLive, t1Live, noStatsLive]
    }

    /// Prochain match de KC (17 oct., 18:00 à Paris). Hors de `schedule` : seuls les widgets l'ajoutent
    /// (`WidgetSamples`), pour que le moyen widget ait quatre lignes sans changer les écrans de l'appli.
    static var kcNext: MatchEvent {
        upcoming("m-kc-blg", "2026-10-17T16:00:00Z", "kc", "blg")
    }

    /// Calendrier (forme `getSchedule` : sans id d'équipe, reconnues par leur nom).
    static var schedule: [MatchEvent] {
        [
            kcLive,
            t1Live,
            upcoming("m-gen-fur", "2026-10-16T09:00:00Z", "gen", "fur"),
            upcoming("m-t1-gen", "2026-10-17T12:00:00Z", "t1", "gen"),
            completed("m-gen-hle", "2026-10-11T09:00:00Z", ("gen", 3, "win"), ("hle", 0, "loss")),
            completed("m-kc-g2", "2026-10-05T16:00:00Z", ("kc", 1, "loss"), ("g2", 3, "win")),
        ]
    }

    /// Game 2 de KC – C9 : première frame, et dernière frame reçue 18:42 plus tard.
    static let kcGameStart = date("2026-10-15T17:02:00Z")
    static let kcSnapshot = GameSnapshot(
        gameId: "g2-kc-c9", phase: .inGame, timestamp: date("2026-10-15T17:20:42Z"),
        blueTeamId: "kc", redTeamId: "c9",
        blue: TeamStats(kills: 7, gold: 32_400, towers: 3, inhibitors: 0, barons: 0, dragons: ["infernal", "ocean"]),
        red: TeamStats(kills: 4, gold: 30_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        bluePlayers: [
            player("top", "Rumble", "KC Top", 2, 0, 1, 162),
            player("jungle", "XinZhao", "KC Jungle", 1, 1, 4, 118),
            player("mid", "Taliyah", "KC Mid", 3, 1, 2, 171),
            player("bottom", "Kaisa", "KC Bot", 1, 1, 3, 189),
            player("support", "Rell", "KC Support", 0, 1, 5, 21),
        ],
        redPlayers: [
            player("top", "KSante", "C9 Top", 0, 1, 1, 150),
            player("jungle", "Vi", "C9 Jungle", 1, 2, 1, 104),
            player("mid", "Azir", "C9 Mid", 2, 2, 1, 168),
            player("bottom", "Ezreal", "C9 Bot", 1, 1, 1, 180),
            player("support", "Nautilus", "C9 Support", 0, 1, 3, 18),
        ]
    )

    /// `getEventDetails` de KC 1 – 3 G2 : quatre games jouées, chacune avec sa rediffusion YouTube (spec
    /// fonctionnalités §1), la cinquième inutile.
    static var kcG2Details: EventDetails {
        EventDetails(
            id: kcG2MatchId, league: worlds,
            match: EventDetails.Match(
                strategy: Strategy(type: "bestOf", count: 5),
                teams: [side("kc", wins: 1, outcome: "loss"), side("g2", wins: 3, outcome: "win")],
                games: (1...5).map { number in
                    GameRef(number: number, id: "g\(number)-kc-g2", state: number <= 4 ? .completed : .unneeded,
                            teams: [GameRef.Side(id: "kc", side: "blue"), GameRef.Side(id: "g2", side: "red")],
                            vods: number <= 4
                                ? [Vod(provider: "youtube", parameter: "kcg2-game\(number)", locale: "en-US",
                                       startMillis: number == 1 ? 0 : 95_000)]
                                : nil)
                }
            ),
            streams: nil
        )
    }

    /// Game 4 de KC – G2, gagnée par G2 en 34 min : sa dernière frame (`finished`), celle sur laquelle finit le fil
    /// d'exemple (`TimelineSamples.Script.redWins`).
    static let kcG2GameStart = date("2026-10-05T19:12:00Z")
    static let kcG2Final = GameSnapshot(
        gameId: "g4-kc-g2", phase: .finished, timestamp: date("2026-10-05T19:46:09Z"),
        blueTeamId: "kc", redTeamId: "g2",
        blue: TeamStats(kills: 5, gold: 54_400, towers: 2, inhibitors: 0, barons: 0, dragons: ["ocean"]),
        red: TeamStats(kills: 14, gold: 69_600, towers: 11, inhibitors: 3, barons: 2,
                       dragons: ["hextech", "hextech", "infernal", "hextech"]),
        bluePlayers: [
            player("top", "Gnar", "KC Top", 1, 3, 1, 268, level: 16),
            player("jungle", "Sejuani", "KC Jungle", 1, 4, 2, 182, level: 14),
            player("mid", "Orianna", "KC Mid", 2, 2, 1, 301, level: 16),
            player("bottom", "Varus", "KC Bot", 1, 3, 2, 322, level: 15),
            player("support", "Braum", "KC Support", 0, 2, 4, 41, level: 13),
        ],
        redPlayers: [
            player("top", "Rumble", "G2 Top", 2, 1, 6, 281, level: 17),
            player("jungle", "LeeSin", "G2 Jungle", 3, 1, 8, 205, level: 16),
            player("mid", "Ahri", "G2 Mid", 5, 1, 6, 320, level: 18),
            player("bottom", "Kalista", "G2 Bot", 4, 0, 7, 345, level: 17),
            player("support", "Rakan", "G2 Support", 0, 2, 12, 38, level: 15),
        ]
    )

    private static func team(_ id: String, _ code: String, _ name: String, _ home: String?,
                             players: [TeamPlayer]? = nil) -> Team {
        Team(id: id, slug: id, name: name, code: code, image: nil, status: "active",
             homeLeague: home.map { Team.HomeLeague(name: $0) }, players: players)
    }

    /// Effectif d'exemple (spec saison §3.1) : mêmes ids que les games de `SeasonSamples`.
    private static func roster(_ players: [(id: String, name: String, role: String)]) -> [TeamPlayer] {
        players.map { TeamPlayer(id: $0.id, summonerName: $0.name, image: nil, role: $0.role) }
    }

    /// Équipe d'un match : avec id comme `getLive`, ou sans id comme `getSchedule`.
    private static func side(_ id: String, wins: Int, outcome: String? = nil, withId: Bool = true) -> MatchTeam {
        let team = catalog.first { $0.id == id }
        return MatchTeam(id: withId ? id : nil, name: team?.name ?? id, code: team?.code ?? id.uppercased(), image: nil,
                         result: MatchTeam.Result(outcome: outcome, gameWins: wins))
    }

    private static func games(count: Int, current: Int, blue: String, red: String) -> [GameRef] {
        (1...count).map { number in
            let state: GameRef.State = number < current ? .completed : (number == current ? .inProgress : .unstarted)
            return GameRef(number: number, id: "g\(number)-\(blue)-\(red)", state: state,
                           teams: [GameRef.Side(id: blue, side: "blue"), GameRef.Side(id: red, side: "red")])
        }
    }

    private static func upcoming(_ id: String, _ start: String, _ a: String, _ b: String) -> MatchEvent {
        MatchEvent(startTime: date(start), state: .unstarted, type: "match", blockName: "Play-in", league: worlds,
                   match: MatchInfo(id: id, teams: [side(a, wins: 0, withId: false), side(b, wins: 0, withId: false)],
                                    strategy: Strategy(type: "bestOf", count: 5), games: nil),
                   streams: nil)
    }

    private static func completed(_ id: String, _ start: String, _ a: (id: String, wins: Int, outcome: String),
                                  _ b: (id: String, wins: Int, outcome: String)) -> MatchEvent {
        MatchEvent(startTime: date(start), state: .completed, type: "match", blockName: "Play-in", league: worlds,
                   match: MatchInfo(id: id,
                                    teams: [side(a.id, wins: a.wins, outcome: a.outcome, withId: false),
                                            side(b.id, wins: b.wins, outcome: b.outcome, withId: false)],
                                    strategy: Strategy(type: "bestOf", count: 5), games: nil),
                   streams: nil)
    }

    private static func player(_ role: String, _ champion: String, _ name: String, _ kills: Int, _ deaths: Int,
                               _ assists: Int, _ cs: Int, level: Int = 11) -> PlayerLine {
        PlayerLine(role: role, champion: champion, name: name, level: level, kills: kills, deaths: deaths,
                   assists: assists, creepScore: cs, gold: 6_000 + cs * 10)
    }
}
