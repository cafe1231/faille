import Foundation
import Testing
@testable import LoLKit

@Suite struct FollowListTests {
    @Test func followKeepsOrderAndIgnoresDuplicates() throws {
        var follows = FollowList()
        follows.follow(try catalogTeam("KC"))
        follows.follow(try catalogTeam("T1"))
        follows.follow(try catalogTeam("KC"))
        #expect(follows.teams.map(\.code) == ["KC", "T1"])
        #expect(follows.contains(id: "111692118851466302"))

        follows.unfollow(id: "111692118851466302")
        #expect(follows.teams.map(\.code) == ["T1"])
    }

    @Test func settingsAndColors() throws {
        var follows = FollowList()
        let kc = try catalogTeam("KC")
        follows.follow(kc)
        #expect(follows.team(id: kc.id)?.colorHex == FollowedTeam.defaultColorHex)

        follows.setAutoColor("#5B8CFF", id: kc.id)
        #expect(follows.team(id: kc.id)?.colorHex == "#5B8CFF")
        follows.setColorOverride("#FF5C7A", id: kc.id)
        #expect(follows.team(id: kc.id)?.colorHex == "#FF5C7A")
        follows.setColorOverride(nil, id: kc.id)
        #expect(follows.team(id: kc.id)?.colorHex == "#5B8CFF")

        follows.setSpoilerFree(true, id: kc.id)
        #expect(follows.team(id: kc.id)?.spoilerFree == true)
    }

    @Test func matchesById_thenName_thenLogo_neverCodeAlone() throws {
        let kia = FollowedTeam(team: try catalogTeam("C9"))
        #expect(kia.name == "Cloud9 Kia")

        #expect(makeTeam("C9", id: "98767991877340524").isSame(as: kia))
        #expect(!makeTeam("C9", id: "99566405130451785", name: "Cloud9 Kia").isSame(as: kia))
        #expect(makeTeam("C9", name: "cloud9 kia").isSame(as: kia))
        #expect(makeTeam("C9", name: "Cloud9", image: kia.image).isSame(as: kia))
        #expect(!makeTeam("C9", name: "Cloud9 Challengers").isSame(as: kia))
    }

    @Test func followedInMatchUsesFollowOrder() throws {
        var follows = FollowList()
        follows.follow(try catalogTeam("T1"))
        follows.follow(try catalogTeam("KC"))
        let teams = [makeTeam("KC", name: "Karmine Corp"), makeTeam("T1", name: "T1")]
        #expect(follows.followed(in: teams).map(\.code) == ["T1", "KC"])
        #expect(follows.involves(teams))
        #expect(!follows.involves([makeTeam("BRO", name: "HANJIN BRION")]))
    }

    @Test func refreshUpdatesRenamedTeams() throws {
        var follows = FollowList()
        let kc = try catalogTeam("KC")
        follows.follow(kc)
        let renamed = Team(id: kc.id, slug: kc.slug, name: "Karmine Corp Blue Lions", code: "KCL",
                           image: "http://nouveau-logo.png", status: "active",
                           homeLeague: Team.HomeLeague(name: "LEC", region: "EMEA"))
        follows.refresh(from: [renamed])
        #expect(follows.team(id: kc.id)?.name == "Karmine Corp Blue Lions")
        #expect(follows.team(id: kc.id)?.code == "KCL")
        #expect(follows.team(id: kc.id)?.image == "http://nouveau-logo.png")
    }

    @Test func roundTripsThroughJSON() throws {
        var follows = FollowList()
        follows.follow(try catalogTeam("SLY"))
        follows.setSpoilerFree(true, id: "105515345386578249")
        let data = try JSONEncoder().encode(follows)
        #expect(try JSONDecoder().decode(FollowList.self, from: data) == follows)
    }

    @Test func refreshKeepsUserSettingsAndNeverAddsTeams() throws {
        var follows = FollowList()
        let kc = try catalogTeam("KC")
        follows.follow(kc)
        follows.setSpoilerFree(true, id: kc.id)
        follows.setAutoColor("#5B8CFF", id: kc.id)
        follows.setColorOverride("#FF5C7A", id: kc.id)
        let renamed = Team(id: kc.id, slug: kc.slug, name: "Karmine Corp Blue Lions", code: "KCL",
                           image: kc.image, status: "active", homeLeague: kc.homeLeague)
        follows.refresh(from: [renamed, try catalogTeam("T1")])
        let team = try #require(follows.team(id: kc.id))
        #expect(team.name == "Karmine Corp Blue Lions")
        #expect(team.spoilerFree)
        #expect(team.autoColorHex == "#5B8CFF")
        #expect(team.colorOverrideHex == "#FF5C7A")
        #expect(follows.teams.map(\.code) == ["KCL"])
    }

    @Test func roundTripsColorsAndOverride() throws {
        var follows = FollowList()
        let kc = try catalogTeam("KC")
        follows.follow(kc)
        follows.setAutoColor("#5B8CFF", id: kc.id)
        follows.setColorOverride("#FF5C7A", id: kc.id)
        let decoded = try JSONDecoder().decode(FollowList.self, from: JSONEncoder().encode(follows))
        #expect(decoded == follows)
        #expect(decoded.team(id: kc.id)?.autoColorHex == "#5B8CFF")
        #expect(decoded.team(id: kc.id)?.colorOverrideHex == "#FF5C7A")
    }

    @Test func legacyJSONWithoutSpoilerFreeDecodesAsFalse() throws {
        let json = #"{"teams":[{"id":"111692118851466302","code":"KC","name":"Karmine Corp"}]}"#
        let follows = try JSONDecoder().decode(FollowList.self, from: Data(json.utf8))
        let team = try #require(follows.teams.first)
        #expect(team.code == "KC")
        #expect(team.spoilerFree == false)
        #expect(team.image == nil && team.homeLeagueName == nil)
        #expect(team.autoColorHex == nil && team.colorOverrideHex == nil)
    }

    @Test func wronglyTypedOptionalFieldsDoNotLoseTheTeam() throws {
        // Un champ optionnel mal typé retombe sur sa valeur par défaut ; l'équipe (id, code, nom) est conservée.
        let json = #"""
        {"teams":[
          {"id":"a","code":"KC","name":"Karmine Corp","image":42,"homeLeagueName":["LEC"],
           "spoilerFree":"oui","autoColorHex":{"r":1},"colorOverrideHex":true},
          {"id":"b","code":"T1","name":"T1","image":"https://img/t1.png","spoilerFree":true,"colorOverrideHex":"#FF5C7A"}
        ]}
        """#
        let follows = try JSONDecoder().decode(FollowList.self, from: Data(json.utf8))
        #expect(follows.teams.map(\.code) == ["KC", "T1"])
        let kc = try #require(follows.team(id: "a"))
        #expect(kc.image == nil && kc.homeLeagueName == nil)
        #expect(kc.spoilerFree == false)
        #expect(kc.autoColorHex == nil && kc.colorOverrideHex == nil)
        // Les champs bien typés de l'autre équipe sont intacts.
        let t1 = try #require(follows.team(id: "b"))
        #expect(t1.image == "https://img/t1.png")
        #expect(t1.spoilerFree)
        #expect(t1.colorOverrideHex == "#FF5C7A")
    }

    @Test func unreadableEntryIsDroppedAndOthersKept() throws {
        let json = #"""
        {"teams":[
          {"id":"a","code":"KC","name":"Karmine Corp","spoilerFree":true},
          {"code":"SANS","name":"Sans identifiant"},
          {"id":"b","code":"T1","name":"T1"}
        ]}
        """#
        let follows = try JSONDecoder().decode(FollowList.self, from: Data(json.utf8))
        #expect(follows.teams.map(\.code) == ["KC", "T1"])
        #expect(follows.team(id: "a")?.spoilerFree == true)
    }

    @Test func scheduleLeagueIdsAreHomeLeaguesPlusInternational() throws {
        let leagues = try JSONDecoder.lolesports()
            .decode(LeaguesResponse.self, from: Fixture.data("getLeagues")).data.leagues.elements
        var follows = FollowList()
        follows.follow(try catalogTeam("KC"))
        follows.follow(try catalogTeam("SLY"))
        #expect(ScheduleQuery.leagueIds(follows: follows, leagues: leagues) == [
            "98767975604431411",  // worlds
            "98767991325878492",  // msi
            "113464388705111224", // first_stand
            "98767991302996019",  // lec
            "105266103462388553", // lfl
        ])
    }
}
