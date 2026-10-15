import Foundation
import Testing
@testable import LoLKit

/// Périmètre des données (spec périmètre §2, §2.3, §6.1 tests 1-12) sur les vraies listes de tournois du 15/10/2026.
@Suite struct SeasonWindowTests {
    private let window = SeasonWindow(today: "2026-10-15")!

    private func ref(_ id: String, _ start: String, _ end: String) -> TournamentRef {
        TournamentRef(id: id, slug: id, startDate: start, endDate: end, leagueId: "l")
    }

    /// Test 1.
    @Test func todayGivesTheCurrentAndPreviousSeasons() {
        #expect(window.currentSeason == 2026)
        #expect(window.previousSeason == 2025)
        #expect(window.startDay == "2025-01-01")
        #expect(window.startDate == date("2025-01-01T00:00:00Z"))
        #expect(SeasonWindow(today: "pas une date") == nil)
    }

    /// Test 2 : Mondial — 2026 (en cours) puis 2025 ; les 9 autres dehors.
    @Test func worldsKeepsTwoTournaments() throws {
        let all = try PerimetreFixture.tournaments("worlds")
        #expect(all.count == 11)
        #expect(window.tournaments(all).map(\.id) == ["115660540725177488", "113475452383887518"])
        let bySlug = Dictionary(uniqueKeysWithValues: all.map { ($0.slug, $0) })
        #expect(window.placement(of: try #require(bySlug["worlds_2026"])) == .current)
        #expect(window.placement(of: try #require(bySlug["worlds_2025"])) == .previous)
        #expect(window.placement(of: try #require(bySlug["worlds_2024"])) == .outside)
        #expect(all.filter { window.placement(of: $0) == .outside }.count == 9)
    }

    /// Test 3 : LEC — 6 dans la fenêtre, du plus récent au plus ancien ; 28 dehors dont la date de fin aberrante.
    @Test func lecKeepsSixTournaments() throws {
        let all = try PerimetreFixture.tournaments("lec")
        #expect(window.tournaments(all).map(\.id) == [
            "115548681802226458", "115548668058343983", "115548424304940735",
            "113487526512660769", "113487400974323999", "113475994398658012",
        ])
        #expect(all.filter { window.placement(of: $0) == .outside }.count == 28)
        let aberrant = try #require(all.first { $0.slug == "eu_lcs_summer_2013" })
        #expect(aberrant.endDate == "2022-08-26")
        #expect(window.placement(of: aberrant) == .outside)
    }

    /// Test 4 : LCK — 6 dedans, 31 dehors ; un tournoi à cheval sur le Nouvel An compte dans l'année de son début.
    @Test func lckKeepsSixAndStraddlingCountsByStart() throws {
        let all = try PerimetreFixture.tournaments("lck")
        #expect(window.tournaments(all).count == 6)
        #expect(all.filter { window.placement(of: $0) == .outside }.count == 31)
        let winter = try #require(all.first { $0.slug == "champions_winter_2014" })
        #expect(SeasonWindow.season(of: winter) == 2013)
        #expect(window.placement(of: winter) == .outside)
    }

    /// Test 5 : EMEA Masters — 7 dedans ; l'été 2026 en cours.
    @Test func emeaMastersSummerIsLive() throws {
        let all = try PerimetreFixture.tournaments("emea_masters")
        #expect(window.tournaments(all).count == 7)
        let summer = try #require(all.first { $0.slug == "emea_masters_summer_2026" })
        #expect(window.placement(of: summer) == .current)
        #expect(summer.isActive(today: "2026-10-15"))
    }

    /// Test 6 : Demacia Cup (2026 seule dans l'API), MSI et First Stand (2 chacun).
    @Test func internationalsInTheWindow() throws {
        let demacia = try PerimetreFixture.tournaments("demacia_cup")
        #expect(demacia.count == 1)
        #expect(window.placement(of: demacia[0]) == .current)
        #expect(demacia[0].isActive(today: window.today))
        #expect(window.tournaments(try PerimetreFixture.tournaments("msi")).count == 2)
        #expect(window.tournaments(try PerimetreFixture.tournaments("first_stand")).count == 2)
    }

    /// Test 7 : le 05/01/2027, la fenêtre glisse d'un an.
    @Test func theWindowMovesOnNewYear() throws {
        let next = try #require(SeasonWindow(today: "2027-01-05"))
        let bySlug = try PerimetreFixture.tournamentsBySlug()
        #expect(next.placement(of: try #require(bySlug["worlds_2025"])) == .outside)
        #expect(next.placement(of: try #require(bySlug["worlds_2026"])) == .previous)
        #expect(next.placement(of: try #require(bySlug["lec_split_1_2026"])) == .previous)
        #expect(next.startDay == "2026-01-01")
    }

    /// Test 8 : cas synthétiques du tableau §2.3.
    @Test func edgeCases() throws {
        // Pas de début : année de la fin.
        #expect(window.placement(of: ref("sans-debut", "", "2026-11-01")) == .current)
        #expect(window.placement(of: ref("sans-debut-vieux", "", "2024-05-01")) == .outside)
        // Ni début ni fin.
        #expect(window.placement(of: ref("vide", "", "")) == .outside)
        #expect(SeasonWindow.season(of: ref("vide", "", "")) == nil)
        // À cheval : saison de l'année du début.
        let straddling = ref("cheval", "2026-12-20", "2027-01-10")
        let january = try #require(SeasonWindow(today: "2027-01-05"))
        #expect(january.placement(of: straddling) == .previous)
        #expect(straddling.isActive(today: "2027-01-05"))
        #expect(try #require(SeasonWindow(today: "2028-01-02")).placement(of: straddling) == .outside)
        // Plus ancien mais en cours, commencé il y a ≤ 400 jours.
        let override = ref("vieux-en-cours", "2024-12-28", "2026-01-05")
        let jan3 = try #require(SeasonWindow(today: "2026-01-03"))
        #expect(jan3.placement(of: override) == .liveOverride)
        #expect(jan3.contains(override))
        #expect(jan3.scopeSeason(of: override) == 2026)
        // Garde-fou : la date de fin aberrante de `eu_lcs_summer_2013` portée au 31/12/2026 est active… et dehors.
        let aberrant = ref("109349946712116171", "2013-06-14", "2026-12-31")
        #expect(aberrant.isActive(today: "2026-10-15"))
        #expect(window.placement(of: aberrant) == .outside)
        #expect(window.scopeSeason(of: aberrant) == nil)
        // Saison future annoncée.
        let december = try #require(SeasonWindow(today: "2026-12-20"))
        #expect(december.placement(of: ref("lec_split_1_2027", "2027-01-16", "2027-03-01")) == .upcoming)
        // Bascule d'année : jour UTC.
        #expect(SeasonWindow(now: date("2026-12-31T23:30:00Z")).currentSeason == 2026)
        let newYear = SeasonWindow(now: date("2027-01-01T00:00:00Z"))
        #expect(newYear.currentSeason == 2027)
        #expect(newYear.startDay == "2026-01-01")
        #expect(newYear.today == "2027-01-01")
        // Dates de game : ≥ 1er janvier de N − 1 (UTC).
        #expect(!window.contains(date: date("2024-12-31T23:59:59Z")))
        #expect(window.contains(date: date("2025-01-01T00:00:00Z")))
    }

    /// Test 9 : saison de référence.
    @Test func referenceSeason() {
        #expect(window.referenceSeason(seasonsWithData: [2026, 2025]) == 2026)
        #expect(window.referenceSeason(seasonsWithData: [2025]) == 2025)
        #expect(window.referenceSeason(seasonsWithData: []) == 2026)
    }

    /// Test 10 : pilules de KC — « 2026 », ses 4 tournois de 2026, « 2025 », ses 4 tournois de 2025 ; avec le Mondial
    /// 2026 joué, 11 pilules et le Mondial en 2e position, en cours.
    @Test func scopesOfKarmineCorp() throws {
        let bySlug = try PerimetreFixture.tournamentsBySlug()
        let byId = Dictionary(uniqueKeysWithValues: bySlug.values.map { ($0.id, $0) })
        let kcTournaments = Set(try PerimetreFixture.kcG2Matches().filter { $0.involves("KC") }.map(\.tournamentId))
        let played = kcTournaments.compactMap { byId[$0] }
        let scopes = window.scopes(played: played)
        #expect(scopes.map(\.label) == [
            "2026", "lec_split_3_2026", "msi_2026", "lec_split_2_2026", "lec_split_1_2026",
            "2025", "lec_summer_2025", "lec_spring_2025", "first_stand_2025", "lec_winter_2025",
        ])
        #expect(scopes.map(\.season) == [2026, 2026, 2026, 2026, 2026, 2025, 2025, 2025, 2025, 2025])
        #expect(!scopes.contains { $0.isLive })
        #expect(scopes[0].tournamentIds.count == 4)
        #expect(scopes[5].tournamentIds.count == 4)
        let withWorlds = window.scopes(played: played + [try #require(bySlug["worlds_2026"])])
        #expect(withWorlds.count == 11)
        #expect(withWorlds[1].label == "worlds_2026")
        #expect(withWorlds[1].isLive)
        #expect(withWorlds[0].tournamentIds.count == 5)
    }

    /// Test 11 : games hors périmètre — par tournoi connu, sinon par date de début.
    @Test func outsideGames() throws {
        let base = try SeasonFixture.summary304(enriched: false)
        func copy(_ id: String, tournamentId: String, startedAt: Date? = nil) -> GameSummary {
            GameSummary(gameId: id, matchId: base.matchId, tournamentId: tournamentId, leagueSlug: base.leagueSlug,
                        number: base.number, patch: base.patch, startedAt: startedAt ?? base.startedAt,
                        endedAt: base.endedAt, durationSeconds: base.durationSeconds, result: base.result,
                        blue: base.blue, red: base.red, enriched: base.enriched)
        }
        let bySlug = try PerimetreFixture.tournamentsBySlug()
        let known = Dictionary(uniqueKeysWithValues: bySlug.values.map { ($0.id, $0) })
        let games = [
            base,
            copy("copie-2024", tournamentId: PerimetreFixture.worlds2024),
            copy("inconnu-2024", tournamentId: "inconnu", startedAt: date("2024-11-02T14:35:43.676Z")),
            copy("inconnu-2025", tournamentId: "inconnu", startedAt: date("2025-01-18T17:09:12.350Z")),
        ]
        #expect(base.gameId == "115548681803406304")
        #expect(window.outsideGameIds(games, tournaments: known) == ["copie-2024", "inconnu-2024"])
    }

    /// Test 12 : fichiers de tournoi hors périmètre — connu → par saison ; inconnu → par son dernier match ; sans date →
    /// gardé.
    @Test func outsideTournaments() throws {
        let bySlug = try PerimetreFixture.tournamentsBySlug()
        let known = Dictionary(uniqueKeysWithValues: bySlug.values.map { ($0.id, $0) })
        let ids: Set<String> = [PerimetreFixture.worlds2024, PerimetreFixture.worlds2025, "inconnu-ancien", "inconnu-sans-date"]
        let outside = window.outsideTournamentIds(ids, tournaments: known,
                                                  lastMatchStart: ["inconnu-ancien": date("2024-11-02T14:00:00Z")])
        #expect(outside == [PerimetreFixture.worlds2024, "inconnu-ancien"])
    }

    /// Premier mois du calendrier : 1er janvier de N − 1 dans le fuseau du calendrier.
    @Test func firstMonthFollowsTheCalendarTimeZone() {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        #expect(window.firstMonth(calendar: paris) == date("2024-12-31T23:00:00Z"))
    }
}
