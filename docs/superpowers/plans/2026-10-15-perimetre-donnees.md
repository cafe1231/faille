# Périmètre des données (SeasonWindow) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Borner toutes les données de saison de Faille à la saison en cours N, la saison précédente N − 1 et aux tournois en cours (règle pure `SeasonWindow`), à l'énumération, dans la collecte, sur le disque et à l'écran, sans nouvelle fonctionnalité.

**Architecture:** Une règle pure dans LoLKit (`SeasonWindow`, `SeasonScope.season/isLive`) et une collecte étendue (`CrawlWanted` + groupes 5-8 + budget disque 4 000) ; dans l'appli, `SeasonStore` devient le point d'étranglement (rien hors fenêtre n'y entre ni n'en sort), `SeasonDisk.load(window:)` purge le dossier `season/` à chaque lancement et `SeasonPurge` purge les caches du Détail une fois par fenêtre (marqueur `season/window.json`) ; les écrans ne font que choisir la saison affichée (saison de référence, pilules « Saison N … Saison N − 1 », face-à-face sur la fenêtre, calendrier borné).

**Tech Stack:** Swift 6.2 (LoLKit, concurrence stricte), Swift Testing, SwiftUI iOS 26, XcodeGen (`project.yml`), Docker `swift:6.2` pour LoLKit (`bash scripts/lolkit.sh test`), GitHub Actions pour l'iOS (compilation et tests hébergés uniquement en CI), `scripts/strings-check.py`.

**Spec:** `docs/superpowers/specs/2026-10-15-perimetre-donnees-design.md` (contraignant ; rulings, tableau §2.3, tests d'acceptation §6, découpage §7). Le plan reprend son découpage W1, W2, A1, A2, A3, I sous les noms D1 à D6.

## Global Constraints

- **Gel des fonctionnalités** (lot qualité depuis le 15/10/2026) : aucune nouvelle fonctionnalité, aucun nouvel écran ; on borne les données de ce qui existe. `League.internationalSlugs` inchangé ; widgets, Live Activity, notifications, lien profond inchangés.
- **Anti-spoiler contraignant** (spec 2026-10-13 §8, inchangé) : tout agrégat reçoit `masked` ; la collecte ne crée jamais de job pour un match masqué ; un filtre par saison s'applique **en même temps** aux matchs et aux games d'un même calcul (sinon une game échapperait à son masque).
- **Jamais de chiffre inventé** à l'écran : une valeur inconnue s'affiche `SeasonFormat.missing` ; les aperçus (`SeasonSamples`) sont des fixtures, signalées comme telles.
- **Réseau** : au plus 1 requête / 2 s (`CrawlPacer.baseInterval`), 300 par session (`CrawlPacer.sessionRequestBudget`) + réserve à la demande ; **aucune requête vers Leaguepedia** ajoutée ; **aucune requête `getCompletedEvents` / `getStandings` pour un tournoi `.outside`**.
- **Années jamais en dur** dans `App/` ni `LoLKit/Sources/` (hors commentaires, fixtures et `App/Season/SeasonSamples.swift`, qui est une fixture d'aperçu) : toutes viennent de `SeasonWindow`. Les années s'interpolent comme `String` (`String(window.currentSeason)`) : un `Int` interpolé dans `String(localized:)` serait formaté « 2 025 ».
- **Chaînes** : toute chaîne affichée passe par `String(localized:)` (fr = clé) et a son entrée fr + en dans `Resources/Localizable.xcstrings` ; `python3 scripts/strings-check.py` vert à la fin (D6 seul édite le catalogue ; D4/D5 tolèrent leurs clés manquantes en attendant).
- **Swift 6 concurrence stricte** : types nouveaux `Sendable` ; `SeasonStore` reste `@MainActor` ; la lecture disque reste hors du fil principal (`Task.detached`).
- **Ne rien casser** : Détail, widgets, Live Activity, notifications, anti-spoiler ; les tests existants restent verts. Seules exceptions, imposées par la spec et listées dans leur tâche : `CrawlPlannerTests.diskBudgetKeepsFollowedTeams` (`diskLimit` 2 000 → 4 000, nouvelle signature), `CrawlPlannerTests` (construction de `CrawlWanted`), `SeasonStatsTests.scopes` (champ `season` rempli), `SeasonStoreTests.planningHelpers` (la saison N − 1 est désormais énumérée), `TeamPageTests.scopesAndStandingOfKarmineCorp` (pilule « Mondial · en cours »).
- **Fichiers** : dans une même vague, deux tâches ne touchent jamais le même fichier (liste « OWNERSHIP » de chaque tâche). Un lot parallèle de finitions visuelles touchera `App/**` plus tard : chaque tâche liste les fichiers de vue qu'elle modifie, et ses modifications de vue restent minimales.
- **Vérifications** : LoLKit `bash scripts/lolkit.sh test` (Docker) à chaque tâche LoLKit ; l'appli ne compile qu'en CI : les tâches App vérifient localement `git diff --check` et `python3 scripts/strings-check.py`, la CI iOS tourne **une fois à la fin** (après D6), comme le veut l'orchestration.
- **Commits** : un commit par tâche (ou par étape « Commit »), message en français, terminé par la ligne `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` passée en second `-m`.

---

## Carte des fichiers et vagues

| Tâche | Vague | Crée | Modifie |
|---|---|---|---|
| **D1** SeasonWindow + périmètres | 1 | `LoLKit/Sources/LoLKit/Season/SeasonWindow.swift`, `LoLKit/Tests/LoLKitTests/SeasonWindowTests.swift`, `LoLKit/Tests/LoLKitTests/Support/PerimetreFixture.swift` | `LoLKit/Sources/LoLKit/Season/SeasonScope.swift`, `LoLKit/Tests/LoLKitTests/SeasonStatsTests.swift`, `LoLKit/Tests/LoLKitTests/PublicInitTests.swift` |
| **D2** Collecte et budget disque | 2 | — | `LoLKit/Sources/LoLKit/Season/CrawlPlanner.swift`, `LoLKit/Tests/LoLKitTests/CrawlPlannerTests.swift`, `LoLKit/Tests/LoLKitTests/PublicInitTests.swift` |
| **D3** Store, énumération, purge | 3 | `App/Season/SeasonPurge.swift`, `Tests/FailleTests/SeasonPerimetreTests.swift` | `App/Season/SeasonStore.swift`, `App/Season/SeasonDisk.swift`, `App/Season/SeasonPlanning.swift`, `App/Season/SeasonCrawler.swift`, `project.yml`, `Tests/FailleTests/SeasonStoreTests.swift` |
| **D4** Pages équipe, joueur, duels | 4 | `Tests/FailleTests/PerimetreScreensTests.swift`, `Tests/FailleTests/PerimetreSnapshotTests.swift` | `App/Season/SeasonLabels.swift`, `App/Season/SeasonSamples.swift`, `Shared/Preview/SampleData.swift`, `App/Store/AppStore+Season.swift`, **vues** `App/TeamPage/TeamPageView.swift`, `App/TeamPage/TeamPageSections.swift`, `App/PlayerPage/PlayerPageView.swift`, `App/Duel/DuelSection.swift`, `App/Duel/DuelView.swift`, `App/Duel/DuelBars.swift`, `Tests/FailleTests/TeamPageTests.swift` |
| **D5** Accueil, calendrier, classements, À propos | 4 | `App/Season/WindowTexts.swift`, `Tests/FailleTests/PerimetreCalendarTests.swift` | `App/Home/HomeStore.swift`, `App/Calendar/CalendarModel.swift`, **vues** `App/Home/HotPlayersSection.swift`, `App/Calendar/SeasonCalendarView.swift`, `App/Standings/StandingsView.swift`, `App/Settings/SettingsView.swift` |
| **D6** Chaînes et intégration | 5 | — | `Resources/Localizable.xcstrings`, `docs/superpowers/notes/2026-10-14-checklist-iphone.md` |

**Vagues** (une vague = tâches parallèles dans des worktrees séparés, fichiers disjoints) :

1. **D1** (LoLKit, base de tout).
2. **D2** (LoLKit ; utilise `SeasonWindow` et `PerimetreFixture` de D1, et modifie `PublicInitTests.swift` après D1).
3. **D3** (appli, cœur : consomme D1 et D2).
4. **D4 ‖ D5** (fichiers disjoints ; chacun ses libellés : D4 dans `SeasonLabels.swift`, D5 dans le nouveau `WindowTexts.swift`).
5. **D6**, puis CI complète (LoLKit, iOS, chaînes), relecture ciblée « rien d'avant 2025 ».

Fixtures réelles (déjà commitées avec ce plan) : `LoLKit/Tests/LoLKitTests/Fixtures/season/perimetre/` — `getTournamentsForLeague_{worlds,msi,first_stand,demacia_cup,lec,lck,emea_masters}.json`, `completed_kc_g2_2024_2026_reduced.json` (par tournoi : `matchCount`, `playedGames`, et `kcG2Matches` = matchs de KC et G2 avec `playedGameIds`, codes d'équipe sans id), `getStandings_demacia_cup_2026.json`. Le dossier est copié dans le paquet LoLKit (`resources: [.copy("Fixtures")]`) ; D3 l'ajoute aussi au paquet de tests hébergés.

Vues touchées (pour séquencer le lot de finitions visuelles) : D4 → `TeamPageView.swift`, `TeamPageSections.swift`, `PlayerPageView.swift`, `DuelSection.swift`, `DuelView.swift`, `DuelBars.swift` ; D5 → `HotPlayersSection.swift`, `SeasonCalendarView.swift`, `StandingsView.swift`, `SettingsView.swift`. D3 ne touche aucune vue.

---

### Task D1: SeasonWindow et périmètres de saison (LoLKit)

Spec §2, §2.3, §6.1 tests 1-14 et 17 (part `SeasonWindow`, `SeasonScope`). Modèle suggéré : standard.

**Files:**
- Create: `LoLKit/Sources/LoLKit/Season/SeasonWindow.swift`
- Create: `LoLKit/Tests/LoLKitTests/Support/PerimetreFixture.swift`
- Create: `LoLKit/Tests/LoLKitTests/SeasonWindowTests.swift`
- Modify: `LoLKit/Sources/LoLKit/Season/SeasonScope.swift` (champs `season`, `isLive`)
- Modify: `LoLKit/Tests/LoLKitTests/SeasonStatsTests.swift` (test `scopes` existant lignes ~205-215 ; tests 13-14 ajoutés)
- Modify: `LoLKit/Tests/LoLKitTests/PublicInitTests.swift` (test `perimeterTypes` ajouté)

**OWNERSHIP (vague 1)** : seule tâche de la vague. Ne touche ni `CrawlPlanner.swift` ni `CrawlPlannerTests.swift` (D2), ni rien sous `App/`.

**Interfaces:**
- Consumes (existant) : `TournamentRef` (`id`, `slug`, `startDate`, `endDate`, `leagueId`, `isActive(today:)`, `static func day(_:) -> Date?` interne, `static func adding(days:to:) -> String?` interne), `GameSummary` (`gameId`, `tournamentId`, `startedAt`), `TournamentsResponse`, `StandingsResponse`, `SeasonMatch`, `MatchTeam`, `SeasonStats.team`, `SeasonStats.headToHead`, `JSONDecoder.lolesports()`, `Fixture.Missing`, `date(_:)` (tests).
- Produces :

```swift
public struct SeasonWindow: Sendable, Hashable {
    public let today: String
    public let currentSeason: Int
    public let startDate: Date
    public var previousSeason: Int { get }
    public var startDay: String { get }
    public init?(today: String)
    public init(now: Date)
    public static let completeLeagueSlugs: Set<String>            // ["worlds", "msi", "first_stand", "demacia_cup"]
    public static let predecessors: [String: [String]]             // ["lcs": ["lta_n", "lta_cross"], "cblol-brazil": ["lta_s", "lta_cross"]]
    public static let liveOverrideMaxAgeDays: Int                  // 400
    public enum Placement: Sendable, Equatable { case current, previous, upcoming, liveOverride, outside }
    public static func season(of tournament: TournamentRef) -> Int?
    public func placement(of tournament: TournamentRef) -> Placement
    public func contains(_ tournament: TournamentRef) -> Bool
    /// Saison à laquelle un tournoi du périmètre est rattaché (liveOverride → N) ; nil hors périmètre.
    public func scopeSeason(of tournament: TournamentRef) -> Int?
    public func tournaments(_ all: [TournamentRef]) -> [TournamentRef]
    public func contains(date: Date) -> Bool
    public func firstMonth(calendar: Calendar) -> Date
    public func referenceSeason(seasonsWithData: Set<Int>) -> Int
    public func scopes(played: [TournamentRef]) -> [SeasonScope]
    public func outsideGameIds(_ games: [GameSummary], tournaments: [String: TournamentRef]) -> [String]
    public func outsideTournamentIds(_ ids: Set<String>, tournaments: [String: TournamentRef],
                                     lastMatchStart: [String: Date]) -> Set<String>
}

public struct SeasonScope: Sendable, Hashable {
    public let tournamentIds: Set<String>
    public let label: String
    public let season: Int?
    public let isLive: Bool
    public init(tournamentIds: Set<String>, label: String, season: Int? = nil, isLive: Bool = false)
    public static func season(_ year: Int, tournaments: [TournamentRef]) -> SeasonScope   // season = year
    public static func tournament(_ tournament: TournamentRef) -> SeasonScope             // season = SeasonWindow.season(of:)
    public func contains(_ match: SeasonMatch) -> Bool
}

// Tests (Support) :
enum PerimetreFixture {
    static let worlds2026: String      // "115660540725177488"
    static let worlds2025: String      // "113475452383887518"
    static let worlds2024: String      // "112966669920590211"
    static let demaciaCup2026: String  // "117133773242499009"
    static func data(_ name: String) throws -> Data
    static func tournaments(_ leagueSlug: String) throws -> [TournamentRef]     // leagueId = slug de la ligue
    static func tournamentsBySlug() throws -> [String: TournamentRef]
    static func reduced() throws -> [String: ReducedTournament]
    static func kcG2Matches() throws -> [SeasonMatch]                          // MatchTeam.id = code
    static func standings(_ name: String) throws -> Standings
}
```

- [ ] **Step 1: Écrire le chargeur de fixtures** `LoLKit/Tests/LoLKitTests/Support/PerimetreFixture.swift`

```swift
import Foundation
@testable import LoLKit

/// Fixtures réelles du périmètre (`Fixtures/season/perimetre/`, capturées le 15/10/2026, spec périmètre §1).
enum PerimetreFixture {
    static let worlds2026 = "115660540725177488"
    static let worlds2025 = "113475452383887518"
    static let worlds2024 = "112966669920590211"
    static let demaciaCup2026 = "117133773242499009"
    /// Ligues capturées (`getTournamentsForLeague_<slug>.json`).
    static let leagueSlugs = ["worlds", "msi", "first_stand", "demacia_cup", "lec", "lck", "emea_masters"]

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures/season/perimetre") else {
            throw Fixture.Missing(name: "season/perimetre/\(name)")
        }
        return try Data(contentsOf: url)
    }

    /// Tournois d'une ligue, dans l'ordre de l'API (du plus récent au plus ancien) ; `leagueId` = le slug de la ligue.
    static func tournaments(_ leagueSlug: String) throws -> [TournamentRef] {
        let response = try JSONDecoder.lolesports()
            .decode(TournamentsResponse.self, from: data("getTournamentsForLeague_\(leagueSlug)"))
        return response.data.leagues.flatMap(\.tournaments.elements).map { tournament in
            var copy = tournament
            copy.leagueId = leagueSlug
            return copy
        }
    }

    /// Tous les tournois des 7 ligues capturées, par slug de tournoi.
    static func tournamentsBySlug() throws -> [String: TournamentRef] {
        var bySlug: [String: TournamentRef] = [:]
        for league in leagueSlugs {
            for tournament in try tournaments(league) { bySlug[tournament.slug] = tournament }
        }
        return bySlug
    }

    struct ReducedTeam: Decodable {
        let code: String
        let name: String
        let gameWins: Int
    }

    struct ReducedMatch: Decodable {
        let matchId: String
        let startTime: Date
        let blockName: String?
        let teams: [ReducedTeam]
        let playedGameIds: [String]
    }

    struct ReducedTournament: Decodable {
        let matchCount: Int
        let playedGames: Int
        /// Absent pour les tournois sans KC ni G2 mesurés en volume seulement.
        let kcG2Matches: [ReducedMatch]?
    }

    /// `completed_kc_g2_2024_2026_reduced.json`, par slug de tournoi.
    static func reduced() throws -> [String: ReducedTournament] {
        try JSONDecoder.lolesports()
            .decode([String: ReducedTournament].self, from: data("completed_kc_g2_2024_2026_reduced"))
    }

    /// Les matchs de KC et G2 (2025-2026, internationaux compris) en `SeasonMatch`, du plus récent au plus ancien ;
    /// `MatchTeam.id` = code (« KC », « G2 »…), `stageSlug` nil, Bo déduit du score.
    static func kcG2Matches() throws -> [SeasonMatch] {
        let bySlug = try tournamentsBySlug()
        return try reduced().flatMap { slug, tournament -> [SeasonMatch] in
            guard let ref = bySlug[slug] else { return [] }
            return (tournament.kcG2Matches ?? []).map { match in
                SeasonMatch(id: match.matchId, tournamentId: ref.id, leagueSlug: ref.leagueId, stageSlug: nil,
                            startTime: match.startTime, blockName: match.blockName,
                            bestOf: 2 * (match.teams.map(\.gameWins).max() ?? 1) - 1,
                            teams: match.teams.map { team in
                                MatchTeam(id: team.code, name: team.name, code: team.code, image: nil,
                                          result: MatchTeam.Result(outcome: nil, gameWins: team.gameWins))
                            },
                            playedGameIds: match.playedGameIds)
            }
        }.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
    }

    static func standings(_ name: String) throws -> Standings {
        try JSONDecoder.lolesports().decode(StandingsResponse.self, from: data(name)).data.standings.elements[0]
    }
}
```

- [ ] **Step 2: Écrire les tests qui échouent** `LoLKit/Tests/LoLKitTests/SeasonWindowTests.swift` (tests 1-12 de la spec)

```swift
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
```

- [ ] **Step 3: Lancer les tests, constater l'échec**

Run: `bash scripts/lolkit.sh test --filter SeasonWindowTests`
Expected: FAIL à la compilation : `cannot find 'SeasonWindow' in scope`.

- [ ] **Step 4: Implémenter** `LoLKit/Sources/LoLKit/Season/SeasonWindow.swift`

```swift
import Foundation

/// Périmètre des données (spec périmètre §2) : saison en cours N, saison précédente N − 1, tournois en cours. Pur.
/// Saison d'un tournoi = année civile de son début (à défaut, de sa fin). Rien d'avant N − 1 n'est énuméré, gardé ni
/// montré, sauf un tournoi encore en cours commencé il y a au plus 400 jours (`liveOverride`). La fenêtre est un
/// plafond, pas une cible : ce que la collecte lit vraiment reste piloté par `CrawlWanted`.
public struct SeasonWindow: Sendable, Hashable {
    /// Jour de référence « yyyy-MM-dd », en UTC (comme les dates des tournois).
    public let today: String
    public let currentSeason: Int
    /// 1er janvier de N − 1, 00:00 UTC : premier instant du périmètre (dates des games, du calendrier).
    public let startDate: Date

    public var previousSeason: Int { currentSeason - 1 }
    /// « 2025-01-01 ».
    public var startDay: String { String(format: "%04d-01-01", previousSeason) }

    /// Compétitions dont toutes les équipes sont collectées (spec §2.1).
    public static let completeLeagueSlugs: Set<String> = ["worlds", "msi", "first_stand", "demacia_cup"]
    /// Ligues renommées : la saison N − 1 d'une ligue passe par ses prédécesseurs (spec §2.1).
    public static let predecessors: [String: [String]] = ["lcs": ["lta_n", "lta_cross"],
                                                          "cblol-brazil": ["lta_s", "lta_cross"]]
    /// Garde-fou de l'exception « en cours » : commencé il y a au plus 400 jours.
    public static let liveOverrideMaxAgeDays = 400

    public enum Placement: Sendable, Equatable {
        /// Saison N.
        case current
        /// Saison N − 1.
        case previous
        /// Saison > N (annoncé ; rien à lire avant son début).
        case upcoming
        /// Plus ancien que N − 1 mais en cours (`isActive`), commencé il y a ≤ 400 jours.
        case liveOverride
        /// Tout le reste, dates illisibles comprises.
        case outside
    }

    /// nil si `today` n'est pas une date « yyyy-MM-dd » lisible.
    public init?(today: String) {
        guard let day = TournamentRef.day(today) else { return nil }
        self.init(day: day, today: today)
    }

    /// Jour UTC de `now`.
    public init(now: Date) {
        let parts = Self.utc.dateComponents([.year, .month, .day], from: now)
        self.init(day: now, today: String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1))
    }

    private init(day: Date, today: String) {
        let year = Self.utc.component(.year, from: day)
        self.today = today
        currentSeason = year
        startDate = Self.utc.date(from: DateComponents(year: year - 1, month: 1, day: 1)) ?? .distantPast
    }

    /// Saison d'un tournoi : année de `startDate`, sinon année de `endDate`, sinon nil.
    public static func season(of tournament: TournamentRef) -> Int? {
        if TournamentRef.day(tournament.startDate) != nil { return Int(tournament.startDate.prefix(4)) }
        if TournamentRef.day(tournament.endDate) != nil { return Int(tournament.endDate.prefix(4)) }
        return nil
    }

    public func placement(of tournament: TournamentRef) -> Placement {
        guard let season = Self.season(of: tournament) else { return .outside }
        if season == currentSeason { return .current }
        if season == previousSeason { return .previous }
        if season > currentSeason { return .upcoming }
        guard tournament.isActive(today: today),
              let start = TournamentRef.day(tournament.startDate),
              let floorDay = TournamentRef.adding(days: -Self.liveOverrideMaxAgeDays, to: today),
              let floor = TournamentRef.day(floorDay), start >= floor else { return .outside }
        return .liveOverride
    }

    public func contains(_ tournament: TournamentRef) -> Bool {
        placement(of: tournament) != .outside
    }

    /// Saison de rattachement (pilules, « saison de référence ») : N pour `current` et `liveOverride`, N − 1 pour
    /// `previous`, la saison du tournoi pour `upcoming` ; nil hors périmètre.
    public func scopeSeason(of tournament: TournamentRef) -> Int? {
        switch placement(of: tournament) {
        case .current, .liveOverride: currentSeason
        case .previous: previousSeason
        case .upcoming: Self.season(of: tournament)
        case .outside: nil
        }
    }

    /// Tournois du périmètre, sans doublon, du plus récent au plus ancien (`startDate`, puis id).
    public func tournaments(_ all: [TournamentRef]) -> [TournamentRef] {
        var seen = Set<String>()
        return all.filter { contains($0) && seen.insert($0.id).inserted }
            .sorted { ($0.startDate, $0.id) > ($1.startDate, $1.id) }
    }

    /// Une date (début de game, de match du calendrier) est-elle dans le périmètre ? ≥ `startDate`.
    public func contains(date: Date) -> Bool {
        date >= startDate
    }

    /// Premier mois montrable par le calendrier : 1er janvier de N − 1 dans le fuseau de `calendar`.
    public func firstMonth(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: previousSeason, month: 1, day: 1)) ?? startDate
    }

    /// Saison « de référence » d'un écran : N s'il y a des données en N, sinon N − 1 s'il y en a, sinon N.
    public func referenceSeason(seasonsWithData: Set<Int>) -> Int {
        if seasonsWithData.contains(currentSeason) { return currentSeason }
        if seasonsWithData.contains(previousSeason) { return previousSeason }
        return currentSeason
    }

    /// Pilules d'une équipe (spec §3.5) : « Saison N », ses tournois de N (dont `liveOverride`), « Saison N − 1 », ses
    /// tournois de N − 1 ; du plus récent au plus ancien dans chaque saison ; une saison sans tournoi joué n'a pas de
    /// pilule ; un tournoi annoncé (`upcoming`) n'a rien de joué, il n'en a pas. `isLive` : tournoi actif aujourd'hui.
    public func scopes(played: [TournamentRef]) -> [SeasonScope] {
        let inWindow = tournaments(played)
        var result: [SeasonScope] = []
        for season in [currentSeason, previousSeason] {
            let group = inWindow.filter { placement(of: $0) != .upcoming && scopeSeason(of: $0) == season }
            guard !group.isEmpty else { continue }
            result.append(SeasonScope(tournamentIds: Set(group.map(\.id)), label: String(season), season: season))
            result += group.map { tournament in
                SeasonScope(tournamentIds: [tournament.id], label: tournament.slug, season: season,
                            isLive: tournament.isActive(today: today))
            }
        }
        return result
    }

    /// Purge (§3.3) : ids des games hors périmètre, triés. Tournoi connu → `!contains` ; inconnu → `startedAt < startDate`.
    public func outsideGameIds(_ games: [GameSummary], tournaments: [String: TournamentRef]) -> [String] {
        games.filter { game in
            if let tournament = tournaments[game.tournamentId] { return !contains(tournament) }
            return !contains(date: game.startedAt)
        }.map(\.gameId).sorted()
    }

    /// Purge : ids de tournoi (fichiers `completed/`, `standings/`) hors périmètre. Connu → `!contains` ; inconnu → hors
    /// si son dernier match connu (`lastMatchStart`) est avant `startDate` ; inconnu sans date → gardé.
    public func outsideTournamentIds(_ ids: Set<String>, tournaments: [String: TournamentRef],
                                     lastMatchStart: [String: Date]) -> Set<String> {
        ids.filter { id in
            if let tournament = tournaments[id] { return !contains(tournament) }
            guard let last = lastMatchStart[id] else { return false }
            return !contains(date: last)
        }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
```

- [ ] **Step 5: Étendre `SeasonScope`** — remplacer le contenu de `LoLKit/Sources/LoLKit/Season/SeasonScope.swift` par :

```swift
import Foundation

/// Périmètre d'un calcul de saison (pilules « Saison 2026 », « LEC Split 3 »… de la page équipe, spec saison §3.1,
/// spec périmètre §2.2) : un ensemble de tournois. `label` est une valeur, pas un texte : l'année (« 2026 ») ou le slug
/// du tournoi. `season` : saison du périmètre ; `isLive` : tournoi en cours aujourd'hui (pilule « · en cours »).
public struct SeasonScope: Sendable, Hashable {
    public let tournamentIds: Set<String>
    public let label: String
    public let season: Int?
    public let isLive: Bool

    public init(tournamentIds: Set<String>, label: String, season: Int? = nil, isLive: Bool = false) {
        self.tournamentIds = tournamentIds
        self.label = label
        self.season = season
        self.isLive = isLive
    }

    /// Saison = année civile (§1.2) : les tournois commencés cette année-là.
    public static func season(_ year: Int, tournaments: [TournamentRef]) -> SeasonScope {
        SeasonScope(tournamentIds: Set(tournaments.filter { $0.year == year }.map(\.id)), label: String(year), season: year)
    }

    /// Un seul tournoi ; `label` = son slug, `season` = sa saison (`SeasonWindow.season(of:)`).
    public static func tournament(_ tournament: TournamentRef) -> SeasonScope {
        SeasonScope(tournamentIds: [tournament.id], label: tournament.slug, season: SeasonWindow.season(of: tournament))
    }

    public func contains(_ match: SeasonMatch) -> Bool {
        tournamentIds.contains(match.tournamentId)
    }
}
```

- [ ] **Step 6: Mettre à jour le test existant `SeasonStatsTests.scopes`** (le champ `season` est désormais rempli) :

```swift
        #expect(SeasonScope.season(2026, tournaments: tournaments)
                == SeasonScope(tournamentIds: ["s3", "s1"], label: "2026", season: 2026))
        #expect(SeasonScope.tournament(tournaments[0])
                == SeasonScope(tournamentIds: ["s3"], label: "lec_split_3_2026", season: 2026))
```

- [ ] **Step 7: Ajouter les tests 13-14** à la fin de `SeasonStatsTests` (avant l'accolade de fin de la suite) :

```swift
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
        #expect([current.winsA, current.winsB] == [2, 6])
        let previous = h2h(SeasonScope.season(2025, tournaments: tournaments).tournamentIds)
        #expect([previous.winsA, previous.winsB] == [3, 2])
        let all = h2h(Set(window.tournaments(tournaments).map(\.id)))
        #expect([all.winsA, all.winsB] == [5, 8])
        #expect(all.matchIds.count == 13)
        #expect(all.matchIds.first == "115548681803406303")
        #expect(matches.first { $0.id == all.matchIds.first }?.startTime == date("2026-09-06T15:00:00Z"))
    }
```

- [ ] **Step 8: Ajouter le test 17 (part D1)** dans `PublicInitTests` (sans `@testable`) :

```swift
    /// Spec périmètre §6.1 test 17 : fenêtre et périmètres construits depuis l'extérieur du module.
    @Test func perimeterTypes() throws {
        let window = try #require(SeasonWindow(today: "2026-10-15"))
        #expect(window.currentSeason == 2026 && window.startDay == "2025-01-01")
        let worlds = TournamentRef(id: "w", slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-11-15", leagueId: "l")
        #expect(window.placement(of: worlds) == .current)
        let scope = SeasonScope(tournamentIds: ["w"], label: "worlds_2026", season: 2026, isLive: true)
        #expect(scope.season == 2026 && scope.isLive)
        #expect(SeasonScope(tournamentIds: [], label: "2026").season == nil)
    }
```

- [ ] **Step 9: Lancer toute la suite LoLKit**

Run: `bash scripts/lolkit.sh test`
Expected: PASS (tous les tests, dont `SeasonWindowTests` 13 tests, `SeasonStatsTests` +2, `PublicInitTests.perimeterTypes`).

- [ ] **Step 10: Commit**

```bash
git add LoLKit/Sources/LoLKit/Season/SeasonWindow.swift LoLKit/Sources/LoLKit/Season/SeasonScope.swift \
        LoLKit/Tests/LoLKitTests/SeasonWindowTests.swift LoLKit/Tests/LoLKitTests/Support/PerimetreFixture.swift \
        LoLKit/Tests/LoLKitTests/SeasonStatsTests.swift LoLKit/Tests/LoLKitTests/PublicInitTests.swift
git commit -m "feat(lolkit): SeasonWindow — saison en cours, précédente et tournois en cours (périmètre des données)" \
           -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task D2: Collecte bornée et budget disque (LoLKit)

Spec §3.2, §6.1 tests 15-17 (part `CrawlWanted`). Modèle suggéré : standard.

**Files:**
- Modify: `LoLKit/Sources/LoLKit/Season/CrawlPlanner.swift` (`CrawlWanted` étendu, filtre `allowedTournamentIds`, groupes 5-8, `evictions`, `diskLimit = 4_000`)
- Modify: `LoLKit/Tests/LoLKitTests/CrawlPlannerTests.swift` (constructions de `CrawlWanted` lignes ~42 et ~83, test `diskBudgetKeepsFollowedTeams` ; 4 tests ajoutés)
- Modify: `LoLKit/Tests/LoLKitTests/PublicInitTests.swift` (test `crawlWantedWithPerimeter` ajouté)

**OWNERSHIP (vague 2)** : seule tâche de la vague. `PublicInitTests.swift` a été modifié par D1 (vague 1) : partir de `main` à jour. Ne touche ni `SeasonWindow.swift` ni `SeasonScope.swift` ni rien sous `App/`.

**Interfaces:**
- Consumes (D1) : `SeasonWindow(today:)`, `window.tournaments(_:)`, `PerimetreFixture.tournamentsBySlug()`, `PerimetreFixture.kcG2Matches()`, `PerimetreFixture.standings(_:)`, `PerimetreFixture.worlds2024`, `PerimetreFixture.demaciaCup2026`. Existant : `CrawlPlanner.currentStageMatchIds(_:)`, `SeasonMatch`, `GameSummary`.
- Produces :

```swift
public struct CrawlWanted: Sendable, Equatable {
    public let openedTeamId: String?
    public let followedTeamIds: [String]
    /// Remplace `worldsStageMatchIds` : étape en cours de CHAQUE tournoi complet en cours (groupe 2).
    public let liveCompleteStageMatchIds: Set<String>
    public let followedLeagueSlugs: [String]
    public let currentTournamentIds: Set<String>
    /// Tournois .current / .previous / .upcoming / .liveOverride énumérés : aucun job hors de cet ensemble.
    public let allowedTournamentIds: Set<String>
    /// Tournois .previous (groupes 6 et 8).
    public let previousSeasonTournamentIds: Set<String>
    /// Tournois des `SeasonWindow.completeLeagueSlugs` dans la fenêtre (groupes 5 et 7).
    public let completeTournamentIds: Set<String>
    public init(openedTeamId: String?, followedTeamIds: [String], liveCompleteStageMatchIds: Set<String>,
                followedLeagueSlugs: [String], currentTournamentIds: Set<String>, allowedTournamentIds: Set<String>,
                previousSeasonTournamentIds: Set<String> = [], completeTournamentIds: Set<String> = [])
}

extension CrawlPlanner {
    public static let diskLimit: Int   // 4_000
    public static func evictions(_ games: [GameSummary], followedTeamIds: Set<String>,
                                 allowedTournamentIds: Set<String>, previousSeasonTournamentIds: Set<String>,
                                 limit: Int = diskLimit) -> [String]
    // jobs(wanted:matches:have:failures:masked:now:) : signature inchangée.
}
```

- [ ] **Step 1: Adapter les tests existants à la nouvelle construction** dans `CrawlPlannerTests.swift` — le `wanted` de la suite (ligne ~42) devient :

```swift
    private var wanted: CrawlWanted {
        CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC"], liveCompleteStageMatchIds: ["t1-gen"],
                    followedLeagueSlugs: ["lck"], currentTournamentIds: [Self.lec3, Self.worlds, Self.lck3],
                    allowedTournamentIds: [Self.lec3, Self.lec1, Self.worlds, Self.lck3, Self.lck1])
    }
```

et `followFnc` (ligne ~83) :

```swift
        let followFnc = CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC", "FNC"], liveCompleteStageMatchIds: [],
                                    followedLeagueSlugs: ["lck"], currentTournamentIds: [Self.lec3, Self.worlds, Self.lck3],
                                    allowedTournamentIds: [Self.lec3, Self.lec1, Self.worlds, Self.lck3, Self.lck1])
```

(reprendre exactement les autres arguments de l'appel existant ; seuls le libellé `liveCompleteStageMatchIds:` et `allowedTournamentIds:` changent). Les attentes des tests existants (ordre des jobs, priorités 0-4) **ne changent pas**.

Le test `diskBudgetKeepsFollowedTeams` devient (même jeu de games, tournoi `"t"` autorisé) :

```swift
    /// Budget disque : 4 000 games ; au-delà, les plus anciennes sans équipe suivie, jamais une game d'équipe suivie.
    @Test func diskBudgetKeepsFollowedTeams() {
        func game(_ id: String, _ start: String, _ blue: String) -> GameSummary {
            let base = summary(id, blue, "X")
            return GameSummary(gameId: id, matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
                               startedAt: date(start), endedAt: date(start).addingTimeInterval(1800),
                               durationSeconds: 1800, result: .unknown, blue: base.blue, red: base.red, enriched: false)
        }
        let games = [game("old-kc", "2026-01-01T10:00:00Z", "KC"), game("old", "2026-01-02T10:00:00Z", "G2"),
                     game("mid", "2026-03-01T10:00:00Z", "T1"), game("new", "2026-09-01T10:00:00Z", "GEN")]
        #expect(CrawlPlanner.diskLimit == 4_000)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC"], allowedTournamentIds: ["t"],
                                       previousSeasonTournamentIds: [], limit: 2) == ["old", "mid"])
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC", "G2", "T1", "GEN"], allowedTournamentIds: ["t"],
                                       previousSeasonTournamentIds: [], limit: 2).isEmpty)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: [], allowedTournamentIds: ["t"],
                                       previousSeasonTournamentIds: [], limit: 4).isEmpty)
    }
```

- [ ] **Step 2: Écrire les tests qui échouent** (ajoutés à `CrawlPlannerTests`)

```swift
    /// Spec périmètre §6.1 test 15 : KC suivie, rien en cache, aucun masque — 221 jobs palier A : les 113 games de 2026
    /// (groupe 1) puis les 108 de 2025 (groupe 6) ; jamais un match de `worlds_2024`, même fourni.
    @Test func kcTwoSeasonsComeInPriorityOrder() throws {
        let window = try #require(SeasonWindow(today: "2026-10-15"))
        let bySlug = try PerimetreFixture.tournamentsBySlug()
        let allowed = Set(window.tournaments(Array(bySlug.values)).map(\.id))
        let previousKC = Set(["lec_winter_2025", "lec_spring_2025", "lec_summer_2025", "first_stand_2025"]
            .compactMap { bySlug[$0]?.id })
        #expect(previousKC.count == 4)
        let worlds24 = SeasonMatch(id: "kc-worlds24", tournamentId: PerimetreFixture.worlds2024, leagueSlug: "worlds",
                                   stageSlug: nil, startTime: date("2024-10-05T12:00:00Z"), blockName: nil, bestOf: 1,
                                   teams: [team("KC", wins: 1), team("T1", wins: 0)], playedGameIds: ["kc-worlds24-g1"])
        let matches = try PerimetreFixture.kcG2Matches() + [worlds24]
        func wanted(allowing ids: Set<String>) -> CrawlWanted {
            CrawlWanted(openedTeamId: nil, followedTeamIds: ["KC"], liveCompleteStageMatchIds: [], followedLeagueSlugs: [],
                        currentTournamentIds: [Self.lec3, Self.worlds], allowedTournamentIds: ids,
                        previousSeasonTournamentIds: previousKC)
        }
        let at = date("2026-10-15T12:00:00Z")
        let jobs = CrawlPlanner.jobs(wanted: wanted(allowing: allowed), matches: matches, have: [:], failures: [:],
                                     masked: [], now: at)
        #expect(jobs.count == 221)
        #expect(jobs.allSatisfy { $0.tier == .a })
        #expect(jobs.prefix(113).allSatisfy { $0.priority == 1 })
        #expect(jobs.suffix(108).allSatisfy { $0.priority == 6 })
        #expect(!jobs.contains { $0.tournamentId == PerimetreFixture.worlds2024 })
        // Le même match, autorisé, serait lu : c'est bien la fenêtre qui l'écarte.
        let unbounded = CrawlPlanner.jobs(wanted: wanted(allowing: allowed.union([PerimetreFixture.worlds2024])),
                                          matches: matches, have: [:], failures: [:], masked: [], now: at)
        #expect(unbounded.contains { $0.gameId == "kc-worlds24-g1" })
    }

    /// Spec périmètre §6.1 test 15 (suite) : Demacia Cup 2026 en cours, ligue complète non suivie — l'étape en cours
    /// (`playoffs`, 7 matchs dont 5 joués, 23 games) en groupe 2, les étapes déjà jouées (39 games) en groupe 5.
    @Test func liveCompleteTournamentStageComesFirst() throws {
        let standings = try PerimetreFixture.standings("getStandings_demacia_cup_2026")
        let stage = CrawlPlanner.currentStageMatchIds(standings)
        #expect(stage.count == 7)
        #expect(stage.contains("117133830110912093"))
        let played = standings.stages.flatMap { $0.sections.flatMap(\.matches) }.filter { $0.state == .completed }
        #expect(played.count == 25)
        let matches = played.map { match in
            let games = match.teams.reduce(0) { $0 + $1.gameWins }
            return SeasonMatch(id: match.id, tournamentId: PerimetreFixture.demaciaCup2026, leagueSlug: "demacia_cup",
                               stageSlug: nil, startTime: date("2026-10-10T10:00:00Z"), blockName: nil, bestOf: 5,
                               teams: match.teams, playedGameIds: (1...games).map { "\(match.id)-g\($0)" })
        }
        let wanted = CrawlWanted(openedTeamId: nil, followedTeamIds: [], liveCompleteStageMatchIds: stage,
                                 followedLeagueSlugs: [], currentTournamentIds: [PerimetreFixture.demaciaCup2026],
                                 allowedTournamentIds: [PerimetreFixture.demaciaCup2026],
                                 completeTournamentIds: [PerimetreFixture.demaciaCup2026])
        let jobs = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: [:], failures: [:], masked: [],
                                     now: date("2026-10-15T12:00:00Z"))
        #expect(jobs.count == 62)
        #expect(jobs.prefix(23).allSatisfy { $0.priority == 2 })
        #expect(jobs.suffix(39).allSatisfy { $0.priority == 5 })
    }

    /// Groupes 5-8 après les 0-4 : complet en cours, suivies N − 1, complets terminés, ligues suivies N − 1.
    @Test func historyGroupsComeAfterTheCurrentSeason() {
        let wanted = CrawlWanted(openedTeamId: nil, followedTeamIds: ["KC"], liveCompleteStageMatchIds: [],
                                 followedLeagueSlugs: ["lck"], currentTournamentIds: ["t-dc"],
                                 allowedTournamentIds: ["t25", "t-lck25", "t-msi25", "t-dc"],
                                 previousSeasonTournamentIds: ["t25", "t-lck25", "t-msi25"],
                                 completeTournamentIds: ["t-msi25", "t-dc"])
        let list = [
            match("fol-25", "t25", "lec", "2025-08-02T15:00:00Z", "KC", "FNC"),
            match("lg-25", "t-lck25", "lck", "2025-08-03T09:00:00Z", "HLE", "DK"),
            match("cmp-done", "t-msi25", "msi", "2025-07-01T09:00:00Z", "GEN", "BLG"),
            match("cmp-live", "t-dc", "demacia_cup", "2026-10-10T09:00:00Z", "BFX", "JDG"),
        ]
        let jobs = CrawlPlanner.jobs(wanted: wanted, matches: list, have: [:], failures: [:], masked: [], now: now)
        #expect(jobs.map(\.matchId) == ["cmp-live", "cmp-live", "fol-25", "fol-25", "cmp-done", "cmp-done", "lg-25", "lg-25"])
        #expect(jobs.map(\.priority) == [5, 5, 6, 6, 7, 7, 8, 8])
    }

    /// Spec périmètre §6.1 test 16 : hors fenêtre toujours supprimé (même d'une équipe suivie, même sous la limite) ;
    /// au-delà de la limite, la saison N − 1 des équipes non suivies d'abord (la plus ancienne d'abord), puis N.
    @Test func diskBudgetDropsOutsideGamesThenThePreviousSeason() {
        func game(_ id: String, _ tournament: String, _ start: String, _ blue: String) -> GameSummary {
            let base = summary(id, blue, "X")
            return GameSummary(gameId: id, matchId: "m", tournamentId: tournament, leagueSlug: "lec", number: 1,
                               patch: nil, startedAt: date(start), endedAt: date(start).addingTimeInterval(1800),
                               durationSeconds: 1800, result: .unknown, blue: base.blue, red: base.red, enriched: false)
        }
        let outside = [game("w24-1", "w24", "2024-10-01T10:00:00Z", "KC"), game("w24-2", "w24", "2024-10-01T11:00:00Z", "KC"),
                       game("w24-3", "w24", "2024-10-01T12:00:00Z", "KC")]
        let inside = [game("k26", "t26", "2026-05-01T10:00:00Z", "KC"), game("n26", "t26", "2026-01-10T10:00:00Z", "G2"),
                      game("n25a", "t25", "2025-08-01T10:00:00Z", "G2"), game("n25b", "t25", "2026-01-12T10:00:00Z", "T1")]
        func evict(_ games: [GameSummary], limit: Int) -> [String] {
            CrawlPlanner.evictions(games, followedTeamIds: ["KC"], allowedTournamentIds: ["t26", "t25"],
                                   previousSeasonTournamentIds: ["t25"], limit: limit)
        }
        #expect(evict(outside + inside, limit: 10) == ["w24-1", "w24-2", "w24-3"])
        #expect(evict(inside, limit: 3) == ["n25a"])
        // `n25b` (N − 1, 12/01/2026) part avant `n26` (N, 10/01/2026), bien que plus récente.
        #expect(evict(inside, limit: 2) == ["n25a", "n25b"])
        #expect(evict(inside, limit: 1) == ["n25a", "n25b", "n26"])
        // Une game d'équipe suivie dans la fenêtre n'est jamais supprimée.
        #expect(evict(inside, limit: 0) == ["n25a", "n25b", "n26"])
    }
```

Et dans `PublicInitTests` :

```swift
    /// Spec périmètre §6.1 test 17 : `CrawlWanted` étendu, construit depuis l'extérieur du module.
    @Test func crawlWantedWithPerimeter() {
        let wanted = CrawlWanted(openedTeamId: nil, followedTeamIds: ["kc"], liveCompleteStageMatchIds: ["m"],
                                 followedLeagueSlugs: [], currentTournamentIds: ["t26"],
                                 allowedTournamentIds: ["t26", "t25"], previousSeasonTournamentIds: ["t25"],
                                 completeTournamentIds: ["t26"])
        #expect(wanted.allowedTournamentIds == ["t26", "t25"])
        #expect(wanted.previousSeasonTournamentIds == ["t25"])
        #expect(wanted.completeTournamentIds == ["t26"])
        #expect(wanted.liveCompleteStageMatchIds == ["m"])
    }
```

- [ ] **Step 3: Lancer, constater l'échec**

Run: `bash scripts/lolkit.sh test --filter CrawlPlannerTests`
Expected: FAIL à la compilation (`extra argument 'liveCompleteStageMatchIds'`, `extra argument 'allowedTournamentIds'`).

- [ ] **Step 4: Implémenter `CrawlWanted`** (remplace la structure existante dans `CrawlPlanner.swift`) :

```swift
/// Ce que la collecte doit couvrir (spec saison §1.6, spec périmètre §3.2), rempli par l'appli.
public struct CrawlWanted: Sendable, Equatable {
    /// Équipe dont la page est ouverte (priorité 0 si elle n'est pas suivie : tournoi en cours seulement).
    public let openedTeamId: String?
    public let followedTeamIds: [String]
    /// Étape en cours de chaque tournoi complet en cours (Mondial, Demacia Cup… : `CrawlPlanner.currentStageMatchIds`).
    public let liveCompleteStageMatchIds: Set<String>
    public let followedLeagueSlugs: [String]
    /// Tournois en cours : celui de chaque ligue concernée et l'international en cours.
    public let currentTournamentIds: Set<String>
    /// Tournois du périmètre énumérés (`SeasonWindow`) : aucun job pour un match d'un autre tournoi.
    public let allowedTournamentIds: Set<String>
    /// Tournois de la saison N − 1.
    public let previousSeasonTournamentIds: Set<String>
    /// Tournois des compétitions complètes (`SeasonWindow.completeLeagueSlugs`) dans la fenêtre.
    public let completeTournamentIds: Set<String>

    public init(openedTeamId: String?, followedTeamIds: [String], liveCompleteStageMatchIds: Set<String>,
                followedLeagueSlugs: [String], currentTournamentIds: Set<String>, allowedTournamentIds: Set<String>,
                previousSeasonTournamentIds: Set<String> = [], completeTournamentIds: Set<String> = []) {
        self.openedTeamId = openedTeamId
        self.followedTeamIds = followedTeamIds
        self.liveCompleteStageMatchIds = liveCompleteStageMatchIds
        self.followedLeagueSlugs = followedLeagueSlugs
        self.currentTournamentIds = currentTournamentIds
        self.allowedTournamentIds = allowedTournamentIds
        self.previousSeasonTournamentIds = previousSeasonTournamentIds
        self.completeTournamentIds = completeTournamentIds
    }
}
```

- [ ] **Step 5: Implémenter le filtre et les groupes dans `CrawlPlanner.jobs`** — la boucle devient (doc comment mise à jour : « 0 page ouverte ; 1 suivies N ; 2 étape en cours des complets en cours ; 3 ligues suivies N ; 4 palier B ; 5 reste des complets en cours ; 6 suivies N − 1 ; 7 complets terminés ; 8 ligues suivies N − 1. Jamais de job hors `allowedTournamentIds` ») :

```swift
        for match in matches where wanted.allowedTournamentIds.contains(match.tournamentId)
            && !masked.contains(match.id) && match.startTime <= now {
            let current = wanted.currentTournamentIds.contains(match.tournamentId)
            let previous = wanted.previousSeasonTournamentIds.contains(match.tournamentId)
            let teamIds = Set(match.teams.compactMap(\.id))
            var groups: [Int] = []
            if let opened = wanted.openedTeamId, !followed.contains(opened), teamIds.contains(opened), current {
                groups.append(0)
            }
            let involvesFollowed = !teamIds.isDisjoint(with: followed)
            if involvesFollowed { groups.append(previous ? 6 : 1) }
            if wanted.liveCompleteStageMatchIds.contains(match.id) { groups.append(2) }
            if leagues.contains(match.leagueSlug) { groups.append(previous ? 8 : 3) }
            if wanted.completeTournamentIds.contains(match.tournamentId) { groups.append(current ? 5 : 7) }
            // … le reste de la boucle (jobs palier A / B, `best`) est inchangé.
```

Le tri final est inchangé (priorité, tournoi en cours d'abord, match le plus récent, id de match, n° de game).

- [ ] **Step 6: Implémenter le budget disque** (remplace `diskLimit` et `evictions`) :

```swift
    /// Budget disque (spec périmètre §3.2, remplace §1.7 de la spec saison) : (1) toujours les games hors fenêtre (tournoi
    /// absent de `allowedTournamentIds`), quelles que soient les équipes ; (2) au-delà de `limit` games dans la fenêtre,
    /// la saison N − 1 des équipes non suivies, la plus ancienne d'abord ; (3) puis la saison N des équipes non suivies.
    /// Une game d'équipe suivie dans la fenêtre n'est jamais supprimée (le cache peut alors dépasser la limite).
    public static let diskLimit = 4_000

    public static func evictions(_ games: [GameSummary], followedTeamIds: Set<String>,
                                 allowedTournamentIds: Set<String>, previousSeasonTournamentIds: Set<String>,
                                 limit: Int = diskLimit) -> [String] {
        let oldestFirst: (GameSummary, GameSummary) -> Bool = { ($0.startedAt, $0.gameId) < ($1.startedAt, $1.gameId) }
        let outside = games.filter { !allowedTournamentIds.contains($0.tournamentId) }.sorted(by: oldestFirst)
        let inside = games.filter { allowedTournamentIds.contains($0.tournamentId) }
        guard inside.count > limit else { return outside.map(\.gameId) }
        let removable = inside.filter {
            !followedTeamIds.contains($0.blue.teamId) && !followedTeamIds.contains($0.red.teamId)
        }
        let previous = removable.filter { previousSeasonTournamentIds.contains($0.tournamentId) }.sorted(by: oldestFirst)
        let current = removable.filter { !previousSeasonTournamentIds.contains($0.tournamentId) }.sorted(by: oldestFirst)
        return outside.map(\.gameId) + (previous + current).prefix(inside.count - limit).map(\.gameId)
    }
```

- [ ] **Step 7: Lancer toute la suite LoLKit**

Run: `bash scripts/lolkit.sh test`
Expected: PASS (dont `jobsFollowThePriorityOrder` et `revealingOrFollowingChangesThePlan` inchangés, les 4 nouveaux tests, `PublicInitTests.crawlWantedWithPerimeter`).

- [ ] **Step 8: Commit**

```bash
git add LoLKit/Sources/LoLKit/Season/CrawlPlanner.swift LoLKit/Tests/LoLKitTests/CrawlPlannerTests.swift \
        LoLKit/Tests/LoLKitTests/PublicInitTests.swift
git commit -m "feat(lolkit): collecte bornée à la fenêtre — groupes 5-8, compétitions complètes, budget disque 4 000" \
           -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task D3: SeasonStore point d'étranglement, énumération et purge (appli)

Spec §3.1, §3.3, §3.4, §6.2 tests 18-20. Modèle suggéré : most capable (concurrence, disque, anti-régression de la collecte).

**Files:**
- Create: `App/Season/SeasonPurge.swift`
- Create: `Tests/FailleTests/SeasonPerimetreTests.swift`
- Modify: `App/Season/SeasonPlanning.swift` (`SeasonContext.window`, `leagueIds`, `predecessorLeagueIds`, `startedTournaments`, `wanted`)
- Modify: `App/Season/SeasonCrawler.swift` (appel de `startedTournaments`, ligne ~59)
- Modify: `App/Season/SeasonDisk.swift` (`load(window:)`, purge, `Snapshot` étendu)
- Modify: `App/Season/SeasonStore.swift` (fenêtre, filtres, lectures par saison)
- Modify: `project.yml` (fixtures du périmètre dans le paquet `FailleTests`)
- Modify: `Tests/FailleTests/SeasonStoreTests.swift` (une attente de `planningHelpers`, ligne ~470)

**OWNERSHIP (vague 3)** : seule tâche de la vague. **Aucune vue** n'est touchée. Ne touche pas `App/Store/AppStore+Season.swift` (D4), `SeasonLabels.swift` (D4), `SeasonSamples.swift` (D4).

**Interfaces:**
- Consumes (D1, D2) : `SeasonWindow` (toutes ses méthodes), `SeasonScope(tournamentIds:label:season:isLive:)`, `CrawlWanted(openedTeamId:followedTeamIds:liveCompleteStageMatchIds:followedLeagueSlugs:currentTournamentIds:allowedTournamentIds:previousSeasonTournamentIds:completeTournamentIds:)`, `CrawlPlanner.evictions(_:followedTeamIds:allowedTournamentIds:previousSeasonTournamentIds:limit:)`, `CrawlPlanner.currentStageMatchIds(_:)`.
- Produces (utilisés par D4 et D5) :

```swift
extension SeasonContext {
    var window: SeasonWindow { get }                                    // SeasonWindow(now: now)
}
enum SeasonPlanning {
    static func leagueIds(_ context: SeasonContext) -> [String]        // + complètes + prédécesseurs
    static func predecessorLeagueIds(_ context: SeasonContext) -> Set<String>
    static func startedTournaments(_ byLeague: [String: [TournamentRef]], leagueIds: [String],
                                   predecessorLeagueIds: Set<String> = [], now: Date) -> [TournamentRef]
    static func wanted(_ context: SeasonContext, byLeague: [String: [TournamentRef]],
                       standings: [String: Standings]) -> CrawlWanted
}
struct SeasonDisk {
    struct Snapshot { /* champs existants */ var outsideTournamentIds: Set<String>; var detailFilesRead: Int }
    func load(window: SeasonWindow) -> Snapshot
}
struct SeasonPurge: Sendable {
    static let markerPath: String                                      // "season/window.json"
    struct Marker: Codable, Equatable, Sendable { let v: Int; let startDay: String }
    let cache: DiskCache
    func run(window: SeasonWindow) -> Int                              // fichiers du Détail lus (0 si marqueur à jour)
}
@MainActor final class SeasonStore {
    private(set) var window: SeasonWindow                              // @ObservationIgnored
    func isOutsideWindow(tournamentId: String) -> Bool
    func season(ofTournament id: String) -> Int?                       // window.scopeSeason(of:) ?? SeasonWindow.season(of:)
    func scopes(forTeam teamId: String, now: Date) -> [SeasonScope]    // SeasonWindow(now:).scopes(played:)
    func referenceSeason(forTeams ids: [String], now: Date) -> Int     // ids vides = toutes les équipes
    func games(inSeason season: Int) -> [GameSummary]                  // par tournoi, jamais par date
    func matches(inSeason season: Int) -> [SeasonMatch]                // par tournoi, jamais par date
    func seasonScope(_ season: Int) -> SeasonScope                     // tous les tournois connus de cette saison
}
```

Écart assumé avec la spec §3.4 : `referenceSeason(forTeams:now:)` prend `now` (les planches figent la date par `\.seasonNow`) ; la garde « pas de page `older` avant `firstMonth` » est posée par D5 dans le calendrier (seul appelant de `schedulePage`), pas dans `SeasonStore`.

- [ ] **Step 1: Ajouter les fixtures au paquet de tests hébergés** — dans `project.yml`, cible `FailleTests`, remplacer `sources:` par :

```yaml
    sources:
      - Tests/FailleTests
      # Fixtures réelles du périmètre (spec périmètre §1), partagées avec LoLKit : copiées telles quelles (dossier).
      - path: LoLKit/Tests/LoLKitTests/Fixtures/season/perimetre
        type: folder
        buildPhase: resources
```

- [ ] **Step 2: Écrire les tests hébergés qui échouent** `Tests/FailleTests/SeasonPerimetreTests.swift`

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

// MARK: Fixtures du périmètre (dossier `perimetre` du paquet de tests)

private final class PerimetreBundle {}

private let today = LoLDate.parse("2026-10-15T15:00:00Z")!
private let worldsId = "98767975604431411"
private let lecId = "98767991302996019"
private let msiId = "98767991325878492"
private let firstStandId = "113464388705111224"
private let demaciaId = "117126995932274206"
private let worlds2026 = "115660540725177488"
private let worlds2025 = "113475452383887518"
private let worlds2024 = "112966669920590211"
private let demacia2026 = "117133773242499009"

private enum PerimetreFiles {
    struct Missing: Error { let name: String }

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: PerimetreBundle.self)
            .url(forResource: name, withExtension: "json", subdirectory: "perimetre") else { throw Missing(name: name) }
        return try Data(contentsOf: url)
    }

    private struct TournamentsFile: Decodable {
        struct Payload: Decodable { let leagues: [League] }
        struct League: Decodable { let tournaments: [TournamentRef] }
        let data: Payload
    }

    /// Tournois d'une ligue (`getTournamentsForLeague_<slug>.json`) avec leur `leagueId`.
    static func tournaments(_ slug: String, leagueId: String) throws -> [TournamentRef] {
        try JSONDecoder().decode(TournamentsFile.self, from: data("getTournamentsForLeague_\(slug)")).data.leagues
            .flatMap(\.tournaments)
            .map { TournamentRef(id: $0.id, slug: $0.slug, startDate: $0.startDate, endDate: $0.endDate, leagueId: leagueId) }
    }

    static func allTournaments() throws -> [TournamentRef] {
        try tournaments("worlds", leagueId: worldsId) + tournaments("lec", leagueId: lecId)
            + tournaments("msi", leagueId: msiId) + tournaments("first_stand", leagueId: firstStandId)
            + tournaments("demacia_cup", leagueId: demaciaId)
    }

    struct ReducedTeam: Decodable { let code: String; let name: String; let gameWins: Int }
    struct ReducedMatch: Decodable {
        let matchId: String
        let startTime: String
        let blockName: String?
        let teams: [ReducedTeam]
        let playedGameIds: [String]
    }
    struct ReducedTournament: Decodable { let kcG2Matches: [ReducedMatch]? }

    /// Matchs réels de KC et G2 par id de tournoi.
    static func reducedByTournamentId() throws -> [String: [ReducedMatch]] {
        let bySlug = Dictionary(try allTournaments().map { ($0.slug, $0.id) }, uniquingKeysWith: { first, _ in first })
        let reduced = try JSONDecoder().decode([String: ReducedTournament].self,
                                               from: data("completed_kc_g2_2024_2026_reduced"))
        var result: [String: [ReducedMatch]] = [:]
        for (slug, tournament) in reduced {
            guard let id = bySlug[slug], let matches = tournament.kcG2Matches, !matches.isEmpty else { continue }
            result[id] = matches
        }
        return result
    }

    /// `SeasonMatch` de KC et G2 (ids d'équipe = code), pour un store d'aperçu.
    static func kcG2Matches() throws -> [SeasonMatch] {
        try reducedByTournamentId().flatMap { tournamentId, matches in
            matches.map { match in
                SeasonMatch(id: match.matchId, tournamentId: tournamentId, leagueSlug: "", stageSlug: nil,
                            startTime: LoLDate.parse(match.startTime)!, blockName: match.blockName,
                            bestOf: 2 * (match.teams.map(\.gameWins).max() ?? 1) - 1,
                            teams: match.teams.map {
                                MatchTeam(id: $0.code, name: $0.name, code: $0.code, image: nil,
                                          result: MatchTeam.Result(outcome: nil, gameWins: $0.gameWins))
                            },
                            playedGameIds: match.playedGameIds)
            }
        }
    }

    /// Réponse `getCompletedEvents` (forme de l'API, équipes sans id) construite depuis la fixture réduite.
    static func completedEvents(_ matches: [ReducedMatch]) -> Data {
        let events = matches.map { match in
            let best = match.teams.map(\.gameWins).max() ?? 0
            let teams = match.teams.map {
                #"{"name":"\#($0.name)","code":"\#($0.code)","image":null,"result":{"outcome":"\#($0.gameWins == best ? "win" : "loss")","gameWins":\#($0.gameWins)}}"#
            }.joined(separator: ",")
            let games = match.playedGameIds.map { #"{"id":"\#($0)","vods":[]}"# }.joined(separator: ",")
            return #"{"startTime":"\#(match.startTime)","blockName":"\#(match.blockName ?? "")","league":{"name":"x"},"match":{"id":"\#(match.matchId)","type":"normal","teams":[\#(teams)],"strategy":{"type":"bestOf","count":\#(max(1, 2 * best - 1))}},"games":[\#(games)]}"#
        }.joined(separator: ",")
        return Data(#"{"data":{"schedule":{"events":[\#(events)]}}}"#.utf8)
    }
}

/// Horloge virtuelle : `sleep` avance l'heure sans attendre.
private actor PerimetreClock: CrawlClock {
    private var current: Date
    init(_ start: Date) { current = start }
    func now() async -> Date { current }
    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        current = current.addingTimeInterval(seconds)
    }
}

/// Faux lolesports servant les fixtures réelles : tournois des 5 ligues, résultats de KC et G2, classement de la Demacia
/// Cup ; flux livestats → 404 (stats désactivées : une requête par game). Garde les URL.
private actor PerimetreWorld: HTTPTransport {
    private(set) var requests: [URL] = []
    private let completed: [String: Data]
    private let leagueFixtures = [worldsId: "worlds", lecId: "lec", msiId: "msi", firstStandId: "first_stand",
                                  demaciaId: "demacia_cup"]

    init(completed: [String: Data]) {
        self.completed = completed
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        let path = url.path(percentEncoded: false)
        let query = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        if path.hasSuffix("/getTournamentsForLeague"), let name = leagueFixtures[query["leagueId"] ?? ""] {
            return HTTPResponse(status: 200, body: try PerimetreFiles.data("getTournamentsForLeague_\(name)"))
        }
        if path.hasSuffix("/getCompletedEvents") {
            return HTTPResponse(status: 200, body: completed[query["tournamentId"] ?? ""]
                ?? Data(#"{"data":{"schedule":{"events":[]}}}"#.utf8))
        }
        if path.hasSuffix("/getStandings") {
            if query["tournamentId"] == demacia2026 {
                return HTTPResponse(status: 200, body: try PerimetreFiles.data("getStandings_demacia_cup_2026"))
            }
            return HTTPResponse(status: 200, body: Data(#"{"data":{"standings":[]}}"#.utf8))
        }
        return HTTPResponse(status: 404, body: Data())
    }
}

private let perimetreLeagues = [
    League(id: worldsId, slug: "worlds", name: "Mondial", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: lecId, slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1),
    League(id: msiId, slug: "msi", name: "MSI", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: firstStandId, slug: "first_stand", name: "First Stand", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: demaciaId, slug: "demacia_cup", name: "DCGI", region: "INTERNATIONAL", image: nil, priority: 1),
]

private let karmine = Team(id: "kc", slug: "karmine-corp", name: "Karmine Corp", code: "KC", image: nil, status: "active",
                           homeLeague: Team.HomeLeague(name: "LEC"))

private func line(_ teamId: String) -> TeamGameLine {
    TeamGameLine(teamId: teamId, kills: 10, gold: 60_000, towers: 8, inhibitors: 1, barons: 1, dragons: [], gold15: nil,
                 players: [])
}

private func game(id: String, tournamentId: String, startedAt: String) -> GameSummary {
    let start = LoLDate.parse(startedAt)!
    return GameSummary(gameId: id, matchId: "m-\(id)", tournamentId: tournamentId, leagueSlug: "lec", number: 1,
                       patch: nil, startedAt: start, endedAt: start.addingTimeInterval(1_800), durationSeconds: 1_800,
                       result: .unknown, blue: line("kc"), red: line("g2"), enriched: false)
}

@MainActor
@Suite(.serialized)
struct SeasonPerimetreTests {
    /// Spec périmètre §6.2 test 18 : premier lancement — tout ce qui date d'avant 2025 part, une seule fois.
    @Test func theFirstLaunchPurgesEverythingBefore2025Once() async throws {
        let cache = DiskCache(root: TemporaryFiles.directory())
        let worlds = try PerimetreFiles.tournaments("worlds", leagueId: worldsId)
        #expect(worlds.count == 11)
        cache.save(Cached(value: worlds, fetchedAt: today), to: SeasonDisk.tournamentsPath(worldsId))
        cache.save(game(id: "115548681803406304", tournamentId: "115548681802226458", startedAt: "2026-09-06T15:17:23.939Z"),
                   to: SeasonDisk.gamePath("115548681803406304"))
        cache.save(game(id: "112966669924194882", tournamentId: worlds2024, startedAt: "2024-11-02T14:35:43.676Z"),
                   to: SeasonDisk.gamePath("112966669924194882"))
        cache.save(Cached(value: [CompletedMatch](), fetchedAt: today), to: SeasonDisk.completedPath(worlds2024))
        cache.save(Cached(value: Standings(stages: []), fetchedAt: today), to: SeasonDisk.standingsPath(worlds2024))
        cache.save(ReplayRecord(firstFrame: LoLDate.parse("2024-11-02T14:35:43.676Z")!, frames: [], lastStep: nil,
                                complete: true), to: "replays/112966669924194882.json")
        cache.save(ReplayRecord(firstFrame: LoLDate.parse("2026-09-06T15:17:23.939Z")!, frames: [], lastStep: nil,
                                complete: true), to: "replays/115548681803406304.json")
        cache.write(Data("pas du json".utf8), to: "replays/illisible.json")

        let store = SeasonStore(transport: StubTransport(), cache: cache, clock: PerimetreClock(today))
        await store.loadFromDisk()

        for path in [SeasonDisk.gamePath("112966669924194882"), SeasonDisk.completedPath(worlds2024),
                     SeasonDisk.standingsPath(worlds2024), "replays/112966669924194882.json"] {
            #expect(cache.data(path) == nil, "\(path) aurait dû être supprimé")
        }
        #expect(cache.data("replays/illisible.json") != nil)
        #expect(cache.data("replays/115548681803406304.json") != nil)
        #expect(cache.data(SeasonDisk.gamePath("115548681803406304")) != nil)
        let rewritten = try #require(cache.load(Cached<[TournamentRef]>.self, from: SeasonDisk.tournamentsPath(worldsId)))
        #expect(rewritten.value.map(\.id) == [worlds2026, worlds2025])
        #expect(cache.load(SeasonPurge.Marker.self, from: SeasonPurge.markerPath)
                == SeasonPurge.Marker(v: 1, startDay: "2025-01-01"))
        #expect(Set(store.games.keys) == ["115548681803406304"])
        #expect(store.tournaments[worldsId]?.count == 2)
        #expect(store.isOutsideWindow(tournamentId: worlds2024))
        // Second lancement : marqueur à jour → aucun fichier du Détail relu.
        let again = SeasonDisk(cache: cache).load(window: SeasonWindow(now: today))
        #expect(again.detailFilesRead == 0)
    }

    /// Spec périmètre §6.2 test 19 : une passe complète pour KC suivie — rien de 2024, une énumération par ligue, la
    /// Demacia Cup (complète, non suivie) lue, 2 s entre deux requêtes, arrêt à 300.
    @Test func aFullPassForKarmineCorpNeverTouches2024() async throws {
        let completed = try PerimetreFiles.reducedByTournamentId().mapValues(PerimetreFiles.completedEvents)
        let world = PerimetreWorld(completed: completed)
        let store = SeasonStore(transport: world, cache: DiskCache(root: TemporaryFiles.directory()),
                                clock: PerimetreClock(today))
        let follows = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", homeLeagueName: "LEC")])
        let end = await store.crawl {
            SeasonContext(follows: follows, leagues: perimetreLeagues, catalog: [karmine], revealed: [],
                          openedTeamId: nil, now: today)
        }
        #expect(end == .budget)
        let urls = await world.requests.map(\.absoluteString)
        #expect(urls.count == CrawlPacer.sessionRequestBudget)
        #expect(!urls.contains { $0.contains(worlds2024) })
        for leagueId in [worldsId, lecId, msiId, firstStandId, demaciaId] {
            #expect(urls.filter { $0.contains("getTournamentsForLeague") && $0.contains(leagueId) }.count == 1)
        }
        #expect(urls.contains { $0.contains("getCompletedEvents") && $0.contains(demacia2026) })
        let sent = try #require(await store.paced?.sentAt)
        for (earlier, later) in zip(sent, sent.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= CrawlPacer.baseInterval)
        }
        // Les games demandées sont toutes des games réelles de KC ou de G2 (2025-2026).
        let known = Set(try PerimetreFiles.reducedByTournamentId().values.flatMap { $0.flatMap(\.playedGameIds) })
        let windows = urls.filter { $0.contains("/window/") }
            .compactMap { URL(string: $0)?.path.split(separator: "/").last.map(String.init) }
        #expect(!windows.isEmpty)
        #expect(Set(windows).isSubset(of: known))
    }

    /// Spec périmètre §6.2 test 20 : le store n'expose que la fenêtre.
    @Test func theStoreOnlyExposesTheWindow() throws {
        let cache = DiskCache(root: TemporaryFiles.directory())
        let store = SeasonStore(transport: StubTransport(), cache: cache, clock: PerimetreClock(today))
        store.record(tournaments: try PerimetreFiles.tournaments("worlds", leagueId: worldsId), leagueId: worldsId, at: today)
        #expect(store.tournaments[worldsId]?.map(\.id) == [worlds2026, worlds2025])
        #expect(store.isOutsideWindow(tournamentId: worlds2024))
        let old = CompletedMatch(matchId: "m-2024", startTime: LoLDate.parse("2024-11-02T14:00:00Z")!, blockName: nil,
                                 bestOf: 5, teams: [], gameIds: [])
        store.record(completed: [old], tournamentId: worlds2024, at: today)
        #expect(store.matches.isEmpty)
        #expect(cache.data(SeasonDisk.completedPath(worlds2024)) == nil)
        store.record(game(id: "g-2024", tournamentId: worlds2024, startedAt: "2024-11-02T14:35:43.676Z"), followedTeamIds: [])
        #expect(store.games["g-2024"] == nil)
        #expect(SeasonPlanning.currentTournamentIds(store.tournaments, leagueIds: [worldsId], now: today) == [worlds2026])

        // Pilules de KC (spec test 10) sur un store d'aperçu nourri des vrais matchs.
        let preview = SeasonStore(preview: SeasonPreview(tournaments: try PerimetreFiles.allTournaments(),
                                                         matches: try PerimetreFiles.kcG2Matches()))
        #expect(preview.scopes(forTeam: "KC", now: today).map(\.label) == [
            "2026", "lec_split_3_2026", "msi_2026", "lec_split_2_2026", "lec_split_1_2026",
            "2025", "lec_summer_2025", "lec_spring_2025", "first_stand_2025", "lec_winter_2025",
        ])
        #expect(preview.referenceSeason(forTeams: ["KC"], now: today) == 2026)
        #expect(preview.referenceSeason(forTeams: ["KC"], now: LoLDate.parse("2027-01-05T12:00:00Z")!) == 2026)
        #expect(preview.matches(inSeason: 2025).filter { $0.involves("KC") }.count == 40)
        #expect(preview.matches(inSeason: 2026).filter { $0.involves("KC") }.count == 46)
        #expect(preview.seasonScope(2025).tournamentIds.count == 6)
    }

    /// Appartenance à une saison par tournoi (jamais par la date de la game).
    @Test func gamesBelongToTheSeasonOfTheirTournament() throws {
        let tournaments = try PerimetreFiles.allTournaments()
        let lecWinter2025 = "113475994398658012"
        let lecSplit3 = "115548681802226458"
        let preview = SeasonStore(preview: SeasonPreview(
            tournaments: tournaments,
            games: [game(id: "g26", tournamentId: lecSplit3, startedAt: "2026-09-06T15:17:23.939Z"),
                    game(id: "g25", tournamentId: lecWinter2025, startedAt: "2025-01-18T17:09:12.350Z")]))
        #expect(preview.games(inSeason: 2025).map(\.gameId) == ["g25"])
        #expect(preview.games(inSeason: 2026).map(\.gameId) == ["g26"])
        #expect(preview.season(ofTournament: lecWinter2025) == 2025)
    }

    /// Énumération : ligues complètes (Demacia Cup) et prédécesseurs (LCS → LTA North / Cross, saison N − 1 seule).
    @Test func planningEnumeratesCompleteLeaguesAndPredecessors() {
        let lcsId = "98767991299243165"
        let ltaNId = "113470291645289904"
        let ltaCrossId = "113475149040947852"
        let lcs = League(id: lcsId, slug: "lcs", name: "LCS", region: "AMÉRIQUE DU NORD", image: nil, priority: 1)
        let leagues = [
            perimetreLeagues[0], perimetreLeagues[1], lcs,
            League(id: ltaNId, slug: "lta_n", name: "LTA North", region: "AMERICAS", image: nil, priority: 1),
            League(id: ltaCrossId, slug: "lta_cross", name: "LTA Cross-Conference", region: "AMERICAS", image: nil, priority: 1),
            perimetreLeagues[4],
        ]
        let context = SeasonContext(follows: FollowList(leagues: [FollowedLeague(league: lcs)]), leagues: leagues,
                                    catalog: [], revealed: [], openedTeamId: nil, now: today)
        #expect(Set(SeasonPlanning.leagueIds(context)) == [worldsId, lcsId, demaciaId, ltaNId, ltaCrossId])
        #expect(SeasonPlanning.predecessorLeagueIds(context) == [ltaNId, ltaCrossId])
        let byLeague: [String: [TournamentRef]] = [
            worldsId: [
                TournamentRef(id: worlds2026, slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-11-15", leagueId: worldsId),
                TournamentRef(id: worlds2025, slug: "worlds_2025", startDate: "2025-10-14", endDate: "2025-11-09", leagueId: worldsId),
                TournamentRef(id: worlds2024, slug: "worlds_2024", startDate: "2024-09-24", endDate: "2024-11-02", leagueId: worldsId),
            ],
            lcsId: [TournamentRef(id: "lcs-26", slug: "lcs_split_3_2026", startDate: "2026-07-25", endDate: "2026-09-14", leagueId: lcsId)],
            ltaNId: [TournamentRef(id: "ltan-25", slug: "lta_n_split_3_2025", startDate: "2025-07-26", endDate: "2025-09-14", leagueId: ltaNId)],
        ]
        let started = SeasonPlanning.startedTournaments(byLeague, leagueIds: SeasonPlanning.leagueIds(context),
                                                        predecessorLeagueIds: SeasonPlanning.predecessorLeagueIds(context),
                                                        now: today)
        #expect(started.map(\.id) == [worlds2026, "lcs-26", worlds2025, "ltan-25"])
        let wanted = SeasonPlanning.wanted(context, byLeague: byLeague, standings: [:])
        #expect(wanted.allowedTournamentIds == [worlds2026, worlds2025, "lcs-26", "ltan-25"])
        #expect(wanted.previousSeasonTournamentIds == [worlds2025, "ltan-25"])
        #expect(wanted.completeTournamentIds == [worlds2026, worlds2025])
        #expect(!wanted.currentTournamentIds.contains("ltan-25"))
    }
}
```

- [ ] **Step 3: Adapter l'attente existante de `SeasonStoreTests.planningHelpers`** (la saison N − 1 est désormais énumérée, spec §3.1) :

```swift
        // Saisons 2026 et 2025 déjà commencées (le tournoi de décembre n'a rien à lire), du plus récent au plus ancien.
        #expect(SeasonPlanning.startedTournaments(refs, leagueIds: ["l"], now: today).map(\.id) == ["s3", "s1", "old"])
```

- [ ] **Step 4: Implémenter `SeasonPlanning`** (`App/Season/SeasonPlanning.swift`) — ajouter après `struct SeasonContext` :

```swift
extension SeasonContext {
    /// Périmètre du tour (spec périmètre §3.1), recalculé depuis `now`.
    var window: SeasonWindow { SeasonWindow(now: now) }
}
```

et remplacer `leagueIds`, `startedTournaments`, `wanted` par (ajouter `predecessorLeagueIds`) :

```swift
    /// Ligues du calendrier de l'appli (`ScheduleQuery`), ligues suivies, ligue d'attache de l'équipe ouverte.
    private static func baseLeagueIds(_ context: SeasonContext) -> [String] {
        var ids = ScheduleQuery.leagueIds(follows: context.follows, leagues: context.leagues)
        for id in context.follows.leagues.map(\.id) where !ids.contains(id) {
            ids.append(id)
        }
        if let opened = context.openedTeamId,
           let home = context.catalog.first(where: { $0.id == opened })?.homeLeague?.name,
           let league = context.leagues.first(where: { $0.name == home }), !ids.contains(league.id) {
            ids.append(league.id)
        }
        return ids
    }

    /// Ligues à énumérer : la base, plus les compétitions complètes (`SeasonWindow.completeLeagueSlugs`, ids lus dans
    /// `getLeagues` par slug, jamais en dur), plus les prédécesseurs des ligues de la base (saison N − 1 seule).
    static func leagueIds(_ context: SeasonContext) -> [String] {
        var ids = baseLeagueIds(context)
        for league in context.leagues where SeasonWindow.completeLeagueSlugs.contains(league.slug) && !ids.contains(league.id) {
            ids.append(league.id)
        }
        let predecessors = predecessorLeagueIds(context)
        for league in context.leagues where predecessors.contains(league.id) && !ids.contains(league.id) {
            ids.append(league.id)
        }
        return ids
    }

    /// Ligues lues seulement pour la saison N − 1 d'une ligue renommée (`SeasonWindow.predecessors`) : LTA North et Cross
    /// pour la LCS, LTA South et Cross pour le CBLOL ; jamais une ligue déjà voulue pour elle-même.
    static func predecessorLeagueIds(_ context: SeasonContext) -> Set<String> {
        let base = Set(baseLeagueIds(context))
        let slugs = context.leagues.filter { base.contains($0.id) }.flatMap { SeasonWindow.predecessors[$0.slug] ?? [] }
        return Set(context.leagues.filter { slugs.contains($0.slug) && !base.contains($0.id) }.map(\.id))
    }

    /// Tournois du périmètre de ces ligues déjà commencés (un tournoi à venir n'a ni résultat ni classement à lire), du
    /// plus récent au plus ancien ; d'une ligue prédécesseur, seulement ceux de la saison N − 1. Aucun tournoi `.outside`.
    static func startedTournaments(_ byLeague: [String: [TournamentRef]], leagueIds: [String],
                                   predecessorLeagueIds: Set<String> = [], now: Date) -> [TournamentRef] {
        let window = SeasonWindow(now: now)
        let today = day(now)
        let candidates = leagueIds.flatMap { leagueId in
            (byLeague[leagueId] ?? []).filter {
                !predecessorLeagueIds.contains(leagueId) || window.placement(of: $0) == .previous
            }
        }
        return window.tournaments(candidates).filter { !$0.startDate.isEmpty && $0.startDate <= today }
    }

    /// Ce que veut la collecte (`CrawlWanted`, spec périmètre §3.2) : équipe ouverte, équipes suivies, étape en cours de
    /// chaque tournoi complet en cours, ligues suivies, tournois en cours (hors prédécesseurs), tournois du périmètre, de
    /// la saison N − 1 et des compétitions complètes.
    static func wanted(_ context: SeasonContext, byLeague: [String: [TournamentRef]],
                       standings: [String: Standings]) -> CrawlWanted {
        let ids = leagueIds(context)
        let window = context.window
        let today = day(context.now)
        let predecessors = predecessorLeagueIds(context)
        let completeLeagueIds = Set(context.leagues.filter { SeasonWindow.completeLeagueSlugs.contains($0.slug) }.map(\.id))
        var allowed = Set<String>(), previous = Set<String>(), complete = Set<String>()
        for leagueId in ids {
            for tournament in window.tournaments(byLeague[leagueId] ?? []) {
                let placement = window.placement(of: tournament)
                if predecessors.contains(leagueId) && placement != .previous { continue }
                allowed.insert(tournament.id)
                if placement == .previous { previous.insert(tournament.id) }
                if completeLeagueIds.contains(leagueId) { complete.insert(tournament.id) }
            }
        }
        let liveStage = completeLeagueIds.filter(ids.contains)
            .flatMap { byLeague[$0] ?? [] }
            .filter { window.contains($0) && $0.isActive(today: today) }
            .compactMap { standings[$0.id] }
            .reduce(into: Set<String>()) { $0.formUnion(CrawlPlanner.currentStageMatchIds($1)) }
        return CrawlWanted(openedTeamId: context.openedTeamId,
                           followedTeamIds: context.follows.teams.map(\.id),
                           liveCompleteStageMatchIds: liveStage,
                           followedLeagueSlugs: context.follows.leagues.map(\.slug),
                           currentTournamentIds: currentTournamentIds(byLeague, leagueIds: ids.filter { !predecessors.contains($0) },
                                                                      now: context.now),
                           allowedTournamentIds: allowed,
                           previousSeasonTournamentIds: previous,
                           completeTournamentIds: complete)
    }
```

(`day`, `readWhileActive`, `plusDays`, `year`, `currentTournamentIds`, `at15` restent inchangés ; mettre à jour la doc comment de l'enum : « fenêtre `SeasonWindow` ».)

- [ ] **Step 5: Brancher l'énumération** — dans `SeasonCrawler.enumerate`, remplacer l'appel de `startedTournaments` :

```swift
        let predecessors = SeasonPlanning.predecessorLeagueIds(context)
        for tournament in SeasonPlanning.startedTournaments(store.tournaments, leagueIds: leagueIds,
                                                            predecessorLeagueIds: predecessors, now: now) {
```

(le corps de la boucle est inchangé ; `getTournamentsForLeague` reste 1 requête par ligue et par 24 h.)

- [ ] **Step 6: Créer `App/Season/SeasonPurge.swift`**

```swift
import Foundation
import LoLKit

/// Purge des caches du Détail hors périmètre (spec périmètre §3.3), une fois par fenêtre : `replays/<gameId>.json`
/// (`firstFrame`), `details/<gameId>.json` (`details.frames[0].rfc460Timestamp`), `spells/<matchId>.json` (plus récent
/// `openings[*].start`) ; supprimé si la date lue est avant `window.startDate`, **gardé** si elle est illisible ou absente.
/// Le marqueur `season/window.json` n'est écrit qu'après la purge : une purge interrompue est refaite (idempotente).
/// Jamais `FileStore` (suivis, réglages, révélations, Live Activities) : seulement des chemins de `DiskCache`.
struct SeasonPurge: Sendable {
    static let markerPath = "season/window.json"

    struct Marker: Codable, Equatable, Sendable {
        let v: Int
        let startDay: String
    }

    let cache: DiskCache

    /// Purge si le marqueur manque ou date d'une autre fenêtre ; rend le nombre de fichiers du Détail lus (0 sinon).
    func run(window: SeasonWindow) -> Int {
        let marker = Marker(v: 1, startDay: window.startDay)
        guard cache.load(Marker.self, from: Self.markerPath) != marker else { return 0 }
        var read = 0
        let probes: [(folder: String, date: @Sendable (Data) -> Date?)] = [
            ("replays", Self.replayDate), ("details", Self.detailsDate), ("spells", Self.spellsDate),
        ]
        for probe in probes {
            for url in files(in: probe.folder) {
                read += 1
                guard let data = try? Data(contentsOf: url), let date = probe.date(data) else { continue }
                if !window.contains(date: date) { try? FileManager.default.removeItem(at: url) }
            }
        }
        cache.save(marker, to: Self.markerPath)
        return read
    }

    private struct ReplayProbe: Decodable { let firstFrame: Date }
    private struct DetailsProbe: Decodable {
        struct Frame: Decodable { let rfc460Timestamp: Date }
        struct Details: Decodable { let frames: [Frame] }
        let details: Details
    }
    private struct SpellsProbe: Decodable {
        struct Opening: Decodable { let start: Date }
        let openings: [String: Opening]
    }

    /// Dates encodées par `JSONEncoder()` par défaut (secondes depuis 2001), comme `DiskCache.save`.
    static func replayDate(_ data: Data) -> Date? {
        (try? JSONDecoder().decode(ReplayProbe.self, from: data))?.firstFrame
    }

    static func detailsDate(_ data: Data) -> Date? {
        (try? JSONDecoder().decode(DetailsProbe.self, from: data))?.details.frames.first?.rfc460Timestamp
    }

    static func spellsDate(_ data: Data) -> Date? {
        (try? JSONDecoder().decode(SpellsProbe.self, from: data))?.openings.values.map(\.start).max()
    }

    private func files(in folder: String) -> [URL] {
        guard let url = cache.url(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
        else { return [] }
        return names.filter { $0.hasSuffix(".json") }.map { url.appendingPathComponent($0) }
    }
}
```

- [ ] **Step 7: Purger `season/` à la lecture** (`App/Season/SeasonDisk.swift`) — `Snapshot` gagne :

```swift
        /// Tournois écartés par la fenêtre (listes filtrées, fichiers supprimés) : jamais relus.
        var outsideTournamentIds: Set<String> = []
        /// Fichiers du Détail lus par `SeasonPurge` (0 quand le marqueur est à jour).
        var detailFilesRead = 0
```

et `load()` devient `load(window:)` (doc comment : « lit tout, puis purge hors fenêtre — spec périmètre §3.3 ») :

```swift
    func load(window: SeasonWindow) -> Snapshot {
        var snapshot = Snapshot()
        let decoder = JSONDecoder()
        for (id, data) in files(in: "season/games") {
            guard let game = GameSummary.decodeStored(data) else {
                if let probe = try? decoder.decode(SchemaProbe.self, from: data), probe.v > GameSummary.schemaVersion {
                    snapshot.newerGameIds.insert(id)
                }
                continue
            }
            snapshot.games[id] = game
        }
        // Listes de tournois : filtrées par la fenêtre, réécrites si elles contenaient des tournois hors fenêtre.
        var known: [String: TournamentRef] = [:]
        for (leagueId, data) in files(in: "season/tournaments") {
            guard let cached = try? decoder.decode(Cached<[TournamentRef]>.self, from: data) else { continue }
            for tournament in cached.value { known[tournament.id] = tournament }
            let kept = window.tournaments(cached.value)
            if kept.count != cached.value.count {
                snapshot.outsideTournamentIds.formUnion(Set(cached.value.map(\.id)).subtracting(kept.map(\.id)))
                save(tournaments: Cached(value: kept, fetchedAt: cached.fetchedAt), leagueId: leagueId)
            }
            snapshot.tournaments[leagueId] = Cached(value: kept, fetchedAt: cached.fetchedAt)
        }
        for (id, data) in files(in: "season/completed") {
            snapshot.completed[id] = try? decoder.decode(Cached<[CompletedMatch]>.self, from: data)
        }
        for (id, data) in files(in: "season/standings") {
            snapshot.standings[id] = try? decoder.decode(Cached<Standings>.self, from: data)
        }
        // Résultats et classements hors fenêtre : les deux fichiers de chaque id.
        let lastMatchStart = snapshot.completed.compactMapValues { $0.value.map(\.startTime).max() }
        let outside = window.outsideTournamentIds(Set(snapshot.completed.keys).union(snapshot.standings.keys),
                                                  tournaments: known, lastMatchStart: lastMatchStart)
        for id in outside {
            for path in [Self.completedPath(id), Self.standingsPath(id)] {
                if let url = cache.url(path) { try? FileManager.default.removeItem(at: url) }
            }
            snapshot.completed[id] = nil
            snapshot.standings[id] = nil
        }
        snapshot.outsideTournamentIds.formUnion(outside)
        // Games hors fenêtre (jamais une game d'un schéma plus récent : elle n'est pas dans `games`).
        let outsideGames = window.outsideGameIds(Array(snapshot.games.values), tournaments: known)
        deleteGames(outsideGames)
        for id in outsideGames { snapshot.games[id] = nil }
        // Échecs : seulement ceux des games qu'un match restant référence.
        let failures = cache.load([String: CrawlFailure].self, from: Self.failuresPath) ?? [:]
        let referenced = Set(snapshot.completed.values.flatMap { $0.value.flatMap(\.gameIds) })
        snapshot.failures = failures.filter { referenced.contains($0.key) }
        if snapshot.failures.count != failures.count { save(failures: snapshot.failures) }
        snapshot.detailFilesRead = SeasonPurge(cache: cache).run(window: window)
        return snapshot
    }
```

(Mettre à jour la doc comment de l'en-tête : « au-delà de 4 000, `CrawlPlanner.evictions` ; rien d'avant N − 1 ».)

- [ ] **Step 8: Faire de `SeasonStore` le point d'étranglement** (`App/Season/SeasonStore.swift`) :

(a) Propriétés internes, à côté de `newerGameIds` :

```swift
    /// Périmètre des écritures (spec périmètre §3.4) : recalculé à chaque écriture datée et à la lecture du disque.
    @ObservationIgnored private(set) var window = SeasonWindow(now: Date())
    /// Tournois écartés par la fenêtre : jamais lus (`loadStandings`), jamais rangés (`record`), jamais montrés.
    @ObservationIgnored private var outsideTournamentIds: Set<String> = []
```

(b) `loadFromDisk` — la tâche devient :

```swift
        let task = Task {
            let now = await self.clock.now()
            let window = SeasonWindow(now: now)
            let snapshot = await Task.detached(priority: .utility) { disk.load(window: window) }.value
            self.advanceWindow(to: now)
            self.outsideTournamentIds.formUnion(snapshot.outsideTournamentIds)
            self.publish(snapshot)
        }
```

(c) Section « Périmètre » (nouvelle `// MARK: Périmètre`, après « Lectures pour les vues ») :

```swift
    /// Tournoi écarté par la fenêtre (classement « trop ancien »).
    func isOutsideWindow(tournamentId: String) -> Bool {
        outsideTournamentIds.contains(tournamentId)
    }

    private var allTournaments: [TournamentRef] {
        tournaments.values.flatMap { $0 }
    }

    /// Saison d'appartenance d'un tournoi : celle de la fenêtre (`scopeSeason` : un `liveOverride` compte en N), à défaut
    /// sa propre saison (store d'aperçu figé, dont la fenêtre suit l'horloge réelle).
    private func membership(of tournament: TournamentRef) -> Int? {
        window.scopeSeason(of: tournament) ?? SeasonWindow.season(of: tournament)
    }

    /// Saison d'appartenance d'un tournoi connu.
    func season(ofTournament id: String) -> Int? {
        tournament(id: id).flatMap(membership(of:))
    }

    private func seasonsByTournament() -> [String: Int] {
        Dictionary(allTournaments.compactMap { tournament in membership(of: tournament).map { (tournament.id, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Saison de référence (spec périmètre §3.5) : N si ces équipes (toutes si `ids` est vide) ont un match en N, sinon
    /// N − 1 si elles en ont, sinon N.
    func referenceSeason(forTeams ids: [String], now: Date) -> Int {
        let target = SeasonWindow(now: now)
        let relevant = ids.isEmpty ? matches : matches.filter { match in ids.contains { match.involves($0) } }
        let seasons = Set(relevant.compactMap { match in tournament(id: match.tournamentId).flatMap(target.scopeSeason(of:)) })
        return target.referenceSeason(seasonsWithData: seasons)
    }

    /// Games d'une saison, par tournoi (jamais par la date de la game).
    func games(inSeason season: Int) -> [GameSummary] {
        let seasons = seasonsByTournament()
        return games.values.filter { seasons[$0.tournamentId] == season }
    }

    /// Matchs d'une saison, par tournoi, du plus récent au plus ancien.
    func matches(inSeason season: Int) -> [SeasonMatch] {
        let seasons = seasonsByTournament()
        return matches.filter { seasons[$0.tournamentId] == season }
    }

    /// Périmètre « Saison N » de tous les tournois connus de cette saison (page joueur sans pilule, duels).
    func seasonScope(_ season: Int) -> SeasonScope {
        SeasonScope(tournamentIds: Set(allTournaments.filter { membership(of: $0) == season }.map(\.id)),
                    label: String(season), season: season)
    }

    /// Le jour a changé de fenêtre (1er janvier UTC) : listes refiltrées, matchs rejoints.
    private func advanceWindow(to date: Date) {
        let next = SeasonWindow(now: date)
        guard next != window else { return }
        window = next
        for (leagueId, list) in tournaments {
            let kept = next.tournaments(list)
            outsideTournamentIds.formUnion(Set(list.map(\.id)).subtracting(kept.map(\.id)))
            tournaments[leagueId] = kept
        }
        rejoin()
    }
```

(d) `scopes(forTeam:now:)` devient (doc comment : « spec périmètre §3.5, `SeasonWindow.scopes` ») :

```swift
    func scopes(forTeam teamId: String, now: Date) -> [SeasonScope] {
        let ids = Set(matches(ofTeam: teamId).map(\.tournamentId))
        return SeasonWindow(now: now).scopes(played: allTournaments.filter { ids.contains($0.id) })
    }
```

(e) `loadStandings` — première ligne : `guard standings[tournamentId] == nil, !isOutsideWindow(tournamentId: tournamentId), let paced else { return }`.

(f) Écritures :

```swift
    func record(tournaments value: [TournamentRef], leagueId: String, at date: Date) {
        advanceWindow(to: date)
        let kept = window.tournaments(value)
        outsideTournamentIds.formUnion(Set(value.map(\.id)).subtracting(kept.map(\.id)))
        tournaments[leagueId] = kept
        fetchedAt[Self.tournamentsKey(leagueId)] = date
        disk?.save(tournaments: Cached(value: kept, fetchedAt: date), leagueId: leagueId)
    }

    func record(completed value: [CompletedMatch], tournamentId: String, at date: Date) {
        advanceWindow(to: date)
        guard !isOutsideWindow(tournamentId: tournamentId) else { return }
        // … corps existant inchangé
    }

    func record(standings value: Standings, tournamentId: String, at date: Date) {
        advanceWindow(to: date)
        guard !isOutsideWindow(tournamentId: tournamentId) else { return }
        // … corps existant inchangé
    }
```

Dans `rejoin`, la boucle commence par : `guard let ref = tournament(id: tournamentId), window.contains(ref) else { continue }` puis utilise `ref.leagueId` au lieu de `tournament(id: tournamentId)?.leagueId` (un match dont le tournoi est inconnu ou hors fenêtre n'entre pas dans `matches`).

Dans `record(_ game:followedTeamIds:)` : première ligne `guard !isOutsideWindow(tournamentId: game.tournamentId) else { return }` ; l'éviction devient :

```swift
        // Inconnu = gardé (la purge du lancement le tranche par sa date) ; hors fenêtre connu = toujours supprimé.
        let allowed = Set(games.values.map(\.tournamentId)).subtracting(outsideTournamentIds)
        let previous = Set(allTournaments.filter { window.placement(of: $0) == .previous }.map(\.id))
        let excess = CrawlPlanner.evictions(Array(games.values), followedTeamIds: followedTeamIds,
                                            allowedTournamentIds: allowed, previousSeasonTournamentIds: previous)
            .filter { $0 != game.gameId }
```

`init(preview:)` ne filtre pas (données figées des planches) ; `currentTournament(forTeam:now:)`, `player(_:scope:masked:)`, `teamSeason` sont inchangés.

- [ ] **Step 9: Vérifications locales**

Run: `git diff --check && python3 scripts/strings-check.py`
Expected: aucune sortie de `git diff --check` ; strings-check vert (D3 n'ajoute aucune chaîne affichée).
Run: `grep -rnE "\"20(24|25)" App/Season/SeasonStore.swift App/Season/SeasonDisk.swift App/Season/SeasonPlanning.swift App/Season/SeasonPurge.swift App/Season/SeasonCrawler.swift`
Expected: aucune occurrence.
Les tests hébergés (18-20 et l'existant) tournent en CI iOS à la fin du lot ; attendu : PASS.

- [ ] **Step 10: Commit**

```bash
git add App/Season/SeasonPurge.swift App/Season/SeasonStore.swift App/Season/SeasonDisk.swift \
        App/Season/SeasonPlanning.swift App/Season/SeasonCrawler.swift project.yml \
        Tests/FailleTests/SeasonPerimetreTests.swift Tests/FailleTests/SeasonStoreTests.swift
git commit -m "feat(app): SeasonStore borné à la fenêtre — énumération, purge du disque et des caches du Détail" \
           -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task D4: Pages équipe et joueur, duels (appli)

Spec §3.5 (page équipe, page joueur, duels), §3.6 (libellés de D4), §6.2 test 22 (planches équipe et duel). Modèle suggéré : standard.

**Files:**
- Create: `Tests/FailleTests/PerimetreScreensTests.swift`
- Create: `Tests/FailleTests/PerimetreSnapshotTests.swift`
- Modify: `App/Season/SeasonLabels.swift`
- Modify: `App/Season/SeasonSamples.swift` (aperçu `perimetre`)
- Modify: `Shared/Preview/SampleData.swift` (`SeasonSample.perimetre`, `PreviewData.withPerimetre`)
- Modify: `App/Store/AppStore+Season.swift` (une ligne du `switch` de `seasonPreview`)
- Modify (vues) : `App/TeamPage/TeamPageView.swift`, `App/TeamPage/TeamPageSections.swift` (`TeamHeadToHeadCard`), `App/PlayerPage/PlayerPageView.swift`, `App/Duel/DuelSection.swift`, `App/Duel/DuelView.swift`, `App/Duel/DuelBars.swift` (`TeamDuelCard`)
- Modify: `Tests/FailleTests/TeamPageTests.swift` (lignes ~92 et ~97)

**OWNERSHIP (vague 4, en parallèle de D5)** : D4 seul modifie `SeasonLabels.swift`, `SeasonSamples.swift`, `SampleData.swift`, `AppStore+Season.swift` (modifié par aucune autre tâche du lot) et les six vues ci-dessus. Ne touche pas `WindowTexts.swift`, `HomeStore.swift`, `HotPlayersSection.swift`, le calendrier, `StandingsView.swift`, `SettingsView.swift` (D5), ni `Localizable.xcstrings` (D6).

**Interfaces:**
- Consumes (D1, D3) : `SeasonWindow(now:)`, `window.currentSeason`, `window.previousSeason`, `SeasonScope.season`, `SeasonScope.isLive`, `store.season.scopes(forTeam:now:)`, `store.season.referenceSeason(forTeams:now:)`, `store.season.games(inSeason:)`, `store.season.seasonScope(_:)`.
- Produces :

```swift
enum SeasonLabels {
    static func season(year: String) -> String                                 // existant
    static func scope(_ scope: SeasonScope, currentSeason: Int) -> String     // remplace scope(_:)
    static func league(slug: String) -> String                                 // + "demacia_cup" → « Demacia Cup »
    static func tournament(slug: String) -> String                             // « demacia_cup_2026 » → « Demacia Cup »
    static func headToHeadTitle(_ window: SeasonWindow) -> String             // « Face-à-face 2025-2026 »
    static func duelHeadToHead(_ window: SeasonWindow, left: String, winsLeft: Int, winsRight: Int,
                               right: String) -> String                        // « 2025-2026 : KC 5 – 8 G2 »
    static func seasonStats(year: Int) -> String                               // « Stats de la saison 2026 »
}
enum SeasonSample { case none, standard, collecting, loading, perimetre }
extension PreviewData { static var withPerimetre: PreviewData { get } }
enum SeasonSamples { static var perimetre: SeasonPreview { get } }
struct TeamPageContent { /* … */ let window: SeasonWindow }
struct DuelSectionContent { let seasonMasked: Set<String>; let lines: [DuelEntry]; let referenceSeason: Int }
```

- [ ] **Step 1: Écrire les tests qui échouent** `Tests/FailleTests/PerimetreScreensTests.swift`

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

private let now = SampleData.date("2026-10-15T15:05:00Z")
private let window = SeasonWindow(now: now)

/// Écrans du périmètre (spec périmètre §3.5, §3.6) : libellés, pilules des deux saisons, face-à-face sur la fenêtre.
@MainActor
struct PerimetreScreensTests {
    @Test func scopeLabels() {
        func label(_ label: String, season: Int?, live: Bool = false) -> String {
            SeasonLabels.scope(SeasonScope(tournamentIds: ["t"], label: label, season: season, isLive: live),
                               currentSeason: 2026)
        }
        #expect(label("2026", season: 2026) == "Saison 2026")
        #expect(label("2025", season: 2025) == "Saison 2025")
        #expect(label("worlds_2026", season: 2026, live: true) == "Mondial · en cours")
        #expect(label("lec_split_3_2026", season: 2026) == "LEC Split 3")
        #expect(label("worlds_2025", season: 2025) == "Mondial 2025")
        #expect(label("lec_summer_2025", season: 2025) == "LEC Summer 2025")
        #expect(SeasonLabels.league(slug: "demacia_cup") == "Demacia Cup")
        #expect(SeasonLabels.tournament(slug: "demacia_cup_2026") == "Demacia Cup")
        #expect(SeasonLabels.tournament(slug: "first_stand_2026") == "First Stand")
    }

    @Test func windowLabels() {
        #expect(SeasonLabels.headToHeadTitle(window) == "Face-à-face 2025-2026")
        #expect(SeasonLabels.duelHeadToHead(window, left: "KC", winsLeft: 5, winsRight: 8, right: "G2")
                == "2025-2026 : KC 5 – 8 G2")
        #expect(SeasonLabels.seasonStats(year: 2026) == "Stats de la saison 2026")
    }

    /// Pilules de KC sur l'aperçu `perimetre` (vrais matchs KC-G2 2025-2026 + un match du Mondial 2026 en cours).
    @Test func karmineCorpHasBothSeasons() {
        let store = AppStore(preview: .withPerimetre)
        let content = TeamPageContent.make(store: store, teamId: "kc", scopeIndex: 0, now: now)
        #expect(content.scopes.map { SeasonLabels.scope($0, currentSeason: content.window.currentSeason) } == [
            "Saison 2026", "Mondial · en cours", "LEC Split 3", "LEC Split 2", "LEC Split 1",
            "Saison 2025", "LEC Summer 2025", "LEC Spring 2025", "LEC Winter 2025",
        ])
        let h2h = SeasonStats.headToHead("kc", "g2", matches: store.season.matches, masked: [])
        #expect([h2h.winsA, h2h.winsB] == [5, 8])
        #expect(h2h.matchIds.count == 13)
        #expect(store.season.referenceSeason(forTeams: ["kc", "g2"], now: now) == 2026)
    }

    /// Duel du Détail : stats de la saison de référence (2026 sur l'aperçu standard).
    @Test func detailDuelUsesTheReferenceSeason() {
        let store = AppStore(preview: .withSeason)
        let teams = SeasonSamples.matches.first { $0.id == "m-kc-g2" }?.teams ?? []
        let content = DuelSectionMemo().value(store: store, teams: teams, selectedGameId: nil, masked: false, now: now)
        #expect(content.referenceSeason == 2026)
    }
}
```

Et adapter `Tests/FailleTests/TeamPageTests.swift` (le Mondial d'exemple, 01/10 → 15/11, est en cours le 15/10) :

```swift
        #expect(content.scopes.map { SeasonLabels.scope($0, currentSeason: 2026) }
                == ["Saison 2026", "Mondial · en cours", "LEC Split 3"])
```

```swift
        #expect(lec.scope.map { SeasonLabels.scope($0, currentSeason: 2026) } == "LEC Split 3")
```

- [ ] **Step 2: Écrire les planches** `Tests/FailleTests/PerimetreSnapshotTests.swift`

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Page de KC sur deux saisons (spec périmètre §3.5) : « Saison 2026 », « Mondial · en cours », « LEC Split 3 »…
    /// « Saison 2025 », « LEC Summer 2025 »…
    @Test func perimeterTeamPage() async throws {
        let view = NavigationStack { TeamPageView(teamId: "kc") }
            .environment(AppStore(preview: .withPerimetre))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        expectNotBlank(try await Snapshot.write(view, named: "40-perimetre-equipe"))
    }

    /// Duel d'équipes : « 2025-2026 : KC 5 – 8 G2 » (vrais matchs), bilans de la saison de référence.
    @Test func perimeterTeamDuel() async throws {
        let view = NavigationStack { DuelView(left: .team("kc"), right: .team("g2")) }
            .environment(AppStore(preview: .withPerimetre))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        expectNotBlank(try await Snapshot.write(view, named: "40b-perimetre-duel-equipes"))
    }
}
```

- [ ] **Step 3: Libellés** — dans `App/Season/SeasonLabels.swift`, remplacer `scope(_:)` et ajouter (garder `season(year:)`, `tournament(_:)`) :

```swift
    /// Libellé d'un périmètre (`SeasonScope.label` est une valeur : l'année « 2026 » ou le slug d'un tournoi) : « Saison
    /// 2026 » ; un tournoi de N garde son nom court (« LEC Split 3 »), un tournoi de N − 1 garde son année (« Mondial
    /// 2025 ») ; un tournoi en cours : « Mondial · en cours ».
    static func scope(_ scope: SeasonScope, currentSeason: Int) -> String {
        if Int(scope.label) != nil { return season(year: scope.label) }
        var name = tournament(slug: scope.label)
        if let season = scope.season, season < currentSeason { name += " " + String(season) }
        return scope.isLive ? String(localized: "\(name) · en cours") : name
    }

    /// « Face-à-face 2025-2026 » (page équipe : le face-à-face couvre toute la fenêtre).
    static func headToHeadTitle(_ window: SeasonWindow) -> String {
        let (previous, current) = (String(window.previousSeason), String(window.currentSeason))
        return String(localized: "Face-à-face \(previous)-\(current)")
    }

    /// « 2025-2026 : KC 5 – 8 G2 » (duel d'équipes).
    static func duelHeadToHead(_ window: SeasonWindow, left: String, winsLeft: Int, winsRight: Int, right: String) -> String {
        let (previous, current) = (String(window.previousSeason), String(window.currentSeason))
        return String(localized: "\(previous)-\(current) : \(left) \(winsLeft) – \(winsRight) \(right)")
    }

    /// « Stats de la saison 2026 » (duels de joueurs).
    static func seasonStats(year: Int) -> String {
        String(localized: "Stats de la saison \(String(year))")
    }
```

Dans `league(slug:)`, ajouter `case "demacia_cup": return String(localized: "Demacia Cup")` ; dans `tournament(slug:)`, traiter « demacia cup » comme « first stand » (deux mots) :

```swift
        if words.count >= 2, words[0] == "first", words[1] == "stand" {
            leagueSlug = "first_stand"
            words.removeFirst(2)
        } else if words.count >= 2, words[0] == "demacia", words[1] == "cup" {
            leagueSlug = "demacia_cup"
            words.removeFirst(2)
        } else {
            leagueSlug = words.removeFirst()
        }
```

- [ ] **Step 4: Aperçu `perimetre`** — `Shared/Preview/SampleData.swift` : `case none, standard, collecting, loading, perimetre` et, après `withSeasonLoading` :

```swift
    /// Périmètre (spec périmètre) : vrais matchs KC-G2 2025-2026 et un match d'exemple de KC au Mondial 2026 en cours.
    static var withPerimetre: PreviewData {
        var data = standard
        data.season = .perimetre
        return data
    }
```

`App/Store/AppStore+Season.swift`, dans `seasonPreview` : ajouter `case .perimetre: SeasonSamples.perimetre`.

`App/Season/SeasonSamples.swift`, ajouter (valeurs réelles de `completed_kc_g2_2024_2026_reduced.json` et des listes de tournois du 15/10/2026, sauf le match du Mondial, d'exemple) :

```swift
    // MARK: Périmètre (spec périmètre §3.5) — fixture d'aperçu

    private static func lec(_ id: String, _ slug: String, _ start: String, _ end: String) -> TournamentRef {
        TournamentRef(id: id, slug: slug, startDate: start, endDate: end, leagueId: lecId)
    }

    /// Tournois réels de la LEC 2025-2026 et du Mondial 2026 (`getTournamentsForLeague`, 15/10/2026).
    static let perimetreTournaments = [
        TournamentRef(id: "115660540725177488", slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-11-15",
                      leagueId: worldsId),
        lec("115548681802226458", "lec_split_3_2026", "2026-07-23", "2026-09-20"),
        lec("115548668058343983", "lec_split_2_2026", "2026-03-27", "2026-06-07"),
        lec("115548424304940735", "lec_split_1_2026", "2026-01-16", "2026-03-01"),
        lec("113487526512660769", "lec_summer_2025", "2025-08-02", "2025-09-29"),
        lec("113487400974323999", "lec_spring_2025", "2025-03-29", "2025-06-08"),
        lec("113475994398658012", "lec_winter_2025", "2025-01-18", "2025-03-02"),
    ]

    /// Les 13 KC – G2 réels de 2025-2026 (id, tournoi, début, victoires de KC, de G2) : 5 – 8 sur la fenêtre.
    private static let kcG2: [(String, String, String, Int, Int)] = [
        ("115548681803406303", "115548681802226458", "2026-09-06T15:00:00Z", 1, 3),
        ("115548681803406287", "115548681802226458", "2026-07-26T17:30:00Z", 2, 1),
        ("115548668059589394", "115548668058343983", "2026-06-07T15:00:00Z", 2, 3),
        ("115548668059589358", "115548668058343983", "2026-05-23T15:00:00Z", 1, 3),
        ("115548668059589348", "115548668058343983", "2026-05-08T14:00:00Z", 0, 2),
        ("115548539108480899", "115548424304940735", "2026-03-01T16:00:00Z", 2, 3),
        ("115548539108415321", "115548424304940735", "2026-02-20T17:30:00Z", 0, 2),
        ("115548424308414170", "115548424304940735", "2026-01-25T19:30:00Z", 1, 0),
        ("113487569888189681", "113487526512660769", "2025-09-07T15:00:00Z", 1, 3),
        ("113487475359325357", "113487400974323999", "2025-05-11T17:00:00Z", 2, 1),
        ("113476054450624509", "113475994398658012", "2025-03-02T17:00:00Z", 3, 0),
        ("113476054450558947", "113475994398658012", "2025-02-24T17:00:00Z", 1, 3),
        ("113476054450558915", "113475994398658012", "2025-01-18T20:00:00Z", 1, 0),
    ]

    static var perimetre: SeasonPreview {
        func side(_ id: String, _ code: String, _ wins: Int) -> MatchTeam {
            MatchTeam(id: id, name: code, code: code, image: nil, result: MatchTeam.Result(outcome: nil, gameWins: wins))
        }
        var matches = kcG2.map { id, tournamentId, start, kc, g2 in
            SeasonMatch(id: id, tournamentId: tournamentId, leagueSlug: "lec", stageSlug: nil,
                        startTime: SampleData.date(start), blockName: nil, bestOf: 2 * max(kc, g2) - 1,
                        teams: [side("kc", "KC", kc), side("g2", "G2", g2)],
                        playedGameIds: (1...(kc + g2)).map { "\(id)-g\($0)" })
        }
        // Exemple (inventé, aperçu seulement) : un match de KC au Mondial 2026, pour la pilule « Mondial · en cours ».
        matches.append(SeasonMatch(id: "m-kc-blg-w26", tournamentId: "115660540725177488", leagueSlug: "worlds",
                                   stageSlug: "play_ins", startTime: SampleData.date("2026-10-15T09:00:00Z"),
                                   blockName: nil, bestOf: 1, teams: [side("kc", "KC", 1), side("blg", "BLG", 0)],
                                   playedGameIds: ["m-kc-blg-w26-g1"]))
        return SeasonPreview(tournaments: perimetreTournaments, matches: matches)
    }
```

- [ ] **Step 5: Page équipe** — `App/TeamPage/TeamPageView.swift` : `TeamPageContent` gagne `let window: SeasonWindow` (rempli par `make` avec `SeasonWindow(now: now)`, passé en dernier argument) ; les pilules :

```swift
                        Text(SeasonLabels.scope(scope, currentSeason: currentSeason))
```

avec `private func scopePills(_ scopes: [SeasonScope], currentSeason: Int)` appelée `scopePills(content.scopes, currentSeason: content.window.currentSeason)` ; le face-à-face :

```swift
                    TeamHeadToHeadCard(teamId: teamId, opponentId: opponentId, headToHead: headToHead,
                                       names: (content.code, store.teamCode(id: opponentId) ?? opponentId),
                                       title: SeasonLabels.headToHeadTitle(content.window))
```

(`headToHead` reste calculé sur `store.season.matches`, déjà bornés à la fenêtre ; la pilule par défaut, index 0, est la saison de référence : « Saison N » s'il y a des matchs en N, sinon « Saison N − 1 », par construction de `SeasonWindow.scopes`.)

`App/TeamPage/TeamPageSections.swift`, `TeamHeadToHeadCard` : ajouter `let title: String` après `names` et remplacer `SectionLabel(text: String(localized: "Face-à-face cette saison"))` par `SectionLabel(text: title)` ; doc comment : « Face-à-face sur la fenêtre (deux saisons) ».

- [ ] **Step 6: Page joueur** — `App/PlayerPage/PlayerPageView.swift` :

```swift
        let scopes = identity?.teamId.map { store.season.scopes(forTeam: $0, now: now) } ?? []
        let currentSeason = SeasonWindow(now: now).currentSeason
        // Sans pilule : la saison de référence, jamais « tout » (spec périmètre §3.5).
        let scope = scopes.isEmpty
            ? store.season.seasonScope(store.season.referenceSeason(forTeams: identity?.teamId.map { [$0] } ?? [], now: now))
            : scopes[min(scopeIndex, scopes.count - 1)]
```

`pills(scopes)` devient `pills(scopes, currentSeason: currentSeason)` avec `Text(SeasonLabels.scope(scope, currentSeason: currentSeason))`.

- [ ] **Step 7: Duels** — `App/Duel/DuelSection.swift` :
  - `DuelSection` gagne `@Environment(\.seasonNow) private var fixedNow` ; l'appel devient `memo.value(store: store, teams: teams, selectedGameId: selectedGameId, masked: masked, now: fixedNow ?? Date())` ; sous le `HStack` du titre, ajouter `Text(SeasonLabels.seasonStats(year: content.referenceSeason)).sora(.secondary).foregroundStyle(Palette.secondary)`.
  - `DuelSectionContent` gagne `let referenceSeason: Int`.
  - `DuelSectionMemo.value(store:teams:selectedGameId:masked:now: Date = Date())` : la clé gagne `let referenceSeason: Int` ; calcul :

```swift
        let reference = store.season.referenceSeason(forTeams: teams.compactMap(\.id), now: now)
        // … clé avec `referenceSeason: reference`
        let games = store.season.games(inSeason: reference)
        let entries = lines.map { line in
            DuelEntry(line: line, duel: Duel.players(left: line.left?.id ?? "", right: line.right?.id ?? "",
                                                     games: games, masked: hidden))
        }
        let built = DuelSectionContent(seasonMasked: hidden, lines: entries, referenceSeason: reference)
```

  (`DuelSection.lines` — compositions — reste sur toutes les games de la fenêtre.)

`App/Duel/DuelView.swift` : ajouter `@Environment(\.seasonNow) private var fixedNow` ; dans `body` :

```swift
        let now = fixedNow ?? Date()
        let teamIds: [String] = {
            switch (left, right) {
            case let (.team(a), .team(b)): [a, b]
            case let (.player(a), .player(b)):
                [a, b].compactMap { id in store.season.games.values.lazy.compactMap { $0.player(id)?.team.teamId }.first }
            default: []
            }
        }()
        let reference = store.season.referenceSeason(forTeams: teamIds, now: now)
```

`ScreenHeader(String(localized: "Duel"), subtitle: SeasonLabels.seasonStats(year: reference))` ; `Duel.players(left: a, right: b, games: store.season.games(inSeason: reference), masked: store.seasonMasked)`.

`App/Duel/DuelBars.swift`, `TeamDuelCard.body` :

```swift
        let now = fixedNow ?? Date()
        let window = SeasonWindow(now: now)
        let reference = store.season.referenceSeason(forTeams: [leftId, rightId], now: now)
        let left = season(leftId, reference: reference, now: now, masked: masked)
        let right = season(rightId, reference: reference, now: now, masked: masked)
        let h2h = SeasonStats.headToHead(leftId, rightId, matches: store.season.matches, masked: masked)
        let codes = (store.teamCode(id: leftId) ?? leftId, store.teamCode(id: rightId) ?? rightId)
        VStack(alignment: .leading, spacing: 12) {
            Text(SeasonLabels.duelHeadToHead(window, left: codes.0, winsLeft: h2h.winsA, winsRight: h2h.winsB,
                                             right: codes.1)).sora(.headline)
            // … le reste inchangé
```

et

```swift
    /// Bilans et moyennes de la saison de référence des deux équipes (spec périmètre §3.5).
    private func season(_ teamId: String, reference: Int, now: Date, masked: Set<String>) -> TeamSeason? {
        guard let scope = store.season.scopes(forTeam: teamId, now: now).first(where: { $0.label == String(reference) }),
              !scope.tournamentIds.isEmpty else { return nil }
        return store.season.teamSeason(teamId, scope: scope, masked: masked, now: now)
    }
```

(doc comment de `TeamDuelCard` : « bilans et moyennes de la saison de référence ; face-à-face sur la fenêtre ».)

- [ ] **Step 8: Vérifications locales**

Run: `git diff --check && python3 scripts/strings-check.py`
Expected: `git diff --check` muet ; strings-check signale **exactement** les clés nouvelles de D4, à ajouter par D6 : `%@ · en cours`, `Face-à-face %@-%@`, `%@-%@ : %@ %lld – %lld %@`, `Stats de la saison %@`, `Demacia Cup`. Toute autre clé manquante est une erreur à corriger.
Run: `grep -rn "SeasonLabels.scope(scope)" App Tests`
Expected: aucune occurrence (toutes passent `currentSeason:`).
Tests hébergés et planches : CI iOS à la fin du lot ; attendu PASS, planches `40-perimetre-equipe.png` et `40b-perimetre-duel-equipes.png` non blanches.

- [ ] **Step 9: Commit**

```bash
git add App/Season/SeasonLabels.swift App/Season/SeasonSamples.swift Shared/Preview/SampleData.swift \
        App/Store/AppStore+Season.swift App/TeamPage/TeamPageView.swift App/TeamPage/TeamPageSections.swift \
        App/PlayerPage/PlayerPageView.swift App/Duel/DuelSection.swift App/Duel/DuelView.swift App/Duel/DuelBars.swift \
        Tests/FailleTests/PerimetreScreensTests.swift Tests/FailleTests/PerimetreSnapshotTests.swift \
        Tests/FailleTests/TeamPageTests.swift
git commit -m "feat(app): pages équipe et joueur, duels sur deux saisons — pilules, saison de référence, face-à-face 2025-2026" \
           -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task D5: Accueil, calendrier, classements, À propos (appli)

Spec §3.1 (pages `older`), §3.5 (Accueil, calendrier, classements, À propos), §3.6 (libellés de D5), §6.2 tests 21 et 22 (planche calendrier). Modèle suggéré : standard.

**Files:**
- Create: `App/Season/WindowTexts.swift`
- Create: `Tests/FailleTests/PerimetreCalendarTests.swift`
- Modify: `App/Home/HomeStore.swift`
- Modify: `App/Calendar/CalendarModel.swift` (`CalendarEvents`)
- Modify (vues) : `App/Home/HotPlayersSection.swift`, `App/Calendar/SeasonCalendarView.swift`, `App/Standings/StandingsView.swift`, `App/Settings/SettingsView.swift` (`AboutView`)

**OWNERSHIP (vague 4, en parallèle de D4)** : D5 seul modifie ces fichiers. N'appelle de `SeasonLabels` que `season(year:)` (existant, **non modifié** : `SeasonLabels.swift` appartient à D4). Ne touche pas `SeasonStore.swift` (D3, vague précédente), ni `Localizable.xcstrings` (D6).

**Interfaces:**
- Consumes (D1, D3) : `SeasonWindow(now:)`, `window.firstMonth(calendar:)`, `window.contains(date:)`, `window.previousSeason`, `window.currentSeason`, `store.season.referenceSeason(forTeams:now:)`, `store.season.matches(inSeason:)`, `store.season.games(inSeason:)`, `store.season.isOutsideWindow(tournamentId:)`.
- Produces :

```swift
enum WindowTexts {
    static func calendarFloor(_ window: SeasonWindow) -> String     // « Faille ne remonte pas avant janvier 2025 »
    static func standingsTooOld(_ window: SeasonWindow) -> String   // « Classement trop ancien · Faille garde les saisons 2025 et 2026 »
    static func dataScope(_ window: SeasonWindow) -> String         // « Données : tournois en cours, saisons 2026 et 2025 »
}
enum CalendarEvents {
    static func merged(pages: [SchedulePageResult], schedule: [MatchEvent], live: [MatchEvent]?,
                       window: SeasonWindow? = nil) -> [MatchEvent]
    static func canGoBack(from month: Date, window: SeasonWindow, calendar: Calendar) -> Bool
    static func mayLoad(month: Date, window: SeasonWindow, calendar: Calendar) -> Bool
}
struct SeasonCalendarView { init(initialMonth: Date? = nil) }
```

- [ ] **Step 1: Écrire les tests qui échouent** `Tests/FailleTests/PerimetreCalendarTests.swift`

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

private func paris() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.locale = Locale(identifier: "fr_FR")
    return calendar
}

private let window = SeasonWindow(now: LoLDate.parse("2026-10-15T15:05:00Z")!)

private func event(_ id: String, _ start: String) -> MatchEvent {
    let league = LeagueRef(id: "98767991302996019", slug: "lec", name: "LEC", image: nil)
    let match = MatchInfo(id: id, teams: [], strategy: Strategy(type: "bestOf", count: 3), games: nil)
    return MatchEvent(startTime: LoLDate.parse(start)!, state: .completed, type: "match", blockName: "Semaine 1",
                      league: league, match: match, streams: [])
}

/// Spec périmètre §6.2 test 21 : calendrier borné à janvier de N − 1 (fuseau Europe/Paris).
struct PerimetreCalendarTests {
    @Test func theCalendarStopsAtJanuaryOfThePreviousSeason() {
        let calendar = paris()
        #expect(window.firstMonth(calendar: calendar) == LoLDate.parse("2024-12-31T23:00:00Z")!)
        #expect(!CalendarEvents.canGoBack(from: LoLDate.parse("2025-01-15T12:00:00Z")!, window: window, calendar: calendar))
        #expect(CalendarEvents.canGoBack(from: LoLDate.parse("2025-02-01T12:00:00Z")!, window: window, calendar: calendar))
        #expect(!CalendarEvents.mayLoad(month: LoLDate.parse("2024-12-15T12:00:00Z")!, window: window, calendar: calendar))
        #expect(CalendarEvents.mayLoad(month: LoLDate.parse("2025-01-15T12:00:00Z")!, window: window, calendar: calendar))
    }

    @Test func mergedDropsMatchesBeforeTheWindow() {
        let merged = CalendarEvents.merged(pages: [], schedule: [event("vieux", "2024-12-31T23:00:00Z"),
                                                                 event("neuf", "2025-01-01T00:00:00Z")],
                                           live: nil, window: window)
        #expect(merged.map(\.id) == ["neuf"])
        // Sans fenêtre (chargement des pages) : rien n'est écarté.
        #expect(CalendarEvents.merged(pages: [], schedule: [event("vieux", "2024-12-31T23:00:00Z")], live: nil).count == 1)
    }

    @Test func windowTexts() {
        #expect(WindowTexts.calendarFloor(window) == "Faille ne remonte pas avant janvier 2025")
        #expect(WindowTexts.standingsTooOld(window) == "Classement trop ancien · Faille garde les saisons 2025 et 2026")
        #expect(WindowTexts.dataScope(window) == "Données : tournois en cours, saisons 2026 et 2025")
    }
}

extension ApercuTests {
    /// Spec périmètre §6.2 test 22 : janvier 2025, flèche « mois précédent » désactivée, pied de page.
    @Test func perimeterCalendarJanuary() async throws {
        let view = NavigationStack { SeasonCalendarView(initialMonth: SampleData.date("2025-01-15T12:00:00Z")) }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        expectNotBlank(try await Snapshot.write(view, named: "41-perimetre-calendrier-janvier"))
    }
}
```

- [ ] **Step 2: Textes de la fenêtre** `App/Season/WindowTexts.swift`

```swift
import Foundation
import LoLKit

/// Textes du périmètre des données (spec périmètre §3.6) hors pages d'équipe et duels (`SeasonLabels`) : calendrier,
/// classements, À propos. Les années viennent toujours de `SeasonWindow`, interpolées en texte (jamais « 2 025 »).
enum WindowTexts {
    static func calendarFloor(_ window: SeasonWindow) -> String {
        String(localized: "Faille ne remonte pas avant janvier \(String(window.previousSeason))")
    }

    static func standingsTooOld(_ window: SeasonWindow) -> String {
        let (previous, current) = (String(window.previousSeason), String(window.currentSeason))
        return String(localized: "Classement trop ancien · Faille garde les saisons \(previous) et \(current)")
    }

    static func dataScope(_ window: SeasonWindow) -> String {
        let (current, previous) = (String(window.currentSeason), String(window.previousSeason))
        return String(localized: "Données : tournois en cours, saisons \(current) et \(previous)")
    }
}
```

- [ ] **Step 3: `CalendarEvents`** (`App/Calendar/CalendarModel.swift`) — `merged` gagne `window` et deux gardes :

```swift
    /// Sans doublon : le direct fait foi, puis le calendrier, puis les pages ; avec `window`, sans les matchs d'avant le
    /// périmètre (`SeasonWindow.contains(date:)`).
    static func merged(pages: [SchedulePageResult], schedule: [MatchEvent], live: [MatchEvent]?,
                       window: SeasonWindow? = nil) -> [MatchEvent] {
        var byId: [String: MatchEvent] = [:]
        for event in pages.flatMap(\.events) + schedule + (live ?? []) {
            byId[event.id] = event
        }
        return byId.values
            .filter { event in window.map { $0.contains(date: event.startTime) } ?? true }
            .sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
    }

    /// Flèche « mois précédent » : seulement après le premier mois du périmètre.
    static func canGoBack(from month: Date, window: SeasonWindow, calendar: Calendar) -> Bool {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return false }
        return start > window.firstMonth(calendar: calendar)
    }

    /// Une page `older` / `newer` ne se lit que pour un mois du périmètre.
    static func mayLoad(month: Date, window: SeasonWindow, calendar: Calendar) -> Bool {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return false }
        return start >= window.firstMonth(calendar: calendar)
    }
```

- [ ] **Step 4: Calendrier** (`App/Calendar/SeasonCalendarView.swift`) :
  - `init(initialMonth: Date? = nil) { _month = State(initialValue: initialMonth) }` (les autres `@State` gardent leur valeur par défaut).
  - Dans `body` : `let window = SeasonWindow(now: now)` ; `let all = CalendarEvents.merged(pages: pages, schedule: store.schedule, live: store.live, window: window)` ; `let canGoBack = CalendarEvents.canGoBack(from: shownMonth, window: window, calendar: calendar)` ; le bouton « Mois précédent » reçoit `.disabled(!canGoBack)` ; juste sous `MonthGrid(...)` :

```swift
                if !canGoBack {
                    NoteCard(icon: .calendar, text: WindowTexts.calendarFloor(window))
                }
```

  - `loadIfNeeded(_:)` commence par `guard CalendarEvents.mayLoad(month: month, window: SeasonWindow(now: fixedNow ?? Date()), calendar: calendar) else { return }` ; son `CalendarEvents.merged(...)` interne reste **sans** `window` (le besoin de page se juge sur tout ce qui est lu, sinon janvier relirait une page à chaque visite).

- [ ] **Step 5: Classements** (`App/Standings/StandingsView.swift`) — en tête du `VStack`, après `ScreenHeader` :

```swift
                if store.season.isOutsideWindow(tournamentId: tournamentId) {
                    // Garde (inatteignable par les liens existants) : un tournoi hors fenêtre n'est jamais lu.
                    NoteCard(icon: .standings, text: WindowTexts.standingsTooOld(SeasonWindow(now: Date())))
                } else if let standings = store.season.standings[tournamentId] {
```

(le reste de la chaîne `if` inchangé) ; la `.task` commence par `guard !store.season.isOutsideWindow(tournamentId: tournamentId) else { attempted = true; return }`.

- [ ] **Step 6: Accueil** — `App/Home/HomeStore.swift` : les entrées de saison passent à la saison de référence, **matchs et games ensemble** (anti-spoiler : le masque de chaque game vient des matchs fournis) :

```swift
    func homeInputs(now: Date, calendar: Calendar = .current) -> HomeInputs {
        // Saison de référence (spec périmètre §3.5) : « Saison 2026 » des joueurs en forme, séries et record de kills de
        // l'activité, revanches de « À ne pas rater » ; même saison pour les matchs et les games.
        let reference = season.referenceSeason(forTeams: [], now: now)
        let games = Dictionary(season.games(inSeason: reference).map { ($0.gameId, $0) }, uniquingKeysWith: { first, _ in first })
        return HomeInputs(feed: HomeFeed.Input(now: now, calendar: calendar, schedule: withoutMaskedUpcoming(schedule),
                                               live: live.map { withoutMaskedUpcoming($0) }, follows: follows,
                                               revealed: settings.revealedMatchIds,
                                               revealedStandings: settings.revealedStandingIds,
                                               seasonMatches: season.matches(inSeason: reference),
                                               games: games, standings: season.standings, catalog: catalog),
                          progress: season.progress, isLoaded: season.isLoaded)
    }

    func mustWatchPicks(limit: Int, now: Date = Date(), calendar: Calendar = .current) -> [MustWatchPick] {
        let reference = season.referenceSeason(forTeams: [], now: now)
        return MustWatch.rank(schedule: withoutMaskedUpcoming(schedule), follows: follows,
                              revealed: settings.revealedMatchIds, revealedStandings: settings.revealedStandingIds,
                              standings: season.standings, seasonMatches: season.matches(inSeason: reference),
                              catalog: catalog, now: now, calendar: calendar, limit: limit)
    }
```

(Écart assumé : « Semaine » et l'activité récente lisent aussi la saison de référence ; ils ne diffèrent de « toute la fenêtre » que la première semaine de janvier, quand un tournoi de décembre de N − 1 joue encore.)

`App/Home/HotPlayersSection.swift` : ajouter `@Environment(\.seasonNow) private var fixedNow` ; la pilule « Saison » devient :

```swift
                    pill(SeasonLabels.season(year: String(store.season.referenceSeason(forTeams: [], now: fixedNow ?? Date()))),
                         selected: key.period == .season) {
                        key = HotPlayersKey(period: .season, metric: key.metric)
                    }
```

- [ ] **Step 7: À propos** (`App/Settings/SettingsView.swift`, `AboutView.body`) — juste après `block("Données", …)` :

```swift
                Text(WindowTexts.dataScope(SeasonWindow(now: Date())))
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
```

- [ ] **Step 8: Vérifications locales**

Run: `git diff --check && python3 scripts/strings-check.py`
Expected: `git diff --check` muet ; strings-check signale exactement les 3 clés de D5, à ajouter par D6 : `Faille ne remonte pas avant janvier %@`, `Classement trop ancien · Faille garde les saisons %@ et %@`, `Données : tournois en cours, saisons %@ et %@`.
Tests hébergés et planche `41-perimetre-calendrier-janvier.png` : CI iOS à la fin du lot ; attendu PASS.

- [ ] **Step 9: Commit**

```bash
git add App/Season/WindowTexts.swift App/Home/HomeStore.swift App/Home/HotPlayersSection.swift \
        App/Calendar/CalendarModel.swift App/Calendar/SeasonCalendarView.swift App/Standings/StandingsView.swift \
        App/Settings/SettingsView.swift Tests/FailleTests/PerimetreCalendarTests.swift
git commit -m "feat(app): Accueil sur la saison de référence, calendrier borné à janvier N − 1, classement trop ancien, À propos" \
           -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task D6: Chaînes fr/en et intégration

Spec §3.6, §6.2 test 22 (`strings-check.py` vert), §7 critères de fin. Modèle suggéré : cheap.

**Files:**
- Modify: `Resources/Localizable.xcstrings`
- Modify: `docs/superpowers/notes/2026-10-14-checklist-iphone.md` (section G)

**OWNERSHIP (vague 5)** : seule tâche ; seul éditeur du catalogue de chaînes de tout le lot.

**Interfaces:**
- Consumes (D4, D5) : les 8 clés listées ci-dessous, produites par `SeasonLabels` et `WindowTexts`.
- Produces : catalogue complet ; checklist iPhone section G.

- [ ] **Step 1: Constater les clés manquantes**

Run: `python3 scripts/strings-check.py`
Expected: FAIL, exactement ces 8 clés manquantes : `%@ · en cours`, `Face-à-face %@-%@`, `%@-%@ : %@ %lld – %lld %@`, `Stats de la saison %@`, `Demacia Cup`, `Faille ne remonte pas avant janvier %@`, `Classement trop ancien · Faille garde les saisons %@ et %@`, `Données : tournois en cours, saisons %@ et %@`.

- [ ] **Step 2: Ajouter les clés** — `python3 scripts/strings-check.py --add-missing` (ajoute les clés, anglais vide), puis remplir chaque `"value": ""` anglais de ces entrées et passer leur `"state"` à `"translated"`, `"extractionState": "manual"` comme les entrées voisines :

| Clé (fr) | en |
|---|---|
| `%@ · en cours` | `%@ · live` |
| `Face-à-face %@-%@` | `Head-to-head %@–%@` |
| `%@-%@ : %@ %lld – %lld %@` | `%@–%@: %@ %lld – %lld %@` |
| `Stats de la saison %@` | `%@ season stats` |
| `Demacia Cup` | `Demacia Cup` |
| `Faille ne remonte pas avant janvier %@` | `Faille doesn't go back before January %@` |
| `Classement trop ancien · Faille garde les saisons %@ et %@` | `Standings too old · Faille keeps the %@ and %@ seasons` |
| `Données : tournois en cours, saisons %@ et %@` | `Data: live tournaments, %@ and %@ seasons` |

Forme d'une entrée (identique aux voisines, ex. `"Saison %@"`) :

```json
    "%@ · en cours": {
      "extractionState": "manual",
      "localizations": {
        "en": {
          "stringUnit": {
            "state": "translated",
            "value": "%@ · live"
          }
        }
      }
    },
```

- [ ] **Step 3: Vérifier**

Run: `python3 scripts/strings-check.py`
Expected: PASS (code de sortie 0).
Run: `python3 -c "import json; json.load(open('Resources/Localizable.xcstrings', encoding='utf-8'))"`
Expected: aucune erreur.

- [ ] **Step 4: Checklist iPhone** — ajouter à la fin de `docs/superpowers/notes/2026-10-14-checklist-iphone.md`, avant « ### Vérifications sur appareil de la relecture finale » :

```markdown
## G. Périmètre des données (saisons N et N − 1, tournois en cours)

30. **Page équipe (KC)** : pilules « Saison 2026 », « Mondial · en cours », « LEC Split 3 »… puis « Saison 2025 », « LEC Summer 2025 », « Mondial 2025 » si joué ; la pilule par défaut est « Saison 2026 ». Face-à-face titré « Face-à-face 2025-2026 ».
31. **Duel d'équipes KC – G2** : « 2025-2026 : KC 5 – 8 G2 » (une fois la collecte des deux saisons faite) ; duel de joueurs : « Stats de la saison 2026 ».
32. **Calendrier** : reculer jusqu'en janvier 2025 : flèche « mois précédent » grisée, « Faille ne remonte pas avant janvier 2025 » ; aucun match de 2024.
33. **Réglages > À propos** : ligne « Données : tournois en cours, saisons 2026 et 2025 ».
34. **Mise à jour depuis la version précédente** : au premier lancement, rien ne disparaît des saisons 2025-2026 ; les suivis, réglages et révélations restent ; un Détail ouvert sur un match de 2024 (calendrier) n'a plus son cache (normal).
35. **Anglais** : « Mondial · live », « Head-to-head 2025–2026 », « Data: live tournaments, 2026 and 2025 seasons ».
```

- [ ] **Step 5: Relecture ciblée « rien d'avant 2025 »**

Run: `grep -rnE "\b20(24|25)\b" App LoLKit/Sources --include=*.swift | grep -v "^\S*:\s*///" | grep -v "App/Season/SeasonSamples.swift"`
Expected: aucune ligne de code (seulement des commentaires, exclus ; `SeasonSamples.swift` est une fixture d'aperçu).
Run: `grep -rn "store.season.games\b\|store.season.matches\b\|season.games.values\|season.matches\b" App --include=*.swift`
Expected : chaque appel restant lit des données déjà bornées par `SeasonStore` (fenêtre) ; ceux qui disent « saison » sans année passent par `games(inSeason:)` / `matches(inSeason:)` / `scopes(forTeam:)` (Accueil, duels, page joueur). Lister le résultat dans le message de commit si un appel est volontairement laissé sur la fenêtre (face-à-face, noms d'équipe, compositions).

- [ ] **Step 6: Commit, puis CI complète**

```bash
git add Resources/Localizable.xcstrings docs/superpowers/notes/2026-10-14-checklist-iphone.md
git commit -m "chore(strings): textes fr/en du périmètre des données ; checklist iPhone section G" \
           -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

Puis (contrôleur) : CI `lolkit.yml`, `ios.yml` (tests hébergés 18-22 + planches 40, 40b, 41), `strings.yml` vertes ; IPA ; relecture ciblée.

---

## Self-Review

**1. Couverture des 22 tests d'acceptation (spec §6)**

| Test | Tâche | Où |
|---|---|---|
| 1 `SeasonWindow(today:)` N, N − 1, `startDay` | D1 | `SeasonWindowTests.todayGivesTheCurrentAndPreviousSeasons` |
| 2 Mondial `[worlds_2026, worlds_2025]`, 9 dehors | D1 | `worldsKeepsTwoTournaments` |
| 3 LEC 6 / 28, `eu_lcs_summer_2013` | D1 | `lecKeepsSixTournaments` |
| 4 LCK 6 / 31, `champions_winter_2014` saison 2013 | D1 | `lckKeepsSixAndStraddlingCountsByStart` |
| 5 EMEA Masters 7, été 2026 actif | D1 | `emeaMastersSummerIsLive` |
| 6 Demacia Cup 1 actif, MSI 2, First Stand 2 | D1 | `internationalsInTheWindow` |
| 7 fenêtre du 05/01/2027 | D1 | `theWindowMovesOnNewYear` |
| 8 cas synthétiques §2.3 (sans début, sans dates, à cheval, liveOverride, garde-fou 400 j, upcoming, bascule UTC, game sans tournoi) | D1 | `edgeCases` (+ `outsideGames` pour la game) |
| 9 `referenceSeason` | D1 | `referenceSeason` |
| 10 pilules de KC (10, puis 11 avec le Mondial en cours) | D1 (+ D3 au niveau du store, D4 libellés) | `scopesOfKarmineCorp`, `SeasonPerimetreTests.theStoreOnlyExposesTheWindow`, `PerimetreScreensTests.karmineCorpHasBothSeasons` |
| 11 `outsideGameIds` | D1 | `outsideGames` |
| 12 `outsideTournamentIds` | D1 | `outsideTournaments` |
| 13 bilans KC / G2 par saison | D1 | `SeasonStatsTests.kcAndG2RecordsPerSeason` |
| 14 face-à-face 2-6, 3-2, 5-8, 13 matchs, 06/09/2026 | D1 | `SeasonStatsTests.kcG2HeadToHeadOverTheWindow` |
| 15 221 jobs (113 groupe 1, 108 groupe 6), pas de `worlds_2024`, étape `playoffs` en groupe 2 | D2 | `kcTwoSeasonsComeInPriorityOrder`, `liveCompleteTournamentStageComesFirst` (+ `historyGroupsComeAfterTheCurrentSeason`) |
| 16 `evictions` | D2 | `diskBudgetDropsOutsideGamesThenThePreviousSeason` |
| 17 `PublicInitTests` | D1 + D2 | `perimeterTypes`, `crawlWantedWithPerimeter` |
| 18 purge et migration | D3 | `theFirstLaunchPurgesEverythingBefore2025Once` |
| 19 collecte sur fixtures | D3 | `aFullPassForKarmineCorpNeverTouches2024` |
| 20 store | D3 | `theStoreOnlyExposesTheWindow` |
| 21 calendrier | D5 | `PerimetreCalendarTests` (2 tests) |
| 22 planches + strings-check | D4, D5, D6 | `40-perimetre-equipe`, `40b-perimetre-duel-equipes`, `41-perimetre-calendrier-janvier` ; D6 Step 3 |

Spec §3 sans test dédié mais couvert : énumération des ligues complètes et prédécesseurs (§2.1, §3.1 → D3 `planningEnumeratesCompleteLeaguesAndPredecessors`) ; appartenance par tournoi (§3.4 → D3 `gamesBelongToTheSeasonOfTheirTournament`) ; À propos, classement trop ancien (§3.5 → D5, textes testés par `windowTexts`) ; Accueil (§3.5 → D5 Step 6, vérifié par les tests `HomeTests` existants et la planche Accueil existante) ; onboarding (`currentTournamentId` lit les tournois filtrés → D3 test 20). Hors périmètre §5 respecté : aucune requête Leaguepedia, aucune énumération des 51 ligues, `League.internationalSlugs` et `revealedMatchIds` intacts.

**2. Placeholders** : aucun « TBD » / « à compléter » ; chaque étape de code a son code ; les « corps existant inchangé » désignent du code existant à ne pas modifier, avec la ligne à ajouter en tête.

**3. Cohérence des types** : `SeasonWindow.scopeSeason(of:)` (D1) est utilisé par D3 (`season(ofTournament:)`, `seasonScope`, `referenceSeason`) ; `CrawlWanted.liveCompleteStageMatchIds` / `allowedTournamentIds` / `previousSeasonTournamentIds` / `completeTournamentIds` (D2) ont les mêmes noms dans D3 `SeasonPlanning.wanted` et ses tests ; `CrawlPlanner.evictions(_:followedTeamIds:allowedTournamentIds:previousSeasonTournamentIds:limit:)` identique en D2 et D3 ; `SeasonStore.referenceSeason(forTeams:now:)`, `games(inSeason:)`, `matches(inSeason:)`, `seasonScope(_:)`, `isOutsideWindow(tournamentId:)` (D3) sont appelés tels quels par D4 et D5 ; `SeasonLabels.scope(_:currentSeason:)` remplace `scope(_:)` partout (vues D4 + `TeamPageTests`) ; `DuelSectionMemo.value(...now:)` a un `now` par défaut (appel existant inchangé). Années : toujours `String(…)` dans les `String(localized:)`, clés `%@` attendues par D6.
