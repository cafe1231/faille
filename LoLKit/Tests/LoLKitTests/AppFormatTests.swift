import Foundation
import Testing
@testable import LoLKit

@Suite struct AppFormatTests {
    @Test func timeAndOfflineBanner() throws {
        let paris = try #require(TimeZone(secondsFromGMT: 2 * 3600))
        #expect(Format.time(date("2026-10-15T12:05:00Z"), timeZone: paris) == "14:05")
        #expect(Format.time(date("2026-10-15T07:09:00Z"), timeZone: paris) == "09:09")
        #expect(Format.offlineBanner(lastUpdate: date("2026-10-15T12:05:00Z"), timeZone: paris)
                == "lolesports ne répond pas · màj 14:05")
        #expect(Format.offlineBanner(lastUpdate: nil) == "lolesports ne répond pas")
    }

    @Test func clockScoreAndKda() {
        #expect(Format.clock(1122) == "18:42")
        #expect(Format.clock(65) == "1:05")
        #expect(Format.clock(3725) == "1:02:05")
        #expect(Format.clock(-5) == "0:00")
        #expect(Format.score([1, 0]) == "1 – 0")
        let line = PlayerLine(role: "jungle", champion: "XinZhao", name: "KC Jungle", level: 9, kills: 1, deaths: 1,
                              assists: 4, creepScore: 118, gold: 6100)
        #expect(Format.kda(line) == "1/1/4")
    }

    @Test func namesInFrench() {
        #expect(Format.dragons(["infernal", "ocean"]) == "infernal · océan")
        #expect(Format.dragons(["elder", "mystery"]) == "ancestral · mystery")
        #expect(Format.dragons([]) == "")
        #expect(Format.dragons(["hextech", "hextech", "infernal", "hextech"]) == "3 hextech · infernal")
        #expect(Format.dragons(["cloud", "cloud"]) == "2 nuage")
        #expect(Format.role("jungle") == "Jungle")
        #expect(Format.role("bottom") == "ADC")
        #expect(Format.role("support") == "Supp.")
        #expect(Format.role("top") == "Top")
        #expect(Format.role("coach") == "Coa")
        #expect(Format.champion("XinZhao") == "Xin Zhao")
        #expect(Format.champion("KSante") == "K'Sante")
        #expect(Format.champion("Rell") == "Rell")
    }

    @Test func championNameExceptions() {
        let expected = [
            "LeBlanc": "LeBlanc", "MonkeyKing": "Wukong", "KSante": "K'Sante", "Chogath": "Cho'Gath",
            "Kaisa": "Kai'Sa", "Khazix": "Kha'Zix", "Velkoz": "Vel'Koz", "KogMaw": "Kog'Maw",
            "RekSai": "Rek'Sai", "Belveth": "Bel'Veth", "Nunu": "Nunu & Willump",
        ]
        for (id, name) in expected {
            #expect(Format.champion(id) == name, "\(id)")
        }
        // Les noms sans exception restent découpés à la casse.
        #expect(Format.champion("MissFortune") == "Miss Fortune")
        #expect(Format.champion("TwistedFate") == "Twisted Fate")
        #expect(Format.champion("Ahri") == "Ahri")
    }

    @Test func subtitles() {
        let event = makeEvent(id: "m", state: .unstarted, teams: [makeTeam("KC"), makeTeam("G2")])
        let cards = [
            TeamCard(team: FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp"), live: event, next: event, last: nil),
            TeamCard(team: FollowedTeam(id: "t1", code: "T1", name: "T1"), live: nil, next: event, last: nil),
            TeamCard(team: FollowedTeam(id: "gen", code: "GEN", name: "Gen.G"), live: nil, next: nil, last: event),
        ]
        #expect(Format.cardsSubtitle(cards, follows: FollowList(), revealed: []) == "1 en direct · 1 à venir")
        #expect(Format.followCount(0) == "aucune équipe suivie")
        #expect(Format.followCount(1) == "1 suivie")
        #expect(Format.followCount(3) == "3 suivies")
    }
}
