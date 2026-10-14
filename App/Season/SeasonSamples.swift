import Foundation
import LoLKit

/// Saison d'exemple des aperçus (planches PNG, #Preview), cohérente avec `SampleData` : mêmes ids d'équipe (« kc »,
/// « g2 », « t1 »…), même match KC 1 – 3 G2 (« m-kc-g2 », games « g1-kc-g2 »…), « aujourd'hui » = 15/10/2026. T1 est en
/// anti-spoiler dans `SampleData.follows` : ses matchs sont masqués (« 2 matchs masqués » dans les planches).
/// Chiffres inventés mais plausibles, construits uniquement avec les inits publics de LoLKit ; aucune image.
enum SeasonSamples {
    static let lecId = "98767991302996019"
    static let lckId = "98767991310872058"
    static let worldsId = "98767975604431411"

    static let lecSplit3 = TournamentRef(id: "t-lec-s3", slug: "lec_split_3_2026", startDate: "2026-07-23",
                                         endDate: "2026-09-20", leagueId: lecId)
    static let lckSplit3 = TournamentRef(id: "t-lck-s3", slug: "lck_split_3_2026", startDate: "2026-07-16",
                                         endDate: "2026-09-27", leagueId: lckId)
    static let worlds = TournamentRef(id: "t-worlds-26", slug: "worlds_2026", startDate: "2026-10-01",
                                      endDate: "2026-11-15", leagueId: worldsId)

    /// Joueurs d'exemple par équipe, du top au support : (id, pseudo du flux).
    static let rosters: [String: [(id: String, name: String)]] = [
        "kc": [("p-canna", "KC Canna"), ("p-yike", "KC Yike"), ("p-kyeahoo", "KC kyeahoo"), ("p-caliste", "KC Caliste"),
               ("p-busio", "KC Busio")],
        "g2": [("p-bb", "G2 BrokenBlade"), ("p-skewmond", "G2 SkewMond"), ("p-caps", "G2 Caps"),
               ("p-hans", "G2 Hans Sama"), ("p-labrov", "G2 Labrov")],
        "t1": [("p-doran", "T1 Doran"), ("p-oner", "T1 Oner"), ("p-faker", "T1 Faker"), ("p-gumayusi", "T1 Gumayusi"),
               ("p-keria", "T1 Keria")],
        "gen": [("p-kiin", "GEN Kiin"), ("p-canyon", "GEN Canyon"), ("p-chovy", "GEN Chovy"), ("p-ruler", "GEN Ruler"),
                ("p-duro", "GEN Duro")],
        "hle": [("p-zeus", "HLE Zeus"), ("p-peanut", "HLE Peanut"), ("p-zeka", "HLE Zeka"), ("p-viper", "HLE Viper"),
                ("p-delight", "HLE Delight")],
        "vit": [("p-naak", "VIT Naak Nako"), ("p-lyncas", "VIT Lyncas"), ("p-humanoid", "VIT Humanoid"),
                ("p-carzzy", "VIT Carzzy"), ("p-fleshy", "VIT Fleshy")],
        "blg": [("p-bin", "BLG Bin"), ("p-xun", "BLG Xun"), ("p-knight", "BLG knight"), ("p-elk", "BLG Elk"),
                ("p-on", "BLG ON")],
    ]

    private static let champions: [[String]] = [
        ["Jayce", "Rumble", "KSante", "Gnar"], ["Vi", "XinZhao", "Sejuani", "LeeSin"],
        ["Ahri", "Taliyah", "Orianna", "Azir"], ["Caitlyn", "Kaisa", "Varus", "Ezreal"],
        ["Bard", "Rell", "Braum", "Rakan"],
    ]

    private static let roles = ["top", "jungle", "mid", "bottom", "support"]

    /// Matchs d'exemple : (id, tournoi, étape, début, équipe A et ses victoires, équipe B et ses victoires).
    private static let schedule: [(String, TournamentRef, String?, String, (String, Int), (String, Int))] = [
        ("m-gen-hle", worlds, "play_ins", "2026-10-11T09:00:00Z", ("gen", 3), ("hle", 0)),
        ("m-t1-blg", worlds, "play_ins", "2026-10-08T12:00:00Z", ("t1", 2), ("blg", 1)),
        ("m-kc-g2", worlds, "play_ins", "2026-10-05T16:00:00Z", ("kc", 1), ("g2", 3)),
        ("m-t1-hle", worlds, "play_ins", "2026-10-03T12:00:00Z", ("t1", 0), ("hle", 2)),
        ("m-kc-g2-s3", lecSplit3, "playoffs", "2026-09-06T15:00:00Z", ("g2", 3), ("kc", 2)),
        ("m-kc-vit", lecSplit3, "regular_season", "2026-08-30T17:00:00Z", ("kc", 2), ("vit", 0)),
        ("m-gen-t1", lckSplit3, "regular_season", "2026-08-29T08:00:00Z", ("gen", 2), ("t1", 1)),
        ("m-kc-g2-rs", lecSplit3, "regular_season", "2026-08-16T17:00:00Z", ("kc", 2), ("g2", 1)),
        ("m-vit-kc", lecSplit3, "regular_season", "2026-08-02T17:00:00Z", ("vit", 1), ("kc", 2)),
    ]

    static var matches: [SeasonMatch] {
        schedule.map { id, tournament, stage, start, a, b in
            SeasonMatch(id: id, tournamentId: tournament.id, leagueSlug: leagueSlug(tournament), stageSlug: stage,
                        startTime: SampleData.date(start), blockName: nil, bestOf: a.1 + b.1 > 3 || max(a.1, b.1) == 3 ? 5 : 3,
                        teams: [side(a.0, wins: a.1, won: a.1 > b.1), side(b.0, wins: b.1, won: b.1 > a.1)],
                        playedGameIds: (1...(a.1 + b.1)).map { "g\($0)-\(id.dropFirst(2))" })
        }
    }

    /// Une game par game jouée, palier B pour les games du Mondial (gold à 15 min, part des dégâts), palier A sinon.
    static var games: [GameSummary] {
        matches.flatMap { match -> [GameSummary] in
            let a = match.teams[0], b = match.teams[1]
            // Ordre des victoires : l'équipe qui perd la série gagne ses games d'abord (série serrée).
            let loserWins = min(a.gameWins, b.gameWins)
            let winner = a.gameWins > b.gameWins ? a : b
            let loser = a.gameWins > b.gameWins ? b : a
            return match.playedGameIds.enumerated().map { index, gameId in
                let winnerId = index < loserWins ? loser.id! : winner.id!
                let seed = gameId.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7 + index
                return game(gameId, match: match, number: index + 1, blue: a.id!, red: b.id!, winner: winnerId,
                            seed: seed, enriched: match.tournamentId == worlds.id,
                            basis: index == match.playedGameIds.count - 1 || loserWins == 0 ? .exact : .inferred)
            }
        }
    }

    /// Classements : LEC Split 3 (saison régulière classée), Mondial (play-ins, puis système suisse à venir).
    static var standings: [String: Standings] {
        func ranked(_ ordinal: Int, _ id: String, _ wins: Int, _ losses: Int) -> Ranking {
            let team = SampleData.catalog.first { $0.id == id }
            return Ranking(ordinal: ordinal, teams: [RankedTeam(id: id, code: team?.code ?? id.uppercased(),
                                                               name: team?.name ?? id, image: nil, wins: wins,
                                                               losses: losses)])
        }
        func bracket(_ match: SeasonMatch) -> BracketMatch {
            BracketMatch(id: match.id, state: .completed, teams: match.teams)
        }
        let worldsMatches = matches.filter { $0.tournamentId == worlds.id }
        let upcoming = BracketMatch(id: "m-kc-c9", state: .inProgress,
                                    teams: [side("kc", wins: 1, won: false), side("c9", wins: 0, won: false)])
        return [
            lecSplit3.id: Standings(stages: [
                StandingsStage(id: "s-lec-rs", name: "Saison régulière", slug: "regular_season", sections: [
                    StandingsSection(name: "Saison régulière",
                                     matches: matches.filter { $0.stageSlug == "regular_season" && $0.tournamentId == lecSplit3.id }
                                         .map(bracket),
                                     rankings: [ranked(1, "kc", 9, 0), ranked(2, "vit", 7, 2), ranked(3, "g2", 6, 3)]),
                ]),
                StandingsStage(id: "s-lec-po", name: "Play-offs", slug: "playoffs", sections: [
                    StandingsSection(name: "Tableau", matches: matches.filter { $0.stageSlug == "playoffs" }.map(bracket),
                                     rankings: []),
                ]),
            ]),
            worlds.id: Standings(stages: [
                StandingsStage(id: "s-w-pi", name: "Play-ins", slug: "play_ins", sections: [
                    StandingsSection(name: "Play-ins", matches: worldsMatches.map(bracket) + [upcoming], rankings: []),
                ]),
                StandingsStage(id: "s-w-sw", name: "Système suisse", slug: "swiss", sections: [
                    StandingsSection(name: "Système suisse", matches: [], rankings: []),
                ]),
            ]),
        ]
    }

    /// Saison complète, tout lu.
    static var standard: SeasonPreview {
        SeasonPreview(tournaments: [lecSplit3, lckSplit3, worlds], matches: matches, games: games, standings: standings,
                      progress: CrawlProgress(read: games.count, remaining: 0, running: false))
    }

    /// Collecte en cours : seules les games du Mondial sont lues, 14 restent à lire.
    static var collecting: SeasonPreview {
        var preview = standard
        preview.games = preview.games.filter { $0.tournamentId == worlds.id }
        preview.progress = CrawlProgress(read: preview.games.count, remaining: 14, running: true)
        return preview
    }

    /// Disque pas encore lu : squelettes.
    static var loading: SeasonPreview {
        SeasonPreview(isLoaded: false)
    }

    // MARK: Construction

    private static func leagueSlug(_ tournament: TournamentRef) -> String {
        switch tournament.leagueId {
        case lecId: return "lec"
        case lckId: return "lck"
        default: return "worlds"
        }
    }

    private static func side(_ id: String, wins: Int, won: Bool) -> MatchTeam {
        let team = SampleData.catalog.first { $0.id == id }
        return MatchTeam(id: id, name: team?.name ?? id.uppercased(), code: team?.code ?? id.uppercased(), image: nil,
                         result: MatchTeam.Result(outcome: won ? "win" : "loss", gameWins: wins))
    }

    private static func game(_ gameId: String, match: SeasonMatch, number: Int, blue: String, red: String,
                             winner: String, seed: Int, enriched: Bool, basis: GameResult.Basis) -> GameSummary {
        let start = match.startTime.addingTimeInterval(Double(number - 1) * 3_000 + 900)
        let duration = 1_740 + seed * 137
        func line(_ teamId: String, won: Bool) -> TeamGameLine {
            let kills = won ? 16 + seed : 8 + seed / 2
            let shares: [Double] = [0.24, 0.14, 0.27, 0.28, 0.07]
            let killWeights = [2, 3, 4, 5, 0]
            let players = (0..<5).map { (index: Int) -> PlayerGameLine in
                let fallback = (id: "p-\(teamId)-\(index)", name: "\(teamId.uppercased()) \(roles[index])")
                let roster: (id: String, name: String) = rosters[teamId]?[index] ?? fallback
                let share = shares[index]
                return PlayerGameLine(
                    playerId: roster.id, name: roster.name, role: roles[index],
                    champion: champions[index][(seed + index + (won ? 0 : 1)) % champions[index].count],
                    level: won ? 17 : 15, kills: index == 4 ? 1 : (kills * killWeights[index]) / 14,
                    deaths: won ? 1 + index % 2 : 3 + index % 3, assists: won ? 6 + index * 2 : 3 + index,
                    creepScore: index == 4 ? 38 : (index == 1 ? 190 : 280) + seed * 3,
                    gold: (won ? 13_500 : 11_200) - index * 600 + seed * 40,
                    damageShare: enriched ? share : nil, wardsPlaced: enriched ? 10 + index * 3 : nil,
                    wardsDestroyed: enriched ? 3 + index : nil, gold15: enriched ? 5_000 + index * 120 : nil,
                    creepScore15: enriched ? (index == 4 ? 18 : 120 + index * 4) : nil)
            }
            return TeamGameLine(teamId: teamId, kills: kills, gold: players.reduce(0) { $0 + $1.gold },
                                towers: won ? 9 + seed % 3 : 3 + seed % 2, inhibitors: won ? 2 : 0, barons: won ? 1 + seed % 2 : 0,
                                dragons: won ? ["ocean", "infernal", "mountain"].prefix(2 + seed % 2).map { $0 } : ["cloud"],
                                gold15: enriched ? (won ? 26_400 : 24_900) : nil, players: players)
        }
        return GameSummary(gameId: gameId, matchId: match.id, tournamentId: match.tournamentId, leagueSlug: match.leagueSlug,
                           number: number, patch: "16.19.1", startedAt: start,
                           endedAt: start.addingTimeInterval(Double(duration)), durationSeconds: duration,
                           result: GameResult(winnerTeamId: winner, basis: basis),
                           blue: line(blue, won: winner == blue), red: line(red, won: winner == red), enriched: enriched)
    }
}
