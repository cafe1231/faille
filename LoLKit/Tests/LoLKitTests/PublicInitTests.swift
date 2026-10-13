import Foundation
import Testing
// Volontairement SANS `@testable` : prouve que l'appli et les widgets (autres modules) peuvent construire ces types.
import LoLKit

@Suite struct PublicInitTests {
    private let league = LeagueRef(id: "98767975604431411", slug: "worlds", name: "Mondial", image: "http://league.png")
    private let kc = MatchTeam(id: "111692118851466302", name: "Karmine Corp", code: "KC", image: nil,
                               result: MatchTeam.Result(outcome: "win", gameWins: 1))
    private let c9 = MatchTeam(id: "98767991877340524", name: "Cloud9 Kia", code: "C9", image: nil, result: nil)

    @Test func catalogTypes() {
        let leagueEntry = League(id: "1", slug: "lec", name: "LEC", region: "EMEA", image: "http://lec.png", priority: 3)
        #expect(leagueEntry.slug == "lec" && leagueEntry.priority == 3)

        let team = Team(id: "t", slug: "kc", name: "Karmine Corp", code: "KC", image: nil, status: "active",
                        homeLeague: Team.HomeLeague(name: "LEC", region: "EMEA"))
        #expect(team.isActive)
        #expect(team.homeLeague?.name == "LEC")
    }

    @Test func scheduleTypes() {
        let strategy = Strategy(type: "bestOf", count: 5)
        let side = GameRef.Side(id: "111692118851466302", side: "blue")
        let game = GameRef(number: 1, id: "g1", state: .inProgress, teams: [side])
        let match = MatchInfo(id: "m1", teams: [kc, c9], strategy: strategy, games: [game])
        let event = MatchEvent(startTime: Date(timeIntervalSince1970: 1_760_000_000), state: .inProgress, type: "match",
                               blockName: "Play-ins", league: league, match: match,
                               streams: [StreamInfo(statsStatus: "disabled")])
        #expect(event.id == "m1")
        #expect(event.bestOf == 5)
        #expect(event.statsDisabled)
        #expect(event.match.games?.first?.teams?.first?.side == "blue")
    }

    @Test func eventDetails() {
        let details = EventDetails(
            id: "m1",
            league: league,
            match: EventDetails.Match(strategy: Strategy(type: nil, count: 3), teams: [kc, c9],
                                      games: [GameRef(number: 1, id: "g1", state: .completed, teams: nil)]),
            streams: nil
        )
        #expect(details.bestOf == 3)
        #expect(details.match.teams.map(\.code) == ["KC", "C9"])
    }

    @Test func gameSnapshot() {
        let line = PlayerLine(role: "jungle", champion: "LeeSin", name: "KC Closer", level: 12,
                              kills: 3, deaths: 1, assists: 3, creepScore: 169, gold: 8359)
        let snapshot = GameSnapshot(
            gameId: "g1", phase: .paused, timestamp: Date(timeIntervalSince1970: 1_760_000_000),
            blueTeamId: "a", redTeamId: "b",
            blue: TeamStats(kills: 7), red: TeamStats(kills: 6),
            bluePlayers: [line], redPlayers: []
        )
        #expect(snapshot.stats(for: "a")?.kills == 7)
        #expect(snapshot.players(for: "a")?.first?.champion == "LeeSin")
    }

    @Test func followedTeamAndCard() {
        let followed = FollowedTeam(id: "111692118851466302", code: "KC", name: "Karmine Corp")
        #expect(followed.image == nil)
        #expect(!followed.spoilerFree)
        #expect(followed.colorHex == FollowedTeam.defaultColorHex)

        let custom = FollowedTeam(id: "x", code: "T1", name: "T1", image: "http://t1.png", homeLeagueName: "LCK",
                                  spoilerFree: true, autoColorHex: "#E4002B", colorOverrideHex: "#FFFFFF")
        #expect(custom.spoilerFree)
        #expect(custom.colorHex == "#FFFFFF")

        let card = TeamCard(team: followed, live: nil, next: nil, last: nil)
        #expect(card.id == followed.id)
    }

    @Test func scoreLine() {
        let line = ScoreLine(matchId: "m1", leagueName: "Mondial", bestOf: 5, teamCodes: ["KC", "C9"], score: [1, 0],
                             status: .live(gameNumber: 2), isMasked: false)
        #expect(line.status == .live(gameNumber: 2))
        #expect(line.score == [1, 0])
    }
}
