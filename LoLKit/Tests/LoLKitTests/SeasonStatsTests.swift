import Foundation
import Testing
@testable import LoLKit

/// Égalité de deux réels à 1e-6 près.
private func close(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tolerance
}

/// Agrégats de saison (spec saison §1.5) sur la vraie collecte « KC, LEC Split 3 » (31 games, palier A) et la game de
/// référence 304 (palier B), anti-spoiler à la lecture (§1.8).
@Suite struct SeasonStatsTests {
    private let now = date("2026-10-14T20:00:00Z")
    private let split3 = SeasonScope(tournamentIds: [SeasonFixture.lecSplit3], label: "lec_split_3_2026")

    /// Valeurs attendues de la spec (§1.1) : séries 10-2, games 22-9, kills 509, morts 388, tours 228, barons 25,
    /// drakes 85 dont 3 elder, gold moyen 68 570, durée moyenne 35,16 min.
    @Test func kcLecSplit3MatchesTheMeasuredAggregates() throws {
        let season = SeasonStats.team(SeasonFixture.kc, matches: try SeasonFixture.kcMatches(),
                                      games: try SeasonFixture.kcGames(), scope: split3, masked: [], now: now)
        #expect(season.teamId == SeasonFixture.kc)
        #expect([season.seriesWins, season.seriesLosses, season.gameWins, season.gameLosses] as [Int] == [10, 2, 22, 9])
        #expect([season.gamesCounted, season.gamesPending, season.gamesWithoutStats, season.maskedMatches] as [Int]
                == [31, 0, 0, 0])
        let averages = try #require(season.averages)
        #expect(close(averages.kills * 31, 509))
        #expect(close(averages.deaths * 31, 388))
        #expect(close(averages.towers * 31, 228))
        #expect(close(averages.barons * 31, 25))
        #expect(close(averages.dragons * 31, 85))
        #expect(close(averages.inhibitors * 31, 34))
        #expect(close(averages.kills, 16.42, 0.005))
        #expect(close(averages.deaths, 12.52, 0.005))
        #expect(close(averages.towers, 7.35, 0.005))
        #expect(close(averages.gold, 68_570.13, 0.01))
        #expect(close(averages.durationSeconds / 60, 35.16, 0.005))
        // Palier A seulement : pas d'écart à 15 min.
        #expect(averages.gold15Diff == nil)
        #expect(averages.gold15Games == 0)
        #expect(season.dragonTypes == ["ocean": 17, "infernal": 13, "cloud": 12, "hextech": 13, "mountain": 13,
                                       "elder": 3, "chemtech": 14])
        // Deux défaites pour finir (G2 1-3, MKOI 0-3) ; forme : SHFT V, SK V, GX V, G2 D, MKOI D.
        #expect(season.streak == Streak(kind: .losses, count: 2))
        #expect(season.form.map(\.outcome) == [.win, .win, .win, .loss, .loss])
        #expect(season.form.last?.matchId == "115548681803406327")
        // L'index ne garde pas les joueurs : aucun champion.
        #expect(season.champions.isEmpty)
    }

    /// Match masqué (KC 1-3 G2) : exclu des bilans, des moyennes et de la série ; pastille neutre ; compté en matchs,
    /// jamais en games.
    @Test func maskedMatchesCountNowhere() throws {
        let matches = try SeasonFixture.kcMatches()
        let games = try SeasonFixture.kcGames()
        let season = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3,
                                      masked: [SeasonFixture.match303], now: now)
        #expect([season.seriesWins, season.seriesLosses, season.gameWins, season.gameLosses] as [Int] == [10, 1, 21, 6])
        #expect(season.gamesCounted == 27)
        #expect(season.gamesPending == 0)
        #expect(season.maskedMatches == 1)
        #expect(season.form.map(\.outcome) == [.win, .win, .win, .masked, .loss])
        // La série s'arrête au match masqué : une seule défaite connue → rien à afficher.
        #expect(season.streak == nil)
        // Le plus récent masqué : série inconnue.
        let latestMasked = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3,
                                            masked: ["115548681803406327"], now: now)
        #expect(latestMasked.streak == nil)
        #expect(SeasonStats.streak(SeasonFixture.kc, matches: matches, masked: ["115548681803406327"]) == nil)
        // Tout masqué : aucune stat, 12 matchs masqués.
        let all = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3,
                                   masked: Set(matches.map(\.id)), now: now)
        #expect(all.maskedMatches == 12)
        #expect(all.averages == nil)
        #expect(all.gamesCounted == 0 && all.gamesPending == 0)
        #expect(all.form.allSatisfy { $0.outcome == .masked })
    }

    /// Games pas encore lues → « à lire » ; échec définitif → « sans stats » ; hors périmètre ou à venir → rien.
    @Test func pendingAndWithoutStatsGames() throws {
        let matches = try SeasonFixture.kcMatches()
        var games = try SeasonFixture.kcGames()
        let removed = ["115548681803406172", "115548681803406280", "115548681803406304"]
        for id in removed { games[id] = nil }
        let season = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3, masked: [],
                                      now: now, withoutStats: ["115548681803406172", "115548681803406280"])
        #expect([season.gamesCounted, season.gamesPending, season.gamesWithoutStats] as [Int] == [28, 1, 2])
        // Bilans exacts quand même (victoires de série).
        #expect([season.gameWins, season.gameLosses] as [Int] == [22, 9])
        let other = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games,
                                     scope: SeasonScope(tournamentIds: ["autre"], label: "x"), masked: [], now: now)
        #expect(other.seriesWins == 0 && other.averages == nil && other.form.isEmpty)
        let before = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3, masked: [],
                                      now: date("2026-07-25T00:00:00Z"))
        #expect(before.seriesWins == 1 && before.form.count == 1)
    }

    /// Écart de gold à 15 min sur les games enrichies (game 304 : KC +228) ; champions de l'équipe avec « estimé ».
    @Test func tierBGoldAt15AndChampions() throws {
        var games = try SeasonFixture.kcGames()
        var enriched = try SeasonFixture.summary304()
        enriched.result = try #require(games[SeasonFixture.game304]?.result)
        games[SeasonFixture.game304] = enriched
        let season = SeasonStats.team(SeasonFixture.kc, matches: try SeasonFixture.kcMatches(), games: games,
                                      scope: split3, masked: [], now: now)
        #expect(season.averages?.gold15Diff == 228)
        #expect(season.averages?.gold15Games == 1)
        #expect(season.champions.map(\.champion) == ["Ahri", "Bard", "Caitlyn", "Jayce", "Vi"])
        #expect(season.champions[0] == ChampionUse(champion: "Ahri", games: 1, wins: 0, winsEstimated: false))
        let g2 = SeasonStats.team(SeasonFixture.g2, matches: try SeasonFixture.kcMatches(), games: games, scope: split3,
                                  masked: [], now: now)
        #expect(g2.averages?.gold15Diff == -228)
        #expect(g2.champions.first { $0.champion == "Viktor" } == ChampionUse(champion: "Viktor", games: 1, wins: 1,
                                                                               winsEstimated: true))
    }

    /// Game 304 : Canna CS/min 8,98, participation aux kills 0,545 ; Caliste gold/min 531,2 (§1.1).
    @Test func playerSeasonOnTheReferenceGame() throws {
        var summary = try SeasonFixture.summary304()
        summary.result = GameResult(winnerTeamId: SeasonFixture.g2, basis: .inferred)
        let canna = try #require(SeasonStats.player("103495716771322725", games: [summary], masked: [], since: nil))
        #expect(canna.name == "KC Canna")
        #expect(canna.role == "top")
        #expect(canna.teamId == SeasonFixture.kc)
        #expect(canna.games == 1)
        #expect([canna.kills, canna.deaths, canna.assists] as [Int] == [1, 3, 5])
        #expect(close(canna.kda, 2))
        #expect(close(canna.csPerMin, 8.98, 0.005))
        #expect(close(canna.killParticipation, 6.0 / 11.0))
        #expect(canna.damageShare == 0.2278)
        #expect(canna.damageShareGames == 1)
        #expect(canna.champions == [ChampionUse(champion: "Jayce", games: 1, wins: 0, winsEstimated: false)])
        #expect(canna.recent.count == 1)
        #expect(canna.recent.first?.won == false)
        #expect(canna.recent.first?.winEstimated == true)
        #expect(canna.bestGame?.gameId == SeasonFixture.game304)
        let caliste = try #require(SeasonStats.player("109461265532592848", games: [summary], masked: [], since: nil))
        #expect(close(caliste.goldPerMin, 531.2, 0.05))
        // Palier A : pas de part des dégâts (« — »).
        let tierA = try SeasonFixture.summary304(enriched: false)
        #expect(SeasonStats.player("103495716771322725", games: [tierA], masked: [], since: nil)?.damageShare == nil)
        // Masqué, ou avant `since` : rien.
        #expect(SeasonStats.player("103495716771322725", games: [summary], masked: [SeasonFixture.match303],
                                   since: nil) == nil)
        #expect(SeasonStats.player("103495716771322725", games: [summary], masked: [],
                                   since: date("2026-09-07T00:00:00Z")) == nil)
        #expect(SeasonStats.player("inconnu", games: [summary], masked: [], since: nil) == nil)
    }

    /// Sommes sur plusieurs games (pas la moyenne des ratios) ; meilleure game = KDA puis kills puis la plus récente.
    @Test func playerSeasonSumsGames() throws {
        let first = try SeasonFixture.summary304()
        let canna = first.blue.players[0]
        let better = PlayerGameLine(playerId: canna.playerId, name: canna.name, role: "top", champion: "KSante", level: 18,
                                    kills: 5, deaths: 1, assists: 7, creepScore: 280, gold: 14_000, damageShare: nil)
        let second = GameSummary(
            gameId: "g2", matchId: "m2", tournamentId: SeasonFixture.lecSplit3, leagueSlug: "lec", number: 1, patch: nil,
            startedAt: date("2026-09-10T15:00:00Z"), endedAt: date("2026-09-10T15:30:00Z"), durationSeconds: 1800,
            result: GameResult(winnerTeamId: SeasonFixture.kc, basis: .exact),
            blue: TeamGameLine(teamId: SeasonFixture.kc, kills: 20, gold: 60_000, towers: 9, inhibitors: 1, barons: 1,
                               dragons: [], gold15: nil, players: [better]),
            red: TeamGameLine(teamId: "autre", kills: 4, gold: 40_000, towers: 1, inhibitors: 0, barons: 0, dragons: [],
                              gold15: nil, players: []),
            enriched: false)
        let season = try #require(SeasonStats.player(canna.playerId, games: [first, second], masked: [], since: nil))
        #expect(season.games == 2)
        #expect(close(season.kda, Double(1 + 5 + 5 + 7) / Double(3 + 1)))
        #expect(close(season.csPerMin, Double(304 + 280) / ((2031 + 1800) / 60.0)))
        #expect(close(season.killParticipation, Double(1 + 5 + 5 + 7) / Double(11 + 20)))
        #expect(season.damageShare == 0.2278 && season.damageShareGames == 1)
        #expect(season.recent.map(\.gameId) == ["g2", SeasonFixture.game304])
        #expect(season.bestGame?.gameId == "g2")
        #expect(season.bestGame?.won == true)
        #expect(season.champions.map(\.champion) == ["Jayce", "KSante"])
        // « Semaine » : depuis le 08/09, seulement la seconde game.
        #expect(SeasonStats.player(canna.playerId, games: [first, second], masked: [],
                                   since: date("2026-09-08T00:00:00Z"))?.games == 1)
    }

    @Test func topPlayersByMetric() throws {
        let game = try SeasonFixture.summary304()
        let byKda = SeasonStats.topPlayers(games: [game], masked: [], metric: .kda, since: nil, minGames: 1, limit: 3)
        #expect(byKda.map(\.name) == ["G2 Labrov", "G2 SkewMond", "G2 Caps"])
        let byKills = SeasonStats.topPlayers(games: [game], masked: [], metric: .kills, since: nil, minGames: 1, limit: 3)
        #expect(byKills.map(\.name) == ["G2 Caps", "G2 SkewMond", "G2 Hans Sama"])
        let byCs = SeasonStats.topPlayers(games: [game], masked: [], metric: .csPerMin, since: nil, minGames: 1, limit: 3)
        #expect(byCs.map(\.name) == ["KC Caliste", "G2 Hans Sama", "KC Canna"])
        #expect(SeasonStats.topPlayers(games: [game], masked: [], metric: .kda, since: nil, minGames: 2, limit: 5).isEmpty)
        #expect(SeasonStats.topPlayers(games: [game], masked: [SeasonFixture.match303], metric: .kda, since: nil,
                                       minGames: 1, limit: 5).isEmpty)
        #expect(PlayerMetric.kills.value(of: byKills[0]) == 7)
    }

    /// KC – G2 cette saison : 1-1 (G2 1-2 KC le 26/07, KC 1-3 G2 le 06/09) ; masqué → exclu et compté.
    @Test func headToHead() throws {
        let matches = try SeasonFixture.kcMatches()
        let all = SeasonStats.headToHead(SeasonFixture.kc, SeasonFixture.g2, matches: matches, masked: [])
        #expect(all == HeadToHead(teamA: SeasonFixture.kc, teamB: SeasonFixture.g2, winsA: 1, winsB: 1,
                                  matchIds: [SeasonFixture.match303, "115548681803406287"], maskedMatches: 0))
        let masked = SeasonStats.headToHead(SeasonFixture.kc, SeasonFixture.g2, matches: matches,
                                            masked: [SeasonFixture.match303])
        #expect(masked.winsA == 1 && masked.winsB == 0 && masked.maskedMatches == 1)
        #expect(masked.matchIds == ["115548681803406287"])
    }

    /// Périmètre : saison = tournois commencés dans l'année ; un tournoi seul a son slug pour label.
    @Test func scopes() {
        let tournaments = [
            TournamentRef(id: "s3", slug: "lec_split_3_2026", startDate: "2026-07-23", endDate: "2026-09-20", leagueId: "l"),
            TournamentRef(id: "s1", slug: "lec_split_1_2026", startDate: "2026-01-16", endDate: "2026-03-01", leagueId: "l"),
            TournamentRef(id: "su", slug: "lec_summer_2025", startDate: "2025-08-02", endDate: "2025-09-29", leagueId: "l"),
        ]
        #expect(SeasonScope.season(2026, tournaments: tournaments)
                == SeasonScope(tournamentIds: ["s3", "s1"], label: "2026", season: 2026))
        #expect(SeasonScope.tournament(tournaments[0])
                == SeasonScope(tournamentIds: ["s3"], label: "lec_split_3_2026", season: 2026))
    }

    /// Masquage de la saison : `SpoilerPolicy` sur les équipes (avec id) de chaque match, révélations comprises.
    @Test func seasonMasking() throws {
        let matches = try SeasonFixture.kcMatches()
        var follows = FollowList(teams: [FollowedTeam(id: SeasonFixture.kc, code: "KC", name: "Karmine Corp")])
        #expect(SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: []).isEmpty)
        follows.setSpoilerFree(true, id: SeasonFixture.kc)
        #expect(SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: []).count == 12)
        #expect(SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: [SeasonFixture.match303]).count == 11)
        // Une équipe suivie en anti-spoiler qui n'est pas dans ces matchs ne masque rien.
        let other = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)])
        #expect(SeasonMasking.maskedMatchIds(matches, follows: other, revealed: []).isEmpty)
    }

    /// Spec périmètre §6.1 test 13 : bilans par saison (séries puis games) sur les vraies séries 2025-2026.
    @Test func kcAndG2RecordsPerSeason() throws {
        let matches = try PerimetreFixture.kcG2Matches()
        let tournaments = Array(try PerimetreFixture.tournamentsBySlug().values)
        let now = date("2026-10-15T12:00:00Z")
        func record(_ team: String, _ year: Int) -> [Int] {
            let season = SeasonStats.team(team, matches: matches, games: [:],
                                          scope: .season(year, tournaments: tournaments), masked: [], now: now)
            return [season.seriesWins, season.seriesLosses, season.gameWins, season.gameLosses]
        }
        #expect(record("KC", 2026) == [33, 13, 72, 41])
        #expect(record("KC", 2025) == [26, 14, 64, 44])
        #expect(record("G2", 2026) == [33, 15, 79, 41])
        #expect(record("G2", 2025) == [28, 14, 62, 41])
    }

    /// Spec périmètre §6.1 test 14 : face-à-face KC-G2 — 2-6 en 2026, 3-2 en 2025, 5-8 sur la fenêtre (13 matchs, le
    /// plus récent le 06/09/2026).
    @Test func kcG2HeadToHeadOverTheWindow() throws {
        let matches = try PerimetreFixture.kcG2Matches()
        let tournaments = Array(try PerimetreFixture.tournamentsBySlug().values)
        let window = try #require(SeasonWindow(today: "2026-10-15"))
        func h2h(_ ids: Set<String>) -> HeadToHead {
            SeasonStats.headToHead("KC", "G2", matches: matches.filter { ids.contains($0.tournamentId) }, masked: [])
        }
        let current = h2h(SeasonScope.season(2026, tournaments: tournaments).tournamentIds)
        #expect((current.winsA, current.winsB) == (2, 6))
        let previous = h2h(SeasonScope.season(2025, tournaments: tournaments).tournamentIds)
        #expect((previous.winsA, previous.winsB) == (3, 2))
        let all = h2h(Set(window.tournaments(tournaments).map(\.id)))
        #expect((all.winsA, all.winsB) == (5, 8))
        #expect(all.matchIds.count == 13)
        #expect(all.matchIds.first == "115548681803406303")
        #expect(matches.first { $0.id == all.matchIds.first }?.startTime == date("2026-09-06T15:00:00Z"))
    }
}
