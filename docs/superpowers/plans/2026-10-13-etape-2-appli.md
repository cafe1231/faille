# Étape 2 — L'appli : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** construire la vraie appli Faille (iPhone + iPad, iOS 26) : onglet Matchs (une carte Vitrail par équipe suivie), onglet Équipes (recherche, suivi, anti-spoiler, couleur d'équipe, ligues en pilules), écran Détail d'un match (stats d'équipe et des joueurs), Réglages, cache disque et rafraîchissements, dans la DA Échap (Abysse, Liquid Glass, Sora, icônes au trait). Terminé quand Dan suit une équipe et voit ses matchs sur son iPhone (spec §13, étape 2).

**Architecture :** toute la logique pure nouvelle (politique de rafraîchissement, cache horodaté, choix du groupe d'apps, réglages, annuaire des équipes, formats, alpha prémultiplié, annulation réseau) va dans LoLKit, avec des tests Swift Testing lancés sur Windows. L'appli SwiftUI (Swift 6) reste fine : un `AppStore` `@MainActor @Observable` possède le `LoLClient`, lit et écrit des fichiers JSON dans le conteneur du groupe d'apps résolu à l'exécution, et rafraîchit selon `RefreshPolicy` tant que la scène est active. La CI macOS compile l'IPA et, sur simulateur, lance les tests de l'appli et rend les écrans en PNG (artefact `Faille-apercus`) pour les voir depuis Windows.

**Tech Stack :** Swift 6.2, SwiftUI iOS 26 (Liquid Glass `glassEffect`, `TabView` + `Tab`), Observation, Swift Testing, XcodeGen, GitHub Actions `macos-26` (Xcode 26), Docker `swift:6.2`, AltServer.

**Spec :** `docs/superpowers/specs/2026-10-13-faille-design.md` (§3, §4.1, §4.4, §5, §8, §9, §10, §11.3, §13). Maquettes : `docs/maquettes/ecrans-appli.html` (option **B** pour l'onglet Matchs).

## Global Constraints

- iOS minimum **26.0** ; iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) ; nom affiché **Faille** ; version **0.1.0** (`MARKETING_VERSION` et `CFBundleShortVersionString` littéral `"0.1.0"` dans les deux cibles), build `1`.
- Identifiants de base : appli `com.cafe1231.faille`, extension `com.cafe1231.faille.widgets`, tests `com.cafe1231.faille.tests`, groupe configuré `group.com.cafe1231.faille`. **Aucun code ne suppose un bundle ID ni un nom de groupe** : AltServer les renomme en `….<TEAMID>` ; le groupe est résolu à l'exécution par `AppGroup` (profil embarqué → `ALTAppGroups` → nom configuré ; premier dont `containerURL` n'est pas nil ; sinon Application Support de l'appli).
- Langage : appli et tests de l'appli en **Swift 6** (concurrence stricte) ; extension `FailleWidgets` en **Swift 5** jusqu'à l'étape 3 ; tout fichier de `Shared/` compile dans les deux modes ; LoLKit reste `swift-tools-version: 6.2`.
- LoLKit n'importe que `Foundation`. Toute logique pure nouvelle y va, avec des tests Swift Testing, lancés par `bash scripts/lolkit.sh test` (Docker Desktop doit tourner).
- **Aucune dépendance externe** (seul paquet : LoLKit, local, `packages: LoLKit: path: LoLKit`).
- Le code iOS ne se compile **qu'en CI** (Dan est sous Windows, sans Xcode) : vérification d'une tâche iOS = commit, `git push origin main`, `gh run watch --exit-status <id>` sur le workflow `iOS`, logs d'échec par `gh run view <id> --log-failed`.
- Cadences (spec §4.1) : ligues et équipes 24 h ; calendrier 30 min + à chaque ouverture ; direct 60 s ; flux `window` 10 s **seulement** tant que l'écran Détail est affiché, et à la cadence du direct (60 s) pour les stats des cartes des matchs en direct suivis et non masqués.
- Anti-spoiler : on n'affiche jamais un score, un numéro de game, des stats ou un vainqueur sans passer par `SpoilerPolicy.isMasked`, `Presenter.scoreLine` ou `LiveMatchBuilder.state` (spec §8).
- Une équipe d'un match se reconnaît par `MatchTeam.isSame(as:)` (id, sinon nom, sinon logo) — **jamais par le code seul**.
- Stockage : fichiers JSON dans `<conteneur>/Faille/` : `follows.json`, `settings.json`, `cache-leagues.json`, `cache-teams.json`, `cache-schedule.json`, `cache-live.json`, et `logos/logo-<fnv1a64>.png`. Encodage `JSONEncoder()` / `JSONDecoder()` par défaut.
- DA (spec §9) : fond `#0B1020`, nappes `rgba(60,140,255,0.18)` (haut gauche) et `rgba(0,220,200,0.14)` (bas droite) ; texte `#E9EEFB`, secondaire `#94A0BF`, accent `#6FD3FF` ; coins 28 pt (cartes) et 22 pt (éléments internes) ; Sora (variable, axe `wght`) titres 32 pt 700 interlettrage −1,28 pt, corps 15 pt, secondaire 12 pt, étiquettes 11 pt capitales interlettrage 0,88 pt ; icônes au trait 1,8 sur grille 24, **jamais d'emoji** ; mode sombre forcé.
- Bandeau d'erreur (spec §10) : exactement `lolesports ne répond pas · màj HH:MM` (ou `lolesports ne répond pas` sans mise à jour connue).
- Étape 2 = **pas de widgets ni de Live Activity** : la sonde de l'étape 0 (`Widgets/`) reste compilée ; pas de bouton « Épingler » (étape 4).
- Textes de l'interface en français ; identifiants de code en anglais ; commentaires en français. Fins de ligne LF.
- Commits avec l'adresse `45066362+cafe1231@users.noreply.github.com` (déjà configurée) ; chaque message se termine par un second `-m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Pousser sur `main` est autorisé.

## Décisions prises par ce plan (au-delà de la spec)

- Annulation réseau : `URLSessionTransport` devient annulable (helper `CancellableCall` dans LoLKit, testé) — annuler la boucle annule les requêtes en vol.
- Stats des cartes de l'onglet Matchs : rafraîchies à la cadence du direct (60 s), pas à 10 s.
- Stats d'une game **terminée** : `window` demandé avec `startingTime = maintenant − 60 s` (le flux renvoie alors ses dernières frames, comme la fixture `window_finished`) ; sinon message « Stats de cette game indisponibles ».
- Aperçus PNG : rendus avec `drawHierarchy` dans une vraie fenêtre de l'appli hôte, **pas** avec `ImageRenderer` (qui ne rend ni `ScrollView`, ni la barre d'onglets, ni le Liquid Glass).
- La sonde widget affiche les codes des équipes suivies lus dans le groupe d'apps (preuve sur l'iPhone que le stockage partagé marche avant l'étape 3).
- Sora : un seul fichier variable ; la graisse est appliquée par l'axe `wght` (`kCTFontVariationAttribute`), pas par `.fontWeight` (peu fiable sur une police variable embarquée).
- Pilules de ligues : seulement les ligues qui ont au moins une équipe ; pour Mondial / MSI / First Stand (ligue d'attache de personne), les équipes vues dans leur calendrier. Recherche limitée aux équipes actives.
- Un fichier JSON illisible est mis de côté (`.illisible`) au lieu d'être écrasé — les équipes suivies ne se perdent jamais.
- Pas d'icône d'appli à l'étape 2 (catalogue sans `AppIcon`) ; bouton retour système.
- Sora et le catalogue d'icônes ne sont embarqués que dans l'appli ; l'extension les recevra à l'étape 3 (le code DA de `Shared/` compile déjà dans les deux cibles).
- Sur iPad, le contenu des écrans est limité à 640 pt de large et centré.

## Structure des fichiers

```
LoLKit/Sources/LoLKit/
├─ API/CancellableCall.swift         (T3) relie l'annulation d'une Task Swift à une opération à rappel
├─ API/HTTPTransport.swift           (T3, modifié) URLSessionTransport annulable
├─ Cache/Cached.swift                (T1) valeur + date d'obtention ; SchedulePage (calendrier + ligues demandées)
├─ Cache/RefreshPolicy.swift         (T1) DataKind, RefreshInput, RefreshPolicy : quand relire quoi
├─ Storage/AppGroupResolver.swift    (T2) ordre et choix des groupes d'apps candidats
├─ Storage/AppSettings.swift         (T2) réglages enregistrés (mode Live Activity, matchs révélés), décodage tolérant
├─ Storage/LogoFileName.swift        (T2) nom de fichier stable d'un logo (FNV-1a 64)
├─ Color/Premultiplied.swift         (T2) TeamColor.unpremultiplied
├─ Presentation/ImageURL.swift       (T2) URL d'image forcée en https (ATS)
├─ Presentation/AppFormat.swift      (T4) heure, bandeau, chrono, score, KDA, drakes, rôles, champions, sous-titres
├─ Follow/TeamDirectory.swift        (T4) recherche, équipes d'une ligue, ligues en pilules
├─ Follow/DisplayOrder.swift         (T4) ordre d'affichage : équipe suivie à gauche
└─ Models/EventDetails+Event.swift   (T4) EventDetails depuis getLive, statsDisabled, currentGame
LoLKit/Tests/LoLKitTests/
├─ CacheTests.swift, RefreshPolicyTests.swift                     (T1)
├─ StorageTests.swift, ImageTests.swift                           (T2)
├─ CancellableCallTests.swift                                     (T3)
└─ TeamDirectoryTests.swift, MatchHelpersTests.swift, AppFormatTests.swift (T4)

project.yml                          (T5, T6) LoLKit lié, Swift 6, ressources, cible de tests
.github/workflows/ios.yml            (T5, T6) durcissement + job « apercus » (tests simulateur, PNG)
scripts/icones.sh                    (T6) génère le catalogue d'icônes depuis les tracés des maquettes
Resources/Fonts/Sora-Variable.ttf, Resources/Fonts/OFL.txt   (T6) police et licence
Resources/Assets.xcassets/           (T6, généré) 21 icônes SVG « template » + couleur de lancement

Shared/                              compilé dans l'appli (Swift 6) ET l'extension (Swift 5)
├─ AppGroup.swift                    (T5) groupe d'apps résolu à l'exécution, dossier de Faille
├─ FileStore.swift                   (T5) lecture / écriture des fichiers JSON et des logos
├─ Provisioning.swift                (inchangé) lecture d'embedded.mobileprovision
├─ DA/Palette.swift                  (T6) couleurs, Color(rgb:), RGB(color:)
├─ DA/Typography.swift               (T6) Sora (axe wght) et échelle typographique
├─ DA/Icon.swift                     (T6) noms des icônes du catalogue, IconView
├─ Preview/SampleData.swift          (T7) PreviewData + données d'exemple (inits publics de LoLKit)
└─ Preview/StubTransport.swift       (T7) faux réseau JSON pour les tests du store
App/
├─ FailleApp.swift                   (T5, T7) point d'entrée, boucle de rafraîchissement liée à la scène
├─ RootView.swift                    (T5, T6, T7, T9, T10, T11) onglets Matchs / Équipes
├─ DA/AbyssBackground.swift          (T6) fond Abysse
├─ DA/GlassCard.swift                (T6) carte en verre Vitrail (glassEffect + dégradé + arête + ombre)
├─ DA/Components.swift               (T6) en-tête, étiquette, point, pastille, pilule, badge d'équipe, bandeau, note
├─ DA/DASampler.swift                (T6) planche DA (aperçu PNG 00-da)
├─ Store/AppStore.swift              (T7) données, disque, rafraîchissements, couleurs d'équipe, actions
├─ Store/AppStore+Tint.swift         (T7) couleur Vitrail d'une équipe d'un match (SwiftUI)
├─ Store/LogoPixels.swift            (T7) miniature PNG et octets RGBA d'un logo
├─ Settings/SettingsView.swift       (T8) Réglages + À propos
├─ Teams/TeamsView.swift             (T9) onglet Équipes
├─ Teams/TeamRows.swift              (T9) lignes « Mes équipes » et catalogue
├─ Teams/TeamColorSheet.swift        (T9) changer la couleur d'une équipe
├─ Matches/MatchesView.swift         (T10) onglet Matchs, MatchRoute, carte d'accueil
├─ Matches/TeamCardView.swift        (T10) carte Vitrail d'une équipe
├─ Matches/MatchParts.swift          (T10) pièces partagées avec le Détail (score, chrono, mini-stats, révéler)
├─ Detail/MatchDetailModel.swift     (T11) boucle 10 s de l'écran Détail
├─ Detail/MatchDetailView.swift      (T11) écran Détail
└─ Detail/StatsPanels.swift          (T11) stats d'équipe, barre de gold, joueurs
Widgets/
├─ FailleWidgets.swift               (T5) sonde : groupe d'apps + équipes suivies lues dans le groupe
└─ ProbeAttributes.swift             (T5, déplacé depuis Shared/) attributs de la Live Activity de la sonde
Tests/FailleTests/                   tests hébergés dans l'appli (simulateur, CI)
├─ Support/Snapshot.swift            (T6) rendu PNG d'un écran dans build/apercus/
├─ ApercuTests.swift                 (T6) suite des aperçus (police, icônes, planche DA)
├─ StoreTests.swift                  (T7) store : chargement, disque, panne
├─ SettingsSnapshotTests.swift       (T8) 07-reglages.png
├─ TeamsSnapshotTests.swift          (T9) 03-equipes.png
├─ MatchesSnapshotTests.swift        (T10) 01-matchs.png, 02-matchs-vide.png, 08-bandeau-erreur.png
└─ DetailSnapshotTests.swift         (T11) 04-detail.png, 05-detail-sans-stats.png, 06-detail-masque.png
Supprimés (T5) : App/ProbeView.swift, Shared/ProbeStore.swift
docs/superpowers/notes/2026-10-etape-2-verdict.md   (T12) résultats sur l'iPhone
```

## Commandes de vérification CI (rappel, utilisées dans chaque tâche)

Après `git push origin main` :

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
```

Expected : un identifiant numérique. Vide → le run n'est pas encore enregistré : relancer la commande quelques secondes plus tard. Puis `gh run watch --exit-status <id>` (Expected : tous les jobs verts). En cas d'échec : `gh run view <id> --log-failed`, corriger, nouveau commit, recommencer. Pour LoLKit, même chose avec `--workflow LoLKit`.

Télécharger les aperçus d'un run (tâches d'interface) :

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls "$HOME/Downloads/faille-apercus-<id>"
```

L'exécutant vérifie seulement la **présence** des PNG nommés ; le jugement visuel revient au contrôleur et à Dan.

---

### Task 1 : Cache horodaté et politique de rafraîchissement (LoLKit)

**Files :**
- Create : `LoLKit/Sources/LoLKit/Cache/Cached.swift`
- Create : `LoLKit/Sources/LoLKit/Cache/RefreshPolicy.swift`
- Test : `LoLKit/Tests/LoLKitTests/CacheTests.swift`
- Test : `LoLKit/Tests/LoLKitTests/RefreshPolicyTests.swift`

**Interfaces :**
- Consumes : `MatchEvent`, `League`, `Team`, `GameRef`, `GameRef.Side` (Codable, Equatable) ; builders de test existants `date(_:)`, `makeEvent(id:state:start:teams:bestOf:games:statsDisabled:)`, `makeTeam(_:id:name:image:wins:)`.
- Produces :
  - `public struct Cached<Value: Codable & Sendable>: Codable, Sendable` — `var value: Value`, `var fetchedAt: Date`, `init(value:fetchedAt:)`, `func age(now: Date) -> TimeInterval` ; `Equatable` quand `Value: Equatable`.
  - `public struct SchedulePage: Codable, Sendable, Equatable` — `var leagueIds: [String]`, `var events: [MatchEvent]`, `init(leagueIds:events:)`.
  - `public enum DataKind: String, Codable, Sendable, CaseIterable { case leagues, teams, schedule, live }`.
  - `public struct RefreshInput: Sendable, Equatable` — `now: Date`, `opening: Bool`, `lastSuccess: [DataKind: Date]`, `lastAttempt: [DataKind: Date]`, `scheduleLeagueIds: [String]?`, `wantedLeagueIds: [String]`, `matchLeftLive: Bool` ; `init(now:opening:lastSuccess:lastAttempt:scheduleLeagueIds:wantedLeagueIds:matchLeftLive:)` (tout sauf `now` a une valeur par défaut).
  - `public enum RefreshPolicy` — `static let tick, detailInterval, retryDelay, minGap, liveTrust: TimeInterval` ; `static func interval(_ kind: DataKind) -> TimeInterval` ; `static func due(_ input: RefreshInput) -> Set<DataKind>` ; `static func leftLive(previous: [MatchEvent]?, current: [MatchEvent]) -> Bool` ; `static func usableLive(_ cached: Cached<[MatchEvent]>?, now: Date) -> [MatchEvent]?`.

- [ ] **Step 1 : Écrire les tests du cache** — `LoLKit/Tests/LoLKitTests/CacheTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

@Suite struct CacheTests {
    @Test func scheduleRoundTripsThroughDefaultJSON() throws {
        let events = [
            makeEvent(id: "1", state: .completed, teams: [makeTeam("KC", wins: 3), makeTeam("G2", wins: 1)]),
            makeEvent(id: "2", state: .inProgress, teams: [makeTeam("T1", id: "t1"), makeTeam("GEN", id: "gen")],
                      games: [GameRef(number: 1, id: "g1", state: .inProgress, teams: [GameRef.Side(id: "t1", side: "blue")])],
                      statsDisabled: true),
        ]
        let cached = Cached(value: SchedulePage(leagueIds: ["98767975604431411"], events: events),
                            fetchedAt: date("2026-10-15T12:00:00Z"))
        let decoded = try JSONDecoder().decode(Cached<SchedulePage>.self, from: JSONEncoder().encode(cached))
        #expect(decoded == cached)
        let live = try #require(decoded.value.events.last)
        #expect(live.statsDisabled)
        #expect(live.match.games?.first?.state == .inProgress)
    }

    @Test func catalogRoundTripsThroughDefaultJSON() throws {
        let leagues = [League(id: "1", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1)]
        let teams = [Team(id: "kc", slug: "karmine-corp", name: "Karmine Corp", code: "KC", image: "http://kc.png",
                          status: "active", homeLeague: Team.HomeLeague(name: "LEC", region: "EMEA"))]
        let at = date("2026-10-15T12:00:00Z")
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        #expect(try decoder.decode(Cached<[League]>.self, from: encoder.encode(Cached(value: leagues, fetchedAt: at))).value == leagues)
        #expect(try decoder.decode(Cached<[Team]>.self, from: encoder.encode(Cached(value: teams, fetchedAt: at))).value == teams)
    }

    @Test func ageCountsFromFetchDate() {
        let cached = Cached(value: [String](), fetchedAt: date("2026-10-15T12:00:00Z"))
        #expect(cached.age(now: date("2026-10-15T12:01:30Z")) == 90)
        #expect(cached.age(now: date("2026-10-15T11:59:00Z")) == -60)
    }

    @Test func unreadableCacheThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Cached<SchedulePage>.self, from: Data(#"{"value":1}"#.utf8))
        }
    }
}
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `bash scripts/lolkit.sh test --filter CacheTests`
Expected : FAIL à la compilation, `error: cannot find 'Cached' in scope`.

- [ ] **Step 3 : Écrire le cache** — `LoLKit/Sources/LoLKit/Cache/Cached.swift`

```swift
import Foundation

/// Une valeur gardée sur disque avec la date à laquelle l'API l'a donnée (spec §4.4 : cache réseau).
/// Encodée avec `JSONEncoder()` par défaut (dates en secondes depuis 2001), relue avec `JSONDecoder()`.
public struct Cached<Value: Codable & Sendable>: Codable, Sendable {
    public var value: Value
    public var fetchedAt: Date

    public init(value: Value, fetchedAt: Date) {
        self.value = value
        self.fetchedAt = fetchedAt
    }

    /// Âge de la valeur ; négatif si l'horloge de l'appareil a reculé.
    public func age(now: Date) -> TimeInterval {
        now.timeIntervalSince(fetchedAt)
    }
}

extension Cached: Equatable where Value: Equatable {}

/// Le calendrier en cache et les ligues demandées pour l'obtenir : suivre une équipe d'une autre ligue
/// impose un nouvel appel à `getSchedule`.
public struct SchedulePage: Codable, Sendable, Equatable {
    public var leagueIds: [String]
    public var events: [MatchEvent]

    public init(leagueIds: [String], events: [MatchEvent]) {
        self.leagueIds = leagueIds
        self.events = events
    }
}
```

- [ ] **Step 4 : Lancer, vérifier le succès**

Run : `bash scripts/lolkit.sh test --filter CacheTests`
Expected : PASS, 4 tests.

- [ ] **Step 5 : Écrire les tests de la politique** — `LoLKit/Tests/LoLKitTests/RefreshPolicyTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

@Suite struct RefreshPolicyTests {
    private let now = date("2026-10-15T12:00:00Z")

    private func ago(_ seconds: TimeInterval) -> Date {
        now.addingTimeInterval(-seconds)
    }

    /// Tout a réussi il y a `seconds` secondes, calendrier demandé avec les bonnes ligues.
    private func fresh(_ seconds: TimeInterval = 5) -> RefreshInput {
        let dates = Dictionary(uniqueKeysWithValues: DataKind.allCases.map { ($0, ago(seconds)) })
        return RefreshInput(now: now, lastSuccess: dates, lastAttempt: dates, scheduleLeagueIds: ["1"], wantedLeagueIds: ["1"])
    }

    @Test func emptyStateFetchesEverythingButScheduleWithoutLeagues() {
        #expect(RefreshPolicy.due(RefreshInput(now: now)) == [.leagues, .teams, .live])
        #expect(RefreshPolicy.due(RefreshInput(now: now, wantedLeagueIds: ["1"])) == [.leagues, .teams, .schedule, .live])
    }

    @Test func freshDataIsNotRefetched() {
        #expect(RefreshPolicy.due(fresh()).isEmpty)
    }

    @Test func eachKindHasItsInterval() {
        var input = fresh()
        input.lastSuccess = [.leagues: ago(23 * 3600), .teams: ago(25 * 3600), .schedule: ago(31 * 60), .live: ago(61)]
        input.lastAttempt = input.lastSuccess
        #expect(RefreshPolicy.due(input) == [.teams, .schedule, .live])

        input.lastSuccess = [.leagues: ago(23 * 3600), .teams: ago(23 * 3600), .schedule: ago(29 * 60), .live: ago(59)]
        input.lastAttempt = input.lastSuccess
        #expect(RefreshPolicy.due(input).isEmpty)
    }

    @Test func openingForcesScheduleAndLiveButNotTwiceInARow() {
        var input = fresh(20)
        input.opening = true
        #expect(RefreshPolicy.due(input) == [.schedule, .live])

        input = fresh(5)
        input.opening = true
        #expect(RefreshPolicy.due(input).isEmpty)
    }

    @Test func newLeaguesOrAMatchLeavingLiveForceTheSchedule() {
        var input = fresh(20)
        input.wantedLeagueIds = ["1", "2"]
        #expect(RefreshPolicy.due(input) == [.schedule])
        input.scheduleLeagueIds = ["2", "1"]
        #expect(RefreshPolicy.due(input).isEmpty)
        input.matchLeftLive = true
        #expect(RefreshPolicy.due(input) == [.schedule])
    }

    @Test func failedAttemptWaitsTheRetryDelay() {
        var input = fresh()
        input.lastSuccess[.live] = ago(120)
        input.lastAttempt[.live] = ago(30)
        #expect(RefreshPolicy.due(input).isEmpty)
        input.lastAttempt[.live] = ago(61)
        #expect(RefreshPolicy.due(input) == [.live])
    }

    @Test func clockMovedBackRefetches() {
        var input = fresh()
        input.lastSuccess[.live] = now.addingTimeInterval(3600)
        input.lastAttempt[.live] = now.addingTimeInterval(3600)
        #expect(RefreshPolicy.due(input) == [.live])
    }

    @Test func leftLiveDetectsDisappearedMatches() {
        let a = makeEvent(id: "a", state: .inProgress, teams: [makeTeam("KC"), makeTeam("G2")])
        let b = makeEvent(id: "b", state: .inProgress, teams: [makeTeam("T1"), makeTeam("GEN")])
        #expect(!RefreshPolicy.leftLive(previous: nil, current: [a]))
        #expect(RefreshPolicy.leftLive(previous: [a, b], current: [a]))
        #expect(!RefreshPolicy.leftLive(previous: [a], current: [a, b]))
    }

    @Test func cachedLiveIsTrustedForTenMinutes() {
        let event = makeEvent(id: "a", state: .inProgress, teams: [makeTeam("KC"), makeTeam("G2")])
        #expect(RefreshPolicy.usableLive(Cached(value: [event], fetchedAt: ago(5 * 60)), now: now) == [event])
        #expect(RefreshPolicy.usableLive(Cached(value: [event], fetchedAt: ago(11 * 60)), now: now) == nil)
        #expect(RefreshPolicy.usableLive(Cached(value: [event], fetchedAt: now.addingTimeInterval(120)), now: now) == nil)
        #expect(RefreshPolicy.usableLive(nil, now: now) == nil)
    }
}
```

- [ ] **Step 6 : Lancer, vérifier l'échec**

Run : `bash scripts/lolkit.sh test --filter RefreshPolicyTests`
Expected : FAIL à la compilation, `error: cannot find 'RefreshInput' in scope` (et `RefreshPolicy`, `DataKind`).

- [ ] **Step 7 : Écrire la politique** — `LoLKit/Sources/LoLKit/Cache/RefreshPolicy.swift`

```swift
import Foundation

/// Données que l'appli relit régulièrement (spec §4.1).
public enum DataKind: String, Codable, Sendable, CaseIterable {
    case leagues, teams, schedule, live
}

/// Ce que l'appli sait au moment de décider quoi relire.
public struct RefreshInput: Sendable, Equatable {
    public var now: Date
    /// L'appli vient de passer au premier plan, ou l'utilisateur a tiré pour rafraîchir.
    public var opening: Bool
    /// Dernière réponse valide de chaque donnée (au lancement : la date du cache sur disque).
    public var lastSuccess: [DataKind: Date]
    /// Dernière tentative, réussie ou non (en mémoire seulement).
    public var lastAttempt: [DataKind: Date]
    /// Ligues demandées pour le calendrier en cache ; nil s'il n'y a pas de calendrier.
    public var scheduleLeagueIds: [String]?
    /// Ligues à demander maintenant (`ScheduleQuery.leagueIds`) ; vide tant que les ligues ne sont pas connues.
    public var wantedLeagueIds: [String]
    /// Un match a quitté `getLive` depuis le dernier calendrier : il faut relire `getSchedule` (spec §10).
    public var matchLeftLive: Bool

    public init(now: Date, opening: Bool = false, lastSuccess: [DataKind: Date] = [:], lastAttempt: [DataKind: Date] = [:],
                scheduleLeagueIds: [String]? = nil, wantedLeagueIds: [String] = [], matchLeftLive: Bool = false) {
        self.now = now
        self.opening = opening
        self.lastSuccess = lastSuccess
        self.lastAttempt = lastAttempt
        self.scheduleLeagueIds = scheduleLeagueIds
        self.wantedLeagueIds = wantedLeagueIds
        self.matchLeftLive = matchLeftLive
    }
}

/// Quand relire quoi. Fonction pure : l'appli lui donne des dates, elle répond par les données à relire.
public enum RefreshPolicy {
    /// Cadence de la boucle de l'appli au premier plan.
    public static let tick: TimeInterval = 10
    /// Cadence du flux de stats tant que l'écran Détail est affiché.
    public static let detailInterval: TimeInterval = 10
    /// Après un échec, délai avant de retenter la même donnée.
    public static let retryDelay: TimeInterval = 60
    /// Écart minimal entre deux tentatives forcées (ouverture, ligues changées, match sorti du direct).
    public static let minGap: TimeInterval = 10
    /// Au-delà, la liste des matchs en direct n'est plus crue : les cartes retombent sur le calendrier.
    public static let liveTrust: TimeInterval = 600
    /// Un succès daté de plus loin que ça dans le futur veut dire que l'horloge a reculé.
    static let clockSkew: TimeInterval = 60

    public static func interval(_ kind: DataKind) -> TimeInterval {
        switch kind {
        case .leagues, .teams: return 24 * 3600
        case .schedule: return 30 * 60
        case .live: return 60
        }
    }

    /// Données à relire maintenant. Le calendrier attend que des ligues soient connues.
    public static func due(_ input: RefreshInput) -> Set<DataKind> {
        var result: Set<DataKind> = []
        for kind in DataKind.allCases {
            if kind == .schedule && input.wantedLeagueIds.isEmpty { continue }
            let success = input.lastSuccess[kind]
            let stale = success.map {
                input.now.timeIntervalSince($0) >= interval(kind) || $0 > input.now.addingTimeInterval(clockSkew)
            } ?? true
            if (stale || isForced(kind, input)) && canTry(success: success, attempt: input.lastAttempt[kind], now: input.now) {
                result.insert(kind)
            }
        }
        return result
    }

    static func isForced(_ kind: DataKind, _ input: RefreshInput) -> Bool {
        switch kind {
        case .leagues, .teams:
            return false
        case .live:
            return input.opening
        case .schedule:
            return input.opening || input.matchLeftLive
                || Set(input.scheduleLeagueIds ?? []) != Set(input.wantedLeagueIds)
        }
    }

    /// Une tentative ratée attend `retryDelay` ; sinon `minGap` suffit (évite les doublons à l'ouverture).
    static func canTry(success: Date?, attempt: Date?, now: Date) -> Bool {
        guard let attempt, attempt <= now else { return true }
        let failed = success.map { attempt > $0 } ?? true
        return now.timeIntervalSince(attempt) >= (failed ? retryDelay : minGap)
    }

    /// Vrai si un match présent dans l'ancienne réponse de `getLive` n'y est plus.
    public static func leftLive(previous: [MatchEvent]?, current: [MatchEvent]) -> Bool {
        guard let previous else { return false }
        let ids = Set(current.map(\.id))
        return previous.contains { !ids.contains($0.id) }
    }

    /// Le direct en cache s'il est assez récent pour faire foi ; sinon nil (repli sur le calendrier, `TeamCards.build`).
    public static func usableLive(_ cached: Cached<[MatchEvent]>?, now: Date) -> [MatchEvent]? {
        guard let cached else { return nil }
        let age = cached.age(now: now)
        return age >= 0 && age <= liveTrust ? cached.value : nil
    }
}
```

- [ ] **Step 8 : Lancer les tests de la tâche, puis tous les tests**

Run : `bash scripts/lolkit.sh test --filter RefreshPolicyTests`
Expected : PASS, 9 tests.
Run : `bash scripts/lolkit.sh test`
Expected : PASS, 111 tests (98 + 13).

- [ ] **Step 9 : Commit, push, CI LoLKit**

```bash
git add LoLKit/Sources/LoLKit/Cache LoLKit/Tests/LoLKitTests/CacheTests.swift LoLKit/Tests/LoLKitTests/RefreshPolicyTests.swift
git commit -m "feat(lolkit): cache horodaté et politique de rafraîchissement" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `test` (Linux) et `test-macos` verts.

---

### Task 2 : Groupe d'apps, réglages, noms de logos, alpha prémultiplié, URL https (LoLKit)

**Files :**
- Create : `LoLKit/Sources/LoLKit/Storage/AppGroupResolver.swift`
- Create : `LoLKit/Sources/LoLKit/Storage/AppSettings.swift`
- Create : `LoLKit/Sources/LoLKit/Storage/LogoFileName.swift`
- Create : `LoLKit/Sources/LoLKit/Color/Premultiplied.swift`
- Create : `LoLKit/Sources/LoLKit/Presentation/ImageURL.swift`
- Test : `LoLKit/Tests/LoLKitTests/StorageTests.swift`
- Test : `LoLKit/Tests/LoLKitTests/ImageTests.swift`

**Interfaces :**
- Consumes : `LiveActivityMode` (`automatic`, `manual`), `TeamColor.dominant(rgba:)`, `RGB`.
- Produces :
  - `public enum AppGroupResolver` — `static func candidates(provisioned: [String], altAppGroups: [String], configured: String) -> [String]` ; `static func first(of candidates: [String], isAvailable: (String) -> Bool) -> String?`.
  - `public struct AppSettings: Codable, Sendable, Equatable` — `var liveActivityMode: LiveActivityMode`, `var revealedMatchIds: Set<String>`, `init(liveActivityMode: = .automatic, revealedMatchIds: = [])`, décodage tolérant.
  - `public enum LogoFileName` — `static func name(for url: String) -> String` (`logo-<16 hex>.png`), `static func fnv1a64(_:) -> UInt64`.
  - `extension TeamColor { public static func unpremultiplied(_ rgba: [UInt8]) -> [UInt8] }`.
  - `public enum ImageURL { public static func secure(_ string: String?) -> URL? }`.

- [ ] **Step 1 : Écrire les tests du stockage** — `LoLKit/Tests/LoLKitTests/StorageTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

@Suite struct StorageTests {
    @Test func candidatesKeepSpecOrderWithoutDuplicates() {
        let list = AppGroupResolver.candidates(
            provisioned: ["group.com.cafe1231.faille.TA6JYZWPU9"],
            altAppGroups: ["group.com.cafe1231.faille.TA6JYZWPU9", "group.com.cafe1231.faille.ALT", ""],
            configured: "group.com.cafe1231.faille"
        )
        #expect(list == ["group.com.cafe1231.faille.TA6JYZWPU9", "group.com.cafe1231.faille.ALT", "group.com.cafe1231.faille"])
        #expect(AppGroupResolver.candidates(provisioned: [], altAppGroups: [], configured: "group.x") == ["group.x"])
    }

    @Test func firstAvailableWins() {
        let list = ["a", "b", "c"]
        #expect(AppGroupResolver.first(of: list) { $0 != "a" } == "b")
        #expect(AppGroupResolver.first(of: list) { _ in false } == nil)
    }

    @Test func settingsHaveDefaultsAndRoundTrip() throws {
        let defaults = AppSettings()
        #expect(defaults.liveActivityMode == .automatic)
        #expect(defaults.revealedMatchIds.isEmpty)
        let custom = AppSettings(liveActivityMode: .manual, revealedMatchIds: ["m1", "m2"])
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom)) == custom)
    }

    @Test func settingsDecodeTolerantly() throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) == AppSettings())
        let future = #"{"liveActivityMode":"turbo","revealedMatchIds":["m1"],"pinned":["m2"]}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(future.utf8))
        #expect(decoded.liveActivityMode == .automatic)
        #expect(decoded.revealedMatchIds == ["m1"])
    }
}
```

- [ ] **Step 2 : Écrire les tests des images** — `LoLKit/Tests/LoLKitTests/ImageTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

@Suite struct ImageTests {
    @Test func fnvMatchesReferenceVectors() {
        #expect(LogoFileName.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(LogoFileName.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(LogoFileName.fnv1a64("foobar") == 0x8594_4171_f739_67e8)
    }

    @Test func logoNamesAreStableAndDistinct() {
        let kc = "http://static.lolesports.com/teams/1704714951336_KC.png"
        let name = LogoFileName.name(for: kc)
        #expect(name == LogoFileName.name(for: kc))
        #expect(name.hasPrefix("logo-") && name.hasSuffix(".png") && name.count == 25)
        #expect(name != LogoFileName.name(for: "http://static.lolesports.com/teams/G2-FullonDark.png"))
        #expect(LogoFileName.name(for: "") == "logo-cbf29ce484222325.png")
    }

    @Test func unpremultiplyRestoresChannels() {
        #expect(TeamColor.unpremultiplied([100, 50, 0, 128]) == [199, 100, 0, 128])
        #expect(TeamColor.unpremultiplied([0, 0, 0, 0, 10, 20, 30, 255]) == [0, 0, 0, 0, 10, 20, 30, 255])
        #expect(TeamColor.unpremultiplied([200, 0, 0, 100]) == [255, 0, 0, 100])
    }

    @Test func halfTransparentLogoKeepsItsColour() {
        let premultiplied = Array(repeating: [UInt8]([110, 10, 30, 128]), count: 50).flatMap { $0 }
        #expect(TeamColor.dominant(rgba: premultiplied) == RGB(r: 110, g: 10, b: 30))
        #expect(TeamColor.dominant(rgba: TeamColor.unpremultiplied(premultiplied)) == RGB(r: 219, g: 20, b: 60))
    }

    @Test func imageURLsBecomeHTTPS() {
        #expect(ImageURL.secure("http://static.lolesports.com/teams/KC.png")?.absoluteString
                == "https://static.lolesports.com/teams/KC.png")
        #expect(ImageURL.secure("https://static.lolesports.com/teams/team-tbd.png")?.absoluteString
                == "https://static.lolesports.com/teams/team-tbd.png")
        #expect(ImageURL.secure("//static.lolesports.com/a.png")?.absoluteString == "https://static.lolesports.com/a.png")
        #expect(ImageURL.secure(nil) == nil)
        #expect(ImageURL.secure("") == nil)
        #expect(ImageURL.secure("ftp://example.com/a.png") == nil)
    }
}
```

- [ ] **Step 3 : Lancer, vérifier l'échec**

Run : `bash scripts/lolkit.sh test --filter "StorageTests|ImageTests"`
Expected : FAIL à la compilation, `error: cannot find 'AppGroupResolver' in scope` (et `AppSettings`, `LogoFileName`, `ImageURL`, `unpremultiplied`).

- [ ] **Step 4 : Écrire `LoLKit/Sources/LoLKit/Storage/AppGroupResolver.swift`**

```swift
/// Choix du groupe d'apps (spec §4.4). Les outils de signature le renomment (AltServer :
/// `group.com.cafe1231.faille.<TEAMID>`) : on ne l'écrit jamais en dur, on essaie des candidats.
public enum AppGroupResolver {
    /// Candidats dans l'ordre de la spec : groupes du profil embarqué, puis clé `ALTAppGroups` de l'Info.plist,
    /// puis le nom configuré. Sans doublon ni chaîne vide.
    public static func candidates(provisioned: [String], altAppGroups: [String], configured: String) -> [String] {
        var seen: Set<String> = []
        return (provisioned + altAppGroups + [configured]).filter { group in
            !group.isEmpty && seen.insert(group).inserted
        }
    }

    /// Premier candidat dont le conteneur existe (côté iOS : `containerURL` non nil), sinon nil.
    public static func first(of candidates: [String], isAvailable: (String) -> Bool) -> String? {
        candidates.first(where: isAvailable)
    }
}
```

- [ ] **Step 5 : Écrire `LoLKit/Sources/LoLKit/Storage/AppSettings.swift`**

```swift
/// Réglages de l'appli, enregistrés dans le groupe d'apps (lus aussi par les widgets et la Live Activity aux étapes 3-4).
public struct AppSettings: Codable, Sendable, Equatable {
    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    public var liveActivityMode: LiveActivityMode
    /// Matchs que l'utilisateur a choisi de révéler malgré l'anti-spoiler (spec §8).
    public var revealedMatchIds: Set<String>

    public init(liveActivityMode: LiveActivityMode = .automatic, revealedMatchIds: Set<String> = []) {
        self.liveActivityMode = liveActivityMode
        self.revealedMatchIds = revealedMatchIds
    }

    private enum CodingKeys: String, CodingKey {
        case liveActivityMode, revealedMatchIds
    }

    /// Décodage tolérant : champ absent ou valeur inconnue (version plus récente) → valeur par défaut.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveActivityMode = (try? container.decodeIfPresent(LiveActivityMode.self, forKey: .liveActivityMode)) ?? .automatic
        revealedMatchIds = (try? container.decodeIfPresent(Set<String>.self, forKey: .revealedMatchIds)) ?? []
    }
}
```

- [ ] **Step 6 : Écrire `LoLKit/Sources/LoLKit/Storage/LogoFileName.swift`**

```swift
/// Nom de fichier stable d'un logo, tiré de son URL : un logo qui change d'URL change de fichier,
/// ce qui déclenche le recalcul de la couleur de l'équipe.
public enum LogoFileName {
    public static func name(for url: String) -> String {
        "logo-" + hex(fnv1a64(url)) + ".png"
    }

    /// FNV-1a 64 bits : stable d'un lancement à l'autre, contrairement à `hashValue`.
    public static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
```

- [ ] **Step 7 : Écrire `LoLKit/Sources/LoLKit/Color/Premultiplied.swift`**

```swift
extension TeamColor {
    /// CoreGraphics ne dessine qu'en RGBA à alpha prémultiplié : on redivise chaque canal par l'alpha pour retrouver
    /// la vraie couleur (un pixel à moitié transparent paraîtrait sinon deux fois plus sombre, voire « quasi noir »).
    /// Entrée et sortie : 4 octets par pixel. Alpha 0 et 255 : pixel inchangé.
    public static func unpremultiplied(_ rgba: [UInt8]) -> [UInt8] {
        var result = rgba
        var index = 0
        while index + 3 < result.count {
            let alpha = Int(result[index + 3])
            if alpha > 0 && alpha < 255 {
                for channel in index..<(index + 3) {
                    result[channel] = UInt8(min(255, (Int(result[channel]) * 255 + alpha / 2) / alpha))
                }
            }
            index += 4
        }
        return result
    }
}
```

- [ ] **Step 8 : Écrire `LoLKit/Sources/LoLKit/Presentation/ImageURL.swift`**

```swift
import Foundation

/// URLs d'images de l'API : souvent en `http://`, refusé par iOS (App Transport Security).
/// static.lolesports.com répond aussi en https.
public enum ImageURL {
    public static func secure(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        var value = string
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        } else if value.hasPrefix("//") {
            value = "https:" + value
        }
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
```

- [ ] **Step 9 : Lancer les tests de la tâche, puis tous les tests**

Run : `bash scripts/lolkit.sh test --filter "StorageTests|ImageTests"`
Expected : PASS, 9 tests.
Run : `bash scripts/lolkit.sh test`
Expected : PASS, 120 tests.

- [ ] **Step 10 : Commit, push, CI LoLKit**

```bash
git add LoLKit/Sources/LoLKit/Storage LoLKit/Sources/LoLKit/Color/Premultiplied.swift LoLKit/Sources/LoLKit/Presentation/ImageURL.swift LoLKit/Tests/LoLKitTests/StorageTests.swift LoLKit/Tests/LoLKitTests/ImageTests.swift
git commit -m "feat(lolkit): groupe d'apps, réglages, noms de logos, alpha prémultiplié, images en https" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `test` et `test-macos` verts.

---

### Task 3 : Requêtes annulables avec la tâche Swift (LoLKit)

Point différé du journal LoLKit (Task 5) : `URLSessionTransport` ne propage pas l'annulation. **Choix : on la propage** (`withTaskCancellationHandler`), sinon chaque passage en arrière-plan laisse des requêtes vivre jusqu'à 15 s.

**Files :**
- Create : `LoLKit/Sources/LoLKit/API/CancellableCall.swift`
- Modify : `LoLKit/Sources/LoLKit/API/HTTPTransport.swift` (contenu complet ci-dessous)
- Test : `LoLKit/Tests/LoLKitTests/CancellableCallTests.swift`

**Interfaces :**
- Consumes : `HTTPResponse`, `HTTPTransport`.
- Produces : `public enum CancellableCall { public static func run<T: Sendable>(_ start: (_ completion: @escaping @Sendable (Result<T, any Error>) -> Void) -> () -> Void) async throws -> T }` ; `URLSessionTransport.get` annule sa `URLSessionDataTask` quand la `Task` appelante est annulée (erreur `URLError.cancelled`).

- [ ] **Step 1 : Écrire les tests** — `LoLKit/Tests/LoLKitTests/CancellableCallTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

/// Fausse opération à rappel : ne répond jamais d'elle-même, seulement quand on l'annule.
private final class PendingCall: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Int, any Error>) -> Void)?
    private var cancels = 0

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancels
    }

    func start(_ completion: @escaping @Sendable (Result<Int, any Error>) -> Void) -> () -> Void {
        lock.lock()
        self.completion = completion
        lock.unlock()
        return { self.cancel() }
    }

    private func cancel() {
        lock.lock()
        cancels += 1
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(.failure(CancellationError()))
    }
}

@Suite struct CancellableCallTests {
    @Test func returnsTheResult() async throws {
        let value: Int = try await CancellableCall.run { completion in
            completion(.success(42))
            return {}
        }
        #expect(value == 42)
    }

    @Test func forwardsErrors() async {
        await #expect(throws: LoLAPIError.noData) {
            let _: Int = try await CancellableCall.run { completion in
                completion(.failure(LoLAPIError.noData))
                return {}
            }
        }
    }

    @Test func cancellingTheTaskCancelsTheCall() async {
        let call = PendingCall()
        let task = Task { try await CancellableCall.run(call.start) }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(call.cancelCount == 1)
    }

    @Test func alreadyCancelledTaskCancelsAtOnce() async {
        let call = PendingCall()
        let task = Task {
            try? await Task.sleep(for: .seconds(30)) // se termine dès l'annulation
            return try await CancellableCall.run(call.start)
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(call.cancelCount == 1)
    }
}
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run : `bash scripts/lolkit.sh test --filter CancellableCallTests`
Expected : FAIL à la compilation, `error: cannot find 'CancellableCall' in scope`.

- [ ] **Step 3 : Écrire `LoLKit/Sources/LoLKit/API/CancellableCall.swift`**

```swift
import Foundation

/// Relie l'annulation d'une `Task` Swift à une opération à rappel (comme `URLSessionDataTask`).
/// Sans ce lien, annuler la boucle de rafraîchissement laisse la requête aller jusqu'à son délai (15 s).
public enum CancellableCall {
    /// - Parameter start: lance l'opération, qui appellera `completion` une seule fois, et renvoie de quoi l'annuler.
    ///   L'annulation doit elle aussi aboutir à un appel de `completion` (en erreur).
    public static func run<T: Sendable>(
        _ start: (_ completion: @escaping @Sendable (Result<T, any Error>) -> Void) -> () -> Void
    ) async throws -> T {
        let canceller = Canceller()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                let cancel = start { result in continuation.resume(with: result) }
                canceller.install(cancel)
            }
        } onCancel: {
            canceller.cancel()
        }
    }
}

/// Garde l'action d'annulation. Si l'annulation arrive avant l'installation (tâche déjà annulée),
/// l'action est exécutée dès qu'elle est installée. Elle ne s'exécute jamais deux fois.
final class Canceller: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (() -> Void)?

    func install(_ action: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            action()
        } else {
            self.action = action
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
}
```

- [ ] **Step 4 : Remplacer `LoLKit/Sources/LoLKit/API/HTTPTransport.swift` (contenu complet)**

```swift
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Accès réseau, remplaçable dans les tests.
public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

/// Transport réel. Utilise `dataTask` (disponible partout, y compris Linux) ; annuler la `Task` appelante
/// annule la requête (`URLError.cancelled`).
public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let finalRequest = request
        return try await CancellableCall.run { completion in
            let task = URLSession.shared.dataTask(with: finalRequest) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(.success(HTTPResponse(status: status, body: data ?? Data())))
            }
            task.resume()
            return { task.cancel() }
        }
    }
}
```

- [ ] **Step 5 : Lancer les tests de la tâche, puis tous les tests**

Run : `bash scripts/lolkit.sh test --filter CancellableCallTests`
Expected : PASS, 4 tests.
Run : `bash scripts/lolkit.sh test`
Expected : PASS, 124 tests (les tests de `LoLClient` passent toujours : ils utilisent `FakeTransport`).

- [ ] **Step 6 : Vérifier la commande contre la vraie API (transport modifié)**

Run : `bash scripts/lolkit.sh run lolkit leagues`
Expected : une cinquantaine de lignes, dont `worlds   Mondial` (le transport réel répond toujours).

- [ ] **Step 7 : Commit, push, CI LoLKit**

```bash
git add LoLKit/Sources/LoLKit/API LoLKit/Tests/LoLKitTests/CancellableCallTests.swift
git commit -m "fix(lolkit): annuler une tâche Swift annule sa requête réseau" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `test` et `test-macos` verts.

---

### Task 4 : Annuaire des équipes, ordre d'affichage, formats de l'appli (LoLKit)

**Files :**
- Create : `LoLKit/Sources/LoLKit/Follow/TeamDirectory.swift`
- Create : `LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift`
- Create : `LoLKit/Sources/LoLKit/Models/EventDetails+Event.swift`
- Create : `LoLKit/Sources/LoLKit/Presentation/AppFormat.swift`
- Test : `LoLKit/Tests/LoLKitTests/TeamDirectoryTests.swift`
- Test : `LoLKit/Tests/LoLKitTests/MatchHelpersTests.swift`
- Test : `LoLKit/Tests/LoLKitTests/AppFormatTests.swift`

**Interfaces :**
- Consumes : `Team.isActive`, `FollowedTeam(team:)`, `MatchTeam.isSame(as:)`, `MatchTeam.isPlaceholder`, `League.priority`, `EventDetails.init(id:league:match:streams:)`, `EventDetails.Match.init(strategy:teams:games:)`, `LiveMatchBuilder.state(...)`, `TeamCard`, `PlayerLine`, `Format` ; tests : `Fixture.data("getLive")`, `ScheduleResponse` (interne).
- Produces :
  - `public enum TeamDirectory` — `static func search(_ query: String, in catalog: [Team], limit: Int = 50) -> [Team]` ; `static func teams(in league: League, catalog: [Team], schedule: [MatchEvent]) -> [Team]` ; `static func leagues(_ leagues: [League], catalog: [Team], schedule: [MatchEvent]) -> [League]`.
  - `extension FollowList { public func displayOrder(_ teams: [MatchTeam], preferring preferred: FollowedTeam? = nil) -> [Int] }`.
  - `extension EventDetails { public init(event: MatchEvent); public var statsDisabled: Bool; public var currentGame: GameRef? }`.
  - `extension Format` — `time(_:timeZone:) -> String`, `offlineBanner(lastUpdate:timeZone:) -> String`, `clock(_ seconds: TimeInterval) -> String`, `score(_ score: [Int]) -> String`, `kda(_ player: PlayerLine) -> String`, `dragons(_ types: [String]) -> String`, `role(_ role: String) -> String`, `champion(_ id: String) -> String`, `cardsSubtitle(_ cards: [TeamCard]) -> String`, `followCount(_ count: Int) -> String`.

- [ ] **Step 1 : Écrire les tests de l'annuaire** — `LoLKit/Tests/LoLKitTests/TeamDirectoryTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

@Suite struct TeamDirectoryTests {
    private func team(_ code: String, _ name: String, home: String? = nil, status: String = "active") -> Team {
        Team(id: code.lowercased(), slug: code.lowercased(), name: name, code: code, image: nil, status: status,
             homeLeague: home.map { Team.HomeLeague(name: $0) })
    }

    private func league(_ slug: String, _ name: String, priority: Int? = 1) -> League {
        League(id: slug, slug: slug, name: name, region: nil, image: nil, priority: priority)
    }

    private var catalog: [Team] {
        [
            team("KC", "Karmine Corp", home: "LEC"),
            team("KCB", "Karmine Corp Blue", home: "La Ligue Française"),
            team("SLY", "Solary", home: "La Ligue Française"),
            team("LGN", "Légion", home: "La Ligue Française"),
            team("G2", "G2 Esports", home: "LEC"),
            team("FUR", "FURIA"),
            team("OLD", "Karmine Old", home: "LEC", status: "archived"),
        ]
    }

    private var worldsSchedule: [MatchEvent] {
        [
            makeEvent(id: "1", state: .unstarted, teams: [makeTeam("FUR", name: "FURIA"), makeTeam("KC", name: "Karmine Corp")]),
            makeEvent(id: "2", state: .unstarted, teams: [makeTeam("TBD"), makeTeam("TBD")]),
        ]
    }

    @Test func searchRanksExactCodeThenPrefixThenContains() {
        #expect(TeamDirectory.search("kc", in: catalog).map(\.code) == ["KC", "KCB"])
        #expect(TeamDirectory.search("karmine", in: catalog).map(\.code) == ["KC", "KCB"])
        #expect(TeamDirectory.search("legion", in: catalog).map(\.code) == ["LGN"])
        #expect(TeamDirectory.search("ESPORTS", in: catalog).map(\.code) == ["G2"])
        #expect(TeamDirectory.search("  ", in: catalog).isEmpty)
        #expect(TeamDirectory.search("a", in: catalog, limit: 2).count == 2)
    }

    @Test func leagueTeamsIncludeHomeTeamsAndTeamsSeenInItsSchedule() {
        let lfl = league("lfl", "La Ligue Française")
        #expect(TeamDirectory.teams(in: lfl, catalog: catalog, schedule: []).map(\.code) == ["KCB", "LGN", "SLY"])
        let worlds = league("worlds", "Mondial")
        #expect(TeamDirectory.teams(in: worlds, catalog: catalog, schedule: worldsSchedule).map(\.code) == ["FUR", "KC"])
        #expect(TeamDirectory.teams(in: worlds, catalog: catalog, schedule: []).isEmpty)
    }

    @Test func leaguePillsSkipEmptyLeaguesAndFollowPriorityThenApiOrder() {
        let leagues = [league("worlds", "Mondial"), league("lpl", "LPL"), league("lec", "LEC", priority: 2),
                       league("lfl", "La Ligue Française")]
        #expect(TeamDirectory.leagues(leagues, catalog: catalog, schedule: worldsSchedule).map(\.slug) == ["worlds", "lfl", "lec"])
    }
}
```

- [ ] **Step 2 : Écrire les tests des aides de match** — `LoLKit/Tests/LoLKitTests/MatchHelpersTests.swift`

```swift
import Foundation
import Testing
@testable import LoLKit

@Suite struct MatchHelpersTests {
    @Test func followedTeamGoesLeft() {
        let follows = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1"),
                                         FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")])
        let kcVsT1 = [makeTeam("KC", id: "kc"), makeTeam("T1", id: "t1")]
        #expect(follows.displayOrder(kcVsT1) == [1, 0])
        #expect(follows.displayOrder(kcVsT1, preferring: follows.teams[1]) == [0, 1])
        #expect(follows.displayOrder([makeTeam("G2", id: "g2"), makeTeam("KC", id: "kc")]) == [1, 0])
        #expect(follows.displayOrder([makeTeam("G2", id: "g2"), makeTeam("FNC", id: "fnc")]) == [0, 1])
        #expect(follows.displayOrder([makeTeam("G2", id: "g2")]) == [0])
    }

    @Test func detailsFromALiveEvent() throws {
        let live = try JSONDecoder.lolesports()
            .decode(ScheduleResponse.self, from: Fixture.data("getLive")).data.schedule.events.elements
        let event = try #require(live.first)
        let details = EventDetails(event: event)
        #expect(details.id == event.id)
        #expect(details.match.teams.map(\.code) == ["BRO", "LGD"])
        #expect(details.bestOf == 5)
        #expect(details.statsDisabled)
        #expect(details.currentGame?.number == 1)
        let state = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil,
                                           statsDisabled: details.statsDisabled, follows: FollowList(), revealed: [],
                                           now: date("2026-10-13T09:30:00Z"))
        #expect(state.phase == .inGame)
        #expect(state.gameNumber == 1)
        #expect(!state.statsAvailable)
    }
}
```

- [ ] **Step 3 : Écrire les tests des formats** — `LoLKit/Tests/LoLKitTests/AppFormatTests.swift`

```swift
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
        #expect(Format.dragons(["infernal", "ocean"]) == "infernal, océan")
        #expect(Format.dragons(["elder", "mystery"]) == "ancien, mystery")
        #expect(Format.dragons([]) == "")
        #expect(Format.role("jungle") == "JGL")
        #expect(Format.role("bottom") == "BOT")
        #expect(Format.role("coach") == "COA")
        #expect(Format.champion("XinZhao") == "Xin Zhao")
        #expect(Format.champion("KSante") == "KSante")
        #expect(Format.champion("Rell") == "Rell")
    }

    @Test func subtitles() {
        let event = makeEvent(id: "m", state: .unstarted, teams: [makeTeam("KC"), makeTeam("G2")])
        let cards = [
            TeamCard(team: FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp"), live: event, next: event, last: nil),
            TeamCard(team: FollowedTeam(id: "t1", code: "T1", name: "T1"), live: nil, next: event, last: nil),
            TeamCard(team: FollowedTeam(id: "gen", code: "GEN", name: "Gen.G"), live: nil, next: nil, last: event),
        ]
        #expect(Format.cardsSubtitle(cards) == "1 en direct · 1 à venir")
        #expect(Format.followCount(0) == "aucune équipe suivie")
        #expect(Format.followCount(1) == "1 suivie")
        #expect(Format.followCount(3) == "3 suivies")
    }
}
```

- [ ] **Step 4 : Lancer, vérifier l'échec**

Run : `bash scripts/lolkit.sh test --filter "TeamDirectoryTests|MatchHelpersTests|AppFormatTests"`
Expected : FAIL à la compilation, `error: cannot find 'TeamDirectory' in scope` (et `displayOrder`, `EventDetails(event:)`, `Format.time`…).

- [ ] **Step 5 : Écrire `LoLKit/Sources/LoLKit/Follow/TeamDirectory.swift`**

```swift
import Foundation

/// Annuaire de l'onglet Équipes (spec §5.2) : recherche et ligues en pilules.
public enum TeamDirectory {
    /// Équipes actives dont le nom ou le code contient `query` (sans tenir compte de la casse ni des accents).
    /// Ordre : code exact, puis début du code ou du nom, puis le reste ; alphabétique à égalité.
    public static func search(_ query: String, in catalog: [Team], limit: Int = 50) -> [Team] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return [] }
        let ranked = catalog.compactMap { team -> (rank: Int, name: String, team: Team)? in
            guard team.isActive else { return nil }
            let code = fold(team.code)
            let name = fold(team.name)
            let rank: Int
            if code == needle {
                rank = 0
            } else if code.hasPrefix(needle) || name.hasPrefix(needle) {
                rank = 1
            } else if code.contains(needle) || name.contains(needle) {
                rank = 2
            } else {
                return nil
            }
            return (rank, name, team)
        }
        return ranked
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
            .prefix(limit)
            .map(\.team)
    }

    /// Équipes actives d'une ligue : celles dont c'est la ligue d'attache, plus celles vues dans son calendrier
    /// (indispensable pour le Mondial, le MSI et le First Stand, ligue d'attache de personne). Triées par nom.
    public static func teams(in league: League, catalog: [Team], schedule: [MatchEvent]) -> [Team] {
        let active = catalog.filter(\.isActive)
        var result = active.filter { $0.homeLeague?.name == league.name }
        let playing = schedule
            .filter { $0.league.slug == league.slug }
            .flatMap(\.match.teams)
            .filter { !$0.isPlaceholder }
        if !playing.isEmpty {
            for team in active where !result.contains(where: { $0.id == team.id }) {
                let followed = FollowedTeam(team: team)
                if playing.contains(where: { $0.isSame(as: followed) }) {
                    result.append(team)
                }
            }
        }
        return result.sorted { fold($0.name) < fold($1.name) }
    }

    /// Ligues à proposer en pilules : celles qui ont au moins une équipe, par priorité de l'API puis dans l'ordre de l'API.
    public static func leagues(_ leagues: [League], catalog: [Team], schedule: [MatchEvent]) -> [League] {
        leagues.enumerated()
            .filter { !teams(in: $0.element, catalog: catalog, schedule: schedule).isEmpty }
            .sorted { ($0.element.priority ?? .max, $0.offset) < ($1.element.priority ?? .max, $1.offset) }
            .map(\.element)
    }

    static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
```

- [ ] **Step 6 : Écrire `LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift`**

```swift
extension FollowList {
    /// Ordre d'affichage des deux équipes d'un match, en index de `teams` : `preferred` (l'équipe d'une carte)
    /// à gauche s'il joue, sinon l'équipe suivie depuis le plus longtemps, sinon l'ordre de l'API.
    public func displayOrder(_ teams: [MatchTeam], preferring preferred: FollowedTeam? = nil) -> [Int] {
        guard teams.count == 2 else { return Array(teams.indices) }
        if let preferred {
            if teams[0].isSame(as: preferred) { return [0, 1] }
            if teams[1].isSame(as: preferred) { return [1, 0] }
        }
        let ranks = teams.map { team in self.teams.firstIndex { team.isSame(as: $0) } }
        switch (ranks[0], ranks[1]) {
        case (nil, .some):
            return [1, 0]
        case let (left?, right?) where right < left:
            return [1, 0]
        default:
            return [0, 1]
        }
    }
}
```

- [ ] **Step 7 : Écrire `LoLKit/Sources/LoLKit/Models/EventDetails+Event.swift`**

```swift
extension EventDetails {
    /// Détails reconstitués depuis un match de `getLive`, qui donne déjà ids d'équipe, victoires et games :
    /// les cartes de l'onglet Matchs n'ont ainsi pas besoin d'un appel `getEventDetails` par match.
    public init(event: MatchEvent) {
        self.init(
            id: event.id,
            league: event.league,
            match: Match(strategy: event.match.strategy, teams: event.match.teams, games: event.match.games ?? []),
            streams: event.streams
        )
    }

    /// Riot ne fournit pas les stats live de ce match (même règle que `MatchEvent.statsDisabled`).
    public var statsDisabled: Bool {
        streams?.contains { $0.statsStatus == "disabled" } ?? false
    }

    /// Game en cours, sinon nil.
    public var currentGame: GameRef? {
        match.games.first { $0.state == .inProgress }
    }
}
```

- [ ] **Step 8 : Écrire `LoLKit/Sources/LoLKit/Presentation/AppFormat.swift`**

```swift
import Foundation

/// Formats propres à l'appli (étape 2), en français, identiques sur toutes les plateformes.
extension Format {
    /// « 14:05 » dans le fuseau donné.
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return twoDigits(parts.hour ?? 0) + ":" + twoDigits(parts.minute ?? 0)
    }

    /// Bandeau d'erreur (spec §10) : « lolesports ne répond pas · màj 14:05 ».
    public static func offlineBanner(lastUpdate: Date?, timeZone: TimeZone = .current) -> String {
        guard let lastUpdate else { return "lolesports ne répond pas" }
        return "lolesports ne répond pas · màj " + time(lastUpdate, timeZone: timeZone)
    }

    /// Chrono d'une game : « 18:42 », « 1:02:05 » au-delà d'une heure.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 { return "\(hours):" + twoDigits(minutes) + ":" + twoDigits(rest) }
        return "\(minutes):" + twoDigits(rest)
    }

    /// Score de série : « 1 – 0 ».
    public static func score(_ score: [Int]) -> String {
        score.map(String.init).joined(separator: " – ")
    }

    /// KDA d'un joueur : « 2/0/1 ».
    public static func kda(_ player: PlayerLine) -> String {
        "\(player.kills)/\(player.deaths)/\(player.assists)"
    }

    private static let dragonNames = [
        "infernal": "infernal", "ocean": "océan", "cloud": "nuage", "mountain": "montagne",
        "hextech": "hextech", "chemtech": "chemtech", "elder": "ancien",
    ]

    /// Types de drakes en français : « infernal, océan ». Type inconnu : tel quel, en minuscules.
    public static func dragons(_ types: [String]) -> String {
        types.map { dragonNames[$0.lowercased()] ?? $0.lowercased() }.joined(separator: ", ")
    }

    private static let roles = ["top": "TOP", "jungle": "JGL", "mid": "MID", "bottom": "BOT", "support": "SUP"]

    /// Rôle court : « JGL ». Rôle inconnu : ses 3 premières lettres en capitales.
    public static func role(_ role: String) -> String {
        roles[role.lowercased()] ?? String(role.uppercased().prefix(3))
    }

    /// Nom de champion lisible depuis son id : « XinZhao » → « Xin Zhao » (espace avant une capitale qui suit une minuscule).
    public static func champion(_ id: String) -> String {
        var result = ""
        var previous: Character?
        for character in id {
            if character.isUppercase, let previous, previous.isLowercase {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
    }

    /// Sous-titre de l'onglet Matchs : « 2 en direct · 1 à venir » (à venir = cartes sans direct mais avec un prochain match).
    public static func cardsSubtitle(_ cards: [TeamCard]) -> String {
        let live = cards.filter { $0.live != nil }.count
        let upcoming = cards.filter { $0.live == nil && $0.next != nil }.count
        return "\(live) en direct · \(upcoming) à venir"
    }

    /// Sous-titre de l'onglet Équipes : « 3 suivies », « 1 suivie », « aucune équipe suivie ».
    public static func followCount(_ count: Int) -> String {
        switch count {
        case 0: return "aucune équipe suivie"
        case 1: return "1 suivie"
        default: return "\(count) suivies"
        }
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
```

- [ ] **Step 9 : Lancer les tests de la tâche, puis tous les tests**

Run : `bash scripts/lolkit.sh test --filter "TeamDirectoryTests|MatchHelpersTests|AppFormatTests"`
Expected : PASS, 9 tests.
Run : `bash scripts/lolkit.sh test`
Expected : PASS, 133 tests.

- [ ] **Step 10 : Commit, push, CI LoLKit**

```bash
git add LoLKit/Sources/LoLKit/Follow/TeamDirectory.swift LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift LoLKit/Sources/LoLKit/Models/EventDetails+Event.swift LoLKit/Sources/LoLKit/Presentation/AppFormat.swift LoLKit/Tests/LoLKitTests/TeamDirectoryTests.swift LoLKit/Tests/LoLKitTests/MatchHelpersTests.swift LoLKit/Tests/LoLKitTests/AppFormatTests.swift
git commit -m "feat(lolkit): annuaire des équipes, ordre d'affichage et formats de l'appli" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `test` et `test-macos` verts (le job macOS valide `folding` de la Foundation d'Apple).

---

### Task 5 : Projet de l'étape 2 — LoLKit lié, groupe d'apps résolu à l'exécution, stockage JSON, CI durcie

La sonde de l'appli (`ProbeView`, `ProbeStore`) disparaît ; la sonde du widget reste, mais lit désormais les équipes suivies dans le groupe d'apps résolu.

**Files :**
- Modify : `project.yml` (contenu complet ci-dessous)
- Modify : `.github/workflows/ios.yml` (contenu complet ci-dessous)
- Create : `Shared/AppGroup.swift`
- Create : `Shared/FileStore.swift`
- Delete : `Shared/ProbeStore.swift`, `App/ProbeView.swift`
- Move : `Shared/ProbeAttributes.swift` → `Widgets/ProbeAttributes.swift` (contenu inchangé)
- Modify : `Widgets/FailleWidgets.swift` (contenu complet ci-dessous)
- Modify : `App/FailleApp.swift` (contenu complet ci-dessous)
- Create : `App/RootView.swift`

**Interfaces :**
- Consumes : `AppGroupResolver.candidates(provisioned:altAppGroups:configured:)`, `AppGroupResolver.first(of:isAvailable:)`, `Provisioning.read(bundleURL:)`, `FollowList`, `LoLKitInfo.version`.
- Produces :
  - `enum AppGroup { static let configured: String; static let identifier: String?; static let directory: URL }`.
  - `struct FileStore: Sendable` — `enum File: String { follows, settings, leagues, teams, schedule, live }`, `init(directory: URL)`, `let directory: URL`, `var logosDirectory: URL`, `func url(_ file: File) -> URL`, `func load<T: Decodable>(_ type: T.Type, from file: File) -> T?`, `func save<T: Encodable>(_ value: T, to file: File)`, `func logoURL(named: String) -> URL`, `func hasLogo(named: String) -> Bool`, `func saveLogo(_ data: Data, named: String)`.
  - `struct RootView: View` (provisoire), cibles liées à LoLKit, appli en Swift 6.

- [ ] **Step 1 : Remplacer `project.yml` (contenu complet)**

```yaml
name: Faille
options:
  bundleIdPrefix: com.cafe1231
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  LoLKit:
    path: LoLKit
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1,2"
    CODE_SIGNING_ALLOWED: "NO"
    CODE_SIGNING_REQUIRED: "NO"
targets:
  Faille:
    type: application
    platform: iOS
    sources:
      - App
      - Shared
    dependencies:
      - target: FailleWidgets
      - package: LoLKit
    scheme: {}
    entitlements:
      path: App/Faille.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.cafe1231.faille
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        UILaunchScreen: {}
        NSSupportsLiveActivities: true
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille
        # Appli en Swift 6 (concurrence stricte) ; l'extension reste en Swift 5 jusqu'à l'étape 3.
        SWIFT_VERSION: "6.0"
  FailleWidgets:
    type: app-extension
    platform: iOS
    sources:
      - Widgets
      - Shared
    dependencies:
      - package: LoLKit
    entitlements:
      path: Widgets/FailleWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.cafe1231.faille
    info:
      path: Widgets/Info.plist
      properties:
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille.widgets
```

- [ ] **Step 2 : Écrire `Shared/AppGroup.swift`**

```swift
import Foundation
import LoLKit

/// Groupe d'apps réellement attribué à ce bundle (spec §4.4). AltServer le renomme en
/// `group.com.cafe1231.faille.<TEAMID>` : on ne suppose jamais ni le nom du groupe, ni le bundle ID.
/// Même règle dans l'appli et dans l'extension (chacune lit son propre profil embarqué).
enum AppGroup {
    /// Nom déclaré dans project.yml, dernier candidat.
    static let configured = "group.com.cafe1231.faille"

    /// Groupe retenu : le premier candidat dont le conteneur existe ; nil si aucun (l'appli marche alors seule).
    static let identifier: String? = {
        let provisioned = Provisioning.read(bundleURL: Bundle.main.bundleURL)?.appGroups ?? []
        let altStore = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let candidates = AppGroupResolver.candidates(provisioned: provisioned, altAppGroups: altStore, configured: configured)
        return AppGroupResolver.first(of: candidates) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    /// Dossier des fichiers de Faille : `Faille/` dans le conteneur du groupe, sinon dans Application Support de l'appli.
    static let directory: URL = {
        if let identifier, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return container.appendingPathComponent("Faille", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Faille", isDirectory: true)
    }()
}
```

- [ ] **Step 3 : Écrire `Shared/FileStore.swift`**

```swift
import Foundation
import os

/// Fichiers JSON de Faille (spec §4.4) dans le dossier résolu par `AppGroup`. Partagé entre l'appli et l'extension.
/// Encodage `JSONEncoder()` / `JSONDecoder()` par défaut. Un fichier illisible est mis de côté, jamais écrasé.
struct FileStore: Sendable {
    enum File: String, Sendable, CaseIterable {
        case follows = "follows.json"
        case settings = "settings.json"
        case leagues = "cache-leagues.json"
        case teams = "cache-teams.json"
        case schedule = "cache-schedule.json"
        case live = "cache-live.json"
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: logosDirectory, withIntermediateDirectories: true)
    }

    var logosDirectory: URL {
        directory.appendingPathComponent("logos", isDirectory: true)
    }

    func url(_ file: File) -> URL {
        directory.appendingPathComponent(file.rawValue)
    }

    /// Valeur enregistrée, ou nil si le fichier manque ou est illisible.
    func load<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        let fileURL = self.url(file)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Format d'une autre version ? On le met de côté pour ne pas l'écraser à la prochaine sauvegarde.
            let aside = fileURL.appendingPathExtension("illisible")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            Self.log.error("\(file.rawValue, privacy: .public) illisible, mis de côté : \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, to file: File) {
        do {
            try JSONEncoder().encode(value).write(to: url(file), options: .atomic)
        } catch {
            Self.log.error("Écriture de \(file.rawValue, privacy: .public) impossible : \(String(describing: error), privacy: .public)")
        }
    }

    func logoURL(named name: String) -> URL {
        logosDirectory.appendingPathComponent(name)
    }

    func hasLogo(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: logoURL(named: name).path(percentEncoded: false))
    }

    func saveLogo(_ data: Data, named name: String) {
        do {
            try data.write(to: logoURL(named: name), options: .atomic)
        } catch {
            Self.log.error("Écriture du logo \(name, privacy: .public) impossible : \(String(describing: error), privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "Faille", category: "fichiers")
}
```

- [ ] **Step 4 : Retirer la sonde de l'appli, garder celle du widget**

```bash
git rm Shared/ProbeStore.swift App/ProbeView.swift
git mv Shared/ProbeAttributes.swift Widgets/ProbeAttributes.swift
```

- [ ] **Step 5 : Remplacer `Widgets/FailleWidgets.swift` (contenu complet)**

```swift
import ActivityKit
import LoLKit
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        ProbeWidget()
        ProbeLiveActivity()
    }
}

/// Sonde jusqu'à l'étape 3 : prouve que l'extension trouve le même groupe d'apps que l'appli
/// et y lit les équipes suivies (follows.json).
struct ProbeEntry: TimelineEntry {
    let date: Date
    let group: String?
    let codes: [String]
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, group: AppGroup.configured, codes: ["KC", "T1"])
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> ProbeEntry {
        let follows = FileStore(directory: AppGroup.directory).load(FollowList.self, from: .follows)
        return ProbeEntry(date: .now, group: AppGroup.identifier, codes: follows?.teams.map(\.code) ?? [])
    }
}

struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProbeWidget", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sonde Faille")
        .description("Vérifie que le widget lit les équipes suivies dans l'appli.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Faille · \(entry.group == nil ? "groupe KO" : "groupe OK")")
                .font(.caption2)
            Text(entry.group ?? "stockage local")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.codes.isEmpty ? "aucune équipe" : entry.codes.joined(separator: " · "))
                .font(.headline)
                .lineLimit(2)
        }
    }
}

struct ProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            HStack {
                Text("Sonde Faille").bold()
                Spacer()
                Text("tick \(context.state.tick)")
                Text(context.state.updatedAt, style: .time)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("tick \(context.state.tick)")
                }
            } compactLeading: {
                Text("F")
            } compactTrailing: {
                Text("\(context.state.tick)")
            } minimal: {
                Text("\(context.state.tick)")
            }
        }
    }
}
```

- [ ] **Step 6 : Remplacer `App/FailleApp.swift` (contenu complet)**

```swift
import SwiftUI

@main
struct FailleApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

- [ ] **Step 7 : Écrire `App/RootView.swift`**

```swift
import LoLKit
import SwiftUI

/// Écran provisoire (remplacé par la planche DA à la Task 6, puis par les onglets à la Task 7) :
/// prouve que LoLKit est lié et montre le groupe d'apps résolu.
struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Faille")
                .font(.largeTitle.bold())
            Text("LoLKit \(LoLKitInfo.version)")
            Text(AppGroup.identifier ?? "aucun groupe d'apps : stockage local")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
```

- [ ] **Step 8 : Remplacer `.github/workflows/ios.yml` (contenu complet, durcissement de l'étape 0)**

```yaml
name: iOS

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    # Si ce label n'existe pas sur GitHub, utiliser macos-latest.
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Générer le projet Xcode
        run: |
          brew install xcodegen
          xcodegen generate

      - name: Compiler sans signature
        run: |
          xcodebuild -project Faille.xcodeproj -scheme Faille -configuration Release \
            -destination 'generic/platform=iOS' -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO build

      - name: Signer en ad hoc avec les entitlements
        # AltServer re-signe ensuite avec l'Apple ID de Dan ; il lit les entitlements embarqués ici.
        run: |
          APP=build/Build/Products/Release-iphoneos/Faille.app
          codesign --force --sign - --entitlements Widgets/FailleWidgets.entitlements "$APP/PlugIns/FailleWidgets.appex"
          codesign --force --sign - --entitlements App/Faille.entitlements "$APP"
          codesign -d --entitlements - "$APP" 2>&1 | tee app-entitlements.txt
          codesign -d --entitlements - "$APP/PlugIns/FailleWidgets.appex" 2>&1 | tee widget-entitlements.txt
          # Sans groupe d'apps embarqué, AltServer n'en crée pas : l'appli et le widget ne partageraient rien.
          grep -q application-groups app-entitlements.txt
          grep -q application-groups widget-entitlements.txt

      - name: Empaqueter l'IPA
        run: |
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/Faille.app Payload/
          zip -qry Faille.ipa Payload

      - uses: actions/upload-artifact@v4
        with:
          name: Faille-ipa
          path: Faille.ipa
          retention-days: 14
```

- [ ] **Step 9 : Commit**

```bash
git add project.yml .github/workflows/ios.yml Shared/AppGroup.swift Shared/FileStore.swift Widgets/FailleWidgets.swift Widgets/ProbeAttributes.swift App/FailleApp.swift App/RootView.swift
git commit -m "feat(app): projet de l'étape 2 — LoLKit lié, groupe d'apps résolu à l'exécution, stockage JSON" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10 : Pousser et suivre la CI iOS**

```bash
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : job `build` vert ; dans le log de l'étape « Signer en ad hoc », les deux blocs d'entitlements contiennent `com.apple.security.application-groups` (vérifier avec `gh run view <id> --log | grep application-groups`, au moins 2 lignes). Erreurs probables et correctifs : `missing required module 'LoLKit'` → vérifier `- package: LoLKit` dans les deux cibles ; une erreur de concurrence Swift 6 dans `Shared/` → la corriger dans le fichier (pas de `@preconcurrency` global).

---

### Task 6 : DA Échap (Sora, icônes, verre, abysse) et aperçus PNG en CI

**Files :**
- Create : `scripts/icones.sh`
- Create : `Resources/Fonts/Sora-Variable.ttf`, `Resources/Fonts/OFL.txt` (téléchargés)
- Create : `Resources/Assets.xcassets/**` (générés par `scripts/icones.sh`)
- Create : `Shared/DA/Palette.swift`, `Shared/DA/Typography.swift`, `Shared/DA/Icon.swift`
- Create : `App/DA/AbyssBackground.swift`, `App/DA/GlassCard.swift`, `App/DA/Components.swift`, `App/DA/DASampler.swift`
- Modify : `App/RootView.swift` (contenu complet ci-dessous)
- Modify : `project.yml` (contenu complet ci-dessous)
- Modify : `.github/workflows/ios.yml` (ajout du job `apercus`, contenu complet ci-dessous)
- Create : `Tests/FailleTests/Support/Snapshot.swift`
- Test : `Tests/FailleTests/ApercuTests.swift`

**Interfaces :**
- Consumes : `RGB`, `RGB(hex:)`, `RGB.accent`, `ImageURL.secure(_:)`.
- Produces :
  - `enum Palette` — `abyss, text, secondary, accent, blueWash, tealWash, glassFill, glassBorder, glassEdge, chipFill: Color` ; `static func team(_ hex: String) -> Color` ; `extension Color { init(rgb: RGB) }` ; `extension RGB { init(color: Color) }`.
  - `enum Sora { enum Weight { regular, medium, semibold, bold }; static func uiFont(_ size: CGFloat, _ weight: Weight) -> UIFont; static func font(_ size: CGFloat, _ weight: Weight) -> Font }`.
  - `enum Typo` — `title, scoreLarge, score, headline, body, bodyMedium, stat, secondary, secondaryMedium, label, chip: Font` ; `titleTracking, labelTracking: CGFloat`.
  - `enum Icon: String, CaseIterable` (21 cas, dont `.eyeOff`, `.starFill`) ; `var assetName: String` ; `extension Image { init(icon: Icon) }` ; `struct IconView: View { icon, size = 14 }`.
  - `struct AbyssBackground: View` ; `extension View { func abyssBackground() -> some View }`.
  - `enum Radius { static let card: CGFloat = 28; static let inner: CGFloat = 22 }` ; `extension View { func glassCard(tint: Color? = nil, radius: CGFloat = Radius.card, padding: CGFloat = 16) -> some View }`.
  - Composants : `ScreenHeader(_ title:, subtitle:)` (+ `trailing:`), `SectionLabel(text:dot:)`, `GlowDot(color:)`, `Chip(muted:content:)`, `PillButton(selected:action:label:)`, `TeamBadge(code:image:logoFile:tint:size:)`, `ErrorBanner(text:)`, `NoteCard(icon:text:)`, `DASampler`.
  - Tests : `enum Snapshot { @MainActor static func write(_ view: some View, named: String) async throws -> URL }` ; `@MainActor @Suite(.serialized) struct ApercuTests` (les tâches suivantes y ajoutent des tests par `extension ApercuTests`).
  - CI : job `apercus` qui lance `xcodebuild test` sur un simulateur iPhone iOS 26+ et publie l'artefact `Faille-apercus` (`build/apercus/*.png`).

- [ ] **Step 1 : Télécharger Sora (police variable) et sa licence**

```bash
mkdir -p Resources/Fonts
curl -fsSL -o Resources/Fonts/Sora-Variable.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/sora/Sora%5Bwght%5D.ttf"
curl -fsSL -o Resources/Fonts/OFL.txt "https://raw.githubusercontent.com/google/fonts/main/ofl/sora/OFL.txt"
wc -c Resources/Fonts/Sora-Variable.ttf
head -c 4 Resources/Fonts/Sora-Variable.ttf | od -An -tx1
head -n 1 Resources/Fonts/OFL.txt
```

Expected : `111400 Resources/Fonts/Sora-Variable.ttf` (taille au 13/10/2026 ; une taille voisine est acceptable), puis ` 00 01 00 00` (TrueType), puis une ligne de copyright « Copyright 2019 The Sora Project Authors… ». Famille `Sora`, axe `wght` 100–800 (METADATA.pb de google/fonts).

- [ ] **Step 2 : Écrire `scripts/icones.sh`**

```bash
#!/usr/bin/env bash
# Génère Resources/Assets.xcassets : les icônes au trait des maquettes (grille 24, trait 1,8, rendu « template »)
# et la couleur du fond de lancement. Tracés copiés des <symbol> de docs/maquettes/ecrans-appli.html.
# Usage : bash scripts/icones.sh   (relancer après avoir modifié un tracé ci-dessous)
set -euo pipefail
cd "$(dirname "$0")/.."
CATALOG=Resources/Assets.xcassets
S='fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"'

mkdir -p "$CATALOG"
cat > "$CATALOG/Contents.json" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

icon() {
  local name="$1" body="$2"
  local dir="$CATALOG/icon-$name.imageset"
  mkdir -p "$dir"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">%s</svg>\n' "$body" > "$dir/icon-$name.svg"
  cat > "$dir/Contents.json" <<EOF
{
  "images" : [
    {
      "filename" : "icon-$name.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
EOF
}

icon swords   "<path $S d=\"M14.5 17.5L3 6V3h3l11.5 11.5M13 19l6-6M16 16l4 4M19 21l2-2M14.5 6.5L18 3h3v3l-3.5 3.5M5 14l4 4M7 17l-3 3M3 19l2 2\"/>"
icon gold     "<ellipse $S cx=\"12\" cy=\"6.5\" rx=\"7\" ry=\"3\"/><path $S d=\"M5 6.5v5c0 1.7 3.1 3 7 3s7-1.3 7-3v-5M5 11.5v5c0 1.7 3.1 3 7 3s7-1.3 7-3v-5\"/>"
icon tower    "<path $S d=\"M7 21V10L5 8V4h3v2h2V4h4v2h2V4h3v4l-2 2v11zM10 21v-4h4v4\"/>"
icon inhib    "<path $S d=\"M12 3l6 9-6 9-6-9z\"/><path $S d=\"M6 12h12\"/>"
icon drake    "<path $S d=\"M12 3c1 4 5 5.5 5 10a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3 0-3-1-5.5 1-8.5z\"/>"
icon baron    "<path $S d=\"M12 3l8 4.5v9L12 21l-8-4.5v-9z\"/><circle $S cx=\"12\" cy=\"12\" r=\"2.5\"/>"
icon clock    "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M12 7v5l3 2\"/>"
icon live     "<circle $S cx=\"12\" cy=\"12\" r=\"2\"/><path $S d=\"M8.5 15.5a5 5 0 0 1 0-7M15.5 8.5a5 5 0 0 1 0 7M5.6 18.4a9 9 0 0 1 0-12.8M18.4 5.6a9 9 0 0 1 0 12.8\"/>"
icon eye      "<path $S d=\"M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z\"/><circle $S cx=\"12\" cy=\"12\" r=\"3\"/>"
icon eyeoff   "<path $S d=\"M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3 3.9M6.6 6.6A17 17 0 0 0 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6M9.9 9.9a3 3 0 0 0 4.2 4.2\"/>"
icon star     "<path $S d=\"M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z\"/>"
icon star-fill "<path fill=\"#000000\" fill-opacity=\"0.25\" stroke=\"#000000\" stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1-4.4-4.3 6.1-.9z\"/>"
icon trophy   "<path $S d=\"M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0zM7 6H4v1a3 3 0 0 0 3 3M17 6h3v1a3 3 0 0 1-3 3\"/>"
icon settings "<circle $S cx=\"12\" cy=\"12\" r=\"3\"/><path $S d=\"M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z\"/>"
icon search   "<circle $S cx=\"11\" cy=\"11\" r=\"7\"/><path $S d=\"M20 20l-4-4\"/>"
icon back     "<path $S d=\"M19 12H5M11 6l-6 6 6 6\"/>"
icon arrow    "<path $S d=\"M5 12h14M13 6l6 6-6 6\"/>"
icon pin      "<rect $S x=\"5\" y=\"3\" width=\"14\" height=\"18\" rx=\"3\"/><path $S d=\"M9 7h6M9 17h6\"/>"
icon check    "<path $S d=\"M5 12l5 5L20 7\"/>"
icon refresh  "<path $S d=\"M20 11a8 8 0 0 0-14.9-3M4 4v4h4M4 13a8 8 0 0 0 14.9 3M20 20v-4h-4\"/>"
icon off      "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M6 6l12 12\"/>"

mkdir -p "$CATALOG/LaunchBackground.colorset"
cat > "$CATALOG/LaunchBackground.colorset/Contents.json" <<'EOF'
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0x20",
          "green" : "0x10",
          "red" : "0x0B"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Catalogue généré : $(ls -d "$CATALOG"/icon-*.imageset | wc -l | tr -d ' ') icônes"
```

- [ ] **Step 3 : Générer et contrôler le catalogue**

```bash
bash scripts/icones.sh
cat Resources/Assets.xcassets/icon-check.imageset/icon-check.svg
python -X utf8 -c "import glob, json, xml.dom.minidom; [xml.dom.minidom.parse(f) for f in glob.glob('Resources/Assets.xcassets/*/*.svg')]; [json.load(open(f, encoding='utf-8')) for f in glob.glob('Resources/Assets.xcassets/**/Contents.json', recursive=True)]; print('ok')"
```

Expected : `Catalogue généré : 21 icônes`, puis
`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M5 12l5 5L20 7"/></svg>`, puis `ok` (tous les SVG et JSON sont bien formés).

- [ ] **Step 4 : Écrire `Shared/DA/Palette.swift`**

```swift
import LoLKit
import SwiftUI
import UIKit

/// Couleurs de la DA « Échap » (spec §9).
enum Palette {
    static let abyss = Color(rgb: RGB(r: 0x0B, g: 0x10, b: 0x20))
    static let text = Color(rgb: RGB(r: 0xE9, g: 0xEE, b: 0xFB))
    static let secondary = Color(rgb: RGB(r: 0x94, g: 0xA0, b: 0xBF))
    static let accent = Color(rgb: .accent)
    /// Nappe bleue en haut à gauche, nappe turquoise en bas à droite.
    static let blueWash = Color(red: 60 / 255, green: 140 / 255, blue: 1, opacity: 0.18)
    static let tealWash = Color(red: 0, green: 220 / 255, blue: 200 / 255, opacity: 0.14)
    /// Verre neutre (équipes non suivies, listes).
    static let glassFill = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.22)
    /// Arête lumineuse en haut des cartes.
    static let glassEdge = Color.white.opacity(0.5)
    static let chipFill = Color.white.opacity(0.10)

    /// Couleur d'une équipe suivie (`FollowedTeam.colorHex`) ; l'accent si le hex est illisible.
    static func team(_ hex: String) -> Color {
        Color(rgb: RGB(hex: hex) ?? .accent)
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension RGB {
    /// Couleur choisie dans le sélecteur : composantes sRGB bornées à 0…1.
    init(color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        self.init(r: byte(red), g: byte(green), b: byte(blue))
    }
}
```

- [ ] **Step 5 : Écrire `Shared/DA/Typography.swift`**

```swift
import CoreText
import SwiftUI
import UIKit

/// Sora, police variable embarquée (Resources/Fonts/Sora-Variable.ttf, famille « Sora », axe `wght` 100–800).
/// La graisse est posée sur l'axe de variation : `.fontWeight` n'est pas fiable sur une police variable embarquée.
enum Sora {
    enum Weight: CGFloat, Sendable {
        case regular = 400, medium = 500, semibold = 600, bold = 700

        var system: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    /// Balise OpenType `wght` lue comme un entier 32 bits (clé du dictionnaire de variations de CoreText).
    private static let weightAxis = 0x7767_6874

    static func uiFont(_ size: CGFloat, _ weight: Weight) -> UIFont {
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: "Sora",
            variation: [weightAxis: weight.rawValue],
        ]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
        // Police absente (fichier non embarqué) : police système plutôt qu'une police de repli quelconque.
        return font.familyName == "Sora" ? font : .systemFont(ofSize: size, weight: weight.system)
    }

    static func font(_ size: CGFloat, _ weight: Weight) -> Font {
        Font(uiFont(size, weight) as CTFont)
    }
}

/// Échelle typographique (spec §9 ; tailles des maquettes ×1,355 pour passer de 290 px à 393 pt).
enum Typo {
    /// Titre d'écran, avec `.tracking(Typo.titleTracking)`.
    static let title = Sora.font(32, .bold)
    static let titleTracking: CGFloat = -1.28 // −0,04 em
    static let scoreLarge = Sora.font(28, .bold)
    static let score = Sora.font(22, .bold)
    static let headline = Sora.font(15, .semibold)
    static let body = Sora.font(15, .regular)
    static let bodyMedium = Sora.font(15, .medium)
    static let stat = Sora.font(15, .bold)
    static let secondary = Sora.font(12, .regular)
    static let secondaryMedium = Sora.font(12, .medium)
    /// Étiquette en capitales, avec `.tracking(Typo.labelTracking)` et `.textCase(.uppercase)`.
    static let label = Sora.font(11, .semibold)
    static let labelTracking: CGFloat = 0.88 // 0,08 em
    static let chip = Sora.font(11.5, .semibold)
}
```

- [ ] **Step 6 : Écrire `Shared/DA/Icon.swift`**

```swift
import SwiftUI

/// Icônes au trait des maquettes (grille 24, trait 1,8), dans Resources/Assets.xcassets en rendu « template » :
/// elles prennent la couleur du texte courant. Jamais d'emoji (spec §9).
enum Icon: String, CaseIterable, Sendable {
    case swords, gold, tower, inhib, drake, baron, clock, live, eye
    case eyeOff = "eyeoff"
    case star
    case starFill = "star-fill"
    case trophy, settings, search, back, arrow, pin, check, refresh, off

    var assetName: String {
        "icon-" + rawValue
    }
}

extension Image {
    init(icon: Icon) {
        self.init(icon.assetName)
    }
}

/// Une icône à la taille voulue (14 pt par défaut), teinte du texte courant.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = 14

    var body: some View {
        Image(icon: icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
```

- [ ] **Step 7 : Écrire `App/DA/AbyssBackground.swift`**

```swift
import SwiftUI

/// Fond « Abysse » (spec §9) : #0b1020, nappe bleue en haut à gauche, nappe turquoise en bas à droite.
struct AbyssBackground: View {
    var body: some View {
        ZStack {
            Palette.abyss
            LinearGradient(colors: [Palette.blueWash, .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.5, y: 0.45))
            LinearGradient(colors: [Palette.tealWash, .clear], startPoint: .bottomTrailing, endPoint: UnitPoint(x: 0.5, y: 0.55))
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Pose le fond Abysse derrière un écran entier.
    func abyssBackground() -> some View {
        background { AbyssBackground() }
    }
}
```

- [ ] **Step 8 : Écrire `App/DA/GlassCard.swift`**

```swift
import SwiftUI

/// Rayons de la DA : 28 pt pour les cartes, 22 pt pour les éléments internes (spec §9).
enum Radius {
    static let card: CGFloat = 28
    static let inner: CGFloat = 22
}

/// Carte en verre : Liquid Glass d'iOS 26 (`glassEffect`) + dégradé Vitrail à 160° (couleur d'équipe → blanc 3 %)
/// + arête lumineuse en haut + ombre profonde. `tint` = couleur de l'équipe suivie ; nil = verre neutre.
/// API iOS 26 utilisée : `View.glassEffect(_ glass: Glass, in shape: some Shape)` et `Glass.regular.tint(_:)`.
/// Si le SDK refuse ces noms, remplacer la ligne `.glassEffect(…)` par `.background(.ultraThinMaterial, in: shape)`.
struct GlassCard: ViewModifier {
    var tint: Color?
    var radius: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint?.opacity(0.24) ?? Palette.glassFill, Color.white.opacity(0.03)],
                    // ≈ linear-gradient(160deg, …) des maquettes
                    startPoint: UnitPoint(x: 0.33, y: 0),
                    endPoint: UnitPoint(x: 0.67, y: 1)
                ),
                in: shape
            )
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.10)) } ?? .regular, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Palette.glassEdge, Palette.glassBorder.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 15, x: 0, y: 14)
    }
}

extension View {
    func glassCard(tint: Color? = nil, radius: CGFloat = Radius.card, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(tint: tint, radius: radius, padding: padding))
    }
}
```

- [ ] **Step 9 : Écrire `App/DA/Components.swift`**

```swift
import LoLKit
import SwiftUI

/// Titre d'écran (32 pt, 700, −0,04 em) et sous-titre secondaire, avec un élément optionnel à droite.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(_ title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typo.title)
                    .tracking(Typo.titleTracking)
                    .foregroundStyle(Palette.text)
                Text(subtitle)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Étiquette de section : 11 pt, capitales espacées, secondaire ; point lumineux optionnel à droite.
struct SectionLabel: View {
    let text: String
    var dot: Color? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(Typo.label)
                .tracking(Typo.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let dot {
                GlowDot(color: dot)
            }
        }
    }
}

/// Point lumineux de l'en-tête des cartes Vitrail.
struct GlowDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color, radius: 5)
    }
}

/// Pastille : « En direct · Game 2 · 18:42 », « masqué ».
struct Chip<Content: View>: View {
    var muted = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) {
            content
        }
        .font(Typo.chip)
        .foregroundStyle(muted ? Palette.secondary : Palette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(muted ? 0.07 : 0.10), in: Capsule())
    }
}

/// Pilule sélectionnable (ligues, games) : blanche quand elle est choisie, verre sinon (onglets d'Échap).
struct PillButton<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var label: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                label
            }
            .font(selected ? Typo.secondaryMedium : Typo.secondary)
            .foregroundStyle(selected ? Palette.abyss : Palette.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Logo d'une équipe (fichier en cache, sinon téléchargé en https), ou à défaut son monogramme :
/// le code dans un badge bordé de sa couleur (verre neutre si l'équipe n'est pas suivie).
struct TeamBadge: View {
    let code: String
    var image: String? = nil
    var logoFile: URL? = nil
    var tint: Color? = nil
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
        ZStack {
            shape.fill(Palette.chipFill)
            if let logo = logoFile.flatMap({ UIImage(contentsOfFile: $0.path(percentEncoded: false)) }) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
            } else if let url = ImageURL.secure(image) {
                AsyncImage(url: url) { phase in
                    if let loaded = phase.image {
                        loaded
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.14)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(tint ?? Palette.glassBorder, lineWidth: 1))
    }

    private var monogram: some View {
        Text(code)
            .font(Sora.font(size * 0.3, .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .foregroundStyle(tint ?? Palette.text)
    }
}

/// Bandeau discret quand l'API ne répond pas (spec §10).
struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            IconView(icon: .refresh, size: 13)
            Text(text)
                .font(Typo.secondaryMedium)
        }
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: .infinity)
    }
}

/// Message sur verre neutre : chargement, liste vide, stats indisponibles.
struct NoteCard: View {
    let icon: Icon
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: icon, size: 15)
            Text(text)
                .font(Typo.secondary)
        }
        .foregroundStyle(Palette.secondary)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
```

- [ ] **Step 10 : Écrire `App/DA/DASampler.swift`**

```swift
import SwiftUI

/// Planche de la DA (couleurs, typographie, icônes, verre) : rendue en PNG (00-da) pour juger depuis Windows.
struct DASampler: View {
    private struct SampleTint: Identifiable {
        let code: String
        let hex: String
        var id: String { code }
    }

    private let tints = [SampleTint(code: "KC", hex: "#5B8CFF"), SampleTint(code: "T1", hex: "#FF5C7A"),
                         SampleTint(code: "GEN", hex: "#FFB454")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Planche DA", subtitle: "Abysse · Verre · Sora · Vitrail")
                SectionLabel(text: "Typographie")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Titre 32").font(Typo.title).tracking(Typo.titleTracking)
                    Text("Score 1 – 0").font(Typo.score)
                    Text("Corps 15 regular").font(Typo.body)
                    Text("Corps 15 medium").font(Typo.bodyMedium)
                    Text("Titre 15 semibold").font(Typo.headline)
                    Text("Secondaire 12").font(Typo.secondary).foregroundStyle(Palette.secondary)
                    Text("Étiquette 11")
                        .font(Typo.label)
                        .tracking(Typo.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.secondary)
                }
                .foregroundStyle(Palette.text)
                SectionLabel(text: "Icônes")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 12) {
                    ForEach(Icon.allCases, id: \.self) { icon in
                        IconView(icon: icon, size: 22)
                    }
                }
                .foregroundStyle(Palette.text)
                SectionLabel(text: "Vitrail")
                ForEach(tints) { sample in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Équipe \(sample.code)", dot: Palette.team(sample.hex))
                        HStack {
                            TeamBadge(code: sample.code, tint: Palette.team(sample.hex))
                            Text(sample.code).font(Typo.headline)
                            Spacer()
                            Chip {
                                IconView(icon: .live, size: 12)
                                Text("En direct · Game 2 · 18:42")
                            }
                        }
                    }
                    .foregroundStyle(Palette.text)
                    .glassCard(tint: Palette.team(sample.hex))
                }
                HStack {
                    TeamBadge(code: "C9")
                    Text("Verre neutre").font(Typo.body)
                    Spacer()
                    Chip(muted: true) {
                        IconView(icon: .eyeOff, size: 12)
                        Text("masqué")
                    }
                }
                .foregroundStyle(Palette.text)
                .glassCard(radius: Radius.inner)
                ErrorBanner(text: "lolesports ne répond pas · màj 14:05")
                NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .abyssBackground()
    }
}

#Preview {
    DASampler()
}
```

- [ ] **Step 11 : Remplacer `App/RootView.swift` (contenu complet)**

```swift
import SwiftUI

/// Écran provisoire : la planche DA (remplacée par les onglets à la Task 7).
struct RootView: View {
    var body: some View {
        DASampler()
    }
}
```

- [ ] **Step 12 : Écrire `Tests/FailleTests/Support/Snapshot.swift`**

```swift
import SwiftUI
import UIKit

/// Rend un écran dans une vraie fenêtre de l'appli hôte et l'enregistre en PNG dans `build/apercus/`
/// (publié par la CI dans l'artefact `Faille-apercus`). `ImageRenderer` ne rend ni les ScrollView, ni la barre
/// d'onglets, ni le Liquid Glass : on photographie la fenêtre avec `drawHierarchy`, comme le simulateur l'affiche.
@MainActor
enum Snapshot {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Racine du dépôt déduite de ce fichier (Tests/FailleTests/Support/Snapshot.swift) : le simulateur écrit
    /// directement sur le disque du Mac de la CI.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // FailleTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // racine du dépôt
        .appendingPathComponent("build/apercus", isDirectory: true)

    @discardableResult
    static func write(_ view: some View, named name: String) async throws -> URL {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw Failure(description: "aucune scène : les tests doivent être hébergés dans l'appli")
        }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Laisse SwiftUI faire sa mise en page, lancer ses `.task` et poser le verre.
        try await Task.sleep(for: .seconds(1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let png = image.pngData() else {
            throw Failure(description: "PNG vide pour \(name)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }
}
```

- [ ] **Step 13 : Écrire `Tests/FailleTests/ApercuTests.swift`**

```swift
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Faille

/// Aperçus PNG des écrans (artefact `Faille-apercus`) : depuis Windows, on ne voit l'appli que comme ça.
/// Les tâches suivantes ajoutent leurs écrans par `extension ApercuTests` (même suite, donc rendus un par un).
@MainActor
@Suite(.serialized)
struct ApercuTests {
    @Test func soraIsBundled() {
        #expect(!UIFont.fontNames(forFamilyName: "Sora").isEmpty)
        #expect(Sora.uiFont(15, .bold).familyName == "Sora")
    }

    @Test func iconsAreInTheCatalog() {
        for icon in Icon.allCases {
            #expect(UIImage(named: icon.assetName) != nil, "icône manquante : \(icon.assetName)")
        }
    }

    @Test func designSheet() async throws {
        let url = try await Snapshot.write(DASampler(), named: "00-da")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
```

- [ ] **Step 14 : Remplacer `project.yml` (contenu complet : ressources, police, catalogue, cible de tests)**

```yaml
name: Faille
options:
  bundleIdPrefix: com.cafe1231
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
packages:
  LoLKit:
    path: LoLKit
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1,2"
    CODE_SIGNING_ALLOWED: "NO"
    CODE_SIGNING_REQUIRED: "NO"
targets:
  Faille:
    type: application
    platform: iOS
    sources:
      - App
      - Shared
      - Resources
    dependencies:
      - target: FailleWidgets
      - package: LoLKit
    scheme:
      testTargets:
        - FailleTests
    entitlements:
      path: App/Faille.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.cafe1231.faille
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        UILaunchScreen:
          UIColorName: LaunchBackground
        UIUserInterfaceStyle: Dark
        UIAppFonts:
          - Sora-Variable.ttf
        NSSupportsLiveActivities: true
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille
        # Appli en Swift 6 (concurrence stricte) ; l'extension reste en Swift 5 jusqu'à l'étape 3.
        SWIFT_VERSION: "6.0"
        # Pas d'icône d'appli ni de couleur d'accent dans le catalogue à l'étape 2 : actool ne doit pas les chercher.
        ASSETCATALOG_COMPILER_APPICON_NAME: ""
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: ""
      configs:
        Debug:
          # Les tests hébergés utilisent du code de LoLKit lié dans l'appli : on ne l'élague pas en Debug.
          DEAD_CODE_STRIPPING: "NO"
  FailleWidgets:
    type: app-extension
    platform: iOS
    sources:
      - Widgets
      - Shared
    dependencies:
      - package: LoLKit
    entitlements:
      path: Widgets/FailleWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.cafe1231.faille
    info:
      path: Widgets/Info.plist
      properties:
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille.widgets
  FailleTests:
    # Tests hébergés dans l'appli (police, catalogue et scène disponibles) ; Swift Testing.
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests/FailleTests
    dependencies:
      - target: Faille
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille.tests
        SWIFT_VERSION: "6.0"
        GENERATE_INFOPLIST_FILE: "YES"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Faille.app/Faille"
        BUNDLE_LOADER: "$(TEST_HOST)"
```

- [ ] **Step 15 : Remplacer `.github/workflows/ios.yml` (contenu complet : job `build` inchangé + job `apercus`)**

```yaml
name: iOS

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    # Si ce label n'existe pas sur GitHub, utiliser macos-latest.
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Générer le projet Xcode
        run: |
          brew install xcodegen
          xcodegen generate

      - name: Compiler sans signature
        run: |
          xcodebuild -project Faille.xcodeproj -scheme Faille -configuration Release \
            -destination 'generic/platform=iOS' -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO build

      - name: Signer en ad hoc avec les entitlements
        # AltServer re-signe ensuite avec l'Apple ID de Dan ; il lit les entitlements embarqués ici.
        run: |
          APP=build/Build/Products/Release-iphoneos/Faille.app
          codesign --force --sign - --entitlements Widgets/FailleWidgets.entitlements "$APP/PlugIns/FailleWidgets.appex"
          codesign --force --sign - --entitlements App/Faille.entitlements "$APP"
          codesign -d --entitlements - "$APP" 2>&1 | tee app-entitlements.txt
          codesign -d --entitlements - "$APP/PlugIns/FailleWidgets.appex" 2>&1 | tee widget-entitlements.txt
          # Sans groupe d'apps embarqué, AltServer n'en crée pas : l'appli et le widget ne partageraient rien.
          grep -q application-groups app-entitlements.txt
          grep -q application-groups widget-entitlements.txt

      - name: Empaqueter l'IPA
        run: |
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/Faille.app Payload/
          zip -qry Faille.ipa Payload

      - uses: actions/upload-artifact@v4
        with:
          name: Faille-ipa
          path: Faille.ipa
          retention-days: 14

  apercus:
    # Tests de l'appli sur simulateur (store, aperçus) : les écrans en PNG dans l'artefact Faille-apercus.
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Générer le projet Xcode
        run: |
          brew install xcodegen
          xcodegen generate

      - name: Choisir un simulateur iPhone sous iOS 26 ou plus
        id: sim
        run: |
          UDID=$(xcrun simctl list devices available --json | jq -r '
            [.devices | to_entries[] | select(.key | test("iOS-(2[6-9]|[3-9][0-9])")) | .value[]
             | select(.name | startswith("iPhone"))] | first | .udid // empty')
          if [ -z "$UDID" ]; then
            xcrun simctl list devices available
            echo "Aucun simulateur iPhone iOS 26+ disponible" >&2
            exit 1
          fi
          echo "Simulateur : $UDID"
          echo "udid=$UDID" >> "$GITHUB_OUTPUT"

      - name: Tests et aperçus
        run: |
          xcodebuild test -project Faille.xcodeproj -scheme Faille \
            -destination "id=${{ steps.sim.outputs.udid }}" -derivedDataPath build/test \
            CODE_SIGNING_ALLOWED=NO

      - name: Lister les aperçus
        if: always()
        run: ls -la build/apercus || echo "aucun aperçu"

      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: Faille-apercus
          path: build/apercus/*.png
          if-no-files-found: warn
          retention-days: 14
```

- [ ] **Step 16 : Commit**

```bash
git add scripts/icones.sh Resources Shared/DA App/DA App/RootView.swift Tests/FailleTests project.yml .github/workflows/ios.yml
git update-index --chmod=+x scripts/icones.sh
git commit -m "feat(app): DA Échap — Sora, icônes, verre, abysse — et aperçus PNG en CI" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 17 : Pousser et suivre la CI iOS**

```bash
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts ; le log d'`apercus` montre `soraIsBundled`, `iconsAreInTheCatalog` et `designSheet` réussis. Erreurs probables : `None of the input catalogs contained a matching … app icon set` → vérifier `ASSETCATALOG_COMPILER_APPICON_NAME: ""` ; `soraIsBundled` en échec → vérifier `UIAppFonts` et la présence de `Sora-Variable.ttf` dans `Resources/Fonts` ; `glassEffect`/`Glass` inconnus → appliquer le repli décrit en tête de `GlassCard.swift` (et dans `ErrorBanner`, `.background(.ultraThinMaterial, in: Capsule())`).

- [ ] **Step 18 : Vérifier la présence de l'aperçu**

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls "$HOME/Downloads/faille-apercus-<id>"
```

Expected : `00-da.png`. Signaler au contrôleur que la planche est prête à être jugée (police Sora en 4 graisses, 21 icônes, trois cartes teintées bleu / carmin / ambre, une carte neutre, bandeau, note).

---

### Task 7 : Store de données — disque, rafraîchissements, couleurs d'équipe, onglets

**Files :**
- Create : `Shared/Preview/SampleData.swift`
- Create : `Shared/Preview/StubTransport.swift`
- Create : `App/Store/AppStore.swift`
- Create : `App/Store/AppStore+Tint.swift`
- Create : `App/Store/LogoPixels.swift`
- Modify : `App/FailleApp.swift` (contenu complet ci-dessous)
- Modify : `App/RootView.swift` (contenu complet ci-dessous)
- Test : `Tests/FailleTests/StoreTests.swift`

**Interfaces :**
- Consumes : T1 (`Cached`, `SchedulePage`, `DataKind`, `RefreshInput`, `RefreshPolicy`), T2 (`AppSettings`, `LogoFileName`, `TeamColor.unpremultiplied`, `ImageURL.secure`), T3 (transport annulable), T4 (`TeamDirectory`, `EventDetails(event:)`, `.statsDisabled`, `.currentGame`, `Format.offlineBanner`), T5 (`FileStore`, `AppGroup`), T6 (`Palette`, `ScreenHeader`, `abyssBackground()`, `Icon`) ; LoLKit : `LoLClient`, `LoLAPIError`, `LiveStatsTime`, `ScheduleQuery.leagueIds(follows:leagues:)`, `TeamCards.build(follows:schedule:live:)`, `SpoilerPolicy.isMasked`, `Presenter.scoreLine(for:follows:revealed:)`, `LiveMatchBuilder.state(details:snapshot:firstFrameTime:statsDisabled:follows:revealed:now:)`, `TeamColor.teamColor(rgba:)`, `FollowList.follow/unfollow/setSpoilerFree/setAutoColor/setColorOverride/refresh(from:)`.
- Produces :
  - `struct PreviewData` (champs : `follows, settings, leagues, catalog, schedule, live, details, snapshots, firstFrames, statsUnavailable, isFailing, lastUpdate`) ; `static var standard, empty, failing: PreviewData`.
  - `enum SampleData` — `kcMatchId = "m-kc-c9"`, `t1MatchId = "m-t1-fly"`, `noStatsMatchId = "m-bro-lgd"`, `leagues`, `catalog`, `follows`, `live`, `schedule`, `kcSnapshot`, `kcGameStart`, `static func date(_ iso: String) -> Date`.
  - `struct StubTransport: HTTPTransport { var failing = false }`.
  - `@MainActor @Observable final class AppStore` :
    - lecture : `follows`, `settings`, `leagues`, `catalog`, `schedule`, `live: [MatchEvent]?`, `leaguePills: [League]`, `details: [String: EventDetails]`, `snapshots: [String: GameSnapshot]`, `snapshotDates`, `firstFrames`, `statsUnavailable: Set<String>`, `isFailing`, `lastSuccess` ; `var cards: [TeamCard]`, `var lastUpdate: Date?`, `var bannerText: String?` ; `func event(id:) -> MatchEvent?`, `func followed(_: MatchTeam) -> FollowedTeam?`, `func isMasked(_ teams: [MatchTeam], matchId: String) -> Bool`, `func scoreLine(_: MatchEvent) -> ScoreLine`, `func liveState(for: MatchEvent) -> LiveMatchState`, `func detailState(matchId:) -> LiveMatchState?`, `func teams(in: League) -> [Team]`, `func search(_: String) -> [Team]`, `func logoFile(for image: String?) -> URL?`.
    - actions : `init(transport: any HTTPTransport = URLSessionTransport(), files: FileStore)`, `init(preview: PreviewData)`, `func poll() async`, `func refreshNow() async`, `func refreshDue(opening: Bool) async`, `func toggleFollow(_: Team)`, `func unfollow(id:)`, `func setSpoilerFree(_:id:)`, `func setColorOverride(_:id:)`, `func reveal(matchId:)`, `func setLiveActivityMode(_:)`, `func refreshLiveStats() async`, `func loadWindow(gameId:inProgress:) async`, `func loadDetails(matchId:) async`.
  - `extension AppStore { func tint(for team: MatchTeam) -> Color? }`.
  - `enum LogoPixels { static func thumbnail(from: Data, maxPixel: Int = 128) -> CGImage?; static func png(_: CGImage) -> Data?; static func rgba(_: CGImage, side: Int = 64) -> [UInt8]? }`.
  - `enum AppTab: Hashable { case matches, teams }` ; `RootView(tab: AppTab = .matches)`.

- [ ] **Step 1 : Écrire `Shared/Preview/SampleData.swift`**

```swift
import Foundation
import LoLKit

/// Données figées d'un `AppStore` d'aperçu (#Preview et tests d'images) : rien n'est lu sur le disque ni sur le réseau.
struct PreviewData {
    var follows = FollowList()
    var settings = AppSettings()
    var leagues: [League] = []
    var catalog: [Team] = []
    var schedule: [MatchEvent] = []
    var live: [MatchEvent]? = []
    var details: [String: EventDetails] = [:]
    var snapshots: [String: GameSnapshot] = [:]
    var firstFrames: [String: Date] = [:]
    var statsUnavailable: Set<String> = []
    var isFailing = false
    var lastUpdate: Date?

    /// Comme les maquettes : KC en direct avec stats, T1 en direct masqué (anti-spoiler), GEN à venir.
    static var standard: PreviewData {
        PreviewData(
            follows: SampleData.follows,
            leagues: SampleData.leagues,
            catalog: SampleData.catalog,
            schedule: SampleData.schedule,
            live: SampleData.live,
            details: Dictionary(uniqueKeysWithValues: SampleData.live.map { ($0.id, EventDetails(event: $0)) }),
            snapshots: [SampleData.kcSnapshot.gameId: SampleData.kcSnapshot],
            firstFrames: [SampleData.kcSnapshot.gameId: SampleData.kcGameStart],
            lastUpdate: SampleData.date("2026-10-15T15:05:00Z")
        )
    }

    /// Premier lancement : aucune équipe suivie.
    static var empty: PreviewData {
        PreviewData(leagues: SampleData.leagues, catalog: SampleData.catalog, schedule: SampleData.schedule,
                    live: SampleData.live)
    }

    /// L'API ne répond plus : données en cache et bandeau.
    static var failing: PreviewData {
        var data = standard
        data.isFailing = true
        return data
    }
}

/// Matchs, équipes et stats d'exemple, construits uniquement avec les inits publics de LoLKit.
enum SampleData {
    static let kcMatchId = "m-kc-c9"
    static let t1MatchId = "m-t1-fly"
    static let noStatsMatchId = "m-bro-lgd"

    static func date(_ iso: String) -> Date {
        LoLDate.parse(iso) ?? Date(timeIntervalSince1970: 0)
    }

    static let worlds = LeagueRef(id: "98767975604431411", slug: "worlds", name: "Mondial", image: nil)

    static let leagues: [League] = [
        League(id: "98767975604431411", slug: "worlds", name: "Mondial", region: "INTERNATIONAL", image: nil, priority: 1),
        League(id: "105266103462388553", slug: "lfl", name: "La Ligue Française", region: "EMEA", image: nil, priority: 1),
        League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1),
        League(id: "98767991310872058", slug: "lck", name: "LCK", region: "CORÉE", image: nil, priority: 1),
        League(id: "98767991314006698", slug: "lpl", name: "LPL", region: "CHINE", image: nil, priority: 1),
    ]

    static let catalog: [Team] = [
        team("kc", "KC", "Karmine Corp", "LEC"),
        team("g2", "G2", "G2 Esports", "LEC"),
        team("t1", "T1", "T1", "LCK"),
        team("gen", "GEN", "Gen.G", "LCK"),
        team("hle", "HLE", "Hanwha Life Esports", "LCK"),
        team("kcb", "KCB", "Karmine Corp Blue", "La Ligue Française"),
        team("sly", "SLY", "Solary", "La Ligue Française"),
        team("blg", "BLG", "Bilibili Gaming", "LPL"),
        team("c9", "C9", "Cloud9 Kia", "LCS"),
        team("fly", "FLY", "FlyQuest", "LCS"),
        team("fur", "FUR", "FURIA", nil),
    ]

    static var follows: FollowList {
        FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", homeLeagueName: "LEC", autoColorHex: "#5B8CFF"),
            FollowedTeam(id: "t1", code: "T1", name: "T1", homeLeagueName: "LCK", spoilerFree: true, autoColorHex: "#FF5C7A"),
            FollowedTeam(id: "gen", code: "GEN", name: "Gen.G", homeLeagueName: "LCK", autoColorHex: "#FFB454"),
        ])
    }

    /// KC 1 – 0 C9, game 2 en cours (forme `getLive` : ids d'équipe et games).
    static let kcLive = MatchEvent(
        startTime: date("2026-10-15T16:00:00Z"), state: .inProgress, type: "match", blockName: "Play-in",
        league: worlds,
        match: MatchInfo(id: kcMatchId, teams: [side("kc", wins: 1), side("c9", wins: 0)],
                         strategy: Strategy(type: "bestOf", count: 5),
                         games: games(count: 5, current: 2, blue: "kc", red: "c9")),
        streams: [StreamInfo(statsStatus: "enabled")]
    )

    /// T1 – FLY en cours : T1 est en anti-spoiler, le match est masqué partout.
    static let t1Live = MatchEvent(
        startTime: date("2026-10-15T17:00:00Z"), state: .inProgress, type: "match", blockName: "Play-in",
        league: worlds,
        match: MatchInfo(id: t1MatchId, teams: [side("t1", wins: 0), side("fly", wins: 0)],
                         strategy: Strategy(type: "bestOf", count: 5),
                         games: games(count: 5, current: 1, blue: "t1", red: "fly")),
        streams: [StreamInfo(statsStatus: "enabled")]
    )

    /// Match d'équipes non suivies dont Riot ne fournit pas les stats (comme la fixture getLive).
    static let noStatsLive = MatchEvent(
        startTime: date("2026-10-15T09:00:00Z"), state: .inProgress, type: "match", blockName: "Quarts de finale",
        league: LeagueRef(id: "117126995932274206", slug: "demacia_cup", name: "DCGI", image: nil),
        match: MatchInfo(
            id: noStatsMatchId,
            teams: [
                MatchTeam(id: "bro", name: "HANJIN BRION", code: "BRO", image: nil,
                          result: MatchTeam.Result(outcome: nil, gameWins: 1)),
                MatchTeam(id: "lgd", name: "LGD GAMING", code: "LGD", image: nil,
                          result: MatchTeam.Result(outcome: nil, gameWins: 0)),
            ],
            strategy: Strategy(type: "bestOf", count: 5),
            games: games(count: 5, current: 2, blue: "bro", red: "lgd")
        ),
        streams: [StreamInfo(statsStatus: "disabled")]
    )

    static var live: [MatchEvent] {
        [kcLive, t1Live, noStatsLive]
    }

    /// Calendrier (forme `getSchedule` : sans id d'équipe, reconnues par leur nom).
    static var schedule: [MatchEvent] {
        [
            kcLive,
            t1Live,
            upcoming("m-gen-fur", "2026-10-16T09:00:00Z", "gen", "fur"),
            upcoming("m-t1-gen", "2026-10-17T12:00:00Z", "t1", "gen"),
            completed("m-gen-hle", "2026-10-11T09:00:00Z", ("gen", 3, "win"), ("hle", 0, "loss")),
            completed("m-kc-g2", "2026-10-05T16:00:00Z", ("kc", 1, "loss"), ("g2", 3, "win")),
        ]
    }

    /// Game 2 de KC – C9 : première frame, et dernière frame reçue 18:42 plus tard.
    static let kcGameStart = date("2026-10-15T17:02:00Z")
    static let kcSnapshot = GameSnapshot(
        gameId: "g2-kc-c9", phase: .inGame, timestamp: date("2026-10-15T17:20:42Z"),
        blueTeamId: "kc", redTeamId: "c9",
        blue: TeamStats(kills: 7, gold: 32_400, towers: 3, inhibitors: 0, barons: 0, dragons: ["infernal", "ocean"]),
        red: TeamStats(kills: 4, gold: 30_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        bluePlayers: [
            player("top", "Rumble", "KC Top", 2, 0, 1, 162),
            player("jungle", "XinZhao", "KC Jungle", 1, 1, 4, 118),
            player("mid", "Taliyah", "KC Mid", 3, 1, 2, 171),
            player("bottom", "Kaisa", "KC Bot", 1, 1, 3, 189),
            player("support", "Rell", "KC Support", 0, 1, 5, 21),
        ],
        redPlayers: [
            player("top", "KSante", "C9 Top", 0, 1, 1, 150),
            player("jungle", "Vi", "C9 Jungle", 1, 2, 1, 104),
            player("mid", "Azir", "C9 Mid", 2, 2, 1, 168),
            player("bottom", "Ezreal", "C9 Bot", 1, 1, 1, 180),
            player("support", "Nautilus", "C9 Support", 0, 1, 3, 18),
        ]
    )

    private static func team(_ id: String, _ code: String, _ name: String, _ home: String?) -> Team {
        Team(id: id, slug: id, name: name, code: code, image: nil, status: "active",
             homeLeague: home.map { Team.HomeLeague(name: $0) })
    }

    /// Équipe d'un match : avec id comme `getLive`, ou sans id comme `getSchedule`.
    private static func side(_ id: String, wins: Int, outcome: String? = nil, withId: Bool = true) -> MatchTeam {
        let team = catalog.first { $0.id == id }
        return MatchTeam(id: withId ? id : nil, name: team?.name ?? id, code: team?.code ?? id.uppercased(), image: nil,
                         result: MatchTeam.Result(outcome: outcome, gameWins: wins))
    }

    private static func games(count: Int, current: Int, blue: String, red: String) -> [GameRef] {
        (1...count).map { number in
            let state: GameRef.State = number < current ? .completed : (number == current ? .inProgress : .unstarted)
            return GameRef(number: number, id: "g\(number)-\(blue)-\(red)", state: state,
                           teams: [GameRef.Side(id: blue, side: "blue"), GameRef.Side(id: red, side: "red")])
        }
    }

    private static func upcoming(_ id: String, _ start: String, _ a: String, _ b: String) -> MatchEvent {
        MatchEvent(startTime: date(start), state: .unstarted, type: "match", blockName: "Play-in", league: worlds,
                   match: MatchInfo(id: id, teams: [side(a, wins: 0, withId: false), side(b, wins: 0, withId: false)],
                                    strategy: Strategy(type: "bestOf", count: 5), games: nil),
                   streams: nil)
    }

    private static func completed(_ id: String, _ start: String, _ a: (id: String, wins: Int, outcome: String),
                                  _ b: (id: String, wins: Int, outcome: String)) -> MatchEvent {
        MatchEvent(startTime: date(start), state: .completed, type: "match", blockName: "Play-in", league: worlds,
                   match: MatchInfo(id: id,
                                    teams: [side(a.id, wins: a.wins, outcome: a.outcome, withId: false),
                                            side(b.id, wins: b.wins, outcome: b.outcome, withId: false)],
                                    strategy: Strategy(type: "bestOf", count: 5), games: nil),
                   streams: nil)
    }

    private static func player(_ role: String, _ champion: String, _ name: String, _ kills: Int, _ deaths: Int,
                               _ assists: Int, _ cs: Int) -> PlayerLine {
        PlayerLine(role: role, champion: champion, name: name, level: 11, kills: kills, deaths: deaths,
                   assists: assists, creepScore: cs, gold: 6_000 + cs * 10)
    }
}
```

- [ ] **Step 2 : Écrire `Shared/Preview/StubTransport.swift`**

```swift
import Foundation
import LoLKit

/// Faux réseau pour les tests du store : réponses JSON minimales de l'API (deux ligues, deux équipes, un match),
/// ou 503 partout (`failing`). Logos et flux `window` : 404.
struct StubTransport: HTTPTransport {
    var failing = false

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        guard !failing else { return HTTPResponse(status: 503, body: Data()) }
        let path = url.path(percentEncoded: false)
        let body: String
        if path.hasSuffix("/getLeagues") {
            body = Self.leagues
        } else if path.hasSuffix("/getTeams") {
            body = Self.teams
        } else if path.hasSuffix("/getSchedule") {
            body = Self.schedule
        } else if path.hasSuffix("/getLive") {
            body = Self.live
        } else {
            return HTTPResponse(status: 404, body: Data())
        }
        return HTTPResponse(status: 200, body: Data(body.utf8))
    }

    static let leagues = #"{"data":{"leagues":[{"id":"98767975604431411","slug":"worlds","name":"Mondial","region":"INTERNATIONAL","priority":1},{"id":"98767991302996019","slug":"lec","name":"LEC","region":"EMEA","priority":1}]}}"#

    static let teams = #"{"data":{"teams":[{"id":"111692118851466302","slug":"karmine-corp","name":"Karmine Corp","code":"KC","image":"http://static.lolesports.com/teams/1704714951336_KC.png","status":"active","homeLeague":{"name":"LEC","region":"EMEA"}},{"id":"98767991853197861","slug":"g2-esports","name":"G2 Esports","code":"G2","image":"http://static.lolesports.com/teams/G2-FullonDark.png","status":"active","homeLeague":{"name":"LEC","region":"EMEA"}}]}}"#

    static let schedule = #"{"data":{"schedule":{"events":[{"startTime":"2026-10-20T16:00:00Z","state":"unstarted","type":"match","blockName":"Quarts de finale","league":{"name":"Mondial","slug":"worlds"},"match":{"id":"300","teams":[{"name":"Karmine Corp","code":"KC","result":{"outcome":null,"gameWins":0}},{"name":"G2 Esports","code":"G2","result":{"outcome":null,"gameWins":0}}],"strategy":{"type":"bestOf","count":5}}}]}}}"#

    static let live = #"{"data":{"schedule":{"events":[]}}}"#
}
```

- [ ] **Step 3 : Écrire `App/Store/LogoPixels.swift`**

```swift
import CoreGraphics
import ImageIO
import UIKit

/// Décodage d'un logo pour `TeamColor` (spec §9) : miniature, puis octets RGBA. CoreGraphics ne dessine qu'en alpha
/// prémultiplié : l'appelant passe les octets par `TeamColor.unpremultiplied` avant `TeamColor.teamColor`.
enum LogoPixels {
    /// Miniature d'au plus `maxPixel` px de côté (les logos de l'API vont jusqu'à 2000 px). nil si illisible (SVG…).
    static func thumbnail(from data: Data, maxPixel: Int = 128) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// PNG de la miniature, gardé dans le dossier des logos pour l'affichage.
    static func png(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }

    /// Octets RGBA 8 bits (alpha prémultiplié) de l'image redessinée en `side` px au plus de côté.
    static func rgba(_ image: CGImage, side: Int = 64) -> [UInt8]? {
        let scale = min(1, Double(side) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}
```

- [ ] **Step 4 : Écrire `App/Store/AppStore.swift`**

```swift
import Foundation
import LoLKit
import Observation
import os

/// Données de l'appli et leurs rafraîchissements (spec §4.1, §4.4, §10).
/// Au lancement, tout ce qui est sur le disque s'affiche aussitôt ; l'API prend ensuite le relais selon `RefreshPolicy`.
/// Les vues lisent ; toute action (suivre, masquer, révéler…) passe par ici et est enregistrée tout de suite.
@MainActor
@Observable
final class AppStore {
    // MARK: Données affichées

    private(set) var follows = FollowList()
    private(set) var settings = AppSettings()
    private(set) var leagues: [League] = []
    private(set) var catalog: [Team] = []
    private(set) var schedule: [MatchEvent] = []
    /// Réponse de `getLive` ; nil si inconnue ou trop vieille : les cartes retombent alors sur le calendrier.
    private(set) var live: [MatchEvent]? = nil
    /// Ligues en pilules de l'onglet Équipes, recalculées quand ligues, équipes ou calendrier changent.
    private(set) var leaguePills: [League] = []
    /// Détails des matchs ouverts dans l'écran Détail (`getEventDetails`), par id de match.
    private(set) var details: [String: EventDetails] = [:]
    /// Dernière frame connue de chaque game, et l'heure de l'appareil à laquelle elle a été reçue.
    private(set) var snapshots: [String: GameSnapshot] = [:]
    private(set) var snapshotDates: [String: Date] = [:]
    /// Première frame de chaque game en cours : sert au chrono.
    private(set) var firstFrames: [String: Date] = [:]
    /// Games dont Riot ne fournit pas les stats (404 sur `window`).
    private(set) var statsUnavailable: Set<String> = []
    /// Le dernier appel à l'API a échoué : bandeau « lolesports ne répond pas ».
    private(set) var isFailing = false
    private(set) var lastSuccess: [DataKind: Date] = [:]

    // MARK: Interne

    private let client: LoLClient
    private let transport: any HTTPTransport
    private let files: FileStore?
    private let isPreview: Bool
    @ObservationIgnored private var lastAttempt: [DataKind: Date] = [:]
    @ObservationIgnored private var scheduleLeagueIds: [String]? = nil
    @ObservationIgnored private var matchLeftLive = false
    @ObservationIgnored private var colorsDirty = true
    @ObservationIgnored private var isRefreshing = false

    private static let log = Logger(subsystem: "Faille", category: "données")

    init(transport: any HTTPTransport = URLSessionTransport(), files: FileStore) {
        self.transport = transport
        client = LoLClient(transport: transport)
        self.files = files
        isPreview = false
        loadFromDisk(files)
    }

    /// Store figé pour les #Preview et les tests d'aperçu : aucune requête, aucun fichier.
    init(preview data: PreviewData) {
        let previewTransport = URLSessionTransport()
        transport = previewTransport
        client = LoLClient(transport: previewTransport)
        files = nil
        isPreview = true
        follows = data.follows
        settings = data.settings
        leagues = data.leagues
        catalog = data.catalog
        schedule = data.schedule
        live = data.live
        details = data.details
        snapshots = data.snapshots
        snapshotDates = data.snapshots.mapValues { _ in Date() }
        firstFrames = data.firstFrames
        statsUnavailable = data.statsUnavailable
        isFailing = data.isFailing
        if let update = data.lastUpdate {
            lastSuccess = [.schedule: update, .live: update]
        }
        recomputeDirectory()
    }

    private func loadFromDisk(_ files: FileStore) {
        follows = files.load(FollowList.self, from: .follows) ?? FollowList()
        settings = files.load(AppSettings.self, from: .settings) ?? AppSettings()
        if let cached = files.load(Cached<[League]>.self, from: .leagues) {
            leagues = cached.value
            lastSuccess[.leagues] = cached.fetchedAt
        }
        if let cached = files.load(Cached<[Team]>.self, from: .teams) {
            catalog = cached.value
            lastSuccess[.teams] = cached.fetchedAt
        }
        if let cached = files.load(Cached<SchedulePage>.self, from: .schedule) {
            schedule = cached.value.events
            scheduleLeagueIds = cached.value.leagueIds
            lastSuccess[.schedule] = cached.fetchedAt
        }
        let cachedLive = files.load(Cached<[MatchEvent]>.self, from: .live)
        live = RefreshPolicy.usableLive(cachedLive, now: Date())
        if live != nil {
            lastSuccess[.live] = cachedLive?.fetchedAt
        }
        recomputeDirectory()
    }

    // MARK: Lectures pour les vues

    /// Cartes Vitrail de l'onglet Matchs : en direct d'abord, puis par prochain match (spec §5.1).
    var cards: [TeamCard] {
        TeamCards.build(follows: follows, schedule: schedule, live: live)
    }

    /// Dernière mise à jour réussie du calendrier ou du direct.
    var lastUpdate: Date? {
        [lastSuccess[.schedule], lastSuccess[.live]].compactMap { $0 }.max()
    }

    /// Texte du bandeau d'erreur ; nil quand l'API répond (spec §10).
    var bannerText: String? {
        isFailing ? Format.offlineBanner(lastUpdate: lastUpdate) : nil
    }

    /// Un match par id : le direct fait foi, sinon le calendrier.
    func event(id: String) -> MatchEvent? {
        live?.first(where: { $0.id == id }) ?? schedule.first(where: { $0.id == id })
    }

    /// L'équipe suivie qui correspond à cette équipe d'un match (id, nom, logo ; jamais le code seul).
    func followed(_ team: MatchTeam) -> FollowedTeam? {
        follows.teams.first { team.isSame(as: $0) }
    }

    func isMasked(_ teams: [MatchTeam], matchId: String) -> Bool {
        SpoilerPolicy.isMasked(teams, matchId: matchId, follows: follows, revealed: settings.revealedMatchIds)
    }

    func scoreLine(_ event: MatchEvent) -> ScoreLine {
        Presenter.scoreLine(for: event, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// État d'un match en direct pour sa carte : anti-spoiler, phase, score, chrono et stats viennent de LoLKit.
    func liveState(for event: MatchEvent) -> LiveMatchState {
        state(details: EventDetails(event: event), statsDisabled: event.statsDisabled)
    }

    /// Même chose depuis `getEventDetails` (écran Détail) ; nil tant que les détails ne sont pas chargés.
    func detailState(matchId: String) -> LiveMatchState? {
        guard let loaded = self.details[matchId] else { return nil }
        return state(details: loaded, statsDisabled: loaded.statsDisabled || event(id: matchId)?.statsDisabled == true)
    }

    private func state(details: EventDetails, statsDisabled: Bool) -> LiveMatchState {
        let game = details.currentGame
        let unavailable = game.map { statsUnavailable.contains($0.id) } ?? false
        return LiveMatchBuilder.state(
            details: details,
            snapshot: game.flatMap { snapshots[$0.id] },
            firstFrameTime: game.flatMap { firstFrames[$0.id] },
            statsDisabled: statsDisabled || unavailable,
            follows: follows,
            revealed: settings.revealedMatchIds,
            // Heure de réception de la frame : le chrono démarre au bon endroit et tourne ensuite tout seul.
            now: game.flatMap { snapshotDates[$0.id] } ?? Date()
        )
    }

    func teams(in league: League) -> [Team] {
        TeamDirectory.teams(in: league, catalog: catalog, schedule: schedule)
    }

    func search(_ query: String) -> [Team] {
        TeamDirectory.search(query, in: catalog)
    }

    /// Fichier du logo en cache (miniature PNG), s'il a déjà été téléchargé.
    func logoFile(for image: String?) -> URL? {
        guard let image, let files else { return nil }
        let name = LogoFileName.name(for: image)
        return files.hasLogo(named: name) ? files.logoURL(named: name) : nil
    }

    // MARK: Actions de l'utilisateur

    /// Étoile d'une équipe du catalogue : suivre ou ne plus suivre.
    func toggleFollow(_ team: Team) {
        if follows.contains(id: team.id) {
            follows.unfollow(id: team.id)
        } else {
            follows.follow(team)
            colorsDirty = true
        }
        saveFollows()
        // Une équipe d'une autre ligue change les ligues du calendrier : la politique le voit tout de suite.
        Task { await refreshDue(opening: false) }
    }

    func unfollow(id: String) {
        follows.unfollow(id: id)
        saveFollows()
    }

    /// Œil d'une équipe suivie (spec §8).
    func setSpoilerFree(_ on: Bool, id: String) {
        follows.setSpoilerFree(on, id: id)
        saveFollows()
        Task { await refreshLiveStats() }
    }

    /// Couleur choisie à la main ; nil = revenir à la couleur tirée du logo.
    func setColorOverride(_ hex: String?, id: String) {
        follows.setColorOverride(hex, id: id)
        saveFollows()
    }

    /// « Toucher pour révéler » (spec §8) : mémorisé pour ce match, sur toutes les surfaces.
    func reveal(matchId: String) {
        settings.revealedMatchIds.insert(matchId)
        saveSettings()
        Task { await refreshLiveStats() }
    }

    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    func setLiveActivityMode(_ mode: LiveActivityMode) {
        settings.liveActivityMode = mode
        saveSettings()
    }

    // MARK: Rafraîchissements

    /// Boucle du premier plan, lancée par `.task(id: scenePhase)` : s'arrête, requêtes comprises, quand la tâche est annulée.
    func poll() async {
        var opening = true
        while !Task.isCancelled {
            await refreshDue(opening: opening)
            opening = false
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        }
    }

    /// Tirer pour rafraîchir : calendrier et direct relus, comme à l'ouverture.
    func refreshNow() async {
        await refreshDue(opening: true)
    }

    /// Un cycle : ce que `RefreshPolicy` juge dû, dans l'ordre ligues → équipes → direct → calendrier.
    func refreshDue(opening: Bool) async {
        guard !isPreview, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let due = RefreshPolicy.due(refreshInput(opening: opening))
        if due.contains(.leagues) { await fetch(.leagues) }
        if due.contains(.teams) { await fetch(.teams) }
        if due.contains(.live) { await fetch(.live) }
        // Le calendrier dépend des ligues (peut-être tout juste chargées) et des matchs sortis du direct : on redemande.
        if RefreshPolicy.due(refreshInput(opening: opening)).contains(.schedule) { await fetch(.schedule) }
        if due.contains(.live) { await refreshLiveStats() }
        if colorsDirty && !isFailing { await updateTeamColors() }
    }

    private var wantedLeagueIds: [String] {
        ScheduleQuery.leagueIds(follows: follows, leagues: leagues)
    }

    private func refreshInput(opening: Bool) -> RefreshInput {
        RefreshInput(now: Date(), opening: opening, lastSuccess: lastSuccess, lastAttempt: lastAttempt,
                     scheduleLeagueIds: scheduleLeagueIds, wantedLeagueIds: wantedLeagueIds, matchLeftLive: matchLeftLive)
    }

    private func fetch(_ kind: DataKind) async {
        let started = Date()
        let previousAttempt = lastAttempt[kind]
        lastAttempt[kind] = started
        do {
            switch kind {
            case .leagues:
                let value = try await client.leagues()
                leagues = value
                files?.save(Cached(value: value, fetchedAt: started), to: .leagues)
            case .teams:
                let value = try await client.teams()
                catalog = value
                follows.refresh(from: value) // renommages de sponsor, nouveaux logos
                saveFollows()
                colorsDirty = true
                files?.save(Cached(value: value, fetchedAt: started), to: .teams)
            case .schedule:
                let ids = wantedLeagueIds
                let events = try await client.schedule(leagueIds: ids)
                schedule = events
                scheduleLeagueIds = ids
                matchLeftLive = false
                files?.save(Cached(value: SchedulePage(leagueIds: ids, events: events), fetchedAt: started), to: .schedule)
            case .live:
                let events = try await client.live()
                if RefreshPolicy.leftLive(previous: live, current: events) {
                    matchLeftLive = true // spec §10 : relire getSchedule aussitôt
                }
                live = events
                files?.save(Cached(value: events, fetchedAt: started), to: .live)
            }
            lastSuccess[kind] = started
            isFailing = false
            if kind != .live { recomputeDirectory() }
        } catch {
            if Task.isCancelled {
                // Passage en arrière-plan : ce n'est pas une panne, on réessaiera à la prochaine ouverture.
                lastAttempt[kind] = previousAttempt
                return
            }
            isFailing = true
            Self.log.error("\(kind.rawValue, privacy: .public) : \(String(describing: error), privacy: .public)")
            if let apiError = error as? LoLAPIError, apiError == .http(status: 403) {
                Self.log.fault("403 sur persisted/gw : la clé publique a sans doute changé (LoLClient.publicAPIKey)")
            }
            if kind == .live, let success = lastSuccess[.live], Date().timeIntervalSince(success) > RefreshPolicy.liveTrust {
                live = nil // direct trop vieux : les cartes retombent sur le calendrier
            }
        }
    }

    /// Stats des matchs en direct des équipes suivies, pour leurs cartes (cadence du direct). Les matchs masqués
    /// et ceux sans stats ne sont pas demandés.
    func refreshLiveStats() async {
        guard !isPreview, let live else { return }
        for event in live where follows.involves(event.match.teams) {
            guard !event.statsDisabled, !isMasked(event.match.teams, matchId: event.id),
                  let game = EventDetails(event: event).currentGame else { continue }
            await loadWindow(gameId: game.id, inProgress: true)
        }
    }

    /// Dernière frame d'une game ; pour une game en cours, aussi sa première frame (chrono), une seule fois.
    /// Pour une game terminée, `startingTime` récent renvoie les dernières frames de la game.
    func loadWindow(gameId: String, inProgress: Bool) async {
        guard !isPreview, !statsUnavailable.contains(gameId) else { return }
        do {
            if inProgress && firstFrames[gameId] == nil {
                firstFrames[gameId] = try await client.window(gameId: gameId, startingTime: nil).firstFrameTime
            }
            let fetchedAt = Date()
            let window = try await client.window(gameId: gameId, startingTime: LiveStatsTime.startingTime(now: fetchedAt))
            if let snapshot = window.latestSnapshot() {
                snapshots[gameId] = snapshot
                snapshotDates[gameId] = fetchedAt
            }
        } catch LoLAPIError.statsDisabled {
            statsUnavailable.insert(gameId)
        } catch {
            // Flux vide (game pas commencée), réseau : on garde la dernière frame connue.
            if !Task.isCancelled {
                Self.log.info("window \(gameId, privacy: .public) : \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// `getEventDetails` d'un match (écran Détail).
    func loadDetails(matchId: String) async {
        guard !isPreview else { return }
        do {
            details[matchId] = try await client.eventDetails(matchId: matchId)
        } catch {
            if !Task.isCancelled {
                Self.log.info("détails \(matchId, privacy: .public) : \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Couleur automatique de chaque équipe suivie, tirée de son logo (spec §9) ; refaite quand le logo change d'URL.
    private func updateTeamColors() async {
        colorsDirty = false
        guard let files else { return }
        for team in follows.teams {
            guard let image = team.image, let url = ImageURL.secure(image) else { continue }
            let name = LogoFileName.name(for: image)
            if team.autoColorHex != nil && files.hasLogo(named: name) { continue }
            do {
                let response = try await transport.get(url, headers: [:])
                guard response.status == 200, let thumbnail = LogoPixels.thumbnail(from: response.body) else {
                    // Logo absent ou illisible (SVG…) : accent, pour ne pas le retélécharger à chaque cycle.
                    follows.setAutoColor(RGB.accent.hex, id: team.id)
                    continue
                }
                if let png = LogoPixels.png(thumbnail) {
                    files.saveLogo(png, named: name)
                }
                let color = LogoPixels.rgba(thumbnail).map { TeamColor.teamColor(rgba: TeamColor.unpremultiplied($0)) } ?? .accent
                follows.setAutoColor(color.hex, id: team.id)
            } catch {
                colorsDirty = true // réseau : nouvel essai au prochain cycle sans panne
            }
        }
        saveFollows()
    }

    private func recomputeDirectory() {
        leaguePills = TeamDirectory.leagues(leagues, catalog: catalog, schedule: schedule)
    }

    private func saveFollows() {
        files?.save(follows, to: .follows)
    }

    private func saveSettings() {
        files?.save(settings, to: .settings)
    }
}
```

- [ ] **Step 5 : Écrire `App/Store/AppStore+Tint.swift`**

```swift
import LoLKit
import SwiftUI

extension AppStore {
    /// Couleur Vitrail d'une équipe d'un match si elle est suivie ; nil = verre neutre (spec §9).
    func tint(for team: MatchTeam) -> Color? {
        followed(team).map { Palette.team($0.colorHex) }
    }
}
```

- [ ] **Step 6 : Remplacer `App/FailleApp.swift` (contenu complet)**

```swift
import SwiftUI

@main
struct FailleApp: App {
    @State private var store = AppStore(files: FileStore(directory: AppGroup.directory))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if Self.isRunningTests {
                // Tests hébergés : ni interface ni réseau, les tests rendent leurs propres fenêtres.
                Color.clear
            } else {
                RootView()
                    .environment(store)
                    // Rafraîchit tant que la scène est active ; la tâche (et ses requêtes) est annulée en arrière-plan.
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        await store.poll()
                    }
            }
        }
    }

    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
}
```

- [ ] **Step 7 : Remplacer `App/RootView.swift` (contenu complet)**

```swift
import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    PlaceholderScreen(title: "Mes équipes")
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack {
                    PlaceholderScreen(title: "Équipes")
                }
            }
        }
        .tint(Palette.accent)
    }
}

/// Onglet pas encore construit (retiré à la Task 10).
private struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title, subtitle: "bientôt")
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
```

Note : `Tab(_:image:value:content:)` existe depuis iOS 18. Si le SDK le refuse, utiliser l'ancienne forme : contenu de chaque onglet suivi de `.tabItem { Label("Matchs", image: Icon.trophy.assetName) }.tag(AppTab.matches)`.

- [ ] **Step 8 : Écrire les tests du store** — `Tests/FailleTests/StoreTests.swift`

```swift
import Foundation
import Testing
@testable import Faille

/// Store branché sur `StubTransport` et un dossier temporaire : chargement, disque, panne (spec §4.4, §10).
@MainActor
@Suite(.serialized)
struct StoreTests {
    private func temporaryFiles() -> FileStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-tests-\(UUID().uuidString)", isDirectory: true)
        return FileStore(directory: directory)
    }

    @Test func firstRefreshLoadsAndPersistsEverything() async throws {
        let files = temporaryFiles()
        let store = AppStore(transport: StubTransport(), files: files)
        await store.refreshDue(opening: true)
        #expect(store.leagues.count == 2)
        #expect(store.catalog.count == 2)
        #expect(store.live?.isEmpty == true)
        // Ligues chargées dans le même cycle : le calendrier (Mondial) suit aussitôt.
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.isFailing == false)

        // Un nouveau store relit tout depuis le disque, sans réseau.
        let offline = AppStore(transport: StubTransport(failing: true), files: files)
        #expect(offline.catalog.count == 2)
        #expect(offline.schedule.map(\.id) == ["300"])
        #expect(offline.leaguePills.map(\.slug) == ["worlds", "lec"])
    }

    @Test func followIsSavedAndFailuresKeepCachedData() async throws {
        let files = temporaryFiles()
        let store = AppStore(transport: StubTransport(), files: files)
        await store.refreshDue(opening: true)
        let kc = try #require(store.catalog.first { $0.code == "KC" })
        store.toggleFollow(kc)
        store.setSpoilerFree(true, id: kc.id)

        let failing = AppStore(transport: StubTransport(failing: true), files: files)
        #expect(failing.follows.teams.map(\.code) == ["KC"])
        #expect(failing.follows.teams.first?.spoilerFree == true)
        await failing.refreshDue(opening: true)
        #expect(failing.isFailing)
        #expect(failing.schedule.map(\.id) == ["300"])
        #expect(failing.bannerText?.hasPrefix("lolesports ne répond pas") == true)
        #expect(failing.cards.first?.next?.id == "300")
    }
}
```

- [ ] **Step 9 : Commit**

```bash
git add Shared/Preview App/Store App/FailleApp.swift App/RootView.swift Tests/FailleTests/StoreTests.swift
git commit -m "feat(app): store de données — cache disque, rafraîchissements, couleurs d'équipe" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10 : Pousser et suivre la CI iOS**

```bash
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts ; le log d'`apercus` montre `firstRefreshLoadsAndPersistsEverything` et `followIsSavedAndFailuresKeepCachedData` réussis. Si le lien échoue sur un symbole de LoLKit (`Undefined symbols … LoLKit`) dans la cible de tests : vérifier `DEAD_CODE_STRIPPING: "NO"` en Debug ; en dernier recours, ajouter `- package: LoLKit` aux dépendances de `FailleTests` et le noter dans le rapport.

---

### Task 8 : Réglages et À propos

**Files :**
- Create : `App/Settings/SettingsView.swift`
- Test : `Tests/FailleTests/SettingsSnapshotTests.swift`

**Interfaces :**
- Consumes : `AppStore.settings`, `AppStore.setLiveActivityMode(_:)`, `LiveActivityMode`, `AppGroup.identifier`, `LoLKitInfo.version`, composants T6, `Snapshot.write`, `PreviewData.standard`.
- Produces : `struct SettingsView: View` (feuille avec son propre `NavigationStack`, bouton « Fermer ») ; `struct AboutView: View` ; aperçu `07-reglages.png`.

- [ ] **Step 1 : Écrire `App/Settings/SettingsView.swift`**

```swift
import LoLKit
import SwiftUI

/// Réglages (spec §5.4) : mode de la Live Activity (utilisé à l'étape 4) et À propos.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var mode = LiveActivityMode.automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel(text: "Live Activity")
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Live Activity", selection: $mode) {
                            Text("Automatique").tag(LiveActivityMode.automatic)
                            Text("Manuelle").tag(LiveActivityMode.manual)
                        }
                        .pickerStyle(.segmented)
                        Text(explanation)
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                        Text("Les Live Activities arrivent dans une prochaine version de Faille ; ce choix est déjà enregistré.")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                    .glassCard(radius: Radius.inner, padding: 14)

                    SectionLabel(text: "Faille")
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Text("À propos").font(Typo.body)
                            Spacer()
                            IconView(icon: .arrow, size: 15)
                                .foregroundStyle(Palette.secondary)
                        }
                        .foregroundStyle(Palette.text)
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .abyssBackground()
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .onAppear { mode = store.settings.liveActivityMode }
        .onChange(of: mode) { _, newValue in
            store.setLiveActivityMode(newValue)
        }
    }

    private var explanation: String {
        switch mode {
        case .automatic:
            return "Automatique : chaque match en direct d'une équipe suivie s'affiche tout seul sur l'écran verrouillé (3 au plus)."
        case .manual:
            return "Manuelle : rien ne s'affiche tout seul, on épingle un match depuis son écran Détail."
        }
    }
}

/// À propos : source des données, version, stockage.
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                block("Faille", "Version \(Self.version)")
                block("Données", "Matchs, équipes et stats viennent de l'API de lolesports.com (non officielle) et du flux livestats de Riot, avec environ une minute de retard sur le direct. Usage strictement personnel.")
                block("Stockage", AppGroup.identifier.map { "Groupe d'apps : \($0)" }
                      ?? "Aucun groupe d'apps : les données restent dans l'appli seule.")
                Text("Police Sora, sous licence SIL Open Font License.")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            .padding(16)
        }
        .abyssBackground()
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Typo.headline)
                .foregroundStyle(Palette.text)
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    /// « 0.1.0 (1) · LoLKit 0.1.0 »
    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build)) · LoLKit \(LoLKitInfo.version)"
    }
}

#Preview {
    SettingsView().environment(AppStore(preview: .standard))
}
```

- [ ] **Step 2 : Écrire l'aperçu** — `Tests/FailleTests/SettingsSnapshotTests.swift`

```swift
import Foundation
import Testing
@testable import Faille

extension ApercuTests {
    @Test func settingsScreen() async throws {
        let url = try await Snapshot.write(SettingsView().environment(AppStore(preview: .standard)), named: "07-reglages")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
```

- [ ] **Step 3 : Commit, push, CI**

```bash
git add App/Settings Tests/FailleTests/SettingsSnapshotTests.swift
git commit -m "feat(app): réglages (mode Live Activity) et à propos" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts.

- [ ] **Step 4 : Vérifier la présence de l'aperçu**

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls "$HOME/Downloads/faille-apercus-<id>"
```

Expected : `00-da.png` et `07-reglages.png`.

---

### Task 9 : Onglet Équipes

**Files :**
- Create : `App/Teams/TeamsView.swift`
- Create : `App/Teams/TeamRows.swift`
- Create : `App/Teams/TeamColorSheet.swift`
- Modify : `App/RootView.swift` (contenu complet ci-dessous)
- Test : `Tests/FailleTests/TeamsSnapshotTests.swift`

**Interfaces :**
- Consumes : `AppStore.follows/catalog/leaguePills/bannerText/isFailing`, `AppStore.teams(in:)`, `.search(_:)`, `.logoFile(for:)`, `.toggleFollow(_:)`, `.unfollow(id:)`, `.setSpoilerFree(_:id:)`, `.setColorOverride(_:id:)`, `Format.followCount(_:)`, `RGB(color:)`, `Palette.team(_:)`, composants T6, `SettingsView` (T8).
- Produces : `struct TeamsView: View` ; `struct FollowedTeamRow: View` ; `struct CatalogTeamRow: View` ; `struct TeamColorSheet: View` ; aperçu `03-equipes.png`.

- [ ] **Step 1 : Écrire `App/Teams/TeamRows.swift`**

```swift
import LoLKit
import SwiftUI

/// Ligne de « Mes équipes » : badge, nom, ligue, œil (anti-spoiler), étoile (ne plus suivre).
struct FollowedTeamRow: View {
    let team: FollowedTeam
    let logoFile: URL?
    let onToggleSpoiler: () -> Void
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TeamBadge(code: team.code, image: team.image, logoFile: logoFile, tint: Palette.team(team.colorHex), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onToggleSpoiler) {
                IconView(icon: team.spoilerFree ? .eyeOff : .eye, size: 20)
                    .foregroundStyle(team.spoilerFree ? Palette.text : Palette.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(team.spoilerFree ? "Afficher les scores" : "Masquer les scores")
            Button(action: onUnfollow) {
                IconView(icon: .starFill, size: 20)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Ne plus suivre")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let parts = [team.homeLeagueName, team.spoilerFree ? "sans spoiler" : nil].compactMap { $0 }
        return parts.isEmpty ? "sans ligue d'attache" : parts.joined(separator: " · ")
    }
}

/// Ligne d'une équipe du catalogue (ligue ou recherche) : badge, nom, ligue, étoile.
struct CatalogTeamRow: View {
    let team: Team
    let followed: Bool
    let logoFile: URL?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TeamBadge(code: team.code, image: team.image, logoFile: logoFile, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                if let league = team.homeLeague?.name {
                    Text(league)
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onToggle) {
                IconView(icon: followed ? .starFill : .star, size: 20)
                    .foregroundStyle(followed ? Palette.accent : Palette.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(followed ? "Ne plus suivre" : "Suivre")
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2 : Écrire `App/Teams/TeamColorSheet.swift`**

```swift
import LoLKit
import SwiftUI

/// « Changer la couleur » (appui long sur une équipe suivie, spec §5.2) : sélecteur, aperçu Vitrail, ou retour à l'automatique.
struct TeamColorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let team: FollowedTeam
    @State private var color: Color

    init(team: FollowedTeam) {
        self.team = team
        _color = State(initialValue: Palette.team(team.colorHex))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: team.name, dot: color)
                    HStack(spacing: 10) {
                        TeamBadge(code: team.code, tint: color, size: 34)
                        Text(team.code).font(Typo.score)
                    }
                }
                .foregroundStyle(Palette.text)
                .glassCard(tint: color)
                ColorPicker("Couleur de l'équipe", selection: $color, supportsOpacity: false)
                    .font(Typo.body)
                    .foregroundStyle(Palette.text)
                    .glassCard(radius: Radius.inner, padding: 14)
                Button("Couleur automatique (tirée du logo)") {
                    store.setColorOverride(nil, id: team.id)
                    dismiss()
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.accent)
                Spacer()
            }
            .padding(16)
            .abyssBackground()
            .navigationTitle("Couleur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        store.setColorOverride(RGB(color: color).hex, id: team.id)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 3 : Écrire `App/Teams/TeamsView.swift`**

```swift
import LoLKit
import SwiftUI

/// Onglet Équipes (spec §5.2) : recherche, mes équipes (œil, étoile, couleur), toutes les ligues en pilules, réglages.
struct TeamsView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var selectedLeagueId: String?
    @State private var showSettings = false
    @State private var colorTeam: FollowedTeam?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Équipes", subtitle: Format.followCount(store.follows.teams.count)) {
                    Button { showSettings = true } label: {
                        IconView(icon: .settings, size: 22)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.text)
                    .accessibilityLabel("Réglages")
                }
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                }
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    myTeams
                    leagueSection
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(store)
        }
        .sheet(item: $colorTeam) { team in
            TeamColorSheet(team: team).environment(store)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            IconView(icon: .search, size: 16)
                .foregroundStyle(Palette.secondary)
            TextField("", text: $query, prompt: Text("Rechercher une équipe").foregroundStyle(Palette.secondary))
                .font(Typo.body)
                .foregroundStyle(Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    IconView(icon: .off, size: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel("Effacer")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Palette.glassBorder, lineWidth: 1))
    }

    @ViewBuilder private var myTeams: some View {
        SectionLabel(text: "Mes équipes")
        if store.follows.teams.isEmpty {
            NoteCard(icon: .star, text: "Touche l'étoile d'une équipe pour la suivre.")
        } else {
            VStack(spacing: 4) {
                ForEach(store.follows.teams) { team in
                    FollowedTeamRow(
                        team: team,
                        logoFile: store.logoFile(for: team.image),
                        onToggleSpoiler: { store.setSpoilerFree(!team.spoilerFree, id: team.id) },
                        onUnfollow: { store.unfollow(id: team.id) }
                    )
                    .contextMenu {
                        Button("Changer la couleur") { colorTeam = team }
                        Button("Couleur automatique") { store.setColorOverride(nil, id: team.id) }
                    }
                }
            }
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }

    @ViewBuilder private var leagueSection: some View {
        SectionLabel(text: "Toutes les ligues")
        let pills = store.leaguePills
        if let first = pills.first {
            let selected = pills.first(where: { $0.id == selectedLeagueId }) ?? first
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(pills) { league in
                        PillButton(selected: league.id == selected.id, action: { selectedLeagueId = league.id }) {
                            Text(league.name)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            teamList(store.teams(in: selected))
        } else {
            NoteCard(icon: .refresh, text: store.isFailing ? "Ligues indisponibles pour l'instant." : "Chargement des ligues…")
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = store.search(query)
        SectionLabel(text: "Résultats")
        if results.isEmpty {
            NoteCard(icon: .search, text: store.catalog.isEmpty ? "Chargement des équipes…" : "Aucune équipe ne correspond.")
        } else {
            teamList(results)
        }
    }

    private func teamList(_ teams: [Team]) -> some View {
        VStack(spacing: 4) {
            ForEach(teams) { team in
                CatalogTeamRow(team: team, followed: store.follows.contains(id: team.id),
                               logoFile: store.logoFile(for: team.image)) {
                    store.toggleFollow(team)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 12)
    }
}

#Preview {
    NavigationStack { TeamsView() }.environment(AppStore(preview: .standard))
}
```

- [ ] **Step 4 : Remplacer `App/RootView.swift` (contenu complet : l'onglet Équipes devient réel)**

```swift
import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    PlaceholderScreen(title: "Mes équipes")
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack {
                    TeamsView()
                }
            }
        }
        .tint(Palette.accent)
    }
}

/// Onglet pas encore construit (retiré à la Task 10).
private struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title, subtitle: "bientôt")
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
```

- [ ] **Step 5 : Écrire l'aperçu** — `Tests/FailleTests/TeamsSnapshotTests.swift`

```swift
import Foundation
import Testing
@testable import Faille

extension ApercuTests {
    @Test func teamsScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .teams).environment(AppStore(preview: .standard)), named: "03-equipes")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
```

- [ ] **Step 6 : Commit, push, CI**

```bash
git add App/Teams App/RootView.swift Tests/FailleTests/TeamsSnapshotTests.swift
git commit -m "feat(app): onglet Équipes — recherche, suivi, anti-spoiler, couleur, ligues" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts.

- [ ] **Step 7 : Vérifier la présence de l'aperçu**

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls "$HOME/Downloads/faille-apercus-<id>"
```

Expected : `00-da.png`, `03-equipes.png`, `07-reglages.png`. À juger par le contrôleur : « Équipes » / « 3 suivies », engrenage, champ de recherche, KC / T1 (« LCK · sans spoiler », œil barré) / GEN avec étoiles pleines, pilules « Mondial » (choisie), « La Ligue Française », « LEC », « LCK », « LPL », liste des équipes du Mondial, barre d'onglets flottante.

---

### Task 10 : Onglet Matchs (cartes Vitrail, version B)

**Files :**
- Create : `App/Matches/MatchParts.swift`
- Create : `App/Matches/TeamCardView.swift`
- Create : `App/Matches/MatchesView.swift`
- Modify : `App/RootView.swift` (contenu complet ci-dessous)
- Test : `Tests/FailleTests/MatchesSnapshotTests.swift`

**Interfaces :**
- Consumes : `AppStore.cards`, `.liveState(for:)`, `.scoreLine(_:)`, `.follows.displayOrder(_:preferring:)`, `.tint(for:)`, `.logoFile(for:)`, `.reveal(matchId:)`, `.refreshNow()`, `.bannerText` ; `LiveMatchState` (`phase`, `seriesScore`, `gameNumber`, `gameClockStart`, `gameClockStoppedAt`, `stats`, `statsAvailable`, `spoilerFree`) ; `ScoreLine` (`teamCodes`, `score`, `isMasked`) ; `Format.cardsSubtitle`, `.followCount`, `.matchDate`, `.goldDiff`, `.score`, `.clock`.
- Produces : `struct MatchRoute: Hashable { let matchId: String }` ; `struct MatchesView: View { let openTeams: () -> Void }` ; `struct WelcomeCard` ; `struct TeamCardView` ; pièces réutilisées par le Détail : `func reorder<T>(_ values: [T], _ order: [Int]) -> [T]?`, `struct LiveChipText(state:opponent:)`, `struct ScoreRow(teams:score:tints:large:)`, `struct MiniStats(stats:tint:)`, `struct RevealButton(action:)` ; aperçus `01-matchs.png`, `02-matchs-vide.png`, `08-bandeau-erreur.png`.

- [ ] **Step 1 : Écrire `App/Matches/MatchParts.swift`**

```swift
import LoLKit
import SwiftUI

/// Remet des valeurs d'un match (score, stats) dans l'ordre d'affichage ; nil si les tailles ne correspondent pas.
func reorder<T>(_ values: [T], _ order: [Int]) -> [T]? {
    guard values.count == order.count, order.allSatisfy({ values.indices.contains($0) }) else { return nil }
    return order.map { values[$0] }
}

/// « En direct · Game 2 · 18:42 » : le chrono tourne seul (minuteur natif), figé si la game est en pause ou finie.
/// Masqué (spec §8) : « En direct » ou « En direct vs FLY », rien d'autre.
struct LiveChipText: View {
    let state: LiveMatchState
    let opponent: String?

    var body: some View {
        if state.spoilerFree {
            Text(opponent.map { "En direct vs \($0)" } ?? "En direct")
        } else {
            HStack(spacing: 0) {
                Text(prefix)
                if state.phase == .inGame, let start = state.gameClockStart {
                    Text(" · ")
                    if let stopped = state.gameClockStoppedAt {
                        Text(Format.clock(stopped.timeIntervalSince(start)))
                    } else {
                        Text(start, style: .timer)
                    }
                }
            }
            .monospacedDigit()
        }
    }

    private var prefix: String {
        switch state.phase {
        case .inGame:
            return state.gameNumber.map { "En direct · Game \($0)" } ?? "En direct"
        case .betweenGames:
            return state.gameNumber.map { "En direct · Game \($0) bientôt" } ?? "En direct"
        case .finished:
            return "Terminé"
        case .upcoming:
            return "Bientôt"
        }
    }
}

/// « [KC] KC   1 – 0   C9 [C9] » : badges, codes, score de série au centre (« vs » sans score).
struct ScoreRow: View {
    @Environment(AppStore.self) private var store
    let teams: [MatchTeam]
    let score: [Int]?
    let tints: [Color?]
    var large = false

    var body: some View {
        HStack(spacing: 8) {
            if let left = teams.first {
                badge(left, tint: tints.first ?? nil)
                Text(left.code)
                    .font(Typo.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let score {
                Text(Format.score(score))
                    .font(large ? Typo.scoreLarge : Typo.score)
                    .monospacedDigit()
            } else {
                Text("vs")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            if teams.count > 1 {
                Text(teams[1].code)
                    .font(Typo.headline)
                    .lineLimit(1)
                badge(teams[1], tint: tints.count > 1 ? tints[1] : nil)
            }
        }
    }

    private func badge(_ team: MatchTeam, tint: Color?) -> some View {
        TeamBadge(code: team.code, image: team.image, logoFile: store.logoFile(for: team.image), tint: tint,
                  size: large ? 38 : 30)
    }
}

/// Ligne de stats d'une carte (spec §5.1) : kills, écart de gold, drakes, tours ; équipe de gauche d'abord.
struct MiniStats: View {
    let stats: [TeamStats]
    let tint: Color

    var body: some View {
        if stats.count == 2 {
            let diff = stats[0].gold - stats[1].gold
            HStack(spacing: 14) {
                item(.swords, "\(stats[0].kills) – \(stats[1].kills)")
                HStack(spacing: 4) {
                    IconView(icon: .gold, size: 13)
                    Text(Format.goldDiff(diff))
                        .font(Sora.font(12, .bold))
                        .foregroundStyle(diff > 0 ? tint : Palette.secondary)
                }
                item(.drake, "\(stats[0].dragons.count) – \(stats[1].dragons.count)")
                item(.tower, "\(stats[0].towers) – \(stats[1].towers)")
            }
            .font(Typo.secondaryMedium)
            .monospacedDigit()
        }
    }

    private func item(_ icon: Icon, _ text: String) -> some View {
        HStack(spacing: 4) {
            IconView(icon: icon, size: 13)
            Text(text)
        }
    }
}

/// « Score masqué · toucher pour révéler » (spec §8) : la révélation est mémorisée pour ce match.
struct RevealButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                IconView(icon: .eyeOff, size: 13)
                Text("Score masqué · ")
                Text("toucher pour révéler")
                    .foregroundStyle(Palette.accent)
            }
            .font(Typo.secondaryMedium)
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2 : Écrire `App/Matches/TeamCardView.swift`**

```swift
import LoLKit
import SwiftUI

/// Carte Vitrail d'une équipe suivie (spec §5.1) : en direct, prochain, dernier.
/// Chaque match est un lien vers son Détail ; l'anti-spoiler (§8) vient de LoLKit.
struct TeamCardView: View {
    @Environment(AppStore.self) private var store
    let card: TeamCard

    private var tint: Color {
        Palette.team(card.team.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: header, dot: tint)
            if let live = card.live {
                liveBlock(live)
            }
            if let next = card.next {
                nextRow(next)
            }
            if let last = card.last {
                lastRow(last)
            }
            if card.live == nil && card.next == nil && card.last == nil {
                Text("Aucun match dans le calendrier récent")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }

    private var header: String {
        [card.team.name, card.team.homeLeagueName].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func liveBlock(_ event: MatchEvent) -> some View {
        let state = store.liveState(for: event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let teams = order.map { event.match.teams[$0] }
        NavigationLink(value: MatchRoute(matchId: event.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip {
                        IconView(icon: .live, size: 12)
                        LiveChipText(state: state, opponent: teams.count == 2 ? teams[1].code : nil)
                    }
                    if state.spoilerFree {
                        Chip(muted: true) {
                            IconView(icon: .eyeOff, size: 12)
                            Text("masqué")
                        }
                    }
                }
                if !state.spoilerFree {
                    ScoreRow(teams: teams, score: state.seriesScore.flatMap { reorder($0, order) },
                             tints: teams.map { store.tint(for: $0) })
                    if let stats = state.stats.flatMap({ reorder($0, order) }) {
                        MiniStats(stats: stats, tint: tint)
                    } else if !state.statsAvailable {
                        Text("Stats live non fournies par Riot")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if state.spoilerFree {
            RevealButton { store.reveal(matchId: event.id) }
        }
    }

    /// « GEN vs FUR » / « Prochain · jeu. 16 oct. · 11:00 » ; si l'équipe joue déjà : « Ensuite · … vs GEN ».
    private func nextRow(_ event: MatchEvent) -> some View {
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let codes = reorder(line.teamCodes, order) ?? line.teamCodes
        let date = Format.matchDate(event.startTime)
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if card.live == nil {
                        Text(codes.joined(separator: " vs "))
                            .font(Typo.bodyMedium)
                        Text("Prochain · \(date)")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    } else {
                        Text("Ensuite · \(date) vs \(codes.last ?? "")")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                IconView(icon: .clock, size: 16)
                    .foregroundStyle(Palette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// « Dernier · GEN 3 – 0 HLE » ; masqué : « Dernier · T1 vs GEN · masqué » (aucun résultat, spec §8).
    private func lastRow(_ event: MatchEvent) -> some View {
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let codes = reorder(line.teamCodes, order) ?? line.teamCodes
        let text: String
        if let score = line.score.flatMap({ reorder($0, order) }), score.count == 2, codes.count == 2 {
            text = "Dernier · \(codes[0]) \(score[0]) – \(score[1]) \(codes[1])"
        } else {
            text = "Dernier · \(codes.joined(separator: " vs ")) · \(line.isMasked ? "masqué" : "terminé")"
        }
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3 : Écrire `App/Matches/MatchesView.swift`**

```swift
import LoLKit
import SwiftUI

/// Destination de navigation : le Détail d'un match (branchée dans `RootView` à la Task 11).
struct MatchRoute: Hashable {
    let matchId: String
}

/// Onglet Matchs, version B (spec §5.1) : « Mes équipes », une carte Vitrail par équipe suivie, tirer pour rafraîchir.
struct MatchesView: View {
    @Environment(AppStore.self) private var store
    let openTeams: () -> Void

    var body: some View {
        let cards = store.cards
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Mes équipes", subtitle: cards.isEmpty ? Format.followCount(0) : Format.cardsSubtitle(cards))
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                }
                if cards.isEmpty {
                    WelcomeCard(action: openTeams)
                } else {
                    ForEach(cards) { card in
                        TeamCardView(card: card)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.refreshNow() }
        .abyssBackground()
        .navigationTitle("Matchs")
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Aucune équipe suivie : message d'accueil et bouton vers l'onglet Équipes (spec §5.1).
struct WelcomeCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bienvenue dans Faille")
                .font(Typo.headline)
            Text("Suis tes équipes pour voir ici leurs matchs en direct, le prochain et le dernier résultat.")
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
            Button(action: action) {
                HStack(spacing: 6) {
                    IconView(icon: .star, size: 15)
                    Text("Choisir mes équipes")
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.abyss)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Palette.accent, in: Capsule())
                .shadow(color: Palette.accent.opacity(0.35), radius: 9, y: 6)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }
}

#Preview {
    NavigationStack { MatchesView(openTeams: {}) }.environment(AppStore(preview: .standard))
}
```

- [ ] **Step 4 : Remplacer `App/RootView.swift` (contenu complet : les deux onglets sont réels, l'écran d'attente disparaît)**

```swift
import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    MatchesView(openTeams: { tab = .teams })
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack {
                    TeamsView()
                }
            }
        }
        .tint(Palette.accent)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
```

- [ ] **Step 5 : Écrire les aperçus** — `Tests/FailleTests/MatchesSnapshotTests.swift`

```swift
import Foundation
import Testing
@testable import Faille

extension ApercuTests {
    @Test func matchesScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: .standard)), named: "01-matchs")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func matchesWelcome() async throws {
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: .empty)), named: "02-matchs-vide")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func matchesOffline() async throws {
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: .failing)), named: "08-bandeau-erreur")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
```

- [ ] **Step 6 : Commit, push, CI**

```bash
git add App/Matches App/RootView.swift Tests/FailleTests/MatchesSnapshotTests.swift
git commit -m "feat(app): onglet Matchs — une carte Vitrail par équipe suivie" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts.

- [ ] **Step 7 : Vérifier la présence des aperçus**

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls "$HOME/Downloads/faille-apercus-<id>"
```

Expected : `00-da.png`, `01-matchs.png`, `02-matchs-vide.png`, `03-equipes.png`, `07-reglages.png`, `08-bandeau-erreur.png`. À juger par le contrôleur, en regard de l'option B de `docs/maquettes/ecrans-appli.html` : « Mes équipes » / « 2 en direct · 1 à venir » ; carte KC bleue (« En direct · Game 2 · 18:4x », `KC 1 – 0 C9`, `7 – 4`, `+2,1k`, `2 – 1`, `3 – 1`, « Dernier · KC 1 – 3 G2 ») ; carte T1 carmin (« En direct vs FLY », « masqué », « toucher pour révéler », « Ensuite · … vs GEN ») ; carte GEN ambre (« GEN vs FUR », « Prochain · … », « Dernier · GEN 3 – 0 HLE ») ; écran vide avec le bouton « Choisir mes équipes » ; bandeau « lolesports ne répond pas · màj 15:05 ».

---

### Task 11 : Écran Détail d'un match

**Files :**
- Create : `App/Detail/MatchDetailModel.swift`
- Create : `App/Detail/StatsPanels.swift`
- Create : `App/Detail/MatchDetailView.swift`
- Modify : `App/RootView.swift` (contenu complet ci-dessous)
- Test : `Tests/FailleTests/DetailSnapshotTests.swift`

**Interfaces :**
- Consumes : `AppStore.details/snapshots/statsUnavailable`, `.event(id:)`, `.detailState(matchId:)`, `.isMasked(_:matchId:)`, `.loadDetails(matchId:)`, `.loadWindow(gameId:inProgress:)`, `.reveal(matchId:)`, `.tint(for:)`, `.follows.displayOrder(_:)` ; `EventDetails.statsDisabled`, `.currentGame`, `.bestOf` ; `GameSnapshot.stats(for:)`, `.players(for:)` ; `RefreshPolicy.detailInterval` ; `Format.gold/dragons/role/champion/kda/matchDate` ; T10 : `MatchRoute`, `reorder`, `LiveChipText`, `ScoreRow`, `RevealButton` ; T6 : `PillButton`, `NoteCard`, `Chip`, `IconView`, `glassCard`.
- Produces : `@MainActor @Observable final class MatchDetailModel { let matchId; var selectedGameNumber: Int?; var playersTeamIndex: Int; private(set) var attempted: Bool; func run(store:) async; func selectedGame(in:) -> GameRef?; func loadSelectedGame(store:) async }` ; `struct MatchDetailView(matchId:)` ; `struct TeamStatsPanel(left:right:tint:)`, `struct StatLabel(icon:text:)`, `struct GoldBar(left:right:tint:)`, `struct PlayersPanel(teams:snapshot:selection:)` ; navigation `MatchRoute` → `MatchDetailView` ; aperçus `04-detail.png`, `05-detail-sans-stats.png`, `06-detail-masque.png`.

- [ ] **Step 1 : Écrire `App/Detail/MatchDetailModel.swift`**

```swift
import Foundation
import LoLKit
import Observation

/// Boucle de l'écran Détail (spec §4.1) : `getEventDetails` à l'ouverture puis toutes les 60 s si le match est en cours
/// (changement de game) ; flux de la game choisie toutes les 10 s ; seulement tant que l'écran est affiché.
@MainActor
@Observable
final class MatchDetailModel {
    let matchId: String
    /// Game choisie dans les pilules ; nil = la game en cours, sinon la dernière jouée.
    var selectedGameNumber: Int?
    /// Équipe affichée dans « Joueurs » (index dans l'ordre d'affichage).
    var playersTeamIndex = 0
    /// Un premier appel à `getEventDetails` a été tenté.
    private(set) var attempted = false

    init(matchId: String) {
        self.matchId = matchId
    }

    /// Lancée par `.task` : annulée, requêtes comprises, quand l'écran disparaît.
    func run(store: AppStore) async {
        var cycle = 0
        while !Task.isCancelled {
            let details = store.details[matchId]
            let inProgress = details?.currentGame != nil || store.event(id: matchId)?.state == .inProgress
            if details == nil || (inProgress && cycle % 6 == 0) {
                await store.loadDetails(matchId: matchId)
                attempted = true
            }
            await loadSelectedGame(store: store)
            cycle += 1
            try? await Task.sleep(for: .seconds(RefreshPolicy.detailInterval))
        }
    }

    /// Game affichée : celle choisie, sinon celle en cours, sinon la dernière jouée, sinon la première.
    func selectedGame(in details: EventDetails) -> GameRef? {
        let games = details.match.games.filter { $0.state != .unneeded }
        if let number = selectedGameNumber, let game = games.first(where: { $0.number == number }) {
            return game
        }
        return games.first(where: { $0.state == .inProgress })
            ?? games.last(where: { $0.state == .completed })
            ?? games.first
    }

    /// Dernière frame de la game affichée : à chaque cycle si elle est en cours, jusqu'à la frame finale si elle est jouée.
    /// Rien pour un match masqué ou sans stats.
    func loadSelectedGame(store: AppStore) async {
        guard let details = store.details[matchId], let game = selectedGame(in: details),
              !store.isMasked(details.match.teams, matchId: matchId),
              !details.statsDisabled, store.event(id: matchId)?.statsDisabled != true else { return }
        switch game.state {
        case .inProgress:
            await store.loadWindow(gameId: game.id, inProgress: true)
        case .completed where store.snapshots[game.id]?.phase != .finished:
            await store.loadWindow(gameId: game.id, inProgress: false)
        default:
            break
        }
    }
}
```

- [ ] **Step 2 : Écrire `App/Detail/StatsPanels.swift`**

```swift
import LoLKit
import SwiftUI

/// Stats d'équipe de la game choisie (spec §5.3) : kills, gold et barre d'écart, tours, inhibiteurs, drakes (types), barons.
struct TeamStatsPanel: View {
    let left: TeamStats
    let right: TeamStats
    /// Couleur de l'équipe de gauche (barre de gold).
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            row(.swords, "Kills", "\(left.kills)", "\(right.kills)")
            row(.gold, "Gold", Format.gold(left.gold), Format.gold(right.gold))
            GoldBar(left: left.gold, right: right.gold, tint: tint)
            row(.tower, "Tours", "\(left.towers)", "\(right.towers)")
            row(.inhib, "Inhibs", "\(left.inhibitors)", "\(right.inhibitors)")
            dragonRow
            row(.baron, "Barons", "\(left.barons)", "\(right.barons)")
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func row(_ icon: Icon, _ label: String, _ a: String, _ b: String) -> some View {
        HStack {
            Text(a)
                .font(Typo.stat)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: icon, text: label)
            Text(b)
                .font(Typo.stat)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
    }

    private var dragonRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(left.dragons.count)").font(Typo.stat)
                if !left.dragons.isEmpty {
                    Text(Format.dragons(left.dragons))
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: .drake, text: "Drakes")
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(right.dragons.count)").font(Typo.stat)
                if !right.dragons.isEmpty {
                    Text(Format.dragons(right.dragons))
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
    }
}

/// Libellé central d'une ligne de stats : icône + étiquette en capitales.
struct StatLabel: View {
    let icon: Icon
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            IconView(icon: icon, size: 13)
            Text(text)
                .font(Typo.label)
                .tracking(Typo.labelTracking)
                .textCase(.uppercase)
        }
        .foregroundStyle(Palette.secondary)
        .frame(minWidth: 96)
    }
}

/// Barre d'écart de gold : la part de l'équipe de gauche, à sa couleur.
struct GoldBar: View {
    let left: Int
    let right: Int
    let tint: Color

    var body: some View {
        let share = CGFloat(left) / CGFloat(max(1, left + right))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * share)
                    .shadow(color: tint, radius: 4)
            }
        }
        .frame(height: 5)
    }
}

/// Joueurs de la game (spec §5.3) : sélecteur d'équipe, puis rôle, champion, KDA, CS.
struct PlayersPanel: View {
    let teams: [MatchTeam]
    let snapshot: GameSnapshot
    @Binding var selection: Int

    var body: some View {
        let index = teams.indices.contains(selection) ? selection : 0
        let players = teams.indices.contains(index) ? (teams[index].id.flatMap { snapshot.players(for: $0) } ?? []) : []
        VStack(alignment: .leading, spacing: 8) {
            Picker("Équipe", selection: $selection) {
                ForEach(teams.indices, id: \.self) { position in
                    Text(teams[position].code).tag(position)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("").frame(width: 38, alignment: .leading)
                Text("Champion").frame(maxWidth: .infinity, alignment: .leading)
                Text("KDA").frame(width: 64, alignment: .leading)
                Text("CS").frame(width: 40, alignment: .trailing)
            }
            .font(Typo.label)
            .tracking(Typo.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.secondary)
            ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                HStack {
                    Text(Format.role(player.role))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 38, alignment: .leading)
                    Text(Format.champion(player.champion))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.kda(player)).frame(width: 64, alignment: .leading)
                    Text("\(player.creepScore)").frame(width: 40, alignment: .trailing)
                }
                .font(Typo.secondaryMedium)
                .monospacedDigit()
            }
            if players.isEmpty {
                Text("Joueurs indisponibles")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
```

- [ ] **Step 3 : Écrire `App/Detail/MatchDetailView.swift`**

```swift
import LoLKit
import SwiftUI

/// Détail d'un match (spec §5.3) : en-tête teinté (ligue, bloc, Bo, chrono, équipes, score), pilules de games,
/// stats d'équipe et joueurs de la game choisie. Le bouton « Épingler sur l'écran verrouillé » arrive à l'étape 4.
struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var model: MatchDetailModel

    init(matchId: String) {
        _model = State(initialValue: MatchDetailModel(matchId: matchId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.run(store: store) }
        .task(id: model.selectedGameNumber) { await model.loadSelectedGame(store: store) }
    }

    @ViewBuilder private var content: some View {
        let event = store.event(id: model.matchId)
        let details = store.details[model.matchId]
        let teams = details?.match.teams ?? event?.match.teams ?? []
        let order = store.follows.displayOrder(teams)
        let ordered = order.map { teams[$0] }
        let masked = store.isMasked(teams, matchId: model.matchId)
        let state = store.detailState(matchId: model.matchId)
        let tint = ordered.compactMap { store.tint(for: $0) }.first
        header(event: event, details: details, teams: ordered, order: order, state: state, masked: masked, tint: tint)
        if masked {
            RevealButton { store.reveal(matchId: model.matchId) }
        } else if let details {
            gamePills(details)
            if details.statsDisabled || event?.statsDisabled == true {
                NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
            } else if let game = model.selectedGame(in: details) {
                gameStats(game: game, teams: ordered)
            }
        } else if model.attempted {
            NoteCard(icon: .refresh, text: "Détails du match indisponibles pour l'instant")
        } else {
            ProgressView()
                .tint(Palette.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func header(event: MatchEvent?, details: EventDetails?, teams: [MatchTeam], order: [Int],
                        state: LiveMatchState?, masked: Bool, tint: Color?) -> some View {
        let league = details?.league.name ?? event?.league.name ?? ""
        let bestOf = details?.bestOf ?? event?.bestOf ?? 1
        let meta = [league, event?.blockName ?? "", "Bo\(bestOf)"].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(meta)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                statusChip(event: event, state: state)
            }
            ScoreRow(teams: teams, score: seriesScore(event: event, state: state, order: order, masked: masked),
                     tints: teams.map { store.tint(for: $0) }, large: true)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }

    /// Score de série dans l'ordre d'affichage ; nil si masqué ou pas commencé.
    private func seriesScore(event: MatchEvent?, state: LiveMatchState?, order: [Int], masked: Bool) -> [Int]? {
        guard !masked else { return nil }
        if let state {
            return state.phase == .upcoming ? nil : state.seriesScore.flatMap { reorder($0, order) }
        }
        guard let event, event.state != .unstarted else { return nil }
        return reorder(event.match.teams.map(\.gameWins), order)
    }

    @ViewBuilder private func statusChip(event: MatchEvent?, state: LiveMatchState?) -> some View {
        switch state?.phase ?? phase(of: event) {
        case .inGame, .betweenGames:
            Chip {
                IconView(icon: .live, size: 12)
                if let state {
                    LiveChipText(state: state, opponent: nil)
                } else {
                    Text("En direct")
                }
            }
        case .finished:
            Chip(muted: true) {
                IconView(icon: .check, size: 12)
                Text("Terminé")
            }
        case .upcoming:
            Chip(muted: true) {
                IconView(icon: .clock, size: 12)
                Text(event.map { Format.matchDate($0.startTime) } ?? "À venir")
            }
        }
    }

    private func phase(of event: MatchEvent?) -> LiveMatchState.Phase {
        switch event?.state {
        case .inProgress: return .inGame
        case .completed: return .finished
        default: return .upcoming
        }
    }

    /// « G1 ✓ », « G2 · en direct », « G3 »… une pilule par game jouée ou à venir.
    private func gamePills(_ details: EventDetails) -> some View {
        let games = details.match.games.filter { $0.state != .unneeded }
        let selected = model.selectedGame(in: details)?.number
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(games, id: \.number) { game in
                    PillButton(selected: game.number == selected, action: { model.selectedGameNumber = game.number }) {
                        Text(game.state == .inProgress ? "G\(game.number) · en direct" : "G\(game.number)")
                        if game.state == .completed {
                            IconView(icon: .check, size: 12)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func gameStats(game: GameRef, teams: [MatchTeam]) -> some View {
        let ids = teams.compactMap(\.id)
        if game.state == .unstarted {
            NoteCard(icon: .clock, text: "La game \(game.number) n'a pas commencé")
        } else if store.statsUnavailable.contains(game.id) {
            NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
        } else if let snapshot = store.snapshots[game.id], ids.count == 2,
                  let left = snapshot.stats(for: ids[0]), let right = snapshot.stats(for: ids[1]) {
            TeamStatsPanel(left: left, right: right, tint: store.tint(for: teams[0]) ?? Palette.accent)
            PlayersPanel(teams: teams, snapshot: snapshot, selection: $model.playersTeamIndex)
        } else {
            NoteCard(icon: .refresh, text: game.state == .inProgress ? "Stats en chargement…" : "Stats de cette game indisponibles")
        }
    }
}

#Preview {
    NavigationStack { MatchDetailView(matchId: SampleData.kcMatchId) }.environment(AppStore(preview: .standard))
}
```

- [ ] **Step 4 : Remplacer `App/RootView.swift` (contenu complet : navigation vers le Détail)**

```swift
import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    MatchesView(openTeams: { tab = .teams })
                        .navigationDestination(for: MatchRoute.self) { route in
                            MatchDetailView(matchId: route.matchId)
                        }
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack {
                    TeamsView()
                }
            }
        }
        .tint(Palette.accent)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
```

- [ ] **Step 5 : Écrire les aperçus** — `Tests/FailleTests/DetailSnapshotTests.swift`

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func detail(_ matchId: String) -> some View {
        NavigationStack { MatchDetailView(matchId: matchId) }.environment(AppStore(preview: .standard))
    }

    @Test func detailWithStats() async throws {
        let url = try await Snapshot.write(detail(SampleData.kcMatchId), named: "04-detail")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func detailWithoutStats() async throws {
        let url = try await Snapshot.write(detail(SampleData.noStatsMatchId), named: "05-detail-sans-stats")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func detailMasked() async throws {
        let url = try await Snapshot.write(detail(SampleData.t1MatchId), named: "06-detail-masque")
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
```

- [ ] **Step 6 : Commit, push, CI**

```bash
git add App/Detail App/RootView.swift Tests/FailleTests/DetailSnapshotTests.swift
git commit -m "feat(app): écran Détail — games, stats d'équipe, joueurs, anti-spoiler" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts.

- [ ] **Step 7 : Vérifier la présence des aperçus**

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls "$HOME/Downloads/faille-apercus-<id>"
```

Expected : les 9 PNG `00-da.png`, `01-matchs.png`, `02-matchs-vide.png`, `03-equipes.png`, `04-detail.png`, `05-detail-sans-stats.png`, `06-detail-masque.png`, `07-reglages.png`, `08-bandeau-erreur.png`. À juger par le contrôleur : `04` = en-tête bleu « Mondial · Play-in · Bo5 » + chrono, `KC 1 – 0 C9`, pilules « G1 ✓ », « G2 · en direct » (choisie), G3–G5, stats 7/4, 32,4k/30,3k + barre, 3/1, 0/0, drakes « 2 infernal, océan » / « 1 nuage », 0/0, joueurs KC (TOP Rumble 2/0/1 162 … SUP Rell 0/1/5 21) ; `05` = BRO 1 – 0 LGD + « Stats live non fournies par Riot pour ce match » ; `06` = T1 vs FLY sans score, « En direct », « toucher pour révéler ».

---

### Task 12 : Essai sur l'iPhone de Dan (manuel)

Cette tâche est faite par **Dan** ; l'agent prépare la commande de téléchargement, attend ses réponses, puis consigne le verdict.

**Files :**
- Create : `docs/superpowers/notes/2026-10-etape-2-verdict.md`

**Interfaces :**
- Consumes : l'artefact `Faille-ipa` du dernier run vert du workflow `iOS` sur `main`.
- Produces : verdict de l'étape 2 (critère de fin spec §13 : « Suivre une équipe et voir ses matchs sur l'iPhone »).

- [ ] **Step 1 : Télécharger l'IPA (agent)**

```bash
gh run list --workflow iOS --branch main --status success --limit 1 --json databaseId --jq '.[0].databaseId'
gh run download <id> --name Faille-ipa --dir "$HOME/Downloads/faille-<id>" && ls -l "$HOME/Downloads/faille-<id>"
```

Expected : `Faille.ipa` (quelques Mo).

- [ ] **Step 2 : Installer avec AltServer (Dan)**

iPhone branché en USB et déverrouillé, AltServer lancé : **Maj + clic** sur l'icône AltServer de la barre des tâches → `Sideload .ipa…` → choisir l'iPhone → `Faille.ipa` → Apple ID. Même identifiant que la sonde (`com.cafe1231.faille.<TEAMID>`) : l'appli de l'étape 0 est remplacée, aucun nouvel identifiant d'app n'est consommé.

- [ ] **Step 3 : Checklist (Dan, cocher OK / KO + remarque)**

1. Ouverture : fond abysse sombre, police Sora (titres épais, chiffres ronds), barre d'onglets flottante en verre « Matchs » / « Équipes », aucune emoji.
2. Premier lancement : onglet Matchs = « Bienvenue dans Faille » ; le bouton mène à l'onglet Équipes.
3. Équipes : les pilules de ligues apparaissent (Mondial en tête) ; « Mondial » liste les équipes des Worlds ; « La Ligue Française » liste les équipes LFL.
4. Recherche « kc » : Karmine Corp en premier ; toucher l'étoile → l'équipe passe dans « Mes équipes » ; en quelques secondes son logo s'affiche et sa couleur (badge, point) n'est plus le bleu clair par défaut.
5. Suivre 2-3 équipes (dont une qui joue aux Worlds) ; l'onglet Matchs affiche une carte teintée par équipe, avec Prochain (date et heure locales) et Dernier.
6. Appui long sur une équipe suivie → « Changer la couleur » → choisir un vert → Valider : la carte devient verte ; « Couleur automatique » rétablit la couleur du logo.
7. Œil sur une équipe → « sans spoiler » ; sa carte n'affiche plus aucun score (Dernier : « masqué ») ; ouvrir le match → « toucher pour révéler » → le score apparaît ; fermer et relancer l'appli → le match reste révélé.
8. Pendant un match en direct des Worlds : carte « En direct · Game N · chrono » (le chrono avance seul), score de série, ligne kills / gold / drakes / tours qui change d'une minute à l'autre.
9. Détail de ce match : pilules de games, stats qui bougent toutes les ~10 s, barre de gold, drakes avec leurs types, joueurs des deux équipes via le sélecteur ; toucher une game terminée affiche ses stats finales (ou « Stats de cette game indisponibles » — noter lequel).
10. Un match aux stats désactivées (ex. DCGI) : « Stats live non fournies par Riot pour ce match ».
11. Mode avion puis tirer pour rafraîchir : bandeau « lolesports ne répond pas · màj HH:MM », les cartes restent affichées ; sortir du mode avion : le bandeau disparaît en moins d'une minute.
12. Tuer l'appli, la relancer en mode avion : équipes, cartes et calendrier s'affichent tout de suite (cache).
13. Engrenage → Réglages : Automatique / Manuelle, choix conservé après relance ; À propos : « 0.1.0 (1) · LoLKit 0.1.0 » et `Groupe d'apps : group.com.cafe1231.faille.<TEAMID>`.
14. Widget « Sonde Faille » ajouté à l'écran d'accueil : « groupe OK » et les codes des équipes suivies (ex. « KC · T1 · GEN »).
15. (Facultatif) iPad : mêmes écrans, contenu centré, lisible en paysage.

- [ ] **Step 4 : Consigner le verdict (agent)** — `docs/superpowers/notes/2026-10-etape-2-verdict.md`

Contenu à écrire avec les réponses de Dan (une ligne par point de la checklist, colonne Résultat = « OK » ou « KO — <remarque de Dan> ») :

```markdown
# Étape 2 — verdict (date de l'essai)

iPhone de Dan sous iOS 27, installation AltServer, IPA du run <id>.

| # | Vérification | Résultat |
|---|---|---|
| 1 | DA : abysse, Sora, barre d'onglets en verre, pas d'emoji | |
| 2 | Accueil sans équipe → onglet Équipes | |
| 3 | Pilules de ligues (Mondial, LFL) | |
| 4 | Recherche, suivre, logo et couleur automatique | |
| 5 | Une carte par équipe, Prochain / Dernier | |
| 6 | Changer la couleur / couleur automatique | |
| 7 | Anti-spoiler, révéler, révélation mémorisée | |
| 8 | Carte en direct : chrono, score, stats | |
| 9 | Détail : games, stats 10 s, gold, drakes, joueurs ; game terminée | |
| 10 | Stats désactivées : message | |
| 11 | Hors ligne : bandeau, données gardées, retour à la normale | |
| 12 | Relance hors ligne : cache immédiat | |
| 13 | Réglages, À propos (version, groupe) | |
| 14 | Widget sonde : groupe OK + équipes suivies | |
| 15 | iPad (facultatif) | |

**Décision :** étape 2 terminée / corrections à faire (lister).
```

```bash
git add docs/superpowers/notes/2026-10-etape-2-verdict.md
git commit -m "docs: verdict de l'étape 2 sur iPhone" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

Tout point KO devient une tâche de correction (même format que ci-dessus) avant de passer à l'étape 3.

---

## Auto-relecture (faite à l'écriture du plan)

**Couverture de la spec :**

| Spec | Où |
|---|---|
| §4.4 groupe lu à l'exécution (profil → `ALTAppGroups` → nom configuré, premier `containerURL` non nil), même règle appli / extension | T2 `AppGroupResolver`, T5 `AppGroup` (utilisé par l'appli et la sonde widget) |
| §4.4 fichiers JSON, liste suivie tolérante, cache réseau daté, logos en cache | T1 `Cached`, T2 `AppSettings`, T5 `FileStore` (fichier illisible mis de côté), T7 `AppStore` |
| §4.1 cadences, `getSchedule` à l'ouverture, `window` 10 s sur le Détail | T1 `RefreshPolicy`, T7 `poll`/`refreshDue`, T11 `MatchDetailModel` |
| §5.1 titre, sous-titre, cartes Vitrail, ordre, direct / prochain / dernier, tirer, toucher → Détail, accueil | T4 `Format.cardsSubtitle`, T10 |
| §5.2 recherche, mes équipes (œil, étoile, appui long couleur / automatique), pilules par priorité, engrenage | T4 `TeamDirectory`, T9, T8 |
| §5.3 en-tête teinté, pilules de games, stats (gold + barre, drakes + types), joueurs + sélecteur, stats désactivées | T11 (bouton Épingler : étape 4) |
| §5.4 Live Activity auto / manuelle, À propos | T8 |
| §8 masquage via `SpoilerPolicy` / `Presenter` / `LiveMatchBuilder`, entre deux games = « En direct », révéler mémorisé | T7 `isMasked`/`liveState`/`reveal`, T10, T11 |
| §9 abysse, verre, Sora, échelle typo, icônes au trait, Vitrail, couleur du logo (alpha dé-prémultiplié), surcharge | T2, T6, T7 `updateTeamColors`, T9 |
| §10 bandeau `màj HH:MM`, 403 logué, stats désactivées, décodage tolérant, groupe absent, match sorti du direct | T4 `Format.offlineBanner`, T7 `fetch`, T1 `matchLeftLive` |
| §11.3 PNG en CI | T6 `Snapshot` + job `apercus`, T8–T11 |

**Signatures vérifiées contre les sources de LoLKit** : `TeamCards.build(follows:schedule:live:)`, `LiveMatchBuilder.state(details:snapshot:firstFrameTime:statsDisabled:follows:revealed:now:)`, `Presenter.scoreLine(for:follows:revealed:)`, `SpoilerPolicy.isMasked(_:matchId:follows:revealed:)`, `ScheduleQuery.leagueIds(follows:leagues:)`, `FollowedTeam.init(id:code:name:image:homeLeagueName:spoilerFree:autoColorHex:colorOverrideHex:)`, `LoLClient.window(gameId:startingTime:)`, `LiveStatsTime.startingTime(now:)`, `LiveWindow.latestSnapshot()` / `.firstFrameTime`, `GameSnapshot.stats(for:)` / `.players(for:)`, `TeamColor.teamColor(rgba:)`, `RGB.accent`, `LoLDate.parse(_:)`.

**API iOS les moins sûres (repli écrit dans le plan) :** `glassEffect(_:in:)` / `Glass.regular.tint(_:)` (repli `.ultraThinMaterial`), `Tab(_:image:value:content:)` (repli `.tabItem` + `.tag`), graisse de Sora par `kCTFontVariationAttribute` (contrôlée par `soraIsBundled` et la planche `00-da`), liaison des tests hébergés aux symboles de LoLKit (`DEAD_CODE_STRIPPING = NO` en Debug, repli : lier LoLKit à la cible de tests), rendu du Liquid Glass par `drawHierarchy`.
