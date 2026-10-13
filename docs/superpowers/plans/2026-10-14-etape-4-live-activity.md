# Étape 4 — La Live Activity : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** remplacer la Live Activity sonde de l'étape 0 par la Live Activity des matchs — écran verrouillé et Dynamic Island (compacte, minimale, déployée), dans tous ses états (en jeu, entre deux games, fin, stats indisponibles, pas fraîche, anti-spoiler) —, démarrée automatiquement ou à la main depuis le Détail, mise à jour au premier plan, au passage en arrière-plan et par `BGAppRefreshTask`, sans aucun push (compte Apple gratuit). Terminé quand la checklist §11.4 passe pendant un match des Worlds (spec §13, étape 4).

**Architecture :** LoLKit décide tout ce qui est pur, testé sur Windows : ce qu'affiche chaque état (`LiveActivityDisplay`), l'état remis dans l'ordre des équipes de la Live Activity (`LiveActivityContent`, `LiveMatchState.aligned`), quoi démarrer, mettre à jour ou terminer (`LiveActivityPlanner.plan(… active:)`, `LiveActivityPlanner.decision`), les choix de l'utilisateur (`LiveActivityChoices` : épinglés, retirés à la main) et la date du prochain réveil en arrière-plan. `Shared/LiveActivity/` porte la conformité `ActivityAttributes` du contrat et des vues SwiftUI simples, rendues en PNG dans les tests hébergés et posées telles quelles par l'extension. Dans l'appli, un seul contrôleur `@MainActor` (`LiveActivityController`) applique les décisions, et seul `ActivityGateway` touche ActivityKit, en n'échangeant que des valeurs Sendable ; le store (`AppStore`) fournit le contenu de chaque match et pilote le contrôleur à chaque tour du premier plan, après chaque action, au passage en arrière-plan et à chaque réveil `BGAppRefreshTask`.

**Tech Stack :** Swift 6.2 (appli, tests et extension en Swift 6), SwiftUI iOS 26, ActivityKit (`Activity`, `ActivityContent`, `ActivityConfiguration`, `DynamicIsland`, `ActivityViewContext.isStale`), BackgroundTasks (`BGTaskScheduler`, `BGAppRefreshTaskRequest`) et `Scene.backgroundTask(.appRefresh(_:))`, `ImageRenderer`, Swift Testing, XcodeGen, GitHub Actions `macos-26` (Xcode 26), Docker `swift:6.2`, AltServer.

**Spec :** `docs/superpowers/specs/2026-10-13-faille-design.md` — §4.3 (contrat `LiveMatchState`, fixture `live_contract.json`, wrapper `ActivityAttributes`), §5.3 (bouton « Épingler »), §5.4, §6 (contenu, Dynamic Island, états, démarrage et fin), §8 (anti-spoiler), §9 (DA), §10, §11.3-§11.4, §13. Maquettes : `docs/maquettes/ecran-verrouille.html` (① et ②). Journaux : `docs/superpowers/notes/2026-10-13-etape-2-journal.md`, `docs/superpowers/notes/2026-10-13-lolkit-journal.md`, `docs/superpowers/notes/2026-10-etape-0-verdict.md`. **Ce plan s'exécute après l'étape 3** (`docs/superpowers/plans/2026-10-14-etape-3-widgets.md`) et en consomme les produits : `reorder(_:_:)` public dans LoLKit, `MonogramBadge`, `WidgetRender`, `BoardWallpaper`, `BoardCaption`, `WidgetSize`, Sora et le catalogue d'icônes dans l'extension, extension en Swift 6, `WidgetBundle` réécrit.

## Global Constraints

- iOS minimum **26.0** ; iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) ; Apple n'affiche les Live Activities que sur iPhone (le bouton « Épingler » n'existe que sur iPhone).
- **Aucun push** : `pushType: nil`, pas d'APNs, pas de push-to-start. Une Live Activity ne se **démarre** qu'au premier plan ; elle se **met à jour** au premier plan (à chaque tour de 10 s, seulement si son contenu a changé), au passage en arrière-plan, et à chaque `BGAppRefreshTask` (demandé toutes les 15 min tant qu'un match suivi est en direct ou qu'une Live Activity est à l'écran ; iOS décide seul s'il l'accorde).
- `staleDate = updatedAt + 180 s` (`LiveMatchState.staleAfter`) ; `updatedAt` = **dernière relecture réussie** de la donnée qui nourrit l'état (direct, ou calendrier pour un match sorti du direct), jamais l'heure de réception de la frame (qui reste l'ancre du chrono).
- Au plus **3** Live Activities à l'écran (`LiveActivityPlanner.maxConcurrent`), terminées encore affichées comprises ; celles qui existent gardent leur place ; nouvelles : épinglées en direct, puis (mode automatique) équipes suivies dans l'ordre de suivi, sauf matchs retirés à la main.
- Match terminé : contenu final, puis retrait de l'écran **1 h** après (`LiveActivityPlanner.finishedDisplay` = 3 600 s, `ActivityUIDismissalPolicy.after`).
- **Contrat inchangé** : `LoLKit/Tests/LoLKitTests/Fixtures/live_contract.json` n'est pas modifié, aucun champ n'est ajouté à `LiveMatchAttributes` / `LiveMatchState` ; `LiveContractTests` reste vert. Wrapper iOS : `extension LiveMatchAttributes: @retroactive ActivityAttributes { public typealias ContentState = LiveMatchState }` dans `Shared/`.
- **Aucun code ne suppose un bundle ID ni un nom de groupe** (AltServer renomme les deux). Identifiant de la tâche d'arrière-plan : `faille.live-refresh` (déclaré dans `BGTaskSchedulerPermittedIdentifiers`, indépendant du bundle ID).
- ActivityKit n'est appelé **que** depuis `App/LiveActivity/ActivityGateway.swift`, qui ne reçoit et ne rend que des valeurs Sendable (`String`, `Date`, `LiveMatchAttributes`, `LiveMatchState`, `RunningActivity`) ; `LiveActivityController` est `@MainActor` et seul à appeler la passerelle.
- LoLKit n'importe que `Foundation` ; toute décision pure nouvelle y va, en TDD (`bash scripts/lolkit.sh test`, Docker Desktop lancé).
- Anti-spoiler (spec §8) : l'état d'une Live Activity vient **toujours** de `LiveMatchBuilder.state` (donc de `SpoilerPolicy`, `masked()`) ; masquée, elle n'affiche que « En direct » / « Terminé », sans score, numéro de game, chrono, stats ni vainqueur, sur l'écran verrouillé comme dans la Dynamic Island. Elle n'annonce **aucun prochain match** ; toute ligne « prochain match » future passerait par `Presenter.nextLine` (règle F1, et décision du contrôleur : un prochain match lui-même masqué et non révélé est aussi « Prochain · masqué »).
- DA (spec §9) : abysse `#0B1020`, texte `#E9EEFB`, secondaire `#94A0BF`, accent `#6FD3FF` ; dégradé à 160° de la couleur de l'équipe suivie (`primaryTeamIndex`) vers l'abysse ; monogrammes (pas de logo) ; Sora ; icônes au trait, **jamais d'emoji** ; pas de matière ni de `glassEffect` dans la Live Activity.
- Hauteur de la vue de l'écran verrouillé ≤ **160 pt** (au-delà, iOS la tronque), vérifiée par un test hébergé à 360 pt de large.
- Aperçus : `build/apercus/11-live-activity.png` et `build/apercus/12-dynamic-island.png` dans l'artefact `Faille-apercus`, chacun > 100 000 octets (`ApercuTests.expectNotBlank`).
- Le code iOS ne se compile **qu'en CI** : une tâche iOS se vérifie par commit, `git push origin main`, `gh run watch --exit-status <id>` sur le workflow `iOS` ; échec : `gh run view <id> --log-failed`.
- Textes de l'interface en français ; identifiants en anglais ; commentaires en français ; fins de ligne LF.
- Commits avec l'adresse noreply déjà configurée ; chaque message se termine par un second `-m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Pousser sur `main` est autorisé.

## Décisions prises par ce plan (au-delà de la spec)

- **`updatedAt` honnête** : `LiveMatchBuilder.state` reçoit un paramètre `updatedAt: Date? = nil` distinct de `now` (ancre du chrono) ; le store y passe `lastSuccess[.live]` (ou `lastSuccess[.schedule]` pour un match fini lu au calendrier). Conséquence : `staleDate = updatedAt + 180 s` peut déjà être passée au moment d'une mise à jour faite avec des données vieilles — c'est voulu (la spec §6.4 dit « maintenant + 3 min » ; on garde l'intention : « pas fraîche » dès que la donnée a plus de 3 min). Le format JSON ne change pas.
- **Démarrage à chaque tour du premier plan**, pas seulement au passage au premier plan : un match qui commence pendant que l'appli est ouverte a aussi sa Live Activity.
- **Pas d'éviction** : les Live Activities déjà à l'écran (y compris terminées et encore affichées) gardent leur place ; « Épingler » quand 3 sont déjà affichées est refusé avec un message (« Déjà 3 Live Activities… »), sans en retirer une d'office.
- **Mode manuel** : au passage en manuel, les Live Activities non épinglées sont terminées au tour suivant ; elles ne sont pas marquées « retirées à la main » (repasser en automatique les recrée).
- **Retrait à la main détecté par réconciliation** : l'appli note les matchs dont elle a démarré la Live Activity (`LiveActivityChoices.started`) ; à chaque mise à jour, une Live Activity notée qui n'est plus en cours sans que l'appli l'ait terminée est « retirée à la main » (glissement, ou fin imposée par iOS au bout de 8 h) et n'est jamais recréée automatiquement. Pas d'observateur `activityStateUpdates` (moins de concurrence, et l'utilisateur ne peut pas glisser une Live Activity pendant que l'appli est au premier plan).
- **Bouton du Détail** : visible sur iPhone pour un match en direct, ou dont la Live Activity est encore à l'écran ; « Retirer » termine tout de suite et marque le match retiré ; « Épingler » annule un retrait précédent. On n'épingle pas un match à venir.
- **Fin** : la Live Activity d'un match terminé reste affichée 1 h **à partir du moment où l'appli l'apprend** (au premier plan ou à un réveil d'arrière-plan) ; un match sorti du direct n'est déclaré fini que quand le calendrier (relu aussitôt, spec §10) le dit `completed` — avant, rien ne change et la Live Activity passe « pas fraîche ». Un match `completed` sans série gagnée (forfait, Bo2) est « Terminé » grâce à `LiveMatchState.displayed(for:)` (déjà dans l'appli).
- **Avant la game 1** (match dans `getLive` mais aucune game commencée) : « En direct » + « La game 1 commence dans quelques minutes ».
- **« màj il y a X min »** : `Text(updatedAt, style: .relative)` (minuteur natif, il avance sans mise à jour) ; les aperçus sont rendus en `fr_FR`. Si iOS y ajoute des secondes sur l'iPhone, repli noté dans la checklist (T8).
- **Icône `pause`** (« entre deux games », maquette ②) ajoutée au catalogue par `scripts/icones.sh` (22 icônes).
- **Pas de `relevanceScore`** (0 par défaut) : iOS choisit seul quelle Live Activity occupe la Dynamic Island.
- **Couleurs d'équipe hors du cycle gardé** : `poll()` lance deux boucles enfants (données, couleurs) ; la passe des logos ne tourne qu'au premier plan, jamais pendant un réveil d'arrière-plan (budget de temps d'iOS).
- **Tâches liées à la scène** : les actions (suivre, œil, révéler, réglage, épingler) lancent leur travail par `runWithScene`, annulé quand la boucle du premier plan s'arrête (`endScene()`).
- **Stats des Live Activities** : `refreshLiveStats` interroge aussi les matchs qui ont une Live Activity sans équipe suivie (match épinglé à la main) ; cadence inchangée (celle du direct, 60 s), suffisante tant que l'appli est ouverte (la Live Activity n'est visible qu'en la quittant).
- Le drapeau de `syncFollowsBeforeChange` : **déjà corrigé** à l'étape 2 (F7, commit `f523ebc`, tests `userChangeWhileStillUnreadableDoesNotOverwriteTheFile` et suivants) — rien à faire.

## Points différés traités ici

| Point (source) | Tâche |
|---|---|
| `updatedAt` = dernière relecture réussie, distinct de l'heure de réception de la frame (étape 2, final-fix-brief) | T1 (`LiveMatchBuilder.state(… updatedAt:)`), T3 (store) |
| Passe des logos hors du cycle gardé (étape 2, Task 7 mineur ; budget de l'arrière-plan) | T3 |
| Tâches non structurées `toggleFollow` / `setSpoilerFree` / `reveal` liées à la scène (étape 2, Task 7) | T3 (`runWithScene`, `endScene`) |
| `syncFollowsBeforeChange` (étape 2, Task 7 #3) | déjà corrigé (F7) — vérifié, aucune tâche |
| Planner sans `active:` (journal LoLKit, Ruling 17) | T2 |
| Épinglés et retirés disjoints (journal LoLKit, Task 10) | T2 (`LiveActivityChoices`) |
| `gameClockStoppedAt` sans `gameClockStart` = pas de chrono (journal LoLKit, re-review) | T1 (`LiveActivityDisplay.runningClock`) |
| Chrono figé sur une game décisive finie dans le flux (journal LoLKit, Task 9) | T1 (`gameClockStoppedAt` → chrono figé) |
| Ordre des équipes attributs (au démarrage) / état (mises à jour) réconcilié par id (journal LoLKit, Task 9) | T1 (`aligned(from:to:)`), T2 (`decision`) |
| Attributs construits depuis des détails avec ids (journal LoLKit, Task 9) | T3 (`getLive` → `EventDetails(event:)`), T6 (pas de démarrage sans attributs) |
| `.finished` sans série gagnée (forfait, Bo2) | T3 (`displayed(for:)`) |

## Structure des fichiers

```
LoLKit/Sources/LoLKit/Live/
├─ LiveMatchBuilder.swift            (T1, modifié) state(…, now:, updatedAt:)
├─ LiveMatchState.swift              (T1, modifié) doc de updatedAt (contrat JSON inchangé)
├─ LiveActivityContent.swift         (T1) LiveActivityContent ; LiveMatchState.aligned(from:to:)
├─ LiveActivityDisplay.swift         (T1) en-tête, statut, chrono, 5 lignes, message de chaque état
├─ LiveActivityPlanner.swift         (T2, réécrit) plan(… active:), decision(…), nextBackgroundRefresh(…), LiveActivityUpdate
└─ LiveActivityChoices.swift         (T2) épinglés / retirés / démarrés
LoLKit/Tests/LoLKitTests/
├─ LiveMatchBuilderTests.swift       (T1, +1 test)
├─ LiveActivityContentTests.swift    (T1)
├─ LiveActivityDisplayTests.swift    (T1)
├─ LiveActivityPlannerTests.swift    (T2, +6 tests)
├─ LiveActivityDecisionTests.swift   (T2)
└─ LiveActivityChoicesTests.swift    (T2)

Shared/                                       compilé dans l'appli ET l'extension
├─ DA/Icon.swift                              (T4, modifié) + Icon.pause
├─ FileStore.swift                            (T6, modifié) + File.liveActivities
├─ LiveActivity/LiveMatchAttributes+Activity.swift  (T4) conformité ActivityAttributes
├─ LiveActivity/LiveActivityViews.swift       (T4) écran verrouillé
├─ LiveActivity/IslandViews.swift             (T4) Dynamic Island
├─ Preview/LiveActivitySamples.swift          (T4) un exemple par état
└─ Preview/SampleData.swift                   (T6, modifié) PreviewData.activityMatchIds
Resources/Assets.xcassets/icon-pause.imageset/  (T4, généré)
scripts/icones.sh                              (T4, modifié)

App/
├─ FailleApp.swift                            (T7, réécrit) AppRuntime, passage en arrière-plan, .backgroundTask
├─ Store/AppStore.swift                       (T3, T6 modifié)
├─ Store/AppStore+LiveActivity.swift          (T3 créé ; T6 et T7 ajoutent un bloc chacun)
├─ LiveActivity/ActivityGateway.swift         (T6) seul code ActivityKit
├─ LiveActivity/LiveActivityController.swift  (T6)
├─ LiveActivity/BackgroundRefresh.swift       (T7)
├─ Detail/LiveActivityPinButton.swift         (T6)
├─ Detail/MatchDetailView.swift               (T6, modifié)
└─ Settings/SettingsView.swift                (T6, modifié)

Widgets/
├─ FailleWidgets.swift                        (T5, modifié) MatchLiveActivity remplace ProbeLiveActivity
├─ MatchLiveActivity.swift                    (T5)
└─ ProbeAttributes.swift                      (T5, supprimé)

Tests/FailleTests/
├─ ApercuTests.swift                          (T4, modifié) 22 icônes
├─ Support/LiveActivityBoard.swift            (T4)
├─ LiveActivitySnapshotTests.swift            (T4)
├─ StorePrerequisitesTests.swift              (T3)
├─ LogoPipelineTests.swift                    (T3, modifié)
├─ StoreRefreshTests.swift                    (T3, modifié)
├─ LiveActivityControllerTests.swift          (T6)
└─ BackgroundRefreshTests.swift               (T7)

project.yml                                    (T7) UIBackgroundModes, BGTaskSchedulerPermittedIdentifiers
.github/workflows/ios.yml                      (T7) vérification de l'Info.plist de l'appli
docs/superpowers/notes/2026-10-etape-4-verdict.md  (T8)
```

## Commandes de vérification CI (rappel, utilisées dans chaque tâche)

Après `git push origin main` :

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
```

Expected : un identifiant numérique. Vide → le run n'est pas encore enregistré : relancer la commande quelques secondes plus tard. Puis `gh run watch --exit-status <id>` (Expected : tous les jobs verts ; la file d'attente des runners macOS peut durer 15 min ; un job « cancelled » sans étape se relance avec `gh run rerun --failed <id>`). En cas d'échec : `gh run view <id> --log-failed`, corriger, nouveau commit, recommencer. Pour LoLKit, même chose avec `--workflow LoLKit` (déclenché seulement si `LoLKit/**` change).

Télécharger les aperçus d'un run (tâches d'interface) :

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

L'exécutant vérifie la **présence** et la taille des PNG nommés et les copie dans `.superpowers/apercus/` ; le jugement visuel revient au contrôleur et à Dan.

**Avant la Task 1 :** vérifier que l'étape 3 est finie — `grep -n "public func reorder" LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift` (Expected : une ligne), `ls Shared/Widgets/WidgetChrome.swift Tests/FailleTests/Support/WidgetBoard.swift` (Expected : les deux fichiers), `grep -n "ProbeLiveActivity" Widgets/FailleWidgets.swift` (Expected : la Live Activity sonde est toujours là). Sinon, s'arrêter et le signaler.

---

### Task 1 : Contenu de la Live Activity (LoLKit)

`updatedAt` distinct de l'ancre du chrono, état remis dans l'ordre des équipes de la Live Activity, et ce qu'affiche chaque état (spec §6.1-§6.3, §8).

**Files :**
- Modify : `LoLKit/Sources/LoLKit/Live/LiveMatchBuilder.swift` (signature de `state` et ligne `updatedAt: now`)
- Modify : `LoLKit/Sources/LoLKit/Live/LiveMatchState.swift` (doc de `updatedAt`)
- Create : `LoLKit/Sources/LoLKit/Live/LiveActivityContent.swift`
- Create : `LoLKit/Sources/LoLKit/Live/LiveActivityDisplay.swift`
- Modify : `LoLKit/Tests/LoLKitTests/LiveMatchBuilderTests.swift` (un test ajouté à la fin de la suite)
- Create : `LoLKit/Tests/LoLKitTests/LiveActivityContentTests.swift`
- Create : `LoLKit/Tests/LoLKitTests/LiveActivityDisplayTests.swift`

**Interfaces :**
- Consumes (vérifiées dans les sources) :
  - `LiveMatchBuilder.state(details: EventDetails, snapshot: GameSnapshot?, firstFrameTime: Date?, statsDisabled: Bool, follows: FollowList, revealed: Set<String>, now: Date) -> LiveMatchState` ; `LiveMatchBuilder.attributes(for: EventDetails, follows: FollowList) -> LiveMatchAttributes?`
  - `LiveMatchState(phase:seriesScore:gameNumber:gameClockStart:gameClockStoppedAt:stats:statsAvailable:spoilerFree:winnerCode:updatedAt:)`, `.masked()`, `.staleDate`, `LiveMatchState.staleAfter` (180), `LiveMatchState.Phase` (`.upcoming`, `.inGame`, `.betweenGames`, `.finished`)
  - `LiveMatchAttributes(matchId:leagueName:bestOf:teams:primaryTeamIndex:)`, `LiveMatchAttributes.Side(id:code:name:colorHex:)`
  - `TeamStats(kills:gold:towers:inhibitors:barons:dragons:)` ; `MatchTeam` (`id: String?`, `name`, `code`) ; `EventDetails.match.teams`
  - `Format.gold(_:)`, `Format.goldDiff(_:)`, `Format.clock(_:)` ; `reorder(_:_:)` (public depuis l'étape 3, `Follow/DisplayOrder.swift`)
  - tests : `date(_:)`, `makeTeam(_:id:name:image:wins:)`, `makeDetails(wins:games:bestOf:teams:)`, `makeEvent(id:state:start:teams:bestOf:games:statsDisabled:)`, `Fixture.data(_:)`, `snapshot(_:)` (privé à `LiveMatchBuilderTests`)
- Produces :
  - `LiveMatchBuilder.state(details:snapshot:firstFrameTime:statsDisabled:follows:revealed:now:updatedAt:)` — `updatedAt: Date? = nil` (nil → `now`)
  - `public struct LiveActivityContent: Sendable, Equatable` — `teams: [MatchTeam]`, `attributes: LiveMatchAttributes?`, `state: LiveMatchState` ; `init(teams:attributes:state:)` ; `init(details: EventDetails, state: LiveMatchState, follows: FollowList)`
  - `extension LiveMatchState { public func aligned(from teams: [MatchTeam], to attributes: LiveMatchAttributes) -> LiveMatchState }`
  - `public struct LiveActivityDisplay: Sendable, Equatable` — `init(attributes:state:isStale:)` ; `header: String`, `teams: [Side]`, `score: [Int]?`, `gameNumber: Int?`, `status: Status`, `rows: [Row]`, `faded: Bool`, `message: Message?`, `tintHex: String?`, `isMasked: Bool`, `compactScore: String?` ; types `Side(code:colorHex:)`, `GameClock` (`.running(since:)`, `.stopped(String)`), `Status` (`.clock(GameClock)`, `.live`, `.betweenGames`, `.victory(String)`, `.finished`, `.stale(since:)` ; `label: String?`), `Stat` (`.kills`, `.gold`, `.towers`, `.drakes`, `.barons` ; `label`), `Row(stat:left:right:lead:leader:compact:)`, `Message` (`.masked`, `.nextGame(Int)`, `.statsUnavailable`, `.statsPending`, `.leavingSoon` ; `text`, `accent: String?`)

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `LoLKit/Tests/LoLKitTests/LiveMatchBuilderTests.swift`, ajouter juste avant l'accolade fermante de `struct LiveMatchBuilderTests` (après `payloadStaysSmall`) :

```swift

    /// Étape 4 : `updatedAt` est la dernière relecture réussie (d'où `staleDate`) ; `now` reste l'ancre du chrono.
    @Test func updatedAtIsTheLastGoodRefreshNotTheClockAnchor() throws {
        let refreshed = now.addingTimeInterval(-50)
        let details = makeDetails(wins: [0, 0], games: [(1, game1, .inProgress)])
        let state = LiveMatchBuilder.state(details: details, snapshot: try snapshot("window_ingame"),
                                           firstFrameTime: date("2026-10-04T20:18:26.892Z"),
                                           statsDisabled: false, follows: FollowList(), revealed: [], now: now,
                                           updatedAt: refreshed)
        #expect(state.updatedAt == refreshed)
        #expect(state.staleDate == refreshed.addingTimeInterval(LiveMatchState.staleAfter))
        let clock = try #require(state.gameClockStart)
        #expect(abs(clock.timeIntervalSince(now.addingTimeInterval(-1202.701))) < 0.01)
    }
```

Créer `LoLKit/Tests/LoLKitTests/LiveActivityContentTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// L'ordre des équipes d'une Live Activity est fixé à son démarrage ; chaque mise à jour y est ramenée (étape 4).
@Suite struct LiveActivityContentTests {
    private let tlaw = "98926509885559666"
    private let lyon = "99566405941863385"
    private let now = date("2026-10-04T20:39:30Z")

    /// Ordre de la Live Activity : TLAW, puis LYON.
    private var attributes: LiveMatchAttributes {
        LiveMatchAttributes(matchId: "115565004607949429", leagueName: "LCS", bestOf: 5,
                            teams: [.init(id: tlaw, code: "TLAW", name: "Team Liquid Alienware", colorHex: nil),
                                    .init(id: lyon, code: "LYON", name: "LYON", colorHex: nil)],
                            primaryTeamIndex: nil)
    }

    private func state(score: [Int]?, stats: [TeamStats]?) -> LiveMatchState {
        LiveMatchState(phase: .inGame, seriesScore: score, gameNumber: 2, gameClockStart: nil, gameClockStoppedAt: nil,
                       stats: stats, statsAvailable: true, spoilerFree: false, winnerCode: nil, updatedAt: now)
    }

    @Test func alignedPutsScoreAndStatsInTheActivityOrderById() {
        let source = [makeTeam("LYON", id: lyon), makeTeam("TLAW", id: tlaw)]
        let aligned = state(score: [1, 0], stats: [TeamStats(kills: 6), TeamStats(kills: 7)])
            .aligned(from: source, to: attributes)
        #expect(aligned.seriesScore == [0, 1])
        #expect(aligned.stats?.map(\.kills) == [7, 6])
    }

    @Test func scheduleTeamsWithoutIdsAreRecognisedByName() {
        let source = [makeTeam("LYON", name: "LYON"), makeTeam("TLAW", name: "Team Liquid Alienware")]
        #expect(state(score: [3, 1], stats: nil).aligned(from: source, to: attributes).seriesScore == [1, 3])
    }

    @Test func unknownTeamsLeaveTheStateUntouched() {
        let original = state(score: [1, 0], stats: nil)
        #expect(original.aligned(from: [makeTeam("X", id: "x"), makeTeam("Y", id: "y")], to: attributes) == original)
        #expect(original.aligned(from: [makeTeam("TLAW", id: tlaw)], to: attributes) == original)
    }

    @Test func aMaskedStateStaysMasked() {
        let masked = state(score: [1, 0], stats: nil).masked()
        #expect(masked.aligned(from: [makeTeam("LYON", id: lyon), makeTeam("TLAW", id: tlaw)], to: attributes) == masked)
    }

    @Test func contentFromDetailsCarriesAttributesAndTheSourceOrder() {
        let details = makeDetails(wins: [1, 0], games: [(2, "g2", .inProgress)])
        let built = LiveMatchBuilder.state(details: details, snapshot: nil, firstFrameTime: nil, statsDisabled: false,
                                           follows: FollowList(), revealed: [], now: now)
        let content = LiveActivityContent(details: details, state: built, follows: FollowList())
        #expect(content.teams.map(\.code) == ["TLAW", "LYON"])
        #expect(content.attributes?.teams.map(\.id) == [tlaw, lyon])
        #expect(content.state == built)
        // Calendrier : pas d'id d'équipe, donc pas d'attributs (on ne démarre jamais une Live Activity sans ids).
        let schedule = EventDetails(event: makeEvent(id: "m", state: .completed, teams: [makeTeam("KC"), makeTeam("C9")]))
        #expect(LiveActivityContent(details: schedule, state: built, follows: FollowList()).attributes == nil)
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/LiveActivityDisplayTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Ce qu'affiche la Live Activity dans chaque état (spec §6.1-§6.3) ; masquée, rien ne fuit (spec §8).
@Suite struct LiveActivityDisplayTests {
    private let now = date("2026-10-15T17:20:42Z")
    /// C9 d'abord dans l'API ; KC, suivie, est l'équipe principale : elle passe à gauche.
    private let attributes = LiveMatchAttributes(
        matchId: "m", leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "c9", code: "C9", name: "Cloud9", colorHex: nil),
                .init(id: "kc", code: "KC", name: "Karmine Corp", colorHex: "#5B8CFF")],
        primaryTeamIndex: 1)
    /// Dans l'ordre de l'API : C9 puis KC.
    private let stats = [
        TeamStats(kills: 4, gold: 30_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        TeamStats(kills: 7, gold: 32_400, towers: 3, inhibitors: 0, barons: 0, dragons: ["infernal", "ocean"]),
    ]

    private func state(_ phase: LiveMatchState.Phase = .inGame, score: [Int]? = [0, 1], game: Int? = 2,
                       start: Date? = nil, stoppedAt: Date? = nil, stats: [TeamStats]? = nil,
                       statsAvailable: Bool = true, winner: String? = nil) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: score, gameNumber: game, gameClockStart: start,
                       gameClockStoppedAt: stoppedAt, stats: stats, statsAvailable: statsAvailable, spoilerFree: false,
                       winnerCode: winner, updatedAt: now)
    }

    private func display(_ state: LiveMatchState, stale: Bool = false) -> LiveActivityDisplay {
        LiveActivityDisplay(attributes: attributes, state: state, isStale: stale)
    }

    @Test func inGameShowsTheFollowedTeamOnTheLeftWithClockAndFiveRows() {
        let start = now.addingTimeInterval(-1122)
        let shown = display(state(start: start, stats: stats))
        #expect(shown.teams == [.init(code: "KC", colorHex: "#5B8CFF"), .init(code: "C9", colorHex: nil)])
        #expect(shown.tintHex == "#5B8CFF")
        #expect(shown.header == "Mondial · Bo5 · Game 2")
        #expect(shown.score == [1, 0])
        #expect(shown.compactScore == "1-0")
        #expect(shown.gameNumber == 2)
        #expect(shown.status == .clock(.running(since: start)))
        #expect(shown.message == nil)
        #expect(!shown.faded)
        #expect(!shown.isMasked)
        #expect(shown.rows == [
            .init(stat: .kills, left: "7", right: "4", lead: nil, leader: nil, compact: "7–4"),
            .init(stat: .gold, left: "32,4k", right: "30,3k", lead: "+2,1k", leader: 0, compact: "+2,1k"),
            .init(stat: .towers, left: "3", right: "1", lead: nil, leader: nil, compact: "3–1"),
            .init(stat: .drakes, left: "2", right: "1", lead: nil, leader: nil, compact: "2–1"),
            .init(stat: .barons, left: "0", right: "0", lead: nil, leader: nil, compact: "0–0"),
        ])
    }

    @Test func clockStopsAtTheStopDateAndNeedsAStart() {
        let start = now.addingTimeInterval(-1122)
        #expect(display(state(start: start, stoppedAt: now, stats: stats)).status == .clock(.stopped("18:42")))
        // Une date d'arrêt sans date de début : pas de chrono du tout (journal LoLKit).
        #expect(display(state(stoppedAt: now, stats: stats)).status == .live)
    }

    @Test func staleReplacesTheClockAndFadesTheStats() {
        let shown = display(state(start: now.addingTimeInterval(-1122), stats: stats), stale: true)
        #expect(shown.status == .stale(since: now))
        #expect(shown.faded)
        #expect(shown.rows.count == 5)
        #expect(LiveActivityDisplay.Status.stale(since: now).label == "màj il y a")
    }

    @Test func maskedShowsOnlyThatItIsLive() {
        let shown = display(state(start: now, stats: stats).masked())
        #expect(shown.isMasked)
        #expect(shown.score == nil)
        #expect(shown.compactScore == nil)
        #expect(shown.gameNumber == nil)
        #expect(shown.header == "Mondial · Bo5")
        #expect(shown.status == .live)
        #expect(shown.rows.isEmpty)
        #expect(shown.message == .masked)
        #expect(LiveActivityDisplay.Message.masked.text == "Sans spoiler ·")
        #expect(LiveActivityDisplay.Message.masked.accent == "ouvre l'appli pour révéler")
        // Entre deux games ou terminé, masqué : jamais plus que « En direct » / « Terminé ».
        #expect(display(state(.betweenGames, score: [0, 2], game: 3).masked()).status == .live)
        let finished = display(state(.finished, score: [1, 3], game: nil, winner: "KC").masked())
        #expect(finished.status == .finished)
        #expect(finished.header == "Mondial · Bo5")
    }

    @Test func betweenGamesAnnouncesTheNextGame() {
        let shown = display(state(.betweenGames, score: [0, 2], game: 3, stats: stats))
        #expect(shown.score == [2, 0])
        #expect(shown.header == "Mondial · Bo5 · Game 3")
        #expect(shown.status == .betweenGames)
        #expect(shown.rows.isEmpty)
        #expect(shown.message == .nextGame(3))
        #expect(shown.message?.text == "La game 3 commence dans quelques minutes")
    }

    @Test func liveBeforeTheFirstGameAnnouncesGameOne() {
        let shown = display(state(.upcoming, score: [0, 0], game: 1))
        #expect(shown.status == .live)
        #expect(shown.message == .nextGame(1))
    }

    @Test func finishedShowsTheWinnerEvenWhenStale() {
        let shown = display(state(.finished, score: [1, 3], game: nil, winner: "KC"), stale: true)
        #expect(shown.score == [3, 1])
        #expect(shown.header == "Mondial · Bo5 · terminé")
        #expect(shown.status == .victory("KC"))
        #expect(shown.status.label == "Victoire KC")
        #expect(shown.message == .leavingSoon)
        #expect(!shown.faded)
        #expect(display(state(.finished, score: [0, 0], game: nil)).status == .finished)
    }

    @Test func statsUnavailableOrNotYetLoaded() {
        let start = now.addingTimeInterval(-1330)
        let unavailable = display(state(start: start, statsAvailable: false))
        #expect(unavailable.status == .clock(.running(since: start)))
        #expect(unavailable.message == .statsUnavailable)
        #expect(unavailable.message?.text == "Stats live non fournies par Riot pour ce match")
        #expect(display(state(start: start)).message == .statsPending)
    }

    @Test func noFollowedTeamMeansNeutralGlassAndApiOrder() {
        let neutral = LiveMatchAttributes(matchId: "m", leagueName: "LFL", bestOf: 3,
                                          teams: [.init(id: "kcb", code: "KCB", name: "Karmine Corp Blue", colorHex: nil),
                                                  .init(id: "sly", code: "SLY", name: "Solary", colorHex: nil)],
                                          primaryTeamIndex: nil)
        let shown = LiveActivityDisplay(attributes: neutral, state: state(score: [1, 0]), isStale: false)
        #expect(shown.tintHex == nil)
        #expect(shown.teams.map(\.code) == ["KCB", "SLY"])
        #expect(shown.score == [1, 0])
        #expect(shown.header == "LFL · Bo3 · Game 2")
    }

    @Test func labels() {
        #expect(LiveActivityDisplay.Stat.allCases.map(\.label) == ["Kills", "Gold", "Tours", "Drakes", "Barons"])
        #expect(LiveActivityDisplay.Status.live.label == "En direct")
        #expect(LiveActivityDisplay.Status.betweenGames.label == "entre deux games")
        #expect(LiveActivityDisplay.Status.finished.label == "Terminé")
        #expect(LiveActivityDisplay.Status.clock(.stopped("1:00")).label == nil)
        #expect(LiveActivityDisplay.Message.statsPending.text == "Stats en attente du flux de Riot")
        #expect(LiveActivityDisplay.Message.leavingSoon.text == "Se retire de l'écran verrouillé au bout d'une heure")
        #expect(LiveActivityDisplay.Message.nextGame(2).accent == nil)
    }
}
```

- [ ] **Step 2 : Lancer les tests, vérifier qu'ils échouent**

Run : `bash scripts/lolkit.sh test --filter "LiveActivityContentTests|LiveActivityDisplayTests|LiveMatchBuilderTests"`
Expected : FAIL à la compilation — `extra argument 'updatedAt' in call`, `cannot find 'LiveActivityContent' in scope`, `cannot find 'LiveActivityDisplay' in scope`, `value of type 'LiveMatchState' has no member 'aligned'`.

- [ ] **Step 3 : `updatedAt` distinct dans `LiveMatchBuilder`**

Dans `LoLKit/Sources/LoLKit/Live/LiveMatchBuilder.swift`, remplacer :

```swift
    ///   - revealed: ids de matchs que l'utilisateur a choisi de révéler.
    public static func state(
        details: EventDetails,
        snapshot: GameSnapshot?,
        firstFrameTime: Date?,
        statsDisabled: Bool,
        follows: FollowList,
        revealed: Set<String>,
        now: Date
    ) -> LiveMatchState {
```

par :

```swift
    ///   - revealed: ids de matchs que l'utilisateur a choisi de révéler.
    ///   - now: heure de réception de la frame : ancre du chrono (et date d'arrêt d'une game en pause ou finie).
    ///   - updatedAt: dernière relecture réussie des données qui nourrissent cet état (spec §4.3) ; c'est elle qui donne
    ///     `staleDate`. nil : `now`.
    public static func state(
        details: EventDetails,
        snapshot: GameSnapshot?,
        firstFrameTime: Date?,
        statsDisabled: Bool,
        follows: FollowList,
        revealed: Set<String>,
        now: Date,
        updatedAt: Date? = nil
    ) -> LiveMatchState {
```

puis, plus bas dans la même fonction, remplacer la ligne :

```swift
            updatedAt: now
```

par :

```swift
            updatedAt: updatedAt ?? now
```

Dans `LoLKit/Sources/LoLKit/Live/LiveMatchState.swift`, remplacer :

```swift
    public var winnerCode: String?
    public var updatedAt: Date
```

par :

```swift
    public var winnerCode: String?
    /// Dernière relecture réussie des données qui ont produit cet état (ni l'heure du calcul, ni l'ancre du chrono) :
    /// `staleDate` en découle. Format inchangé dans le contrat (secondes depuis 2001).
    public var updatedAt: Date
```

- [ ] **Step 4 : `LiveActivityContent` et `aligned`**

Créer `LoLKit/Sources/LoLKit/Live/LiveActivityContent.swift` :

```swift
import Foundation

/// Contenu d'une Live Activity à un instant (spec §4.3, §6) : les attributs pour la démarrer, l'état (anti-spoiler
/// compris) et les équipes de la source dans l'ordre de cet état — pour le ramener à l'ordre fixé au démarrage.
public struct LiveActivityContent: Sendable, Equatable {
    /// Équipes de la source (`getLive`, calendrier…), dans l'ordre de `state.seriesScore` et `state.stats`.
    public let teams: [MatchTeam]
    /// Attributs pour démarrer une Live Activity ; nil si une équipe n'a pas d'id (calendrier) : on n'en démarre pas.
    public let attributes: LiveMatchAttributes?
    public let state: LiveMatchState

    public init(teams: [MatchTeam], attributes: LiveMatchAttributes?, state: LiveMatchState) {
        self.teams = teams
        self.attributes = attributes
        self.state = state
    }

    /// Contenu tiré de détails de match : attributs de `LiveMatchBuilder.attributes` (couleurs et équipe principale
    /// d'après les équipes suivies), équipes dans l'ordre des détails, donc de `state`.
    public init(details: EventDetails, state: LiveMatchState, follows: FollowList) {
        self.init(teams: details.match.teams,
                  attributes: LiveMatchBuilder.attributes(for: details, follows: follows),
                  state: state)
    }
}

extension LiveMatchState {
    /// Score de série et stats remis dans l'ordre des équipes de `attributes` (fixé au démarrage de la Live Activity) :
    /// chaque équipe est reconnue par son id, sinon son nom (sans la casse), sinon — en dernier recours, et seulement
    /// entre les deux équipes d'un même match — son code. Inchangé si une équipe n'est pas reconnue.
    public func aligned(from teams: [MatchTeam], to attributes: LiveMatchAttributes) -> LiveMatchState {
        guard teams.count == attributes.teams.count else { return self }
        var order: [Int] = []
        for side in attributes.teams {
            guard let index = teams.firstIndex(where: { Self.isSame($0, side) }), !order.contains(index) else {
                return self
            }
            order.append(index)
        }
        var copy = self
        copy.seriesScore = seriesScore.flatMap { reorder($0, order) }
        copy.stats = stats.flatMap { reorder($0, order) }
        return copy
    }

    static func isSame(_ team: MatchTeam, _ side: LiveMatchAttributes.Side) -> Bool {
        if let id = team.id { return id == side.id }
        if team.name.lowercased() == side.name.lowercased() { return true }
        return team.code == side.code
    }
}
```

- [ ] **Step 5 : `LiveActivityDisplay`**

Créer `LoLKit/Sources/LoLKit/Live/LiveActivityDisplay.swift` :

```swift
import Foundation

/// Ce qu'affiche une Live Activity (spec §6.1-§6.3, maquettes ① et ②), calculé sans SwiftUI pour être testé sur
/// Windows : l'écran verrouillé et la Dynamic Island ne font que poser ces valeurs. L'anti-spoiler est déjà dans l'état
/// (`LiveMatchBuilder.state` → `masked()`) : masqué, il n'y a ici ni score, ni numéro de game, ni chrono, ni stats, ni
/// vainqueur (spec §8). Une Live Activity n'annonce jamais de prochain match.
public struct LiveActivityDisplay: Sendable, Equatable {
    /// Une équipe, dans l'ordre d'affichage : l'équipe suivie (principale) à gauche, comme les maquettes.
    public struct Side: Sendable, Equatable {
        public let code: String
        /// Couleur de l'équipe si elle est suivie ; nil : verre neutre.
        public let colorHex: String?

        public init(code: String, colorHex: String?) {
            self.code = code
            self.colorHex = colorHex
        }
    }

    /// Chrono de la game en cours.
    public enum GameClock: Sendable, Equatable {
        /// Tourne seul depuis cette date (minuteur natif d'iOS : aucune mise à jour nécessaire).
        case running(since: Date)
        /// Figé (game en pause ou finie dans le flux) : « 18:42 ».
        case stopped(String)
    }

    /// À droite de l'en-tête.
    public enum Status: Sendable, Equatable {
        case clock(GameClock)
        /// « En direct » : match masqué, avant la game 1, ou game en cours dont le début est inconnu.
        case live
        /// « entre deux games ».
        case betweenGames
        /// « Victoire KC ».
        case victory(String)
        /// « Terminé » : match masqué, ou vainqueur inconnu (forfait, Bo2).
        case finished
        /// « màj il y a X min » à la place du chrono : rien de frais depuis `since` (spec §6.3).
        case stale(since: Date)

        /// Texte fixe ; nil pour le chrono (minuteur natif). Pour `.stale`, la vue ajoute la durée (minuteur natif).
        public var label: String? {
            switch self {
            case .clock: return nil
            case .live: return "En direct"
            case .betweenGames: return "entre deux games"
            case let .victory(code): return "Victoire \(code)"
            case .finished: return "Terminé"
            case .stale: return "màj il y a"
            }
        }
    }

    /// Les 5 stats de la spec §6.1, dans l'ordre d'affichage.
    public enum Stat: String, Sendable, Hashable, CaseIterable {
        case kills, gold, towers, drakes, barons

        public var label: String {
            switch self {
            case .kills: return "Kills"
            case .gold: return "Gold"
            case .towers: return "Tours"
            case .drakes: return "Drakes"
            case .barons: return "Barons"
            }
        }
    }

    /// Une ligne « 7 · KILLS · 4 ». Pour le gold : l'écart (« +2,1k ») à côté de l'équipe qui mène (`leader`, 0 ou 1).
    public struct Row: Sendable, Equatable {
        public let stat: Stat
        public let left: String
        public let right: String
        public let lead: String?
        public let leader: Int?
        /// Version courte de la Dynamic Island déployée : « 7–4 », « +2,1k ».
        public let compact: String

        public init(stat: Stat, left: String, right: String, lead: String?, leader: Int?, compact: String) {
            self.stat = stat
            self.left = left
            self.right = right
            self.lead = lead
            self.leader = leader
            self.compact = compact
        }
    }

    /// Message sous le score.
    public enum Message: Sendable, Equatable {
        /// « Sans spoiler · ouvre l'appli pour révéler » (spec §8 : la révélation se fait dans l'appli).
        case masked
        /// « La game 3 commence dans quelques minutes » (spec §6.3).
        case nextGame(Int)
        /// Riot ne fournit pas les stats de ce match (spec §6.3).
        case statsUnavailable
        /// Stats prévues mais pas encore reçues du flux.
        case statsPending
        /// Match terminé : la Live Activity se retire au bout d'une heure (spec §6.3).
        case leavingSoon

        public var text: String {
            switch self {
            case .masked: return "Sans spoiler ·"
            case let .nextGame(number): return "La game \(number) commence dans quelques minutes"
            case .statsUnavailable: return "Stats live non fournies par Riot pour ce match"
            case .statsPending: return "Stats en attente du flux de Riot"
            case .leavingSoon: return "Se retire de l'écran verrouillé au bout d'une heure"
            }
        }

        /// Suite du texte, à la couleur d'accent.
        public var accent: String? {
            if case .masked = self { return "ouvre l'appli pour révéler" }
            return nil
        }
    }

    /// « Mondial · Bo5 · Game 2 » (« · terminé » à la fin ; rien après le Bo si masqué). La vue le met en capitales.
    public let header: String
    public let teams: [Side]
    /// Victoires dans l'ordre de `teams` ; nil si masqué.
    public let score: [Int]?
    /// nil si masqué ou terminé.
    public let gameNumber: Int?
    public let status: Status
    /// Les 5 lignes de stats ; vides hors d'une game en cours, sans stats, ou si masqué.
    public let rows: [Row]
    /// Pas fraîche : les stats pâlissent (spec §6.3).
    public let faded: Bool
    public let message: Message?
    /// Couleur du fond : celle de l'équipe suivie en premier (`primaryTeamIndex`) ; nil : verre neutre.
    public let tintHex: String?
    public let isMasked: Bool

    public init(attributes: LiveMatchAttributes, state: LiveMatchState, isStale: Bool) {
        let order = Self.order(attributes)
        let masked = state.spoilerFree
        let finished = state.phase == .finished
        teams = (reorder(attributes.teams, order) ?? attributes.teams).map { Side(code: $0.code, colorHex: $0.colorHex) }
        tintHex = attributes.primaryTeamIndex.flatMap { index in
            attributes.teams.indices.contains(index) ? attributes.teams[index].colorHex : nil
        }
        isMasked = masked
        score = masked ? nil : state.seriesScore.flatMap { reorder($0, order) }
        gameNumber = masked ? nil : state.gameNumber

        var parts = [attributes.leagueName, "Bo\(attributes.bestOf)"]
        if !masked {
            if finished {
                parts.append("terminé")
            } else if let number = state.gameNumber {
                parts.append("Game \(number)")
            }
        }
        header = parts.joined(separator: " · ")

        if isStale && !finished {
            status = .stale(since: state.updatedAt)
        } else if masked {
            status = finished ? .finished : .live
        } else {
            switch state.phase {
            case .inGame: status = Self.runningClock(state).map { Status.clock($0) } ?? .live
            case .betweenGames: status = .betweenGames
            case .upcoming: status = .live
            case .finished: status = state.winnerCode.map { Status.victory($0) } ?? .finished
            }
        }

        var shownRows: [Row] = []
        if !masked, state.phase == .inGame, let stats = state.stats.flatMap({ reorder($0, order) }), stats.count == 2 {
            shownRows = Self.rows(stats[0], stats[1])
        }
        rows = shownRows
        faded = isStale && !finished

        if masked {
            message = .masked
        } else {
            switch state.phase {
            case .finished: message = .leavingSoon
            case .betweenGames, .upcoming: message = .nextGame(state.gameNumber ?? 1)
            case .inGame: message = !state.statsAvailable ? .statsUnavailable : (shownRows.isEmpty ? .statsPending : nil)
            }
        }
    }

    /// Score de la Dynamic Island minimale : « 1-0 » ; nil si masqué.
    public var compactScore: String? {
        guard let score, score.count == 2 else { return nil }
        return "\(score[0])-\(score[1])"
    }

    /// Ordre d'affichage : l'équipe principale à gauche.
    static func order(_ attributes: LiveMatchAttributes) -> [Int] {
        attributes.primaryTeamIndex == 1 && attributes.teams.count == 2 ? [1, 0] : Array(attributes.teams.indices)
    }

    /// Chrono d'une game en cours ; une date d'arrêt sans date de début ne donne pas de chrono.
    static func runningClock(_ state: LiveMatchState) -> GameClock? {
        guard let start = state.gameClockStart else { return nil }
        if let stopped = state.gameClockStoppedAt {
            return .stopped(Format.clock(stopped.timeIntervalSince(start)))
        }
        return .running(since: start)
    }

    /// Kills, gold (écart à côté du meneur), tours, drakes, barons ; `a` est l'équipe de gauche.
    static func rows(_ a: TeamStats, _ b: TeamStats) -> [Row] {
        func plain(_ stat: Stat, _ x: Int, _ y: Int) -> Row {
            Row(stat: stat, left: "\(x)", right: "\(y)", lead: nil, leader: nil, compact: "\(x)–\(y)")
        }
        let diff = a.gold - b.gold
        let leader: Int? = diff > 0 ? 0 : (diff < 0 ? 1 : nil)
        let lead = leader.map { _ in Format.goldDiff(abs(diff)) }
        return [
            plain(.kills, a.kills, b.kills),
            Row(stat: .gold, left: Format.gold(a.gold), right: Format.gold(b.gold), lead: lead, leader: leader,
                compact: lead ?? Format.goldDiff(0)),
            plain(.towers, a.towers, b.towers),
            plain(.drakes, a.dragons.count, b.dragons.count),
            plain(.barons, a.barons, b.barons),
        ]
    }
}
```

- [ ] **Step 6 : Lancer les tests, vérifier qu'ils passent**

Run : `bash scripts/lolkit.sh test --filter "LiveActivityContentTests|LiveActivityDisplayTests|LiveMatchBuilderTests|LiveContractTests"`
Expected : PASS — 5 + 10 tests nouveaux, `LiveMatchBuilderTests` (dont `updatedAtIsTheLastGoodRefreshNotTheClockAnchor`) et `LiveContractTests` verts (contrat inchangé : `git diff --stat LoLKit/Tests/LoLKitTests/Fixtures` → rien).
Run : `bash scripts/lolkit.sh test` → Expected : aucun échec, total précédent + 16, aucun avertissement de compilation.

- [ ] **Step 7 : Commit, push, CI**

```bash
git add LoLKit/Sources/LoLKit/Live/LiveMatchBuilder.swift LoLKit/Sources/LoLKit/Live/LiveMatchState.swift LoLKit/Sources/LoLKit/Live/LiveActivityContent.swift LoLKit/Sources/LoLKit/Live/LiveActivityDisplay.swift LoLKit/Tests/LoLKitTests/LiveMatchBuilderTests.swift LoLKit/Tests/LoLKitTests/LiveActivityContentTests.swift LoLKit/Tests/LoLKitTests/LiveActivityDisplayTests.swift
git commit -m "feat(lolkit): contenu de la Live Activity — updatedAt distinct du chrono, état aligné sur ses équipes, affichage de chaque état" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : LoLKit vert (Linux + macOS) ; iOS vert (l'appli compile inchangée : le paramètre `updatedAt` a une valeur par défaut).

---

### Task 2 : Décisions des Live Activities (LoLKit)

Quoi démarrer en tenant compte des Live Activities existantes, quoi faire de chacune à une mise à jour, choix de l'utilisateur, prochain réveil en arrière-plan (spec §6.3, §6.4).

**Files :**
- Modify (réécrit) : `LoLKit/Sources/LoLKit/Live/LiveActivityPlanner.swift`
- Create : `LoLKit/Sources/LoLKit/Live/LiveActivityChoices.swift`
- Modify : `LoLKit/Tests/LoLKitTests/LiveActivityPlannerTests.swift` (6 tests ajoutés à la fin de la suite)
- Create : `LoLKit/Tests/LoLKitTests/LiveActivityDecisionTests.swift`
- Create : `LoLKit/Tests/LoLKitTests/LiveActivityChoicesTests.swift`

**Interfaces :**
- Consumes : `LiveActivityPlanner.plan(live:follows:mode:pinned:dismissed:)` et ses 5 tests existants (inchangés) ; `LiveActivityMode` (`.automatic`, `.manual`) ; `FollowList.teams`, `.involves(_:)` ; `MatchTeam.isSame(as:)` ; `MatchEvent.id`, `.match.teams` ; `LiveActivityContent`, `LiveMatchState.aligned(from:to:)` (Task 1) ; tests : `makeEvent`, `makeTeam`, `catalogTeam`, `date`.
- Produces :
  - `public enum LiveActivityUpdate: Sendable, Equatable { case keep; case update(LiveMatchState); case end(LiveMatchState, dismissAt: Date?) }`
  - `LiveActivityPlanner.plan(live:follows:mode:pinned:dismissed:active:)` — `active: [String] = []`
  - `LiveActivityPlanner.decision(attributes: LiveMatchAttributes, current: LiveMatchState, latest: LiveActivityContent?, isPinned: Bool, mode: LiveActivityMode, now: Date) -> LiveActivityUpdate`
  - `LiveActivityPlanner.nextBackgroundRefresh(now: Date, live: [MatchEvent]?, follows: FollowList, hasActivities: Bool) -> Date?`
  - constantes `LiveActivityPlanner.maxConcurrent` (3, inchangée), `.finishedDisplay` (3 600 s), `.backgroundInterval` (900 s)
  - `public struct LiveActivityChoices: Codable, Sendable, Equatable` — `pinned`, `dismissed`, `started: [String: Date]` (`public private(set)`) ; `init(pinned:dismissed:started:)` (défauts vides) ; `pinnedIds: [String]`, `dismissedIds: Set<String>`, `isPinned(_:)` ; `mutating pin(_:now:)`, `dismiss(_:now:)`, `markStarted(_:now:)`, `markEnded(_:)`, `reconcile(running:now:)` ; `pruned(now:) -> LiveActivityChoices` ; `static let retention` (86 400 s)

- [ ] **Step 1 : Écrire les tests qui échouent**

Dans `LoLKit/Tests/LoLKitTests/LiveActivityPlannerTests.swift`, ajouter juste avant l'accolade fermante de `struct LiveActivityPlannerTests` (après `neverMoreThanThree`) :

```swift

    // MARK: Live Activities déjà à l'écran (étape 4)

    @Test func existingActivitiesKeepTheirPlaceAndCountTowardsTheLimit() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, other], follows: try follows(), mode: .automatic,
                                            pinned: [], dismissed: [], active: ["other"])
        #expect(plan == ["other", "kc", "t1"])
    }

    @Test func aFinishedMatchStillOnScreenTakesASlot() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc], follows: try follows(), mode: .automatic,
                                            pinned: [], dismissed: [], active: ["fini"])
        #expect(plan == ["fini", "kc", "t1"])
    }

    @Test func nothingNewWhenThreeAreAlreadyShown() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc], follows: try follows(), mode: .automatic,
                                            pinned: ["kc"], dismissed: [], active: ["a", "b", "c"])
        #expect(plan == ["a", "b", "c"])
    }

    @Test func pinnedGetTheFreeSlotsBeforeAutomatic() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1, kc, other], follows: try follows(), mode: .automatic,
                                            pinned: ["other"], dismissed: [], active: ["kc"])
        #expect(plan == ["kc", "other", "t1"])
    }

    @Test func manualModeOnlyAddsLivePinnedNextToExistingOnes() throws {
        let plan = LiveActivityPlanner.plan(live: [gen, t1], follows: try follows(), mode: .manual,
                                            pinned: ["gen"], dismissed: [], active: ["t1"])
        #expect(plan == ["t1", "gen"])
    }

    /// Spec §6.4 : réveil en arrière-plan toutes les 15 min tant qu'un match suivi est en direct (ou qu'une Live
    /// Activity est à l'écran, pour la terminer).
    @Test func backgroundRefreshOnlyWhileAFollowedMatchIsLiveOrAnActivityIsShown() throws {
        let now = date("2026-10-15T17:00:00Z")
        let list = try follows()
        let soon = now.addingTimeInterval(LiveActivityPlanner.backgroundInterval)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: [kc], follows: list, hasActivities: false) == soon)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: [other], follows: list, hasActivities: false) == nil)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: [other], follows: list, hasActivities: true) == soon)
        #expect(LiveActivityPlanner.nextBackgroundRefresh(now: now, live: nil, follows: list, hasActivities: false) == nil)
        #expect(LiveActivityPlanner.backgroundInterval == 900)
    }
```

Créer `LoLKit/Tests/LoLKitTests/LiveActivityDecisionTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Que faire d'une Live Activity en cours à chaque mise à jour (spec §6.3, §6.4).
@Suite struct LiveActivityDecisionTests {
    private let now = date("2026-10-15T17:20:00Z")
    /// Ordre de la Live Activity : KC, puis C9.
    private let attributes = LiveMatchAttributes(
        matchId: "kc-c9", leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "kc", code: "KC", name: "Karmine Corp", colorHex: "#5B8CFF"),
                .init(id: "c9", code: "C9", name: "Cloud9", colorHex: nil)],
        primaryTeamIndex: 0)

    private func state(_ phase: LiveMatchState.Phase = .inGame, score: [Int]? = [1, 0], updatedAt: Date) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: score, gameNumber: phase == .finished ? nil : 2, gameClockStart: nil,
                       gameClockStoppedAt: nil, stats: nil, statsAvailable: true, spoilerFree: false,
                       winnerCode: phase == .finished ? "KC" : nil, updatedAt: updatedAt)
    }

    private func content(_ state: LiveMatchState, teams: [MatchTeam]? = nil) -> LiveActivityContent {
        LiveActivityContent(teams: teams ?? [makeTeam("KC", id: "kc"), makeTeam("C9", id: "c9")],
                            attributes: attributes, state: state)
    }

    private func decide(_ current: LiveMatchState, _ latest: LiveActivityContent?, pinned: Bool = false,
                        mode: LiveActivityMode = .automatic) -> LiveActivityUpdate {
        LiveActivityPlanner.decision(attributes: attributes, current: current, latest: latest, isPinned: pinned,
                                     mode: mode, now: now)
    }

    @Test func newerContentIsSent() {
        let latest = state(score: [2, 0], updatedAt: now)
        #expect(decide(state(updatedAt: now.addingTimeInterval(-60)), content(latest)) == .update(latest))
    }

    @Test func theSameRefreshIsNotSentAgainEvenWithLessData() {
        var current = state(updatedAt: now)
        #expect(decide(current, content(current)) == .keep)
        // Même relecture, mais stats pas encore rechargées (appli relancée hors ligne) : on n'efface rien.
        current.stats = [TeamStats(kills: 7), TeamStats(kills: 4)]
        #expect(decide(current, content(state(updatedAt: now))) == .keep)
    }

    @Test func olderContentNeverReplacesNewer() {
        #expect(decide(state(updatedAt: now), content(state(score: [0, 0], updatedAt: now.addingTimeInterval(-120)))) == .keep)
    }

    @Test func aRevealOrAMaskIsSentWithoutANewRefresh() {
        let revealed = state(updatedAt: now)
        let masked = revealed.masked()
        #expect(decide(masked, content(revealed)) == .update(revealed))
        #expect(decide(revealed, content(masked)) == .update(masked))
    }

    @Test func nothingNewKeepsTheActivityAsItIs() {
        #expect(decide(state(updatedAt: now), nil) == .keep)
    }

    @Test func aFinishedMatchEndsAndStaysAnHour() {
        let finished = state(.finished, score: [3, 1], updatedAt: now)
        #expect(decide(state(updatedAt: now.addingTimeInterval(-60)), content(finished))
                == .end(finished, dismissAt: now.addingTimeInterval(3600)))
    }

    @Test func manualModeEndsWhatIsNotPinned() {
        let current = state(updatedAt: now)
        #expect(decide(current, content(current), mode: .manual) == .end(current, dismissAt: nil))
        let latest = state(score: [2, 0], updatedAt: now.addingTimeInterval(60))
        #expect(decide(current, content(latest), pinned: true, mode: .manual) == .update(latest))
    }

    @Test func theLatestStateIsPutBackInTheActivityTeamOrder() {
        let swapped = state(score: [0, 2], updatedAt: now.addingTimeInterval(60))   // source : C9 puis KC
        let expected = state(score: [2, 0], updatedAt: now.addingTimeInterval(60))
        #expect(decide(state(updatedAt: now), content(swapped, teams: [makeTeam("C9", id: "c9"), makeTeam("KC", id: "kc")]))
                == .update(expected))
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/LiveActivityChoicesTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Épinglés, retirés à la main, démarrés par l'appli (spec §6.4) ; épinglés et retirés restent disjoints.
@Suite struct LiveActivityChoicesTests {
    private let now = date("2026-10-15T17:00:00Z")

    @Test func pinAndDismissStayDisjoint() {
        var choices = LiveActivityChoices()
        choices.pin("a", now: now)
        #expect(choices.isPinned("a"))
        choices.dismiss("a", now: now)
        #expect(!choices.isPinned("a"))
        #expect(choices.dismissedIds == ["a"])
        choices.pin("a", now: now)
        #expect(choices.isPinned("a"))
        #expect(choices.dismissedIds.isEmpty)
    }

    @Test func pinnedComeInPinOrder() {
        var choices = LiveActivityChoices()
        choices.pin("b", now: now)
        choices.pin("a", now: now.addingTimeInterval(10))
        choices.pin("b", now: now.addingTimeInterval(20))   // déjà épinglé : garde sa place
        #expect(choices.pinnedIds == ["b", "a"])
    }

    @Test func activitiesThatVanishedWithoutTheAppAreDismissed() {
        var choices = LiveActivityChoices()
        choices.markStarted("a", now: now)
        choices.markStarted("b", now: now)
        choices.pin("b", now: now)
        choices.reconcile(running: ["a"], now: now)
        #expect(choices.dismissedIds == ["b"])
        #expect(!choices.isPinned("b"))
        #expect(choices.started.keys.sorted() == ["a"])
    }

    @Test func endedByTheAppIsNotADismissal() {
        var choices = LiveActivityChoices()
        choices.markStarted("a", now: now)
        choices.markEnded("a")
        choices.reconcile(running: [], now: now)
        #expect(choices.dismissedIds.isEmpty)
        #expect(choices.started.isEmpty)
    }

    @Test func marksOlderThanADayAreForgotten() {
        var choices = LiveActivityChoices()
        choices.pin("old", now: now)
        choices.dismiss("gone", now: now)
        choices.markStarted("run", now: now)
        #expect(choices.pruned(now: now.addingTimeInterval(3600)) == choices)
        #expect(choices.pruned(now: now.addingTimeInterval(LiveActivityChoices.retention + 1)) == LiveActivityChoices())
    }

    @Test func decodingIsTolerant() throws {
        var choices = LiveActivityChoices()
        choices.pin("a", now: now)
        choices.dismiss("b", now: now)
        let data = try JSONEncoder().encode(choices)
        #expect(try JSONDecoder().decode(LiveActivityChoices.self, from: data) == choices)
        #expect(try JSONDecoder().decode(LiveActivityChoices.self, from: Data("{}".utf8)) == LiveActivityChoices())
        let partial = try JSONDecoder().decode(LiveActivityChoices.self,
                                               from: Data(#"{"pinned":{"a":813415300},"dismissed":"illisible"}"#.utf8))
        #expect(partial.pinnedIds == ["a"])
        #expect(partial.dismissedIds.isEmpty)
    }
}
```

- [ ] **Step 2 : Lancer les tests, vérifier qu'ils échouent**

Run : `bash scripts/lolkit.sh test --filter "LiveActivityPlannerTests|LiveActivityDecisionTests|LiveActivityChoicesTests"`
Expected : FAIL à la compilation — `extra argument 'active' in call`, `type 'LiveActivityPlanner' has no member 'decision'` / `'nextBackgroundRefresh'` / `'backgroundInterval'`, `cannot find 'LiveActivityChoices' in scope`, `cannot find type 'LiveActivityUpdate' in scope`.

- [ ] **Step 3 : Réécrire `LiveActivityPlanner.swift`**

Remplacer tout le contenu de `LoLKit/Sources/LoLKit/Live/LiveActivityPlanner.swift` par :

```swift
import Foundation

/// Réglage « Live Activity » (spec §5.4).
public enum LiveActivityMode: String, Codable, Sendable {
    case automatic, manual
}

/// Ce que l'appli doit faire d'une Live Activity en cours, à une mise à jour (spec §6.3, §6.4).
public enum LiveActivityUpdate: Sendable, Equatable {
    /// Rien de neuf : aucun appel à ActivityKit (la Live Activity passe « pas fraîche » d'elle-même à sa `staleDate`).
    case keep
    /// Nouveau contenu, déjà dans l'ordre des équipes de la Live Activity.
    case update(LiveMatchState)
    /// Contenu final, puis retrait de l'écran verrouillé à `dismissAt` ; nil : tout de suite.
    case end(LiveMatchState, dismissAt: Date?)
}

/// Décide quelles Live Activities démarrer, mettre à jour et terminer (spec §6.4). Fonctions pures : l'appli
/// (`LiveActivityController`) les applique avec ActivityKit.
public enum LiveActivityPlanner {
    /// Au plus 3 Live Activities à l'écran en même temps.
    public static let maxConcurrent = 3
    /// Une Live Activity de match terminé reste affichée 1 h (spec §6.3).
    public static let finishedDisplay: TimeInterval = 3600
    /// Délai demandé à iOS entre deux réveils en arrière-plan (spec §6.4) ; iOS peut accorder plus tard, ou rien.
    public static let backgroundInterval: TimeInterval = 15 * 60

    /// Matchs qui doivent avoir une Live Activity, par priorité : d'abord ceux qui en ont déjà une (`active` : en cours,
    /// ou terminée et encore affichée ; ils gardent leur place, comptent dans la limite et ne sont jamais remplacés),
    /// puis les épinglés en direct, puis, en automatique, les matchs des équipes suivies dans l'ordre de suivi, sauf
    /// ceux retirés à la main. Les nouveaux venus ne prennent que les places libres (`maxConcurrent` en tout) ; ceux qui
    /// ne sont pas dans `active` sont à démarrer.
    public static func plan(
        live: [MatchEvent],
        follows: FollowList,
        mode: LiveActivityMode,
        pinned: [String],
        dismissed: Set<String>,
        active: [String] = []
    ) -> [String] {
        let liveIds = Set(live.map(\.id))
        var result: [String] = []
        for id in active where !result.contains(id) {
            result.append(id)
        }
        let kept = result.count
        for id in pinned where liveIds.contains(id) && !result.contains(id) {
            result.append(id)
        }
        if mode == .automatic {
            let ranked = live.enumerated()
                .compactMap { position, event -> (rank: Int, position: Int, id: String)? in
                    let ranks = follows.teams.indices.filter { index in
                        event.match.teams.contains { $0.isSame(as: follows.teams[index]) }
                    }
                    return ranks.min().map { (rank: $0, position: position, id: event.id) }
                }
                .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            for candidate in ranked where !dismissed.contains(candidate.id) && !result.contains(candidate.id) {
                result.append(candidate.id)
            }
        }
        return Array(result.prefix(max(maxConcurrent, kept)))
    }

    /// Que faire de la Live Activity d'un match avec ce que l'appli vient de calculer (`latest`, nil s'il n'y a rien de
    /// neuf sur ce match). `latest` est d'abord remis dans l'ordre des équipes de la Live Activity (fixé au démarrage).
    /// - mode manuel et match pas épinglé : fin tout de suite (spec §6.4 « uniquement via le bouton du Détail ») ;
    /// - match terminé : contenu final, retrait 1 h plus tard (spec §6.3) ;
    /// - une donnée plus ancienne que celle affichée ne la remplace jamais ; à relecture égale, seul un changement
    ///   d'anti-spoiler (révélation, œil) est envoyé — un contenu recalculé avec moins d'informations (stats pas encore
    ///   rechargées après un relancement) n'efface pas ce qui est affiché ;
    /// - sinon, mise à jour.
    public static func decision(
        attributes: LiveMatchAttributes,
        current: LiveMatchState,
        latest: LiveActivityContent?,
        isPinned: Bool,
        mode: LiveActivityMode,
        now: Date
    ) -> LiveActivityUpdate {
        if mode == .manual && !isPinned { return .end(current, dismissAt: nil) }
        guard let latest else { return .keep }
        let state = latest.state.aligned(from: latest.teams, to: attributes)
        if state.phase == .finished { return .end(state, dismissAt: now.addingTimeInterval(finishedDisplay)) }
        if state.updatedAt < current.updatedAt { return .keep }
        if state.updatedAt == current.updatedAt && state.spoilerFree == current.spoilerFree { return .keep }
        return .update(state)
    }

    /// Prochain réveil en arrière-plan à demander (spec §6.4) : dans 15 min si un match d'une équipe suivie est en
    /// direct, ou si une Live Activity est à l'écran (pour la mettre à jour ou la terminer) ; sinon aucun.
    public static func nextBackgroundRefresh(now: Date, live: [MatchEvent]?, follows: FollowList,
                                             hasActivities: Bool) -> Date? {
        let followedLive = live?.contains { follows.involves($0.match.teams) } ?? false
        return followedLive || hasActivities ? now.addingTimeInterval(backgroundInterval) : nil
    }
}
```

- [ ] **Step 4 : `LiveActivityChoices`**

Créer `LoLKit/Sources/LoLKit/Live/LiveActivityChoices.swift` :

```swift
import Foundation

/// Choix de l'utilisateur sur les Live Activities (spec §6.4), enregistrés par l'appli dans `live-activities.json` :
/// - `pinned` : matchs épinglés depuis le Détail (prioritaires, gardés en mode manuel) ;
/// - `dismissed` : matchs dont la Live Activity a été retirée à la main — jamais recréée automatiquement ;
/// - `started` : matchs dont l'appli a démarré la Live Activity et qu'elle n'a pas terminée elle-même. Une Live Activity
///   de cette liste qui n'est plus en cours a été retirée par l'utilisateur (ou par iOS) pendant que l'appli dormait.
/// Épinglés et retirés restent disjoints : chaque opération enlève l'id de l'autre liste. Chaque marque est datée et
/// oubliée au bout de 24 h (un match ne dure jamais aussi longtemps).
public struct LiveActivityChoices: Codable, Sendable, Equatable {
    public static let retention: TimeInterval = 24 * 3600

    public private(set) var pinned: [String: Date]
    public private(set) var dismissed: [String: Date]
    public private(set) var started: [String: Date]

    public init(pinned: [String: Date] = [:], dismissed: [String: Date] = [:], started: [String: Date] = [:]) {
        self.pinned = pinned
        self.dismissed = dismissed
        self.started = started
    }

    private enum CodingKeys: String, CodingKey {
        case pinned, dismissed, started
    }

    /// Décodage tolérant : une liste absente ou illisible est vide, les autres sont gardées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinned = (try? container.decodeIfPresent([String: Date].self, forKey: .pinned)) ?? [:]
        dismissed = (try? container.decodeIfPresent([String: Date].self, forKey: .dismissed)) ?? [:]
        started = (try? container.decodeIfPresent([String: Date].self, forKey: .started)) ?? [:]
    }

    /// Épinglés, du plus ancien au plus récent (priorité de `LiveActivityPlanner.plan`).
    public var pinnedIds: [String] {
        pinned.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
    }

    public var dismissedIds: Set<String> {
        Set(dismissed.keys)
    }

    public func isPinned(_ matchId: String) -> Bool {
        pinned[matchId] != nil
    }

    /// « Épingler sur l'écran verrouillé » : prioritaire, et n'est plus « retiré ». Un match déjà épinglé garde sa place.
    public mutating func pin(_ matchId: String, now: Date) {
        dismissed[matchId] = nil
        if pinned[matchId] == nil {
            pinned[matchId] = now
        }
    }

    /// « Retirer de l'écran verrouillé », ou glissement sur l'écran verrouillé : plus épinglé, jamais recréé
    /// automatiquement.
    public mutating func dismiss(_ matchId: String, now: Date) {
        pinned[matchId] = nil
        started[matchId] = nil
        dismissed[matchId] = now
    }

    /// L'appli vient de démarrer la Live Activity de ce match.
    public mutating func markStarted(_ matchId: String, now: Date) {
        started[matchId] = now
    }

    /// L'appli termine elle-même cette Live Activity (match fini, mode manuel) : ce n'est pas un retrait à la main.
    public mutating func markEnded(_ matchId: String) {
        started[matchId] = nil
    }

    /// Les Live Activities démarrées par l'appli qui ne sont plus en cours (`running`) sans qu'elle les ait terminées
    /// ont été retirées à la main (ou par iOS) : elles passent dans `dismissed`.
    public mutating func reconcile(running: Set<String>, now: Date) {
        for matchId in Array(started.keys) where !running.contains(matchId) {
            dismiss(matchId, now: now)
        }
    }

    /// Sans les marques de plus de 24 h.
    public func pruned(now: Date) -> LiveActivityChoices {
        func fresh(_ marks: [String: Date]) -> [String: Date] {
            marks.filter { now.timeIntervalSince($0.value) <= Self.retention }
        }
        return LiveActivityChoices(pinned: fresh(pinned), dismissed: fresh(dismissed), started: fresh(started))
    }
}
```

- [ ] **Step 5 : Lancer les tests, vérifier qu'ils passent**

Run : `bash scripts/lolkit.sh test --filter "LiveActivityPlannerTests|LiveActivityDecisionTests|LiveActivityChoicesTests"`
Expected : PASS — les 5 tests d'origine du planner inchangés + 6 nouveaux, 8 de décision, 6 de choix.
Run : `bash scripts/lolkit.sh test` → Expected : aucun échec (total de la Task 1 + 20), aucun avertissement.

- [ ] **Step 6 : Commit, push, CI**

```bash
git add LoLKit/Sources/LoLKit/Live/LiveActivityPlanner.swift LoLKit/Sources/LoLKit/Live/LiveActivityChoices.swift LoLKit/Tests/LoLKitTests/LiveActivityPlannerTests.swift LoLKit/Tests/LoLKitTests/LiveActivityDecisionTests.swift LoLKit/Tests/LoLKitTests/LiveActivityChoicesTests.swift
git commit -m "feat(lolkit): décisions des Live Activities — places prises, mise à jour ou fin, choix de l'utilisateur, réveil en arrière-plan" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : LoLKit vert (Linux + macOS) ; iOS vert (rien ne change côté appli).

---

### Task 3 : Prérequis de l'étape 4 dans le store

`updatedAt` = dernière relecture réussie, contenu d'une Live Activity par match, couleurs d'équipe hors du cycle gardé, tâches d'action liées à la scène (points différés de l'étape 2).

**Files :**
- Modify : `App/Store/AppStore.swift` (propriété après `isRefreshing` ; `liveState`, `detailState`, `state` ; `poll` ; ligne des couleurs dans `cycle` ; `toggleFollow`, `setSpoilerFree`, `reveal`)
- Create : `App/Store/AppStore+LiveActivity.swift`
- Modify : `Tests/FailleTests/LogoPipelineTests.swift` (2 tests)
- Modify : `Tests/FailleTests/StoreRefreshTests.swift` (`aLogoThatKeepsFailingDoesNotBlockTheNextTeams`)
- Create : `Tests/FailleTests/StorePrerequisitesTests.swift`

**Interfaces :**
- Consumes : `LiveMatchBuilder.state(…, now:, updatedAt:)`, `LiveActivityContent(details:state:follows:)` (Task 1) ; dans `AppStore` : `live`, `schedule`, `follows`, `settings`, `lastSuccess`, `snapshots`, `snapshotDates`, `firstFrames`, `statsUnavailable`, `colorsDirty`, `isFailing`, `isPreview`, `isRefreshing`, `refreshDue(opening:)`, `refreshLiveStats()`, `updateTeamColors()` (privée), `event(id:)` ; `LiveMatchState.displayed(for: MatchEvent?)` (`App/Matches/MatchParts.swift`) ; `EventDetails(event:)`, `MatchEvent.statsDisabled`, `EventState.completed` ; tests : `AppStore(preview:)`, `PreviewData.standard`, `SampleData.kcMatchId / .t1MatchId / .date(_:)`, `ScriptedTransport(mode:delay:extra:failure:)`, `ScriptedTransport.requests`, `StubTransport(failing:)`, `TemporaryFiles.store()`, `Team(id:slug:name:code:image:status:homeLeague:)`, `RGB.accent`.
- Produces :
  - `func state(details: EventDetails, statsDisabled: Bool, updatedAt: Date?) -> LiveMatchState` (interne, n'est plus `private`)
  - `func activityContent(matchId: String) -> LiveActivityContent?` (extension, `AppStore+LiveActivity.swift`)
  - `func updateColorsIfNeeded() async` ; `func runWithScene(_ work: @escaping @MainActor @Sendable () async -> Void)` ; `func endScene()` ; `var sceneTaskCount: Int`
  - `poll()` : deux boucles enfants (données, couleurs) puis `endScene()`

- [ ] **Step 1 : Écrire les tests (ils échouent à la compilation)**

Créer `Tests/FailleTests/StorePrerequisitesTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Attend (5 s au plus) qu'une requête soit partie ; sinon enregistre un échec au lieu de bloquer le test.
private func waitForRequest(_ transport: ScriptedTransport) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while await transport.requests.isEmpty {
        if ContinuousClock.now >= deadline {
            Issue.record("aucune requête n'est partie après 5 s")
            return false
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// Une tâche d'action a-t-elle vu son annulation ? (nil tant qu'elle n'a pas fini)
@MainActor
private final class CancellationProbe {
    var cancelled: Bool?
}

/// Prérequis de l'étape 4 dans le store : contenu des Live Activities daté de la dernière relecture réussie, couleurs
/// d'équipe hors du cycle gardé, tâches des actions liées à la scène.
@MainActor
@Suite(.serialized)
struct StorePrerequisitesTests {
    /// `lastUpdate` de `PreviewData.standard` : dernière relecture réussie du direct et du calendrier.
    private let lastRefresh = SampleData.date("2026-10-15T15:05:00Z")

    // MARK: Contenu des Live Activities

    @Test func activityContentIsDatedFromTheLastGoodRefreshNotFromTheClockAnchor() throws {
        let content = try #require(AppStore(preview: .standard).activityContent(matchId: SampleData.kcMatchId))
        #expect(content.attributes?.teams.map(\.code) == ["KC", "C9"])
        #expect(content.attributes?.primaryTeamIndex == 0)
        #expect(content.state.phase == .inGame)
        #expect(content.state.updatedAt == lastRefresh)
        #expect(content.state.staleDate == lastRefresh.addingTimeInterval(LiveMatchState.staleAfter))
        // Le chrono reste ancré sur la réception de la frame (18:42 de jeu « maintenant »), pas sur `updatedAt`.
        let start = try #require(content.state.gameClockStart)
        #expect(abs(start.timeIntervalSinceNow + 1122) < 60)
    }

    @Test func activityContentAppliesTheSpoilerPolicy() throws {
        let content = try #require(AppStore(preview: .standard).activityContent(matchId: SampleData.t1MatchId))
        #expect(content.state.spoilerFree)
        #expect(content.state.seriesScore == nil)
        #expect(content.state.stats == nil)
    }

    @Test func aMatchOutOfTheLiveIsFinishedOnlyWhenTheScheduleSaysSo() throws {
        let store = AppStore(preview: .standard)
        let finished = try #require(store.activityContent(matchId: "m-gen-hle"))
        #expect(finished.state.phase == .finished)
        #expect(finished.state.winnerCode == "GEN")
        #expect(finished.attributes == nil)                  // le calendrier ne donne pas d'id d'équipe
        #expect(finished.state.updatedAt == lastRefresh)
        #expect(store.activityContent(matchId: "m-gen-fur") == nil)   // à venir : rien de neuf pour une Live Activity
        #expect(store.activityContent(matchId: "inconnu") == nil)
    }

    // MARK: Couleurs d'équipe hors du cycle gardé

    @Test func logosAreFetchedOutsideTheRefreshCycle() async {
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp",
                         image: "http://static.lolesports.com/teams/kc-test.png", homeLeagueName: "LEC"),
        ]), to: .follows)
        let transport = ScriptedTransport()
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        #expect(await transport.requests.filter { $0.absoluteString.hasSuffix("kc-test.png") }.isEmpty)

        await store.updateColorsIfNeeded()
        #expect(await transport.requests.filter { $0.absoluteString.hasSuffix("kc-test.png") }.count == 1)
        #expect(store.follows.team(id: "kc")?.autoColorHex == RGB.accent.hex)   // 404 sur le logo : accent
    }

    // MARK: Tâches des actions liées à la scène

    @Test func actionTasksEndWithTheForegroundLoop() async {
        let transport = ScriptedTransport(delay: .seconds(30))
        let store = AppStore(transport: transport, files: TemporaryFiles.store())
        let loop = Task { await store.poll() }
        guard await waitForRequest(transport) else {
            loop.cancel()
            await loop.value
            return
        }
        let g2 = Team(id: "g2", slug: "g2", name: "G2 Esports", code: "G2", image: nil, status: "active", homeLeague: nil)
        store.toggleFollow(g2)               // son rafraîchissement attend la fin du cycle en cours
        #expect(store.sceneTaskCount == 1)
        loop.cancel()                        // la scène quitte le premier plan
        await loop.value
        #expect(store.sceneTaskCount == 0)
    }

    @Test func endingTheSceneCancelsItsActionTasks() async {
        let store = AppStore(transport: StubTransport(failing: true), files: TemporaryFiles.store())
        let probe = CancellationProbe()
        store.runWithScene {
            try? await Task.sleep(for: .seconds(30))
            probe.cancelled = Task.isCancelled
        }
        #expect(store.sceneTaskCount == 1)
        store.endScene()
        #expect(store.sceneTaskCount == 0)
        let deadline = ContinuousClock.now + .seconds(5)
        while probe.cancelled == nil && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(probe.cancelled == true)
    }
}
```

- [ ] **Step 2 : `AppStore` — `updatedAt` distinct et `state` interne**

Dans `App/Store/AppStore.swift`, remplacer :

```swift
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
```

par :

```swift
    /// État d'un match en direct pour sa carte : anti-spoiler, phase, score, chrono et stats viennent de LoLKit.
    func liveState(for event: MatchEvent) -> LiveMatchState {
        state(details: EventDetails(event: event), statsDisabled: event.statsDisabled, updatedAt: lastSuccess[.live])
    }

    /// Même chose depuis `getEventDetails` (écran Détail) ; nil tant que les détails ne sont pas chargés.
    func detailState(matchId: String) -> LiveMatchState? {
        guard let loaded = self.details[matchId] else { return nil }
        return state(details: loaded, statsDisabled: loaded.statsDisabled || event(id: matchId)?.statsDisabled == true,
                     updatedAt: lastSuccess[.live])
    }

    /// État d'un match par LoLKit. Deux heures distinctes (spec §4.3) : l'heure de réception de la frame, ancre du
    /// chrono ; et `updatedAt`, dernière relecture réussie de la donnée (le direct, ou le calendrier), dont découle
    /// `staleDate` (nil : l'heure du calcul).
    func state(details: EventDetails, statsDisabled: Bool, updatedAt: Date?) -> LiveMatchState {
```

puis, dans le corps de cette même fonction, remplacer :

```swift
            // Heure de réception de la frame : le chrono démarre au bon endroit et tourne ensuite tout seul.
            now: game.flatMap { snapshotDates[$0.id] } ?? Date()
        )
```

par :

```swift
            // Heure de réception de la frame : le chrono démarre au bon endroit et tourne ensuite tout seul.
            now: game.flatMap { snapshotDates[$0.id] } ?? Date(),
            updatedAt: updatedAt
        )
```

- [ ] **Step 3 : `AppStore` — boucle du premier plan, couleurs, tâches de la scène**

(a) Juste après la ligne `    @ObservationIgnored private var isRefreshing = false`, ajouter :

```swift
    /// Tâches lancées par une action de l'utilisateur (suivre, masquer, révéler, épingler…) : elles vivent avec la scène
    /// et sont annulées quand la boucle du premier plan s'arrête (`endScene`), au lieu de continuer en arrière-plan.
    @ObservationIgnored private var sceneTasks: [UUID: Task<Void, Never>] = [:]
```

(b) Remplacer :

```swift
    /// Boucle du premier plan, lancée par `.task(id: scenePhase)` : s'arrête, requêtes comprises, quand la tâche est annulée.
    func poll() async {
        var opening = true
        while !Task.isCancelled {
            await refreshDue(opening: opening)
            opening = false
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        }
    }
```

par :

```swift
    /// Boucle du premier plan, lancée par `.task(id: scenePhase)` : s'arrête, requêtes comprises, quand la tâche est
    /// annulée. Deux boucles en parallèle : les données de l'API, et les couleurs tirées des logos — hors du cycle gardé
    /// par `isRefreshing`, un hôte de logos lent ne retient plus aucun rafraîchissement. Quand la scène quitte le premier
    /// plan, les tâches lancées par les actions de l'utilisateur s'arrêtent avec elle.
    func poll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshLoop() }
            group.addTask { await self.colorLoop() }
        }
        endScene()
    }

    private func refreshLoop() async {
        var opening = true
        while !Task.isCancelled {
            await refreshDue(opening: opening)
            opening = false
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        }
    }

    /// Un tour d'attente d'abord : le premier cycle a alors dit si l'API répond (`isFailing`).
    private func colorLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
            await updateColorsIfNeeded()
        }
    }

    /// Couleurs d'équipe à (re)calculer depuis les logos (spec §9) : au premier plan seulement, jamais pendant un réveil
    /// en arrière-plan (le temps accordé par iOS est compté), jamais quand l'API est en panne.
    func updateColorsIfNeeded() async {
        guard !isPreview, colorsDirty, !isFailing, !Task.isCancelled else { return }
        await updateTeamColors()
    }

    /// Lance le travail d'une action de l'utilisateur, lié à la scène (annulé par `endScene`).
    func runWithScene(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let id = UUID()
        sceneTasks[id] = Task {
            await work()
            self.sceneTasks[id] = nil
        }
    }

    /// La scène quitte le premier plan : les tâches des actions s'arrêtent.
    func endScene() {
        for task in sceneTasks.values {
            task.cancel()
        }
        sceneTasks.removeAll()
    }

    /// Tâches d'action en cours (tests).
    var sceneTaskCount: Int {
        sceneTasks.count
    }
```

(c) Dans `cycle(opening:pullToRefresh:)`, supprimer la ligne :

```swift
        if colorsDirty && !isFailing && !Task.isCancelled { await updateTeamColors() }
```

(d) Dans `toggleFollow(_:)`, remplacer :

```swift
        Task { await refreshDue(opening: false) }
```

par :

```swift
        runWithScene { await self.refreshDue(opening: false) }
```

(e) Dans `setSpoilerFree(_:id:)`, remplacer :

```swift
        follows.setSpoilerFree(on, id: id)
        saveFollows()
        Task { await refreshLiveStats() }
```

par :

```swift
        follows.setSpoilerFree(on, id: id)
        saveFollows()
        runWithScene { await self.refreshLiveStats() }
```

(f) Dans `reveal(matchId:)`, remplacer :

```swift
        settings.revealedMatchIds.insert(matchId)
        saveSettings()
        Task { await refreshLiveStats() }
```

par :

```swift
        settings.revealedMatchIds.insert(matchId)
        saveSettings()
        runWithScene { await self.refreshLiveStats() }
```

Vérifier : `grep -n "Task {" App/Store/AppStore.swift` → Expected : une seule ligne, celle de `runWithScene`.

- [ ] **Step 4 : Contenu d'une Live Activity par match**

Créer `App/Store/AppStore+LiveActivity.swift` :

```swift
import Foundation
import LoLKit

// MARK: - Contenu des Live Activities (étape 4, Task 3)

extension AppStore {
    /// Contenu de la Live Activity d'un match (spec §4.3, §6) : attributs (pour la démarrer) et état, anti-spoiler
    /// compris. `updatedAt` est la dernière relecture réussie de la donnée qui le nourrit : le direct, ou, pour un match
    /// sorti du direct, le calendrier — jamais l'heure de réception de la frame, qui reste l'ancre du chrono.
    /// Un match que l'API dit terminé est « terminé » même sans série gagnée (`displayed(for:)` : forfait, Bo2).
    /// - Returns: nil s'il n'y a rien de neuf sur ce match (ni dans le direct, ni terminé au calendrier) : la Live
    ///   Activity garde alors son contenu et passe « pas fraîche » d'elle-même.
    func activityContent(matchId: String) -> LiveActivityContent? {
        if let event = live?.first(where: { $0.id == matchId }) {
            let details = EventDetails(event: event)
            let built = self.state(details: details, statsDisabled: event.statsDisabled, updatedAt: lastSuccess[.live])
            return LiveActivityContent(details: details, state: built.displayed(for: event), follows: follows)
        }
        // Sorti du direct : le calendrier, relu aussitôt (spec §10), dit s'il est terminé ; sinon on attend.
        guard let event = schedule.first(where: { $0.id == matchId }), event.state == .completed else { return nil }
        let details = EventDetails(event: event)
        let built = self.state(details: details, statsDisabled: event.statsDisabled, updatedAt: lastSuccess[.schedule])
        return LiveActivityContent(details: details, state: built.displayed(for: event), follows: follows)
    }
}
```

- [ ] **Step 5 : Les tests des couleurs appellent la passe des couleurs**

Dans `Tests/FailleTests/LogoPipelineTests.swift` :

(a) dans `logoIsDownloadedOverHttpsKeptUnderTheRawName`, remplacer :

```swift
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)

```

par :

```swift
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        await store.updateColorsIfNeeded()   // la passe des couleurs vit hors du cycle (étape 4)

```

puis remplacer :

```swift
        await store.refreshDue(opening: false)
        #expect(await transport.requests.map(\.absoluteString).filter { $0 == secure }.count == 1)
```

par :

```swift
        await store.refreshDue(opening: false)
        await store.updateColorsIfNeeded()
        #expect(await transport.requests.map(\.absoluteString).filter { $0 == secure }.count == 1)
```

(b) dans `missingLogoFallsBackToTheAccentColor`, remplacer :

```swift
        let store = AppStore(transport: ScriptedTransport(), files: files) // 404 sur les logos
        await store.refreshDue(opening: true)
```

par :

```swift
        let store = AppStore(transport: ScriptedTransport(), files: files) // 404 sur les logos
        await store.refreshDue(opening: true)
        await store.updateColorsIfNeeded()
```

Dans `Tests/FailleTests/StoreRefreshTests.swift`, test `aLogoThatKeepsFailingDoesNotBlockTheNextTeams`, remplacer :

```swift
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        #expect(store.follows.team(id: "a")?.autoColorHex == nil) // en échec : réessayé plus tard
```

par :

```swift
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        await store.updateColorsIfNeeded()   // la passe des couleurs vit hors du cycle (étape 4)
        #expect(store.follows.team(id: "a")?.autoColorHex == nil) // en échec : réessayé plus tard
```

puis remplacer :

```swift
        await store.refreshDue(opening: false)
        let brokenRequests = await transport.requests.filter { $0.absoluteString.contains("broken.png") }
```

par :

```swift
        await store.refreshDue(opening: false)
        await store.updateColorsIfNeeded()
        let brokenRequests = await transport.requests.filter { $0.absoluteString.contains("broken.png") }
```

- [ ] **Step 6 : Commit, push, CI**

```bash
git add App/Store/AppStore.swift App/Store/AppStore+LiveActivity.swift Tests/FailleTests/StorePrerequisitesTests.swift Tests/FailleTests/LogoPipelineTests.swift Tests/FailleTests/StoreRefreshTests.swift
git commit -m "refactor(app): prérequis de l'étape 4 — updatedAt = dernière relecture réussie, logos hors du cycle gardé, actions liées à la scène" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : `build` et `apercus` verts ; les 6 tests de `StorePrerequisitesTests` verts ; `LogoPipelineTests`, `StoreRefreshTests` (dont `cancellingThePollLoopEndsCleanly`, `pullToRefreshWaitsForTheRunningCycleThenRunsItsOwn`) et `WidgetDataTests` (étape 3) toujours verts. Erreurs probables et replis :
- « reference to captured var / sending 'self' » sur `group.addTask` : `self` est un `@MainActor` (donc Sendable) — vérifier que l'appel est bien `await self.refreshLoop()` ; si le compilateur refuse encore, remplacer le groupe par `async let refreshing: Void = refreshLoop()` et `async let coloring: Void = colorLoop()` suivis de `_ = await (refreshing, coloring)`.
- « variable used within its own initial value » : les variables locales de `activityContent` s'appellent `built`, jamais `state`.
- `actionTasksEndWithTheForegroundLoop` voit 0 tâche juste après `toggleFollow` : la tâche d'action a été enregistrée sous un autre nom — `runWithScene` doit stocker la `Task` avant tout `await`.

---

### Task 4 : Vues de la Live Activity et de la Dynamic Island, aperçus PNG

Conformité `ActivityAttributes` du contrat et vues SwiftUI simples dans `Shared/LiveActivity/` (compilées dans l'appli et l'extension), rendues en PNG dans les tests hébergés.

**Files :**
- Create : `Shared/LiveActivity/LiveMatchAttributes+Activity.swift`
- Create : `Shared/LiveActivity/LiveActivityViews.swift`
- Create : `Shared/LiveActivity/IslandViews.swift`
- Create : `Shared/Preview/LiveActivitySamples.swift`
- Modify : `Shared/DA/Icon.swift` (`case … off` → `… off, pause`)
- Modify : `scripts/icones.sh` (une ligne) ; généré : `Resources/Assets.xcassets/icon-pause.imageset/Contents.json`, `icon-pause.svg`
- Modify : `Tests/FailleTests/ApercuTests.swift` (21 → 22 icônes)
- Create : `Tests/FailleTests/Support/LiveActivityBoard.swift`
- Create : `Tests/FailleTests/LiveActivitySnapshotTests.swift`

**Interfaces :**
- Consumes : `LiveActivityDisplay` et ses types (Task 1) ; `LiveMatchAttributes`, `LiveMatchState`, `TeamStats` ; `Format.score(_:)` ; `Palette.abyss / text / secondary / accent / team(_:)`, `Sora.font(_:_:)`, `IconView(icon:size:)`, `Icon` (`.live`, `.trophy`, `.check`, `.refresh`, `.clock`, `.eyeOff`, `.off`, `.swords`, `.gold`, `.tower`, `.drake`, `.baron`) ; `MonogramBadge(code: String, tint: Color? = nil, size: CGFloat = 26)` (étape 3, `Shared/Widgets/WidgetChrome.swift`) ; `SampleData.kcMatchId / .t1MatchId` ; tests : `WidgetRender.write(_:size:named:)`, `WidgetRender.inkRatio(_:size:)`, `WidgetSize.screen`, `BoardWallpaper`, `BoardCaption(text:)` (étape 3, `Tests/FailleTests/Support/WidgetBoard.swift`), `ApercuTests.expectNotBlank(_:)`.
- Produces :
  - `extension LiveMatchAttributes: @retroactive ActivityAttributes { public typealias ContentState = LiveMatchState }`
  - `Icon.pause`
  - vues : `LiveActivityBackdrop(tintHex:)`, `LiveActivityLockView(display:)`, `LiveActivityStatusView(status:prefix:)`, `LiveActivityScoreRow(display:)`, `LiveActivityStatRows(rows:teams:)`, `LiveActivityMessageView(message:)`, `IslandCompactView(display:side:)`, `IslandMinimalView(display:)`, `IslandTeamView(side:)`, `IslandCenterView(display:)`, `IslandBottomView(display:)` ; `LiveActivityDisplay.Stat.icon`, `LiveActivityDisplay.Message.icon`
  - `LiveActivitySamples.kc / .t1 / .kcb` (attributs) et `.inGame / .clockStopped / .masked / .stale / .betweenGames / .finished / .statsUnavailable` (`LiveActivityDisplay`)
  - tests : `LiveBoardState(caption:display:)`, `LiveBoardState.lockScreen / .island`, `LiveActivityBoard(states:)` (`LiveActivityBoard.size`), `DynamicIslandBoard(states:)`, `LiveActivityRender.height(_:width:)` ; PNG `11-live-activity.png`, `12-dynamic-island.png`

- [ ] **Step 1 : Lire les produits de l'étape 3**

Lire `Shared/Widgets/WidgetChrome.swift` et `Tests/FailleTests/Support/WidgetBoard.swift`. Expected : `MonogramBadge(code:tint:size:)`, `WidgetRender.write(_:size:named:) throws -> URL`, `WidgetRender.inkRatio(_:size:) -> Double`, `WidgetSize.screen`, `BoardWallpaper`, `BoardCaption(text:)` existent avec ces signatures. Si un nom ou un libellé diffère, utiliser le nom réel partout dans cette tâche et le noter dans le rapport.

- [ ] **Step 2 : Icône « pause » (entre deux games, maquette ②)**

Dans `scripts/icones.sh`, ajouter juste après la ligne `icon off      "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M6 6l12 12\"/>"` :

```bash
icon pause    "<circle $S cx=\"12\" cy=\"12\" r=\"9\"/><path $S d=\"M10 9v6M14 9v6\"/>"
```

Run : `bash scripts/icones.sh` → Expected : `Catalogue généré : 22 icônes`.
Run : `git status --short Resources scripts` → Expected : ` M scripts/icones.sh` et `?? Resources/Assets.xcassets/icon-pause.imageset/` seulement (si d'autres fichiers du catalogue apparaissent modifiés, les remettre par `git checkout -- <fichier>`).

Dans `Shared/DA/Icon.swift`, remplacer :

```swift
    case trophy, settings, search, back, arrow, pin, check, refresh, off
```

par :

```swift
    case trophy, settings, search, back, arrow, pin, check, refresh, off, pause
```

Dans `Tests/FailleTests/ApercuTests.swift`, remplacer :

```swift
        #expect(Icon.allCases.count == 21)
```

par :

```swift
        #expect(Icon.allCases.count == 22)
```

- [ ] **Step 3 : Conformité ActivityKit du contrat**

Créer `Shared/LiveActivity/LiveMatchAttributes+Activity.swift` :

```swift
import ActivityKit
import LoLKit

/// Conformité ActivityKit du contrat de la Live Activity (spec §4.3) : l'état d'une Live Activity est exactement
/// `LiveMatchState`, pour que le JSON des push de la phase 2 soit celui de la fixture `live_contract.json`.
/// Compilée dans l'appli (qui démarre et met à jour) et dans l'extension (qui affiche).
extension LiveMatchAttributes: @retroactive ActivityAttributes {
    public typealias ContentState = LiveMatchState
}
```

- [ ] **Step 4 : Vues de l'écran verrouillé**

Créer `Shared/LiveActivity/LiveActivityViews.swift` :

```swift
import LoLKit
import SwiftUI

// MARK: - Écran verrouillé (spec §6.1, §6.3, maquettes ① et ②)

/// Fond de la Live Activity : dégradé à 160° de la couleur de l'équipe suivie vers l'abysse ; verre neutre si aucune
/// équipe du match n'est suivie (match épinglé à la main). Un dégradé seulement : pas de matière dans une Live Activity.
struct LiveActivityBackdrop: View {
    let tintHex: String?

    var body: some View {
        let top = tintHex.map { Palette.team($0).opacity(0.34) } ?? Color.white.opacity(0.08)
        ZStack {
            Palette.abyss
            LinearGradient(
                stops: [.init(color: top, location: 0), .init(color: Palette.abyss.opacity(0.86), location: 0.7)],
                startPoint: UnitPoint(x: 0.33, y: 0),
                endPoint: UnitPoint(x: 0.67, y: 1)
            )
        }
    }
}

/// La Live Activity de l'écran verrouillé : « LIGUE · Bo5 · Game N » et chrono, score entre les deux monogrammes,
/// 5 lignes de stats ou un message. iOS tronque au-delà de 160 pt de haut : vérifié par les tests hébergés.
struct LiveActivityLockView: View {
    let display: LiveActivityDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(display.header)
                    .font(Sora.font(9.5, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                LiveActivityStatusView(status: display.status)
                    .font(Sora.font(11.5, .semibold))
            }
            LiveActivityScoreRow(display: display)
            if !display.rows.isEmpty {
                LiveActivityStatRows(rows: display.rows, teams: display.teams)
                    .opacity(display.faded ? 0.55 : 1)
            }
            if let message = display.message {
                LiveActivityMessageView(message: message)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiveActivityBackdrop(tintHex: display.tintHex))
    }
}

/// Droite de l'en-tête : chrono natif (il tourne sans mise à jour), chrono figé, « En direct », « entre deux games »,
/// « Victoire KC », « Terminé », ou « màj il y a X min » quand la Live Activity n'est plus fraîche (spec §6.3).
struct LiveActivityStatusView: View {
    let status: LiveActivityDisplay.Status
    /// « Game 2 · » devant le chrono (Dynamic Island déployée).
    var prefix: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            IconView(icon: icon, size: 12)
            switch status {
            case let .clock(.running(since)):
                if let prefix {
                    Text(prefix)
                }
                // Largeur fixe : un minuteur natif occupe sinon toute la place disponible.
                Text(since, style: .timer)
                    .monospacedDigit()
                    .frame(width: 52, alignment: .leading)
            case let .clock(.stopped(text)):
                if let prefix {
                    Text(prefix)
                }
                Text(text)
                    .monospacedDigit()
            case let .stale(since):
                Text("\(status.label ?? "") ")
                Text(since, style: .relative)
            default:
                Text(status.label ?? "")
            }
        }
        .lineLimit(1)
        .foregroundStyle(isStale ? Palette.secondary : Palette.text)
    }

    private var isStale: Bool {
        if case .stale = status { return true }
        return false
    }

    /// La nature d'une info se lit à son icône (spec §9).
    private var icon: Icon {
        switch status {
        case .clock, .live: return .live
        case .betweenGames: return .pause
        case .victory: return .trophy
        case .finished: return .check
        case .stale: return .refresh
        }
    }
}

/// « [KC] KC   1 – 0   C9 [C9] » ; « vs » sans score (masqué).
struct LiveActivityScoreRow: View {
    let display: LiveActivityDisplay

    var body: some View {
        HStack(spacing: 7) {
            if let left = display.teams.first {
                MonogramBadge(code: left.code, tint: left.colorHex.map(Palette.team), size: 24)
                Text(left.code)
                    .font(Sora.font(15, .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if let score = display.score, score.count == 2 {
                Text(Format.score(score))
                    .font(Sora.font(22, .bold))
                    .monospacedDigit()
            } else {
                Text("vs")
                    .font(Sora.font(12, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 6)
            if display.teams.count > 1 {
                Text(display.teams[1].code)
                    .font(Sora.font(15, .semibold))
                    .lineLimit(1)
                MonogramBadge(code: display.teams[1].code, tint: display.teams[1].colorHex.map(Palette.team), size: 24)
            }
        }
    }
}

/// Les 5 lignes de stats (spec §6.1) : « 7 · ⚔ KILLS · 4 » ; l'écart de gold à la couleur de l'équipe qui mène.
struct LiveActivityStatRows: View {
    let rows: [LiveActivityDisplay.Row]
    let teams: [LiveActivityDisplay.Side]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 1) {
            ForEach(rows, id: \.stat) { row in
                GridRow {
                    HStack(spacing: 4) {
                        Text(row.left)
                        if row.leader == 0, let lead = row.lead {
                            leadText(lead, leader: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        IconView(icon: row.stat.icon, size: 11)
                        Text(row.stat.label)
                            .font(Sora.font(8.5, .semibold))
                            .tracking(0.7)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Palette.secondary)
                    .frame(minWidth: 84)
                    HStack(spacing: 4) {
                        if row.leader == 1, let lead = row.lead {
                            leadText(lead, leader: 1)
                        }
                        Text(row.right)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(Sora.font(11.5, .bold))
        .monospacedDigit()
    }

    private func leadText(_ text: String, leader: Int) -> some View {
        let color = teams.indices.contains(leader) ? teams[leader].colorHex.map(Palette.team) : nil
        return Text(text)
            .font(Sora.font(9, .semibold))
            .foregroundStyle(color ?? Palette.secondary)
    }
}

/// Message sous le score (spec §6.3, §8) : anti-spoiler, prochaine game, stats indisponibles, fin de match.
struct LiveActivityMessageView: View {
    let message: LiveActivityDisplay.Message

    var body: some View {
        HStack(spacing: 5) {
            if let icon = message.icon {
                IconView(icon: icon, size: 12)
            }
            Text(message.text)
            if let accent = message.accent {
                Text(accent)
                    .font(Sora.font(11, .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .font(Sora.font(11, .regular))
        .foregroundStyle(Palette.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }
}

extension LiveActivityDisplay.Stat {
    /// Icône de chaque stat (spec §9 : kills = épées, gold = pièces, tour, drake = flamme, baron = hexagone).
    var icon: Icon {
        switch self {
        case .kills: return .swords
        case .gold: return .gold
        case .towers: return .tower
        case .drakes: return .drake
        case .barons: return .baron
        }
    }
}

extension LiveActivityDisplay.Message {
    var icon: Icon? {
        switch self {
        case .masked: return .eyeOff
        case .nextGame: return .clock
        case .statsUnavailable: return .off
        case .statsPending: return .refresh
        case .leavingSoon: return nil
        }
    }
}
```

- [ ] **Step 5 : Vues de la Dynamic Island**

Créer `Shared/LiveActivity/IslandViews.swift` :

```swift
import LoLKit
import SwiftUI

// MARK: - Dynamic Island (spec §6.2, maquette ①)

/// Compacte : un côté de la caméra — monogramme et victoires ; masqué : le monogramme seul.
struct IslandCompactView: View {
    let display: LiveActivityDisplay
    /// 0 : à gauche de la caméra ; 1 : à droite.
    let side: Int

    var body: some View {
        let team = display.teams.indices.contains(side) ? display.teams[side] : nil
        let wins = display.score.flatMap { $0.indices.contains(side) ? $0[side] : nil }
        HStack(spacing: 5) {
            if side == 1, let wins {
                Text("\(wins)")
            }
            if let team {
                MonogramBadge(code: team.code, tint: team.colorHex.map(Palette.team), size: 20)
            }
            if side == 0, let wins {
                Text("\(wins)")
            }
        }
        .font(Sora.font(14, .bold))
        .monospacedDigit()
        .foregroundStyle(Color.white)
    }
}

/// Minimale : code de l'équipe suivie et score ; masqué : son monogramme seul.
struct IslandMinimalView: View {
    let display: LiveActivityDisplay

    var body: some View {
        if let team = display.teams.first {
            if let score = display.compactScore {
                VStack(spacing: 0) {
                    Text(team.code)
                        .font(Sora.font(8, .bold))
                        .foregroundStyle(team.colorHex.map(Palette.team) ?? Color.white)
                    Text(score)
                        .font(Sora.font(11, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                MonogramBadge(code: team.code, tint: team.colorHex.map(Palette.team), size: 22)
            }
        }
    }
}

/// Déployée, à gauche et à droite : monogramme et code d'une équipe.
struct IslandTeamView: View {
    let side: LiveActivityDisplay.Side?

    var body: some View {
        if let side {
            VStack(spacing: 3) {
                MonogramBadge(code: side.code, tint: side.colorHex.map(Palette.team), size: 30)
                Text(side.code)
                    .font(Sora.font(11, .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white)
            }
        }
    }
}

/// Déployée, au centre : score (« vs » si masqué) et « Game 2 · 18:42 », ou l'état.
struct IslandCenterView: View {
    let display: LiveActivityDisplay

    var body: some View {
        VStack(spacing: 4) {
            if let score = display.score, score.count == 2 {
                Text(Format.score(score))
                    .font(Sora.font(26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            } else {
                Text("vs")
                    .font(Sora.font(15, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            LiveActivityStatusView(status: display.status, prefix: display.gameNumber.map { "Game \($0) · " })
                .font(Sora.font(10, .semibold))
        }
    }
}

/// Déployée, en bas : les 5 stats sur une ligne (« 7–4 », « +2,1k »…), ou le message.
struct IslandBottomView: View {
    let display: LiveActivityDisplay

    var body: some View {
        if display.rows.isEmpty {
            if let message = display.message {
                LiveActivityMessageView(message: message)
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(display.rows.enumerated()), id: \.element.stat) { index, row in
                    if index > 0 {
                        Spacer(minLength: 4)
                    }
                    HStack(spacing: 3) {
                        IconView(icon: row.stat.icon, size: 11)
                            .foregroundStyle(Palette.secondary)
                        Text(row.compact)
                            .foregroundStyle(color(of: row))
                    }
                }
            }
            .font(Sora.font(11, .semibold))
            .monospacedDigit()
            .opacity(display.faded ? 0.55 : 1)
        }
    }

    /// L'écart de gold à la couleur de l'équipe qui mène (si elle est suivie), le reste en blanc.
    private func color(of row: LiveActivityDisplay.Row) -> Color {
        guard let leader = row.leader, display.teams.indices.contains(leader) else { return Color.white }
        return display.teams[leader].colorHex.map(Palette.team) ?? Color.white
    }
}
```

- [ ] **Step 6 : Exemples (un par état)**

Créer `Shared/Preview/LiveActivitySamples.swift` :

```swift
import Foundation
import LoLKit

/// Live Activities d'exemple (aperçus PNG, #Preview), une par état de la spec §6.3, comme les maquettes ① et ②.
/// Les dates partent de l'heure du rendu : le chrono affiche « 18:42 » et « màj il y a 9 min » au moment de la capture.
enum LiveActivitySamples {
    /// KC (suivie) contre C9, Mondial Bo5.
    static let kc = LiveMatchAttributes(
        matchId: SampleData.kcMatchId, leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "kc", code: "KC", name: "Karmine Corp", colorHex: "#5B8CFF"),
                .init(id: "c9", code: "C9", name: "Cloud9 Kia", colorHex: nil)],
        primaryTeamIndex: 0)

    /// T1 (suivie, en anti-spoiler) contre FLY.
    static let t1 = LiveMatchAttributes(
        matchId: SampleData.t1MatchId, leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "t1", code: "T1", name: "T1", colorHex: "#FF5C7A"),
                .init(id: "fly", code: "FLY", name: "FlyQuest", colorHex: nil)],
        primaryTeamIndex: 0)

    /// Match épinglé à la main, aucune équipe suivie : verre neutre.
    static let kcb = LiveMatchAttributes(
        matchId: "m-kcb-sly", leagueName: "LFL", bestOf: 3,
        teams: [.init(id: "kcb", code: "KCB", name: "Karmine Corp Blue", colorHex: nil),
                .init(id: "sly", code: "SLY", name: "Solary", colorHex: nil)],
        primaryTeamIndex: nil)

    static let stats = [
        TeamStats(kills: 7, gold: 32_400, towers: 3, inhibitors: 0, barons: 0, dragons: ["infernal", "ocean"]),
        TeamStats(kills: 4, gold: 30_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
    ]

    private static func state(_ phase: LiveMatchState.Phase, score: [Int]?, game: Int?, clockStart: Date? = nil,
                              stoppedAt: Date? = nil, stats: [TeamStats]? = nil, statsAvailable: Bool = true,
                              winner: String? = nil, updatedAt: Date = Date()) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: score, gameNumber: game, gameClockStart: clockStart,
                       gameClockStoppedAt: stoppedAt, stats: stats, statsAvailable: statsAvailable,
                       spoilerFree: false, winnerCode: winner, updatedAt: updatedAt)
    }

    /// Maquette ① : KC 1 – 0 C9, game 2, chrono à 18:42, stats.
    static var inGame: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc,
                            state: state(.inGame, score: [1, 0], game: 2,
                                         clockStart: Date().addingTimeInterval(-1122), stats: stats),
                            isStale: false)
    }

    /// Game en pause dans le flux : le chrono est figé.
    static var clockStopped: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc,
                            state: state(.inGame, score: [1, 1], game: 3, clockStart: Date().addingTimeInterval(-1500),
                                         stoppedAt: Date().addingTimeInterval(-30), stats: stats),
                            isStale: false)
    }

    /// T1 en anti-spoiler : ni score, ni game, ni stats.
    static var masked: LiveActivityDisplay {
        LiveActivityDisplay(attributes: t1,
                            state: state(.inGame, score: [1, 0], game: 2, clockStart: Date().addingTimeInterval(-600),
                                         stats: stats).masked(),
                            isStale: false)
    }

    /// Pas fraîche : dernière relecture il y a 9 min, stats pâlies.
    static var stale: LiveActivityDisplay {
        let older = [
            TeamStats(kills: 5, gold: 24_100, towers: 2, inhibitors: 0, barons: 0, dragons: ["infernal"]),
            TeamStats(kills: 4, gold: 23_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        ]
        return LiveActivityDisplay(attributes: kc,
                                   state: state(.inGame, score: [1, 0], game: 2,
                                                clockStart: Date().addingTimeInterval(-1500), stats: older,
                                                updatedAt: Date().addingTimeInterval(-540)),
                                   isStale: true)
    }

    /// KC 2 – 0, la game 3 va commencer.
    static var betweenGames: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc, state: state(.betweenGames, score: [2, 0], game: 3), isStale: false)
    }

    /// Victoire KC 3 – 1.
    static var finished: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc, state: state(.finished, score: [3, 1], game: nil, winner: "KC"),
                            isStale: false)
    }

    /// Riot ne fournit pas les stats : score et chrono seulement.
    static var statsUnavailable: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kcb,
                            state: state(.inGame, score: [0, 0], game: 1, clockStart: Date().addingTimeInterval(-1330),
                                         statsAvailable: false),
                            isStale: false)
    }
}
```

- [ ] **Step 7 : Planches et mesure (support de test)**

Créer `Tests/FailleTests/Support/LiveActivityBoard.swift` :

```swift
import LoLKit
import SwiftUI
import UIKit
@testable import Faille

/// Un état de la Live Activity sur une planche : sa légende et ce qu'elle affiche.
struct LiveBoardState {
    let caption: String
    let display: LiveActivityDisplay

    /// Écran verrouillé : chaque état de la spec §6.3 (maquettes ① et ②).
    static var lockScreen: [LiveBoardState] {
        [
            LiveBoardState(caption: "En jeu · KC", display: LiveActivitySamples.inGame),
            LiveBoardState(caption: "Game en pause · chrono figé", display: LiveActivitySamples.clockStopped),
            LiveBoardState(caption: "Anti-spoiler · T1", display: LiveActivitySamples.masked),
            LiveBoardState(caption: "Pas fraîche", display: LiveActivitySamples.stale),
            LiveBoardState(caption: "Entre deux games", display: LiveActivitySamples.betweenGames),
            LiveBoardState(caption: "Fin du match", display: LiveActivitySamples.finished),
            LiveBoardState(caption: "Stats indisponibles", display: LiveActivitySamples.statsUnavailable),
        ]
    }

    /// Dynamic Island : en jeu, anti-spoiler, fin du match.
    static var island: [LiveBoardState] {
        [
            LiveBoardState(caption: "En jeu · KC", display: LiveActivitySamples.inGame),
            LiveBoardState(caption: "Anti-spoiler · T1", display: LiveActivitySamples.masked),
            LiveBoardState(caption: "Fin du match", display: LiveActivitySamples.finished),
        ]
    }
}

/// Planche de l'écran verrouillé (spec §6.3) : la Live Activity dans chaque état, coins arrondis comme iOS la pose.
struct LiveActivityBoard: View {
    let states: [LiveBoardState]
    static let size = CGSize(width: WidgetSize.screen.width, height: 1120)
    /// Largeur d'une Live Activity sur un iPhone de 6,3 pouces.
    static let activityWidth: CGFloat = 370

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 6) {
                    BoardCaption(text: state.caption)
                    LiveActivityLockView(display: state.display)
                        .frame(width: Self.activityWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(BoardWallpaper())
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }
}

/// Planche de la Dynamic Island (spec §6.2) : pour chaque état, la compacte (de part et d'autre de la caméra), la
/// minimale et la déployée, sur fond noir comme l'île. Disposition approchée : sur l'iPhone, c'est iOS qui place les
/// régions.
struct DynamicIslandBoard: View {
    let states: [LiveBoardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 8) {
                    BoardCaption(text: state.caption)
                    HStack(spacing: 12) {
                        compact(state.display)
                        minimal(state.display)
                    }
                    expanded(state.display)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: WidgetSize.screen.width, height: WidgetSize.screen.height, alignment: .topLeading)
        .background(BoardWallpaper())
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    /// Compacte : un côté de chaque côté de la caméra (le vide au milieu).
    private func compact(_ display: LiveActivityDisplay) -> some View {
        HStack(spacing: 0) {
            IslandCompactView(display: display, side: 0)
            Spacer(minLength: 0)
            IslandCompactView(display: display, side: 1)
        }
        .padding(.horizontal, 10)
        .frame(width: 236, height: 36)
        .background(Color.black, in: Capsule())
    }

    private func minimal(_ display: LiveActivityDisplay) -> some View {
        IslandMinimalView(display: display)
            .frame(width: 36, height: 36)
            .background(Color.black, in: Circle())
    }

    /// Déployée : équipes à gauche et à droite, score et game au centre, stats (ou message) en bas.
    private func expanded(_ display: LiveActivityDisplay) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                IslandTeamView(side: display.teams.first)
                    .frame(width: 64)
                Spacer(minLength: 4)
                IslandCenterView(display: display)
                Spacer(minLength: 4)
                IslandTeamView(side: display.teams.count > 1 ? display.teams[1] : nil)
                    .frame(width: 64)
            }
            IslandBottomView(display: display)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 370)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
    }
}

/// Mesures des vues de la Live Activity par `ImageRenderer`.
@MainActor
enum LiveActivityRender {
    /// Hauteur naturelle (pt) d'une vue posée sur `width` : iOS tronque une Live Activity de plus de 160 pt.
    static func height(_ view: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        return renderer.uiImage?.size.height ?? .infinity
    }
}
```

- [ ] **Step 8 : Tests des planches, de la hauteur et des exemples**

Créer `Tests/FailleTests/LiveActivitySnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Écran verrouillé (spec §6.1, §6.3) : la Live Activity dans chacun de ses états.
    @Test func liveActivityLockScreen() throws {
        let url = try WidgetRender.write(LiveActivityBoard(states: LiveBoardState.lockScreen),
                                         size: LiveActivityBoard.size, named: "11-live-activity")
        expectNotBlank(url)
    }

    /// Dynamic Island (spec §6.2) : compacte, minimale et déployée.
    @Test func dynamicIsland() throws {
        let url = try WidgetRender.write(DynamicIslandBoard(states: LiveBoardState.island),
                                         size: WidgetSize.screen, named: "12-dynamic-island")
        expectNotBlank(url)
    }

    /// iOS tronque une Live Activity de plus de 160 pt ; chaque vue de la Dynamic Island dessine vraiment quelque chose.
    @Test func liveActivityFitsAndDraws() {
        for state in LiveBoardState.lockScreen {
            let height = LiveActivityRender.height(LiveActivityLockView(display: state.display), width: 360)
            #expect(height > 40 && height <= 160, "\(state.caption) : \(height) pt")
        }
        let display = LiveActivitySamples.inGame
        #expect(WidgetRender.inkRatio(IslandCompactView(display: display, side: 0), size: CGSize(width: 60, height: 36)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandCompactView(display: display, side: 1), size: CGSize(width: 60, height: 36)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandMinimalView(display: display), size: CGSize(width: 36, height: 36)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandCenterView(display: display), size: CGSize(width: 160, height: 60)) > 0.01)
        #expect(WidgetRender.inkRatio(IslandBottomView(display: display), size: CGSize(width: 320, height: 24)) > 0.01)
    }
}

/// Les exemples des planches couvrent chaque état de la spec §6.3.
struct LiveActivitySampleTests {
    @Test func samplesCoverEveryState() {
        #expect(LiveActivitySamples.inGame.rows.count == 5)
        #expect(LiveActivitySamples.clockStopped.status == .clock(.stopped("24:30")))
        #expect(LiveActivitySamples.masked.isMasked)
        #expect(LiveActivitySamples.masked.score == nil)
        if case .stale = LiveActivitySamples.stale.status {} else { Issue.record("l'exemple « pas fraîche » ne l'est pas") }
        #expect(LiveActivitySamples.betweenGames.status == .betweenGames)
        #expect(LiveActivitySamples.finished.status == .victory("KC"))
        #expect(LiveActivitySamples.statsUnavailable.message == .statsUnavailable)
        #expect(LiveActivitySamples.statsUnavailable.tintHex == nil)
    }
}
```

- [ ] **Step 9 : Commit et push**

```bash
git add Shared/LiveActivity/LiveMatchAttributes+Activity.swift Shared/LiveActivity/LiveActivityViews.swift Shared/LiveActivity/IslandViews.swift Shared/Preview/LiveActivitySamples.swift Shared/DA/Icon.swift scripts/icones.sh Resources/Assets.xcassets/icon-pause.imageset Tests/FailleTests/ApercuTests.swift Tests/FailleTests/Support/LiveActivityBoard.swift Tests/FailleTests/LiveActivitySnapshotTests.swift
git commit -m "feat(live-activity): vues de l'écran verrouillé et de la Dynamic Island, icône pause, aperçus PNG" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 10 : CI iOS et aperçus**

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
cp "$HOME/Downloads/faille-apercus-<id>/"*.png .superpowers/apercus/
```

Expected : `build` (appli **et** extension : `Shared/` y est compilé) et `apercus` verts ; l'artefact contient `11-live-activity.png` (1206 × 3360 px) et `12-dynamic-island.png` (1206 × 2622 px), chacun > 100 000 octets, en plus des PNG des étapes 2 et 3 (`00-da.png` montre la nouvelle icône). Erreurs probables et replis :
- `'@retroactive' …` refusé, ou « typealias must be declared public » / « cannot be declared public » : garder la forme exacte de la spec qui compile — d'abord sans `@retroactive` (un avertissement seulement), puis avec ou sans `public` selon le message ; ne jamais ajouter de champ au contrat.
- Une hauteur > 160 pt dans `liveActivityFitsAndDraws` : réduire, dans `LiveActivityLockView` / `LiveActivityStatRows`, la police des stats à 11 pt et `verticalSpacing` à 0, puis le score à 20 pt ; ne pas relever la limite.
- `capture quasi vide` ou planche blanche : rendre la planche avec `Snapshot.write(board, named:)` (drawHierarchy, test passé en `async throws`) au lieu de `WidgetRender.write` ; ne jamais baisser le seuil.
- `Grid` mal rendu par `ImageRenderer` : remplacer `Grid`/`GridRow` par un `VStack(spacing: 1)` de `HStack` (mêmes trois colonnes, centre en `.frame(minWidth: 84)`).

---

### Task 5 : La Live Activity des matchs remplace la sonde dans l'extension

**Files :**
- Create : `Widgets/MatchLiveActivity.swift`
- Modify : `Widgets/FailleWidgets.swift` (le `WidgetBundle` réécrit à l'étape 3)
- Delete : `Widgets/ProbeAttributes.swift`

**Interfaces :**
- Consumes : `LiveMatchAttributes: ActivityAttributes` (Task 4) ; `LiveActivityDisplay(attributes:state:isStale:)` (Task 1) ; `LiveActivityLockView`, `IslandTeamView`, `IslandCenterView`, `IslandBottomView`, `IslandCompactView`, `IslandMinimalView` (Task 4) ; `Palette.abyss / text / accent / team(_:)` ; `ActivityConfiguration(for:content:dynamicIsland:)`, `ActivityViewContext` (`attributes`, `state`, `isStale`), `DynamicIsland`, `DynamicIslandExpandedRegion`, `.keylineTint(_:)`, `.activityBackgroundTint(_:)`, `.activitySystemActionForegroundColor(_:)` ; les widgets de l'étape 3 (`LockScreenWidget`, `TeamWidget`, `TeamsWidget`).
- Produces : `struct MatchLiveActivity: Widget` ; bundle `LockScreenWidget()`, `TeamWidget()`, `TeamsWidget()`, `MatchLiveActivity()` ; plus aucune trace de la sonde.

- [ ] **Step 1 : La Live Activity des matchs**

Créer `Widgets/MatchLiveActivity.swift` :

```swift
import ActivityKit
import LoLKit
import SwiftUI
import WidgetKit

/// La Live Activity d'un match (spec §6) : écran verrouillé et Dynamic Island. L'appli fournit l'état (anti-spoiler
/// déjà appliqué par `LiveMatchBuilder.state`), LoLKit (`LiveActivityDisplay`) dit quoi afficher, les vues de
/// `Shared/LiveActivity/` le posent. `context.isStale` vient d'iOS : vrai passé la `staleDate` (`updatedAt + 180 s`).
struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveMatchAttributes.self) { context in
            LiveActivityLockView(display: Self.display(context))
                .activityBackgroundTint(Palette.abyss)
                .activitySystemActionForegroundColor(Palette.text)
        } dynamicIsland: { context in
            let display = Self.display(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandTeamView(side: display.teams.first)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTeamView(side: display.teams.count > 1 ? display.teams[1] : nil)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandCenterView(display: display)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottomView(display: display)
                }
            } compactLeading: {
                IslandCompactView(display: display, side: 0)
            } compactTrailing: {
                IslandCompactView(display: display, side: 1)
            } minimal: {
                IslandMinimalView(display: display)
            }
            .keylineTint(display.tintHex.map(Palette.team) ?? Palette.accent)
        }
    }

    private static func display(_ context: ActivityViewContext<LiveMatchAttributes>) -> LiveActivityDisplay {
        LiveActivityDisplay(attributes: context.attributes, state: context.state, isStale: context.isStale)
    }
}
```

- [ ] **Step 2 : Le bundle — la sonde s'en va**

Lire `Widgets/FailleWidgets.swift` (réécrit par l'étape 3, Task 6). Contenu attendu : `@main struct FailleWidgets: WidgetBundle` listant `LockScreenWidget()`, `TeamWidget()`, `TeamsWidget()`, puis le commentaire `// Sonde de l'étape 0 : …` et `ProbeLiveActivity()`, suivi de `struct ProbeLiveActivity: Widget { … }`. Remplacer tout son contenu par :

```swift
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        LockScreenWidget()
        TeamWidget()
        TeamsWidget()
        // Spec §6 : la Live Activity des matchs (écran verrouillé et Dynamic Island).
        MatchLiveActivity()
    }
}
```

Si l'étape 3 a nommé ses widgets autrement, garder exactement les noms trouvés dans le fichier : seule la sonde (`ProbeLiveActivity`, ses lignes et son `struct`) disparaît.

- [ ] **Step 3 : Supprimer les attributs de la sonde**

```bash
git rm Widgets/ProbeAttributes.swift
grep -rn "Probe" App Shared Widgets Tests project.yml .github
```

Expected : `rm 'Widgets/ProbeAttributes.swift'`, puis aucune ligne trouvée.

- [ ] **Step 4 : Commit, push, CI**

```bash
git add Widgets/MatchLiveActivity.swift Widgets/FailleWidgets.swift
git commit -m "feat(live-activity): la Live Activity des matchs remplace la sonde dans l'extension" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : `build` et `apercus` verts. Erreurs probables et replis :
- Sendabilité de `ActivityViewContext` ou des fermetures d'`ActivityConfiguration` en Swift 6 : ajouter `@preconcurrency import ActivityKit` dans ce fichier (les erreurs deviennent des avertissements) ; en dernier recours, le repli documenté de l'étape 3 (extension en Swift 5, `SWIFT_VERSION: "5.0"` dans la cible `FailleWidgets`), à noter dans le rapport.
- `context.isStale` introuvable : remplacer par `Date() >= context.state.staleDate` (iOS redessine la Live Activity à sa `staleDate`) et le noter.
- Mélange de types dans `ActivityConfiguration` (« generic parameter could not be inferred ») : sortir la vue de l'écran verrouillé dans `private static func lockView(_ context: ActivityViewContext<LiveMatchAttributes>) -> some View`.

---

### Task 6 : Démarrage, mises à jour, bouton « Épingler » (appli)

Le contrôleur `@MainActor` des Live Activities, la passerelle ActivityKit, le câblage du store (chaque tour du premier plan, chaque action), le bouton du Détail et le texte des Réglages.

**Files :**
- Create : `App/LiveActivity/ActivityGateway.swift`
- Create : `App/LiveActivity/LiveActivityController.swift`
- Create : `App/Detail/LiveActivityPinButton.swift`
- Modify : `Shared/FileStore.swift` (`File.liveActivities`)
- Modify : `Shared/Preview/SampleData.swift` (`PreviewData.activityMatchIds`)
- Modify : `App/Store/AppStore.swift` (propriété `liveActivities`, deux `init`, `refreshLoop`, actions, `refreshLiveStats`, `setLiveActivityMode`)
- Modify : `App/Store/AppStore+LiveActivity.swift` (deuxième bloc `extension`)
- Modify : `App/Detail/MatchDetailView.swift` (doc, bouton)
- Modify : `App/Settings/SettingsView.swift` (doc, texte)
- Create : `Tests/FailleTests/LiveActivityControllerTests.swift`

**Interfaces :**
- Consumes : `LiveActivityPlanner.plan(live:follows:mode:pinned:dismissed:active:)`, `.decision(attributes:current:latest:isPinned:mode:now:)`, `.maxConcurrent`, `LiveActivityUpdate`, `LiveActivityChoices` (Task 2) ; `LiveActivityContent` (Task 1) ; `AppStore.activityContent(matchId:)`, `runWithScene(_:)` (Task 3) ; `LiveMatchAttributes.ContentState` (Task 4) ; ActivityKit : `Activity<LiveMatchAttributes>.activities`, `.request(attributes:content:pushType:)`, `activity.attributes`, `activity.content.state`, `activity.activityState`, `activity.update(_:)`, `activity.end(_:dismissalPolicy:)`, `ActivityContent(state:staleDate:)`, `ActivityUIDismissalPolicy.after(_:)` / `.immediate`, `ActivityState` (`.active`, `.stale`, `.ended`, `.dismissed`), `ActivityAuthorizationInfo().areActivitiesEnabled` ; `FileStore.load(_:from:)` / `.save(_:to:)` ; `RunEnvironment.isTesting` ; `IconView`, `Icon.pin`, `Typo.bodyMedium / .secondary`, `Palette`, `.glassCard(tint:radius:padding:)`, `Radius.inner` ; tests : `TemporaryFiles.store()`, `StubTransport(failing:)`.
- Produces :
  - `struct RunningActivity: Sendable, Equatable` (`matchId`, `attributes`, `state`, `phase: Phase` — `.running`, `.ended`, `.gone` ; `isRunning`, `isVisible`)
  - `enum ActivityGateway` — `@MainActor static var isEnabled: Bool` ; `@MainActor static func running() -> [RunningActivity]` ; `@MainActor static func start(attributes:state:) throws` ; `static func update(matchId:state:) async` ; `static func end(matchId:state:dismissAt:) async`
  - `enum PinOutcome: Equatable { case pinned, full, disabled }`
  - `@MainActor @Observable final class LiveActivityController` — `shownMatchIds: Set<String>`, `isEnabled: Bool`, `choices: LiveActivityChoices` (`private(set)`) ; `init(files: FileStore?, usesActivityKit: Bool)`, `init(preview: Set<String>)` ; `sync(live:follows:mode:canStart:now:content:) async` ; `pin(matchId:now:) -> PinOutcome` ; `remove(matchId:now:) async`
  - `AppStore.liveActivities: LiveActivityController` ; `AppStore.syncLiveActivities(canStart:) async`, `.pinActivity(matchId:) -> PinOutcome`, `.removeActivity(matchId:)`
  - `FileStore.File.liveActivities` (`live-activities.json`) ; `PreviewData.activityMatchIds: Set<String>` (`.standard` : `[SampleData.kcMatchId]`)
  - `LiveActivityPinButton(matchId:)`

- [ ] **Step 1 : Fichier des choix et données d'aperçu**

Dans `Shared/FileStore.swift`, remplacer :

```swift
        case live = "cache-live.json"
    }
```

par :

```swift
        case live = "cache-live.json"
        /// Choix sur les Live Activities (épinglées, retirées à la main, démarrées) : écrit par l'appli seule.
        case liveActivities = "live-activities.json"
    }
```

Dans `Shared/Preview/SampleData.swift`, remplacer :

```swift
    var isFailing = false
    var lastUpdate: Date?
```

par :

```swift
    var isFailing = false
    var lastUpdate: Date?
    /// Matchs dont la Live Activity est à l'écran (bouton du Détail).
    var activityMatchIds: Set<String> = []
```

puis, dans `static var standard`, remplacer :

```swift
            firstFrames: [SampleData.kcSnapshot.gameId: SampleData.kcGameStart],
            lastUpdate: SampleData.date("2026-10-15T15:05:00Z")
        )
```

par :

```swift
            firstFrames: [SampleData.kcSnapshot.gameId: SampleData.kcGameStart],
            lastUpdate: SampleData.date("2026-10-15T15:05:00Z"),
            activityMatchIds: [SampleData.kcMatchId]
        )
```

- [ ] **Step 2 : La passerelle ActivityKit**

Créer `App/LiveActivity/ActivityGateway.swift` :

```swift
import ActivityKit
import Foundation
import LoLKit

/// Une Live Activity existante, recopiée en valeurs Sendable : les objets `Activity` ne quittent jamais `ActivityGateway`.
struct RunningActivity: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        /// Active ou « pas fraîche » : on peut encore la mettre à jour.
        case running
        /// Terminée mais encore affichée (fin de match : 1 h) : elle compte dans la limite de 3.
        case ended
        /// Retirée de l'écran.
        case gone
    }

    let matchId: String
    let attributes: LiveMatchAttributes
    let state: LiveMatchState
    let phase: Phase

    var isRunning: Bool { phase == .running }
    /// À l'écran (en cours ou terminée) : compte dans la limite de 3.
    var isVisible: Bool { phase != .gone }
}

/// Le seul code qui touche ActivityKit (spec §6.4, sans push : `pushType: nil`). Les fonctions synchrones s'exécutent
/// sur l'acteur principal ; les fonctions asynchrones sont non isolées et ne reçoivent que des valeurs Sendable : les
/// `Activity`, non Sendable, restent locales à chaque appel et ne traversent jamais d'acteur (Swift 6).
enum ActivityGateway {
    /// Live Activities autorisées par iOS (faux si l'utilisateur les a coupées, et sur iPad).
    @MainActor
    static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Les Live Activities de Faille, en cours ou terminées.
    @MainActor
    static func running() -> [RunningActivity] {
        Activity<LiveMatchAttributes>.activities.map { activity in
            RunningActivity(matchId: activity.attributes.matchId, attributes: activity.attributes,
                            state: activity.content.state, phase: phase(activity.activityState))
        }
    }

    /// Démarre une Live Activity (au premier plan seulement : iOS refuse en arrière-plan).
    @MainActor
    static func start(attributes: LiveMatchAttributes, state: LiveMatchState) throws {
        _ = try Activity<LiveMatchAttributes>.request(attributes: attributes, content: content(state), pushType: nil)
    }

    static func update(matchId: String, state: LiveMatchState) async {
        for activity in Activity<LiveMatchAttributes>.activities where activity.attributes.matchId == matchId {
            await activity.update(content(state))
        }
    }

    /// Termine la Live Activity d'un match : contenu final (nil : le dernier), retrait à `dismissAt` (nil : tout de suite).
    static func end(matchId: String, state: LiveMatchState?, dismissAt: Date?) async {
        let policy: ActivityUIDismissalPolicy = dismissAt.map { .after($0) } ?? .immediate
        for activity in Activity<LiveMatchAttributes>.activities where activity.attributes.matchId == matchId {
            await activity.end(state.map { content($0) }, dismissalPolicy: policy)
        }
    }

    /// `staleDate = updatedAt + 180 s` (spec §6.4) : passé cette date, iOS affiche la Live Activity « pas fraîche ».
    private static func content(_ state: LiveMatchState) -> ActivityContent<LiveMatchState> {
        ActivityContent(state: state, staleDate: state.staleDate)
    }

    private static func phase(_ state: ActivityState) -> RunningActivity.Phase {
        switch state {
        case .active, .stale: return .running
        case .ended: return .ended
        case .dismissed: return .gone
        @unknown default: return .running
        }
    }
}
```

- [ ] **Step 3 : Le contrôleur**

Créer `App/LiveActivity/LiveActivityController.swift` :

```swift
import Foundation
import LoLKit
import Observation
import os

/// Réponse du bouton « Épingler sur l'écran verrouillé ».
enum PinOutcome: Equatable {
    case pinned
    /// 3 Live Activities sont déjà à l'écran (spec §6.4) : il faut en retirer une.
    case full
    /// Live Activities désactivées dans les réglages d'iOS (ou iPad) : le bouton explique où les réactiver (spec §10).
    case disabled
}

/// Les Live Activities de Faille (spec §6) : seul objet qui décide quoi démarrer, mettre à jour et terminer, et seul à
/// appeler ActivityKit (par `ActivityGateway`). Les décisions elles-mêmes sont dans LoLKit (`LiveActivityPlanner`,
/// `LiveActivityChoices`) ; le contenu de chaque match vient du store (`AppStore.activityContent`).
@MainActor
@Observable
final class LiveActivityController {
    /// Matchs dont la Live Activity est à l'écran (en cours, ou terminée et encore affichée).
    private(set) var shownMatchIds: Set<String> = []
    /// Live Activities autorisées par iOS (faux si l'utilisateur les a coupées, et sur iPad).
    private(set) var isEnabled: Bool
    /// Épinglés, retirés à la main, démarrés par l'appli ; enregistrés dans `live-activities.json`.
    private(set) var choices: LiveActivityChoices

    private let files: FileStore?
    /// Faux dans les tests hébergés et les aperçus : rien n'est demandé à ActivityKit (les choix restent enregistrés).
    private let usesActivityKit: Bool

    private static let log = Logger(subsystem: "Faille", category: "live-activity")

    init(files: FileStore?, usesActivityKit: Bool) {
        self.files = files
        self.usesActivityKit = usesActivityKit
        choices = files?.load(LiveActivityChoices.self, from: .liveActivities) ?? LiveActivityChoices()
        isEnabled = usesActivityKit ? ActivityGateway.isEnabled : true
        if usesActivityKit {
            shownMatchIds = Set(ActivityGateway.running().filter(\.isVisible).map(\.matchId))
        }
    }

    /// Aperçus (#Preview, PNG) : ces matchs ont une Live Activity ; rien n'est lu, écrit ni demandé à ActivityKit.
    init(preview shown: Set<String>) {
        files = nil
        usesActivityKit = false
        choices = LiveActivityChoices()
        isEnabled = true
        shownMatchIds = shown
    }

    /// Une passe complète (spec §6.4) :
    /// 1. les Live Activities démarrées par l'appli et disparues depuis ont été retirées à la main : jamais recréées ;
    /// 2. chaque Live Activity en cours est mise à jour ou terminée (`LiveActivityPlanner.decision`) — ActivityKit n'est
    ///    appelé que pour ce qui a changé ;
    /// 3. si `canStart` (premier plan) et si le direct est connu : démarrage des nouvelles, dans les places libres.
    /// - Parameter content: contenu actuel d'un match (`AppStore.activityContent`), nil s'il n'y a rien de neuf.
    func sync(live: [MatchEvent]?, follows: FollowList, mode: LiveActivityMode, canStart: Bool, now: Date,
              content: (String) -> LiveActivityContent?) async {
        guard usesActivityKit else { return }
        isEnabled = ActivityGateway.isEnabled
        let before = choices

        let running = ActivityGateway.running()
        choices.reconcile(running: Set(running.filter(\.isRunning).map(\.matchId)), now: now)
        choices = choices.pruned(now: now)

        for activity in running where activity.isRunning {
            let decision = LiveActivityPlanner.decision(
                attributes: activity.attributes, current: activity.state, latest: content(activity.matchId),
                isPinned: choices.isPinned(activity.matchId), mode: mode, now: now)
            switch decision {
            case .keep:
                break
            case let .update(state):
                await ActivityGateway.update(matchId: activity.matchId, state: state)
            case let .end(state, dismissAt):
                // Noté AVANT la fin : la réconciliation ne doit pas y voir un retrait à la main.
                choices.markEnded(activity.matchId)
                await ActivityGateway.end(matchId: activity.matchId, state: state, dismissAt: dismissAt)
            }
        }

        if canStart, isEnabled, let live {
            let visible = ActivityGateway.running().filter(\.isVisible).map(\.matchId)
            let target = LiveActivityPlanner.plan(live: live, follows: follows, mode: mode, pinned: choices.pinnedIds,
                                                  dismissed: choices.dismissedIds, active: visible)
            for matchId in target where !visible.contains(matchId) {
                // Pas de démarrage sans ids d'équipe (attributs), ni pour un match déjà fini.
                guard let start = content(matchId), let attributes = start.attributes,
                      start.state.phase != .finished else { continue }
                do {
                    try ActivityGateway.start(attributes: attributes, state: start.state)
                    choices.markStarted(matchId, now: now)
                } catch {
                    Self.log.error("Live Activity de \(matchId, privacy: .public) : \(String(describing: error), privacy: .public)")
                }
            }
        }

        shownMatchIds = Set(ActivityGateway.running().filter(\.isVisible).map(\.matchId))
        if choices != before {
            save()
        }
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : enregistré tout de suite ; la Live Activity démarre au `sync`
    /// suivant, que le store lance aussitôt. Refusé si iOS les a désactivées ou si 3 sont déjà à l'écran.
    func pin(matchId: String, now: Date = Date()) -> PinOutcome {
        guard isEnabled else { return .disabled }
        if !shownMatchIds.contains(matchId), shownMatchIds.count >= LiveActivityPlanner.maxConcurrent {
            return .full
        }
        choices.pin(matchId, now: now)
        save()
        return .pinned
    }

    /// « Retirer de l'écran verrouillé » : la Live Activity s'en va tout de suite et n'est plus recréée automatiquement.
    func remove(matchId: String, now: Date = Date()) async {
        choices.dismiss(matchId, now: now)
        save()
        shownMatchIds.remove(matchId)
        guard usesActivityKit else { return }
        await ActivityGateway.end(matchId: matchId, state: nil, dismissAt: nil)
    }

    private func save() {
        files?.save(choices, to: .liveActivities)
    }
}
```

- [ ] **Step 4 : Le store pilote le contrôleur**

Dans `App/Store/AppStore.swift` :

(a) Juste après :

```swift
    /// Heure de DÉBUT de la dernière tentative réussie de chaque donnée (pas l'heure de la réponse : la cadence du
    /// direct, 60 s, se compte de début de requête à début de requête).
    private(set) var lastSuccess: [DataKind: Date] = [:]
```

ajouter :

```swift
    /// Live Activities (spec §6) : tous les appels à ActivityKit passent par lui.
    let liveActivities: LiveActivityController
```

(b) Dans `init(transport:files:)`, remplacer :

```swift
        reloadsWidgets = !RunEnvironment.isTesting
        loadFromDisk(files)
```

par :

```swift
        reloadsWidgets = !RunEnvironment.isTesting
        // Tests hébergés : aucune Live Activity réelle (les choix restent enregistrés et testables).
        liveActivities = LiveActivityController(files: files, usesActivityKit: !RunEnvironment.isTesting)
        loadFromDisk(files)
```

(c) Dans `init(preview:)`, remplacer :

```swift
        isPreview = true
        reloadsWidgets = false
```

par :

```swift
        isPreview = true
        reloadsWidgets = false
        liveActivities = LiveActivityController(preview: data.activityMatchIds)
```

(d) Dans `refreshLoop()` (Task 3), remplacer :

```swift
            await refreshDue(opening: opening)
            opening = false
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
```

par :

```swift
            await refreshDue(opening: opening)
            opening = false
            // Spec §6.4 : au premier plan, les Live Activities suivent chaque tour ; ActivityKit n'est appelé que si leur
            // contenu a changé (en pratique à chaque relecture du direct, 60 s).
            await syncLiveActivities(canStart: true)
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
```

(e) Dans `toggleFollow(_:)`, remplacer :

```swift
        runWithScene { await self.refreshDue(opening: false) }
```

par :

```swift
        runWithScene {
            await self.refreshDue(opening: false)
            await self.syncLiveActivities(canStart: true)
        }
```

(f) Remplacer les deux occurrences (dans `setSpoilerFree` et `reveal`) de :

```swift
        runWithScene { await self.refreshLiveStats() }
```

par :

```swift
        runWithScene {
            await self.refreshLiveStats()
            // La Live Activity suit le masquage ou la révélation à sa prochaine mise à jour (spec §8) : maintenant.
            await self.syncLiveActivities(canStart: true)
        }
```

(g) Remplacer :

```swift
    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    func setLiveActivityMode(_ mode: LiveActivityMode) {
        syncSettingsBeforeChange()
        settings.liveActivityMode = mode
        saveSettings()
    }
```

par :

```swift
    /// Réglage « Live Activity » (spec §5.4) : en manuel, les Live Activities non épinglées s'en vont tout de suite ;
    /// en automatique, celles des équipes suivies démarrent.
    func setLiveActivityMode(_ mode: LiveActivityMode) {
        syncSettingsBeforeChange()
        settings.liveActivityMode = mode
        saveSettings()
        runWithScene { await self.syncLiveActivities(canStart: true) }
    }
```

(h) Remplacer :

```swift
    /// Stats des matchs en direct des équipes suivies, pour leurs cartes (cadence du direct). Les matchs masqués ne
    /// sont pas demandés. Une game en cours est interrogée même quand Riot n'en fournit pas les stats
    /// (`statsDisabled`) : le chrono (spec §4.3, §5.1) n'en dépend pas, et les stats restent cachées par LoLKit.
    /// Un 404 arrête ensuite les nouvelles tentatives pour cette game (`statsUnavailable`).
    func refreshLiveStats() async {
        guard !isPreview, let live else { return }
        for event in live where follows.involves(event.match.teams) {
```

par :

```swift
    /// Stats des matchs en direct des équipes suivies (cartes) et de ceux qui ont une Live Activity (match épinglé
    /// d'équipes non suivies), à la cadence du direct. Les matchs masqués ne sont pas demandés. Une game en cours est
    /// interrogée même quand Riot n'en fournit pas les stats (`statsDisabled`) : le chrono (spec §4.3, §5.1) n'en
    /// dépend pas, et les stats restent cachées par LoLKit. Un 404 arrête ensuite les nouvelles tentatives pour cette
    /// game (`statsUnavailable`).
    func refreshLiveStats() async {
        guard !isPreview, let live else { return }
        for event in live where follows.involves(event.match.teams) || liveActivities.shownMatchIds.contains(event.id) {
```

Ajouter à la fin de `App/Store/AppStore+LiveActivity.swift` :

```swift

// MARK: - Live Activities (étape 4, Task 6)

extension AppStore {
    /// Live Activities à jour (spec §6.4) : retraits à la main reconnus, mises à jour et fins, puis démarrages si
    /// `canStart` (premier plan seulement). Sans effet dans les aperçus et les tests hébergés.
    func syncLiveActivities(canStart: Bool) async {
        await liveActivities.sync(live: live, follows: follows, mode: settings.liveActivityMode, canStart: canStart,
                                  now: Date()) { matchId in
            self.activityContent(matchId: matchId)
        }
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : enregistré tout de suite, la Live Activity démarre aussitôt.
    func pinActivity(matchId: String) -> PinOutcome {
        let outcome = liveActivities.pin(matchId: matchId)
        if outcome == .pinned {
            runWithScene { await self.syncLiveActivities(canStart: true) }
        }
        return outcome
    }

    /// « Retirer de l'écran verrouillé » : tout de suite, et plus jamais recréée automatiquement pour ce match.
    func removeActivity(matchId: String) {
        runWithScene { await self.liveActivities.remove(matchId: matchId) }
    }
}
```

- [ ] **Step 5 : Le bouton du Détail**

Créer `App/Detail/LiveActivityPinButton.swift` :

```swift
import LoLKit
import SwiftUI

/// « Épingler sur l'écran verrouillé » / « Retirer de l'écran verrouillé » (spec §5.3, §6.4). Explique pourquoi rien
/// ne s'affiche quand iOS a désactivé les Live Activities (spec §10) ou quand 3 sont déjà à l'écran.
struct LiveActivityPinButton: View {
    @Environment(AppStore.self) private var store
    let matchId: String
    @State private var refused: PinOutcome?

    var body: some View {
        let controller = store.liveActivities
        let shown = controller.shownMatchIds.contains(matchId)
        VStack(spacing: 6) {
            Button {
                if shown {
                    refused = nil
                    store.removeActivity(matchId: matchId)
                } else {
                    let outcome = store.pinActivity(matchId: matchId)
                    refused = outcome == .pinned ? nil : outcome
                }
            } label: {
                HStack(spacing: 6) {
                    IconView(icon: .pin, size: 15)
                    Text(shown ? "Retirer de l'écran verrouillé" : "Épingler sur l'écran verrouillé")
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(controller.isEnabled ? Palette.text : Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassCard(radius: Radius.inner, padding: 4)
            if let note = note(enabled: controller.isEnabled) {
                Text(note)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func note(enabled: Bool) -> String? {
        if !enabled || refused == .disabled {
            return "Live Activities désactivées : Réglages › Faille › Activités en direct."
        }
        if refused == .full {
            return "Déjà 3 Live Activities sur l'écran verrouillé : retires-en une d'abord."
        }
        return nil
    }
}
```

Dans `App/Detail/MatchDetailView.swift`, remplacer :

```swift
/// stats d'équipe et joueurs de la game choisie. Le bouton « Épingler sur l'écran verrouillé » arrive à l'étape 4.
```

par :

```swift
/// stats d'équipe et joueurs de la game choisie, et bouton « Épingler sur l'écran verrouillé » (iPhone, spec §6.4).
```

puis remplacer :

```swift
        } else {
            ProgressView()
                .tint(Palette.secondary)
                .frame(maxWidth: .infinity)
        }
    }
```

par :

```swift
        } else {
            ProgressView()
                .tint(Palette.secondary)
                .frame(maxWidth: .infinity)
        }
        if showsPinButton(event: event) {
            LiveActivityPinButton(matchId: model.matchId)
        }
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : iPhone seulement (Apple n'affiche pas les Live Activities sur
    /// iPad), pour un match en direct ou dont la Live Activity est encore à l'écran.
    private func showsPinButton(event: MatchEvent?) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && (event?.state == .inProgress || store.liveActivities.shownMatchIds.contains(model.matchId))
    }
```

- [ ] **Step 6 : Réglages — un texte honnête**

Dans `App/Settings/SettingsView.swift`, remplacer :

```swift
/// Réglages (spec §5.4) : mode de la Live Activity (utilisé à l'étape 4) et À propos.
```

par :

```swift
/// Réglages (spec §5.4) : mode de la Live Activity et À propos.
```

puis remplacer :

```swift
                        Text("Les Live Activities arrivent dans une prochaine version de Faille ; ce choix est déjà enregistré.")
```

par :

```swift
                        Text("Sans serveur de push, la Live Activity se met à jour quand Faille est ouverte, et en arrière-plan quand iOS le permet (environ toutes les 15 min, si l'actualisation en arrière-plan est activée). Sinon elle affiche « màj il y a X min ».")
```

- [ ] **Step 7 : Tests hébergés**

Créer `Tests/FailleTests/LiveActivityControllerTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Bouton du Détail et choix enregistrés (spec §5.3, §6.4, §10). ActivityKit n'est pas appelé dans les tests hébergés :
/// les décisions sont testées dans LoLKit, ici le câblage et la persistance.
@MainActor
@Suite(.serialized)
struct LiveActivityControllerTests {
    @Test func pinAndRemovalAreSavedAndKeptDisjoint() async {
        let files = TemporaryFiles.store()
        let controller = LiveActivityController(files: files, usesActivityKit: false)
        #expect(controller.pin(matchId: "m1") == .pinned)
        #expect(LiveActivityController(files: files, usesActivityKit: false).choices.pinnedIds == ["m1"])

        await controller.remove(matchId: "m1")
        let reloaded = LiveActivityController(files: files, usesActivityKit: false)
        #expect(reloaded.choices.pinnedIds.isEmpty)
        #expect(reloaded.choices.dismissedIds == ["m1"])

        // Épingler à nouveau annule le retrait.
        #expect(reloaded.pin(matchId: "m1") == .pinned)
        #expect(reloaded.choices.dismissedIds.isEmpty)
    }

    @Test func aFourthPinIsRefusedWhileThreeAreShown() {
        let controller = LiveActivityController(preview: ["a", "b", "c"])
        #expect(controller.pin(matchId: "d") == .full)
        #expect(controller.pin(matchId: "a") == .pinned)
        #expect(controller.choices.pinnedIds == ["a"])
    }

    @Test func theStoreGoesThroughTheController() {
        let store = AppStore(transport: StubTransport(failing: true), files: TemporaryFiles.store())
        #expect(store.pinActivity(matchId: "m1") == .pinned)
        #expect(store.liveActivities.choices.isPinned("m1"))
    }

    @Test func previewStoreShowsTheKcActivity() {
        #expect(AppStore(preview: .standard).liveActivities.shownMatchIds == [SampleData.kcMatchId])
        #expect(AppStore(preview: .empty).liveActivities.shownMatchIds.isEmpty)
    }
}
```

- [ ] **Step 8 : Commit, push, CI et aperçus**

```bash
git add App/LiveActivity/ActivityGateway.swift App/LiveActivity/LiveActivityController.swift App/Detail/LiveActivityPinButton.swift Shared/FileStore.swift Shared/Preview/SampleData.swift App/Store/AppStore.swift App/Store/AppStore+LiveActivity.swift App/Detail/MatchDetailView.swift App/Settings/SettingsView.swift Tests/FailleTests/LiveActivityControllerTests.swift
git commit -m "feat(live-activity): démarrage auto/manuel, mises à jour au premier plan, bouton Épingler du Détail" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
cp "$HOME/Downloads/faille-apercus-<id>/"*.png .superpowers/apercus/
```

Expected : `build` et `apercus` verts ; les 4 tests de `LiveActivityControllerTests` verts ; `04-detail.png` montre « Retirer de l'écran verrouillé » (KC a une Live Activity dans l'aperçu), `05-detail-sans-stats.png` et `06-detail-masque.png` « Épingler sur l'écran verrouillé », `07-reglages.png` le nouveau texte. Erreurs probables et replis (dans cet ordre) :
1. « sending 'activity' risks causing data races » / « non-sendable type 'Activity<…>' » dans `ActivityGateway` : ajouter `@preconcurrency import ActivityKit` en tête du fichier ; si une erreur persiste sur `update` / `end`, marquer aussi ces deux fonctions `@MainActor` (les `Activity` restent alors sur l'acteur principal).
2. `Activity.request` (ou `activities`) annoncé `@MainActor` ailleurs que là où on l'appelle : toutes les fonctions synchrones de la passerelle le sont déjà ; ne pas déplacer d'appel ActivityKit hors de `ActivityGateway`.
3. `ActivityState` sans `.stale` : retirer `.stale` du `case` (il tombe dans `@unknown default`, traité comme « en cours »).
4. `UIDevice` introuvable dans `MatchDetailView` : ajouter `import UIKit`.
5. Un test de capture des étapes 2-3 casse parce que le Détail est plus haut : c'est attendu (le bouton s'ajoute en bas) — seuls `expectNotBlank` et la présence comptent.

---

### Task 7 : Passage en arrière-plan et `BGAppRefreshTask`

**Files :**
- Create : `App/LiveActivity/BackgroundRefresh.swift`
- Modify (réécrit) : `App/FailleApp.swift`
- Modify : `App/Store/AppStore+LiveActivity.swift` (troisième bloc `extension`)
- Modify : `project.yml` (cible `Faille`, `info.properties`)
- Modify : `.github/workflows/ios.yml` (job `build`, nouvelle étape avant « Signer en ad hoc avec les entitlements »)
- Create : `Tests/FailleTests/BackgroundRefreshTests.swift`

**Interfaces :**
- Consumes : `LiveActivityPlanner.nextBackgroundRefresh(now:live:follows:hasActivities:)` (Task 2) ; `AppStore.refreshDue(opening:)`, `.syncLiveActivities(canStart:)`, `.liveActivities.shownMatchIds`, `.live`, `.follows`, `.poll()` ; `RunEnvironment.isTesting` ; `AppStore(preview:)`, `AppStore(files:)`, `FileStore(directory:)`, `AppGroup.directory` ; BackgroundTasks : `BGTaskScheduler.shared.submit(_:)`, `.cancel(taskRequestWithIdentifier:)`, `BGAppRefreshTaskRequest(identifier:)`, `.earliestBeginDate` ; SwiftUI : `Scene.backgroundTask(_:action:)`, `BackgroundTask.appRefresh(_:)`, `View.onChange(of:_:)` ; UIKit : `UIApplication.shared.beginBackgroundTask(withName:expirationHandler:)`, `.endBackgroundTask(_:)`.
- Produces :
  - `enum BackgroundRefresh` — `static let identifier = "faille.live-refresh"`, `static func schedule(at: Date?)`, `@MainActor static func finishInBackground(_ work: @escaping @MainActor @Sendable () async -> Void)`
  - `@MainActor enum AppRuntime` — `static let store: AppStore`, `static func refreshInBackground() async`
  - `AppStore.refreshInBackground() async`, `.enterBackground() async`, `.scheduleBackgroundRefresh(now:)`
  - Info.plist de l'appli : `UIBackgroundModes = [fetch]`, `BGTaskSchedulerPermittedIdentifiers = [faille.live-refresh]`

- [ ] **Step 1 : Info.plist (XcodeGen)**

Dans `project.yml`, cible `Faille`, remplacer :

```yaml
        NSSupportsLiveActivities: true
```

par :

```yaml
        NSSupportsLiveActivities: true
        # Réveils en arrière-plan pour les Live Activities (spec §6.4) : BGAppRefreshTask, sans entitlement ni push.
        UIBackgroundModes:
          - fetch
        BGTaskSchedulerPermittedIdentifiers:
          - faille.live-refresh
```

- [ ] **Step 2 : CI — vérifier l'Info.plist de l'appli**

Dans `.github/workflows/ios.yml`, job `build`, insérer juste avant la ligne `      - name: Signer en ad hoc avec les entitlements` :

```yaml
      - name: Vérifier l'Info.plist de l'appli (Live Activities, arrière-plan)
        # Sans ces clés, iOS refuse les Live Activities ou ne réveille jamais l'appli en arrière-plan (spec §6.4).
        run: |
          PLIST=build/Build/Products/Release-iphoneos/Faille.app/Info.plist
          /usr/libexec/PlistBuddy -c "Print :NSSupportsLiveActivities" "$PLIST" | grep -qx true
          /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" | grep -q fetch
          /usr/libexec/PlistBuddy -c "Print :BGTaskSchedulerPermittedIdentifiers" "$PLIST" | grep -q faille.live-refresh

```

- [ ] **Step 3 : Demandes de réveil et temps de fin**

Créer `App/LiveActivity/BackgroundRefresh.swift` :

```swift
import BackgroundTasks
import Foundation
import os
import UIKit

/// Rafraîchissement en arrière-plan (spec §6.4) : `BGAppRefreshTask` environ toutes les 15 min tant qu'un match suivi
/// est en direct. iOS décide seul du moment, et peut ne rien accorder (mode économie d'énergie, actualisation en
/// arrière-plan coupée, appli peu utilisée) : la Live Activity le montre alors honnêtement (« màj il y a X min »).
enum BackgroundRefresh {
    /// Déclaré dans Info.plist (`BGTaskSchedulerPermittedIdentifiers`). Indépendant du bundle ID, qu'AltServer renomme.
    static let identifier = "faille.live-refresh"

    private static let log = Logger(subsystem: "Faille", category: "arrière-plan")

    /// Demande le prochain réveil au plus tôt à `date` ; nil annule la demande en attente. Rien dans les tests.
    static func schedule(at date: Date?) {
        guard !RunEnvironment.isTesting else { return }
        guard let date else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulateur, actualisation en arrière-plan coupée : la Live Activity passera « pas fraîche ».
            log.info("Réveil en arrière-plan non programmé : \(String(describing: error), privacy: .public)")
        }
    }

    /// Laisse à `work` le temps de finir après le passage en arrière-plan (quelques secondes accordées par iOS).
    @MainActor
    static func finishInBackground(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let assertion = BackgroundAssertion()
        assertion.begin()
        Task {
            await work()
            assertion.end()
        }
    }
}

/// Une demande de temps d'exécution en arrière-plan (`beginBackgroundTask`), rendue au plus tard à son expiration.
@MainActor
private final class BackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Faille · Live Activities") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
```

- [ ] **Step 4 : Le store en arrière-plan**

Ajouter à la fin de `App/Store/AppStore+LiveActivity.swift` :

```swift

// MARK: - Arrière-plan (étape 4, Task 7)

extension AppStore {
    /// Réveil par iOS (`BGAppRefreshTask`, spec §6.4) : le direct et les stats des matchs suivis (ni logos ni couleurs :
    /// le temps accordé est compté, environ 30 s), puis les Live Activities — sans en démarrer, iOS ne le permet pas
    /// en arrière-plan —, puis la demande du réveil suivant. Sans effet dans les aperçus et les tests.
    func refreshInBackground() async {
        await refreshDue(opening: false)
        await syncLiveActivities(canStart: false)
        scheduleBackgroundRefresh()
    }

    /// Passage en arrière-plan (spec §6.4) : une dernière mise à jour des Live Activities avec ce que l'appli sait, puis
    /// la demande du premier réveil.
    func enterBackground() async {
        await syncLiveActivities(canStart: false)
        scheduleBackgroundRefresh()
    }

    /// Dans 15 min si un match suivi est en direct ou si une Live Activity est à l'écran ; sinon, plus aucune demande.
    func scheduleBackgroundRefresh(now: Date = Date()) {
        BackgroundRefresh.schedule(at: LiveActivityPlanner.nextBackgroundRefresh(
            now: now, live: live, follows: follows, hasActivities: !liveActivities.shownMatchIds.isEmpty))
    }
}
```

- [ ] **Step 5 : L'appli — store unique, passage en arrière-plan, tâche d'arrière-plan**

Remplacer tout le contenu de `App/FailleApp.swift` par :

```swift
import SwiftUI

/// Le store unique de l'appli : la scène, le passage en arrière-plan et la tâche d'arrière-plan d'iOS (qui peut réveiller
/// l'appli sans aucune scène au premier plan) partagent le même.
@MainActor
enum AppRuntime {
    /// Dans les tests hébergés, un store figé et inerte : le vrai ne doit ni lire le disque de l'appli ni appeler l'API.
    static let store: AppStore = RunEnvironment.isTesting
        ? AppStore(preview: .empty)
        : AppStore(files: FileStore(directory: AppGroup.directory))

    static func refreshInBackground() async {
        await store.refreshInBackground()
    }
}

@main
struct FailleApp: App {
    @State private var store = AppRuntime.store
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if RunEnvironment.isTesting {
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
                    // Passage en arrière-plan (spec §6.4) : dernière mise à jour des Live Activities, puis demande du
                    // premier réveil si un match suivi est en direct.
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .background else { return }
                        BackgroundRefresh.finishInBackground {
                            await AppRuntime.store.enterBackground()
                        }
                    }
            }
        }
        // Réveil par iOS environ toutes les 15 min tant qu'un match suivi est en direct (spec §6.4), si l'actualisation
        // en arrière-plan n'est pas coupée.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await AppRuntime.refreshInBackground()
        }
    }
}
```

- [ ] **Step 6 : Tests hébergés**

Créer `Tests/FailleTests/BackgroundRefreshTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Arrière-plan (spec §6.4) : clés de l'Info.plist, et rien de réel dans les aperçus et les tests.
@MainActor
struct BackgroundRefreshTests {
    @Test func infoPlistAllowsLiveActivitiesAndTheBackgroundRefresh() {
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String]
        #expect(identifiers == [BackgroundRefresh.identifier])
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("fetch") == true)
        #expect(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true)
    }

    @Test func thePreviewStoreDoesNothingInBackground() async {
        let store = AppStore(preview: .standard)
        await store.refreshInBackground()   // ni réseau, ni ActivityKit, ni demande à iOS
        await store.enterBackground()
        #expect(store.schedule == SampleData.schedule)
        #expect(store.liveActivities.shownMatchIds == [SampleData.kcMatchId])
    }
}
```

- [ ] **Step 7 : Commit, push, CI**

```bash
git add App/LiveActivity/BackgroundRefresh.swift App/FailleApp.swift App/Store/AppStore+LiveActivity.swift project.yml .github/workflows/ios.yml Tests/FailleTests/BackgroundRefreshTests.swift
git commit -m "feat(live-activity): dernière mise à jour au passage en arrière-plan et réveils BGAppRefreshTask" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run view <id> --log | grep -A6 "Vérifier l'Info.plist de l'appli"
```

Expected : `build` vert (l'étape « Vérifier l'Info.plist de l'appli » passe), `apercus` vert avec les 2 tests de `BackgroundRefreshTests`. Erreurs probables et replis (dans cet ordre) :
1. `backgroundTask` / `.appRefresh` refusé en Swift 6 (fermeture non Sendable, isolement) : garder l'appel sous la forme `await AppRuntime.refreshInBackground()` (fonction `@MainActor` appelée avec `await`) ; si le modificateur de scène reste inutilisable, repli UIKit — un `final class AppDelegate: NSObject, UIApplicationDelegate` déclaré par `@UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate` dans `FailleApp`, dont `application(_:didFinishLaunchingWithOptions:)` appelle `BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundRefresh.identifier, using: nil) { task in … }` ; le gestionnaire lance `Task { @MainActor in await AppRuntime.refreshInBackground(); task.setTaskCompleted(success: true) }` et pose `task.expirationHandler` (annulation de cette `Task`) — à noter dans le rapport.
2. Fermeture d'expiration de `beginBackgroundTask` refusée (« call to main actor-isolated instance method 'end()' in a synchronous nonisolated context ») : la remplacer par `{ [weak self] in Task { @MainActor in self?.end() } }`.
3. `onChange(of:)` à deux paramètres indisponible : `.onChange(of: scenePhase) { phase in … }` (forme iOS 14), même corps.
4. L'étape PlistBuddy échoue sur `UIBackgroundModes` : le bloc YAML du Step 1 n'est pas sous `info.properties` de la cible `Faille` (indentation).

---

### Task 8 : Sur l'iPhone, pendant un match des Worlds — checklist de Dan (manuelle)

**Files :**
- Create : `docs/superpowers/notes/2026-10-etape-4-verdict.md`

**Interfaces :**
- Consumes : l'IPA du dernier run iOS vert (artefact `Faille-ipa`), installée avec AltServer (`docs/superpowers/notes/2026-10-etape-0-verdict.md`) ; les PNG `11-live-activity.png` et `12-dynamic-island.png`.
- Produces : le verdict de l'étape 4 (spec §13 : « Checklist §11.4 passée pendant un match des Worlds »).

- [ ] **Step 1 : Préparer l'IPA**

```bash
gh run list --workflow iOS --branch main --status success --limit 1 --json databaseId,headSha --jq '.[0]'
gh run download <id> --name Faille-ipa --dir "$HOME/Downloads/faille-ipa-<id>" && ls -la "$HOME/Downloads/faille-ipa-<id>"
cp "$HOME/Downloads/faille-ipa-<id>/Faille.ipa" "$HOME/Downloads/faille/Faille-etape4.ipa"
```

Expected : `Faille.ipa` copiée en `Faille-etape4.ipa`. Le contrôleur la donne à Dan avec les vérifications du Step 2 ; Dan l'installe avec AltServer (Maj + clic sur l'icône → « Sideload .ipa… »). Avant le match : Réglages iOS › Général › Actualisation en arrière-plan → activée pour Faille ; Réglages › Faille › Activités en direct → activées ; mode économie d'énergie coupé.

- [ ] **Step 2 : Vérifications de Dan (une réponse par ligne, pendant un match des Worlds d'une équipe suivie)**

1. Réglages de Faille : « Automatique ». Ouvrir Faille pendant le match : la Live Activity apparaît en quelques secondes ; verrouiller : en-tête « MONDIAL · BO5 · GAME N », chrono, score entre les monogrammes, 5 lignes de stats, fond à la couleur de l'équipe suivie (Sora, icônes au trait, pas d'emoji). Rien n'est coupé en bas.
2. Le chrono avance seul, téléphone verrouillé, sans ouverture de l'appli ; il colle à celui du stream (à ~1 min près, retard normal du flux).
3. Dynamic Island : compacte (monogramme + victoires de chaque côté de la caméra) ; appui long → déployée (équipes, score, « Game N · chrono », 5 stats sur une ligne) ; minimale quand une autre appli occupe l'île (lancer un minuteur de l'appli Horloge).
4. Premier plan : laisser Faille ouverte 2 min puis verrouiller : score et stats à jour (moins d'une minute de retard sur l'appli).
5. Arrière-plan : verrouiller 30 min sans ouvrir Faille. Noter ce qui se passe : mises à jour toutes les ~15 min (réveils accordés par iOS) ou « màj il y a X min » à la place du chrono, stats pâlies. Noter aussi le texte exact de « màj il y a … » (s'il affiche des secondes, le signaler).
6. Entre deux games : « entre deux games » (icône pause), score de série à jour, « La game N commence dans quelques minutes ».
7. Anti-spoiler : une équipe suivie en anti-spoiler joue → « En direct » + « Sans spoiler · ouvre l'appli pour révéler », ni score ni numéro de game ni stats, dans la Dynamic Island aussi. Révéler le match dans l'appli → la Live Activity montre le score en quelques secondes.
8. Glisser la Live Activity pour la retirer, rouvrir Faille : elle ne revient pas ; le Détail du match propose « Épingler sur l'écran verrouillé » → elle revient ; « Retirer de l'écran verrouillé » → elle s'en va.
9. Réglage « Manuelle » : les Live Activities non épinglées s'en vont ; épingler un match depuis le Détail → il s'affiche ; rien d'autre ne s'affiche tout seul. Repasser en « Automatique ».
10. Fin du match : « Victoire XX » (icône trophée), score final, « Se retire de l'écran verrouillé au bout d'une heure » ; elle disparaît environ 1 h plus tard.
11. Match sans stats (épingler un match régional sans stats si l'occasion se présente) : score + chrono + « Stats live non fournies par Riot pour ce match », verre neutre si aucune équipe n'est suivie.
12. Plus de 3 matchs suivis en direct (si l'occasion se présente) : 3 Live Activities au plus, dans l'ordre de suivi ; « Épingler » un 4e → message « Déjà 3 Live Activities… ».
13. Live Activities coupées dans Réglages › Faille : le Détail affiche « Live Activities désactivées : Réglages › Faille › Activités en direct. ».
14. iPad (si disponible) : pas de bouton « Épingler », l'appli et les widgets marchent.

- [ ] **Step 3 : Écrire le verdict**

Créer `docs/superpowers/notes/2026-10-etape-4-verdict.md` avec, pour en-tête, la date, le match regardé, l'id du run et le SHA de l'IPA, puis le tableau des 14 vérifications du Step 2 (colonnes : n°, vérification, résultat « OK » / « KO » + remarque de Dan), puis les écarts constatés et les décisions qui en découlent. Replis prévus : « màj il y a » avec des secondes → `Text(timerInterval: since...Date.distantFuture, countsDown: false)` (« màj il y a 9:12 ») ; chrono qui pousse l'en-tête → largeur du minuteur réduite ou `Text(timerInterval:)` ; aucun réveil en arrière-plan observé → rien à corriger côté code (limite d'iOS sans push, documentée ; phase 2 de la spec §12).

- [ ] **Step 4 : Commit et push**

```bash
git add docs/superpowers/notes/2026-10-etape-4-verdict.md
git commit -m "docs: verdict de l'étape 4 sur l'iPhone" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

Expected : verdict commité ; chaque KO devient une tâche de correction (même cycle : code, push, CI).

---

## Auto-relecture

**1. Couverture de la spec**

| Exigence | Tâche |
|---|---|
| §4.3 wrapper `extension LiveMatchAttributes: ActivityAttributes { typealias ContentState = LiveMatchState }` | T4 (Shared, appli + extension) |
| §4.3 fixture dorée inchangée | T1 (aucun champ ajouté ; `LiveContractTests` relancé), Global Constraints |
| §4.3 `gameClockStoppedAt` : le chrono s'arrête ; sans début, pas de chrono | T1 (`runningClock`, testé) |
| §6.1 en-tête « LIGUE · Bo5 · Game N » + chrono qui tourne seul | T1 (`header`, `.clock(.running)`), T4 (`Text(.timer)`) |
| §6.1 score : monogramme + code, score au centre | T1 (`teams`, `score`), T4 (`LiveActivityScoreRow`) |
| §6.1 5 lignes ; écart de gold à la couleur du meneur | T1 (`rows`, `lead`, `leader`), T4 (`LiveActivityStatRows`) |
| §6.1 fond dégradé équipe suivie → abysse ; deux suivies : la première suivie | T1 (`tintHex` = `primaryTeamIndex`), T4 (`LiveActivityBackdrop`) |
| §6.2 compacte, minimale, déployée | T1 (`compactScore`, `Row.compact`), T4 (`Island*View`), T5 (`DynamicIsland`) |
| §6.3 `inGame`, `betweenGames`, `finished`, stats indisponibles, pas fraîche, anti-spoiler | T1 (10 tests), T4 (planche à 7 états) |
| §6.3 retrait 1 h après la fin | T2 (`decision` → `.end(…, dismissAt: now + 3600)`), T6 (`ActivityUIDismissalPolicy.after`) |
| §6.4 automatique : à chaque passage au premier plan, une par match d'équipe suivie, max 3 par ordre de suivi | T2 (`plan(… active:)`), T6 (`refreshLoop` → `syncLiveActivities(canStart: true)`) |
| §6.4 manuelle : uniquement via le Détail | T2 (`decision` en manuel), T6 (`LiveActivityPinButton`) |
| §6.4 retirée à la main : jamais recréée | T2 (`LiveActivityChoices.reconcile` / `dismiss`), T6 (`sync`, `remove`) |
| §6.4 mises à jour : premier plan (10 s), passage en arrière-plan, `BGAppRefreshTask` 15 min | T6 (`refreshLoop`), T7 (`enterBackground`, `.backgroundTask`, `nextBackgroundRefresh`) |
| §6.4 `staleDate` | T1 (`updatedAt` honnête), T6 (`ActivityContent(state:staleDate:)`) |
| §6.4 fin quand le match passe à `completed` | T3 (`activityContent` : calendrier `completed`, `displayed(for:)`), T2 |
| §5.3 bouton « Épingler / Retirer » (iPhone uniquement) | T6 |
| §8 anti-spoiler partout, révélation suivie à la mise à jour suivante | T1 (affichage masqué), T3 (`LiveMatchBuilder.state`), T6 (`reveal` / œil → `syncLiveActivities`) |
| §9 DA (abysse, teinte, Sora, icônes, monogrammes) | T4 |
| §10 Live Activities désactivées : le bouton explique ; plus de 3 matchs | T6 (`PinOutcome.disabled` / `.full`, note du bouton) |
| §11.1 « ordre et limite de 3 Live Activities », « pas fraîche » | T2, T1 |
| §11.3 PNG de la Live Activity (tous les états) et de la Dynamic Island | T4 (`11-live-activity.png`, `12-dynamic-island.png`, hauteur ≤ 160 pt, encre par vue) |
| §11.4 / §13 checklist pendant un match des Worlds | T8 |
| Différés : `updatedAt`, logos hors cycle, tâches de scène, `active:`, disjoints, chrono sans début, ordre des équipes | T1, T2, T3 (table « Points différés ») ; `syncFollowsBeforeChange` déjà corrigé (F7) |

Hors périmètre, assumé : push et push-to-start (phase 2, spec §12) ; `relevanceScore` ; observation `activityStateUpdates` (remplacée par la réconciliation) ; lien profond Live Activity → Détail (un toucher ouvre l'appli).

**2. Contrat** : `live_contract.json`, `LiveMatchAttributes` et `LiveMatchState` gardent exactement leurs champs ; seule la sémantique documentée de `updatedAt` est précisée (dernière relecture réussie), et `LiveMatchBuilder.state` gagne un paramètre par défaut. `LiveContractTests` est relancé en T1, Step 6.

**3. Recherche de trous** : chaque fichier créé a son code complet ; chaque fichier modifié a son ancien et son nouveau texte exacts. Les seuls champs à remplir sont l'id de run (`<id>`, sortie d'une commande donnée) et les résultats de Dan (T8). Deux fichiers dépendent de l'étape 3 et sont lus avant d'être touchés : `Widgets/FailleWidgets.swift` (T5, Step 2) et `Tests/FailleTests/Support/WidgetBoard.swift` / `Shared/Widgets/WidgetChrome.swift` (T4, Step 1).

**4. Cohérence des types** (vérifiée contre les sources) : `LiveMatchBuilder.state(details:snapshot:firstFrameTime:statsDisabled:follows:revealed:now:)` (+ `updatedAt:`), `LiveMatchBuilder.attributes(for:follows:)`, `LiveMatchState(phase:seriesScore:gameNumber:gameClockStart:gameClockStoppedAt:stats:statsAvailable:spoilerFree:winnerCode:updatedAt:)`, `.masked()`, `.staleDate`, `.staleAfter`, `LiveMatchAttributes(matchId:leagueName:bestOf:teams:primaryTeamIndex:)`, `.Side(id:code:name:colorHex:)`, `TeamStats(kills:gold:towers:inhibitors:barons:dragons:)`, `LiveActivityPlanner.plan(live:follows:mode:pinned:dismissed:)` et ses 5 tests, `LiveActivityMode`, `FollowList.involves(_:)`, `MatchTeam.isSame(as:)`, `EventDetails(event:)`, `MatchEvent.statsDisabled`, `LiveMatchState.displayed(for:)` (appli), `Format.gold / goldDiff / clock / score`, `AppStore.lastSuccess / live / schedule / follows / settings / refreshDue(opening:) / refreshLiveStats() / setLiveActivityMode(_:)`, `FileStore.load(_:from:) / save(_:to:)`, `PreviewData` (initialiseur membre à membre, nouveau champ en dernier), `Icon`, `IconView(icon:size:)`, `Palette`, `Sora.font(_:_:)`, `Typo`, `.glassCard(tint:radius:padding:)`, `Radius.inner`, `ScriptedTransport`, `StubTransport`, `TemporaryFiles`, `SampleData.kcMatchId / .t1MatchId / .schedule / .date(_:)` ; de l'étape 3 : `reorder(_:_:)`, `MonogramBadge(code:tint:size:)`, `WidgetRender.write / inkRatio`, `WidgetSize.screen`, `BoardWallpaper`, `BoardCaption(text:)`. Noms produits et réutilisés à l'identique : `LiveActivityContent(teams:attributes:state:)` / `(details:state:follows:)`, `aligned(from:to:)`, `LiveActivityDisplay` (`GameClock`, `Status`, `Stat`, `Row`, `Message`, `compactScore`), `LiveActivityUpdate` (`.keep`, `.update`, `.end(_:dismissAt:)`), `LiveActivityPlanner.decision(attributes:current:latest:isPinned:mode:now:)`, `.nextBackgroundRefresh(now:live:follows:hasActivities:)`, `.finishedDisplay`, `.backgroundInterval`, `LiveActivityChoices` (`pin`, `dismiss`, `markStarted`, `markEnded`, `reconcile(running:now:)`, `pruned(now:)`, `pinnedIds`, `dismissedIds`, `isPinned`), `RunningActivity`, `ActivityGateway`, `PinOutcome`, `LiveActivityController.sync(live:follows:mode:canStart:now:content:)`, `AppStore.activityContent(matchId:) / syncLiveActivities(canStart:) / pinActivity(matchId:) / removeActivity(matchId:) / runWithScene(_:) / endScene() / updateColorsIfNeeded() / refreshInBackground() / enterBackground() / scheduleBackgroundRefresh(now:)`, `BackgroundRefresh.identifier / schedule(at:) / finishInBackground(_:)`, `AppRuntime.store / refreshInBackground()`. `LiveActivityDisplay.GameClock` évite le protocole `Clock` de la bibliothèque standard.

**5. API ActivityKit / BackgroundTasks / SwiftUI — prudence et replis**

| API | Tâche | Risque | Repli |
|---|---|---|---|
| `extension LiveMatchAttributes: @retroactive ActivityAttributes` + `public typealias ContentState` | T4 | `@retroactive` ou `public` refusés selon le contexte | sans `@retroactive` (avertissement seulement), `public` ôté ou ajouté selon le message ; jamais de changement du contrat |
| `Activity.request(attributes:content:pushType:)`, `.activities`, `activity.content`, `.activityState` (iOS 16.2) | T6 | isolement `@MainActor` annoncé par le SDK ; `request` lève une erreur en arrière-plan | appels synchrones déjà `@MainActor` dans la passerelle ; démarrage seulement avec `canStart` (premier plan), erreur journalisée |
| `activity.update(_:)`, `activity.end(_:dismissalPolicy:)` (async) en Swift 6 | T6 | `Activity` non Sendable traversant un acteur | passerelle non isolée qui ne fait circuler que des valeurs Sendable ; sinon `@preconcurrency import ActivityKit`, puis `update`/`end` en `@MainActor` |
| `ActivityState` (`.active`, `.stale`, `.ended`, `.dismissed`) | T6 | cas nouveau (iOS 26) ou `.stale` absent | `@unknown default` → « en cours » ; `.stale` retiré du `case` si besoin |
| `ActivityUIDismissalPolicy.after(_:)` / `.immediate` | T6 | — | API stable depuis iOS 16.1 |
| Retrait à la main détecté par réconciliation | T2, T6 | `Activity.activities` momentanément vide au lancement → retraits fantômes | marques purgées en 24 h ; « Épingler » annule un retrait ; noté pour la checklist (T8, n° 8) |
| `ActivityConfiguration(for:content:dynamicIsland:)`, `DynamicIsland { … } compactLeading:compactTrailing:minimal:`, `DynamicIslandExpandedRegion`, `.keylineTint`, `.activityBackgroundTint`, `.activitySystemActionForegroundColor` | T5 | déjà compilés sous cette forme par la sonde de l'étape 0 (sauf `keylineTint` et les teintes) ; Swift 6 dans l'extension | `@preconcurrency import ActivityKit`, puis le repli Swift 5 de l'étape 3 |
| `ActivityViewContext.isStale` (iOS 16.2) | T5 | — | `Date() >= context.state.staleDate` |
| `Text(date, style: .timer)` dans une Live Activity | T4 | le minuteur prend toute la largeur | largeur fixe (52 pt) ; sinon `Text(timerInterval:countsDown:)` (T8) |
| `Text(date, style: .relative)` (« màj il y a X min ») | T4 | secondes affichées, langue du simulateur | planches en `fr_FR` ; repli `Text(timerInterval:)` (T8) |
| `Scene.backgroundTask(.appRefresh(_:))` + `BGTaskScheduler.submit` | T7 | isolement de la fermeture en Swift 6 ; `submit` lève une erreur sur simulateur | appel d'une fonction `@MainActor` avec `await` ; erreur journalisée ; repli UIKit `BGTaskScheduler.register` dans un `UIApplicationDelegateAdaptor` |
| `UIBackgroundModes: [fetch]`, `BGTaskSchedulerPermittedIdentifiers` (XcodeGen) | T7 | clé mal placée | vérifiées par la CI (PlistBuddy) et par un test hébergé |
| `UIApplication.beginBackgroundTask(withName:expirationHandler:)` | T7 | fermeture d'expiration non isolée | `Task { @MainActor in … }` dans la fermeture |
| `ImageRenderer` (`Grid`, minuteurs, `proposedSize` implicite) | T4 | planche vide ou `Grid` mal rendu | `Snapshot.write` (drawHierarchy) ; `VStack` de `HStack` au lieu de `Grid` |
| `withTaskGroup` dans une classe `@MainActor` | T3 | capture de `self` | `self` est Sendable (classe isolée à l'acteur principal) ; repli `async let` |
| Mises à jour en arrière-plan | T7, T8 | iOS n'accorde aucun réveil (économie d'énergie, appli peu utilisée) | limite assumée sans push : « pas fraîche » honnête ; phase 2 (spec §12) |
