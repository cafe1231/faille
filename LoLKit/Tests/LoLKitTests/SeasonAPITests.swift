import Foundation
import Testing
@testable import LoLKit

/// Fixture réelle réduite du dossier `Fixtures/season/` (capturée le 14/10/2026, spec saison §1.1).
private func seasonJSON(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/season") else {
        throw Fixture.Missing(name: "season/\(name)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// API de la saison (spec saison §1.1, §1.2) : tournois, matchs terminés, classements, page de calendrier, effectif.
@Suite struct SeasonAPITests {
    private static let lec = "98767991302996019"
    private static let lecSplit3 = "115548681802226458"
    private static let kc = "111692118851466302"

    @Test func tournamentsOfALeagueNewestFirstWithTheLeagueId() async throws {
        let fake = FakeTransport()
        try await fake.on("getTournamentsForLeague", body: try seasonJSON("getTournamentsForLeague_lec_reduced"))
        let tournaments = try await LoLClient(transport: fake).tournaments(leagueId: Self.lec)
        #expect(tournaments.map(\.slug) == ["lec_split_3_2026", "lec_split_2_2026", "lec_split_1_2026", "lec_summer_2025"])
        #expect(tournaments[0] == TournamentRef(id: Self.lecSplit3, slug: "lec_split_3_2026", startDate: "2026-07-23",
                                                endDate: "2026-09-20", leagueId: Self.lec))
        #expect(tournaments.allSatisfy { $0.leagueId == Self.lec })
        #expect(tournaments.map(\.year) == [2026, 2026, 2026, 2025])

        let request = try #require(await fake.requests.first)
        #expect(request.url.path == "/persisted/gw/getTournamentsForLeague")
        #expect(queryValue(request.url, "leagueId") == Self.lec)
        #expect(queryValue(request.url, "hl") == "fr-FR")
        #expect(request.headers["x-api-key"] == LoLClient.publicAPIKey)
    }

    /// Actif de la date de début à la date de fin + 2 jours (§1.2).
    @Test func aTournamentIsActiveUntilTwoDaysAfterItsEnd() {
        let split3 = TournamentRef(id: Self.lecSplit3, slug: "lec_split_3_2026", startDate: "2026-07-23",
                                   endDate: "2026-09-20", leagueId: Self.lec)
        #expect(!split3.isActive(today: "2026-07-22"))
        #expect(split3.isActive(today: "2026-07-23"))
        #expect(split3.isActive(today: "2026-09-22"))
        #expect(!split3.isActive(today: "2026-09-23"))
        // Fin de mois et d'année.
        let worlds = TournamentRef(id: "w", slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-12-30", leagueId: "")
        #expect(worlds.isActive(today: "2027-01-01"))
        #expect(!worlds.isActive(today: "2027-01-02"))
        #expect(!TournamentRef(id: "x", slug: "", startDate: "", endDate: "", leagueId: "").isActive(today: "2026-10-15"))
    }

    /// KC 1-3 G2 (Bo5, game 5 listée mais pas jouée) et KC 2-0 VIT (Bo3, game 3 pas jouée).
    @Test func completedEventsListAllGamesAndThePlayedOnes() async throws {
        let fake = FakeTransport()
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_reduced"))
        let matches = try await LoLClient(transport: fake).completedEvents(tournamentId: Self.lecSplit3)
        #expect(matches.map(\.matchId) == ["115548681803406303", "115548681803406199"])
        let final = matches[0]
        #expect(final.startTime == date("2026-09-06T15:00:00Z"))
        #expect(final.blockName == "Play-offs")
        #expect(final.bestOf == 5)
        #expect(final.teams.map(\.code) == ["KC", "G2"])
        #expect(final.teams.map(\.gameWins) == [1, 3])
        #expect(final.teams.allSatisfy { $0.id == nil })
        #expect(final.gameIds.count == 5)
        #expect(final.playedGameIds == ["115548681803406304", "115548681803406305", "115548681803406306",
                                        "115548681803406307"])
        #expect(matches[1].bestOf == 3)
        #expect(matches[1].playedGameIds == ["115548681803406200", "115548681803406201"])
        #expect(queryValue(try #require(await fake.requests.first?.url), "tournamentId") == Self.lecSplit3)
    }

    /// LEC Split 3 entier (53 matchs) : 175 games listées, 137 jouées (§1.1).
    @Test func lecSplit3Has137PlayedGamesOutOf175Listed() async throws {
        let fake = FakeTransport()
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_ids"))
        let matches = try await LoLClient(transport: fake).completedEvents(tournamentId: Self.lecSplit3)
        #expect(matches.count == 53)
        #expect(matches.reduce(0) { $0 + $1.gameIds.count } == 175)
        #expect(matches.reduce(0) { $0 + $1.playedGameIds.count } == 137)
    }

    /// Classement de la saison régulière (KC 9-0, VIT 7-2, G2 6-3) et play-offs sans classement, ids d'équipe présents.
    @Test func standingsOfTheLecSplit() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: try seasonJSON("getStandings_lec3_reduced"))
        let standings = try await LoLClient(transport: fake).standings(tournamentId: Self.lecSplit3)
        #expect(standings.stages.map(\.slug) == ["regular_season", "playoffs"])
        #expect(standings.stages[0].name == "Saison régulière")
        let rankings = standings.stages[0].sections[0].rankings
        #expect(rankings.map(\.ordinal) == [1, 2, 3])
        #expect(rankings[0].teams == [RankedTeam(id: Self.kc, code: "KC", name: "Karmine Corp",
                                                 image: "http://static.lolesports.com/teams/1704714951336_KC.png",
                                                 wins: 9, losses: 0)])
        #expect(rankings.map { "\($0.teams[0].code) \($0.teams[0].wins)-\($0.teams[0].losses)" } == ["KC 9-0", "VIT 7-2", "G2 6-3"])
        #expect(standings.stages[1].sections[0].rankings.isEmpty)
        let kcMkoi = try #require(standings.match(id: "115548681803406327"))
        #expect(kcMkoi.state == .completed)
        #expect(kcMkoi.teams.map(\.id) == [Self.kc, "103461966965149786"])
        #expect(kcMkoi.teams.map { $0.result?.outcome } == ["loss", "win"])
        #expect(standings.stage(containing: "115548681803406327")?.slug == "playoffs")
        #expect(standings.stage(containing: "inconnu") == nil)
        #expect(standings.allMatches.count == 4)
    }

    /// Mondial 2026 avant son début : trois étapes, jamais de `rankings`, équipes à venir `id "0"` / `TBD`.
    @Test func worldsStandingsHavePlaceholders() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: try seasonJSON("getStandings_worlds26_reduced"))
        let standings = try await LoLClient(transport: fake).standings(tournamentId: "115660540725177488")
        #expect(standings.stages.map(\.slug) == ["play_ins", "swiss", "knockouts"])
        #expect(standings.stages.allSatisfy { $0.sections.allSatisfy(\.rankings.isEmpty) })
        let tbd = try #require(standings.stages[1].sections[0].matches.first?.teams.first)
        #expect(tbd.id == "0")
        #expect(tbd.isPlaceholder)
        #expect(tbd.result == nil)
        #expect(standings.match(id: "115660588583171786")?.teams.map(\.code) == ["C9", "KC"])
    }

    @Test func noStandingsGivesNoStage() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: #"{"data":{"standings":[]}}"#)
        #expect(try await LoLClient(transport: fake).standings(tournamentId: "x") == Standings(stages: []))
    }

    /// Décodage tolérant : un champ retiré ne fait échouer ni l'étape, ni la section, ni l'équipe classée.
    @Test func standingsDecodeTolerantly() throws {
        let json = #"""
        {"data":{"standings":[{"stages":[
          {"id":"s1","sections":[{"matches":[{"id":"m1","teams":[{"id":"a","name":"A","code":"A","result":null}]},
                                              {"state":"completed"}]}]},
          {"id":"s2","name":"Play-offs","slug":"playoffs","sections":[{"name":"P","rankings":[{"ordinal":1,"teams":[{"id":"a"}]}]}]},
          {"name":"sans id"}
        ]}]}}
        """#
        let standings = try JSONDecoder.lolesports().decode(StandingsResponse.self, from: Data(json.utf8))
            .data.standings.elements[0]
        #expect(standings.stages.map(\.id) == ["s1", "s2"])
        #expect(standings.stages[0].name == "" && standings.stages[0].slug == "")
        #expect(standings.stages[0].sections[0].matches.map(\.id) == ["m1"])
        #expect(standings.stages[0].sections[0].matches[0].state == .unknown)
        #expect(standings.stages[0].sections[0].rankings.isEmpty)
        #expect(standings.stages[1].sections[0].matches.isEmpty)
        #expect(standings.stages[1].sections[0].rankings[0].teams == [RankedTeam(id: "a", code: "", name: "", image: nil,
                                                                                  wins: 0, losses: 0)])
    }

    @Test func completedEventsDecodeTolerantly() throws {
        let json = #"""
        {"data":{"schedule":{"events":[
          {"startTime":"2026-09-06T15:00:00Z","match":{"id":"m1"}},
          {"startTime":"2026-09-06T15:00:00Z","match":{"teams":[]}},
          {"match":{"id":"m3"}}
        ]}}}
        """#
        let events = try JSONDecoder.lolesports().decode(CompletedEventsResponse.self, from: Data(json.utf8))
            .data.schedule.events.elements.map(\.completed)
        #expect(events == [CompletedMatch(matchId: "m1", startTime: date("2026-09-06T15:00:00Z"), blockName: nil,
                                          bestOf: 1, teams: [], gameIds: [])])
    }

    /// Le cache disque (`Cached<…>`, `JSONEncoder` par défaut) se relit à l'identique.
    @Test func seasonValuesRoundTripThroughTheDiskCache() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: try seasonJSON("getStandings_lec3_reduced"))
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_reduced"))
        try await fake.on("getTournamentsForLeague", body: try seasonJSON("getTournamentsForLeague_lec_reduced"))
        let client = LoLClient(transport: fake)
        let fetchedAt = date("2026-10-14T20:00:00Z")

        let standings = Cached(value: try await client.standings(tournamentId: Self.lecSplit3), fetchedAt: fetchedAt)
        #expect(try JSONDecoder().decode(Cached<Standings>.self, from: JSONEncoder().encode(standings)) == standings)
        let completed = Cached(value: try await client.completedEvents(tournamentId: Self.lecSplit3), fetchedAt: fetchedAt)
        #expect(try JSONDecoder().decode(Cached<[CompletedMatch]>.self, from: JSONEncoder().encode(completed)) == completed)
        let tournaments = Cached(value: try await client.tournaments(leagueId: Self.lec), fetchedAt: fetchedAt)
        #expect(try JSONDecoder().decode(Cached<[TournamentRef]>.self, from: JSONEncoder().encode(tournaments)) == tournaments)
    }

    /// Page `older` du calendrier LEC : jetons de pagination et matchs (sans id de game ni d'équipe).
    @Test func schedulePageCarriesThePageTokens() async throws {
        let fake = FakeTransport()
        try await fake.on("getSchedule", body: try seasonJSON("getSchedule_lec_page1_reduced"))
        let page = try await LoLClient(transport: fake)
            .schedulePage(leagueIds: [Self.lec], pageToken: "b2xkZXI6OjExNTU0ODY2ODA1OTU4OTMyMA==")
        #expect(page.older == "b2xkZXI6OjExNTU0ODQyNDMwODQxNDI0NA==")
        #expect(page.newer == "bmV3ZXI6OjExNTU0ODY2ODA1OTUyMzc1Mg==")
        #expect(page.events.map(\.id) == ["115548424308414244", "115548424308414224"])
        #expect(page.events[0].match.teams.map(\.code) == ["LR", "TH"])
        let url = try #require(await fake.requests.first?.url)
        #expect(queryValue(url, "pageToken") == "b2xkZXI6OjExNTU0ODY2ODA1OTU4OTMyMA==")
        #expect(queryValue(url, "leagueId") == Self.lec)

        // Sans jeton : la page autour d'aujourd'hui ; `pages` absent → aucun jeton.
        let empty = FakeTransport()
        try await empty.on("getSchedule", body: #"{"data":{"schedule":{"events":[]}}}"#)
        let first = try await LoLClient(transport: empty).schedulePage(leagueIds: [], pageToken: nil)
        #expect(queryValue(try #require(await empty.requests.first?.url), "pageToken") == nil)
        #expect(first == SchedulePageResult(events: [], older: nil, newer: nil))
    }

    /// Effectif de KC dans `getTeams` : 5 joueurs avec rôle ; `id` = `esportsPlayerId` du flux.
    @Test func teamsCarryTheirRoster() async throws {
        let fake = FakeTransport()
        try await fake.on("getTeams", body: try seasonJSON("getTeams_karmine-corp"))
        let kc = try #require(try await LoLClient(transport: fake).teams().first)
        let players = try #require(kc.players)
        #expect(players.count == 5)
        #expect(players[0] == TeamPlayer(id: "103495716771322725", summonerName: "Canna",
                                         image: "http://static.lolesports.com/players/1774651372836_canna.png",
                                         role: "top"))
        #expect(players.map(\.role) == ["top", "jungle", "bottom", "mid", "support"])
        #expect(kc.homeLeague?.name == "LEC")
    }

    /// Le catalogue réduit déjà au dépôt (un joueur par équipe) se lit aussi ; un effectif absent donne nil, un effectif
    /// illisible ne retire pas l'équipe.
    @Test func rosterIsOptionalAndTolerant() throws {
        #expect(try catalogTeam("KC").players?.map(\.summonerName) == ["Canna"])
        let json = #"""
        {"data":{"teams":[
          {"id":"1","slug":"a","name":"A","code":"A","status":"active","players":"oups"},
          {"id":"2","slug":"b","name":"B","code":"B","players":[{"id":"p1","summonerName":"Un"},{"summonerName":"sans id"}]},
          {"id":"3","slug":"c","name":"C","code":"C"}
        ]}}
        """#
        let teams = try JSONDecoder.lolesports().decode(TeamsResponse.self, from: Data(json.utf8)).data.teams.elements
        #expect(teams.map(\.id) == ["1", "2", "3"])
        #expect(teams[0].players == nil)
        #expect(teams[2].players == nil)
        #expect(teams[1].players == [TeamPlayer(id: "p1", summonerName: "Un", image: nil, role: nil)])
        let roundTrip = try JSONDecoder().decode(Team.self, from: JSONEncoder().encode(teams[1]))
        #expect(roundTrip == teams[1])
    }

    /// Jointure (§1.2) : ids d'équipe et étape depuis `getStandings` ; à défaut, ids du catalogue (nom, logo).
    @Test func seasonMatchesJoinCompletedEventsAndStandings() async throws {
        let fake = FakeTransport()
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_ids"))
        try await fake.on("getStandings", body: try seasonJSON("getStandings_lec3_reduced"))
        try await fake.on("getTeams", body: try seasonJSON("getTeams_karmine-corp"))
        let client = LoLClient(transport: fake)
        let completed = try await client.completedEvents(tournamentId: Self.lecSplit3)
        let standings = try await client.standings(tournamentId: Self.lecSplit3)
        let catalog = try await client.teams()

        let matches = SeasonMatch.join(completed: completed, standings: standings, tournamentId: Self.lecSplit3,
                                       leagueSlug: "lec", catalog: catalog)
        #expect(matches.count == 53)
        #expect(matches.map(\.id) == completed.map(\.matchId))
        #expect(matches.reduce(0) { $0 + $1.playedGameIds.count } == 137)

        // Dans les classements : ids et étape.
        let kcMkoi = try #require(matches.first { $0.id == "115548681803406327" })
        #expect(kcMkoi.stageSlug == "playoffs")
        #expect(kcMkoi.teams.map(\.id) == [Self.kc, "103461966965149786"])
        #expect(kcMkoi.involves(Self.kc))
        #expect(kcMkoi.tournamentId == Self.lecSplit3 && kcMkoi.leagueSlug == "lec")
        #expect(kcMkoi.bestOf == 5)
        let thNavi = try #require(matches.first { $0.id == "115548681803340575" })
        #expect(thNavi.stageSlug == "regular_season")

        // Hors des classements réduits : KC retrouvée dans le catalogue par son nom, G2 (absente du catalogue) sans id.
        let kcG2 = try #require(matches.first { $0.id == "115548681803406303" })
        #expect(kcG2.stageSlug == nil)
        #expect(kcG2.teams.map(\.id) == [Self.kc, nil])
        #expect(kcG2.teams.map(\.gameWins) == [1, 3])
        #expect(kcG2.playedGameIds.count == 4)
        #expect(matches.filter { $0.involves(Self.kc) }.count == 12)
    }
}
