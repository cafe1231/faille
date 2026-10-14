import Foundation
import Testing
@testable import LoLKit

/// Réduction d'une game jouée (spec saison §1.3, §1.5) sur la game de référence 304 (KC 1-3 G2, game 1).
@Suite struct GameSummaryTests {
    /// Résumé attendu, calculé à part (`game_summary_115548681803406304.json`, palier B) : comparé valeur par valeur.
    private func expected() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: SeasonFixture.data("game_summary_115548681803406304"))
            as? [String: Any])
    }

    @Test func tierAReadsTheFirstAndTheFinishedFrames() throws {
        let summary = try SeasonFixture.summary304(enriched: false)
        #expect(summary.v == GameSummary.schemaVersion)
        #expect(summary.gameId == SeasonFixture.game304)
        #expect(summary.matchId == SeasonFixture.match303)
        #expect(summary.tournamentId == SeasonFixture.lecSplit3)
        #expect(summary.leagueSlug == "lec")
        #expect(summary.number == 1)
        #expect(summary.patch == "16.17.810.4348")
        #expect(summary.startedAt == date("2026-09-06T15:17:23.939Z"))
        #expect(summary.endedAt == date("2026-09-06T15:51:14.975Z"))
        // 33:51 = dernière frame − première frame (2031,036 s).
        #expect(summary.durationSeconds == 2031)
        #expect(summary.result == .unknown)
        #expect(!summary.enriched)

        #expect(summary.blue.teamId == SeasonFixture.kc)
        #expect([summary.blue.gold, summary.blue.kills, summary.blue.towers, summary.blue.inhibitors,
                 summary.blue.barons] as [Int] == [63_457, 11, 4, 0, 0])
        #expect(summary.blue.dragons.isEmpty)
        #expect(summary.red.teamId == SeasonFixture.g2)
        #expect([summary.red.gold, summary.red.kills, summary.red.towers, summary.red.inhibitors,
                 summary.red.barons] as [Int] == [70_918, 23, 10, 2, 2])
        #expect(summary.red.dragons == ["ocean", "mountain", "cloud", "cloud", "elder"])
        // Somme des gold joueurs = gold d'équipe.
        #expect(summary.blue.players.reduce(0) { $0 + $1.gold } == 63_457)

        let canna = try #require(summary.blue.players.first)
        #expect(canna == PlayerGameLine(playerId: "103495716771322725", name: "KC Canna", role: "top", champion: "Jayce",
                                        level: 18, kills: 1, deaths: 3, assists: 5, creepScore: 304, gold: 12_846))
        #expect(summary.blue.players.map(\.role) == ["top", "jungle", "mid", "bottom", "support"])
        #expect(summary.red.players.map(\.champion) == ["KSante", "XinZhao", "Viktor", "Ezreal", "Karma"])
        #expect(summary.red.players.map { "\($0.kills)/\($0.deaths)/\($0.assists)" }
                == ["3/2/6", "7/2/6", "7/2/5", "5/3/11", "1/2/18"])
        // Palier A : rien du palier B.
        #expect(summary.blue.gold15 == nil && summary.red.gold15 == nil)
        #expect(summary.blue.players.allSatisfy { $0.damageShare == nil && $0.gold15 == nil && $0.wardsPlaced == nil })
        #expect(summary.line(teamId: SeasonFixture.g2) == summary.red)
        #expect(summary.opponentLine(of: SeasonFixture.g2) == summary.blue)
        #expect(summary.line(teamId: "autre") == nil)
        #expect(summary.player("98767975968177297")?.line.champion == "Viktor")
        #expect(summary.player("98767975968177297")?.team.teamId == SeasonFixture.g2)
    }

    /// Palier B : à 15 min, KC +228 (26 851 contre 26 623), Canna 5 197 gold / 148 CS ; part des dégâts et balises.
    @Test func tierBMatchesTheExpectedSummary() throws {
        let summary = try SeasonFixture.summary304()
        let reference = try expected()
        #expect(summary.enriched)
        #expect(summary.blue.gold15 == 26_851)
        #expect(summary.red.gold15 == 26_623)
        #expect((summary.blue.gold15 ?? 0) - (summary.red.gold15 ?? 0) == 228)
        #expect(summary.blue.players[0].gold15 == 5_197)
        #expect(summary.blue.players[0].creepScore15 == 148)
        #expect(summary.blue.players[0].damageShare == 0.2278)
        #expect(summary.blue.players[3].damageShare == 0.3387)

        #expect(summary.durationSeconds == reference["durationSeconds"] as? Int)
        #expect(summary.patch == reference["patch"] as? String)
        for side in ["blue", "red"] {
            let line = side == "blue" ? summary.blue : summary.red
            let team = try #require(reference[side] as? [String: Any])
            #expect(line.teamId == team["teamId"] as? String)
            #expect(line.gold15 == team["gold15"] as? Int)
            #expect(line.dragons == team["dragons"] as? [String])
            let players = try #require(team["players"] as? [[String: Any]])
            #expect(players.count == line.players.count)
            for (player, wanted) in zip(line.players, players) {
                #expect(player.playerId == wanted["playerId"] as? String)
                #expect(player.name == wanted["name"] as? String)
                #expect(player.champion == wanted["champion"] as? String)
                #expect([player.level, player.kills, player.deaths, player.assists, player.creepScore, player.gold]
                        == ["level", "kills", "deaths", "assists", "creepScore", "gold"].map { wanted[$0] as? Int ?? -1 })
                #expect(player.damageShare == wanted["damageShare"] as? Double)
                #expect(player.wardsPlaced == wanted["wardsPlaced"] as? Int)
                #expect(player.wardsDestroyed == wanted["wardsDestroyed"] as? Int)
                #expect(player.gold15 == wanted["gold15"] as? Int)
                #expect(player.creepScore15 == wanted["creepScore15"] as? Int)
            }
        }
    }

    /// « Jamais de chiffre inventé » : pas de frame `finished` → pas de résumé ; deux games différentes → rien.
    @Test func noSummaryWithoutTheFinishedFrame() throws {
        let first = try SeasonFixture.window("window_first_115548681803406304")
        #expect(GameSummary.make(first: first, final: first, at15: nil, details: nil, matchId: "m", number: 1,
                                 tournamentId: "t", leagueSlug: "lec") == nil)
        let other = try SeasonFixture.window("window_15min_115548681803406304")
        #expect(other.frames.allSatisfy { $0.gameState != "finished" })
        #expect(GameSummary.make(first: first, final: other, at15: nil, details: nil, matchId: "m", number: 1,
                                 tournamentId: "t", leagueSlug: "lec") == nil)
        let tlaw = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data("window_finished"))
        #expect(GameSummary.make(first: first, final: tlaw, at15: nil, details: nil, matchId: "m", number: 1,
                                 tournamentId: "t", leagueSlug: "lec") == nil)
    }

    /// Une frame à plus de 15 s de début + 900 s n'est pas « à 15 min ».
    @Test func goldAt15NeedsAFrameWithinFifteenSeconds() throws {
        let final = try SeasonFixture.window("window_final_115548681803406304")
        let summary = try #require(GameSummary.make(
            first: try SeasonFixture.window("window_first_115548681803406304"), final: final, at15: final,
            details: nil, matchId: SeasonFixture.match303, number: 1, tournamentId: SeasonFixture.lecSplit3,
            leagueSlug: "lec"))
        #expect(summary.blue.gold15 == nil)
        #expect(summary.blue.players.allSatisfy { $0.gold15 == nil && $0.creepScore15 == nil })
        #expect(summary.enriched)
    }

    /// Cache disque : `JSONEncoder` par défaut, relu à l'identique, ~3 Ko au palier B (jamais le JSON brut).
    @Test func roundTripsCompactly() throws {
        let summary = try SeasonFixture.summary304()
        let data = try JSONEncoder().encode(summary)
        #expect(data.count < 3_600)
        #expect(GameSummary.decodeStored(data) == summary)
        let tierA = try JSONEncoder().encode(try SeasonFixture.summary304(enriched: false))
        #expect(tierA.count < 2_600)
    }

    /// Schéma plus récent → ignoré ; champs retirés → relus à nil ou à une valeur neutre (jamais d'échec).
    @Test func storedSummariesDecodeTolerantly() throws {
        var object = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(try SeasonFixture.summary304())) as? [String: Any])
        object["v"] = GameSummary.schemaVersion + 1
        #expect(GameSummary.decodeStored(try JSONSerialization.data(withJSONObject: object)) == nil)

        object["v"] = nil
        object["patch"] = nil
        object["result"] = nil
        object["enriched"] = nil
        object["durationSeconds"] = nil
        var blue = try #require(object["blue"] as? [String: Any])
        var players = try #require(blue["players"] as? [[String: Any]])
        players[0]["damageShare"] = nil
        players[0]["gold15"] = nil
        players[1] = ["name": "sans id"]
        blue["players"] = players
        blue["gold15"] = nil
        object["blue"] = blue
        let summary = try #require(GameSummary.decodeStored(try JSONSerialization.data(withJSONObject: object)))
        #expect(summary.v == 1)
        #expect(summary.patch == nil)
        #expect(summary.result == .unknown)
        #expect(!summary.enriched)
        #expect(summary.durationSeconds == 2031)
        #expect(summary.blue.gold15 == nil)
        #expect(summary.blue.players.count == 4)
        #expect(summary.blue.players[0].damageShare == nil)
        #expect(summary.blue.players[0].kills == 1)
        #expect(summary.red.players.count == 5)

        let unknownBasis = #"{"winnerTeamId":"x","basis":"verified"}"#
        #expect(try JSONDecoder().decode(GameResult.self, from: Data(unknownBasis.utf8)).basis == .unknown)
        #expect(GameSummary.decodeStored(Data("{}".utf8)) == nil)
    }

    /// Le flux nomme le joueur avec le préfixe de son équipe ; `esportsPlayerId` est l'id de `getTeams`.
    @Test func participantMetadataCarriesThePlayerId() throws {
        let window = try SeasonFixture.window("window_first_115548681803406304")
        let canna = try #require(window.gameMetadata.blueTeamMetadata.participantMetadata.first)
        #expect(canna.esportsPlayerId == "103495716771322725")
        #expect(canna.summonerName == "KC Canna")
        // Une vieille capture sans `esportsPlayerId` reste lisible.
        let old = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data("window_finished"))
        #expect(old.gameMetadata.blueTeamMetadata.participantMetadata.count == 5)
    }
}
