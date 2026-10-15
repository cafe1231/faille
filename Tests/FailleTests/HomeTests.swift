import Foundation
import LoLKit
import Testing
@testable import Faille

private let fr = Locale(identifier: "fr_FR")
private let now = SampleData.date("2026-10-15T15:05:00Z")

private func paris() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.locale = fr
    return calendar
}

struct HomeModelTests {
    private func inputs(follows: FollowList, revealed: Set<String> = []) -> HomeInputs {
        let preview = SeasonSamples.standard
        let feed = HomeFeed.Input(now: now, calendar: paris(), schedule: SampleData.schedule, live: SampleData.live,
                                  follows: follows, revealed: revealed, revealedStandings: [],
                                  seasonMatches: preview.matches,
                                  games: Dictionary(uniqueKeysWithValues: preview.games.map { ($0.gameId, $0) }),
                                  standings: preview.standings, catalog: SampleData.catalog)
        return HomeInputs(feed: feed, progress: preview.progress, isLoaded: true)
    }

    @Test func liveMatchesPutFollowedTeamsFirstAndKeepMaskedOnesWithoutScore() {
        let content = HomeModel.compute(inputs(follows: SampleData.follows))
        // KC – C9 et T1 – FLY (suivis) d'abord, puis BRO – LGD (ni suivi ni international).
        #expect(content.live.map(\.id) == [SampleData.kcMatchId, SampleData.t1MatchId, SampleData.noStatsMatchId])
        #expect(content.live.map(\.masked) == [false, true, false])
        #expect(content.sections.todayCount == 2)
        #expect(content.masked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
        #expect(content.strip.count == 43)
        #expect(content.eventsByDay[paris().startOfDay(for: now)]?.count == 3)
    }

    @Test func recentResultsCoverSeventyTwoHours() {
        // 72 h avant le 15/10 15:05 : GEN – HLE (11/10) et KC – G2 (05/10) sont trop vieux.
        #expect(HomeModel.compute(inputs(follows: SampleData.follows)).sections.recentResults.isEmpty)
    }

    @Test func withoutFollowsTheHomeStillShowsTheWorlds() {
        let content = HomeModel.compute(inputs(follows: FollowList()))
        #expect(!content.hasFollows)
        #expect(Array(content.live.map(\.id).prefix(2)) == [SampleData.kcMatchId, SampleData.t1MatchId])
        #expect(content.live.allSatisfy { !$0.masked })
        #expect(content.masked.isEmpty)
    }

    @Test func hotPlayersExistForEveryPeriodAndMetric() {
        let content = HomeModel.compute(inputs(follows: SampleData.follows))
        #expect(content.hotPlayers.count == 6)
        // Saison : 5 games au moins ; aucun joueur de T1 (tous ses matchs sont masqués).
        let season = content.hotPlayers[HotPlayersKey(period: .season, metric: .kda)] ?? []
        #expect(!season.isEmpty)
        #expect(!season.contains { $0.playerId == "p-faker" })
    }
}

/// M16 : le délai de 30 s ne retient que les lectures de games ; un suivi ou une révélation passe tout de suite.
struct HomeThrottleTests {
    private func key(version: Int = 1, follows: FollowList = FollowList(), revealed: Set<String> = [],
                     standings: Set<String> = [], day: Date = now, running: Bool = true) -> HomeKey {
        HomeKey(version: version, follows: follows, revealed: revealed, day: day, updated: nil, liveIds: nil,
                loaded: true, running: running, revealedStandings: standings)
    }

    @Test func gameReadTicksAreThrottledDuringACrawl() {
        #expect(HomeKey.shouldThrottle(old: key(), new: key(version: 2), running: true))
    }

    @Test func nothingIsThrottledOutsideACrawlOrBeforeTheFirstPublication() {
        #expect(!HomeKey.shouldThrottle(old: key(), new: key(version: 2), running: false))
        #expect(!HomeKey.shouldThrottle(old: nil, new: key(), running: true))
    }

    @Test func followsRevealsAndDayChangesPublishAtOnce() {
        let old = key()
        #expect(!HomeKey.shouldThrottle(old: old, new: key(follows: SampleData.follows), running: true))
        #expect(!HomeKey.shouldThrottle(old: old, new: key(revealed: ["m-t1-blg"]), running: true))
        #expect(!HomeKey.shouldThrottle(old: old, new: key(standings: ["s1"]), running: true))
        #expect(!HomeKey.shouldThrottle(old: old, new: key(day: now.addingTimeInterval(86_400)), running: true))
    }
}

/// « Regarder » : absent d'un match en direct masqué, présent sinon ; les clés des joueurs en forme sont distinctes.
struct HomeLiveWatchTests {
    @Test func maskedLiveItemHasNoWatchLink() {
        let kc = SampleData.kcLive
        #expect(WatchLinks.live(kc.streams, inProgress: true, masked: false) != nil)
        #expect(WatchLinks.live(kc.streams, inProgress: true, masked: true) == nil)
    }

    @Test func hotPlayersKeysAreSixDistinct() {
        let keys = Set(HomeModel.periods.flatMap { period in
            PlayerMetric.allCases.map { HotPlayersKey(period: period, metric: $0) }
        })
        #expect(keys.count == HomeModel.periods.count * PlayerMetric.allCases.count)
        #expect(HotPlayersKey(period: .week, metric: .kda) != HotPlayersKey(period: .season, metric: .kda))
    }
}

/// Textes de l'Accueil (spec saison §2.2, §3.6) : LoLKit donne des valeurs, l'appli formule.
struct HomeTextsTests {
    @Test func reasonsAndExplanation() {
        #expect(HomeTexts.reason(.followedTeam) == "Tes équipes")
        #expect(HomeTexts.reason(.elimination) == "Élimination en jeu")
        #expect(HomeTexts.reason(.international(slug: "worlds")) == "Mondial")
        #expect(HomeTexts.reason(.decider) == "Tout se joue")
        let pick = MustWatchPick(event: SampleData.kcLive, points: 90,
                                 reasons: [MustWatchScore(reason: .followedTeam, points: 50),
                                           MustWatchScore(reason: .elimination, points: 30),
                                           MustWatchScore(reason: .bestOf5, points: 10)])
        #expect(HomeTexts.explanation(pick) == "Tes équipes · Élimination en jeu")
    }

    @Test func subtitleCountsTodaysMatches() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = SampleData.date("2026-10-15T15:05:00Z")
        let fr = Locale(identifier: "fr_FR")
        #expect(HomeTexts.subtitle(now: now, todayCount: 3, calendar: calendar, locale: fr) == "jeudi 15 octobre · 3 matchs aujourd'hui")
        #expect(HomeTexts.subtitle(now: now, todayCount: 0, calendar: calendar, locale: fr) == "jeudi 15 octobre · aucun match aujourd'hui")
    }
}

/// Cas branchés sur un `AppStore` d'aperçu (M15 : suite sérialisée) : résultats récents (M6) et anti-spoiler I-1.
@MainActor
@Suite(.serialized)
struct HomeStoreTests {
    private func event(_ id: String, _ start: String, state: EventState, _ a: String, _ b: String) -> MatchEvent {
        func team(_ teamId: String) -> MatchTeam {
            let catalog = SampleData.catalog.first { $0.id == teamId }
            return MatchTeam(id: teamId, name: catalog?.name ?? teamId, code: catalog?.code ?? teamId.uppercased(),
                             image: nil,
                             result: state == .completed ? MatchTeam.Result(outcome: "win", gameWins: 2) : nil)
        }
        return MatchEvent(startTime: SampleData.date(start), state: state, type: "match", blockName: "Play-in",
                          league: SampleData.worlds,
                          match: MatchInfo(id: id, teams: [team(a), team(b)], strategy: Strategy(type: "bestOf", count: 3),
                                           games: nil),
                          streams: nil)
    }

    @Test func aResultUnderSeventyTwoHoursIsInRecentResults() {
        var data = PreviewData.withSeason
        data.schedule.append(event("m-gen-fur-r", "2026-10-14T09:00:00Z", state: .completed, "gen", "fur"))
        let store = AppStore(preview: data)
        let content = HomeModel.compute(store.homeInputs(now: now, calendar: paris()))
        #expect(content.sections.recentResults.map(\.id).contains("m-gen-fur-r"))
    }

    @Test func aMaskedUpcomingMatchBetraysNeitherTheStripNorTheMustWatch() {
        var data = PreviewData.withSeason
        data.schedule.append(event("m-t1-hle-soon", "2026-10-15T18:00:00Z", state: .unstarted, "t1", "hle"))
        let store = AppStore(preview: data)
        #expect(store.maskedLatestTeamIds.contains("t1"))
        let content = HomeModel.compute(store.homeInputs(now: now, calendar: paris()))
        let today = paris().startOfDay(for: now)
        #expect(content.eventsByDay[today]?.contains { $0.id == "m-t1-hle-soon" } != true)
        #expect(content.strip.flatMap(\.matchIds).contains("m-t1-hle-soon") == false)
        #expect(!content.sections.mustWatch.contains { $0.id == "m-t1-hle-soon" })
        #expect(!store.mustWatchPicks(limit: 5, now: now, calendar: paris()).contains { $0.id == "m-t1-hle-soon" })
    }

    /// I-1 généralisé (W1) : le match de T1 (T1–FLY, en anti-spoiler) est masqué ; la suite du tableau du Mondial entre
    /// d'autres équipes (GEN–FUR) n'apparaît ni dans le bandeau, ni dans le direct, ni dans les résultats récents, ni dans
    /// les ligues, ni dans les notifications ; révéler le match de T1 la rend.
    @Test func theRestOfABracketIsHiddenUntilTheMaskedMatchIsRevealed() {
        var data = PreviewData.withSeason
        data.schedule.append(event("m-semi-done", "2026-10-15T22:00:00Z", state: .completed, "blg", "gen"))
        let store = AppStore(preview: data)
        let later = SampleData.date("2026-10-16T00:30:00Z")
        #expect(store.bracketHiddenIds.contains("m-gen-fur"))
        #expect(store.bracketHiddenIds.contains("m-semi-done"))
        // Bandeau, calendrier, direct : l'événement à venir est une ligne fixe, absent des listes filtrées.
        let upcoming = store.schedule.first { $0.id == "m-gen-fur" }!
        #expect(store.isUpcomingMasked(upcoming))
        #expect(!store.withoutMaskedUpcoming(store.schedule).contains { $0.id == "m-gen-fur" || $0.id == "m-semi-done" })
        let content = HomeModel.compute(store.homeInputs(now: later, calendar: paris()))
        #expect(content.strip.flatMap(\.matchIds).contains("m-gen-fur") == false)
        #expect(!content.sections.recentResults.contains { $0.id == "m-semi-done" })
        // Ligues (Mondial suivi) : « Prochain · masqué ».
        let worlds = SampleData.leagues[0]
        let follows = FollowList(teams: store.follows.teams,
                                 leagues: [FollowedLeague(id: worlds.id, slug: worlds.slug, name: worlds.name)])
        let rows = LeagueRows.rows(follows: follows, schedule: store.schedule, revealed: [],
                                   maskedLatestTeamIds: store.maskedLatestTeamIds, currentTournamentIds: [:],
                                   now: now, bracketHiddenIds: store.bracketHiddenIds)
        #expect(rows.first?.next == .hidden)
        // Révéler le match de T1 rend la suite.
        store.reveal(matchId: SampleData.t1MatchId)
        #expect(store.bracketHiddenIds.isEmpty)
        #expect(store.withoutMaskedUpcoming(store.schedule).contains { $0.id == "m-gen-fur" })
        store.endScene()
    }

    /// Détail : un match que cache la suite du tableau est masqué comme un match en anti-spoiler (même décision, donc
    /// aucune clé de fonctionnalité ni requête) ; révéler le match de T1 le rend, et révéler le match lui-même aussi.
    @Test func aBracketHiddenMatchIsMaskedInTheDetailUntilRevealed() {
        let store = AppStore(preview: PreviewData.withSeason)
        let hidden = store.schedule.first { $0.id == "m-gen-fur" }!
        let teams = hidden.match.teams
        #expect(!store.isMasked(teams, matchId: hidden.id))
        #expect(store.isBracketHidden(matchId: hidden.id))
        #expect(store.isDetailMasked(teams, matchId: hidden.id))
        #expect(store.isDetailMasked(teams, matchId: hidden.id, bracketHidden: true))
        let model = MatchDetailModel(matchId: hidden.id)
        #expect(model.featureGame(store: store) == nil)
        // Un match du tableau non caché n'est pas touché.
        let other = store.schedule.first { $0.id == "m-gen-hle" }!
        #expect(!store.isDetailMasked(other.match.teams, matchId: other.id))
        // « Toucher pour révéler » : CE match.
        store.reveal(matchId: hidden.id)
        #expect(!store.isBracketHidden(matchId: hidden.id))
        #expect(!store.isDetailMasked(teams, matchId: hidden.id))
        store.endScene()
        // Révéler le match masqué de T1 restaure aussi la suite.
        let again = AppStore(preview: PreviewData.withSeason)
        #expect(again.isDetailMasked(teams, matchId: hidden.id))
        again.reveal(matchId: SampleData.t1MatchId)
        #expect(!again.isDetailMasked(teams, matchId: hidden.id))
        again.endScene()
    }
}
