import Foundation
import LoLKit
import Testing
@testable import Faille


private func upcoming(_ id: String, _ start: String, _ a: (String, String), _ b: (String, String),
                      league: LeagueRef = SampleData.worlds) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: .unstarted, type: "match", blockName: nil, league: league,
               match: MatchInfo(id: id, teams: [MatchTeam(id: a.0, name: a.1, code: a.0.uppercased(), image: nil, result: nil),
                                                MatchTeam(id: b.0, name: b.1, code: b.0.uppercased(), image: nil, result: nil)],
                                strategy: Strategy(type: "bestOf", count: 3), games: nil),
               streams: nil)
}

private func completed(_ id: String, _ start: String, _ a: (String, String, Int), _ b: (String, String, Int)) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: .completed, type: "match", blockName: nil, league: SampleData.worlds,
               match: MatchInfo(id: id, teams: [
                   MatchTeam(id: a.0, name: a.1, code: a.0.uppercased(), image: nil,
                             result: MatchTeam.Result(outcome: a.2 > b.2 ? "win" : "loss", gameWins: a.2)),
                   MatchTeam(id: b.0, name: b.1, code: b.0.uppercased(), image: nil,
                             result: MatchTeam.Result(outcome: b.2 > a.2 ? "win" : "loss", gameWins: b.2)),
               ], strategy: Strategy(type: "bestOf", count: 3), games: nil),
               streams: nil)
}

struct TeamPageModelTests {
    private let gen = FollowedTeam(id: "gen", code: "GEN", name: "Gen.G")
    private let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)

    @Test func aSpoilerFreeTeamWithAMaskedLastMatchShowsOnlyAHiddenLine() {
        let schedule = [completed("last", "2026-10-14T10:00:00Z", ("t1", "T1", 2), ("blg", "BLG", 0)),
                        upcoming("next", "2026-10-17T12:00:00Z", ("t1", "T1"), ("hle", "HLE"))]
        let follows = FollowList(teams: [t1])
        let lines = TeamPageModel.upcoming(team: t1, schedule: schedule, live: nil, follows: follows, revealed: [],
                                           maskedLatestTeamIds: ["t1"])
        #expect(lines == .hidden)
        // Révélé : le prochain match seul (équipe en anti-spoiler).
        let revealed = TeamPageModel.upcoming(team: t1, schedule: schedule, live: nil, follows: follows, revealed: ["last"],
                                              maskedLatestTeamIds: [])
        #expect(revealed == .matches([schedule[1]]))
    }

    @Test func anOrdinaryTeamShowsUpToThreeMatchesButNeverOneAgainstAMaskedSpoilerFreeTeam() {
        let schedule = [upcoming("a", "2026-10-16T09:00:00Z", ("gen", "Gen.G"), ("fur", "FURIA")),
                        upcoming("b", "2026-10-17T12:00:00Z", ("t1", "T1"), ("gen", "Gen.G")),
                        upcoming("c", "2026-10-18T12:00:00Z", ("gen", "Gen.G"), ("hle", "HLE")),
                        upcoming("d", "2026-10-19T12:00:00Z", ("gen", "Gen.G"), ("blg", "BLG"))]
        let follows = FollowList(teams: [gen, t1])
        let lines = TeamPageModel.upcoming(team: gen, schedule: schedule, live: nil, follows: follows, revealed: [],
                                           maskedLatestTeamIds: ["t1"])
        #expect(lines == .matches([schedule[0], schedule[2], schedule[3]]))
        #expect(TeamPageModel.nextOpponentId(lines, team: gen, catalog: []) == "fur")
        // Calendrier sans id d'équipe : l'adversaire est retrouvé dans le catalogue par son nom.
        let anonymous = MatchEvent(startTime: schedule[0].startTime, state: .unstarted, type: "match", blockName: nil,
                                   league: SampleData.worlds,
                                   match: MatchInfo(id: "a", teams: [MatchTeam(id: nil, name: "Gen.G", code: "GEN", image: nil, result: nil),
                                                                     MatchTeam(id: nil, name: "FURIA", code: "FUR", image: nil, result: nil)],
                                                    strategy: nil, games: nil),
                                   streams: nil)
        #expect(TeamPageModel.nextOpponentId(.matches([anonymous]), team: gen, catalog: SampleData.catalog) == "fur")
    }

    @Test func standingLineIsMaskedRankedOrAbsent() {
        let standings = SeasonSamples.standings[SeasonSamples.lecSplit3.id]
        #expect(TeamPageModel.standing(teamId: "kc", tournamentId: "t", standings: standings, masked: false)
                == .ranked(tournamentId: "t", ordinal: 1, wins: 9, losses: 0))
        #expect(TeamPageModel.standing(teamId: "kc", tournamentId: "t", standings: standings, masked: true)
                == .masked(tournamentId: "t"))
        #expect(TeamPageModel.standing(teamId: "kc", tournamentId: "t", standings: nil, masked: false) == nil)
    }
}

/// Contenu de la page assemblé sur la saison d'exemple (T1 en anti-spoiler) : rien de ses matchs masqués.
@MainActor
@Suite(.serialized)
struct TeamPageContentTests {
    private let now = SampleData.date("2026-10-15T15:05:00Z")

    @Test func aSpoilerFreeTeamCountsItsMaskedMatchesAndHidesItsNextOne() throws {
        let content = TeamPageContent.make(store: AppStore(preview: .withSeason), teamId: "t1", scopeIndex: 0, now: now)
        let season = try #require(content.season)
        #expect(season.maskedMatches == 3)
        #expect(season.seriesWins + season.seriesLosses == 0)
        #expect(TeamPageModel.allMasked(season))
        #expect(content.upcoming == .hidden)
        #expect(content.headToHead == nil)
    }

    @Test func scopesAndStandingOfKarmineCorp() {
        let content = TeamPageContent.make(store: AppStore(preview: .withSeason), teamId: "kc", scopeIndex: 0, now: now)
        #expect(content.scopes.map(SeasonLabels.scope) == ["Saison 2026", "Mondial", "LEC Split 3"])
        #expect(content.roster.map(\.summonerName) == ["Canna", "Yike", "kyeahoo", "Caliste", "Busio"])
        // Le classement du Mondial contient des matchs masqués de T1 : masqué, même sur la page de KC.
        #expect(content.standing == .masked(tournamentId: SeasonSamples.worlds.id))
        let lec = TeamPageContent.make(store: AppStore(preview: .withSeason), teamId: "kc", scopeIndex: 2, now: now)
        #expect(lec.scope.map(SeasonLabels.scope) == "LEC Split 3")
    }

    /// Anti-spoiler I-1 : aucune ligne de « Prochains matchs » n'est un match à venir masqué, quelle que soit la page.
    @Test func upcomingLinesNeverContainAMaskedUpcomingMatch() {
        let store = AppStore(preview: .withSeason)
        for teamId in ["t1", "kc", "gen", "g2"] {
            let content = TeamPageContent.make(store: store, teamId: teamId, scopeIndex: 0, now: now)
            if case let .matches(events) = content.upcoming {
                #expect(events.allSatisfy { !store.isUpcomingMasked($0) })
            }
        }
    }
}
