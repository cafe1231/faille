# Étape 3 — Les widgets : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** remplacer le widget sonde de l'étape 0 par les cinq widgets de Faille — écran verrouillé en ligne, rectangulaire et rond (compte à rebours) ; écran d'accueil petit (équipe choisie par AppIntent) et moyen — qui lisent les fichiers de l'appli dans le groupe d'apps, respectent l'anti-spoiler partout, et sont visibles en PNG depuis Windows. Terminé quand les widgets sont justes sur l'iPhone et que leurs aperçus PNG sortent de la CI (spec §13, étape 3).

**Architecture :** toute la logique pure va dans LoLKit (`Widget/`) et se teste sur Windows : `WidgetTimeline` projette le cache de l'appli (calendrier, direct, équipes suivies, matchs révélés) à n'importe quelle date en passant par `TeamCards`, `Presenter.scoreLine` et `Presenter.nextLine` (donc l'anti-spoiler de l'appli), et `WidgetText` écrit les textes de chaque famille. Les vues des widgets sont de simples vues SwiftUI dans `Shared/Widgets/` (compilées dans l'appli ET l'extension), ce qui permet de les rendre en PNG par `ImageRenderer` dans les tests hébergés. L'extension `FailleWidgets` reste fine : fournisseurs de planning, intent de configuration, configurations WidgetKit, lecture seule du groupe d'apps.

**Tech Stack :** Swift 6.2, SwiftUI iOS 26, WidgetKit (`StaticConfiguration`, `AppIntentConfiguration`, familles `accessory*` et `system*`, `containerBackground(for: .widget)`), AppIntents (`WidgetConfigurationIntent`, `AppEntity`, `EntityQuery`), Swift Testing, XcodeGen, GitHub Actions `macos-26` (Xcode 26), Docker `swift:6.2`, AltServer.

**Spec :** `docs/superpowers/specs/2026-10-13-faille-design.md` (§4.4, §7, §8, §9, §11.3, §13). Maquettes : `docs/maquettes/ecran-verrouille.html` (① widgets de l'écran verrouillé, ③ widgets de l'écran d'accueil). Contexte : `docs/superpowers/notes/2026-10-etape-0-verdict.md` (AltServer, groupe renommé), `.superpowers/sdd/2026-10-13-etape-2-appli/progress.md` (Rulings 14-18, F1-F9).

## Global Constraints

- iOS minimum **26.0** ; iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) ; version **0.1.0** dans les deux cibles.
- **Aucun code ne suppose un bundle ID ni un nom de groupe** (AltServer : `com.cafe1231.faille.<TEAMID>`, `group.com.cafe1231.faille.<TEAMID>`) : l'extension lit `AppGroup.directory` (résolu à l'exécution) avec `FileStore(directory: AppGroup.directory, readOnly: true)`.
- L'extension **n'écrit jamais** : ni fichier, ni mise de côté, ni dossier ; elle n'appelle **jamais** l'API.
- Fichiers lus (dans `<conteneur>/Faille/`) : `follows.json` (`FollowList`), `settings.json` (`AppSettings`), `cache-schedule.json` (`Cached<SchedulePage>`), `cache-live.json` (`Cached<[MatchEvent]>`) ; `JSONEncoder()` / `JSONDecoder()` par défaut.
- LoLKit n'importe que `Foundation` ; toute logique pure nouvelle y va, testée par Swift Testing via `bash scripts/lolkit.sh test` (Docker Desktop doit tourner).
- **Aucune dépendance externe** (seul paquet : LoLKit local).
- Langage : appli et tests de l'appli en **Swift 6** ; extension `FailleWidgets` en **Swift 6 à partir de la Task 6** (repli documenté : Swift 5) ; tout fichier de `Shared/` compile dans les deux cibles.
- Le code iOS ne se compile **qu'en CI** : vérification d'une tâche iOS = commit, `git push origin main`, `gh run watch --exit-status <id>` sur le workflow `iOS` ; logs d'échec par `gh run view <id> --log-failed`.
- Anti-spoiler (spec §8) : tout texte de widget vient d'une `WidgetLine` / `WidgetTeam` construite par `WidgetTimeline` à partir de `Presenter.scoreLine` et `Presenter.nextLine` ; jamais `TeamCard.next` ni `MatchTeam.gameWins` directement. Un match masqué ne montre que « En direct » (ou sa date s'il est à venir) ; une équipe dont le dernier match est masqué montre « Prochain · masqué ».
- Widgets (spec §7) : kind `FailleLockScreen` (`.accessoryInline`, `.accessoryRectangular`, `.accessoryCircular`), kind `FailleTeam` (`.systemSmall`, `AppIntentConfiguration`, défaut = première équipe suivie), kind `FailleTeams` (`.systemMedium`, 4 lignes au plus).
- Planning (spec §7) : une entrée à chaque début de match à venir d'une équipe suivie (plus les paliers du compte à rebours et les fins de confiance du direct), rechargement `.after(min(prochain début, maintenant + 30 min))` ; « en direct » n'est cru que si la donnée a au plus `RefreshPolicy.liveTrust` = 600 s.
- Écran verrouillé : rendu monochrome par iOS — Sora + icônes, niveaux `.primary` / `.secondary` seulement, **aucune couleur d'équipe**. Écran d'accueil : DA (abysse `#0B1020`, nappes, teinte d'équipe) posée par `containerBackground(for: .widget)`.
- Widgets : **pas de logos**, un monogramme (code dans un badge à la couleur de l'équipe, spec §4.4) ; pas de `glassEffect`, pas de matière (`.ultraThinMaterial`).
- DA (spec §9) : texte `#E9EEFB`, secondaire `#94A0BF`, accent `#6FD3FF` ; Sora variable (axe `wght`) ; icônes au trait du catalogue `Resources/Assets.xcassets`, **jamais d'emoji**.
- Aperçus : `build/apercus/09-widgets-verrouille.png` et `build/apercus/10-widgets-accueil.png` dans l'artefact `Faille-apercus` ; chaque capture passe `ApercuTests.expectNotBlank` (> 100 000 octets).
- La Live Activity sonde (`ProbeLiveActivity`, `Widgets/ProbeAttributes.swift`) reste compilée : l'étape 4 la remplace.
- Textes de l'interface en français ; identifiants de code en anglais ; commentaires en français ; fins de ligne LF.
- Commits avec l'adresse noreply déjà configurée ; chaque message se termine par un second `-m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Pousser sur `main` est autorisé.

## Décisions prises par ce plan (au-delà de la spec)

- **Dettes de l'étape 2 réglées ici** : `reorder` devient une fonction publique de LoLKit (même signature), `lastRowText` devient `Format.lastRow`, et les libellés masqués de la spec §8 deviennent `Format.maskedStatus` (appli et widgets les partagent). Le log de `LossyArray` (M14, optionnel) n'est **pas** fait : LoLKit n'a pas de canal de log et ce n'est pas nécessaire aux widgets.
- **Le cache vieillit pendant que l'appli dort** : à la date d'une entrée, le direct en cache n'est cru que s'il a ≤ 600 s (`RefreshPolicy.usableLive`) ; à défaut, les matchs en cours d'un calendrier de ≤ 600 s servent de repli (comme l'appli) ; sinon personne n'est « en direct ». Un match **commencé** dont aucune donnée fraîche ne parle (en cours dans un vieux calendrier, ou heure de début passée) a une issue inconnue : il n'est ni en direct ni à venir, mais compte comme **dernier match** de ses équipes (une équipe en anti-spoiler garde donc « Prochain · masqué », règle F1). Conséquence assumée : sans appli ouverte récemment, un match en cours n'apparaît pas comme « en direct » dans les widgets (la Live Activity de l'étape 4 couvre le direct).
- **Entrées** : maintenant ; chaque début de match à venir d'une équipe suivie ; les paliers du compte à rebours (chaque heure pleine avant le début, puis toutes les 5 min pendant la dernière heure) ; la fin de confiance du direct et du calendrier ; le tout sur 6 h (filet si iOS tarde à recharger).
- **Rechargements** : l'appli recharge les widgets après chaque calendrier **ou direct** relu avec succès (au plus une fois par cycle), à chaque sauvegarde des équipes suivies (déjà fait) et des réglages (une révélation se voit tout de suite). Au premier plan, iOS ne décompte pas ces rechargements de leur budget.
- Les lignes « prochain match » de tous les widgets passent par `Presenter.nextLine` **équipe par équipe**, comme les cartes de l'appli. Limite héritée de F1, signalée et non corrigée ici (elle touche l'appli autant que les widgets) : le prochain match d'une équipe **non masquée** contre une équipe en anti-spoiler (« GEN vs T1 ») reste annoncé, et son existence peut trahir le résultat du match masqué de T1.
- Une seule kind pour les trois widgets de l'écran verrouillé (le contenu dépend de la famille) ; petit et moyen sont deux kinds séparées (seul le petit se configure).
- Jauge du widget rond : elle se remplit pendant les 24 h qui précèdent le match ; en direct, elle est pleine avec l'icône « en direct ».
- Icône du widget en ligne redessinée à 14 pt (`InlineIcon`) : iOS affiche l'image d'un widget en ligne à sa taille propre.
- Sora et le catalogue d'icônes : tout le dossier `Resources/` est ajouté à l'extension (police, licence OFL, catalogue), `UIAppFonts` dans son Info.plist, vérifiés par la CI dans l'`.appex`.
- **Aperçus** : un PNG d'un seul widget pèserait moins de 100 000 octets (calcul sur un rendu équivalent : ~92 Ko pour un petit widget à ×3) et échouerait à `expectNotBlank` ; on rend donc deux **planches** (écran verrouillé, écran d'accueil ; chaque famille dans plusieurs états) avec `ImageRenderer` à ×3 (~0,5 Mo estimés), plus un contrôle par famille (« la vue dessine quelque chose » : part de pixels non transparents > 1 %).
- Extension passée en **Swift 6** (Task 6), avec repli explicite en Swift 5 si un protocole WidgetKit/AppIntents refuse la conformité en concurrence stricte.

## Structure des fichiers

```
LoLKit/Sources/LoLKit/
├─ Follow/DisplayOrder.swift           (T1, modifié) + reorder(_:_:) public (déplacé de l'appli)
├─ Presentation/AppFormat.swift        (T1, modifié) + Format.maskedStatus, Format.lastRow (déplacé de l'appli)
├─ Presentation/Format.swift           (T3, modifié) + Format.day, Format.shortDate
├─ Widget/WidgetContent.swift          (T2) WidgetInput, WidgetLine, WidgetTeam, WidgetContent
├─ Widget/WidgetTimeline.swift         (T2) contenu à une date, dates des entrées, date de rechargement
└─ Widget/WidgetText.swift             (T3) textes de chaque famille (en ligne, rectangulaire, rond, ligne, petit)
LoLKit/Tests/LoLKitTests/
├─ CardTextTests.swift                 (T1)
├─ WidgetTimelineTests.swift           (T2)
└─ WidgetTextTests.swift               (T3)

App/Matches/MatchParts.swift           (T1, modifié) reorder retiré ; maskedText s'appuie sur Format.maskedStatus
App/Matches/TeamCardView.swift         (T1, modifié) lastRowText retiré → Format.lastRow
App/Store/AppStore.swift               (T4, modifié) reloadWidgets() : calendrier/direct relus, équipes, réglages
project.yml                            (T4) Resources + UIAppFonts dans l'extension ; (T6) extension en Swift 6
.github/workflows/ios.yml              (T4, T6) vérifie police, catalogue (et métadonnées AppIntents) dans l'.appex

Shared/                                compilé dans l'appli ET l'extension
├─ Widgets/WidgetInput+Files.swift     (T4) lecture seule des fichiers de l'appli → WidgetInput
├─ Widgets/WidgetChrome.swift          (T5) WidgetBackdrop, MonogramBadge, InlineIcon
├─ Widgets/AccessoryWidgetViews.swift  (T5) InlineWidgetView, RectangularWidgetView, CircularWidgetView
├─ Widgets/HomeWidgetViews.swift       (T5) SmallWidgetView, MediumWidgetView
└─ Preview/WidgetSamples.swift         (T5) contenus d'exemple (galerie, aperçus PNG)

Widgets/                               extension FailleWidgets
├─ FailleWidgets.swift                 (T6, réécrit) WidgetBundle ; widget sonde retiré ; ProbeLiveActivity gardée
├─ WidgetTimelines.swift               (T6) FailleEntry, TeamEntry, FailleTimeline, FailleProvider, TeamProvider
├─ SelectTeamIntent.swift              (T6) SelectTeamIntent, TeamEntity, TeamQuery
├─ LockScreenWidget.swift              (T6) kind FailleLockScreen
├─ HomeWidgets.swift                   (T6) kinds FailleTeam et FailleTeams
└─ ProbeAttributes.swift               (inchangé) attributs de la Live Activity sonde

Tests/FailleTests/
├─ MatchCardTextTests.swift            (T1, modifié) lastRowText → Format.lastRow
├─ WidgetDataTests.swift               (T4) lecture des fichiers, rechargements des widgets
├─ Support/WidgetBoard.swift           (T5) tailles, planches, rendu ImageRenderer, part de pixels dessinés
└─ WidgetSnapshotTests.swift           (T5) 09-widgets-verrouille.png, 10-widgets-accueil.png, contrôle par famille

docs/superpowers/notes/2026-10-etape-3-verdict.md   (T7) résultats sur l'iPhone
```

## Commandes de vérification CI (rappel, utilisées dans chaque tâche)

Après `git push origin main` :

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
```

Expected : un identifiant numérique. Vide → le run n'est pas encore enregistré : relancer la commande quelques secondes plus tard. Puis `gh run watch --exit-status <id>` (Expected : tous les jobs verts ; la file d'attente des runners macOS peut durer 15 min). En cas d'échec : `gh run view <id> --log-failed`, corriger, nouveau commit, recommencer. Pour LoLKit, même chose avec `--workflow LoLKit` (déclenché seulement si `LoLKit/**` change).

Télécharger les aperçus d'un run (tâches d'interface) :

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

L'exécutant vérifie la **présence** et la taille des PNG nommés et les copie dans `.superpowers/apercus/` ; le jugement visuel revient au contrôleur et à Dan.

---

### Task 1 : `reorder`, ligne « Dernier » et libellés masqués dans LoLKit

Dettes de l'étape 2 (Ruling 18) : la logique pure des cartes passe dans LoLKit, testée sur Windows, pour que les widgets la réutilisent.

**Files :**
- Modify : `LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift` (ajout en fin de fichier)
- Modify : `LoLKit/Sources/LoLKit/Presentation/AppFormat.swift` (ajout avant `static func twoDigits`)
- Create : `LoLKit/Tests/LoLKitTests/CardTextTests.swift`
- Modify : `App/Matches/MatchParts.swift:4-8` (suppression) et `:41-49` (`maskedText`)
- Modify : `App/Matches/TeamCardView.swift:4-13` (suppression) et `:143` (appel)
- Modify : `Tests/FailleTests/MatchCardTextTests.swift:36, 91, 103`

**Interfaces :**
- Consumes : `ScoreLine(matchId:leagueName:bestOf:teamCodes:score:status:isMasked:)` et `ScoreLine.Status.finished(winnerCode:)` (LoLKit `Presentation/SpoilerPolicy.swift`) ; `LiveMatchState.Phase` (`.upcoming`, `.inGame`, `.betweenGames`, `.finished`).
- Produces :
  - `public func reorder<T>(_ values: [T], _ order: [Int]) -> [T]?` (module LoLKit, fonction libre)
  - `Format.maskedStatus(_ phase: LiveMatchState.Phase) -> String` — « En direct » / « Terminé » / « À venir »
  - `Format.lastRow(_ line: ScoreLine, order: [Int], date: String) -> String`

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/CardTextTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Pièces de texte des cartes, déplacées de l'appli vers LoLKit à l'étape 3 (les widgets les réutilisent).
@Suite struct CardTextTests {
    @Test func reorderFollowsTheDisplayOrder() {
        #expect(reorder(["C9", "KC"], [1, 0]) == ["KC", "C9"])
        #expect(reorder([0, 1], [1, 0]) == [1, 0])
        #expect(reorder(["KC"], [0, 1]) == nil)          // tailles différentes
        #expect(reorder(["KC", "C9"], [0, 2]) == nil)    // index hors du tableau
    }

    /// Spec §8 : un match masqué n'affiche que son état ; entre deux games, il reste « En direct ».
    @Test func maskedStatusIsOnlyTheState() {
        #expect(Format.maskedStatus(.inGame) == "En direct")
        #expect(Format.maskedStatus(.betweenGames) == "En direct")
        #expect(Format.maskedStatus(.finished) == "Terminé")
        #expect(Format.maskedStatus(.upcoming) == "À venir")
    }

    private func finished(score: [Int]?, masked: Bool) -> ScoreLine {
        ScoreLine(matchId: "m", leagueName: "Mondial", bestOf: 5, teamCodes: ["HLE", "GEN"], score: score,
                  status: .finished(winnerCode: masked ? nil : "GEN"), isMasked: masked)
    }

    @Test func lastRowPutsTheCardTeamOnTheLeftWithItsScore() {
        #expect(Format.lastRow(finished(score: [0, 3], masked: false), order: [1, 0], date: "DATE")
                == "Dernier · GEN 3 – 0 HLE")
        #expect(Format.lastRow(finished(score: [0, 3], masked: false), order: [0, 1], date: "DATE")
                == "Dernier · HLE 0 – 3 GEN")
    }

    @Test func maskedLastRowHasNoResultButTheDate() {
        let text = Format.lastRow(finished(score: nil, masked: true), order: [1, 0], date: "sam. 11 oct. · 09:00")
        #expect(text == "Dernier · GEN vs HLE · Terminé · sam. 11 oct. · 09:00")
        #expect(!text.contains("–"))
    }
}
```

- [ ] **Step 2 : Lancer le test, vérifier qu'il échoue**

Run : `bash scripts/lolkit.sh test --filter CardTextTests`
Expected : FAIL à la compilation — `cannot find 'reorder' in scope` et `type 'Format' has no member 'maskedStatus'` / `'lastRow'`.

- [ ] **Step 3 : Implémenter `reorder`**

Ajouter à la fin de `LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift` (après la fermeture de `extension FollowList`) :

```swift

/// Remet des valeurs d'un match (codes, score, stats) dans l'ordre d'affichage donné par `displayOrder` ;
/// nil si les tailles ne correspondent pas ou si un index sort du tableau.
public func reorder<T>(_ values: [T], _ order: [Int]) -> [T]? {
    guard values.count == order.count, order.allSatisfy({ values.indices.contains($0) }) else { return nil }
    return order.map { values[$0] }
}
```

- [ ] **Step 4 : Implémenter `Format.maskedStatus` et `Format.lastRow`**

Dans `LoLKit/Sources/LoLKit/Presentation/AppFormat.swift`, insérer juste avant la ligne `    static func twoDigits(_ value: Int) -> String {` :

```swift
    /// Seul état qu'affiche un match masqué (spec §8) : « En direct » (entre deux games aussi : le nombre de pauses
    /// trahirait la longueur de la série), « Terminé » ou « À venir ».
    public static func maskedStatus(_ phase: LiveMatchState.Phase) -> String {
        switch phase {
        case .inGame, .betweenGames: return "En direct"
        case .finished: return "Terminé"
        case .upcoming: return "À venir"
        }
    }

    /// Ligne « Dernier » d'une carte (spec §5.1, §8) : « Dernier · GEN 3 – 0 HLE » ; sans score (match masqué) :
    /// « Dernier · T1 vs GEN · Terminé · sam. 11 oct. · 09:00 » — ni résultat ni vainqueur, seulement l'état et la date.
    /// Le score vient de `ScoreLine` (donc de `SpoilerPolicy`) ; `order` est l'ordre d'affichage (`displayOrder`).
    public static func lastRow(_ line: ScoreLine, order: [Int], date: String) -> String {
        let codes = reorder(line.teamCodes, order) ?? line.teamCodes
        if let score = line.score.flatMap({ reorder($0, order) }), score.count == 2, codes.count == 2 {
            return "Dernier · \(codes[0]) \(score[0]) – \(score[1]) \(codes[1])"
        }
        return "Dernier · \(codes.joined(separator: " vs ")) · \(maskedStatus(.finished)) · \(date)"
    }

```

- [ ] **Step 5 : Lancer les tests, vérifier qu'ils passent**

Run : `bash scripts/lolkit.sh test --filter CardTextTests` → Expected : PASS (4 tests).
Run : `bash scripts/lolkit.sh test` → Expected : aucun échec, `Test run with N tests … passed` avec N = total précédent (152) + 4.

- [ ] **Step 6 : L'appli utilise LoLKit — `MatchParts.swift`**

Dans `App/Matches/MatchParts.swift`, supprimer ces lignes (4 à 8, et la ligne vide qui suit) :

```swift
/// Remet des valeurs d'un match (score, stats) dans l'ordre d'affichage ; nil si les tailles ne correspondent pas.
func reorder<T>(_ values: [T], _ order: [Int]) -> [T]? {
    guard values.count == order.count, order.allSatisfy({ values.indices.contains($0) }) else { return nil }
    return order.map { values[$0] }
}
```

Puis remplacer :

```swift
    static func maskedText(phase: LiveMatchState.Phase, opponent: String?) -> String {
        let label: String
        switch phase {
        case .inGame, .betweenGames: label = "En direct"
        case .finished: label = "Terminé"
        case .upcoming: label = "À venir"
        }
        return opponent.map { "\(label) vs \($0)" } ?? label
    }
```

par :

```swift
    static func maskedText(phase: LiveMatchState.Phase, opponent: String?) -> String {
        let label = Format.maskedStatus(phase)
        return opponent.map { "\(label) vs \($0)" } ?? label
    }
```

(`MatchDetailView.swift` et `TeamCardView.swift` appellent toujours `reorder($0, order)` : c'est maintenant celui de LoLKit, même signature, déjà importé.)

- [ ] **Step 7 : L'appli utilise LoLKit — `TeamCardView.swift` et ses tests**

Dans `App/Matches/TeamCardView.swift`, supprimer le bloc des lignes 4 à 13 (doc + fonction) :

```swift
/// Texte de la ligne « Dernier » d'une carte : « Dernier · GEN 3 – 0 HLE » ; sans score (masqué, spec §8) :
/// « Dernier · T1 vs GEN · Terminé · sam. 11 oct. · 09:00 » (ni résultat ni vainqueur : seulement « Terminé » et la date).
/// Le score vient de `ScoreLine` (donc de `SpoilerPolicy`) ; `order` est l'ordre d'affichage (équipe de la carte à gauche).
func lastRowText(_ line: ScoreLine, order: [Int], date: String) -> String {
    let codes = reorder(line.teamCodes, order) ?? line.teamCodes
    if let score = line.score.flatMap({ reorder($0, order) }), score.count == 2, codes.count == 2 {
        return "Dernier · \(codes[0]) \(score[0]) – \(score[1]) \(codes[1])"
    }
    return "Dernier · \(codes.joined(separator: " vs ")) · Terminé · \(date)"
}

```

et remplacer, dans `lastRow(_:)` :

```swift
        let text = lastRowText(line, order: order, date: Format.matchDate(event.startTime))
```

par :

```swift
        let text = Format.lastRow(line, order: order, date: Format.matchDate(event.startTime))
```

Dans `Tests/FailleTests/MatchCardTextTests.swift`, remplacer les trois appels :
- ligne 36 : `let text = lastRowText(line, order: order, date: "DATE")` → `let text = Format.lastRow(line, order: order, date: "DATE")`
- ligne 91 : `let text = lastRowText(store.scoreLine(event), order: store.follows.displayOrder(event.match.teams, preferring: card.team),` → `let text = Format.lastRow(store.scoreLine(event), order: store.follows.displayOrder(event.match.teams, preferring: card.team),`
- ligne 103 : `#expect(lastRowText(store.scoreLine(event), order: order, date: "DATE") == "Dernier · GEN 3 – 0 HLE")` → `#expect(Format.lastRow(store.scoreLine(event), order: order, date: "DATE") == "Dernier · GEN 3 – 0 HLE")`

Vérifier qu'il ne reste rien : `grep -rn "lastRowText\|^func reorder" App Shared Widgets Tests` → Expected : aucune ligne.

- [ ] **Step 8 : Commit et push**

```bash
git add LoLKit/Sources/LoLKit/Follow/DisplayOrder.swift LoLKit/Sources/LoLKit/Presentation/AppFormat.swift LoLKit/Tests/LoLKitTests/CardTextTests.swift App/Matches/MatchParts.swift App/Matches/TeamCardView.swift Tests/FailleTests/MatchCardTextTests.swift
git commit -m "refactor(lolkit): reorder, ligne « Dernier » et libellés masqués passent dans LoLKit" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 9 : CI LoLKit et iOS**

```bash
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : LoLKit vert (Linux + macOS) ; iOS vert (`build` + `apercus`, `MatchCardTextTests` verts, 64 tests hébergés). Erreur probable : `ambiguous use of 'reorder'` → une copie de `reorder` est restée dans `App/` (Step 6).

---

### Task 2 : Planning des widgets (LoLKit)

**Files :**
- Create : `LoLKit/Sources/LoLKit/Widget/WidgetContent.swift`
- Create : `LoLKit/Sources/LoLKit/Widget/WidgetTimeline.swift`
- Create : `LoLKit/Tests/LoLKitTests/WidgetTimelineTests.swift`

**Interfaces :**
- Consumes (vérifiées dans les sources) :
  - `TeamCards.build(follows: FollowList, schedule: [MatchEvent], live: [MatchEvent]?, revealed: Set<String>) -> [TeamCard]` ; `TeamCard.team`, `.live`
  - `Presenter.nextLine(for card: TeamCard, follows: FollowList, revealed: Set<String>) -> NextLine` (`.hidden`, `.none`, `.match(MatchEvent)`)
  - `Presenter.scoreLine(for event: MatchEvent, follows: FollowList, revealed: Set<String>) -> ScoreLine` (`.status` : `.upcoming(Date)`, `.live(gameNumber: Int?)`, `.finished(winnerCode:)` ; `.score: [Int]?` ; `.isMasked`)
  - `FollowList.displayOrder(_ teams: [MatchTeam], preferring: FollowedTeam?) -> [Int]` ; `FollowList.involves(_:)` ; `MatchTeam.isSame(as:)` ; `FollowedTeam.colorHex`
  - `reorder(_:_:)` (Task 1)
  - `RefreshPolicy.usableLive(_ cached: Cached<[MatchEvent]>?, now: Date) -> [MatchEvent]?` ; `RefreshPolicy.liveTrust` (600)
  - `Cached<Value>` (`value`, `fetchedAt`, `age(now:)`) ; `SchedulePage(leagueIds:events:)` ; `AppSettings(revealedMatchIds:)` / `.revealedMatchIds`
  - `MatchEvent(startTime:state:type:blockName:league:match:streams:)` ; `EventState` (`.unstarted`, `.inProgress`, `.completed`, `.unknown`)
- Produces :
  - `public struct WidgetInput: Sendable, Equatable` — `follows: FollowList`, `settings: AppSettings`, `schedule: Cached<SchedulePage>?`, `live: Cached<[MatchEvent]>?` ; `init(follows:settings:schedule:live:)` (tous avec défaut)
  - `public struct WidgetLine: Sendable, Equatable, Identifiable` — `matchId`, `leagueName`, `codes: [String]`, `colorHexes: [String?]`, `status: Status`, `isMasked: Bool` ; `enum Status { case live(score: [Int]?, gameNumber: Int?), upcoming(Date) }` ; `isLive: Bool`, `upcomingStart: Date?`, `id`
  - `public struct WidgetTeam: Sendable, Equatable, Identifiable` — `team: FollowedTeam`, `next: Next` ; `enum Next { case live(WidgetLine), match(WidgetLine), hidden, noMatch }`
  - `public struct WidgetContent: Sendable, Equatable` — `date: Date`, `teams: [WidgetTeam]` (ordre de suivi), `lines: [WidgetLine]` ; `headline: WidgetLine?` ; `team(id: String?) -> WidgetTeam?`
  - `WidgetTimeline.content(at: Date, input: WidgetInput) -> WidgetContent`
  - `WidgetTimeline.entryDates(now: Date, input: WidgetInput) -> [Date]`
  - `WidgetTimeline.reloadDate(now: Date, input: WidgetInput) -> Date`
  - constantes `WidgetTimeline.reloadInterval` (1 800 s), `.horizon` (21 600 s), `.countdownStep` (300 s)

- [ ] **Step 1 : Écrire les tests qui échouent**

Créer `LoLKit/Tests/LoLKitTests/WidgetTimelineTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Planning des widgets (spec §7) : quelles entrées, à quelles dates, et jamais de spoiler (spec §8).
@Suite struct WidgetTimelineTests {
    /// KC et GEN suivies ; T1 suivie en anti-spoiler. Forme `getSchedule` : sans id, les équipes se reconnaissent à leur nom.
    private let follows = FollowList(teams: [
        FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", autoColorHex: "#5B8CFF"),
        FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true, autoColorHex: "#FF5C7A"),
        FollowedTeam(id: "gen", code: "GEN", name: "Gen.G", autoColorHex: "#FFB454"),
    ])

    private func match(_ id: String, _ state: EventState, _ start: String, _ a: String, _ b: String,
                       wins: [Int] = [0, 0]) -> MatchEvent {
        let names = ["KC": "Karmine Corp", "T1": "T1", "GEN": "Gen.G"]
        return makeEvent(id: id, state: state, start: start,
                         teams: [makeTeam(a, name: names[a], wins: wins[0]), makeTeam(b, name: names[b], wins: wins[1])])
    }

    /// Fichiers de l'appli : calendrier (et direct, s'il est donné) relus à `fetchedAt`.
    private func input(_ schedule: [MatchEvent], fetchedAt: String, live: [MatchEvent]? = nil,
                       revealed: Set<String> = []) -> WidgetInput {
        WidgetInput(
            follows: follows,
            settings: AppSettings(revealedMatchIds: revealed),
            schedule: Cached(value: SchedulePage(leagueIds: [], events: schedule), fetchedAt: date(fetchedAt)),
            live: live.map { Cached(value: $0, fetchedAt: date(fetchedAt)) }
        )
    }

    /// Heures du 15 octobre 2026 (UTC) : `times(["12:00:00"])`.
    private func times(_ values: [String]) -> [Date] {
        values.map { date("2026-10-15T\($0)Z") }
    }

    private var kcG2: MatchEvent { match("kc-g2", .unstarted, "2026-10-15T18:00:00Z", "KC", "G2") }
    private var genFur: MatchEvent { match("gen-fur", .unstarted, "2026-10-16T09:00:00Z", "GEN", "FUR") }
    /// En cours, C9 à gauche dans l'API : KC mène 1 – 0, game 2.
    private var kcC9: MatchEvent { match("kc-c9", .inProgress, "2026-10-15T16:00:00Z", "C9", "KC", wins: [0, 1]) }
    /// En cours et masqué (T1 en anti-spoiler).
    private var t1Fly: MatchEvent { match("t1-fly", .inProgress, "2026-10-15T17:00:00Z", "T1", "FLY", wins: [1, 0]) }
    private var t1Gen: MatchEvent { match("t1-gen", .unstarted, "2026-10-17T12:00:00Z", "T1", "GEN") }

    // MARK: Contenu à une date

    @Test func upcomingMatchesAreListedByStartTime() throws {
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([genFur, kcG2], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.map(\.matchId) == ["kc-g2", "gen-fur"])
        let first = try #require(content.headline)
        #expect(first.status == .upcoming(date("2026-10-15T18:00:00Z")))
        #expect(first.codes == ["KC", "G2"])
        #expect(first.colorHexes == ["#5B8CFF", nil])
        #expect(!first.isMasked)
        #expect(content.team(id: "gen")?.next == .match(content.lines[1]))
        #expect(content.team(id: "t1")?.next == .noMatch)
    }

    @Test func liveMatchComesFirstWithItsScoreInDisplayOrder() throws {
        let content = WidgetTimeline.content(at: date("2026-10-15T16:15:00Z"),
                                             input: input([kcC9, genFur], fetchedAt: "2026-10-15T16:10:00Z", live: [kcC9]))
        #expect(content.lines.map(\.matchId) == ["kc-c9", "gen-fur"])
        let live = try #require(content.headline)
        #expect(live.status == .live(score: [1, 0], gameNumber: 2))
        #expect(live.codes == ["KC", "C9"])
        #expect(content.team(id: "kc")?.next == .live(live))
    }

    @Test func maskedLiveMatchShowsNeitherScoreNorGameAndHidesTheNextMatch() throws {
        let content = WidgetTimeline.content(
            at: date("2026-10-15T17:05:00Z"),
            input: input([t1Fly, genFur, t1Gen], fetchedAt: "2026-10-15T17:00:00Z", live: [t1Fly]))
        let masked = try #require(content.headline)
        #expect(masked.matchId == "t1-fly")
        #expect(masked.status == .live(score: nil, gameNumber: nil))
        #expect(masked.isMasked)
        #expect(content.team(id: "t1")?.next == .live(masked))
        // « T1 vs GEN » n'est annoncé nulle part : le match en direct de T1 est masqué.
        #expect(content.lines.map(\.matchId) == ["t1-fly", "gen-fur"])
    }

    @Test func aMatchWhoseStartHasPassedIsNoLongerUpcoming() {
        let content = WidgetTimeline.content(at: date("2026-10-15T18:00:00Z"),
                                             input: input([kcG2, genFur], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.map(\.matchId) == ["gen-fur"])
        #expect(content.team(id: "kc")?.next == .noMatch)
    }

    @Test func liveDataOlderThanTenMinutesIsNotTrusted() {
        let input = input([kcC9, genFur], fetchedAt: "2026-10-15T16:10:00Z", live: [kcC9])
        #expect(WidgetTimeline.content(at: date("2026-10-15T16:20:00Z"), input: input).headline?.matchId == "kc-c9")
        let later = WidgetTimeline.content(at: date("2026-10-15T16:20:01Z"), input: input)
        #expect(later.lines.map(\.matchId) == ["gen-fur"])
        #expect(later.team(id: "kc")?.next == .noMatch)
    }

    @Test func aFreshScheduleStandsInForAMissingLive() {
        let input = input([kcC9, genFur], fetchedAt: "2026-10-15T16:10:00Z")   // pas de cache du direct
        #expect(WidgetTimeline.content(at: date("2026-10-15T16:15:00Z"), input: input).headline?.status
                == .live(score: [1, 0], gameNumber: 2))
        #expect(WidgetTimeline.content(at: date("2026-10-15T16:25:00Z"), input: input).headline?.matchId == "gen-fur")
    }

    /// Le calendrier date du match T1 – FLY (masqué) ; le lendemain, rien ne dit qu'il est fini : la ligne « Prochain »
    /// de T1 reste masquée (règle F1), et « T1 vs GEN » n'est pas annoncé.
    @Test func aMaskedMatchPresumedOverKeepsTheNextLineHidden() {
        let content = WidgetTimeline.content(at: date("2026-10-16T05:00:00Z"),
                                             input: input([t1Fly, genFur, t1Gen], fetchedAt: "2026-10-15T17:05:00Z"))
        #expect(content.team(id: "t1")?.next == .hidden)
        #expect(content.lines.map(\.matchId) == ["gen-fur"])
    }

    @Test func revealingTheMaskedMatchBringsTheNextMatchBack() throws {
        let content = WidgetTimeline.content(
            at: date("2026-10-16T05:00:00Z"),
            input: input([t1Fly, genFur, t1Gen], fetchedAt: "2026-10-15T17:05:00Z", revealed: ["t1-fly"]))
        #expect(content.lines.map(\.matchId) == ["gen-fur", "t1-gen"])
        let next = try #require(content.lines.last)
        #expect(next.codes == ["T1", "GEN"])
        #expect(next.isMasked)   // T1 reste en anti-spoiler : à venir, rien à cacher
        #expect(content.team(id: "t1")?.next == .match(next))
    }

    @Test func aMatchBetweenTwoFollowedTeamsIsListedOnce() throws {
        let kcGen = match("kc-gen", .unstarted, "2026-10-15T18:00:00Z", "GEN", "KC")
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([kcGen], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.count == 1)
        let line = try #require(content.headline)
        #expect(line.codes == ["KC", "GEN"])                 // carte de KC (suivie avant GEN)
        #expect(line.colorHexes == ["#5B8CFF", "#FFB454"])
        guard case let .match(genLine)? = content.team(id: "gen")?.next else {
            Issue.record("GEN n'annonce pas son prochain match")
            return
        }
        #expect(genLine.codes == ["GEN", "KC"])              // le petit widget de GEN met GEN à gauche
    }

    @Test func smallWidgetDefaultsToTheFirstFollowedTeam() {
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.teams.map(\.team.id) == ["kc", "t1", "gen"])
        #expect(content.team(id: nil)?.team.id == "kc")
        #expect(content.team(id: "gen")?.team.id == "gen")
        #expect(content.team(id: "plus-suivie")?.team.id == "kc")
        #expect(WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"), input: WidgetInput()).team(id: nil) == nil)
    }

    // MARK: Dates des entrées et rechargement

    @Test func entriesAtTheStartAndAtEachCountdownStep() {
        let kc = match("kc-g2", .unstarted, "2026-10-15T14:00:00Z", "KC", "G2")
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T12:00:00Z"),
                                              input: input([kc], fetchedAt: "2026-10-15T11:30:00Z"))
        #expect(dates == times(["12:00:00", "13:00:00", "13:05:00", "13:10:00", "13:15:00", "13:20:00", "13:25:00",
                                "13:30:00", "13:35:00", "13:40:00", "13:45:00", "13:50:00", "13:55:00", "14:00:00"]))
    }

    @Test func aFarMatchOnlyAddsItsHourlyStepsWithinTheHorizon() {
        // GEN vs FUR est 21 h plus tard : seules ses heures pleines tombent dans les 6 h couvertes.
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T12:00:00Z"),
                                              input: input([genFur], fetchedAt: "2026-10-15T11:30:00Z"))
        #expect(dates == times(["12:00:00", "13:00:00", "14:00:00", "15:00:00", "16:00:00", "17:00:00", "18:00:00"]))
    }

    @Test func theEndOfLiveTrustIsAnEntry() {
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T16:15:00Z"),
                                              input: input([kcC9], fetchedAt: "2026-10-15T16:10:00Z", live: [kcC9]))
        #expect(dates == times(["16:15:00", "16:20:01"]))
    }

    @Test func reloadAtTheNextStartOrWithinThirtyMinutes() {
        let now = date("2026-10-15T12:00:00Z")
        let later = match("kc-g2", .unstarted, "2026-10-15T14:00:00Z", "KC", "G2")
        let soon = match("kc-g2", .unstarted, "2026-10-15T12:10:00Z", "KC", "G2")
        let others = makeEvent(id: "g2-fnc", state: .unstarted, start: "2026-10-15T12:05:00Z",
                               teams: [makeTeam("G2"), makeTeam("FNC")])
        #expect(WidgetTimeline.reloadDate(now: now, input: input([later], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:30:00Z"))
        #expect(WidgetTimeline.reloadDate(now: now, input: input([soon], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:10:00Z"))
        #expect(WidgetTimeline.reloadDate(now: now, input: input([], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:30:00Z"))
        // Un match d'équipes non suivies ne compte pas.
        #expect(WidgetTimeline.reloadDate(now: now, input: input([others], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:30:00Z"))
    }

    // MARK: Anti-spoiler sur tout le planning

    @Test func noEntryEverShowsAMaskedScoreOrTheNextMatchOfAMaskedTeam() {
        let input = input([t1Fly, genFur, t1Gen, kcC9], fetchedAt: "2026-10-15T17:00:00Z", live: [t1Fly, kcC9])
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T17:05:00Z"), input: input)
        #expect(dates.count > 2)
        for entry in dates {
            let content = WidgetTimeline.content(at: entry, input: input)
            for line in content.lines where line.isMasked {
                if case let .live(score, game) = line.status {
                    #expect(score == nil && game == nil)
                }
            }
            switch content.team(id: "t1")?.next {
            case let .live(line)?:
                #expect(line.isMasked && line.status == .live(score: nil, gameNumber: nil))
            case .hidden?:
                break
            default:
                Issue.record("T1 annonce autre chose que « En direct » masqué ou « Prochain · masqué » à \(entry)")
            }
        }
    }
}
```

- [ ] **Step 2 : Lancer les tests, vérifier qu'ils échouent**

Run : `bash scripts/lolkit.sh test --filter WidgetTimelineTests`
Expected : FAIL à la compilation — `cannot find 'WidgetInput' in scope`, `cannot find 'WidgetTimeline' in scope`.

- [ ] **Step 3 : Écrire les modèles**

Créer `LoLKit/Sources/LoLKit/Widget/WidgetContent.swift` :

```swift
import Foundation

/// Ce que les widgets lisent dans le groupe d'apps (spec §4.4, §7) : les fichiers de l'appli, tels quels.
/// L'extension n'appelle jamais l'API : tout ce qu'elle montre vient d'ici.
public struct WidgetInput: Sendable, Equatable {
    public var follows: FollowList
    /// `settings.json` : seuls les matchs révélés (`revealedMatchIds`) comptent pour les widgets.
    public var settings: AppSettings
    /// `cache-schedule.json` ; nil tant que l'appli n'a jamais chargé le calendrier.
    public var schedule: Cached<SchedulePage>?
    /// `cache-live.json` ; sa fraîcheur est jugée à la date de chaque entrée (`RefreshPolicy.usableLive`).
    public var live: Cached<[MatchEvent]>?

    public init(follows: FollowList = FollowList(), settings: AppSettings = AppSettings(),
                schedule: Cached<SchedulePage>? = nil, live: Cached<[MatchEvent]>? = nil) {
        self.follows = follows
        self.settings = settings
        self.schedule = schedule
        self.live = live
    }
}

/// Un match tel qu'un widget a le droit de l'afficher : l'anti-spoiler (spec §8) y est déjà appliqué.
public struct WidgetLine: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        /// En direct. Score de série et numéro de game dans l'ordre d'affichage ; tous deux nil si le match est masqué.
        case live(score: [Int]?, gameNumber: Int?)
        /// À venir, avec son heure de début.
        case upcoming(Date)
    }

    public let matchId: String
    public let leagueName: String
    /// Codes des équipes dans l'ordre d'affichage : l'équipe suivie à gauche (`FollowList.displayOrder`).
    public let codes: [String]
    /// Couleur de chaque équipe, dans le même ordre ; nil pour une équipe non suivie.
    public let colorHexes: [String?]
    public let status: Status
    /// Au moins une équipe du match est en anti-spoiler et le match n'a pas été révélé.
    public let isMasked: Bool

    public init(matchId: String, leagueName: String, codes: [String], colorHexes: [String?], status: Status,
                isMasked: Bool) {
        self.matchId = matchId
        self.leagueName = leagueName
        self.codes = codes
        self.colorHexes = colorHexes
        self.status = status
        self.isMasked = isMasked
    }

    public var id: String { matchId }

    public var isLive: Bool {
        if case .live = status { return true }
        return false
    }

    /// Heure de début d'un match à venir ; nil en direct.
    public var upcomingStart: Date? {
        if case let .upcoming(start) = status { return start }
        return nil
    }
}

/// Ce que le petit widget annonce pour une équipe suivie (spec §7).
public struct WidgetTeam: Sendable, Equatable, Identifiable {
    public enum Next: Sendable, Equatable {
        /// L'équipe joue en ce moment.
        case live(WidgetLine)
        /// Son prochain match (`Presenter.nextLine` = `.match`).
        case match(WidgetLine)
        /// Son dernier match est masqué : « Prochain · masqué », rien n'est annoncé (spec §8, règle F1).
        case hidden
        /// Aucun match à venir connu. (Pas `.none` : on le confondrait avec `Optional.none`.)
        case noMatch
    }

    public let team: FollowedTeam
    public let next: Next

    public init(team: FollowedTeam, next: Next) {
        self.team = team
        self.next = next
    }

    public var id: String { team.id }
}

/// Ce que montrent les widgets à une date donnée.
public struct WidgetContent: Sendable, Equatable {
    /// Date de l'entrée : les comptes à rebours partent d'elle.
    public let date: Date
    /// Une par équipe suivie, dans l'ordre de suivi.
    public let teams: [WidgetTeam]
    /// Matchs en direct (dans l'ordre des cartes de l'appli), puis prochains matchs par heure de début ; un match
    /// entre deux équipes suivies n'y est qu'une fois.
    public let lines: [WidgetLine]

    public init(date: Date, teams: [WidgetTeam], lines: [WidgetLine]) {
        self.date = date
        self.teams = teams
        self.lines = lines
    }

    /// Match des widgets de l'écran verrouillé : un match en direct d'abord, sinon le prochain.
    public var headline: WidgetLine? { lines.first }

    /// Équipe du petit widget : celle choisie dans ses réglages si elle est toujours suivie, sinon la première suivie.
    public func team(id: String?) -> WidgetTeam? {
        if let id, let chosen = teams.first(where: { $0.team.id == id }) { return chosen }
        return teams.first
    }
}
```

- [ ] **Step 4 : Écrire le planning**

Créer `LoLKit/Sources/LoLKit/Widget/WidgetTimeline.swift` :

```swift
import Foundation

/// Planning des widgets (spec §7) : ce qu'ils montrent à chaque date, calculé seulement à partir des fichiers de
/// l'appli. Toutes les lignes passent par `Presenter.scoreLine` et `Presenter.nextLine` : l'anti-spoiler (spec §8)
/// est exactement celui de l'appli.
///
/// Le cache vieillit pendant que l'appli dort : à la date d'une entrée, un direct de plus de `RefreshPolicy.liveTrust`
/// ne fait plus foi, et un match commencé sans donnée fraîche pour le confirmer a une issue inconnue (ni en direct, ni
/// à venir ; il compte seulement comme dernier match de ses équipes, pour l'anti-spoiler de la ligne « Prochain »).
public enum WidgetTimeline {
    /// Rechargement au plus tard 30 min après le calcul (spec §7), ou au prochain début de match s'il est plus proche.
    public static let reloadInterval: TimeInterval = 30 * 60
    /// Les entrées couvrent les 6 h qui viennent : si iOS tarde à recharger, le widget reste juste.
    public static let horizon: TimeInterval = 6 * 3600
    /// Pas du compte à rebours pendant la dernière heure avant un match.
    public static let countdownStep: TimeInterval = 5 * 60

    /// Ce que montrent les widgets à `date`.
    public static func content(at date: Date, input: WidgetInput) -> WidgetContent {
        let follows = input.follows
        let revealed = input.settings.revealedMatchIds
        let live = liveEvents(at: date, input: input)
        let schedule = presumed(input.schedule?.value.events ?? [], at: date, live: live)
        let cards = TeamCards.build(follows: follows, schedule: schedule, live: live, revealed: revealed)

        var liveLines: [WidgetLine] = []
        var upcoming: [WidgetLine] = []
        var next: [String: WidgetTeam.Next] = [:]
        for card in cards {
            if let event = card.live,
               let line = makeLine(for: event, card: card, follows: follows, revealed: revealed), line.isLive {
                next[card.team.id] = .live(line)
                if !liveLines.contains(where: { $0.matchId == line.matchId }) {
                    liveLines.append(line)
                }
            }
            // Jamais `card.next` directement : la ligne « Prochain » passe par LoLKit (anti-spoiler, spec §8).
            let shown: WidgetTeam.Next
            switch Presenter.nextLine(for: card, follows: follows, revealed: revealed) {
            case .hidden:
                shown = .hidden
            case .none:
                shown = .noMatch
            case let .match(event):
                if let line = makeLine(for: event, card: card, follows: follows, revealed: revealed), !line.isLive {
                    shown = .match(line)
                    if !upcoming.contains(where: { $0.matchId == line.matchId }) {
                        upcoming.append(line)
                    }
                } else {
                    shown = .noMatch
                }
            }
            if next[card.team.id] == nil {
                next[card.team.id] = shown
            }
        }
        let byStart = upcoming.enumerated().sorted { a, b in
            let x = a.element.upcomingStart ?? .distantFuture
            let y = b.element.upcomingStart ?? .distantFuture
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
        return WidgetContent(
            date: date,
            teams: follows.teams.map { WidgetTeam(team: $0, next: next[$0.id] ?? .noMatch) },
            lines: liveLines + byStart
        )
    }

    /// Dates des entrées : maintenant ; le début de chaque match à venir d'une équipe suivie ; les paliers de son compte
    /// à rebours (chaque heure pleine avant le début, puis toutes les 5 min pendant la dernière heure) ; la fin de
    /// confiance du direct et du calendrier. Toutes dans `[now, now + horizon]`, triées, sans doublon.
    public static func entryDates(now: Date, input: WidgetInput) -> [Date] {
        let end = now.addingTimeInterval(horizon)
        var dates: Set<Date> = [now]
        func add(_ date: Date) {
            if date > now && date <= end {
                dates.insert(date)
            }
        }
        for start in upcomingStarts(input) where start > now {
            add(start)
            for hours in 1..<48 {
                add(start.addingTimeInterval(-Double(hours) * 3600))
            }
            for steps in 1..<12 {
                add(start.addingTimeInterval(-Double(steps) * countdownStep))
            }
        }
        // Passé cette date, « en direct » n'est plus cru : l'entrée suivante ne l'affiche plus.
        if let live = input.live {
            add(live.fetchedAt.addingTimeInterval(RefreshPolicy.liveTrust + 1))
        }
        if let schedule = input.schedule {
            add(schedule.fetchedAt.addingTimeInterval(RefreshPolicy.liveTrust + 1))
        }
        return dates.sorted()
    }

    /// Prochain rechargement (spec §7) : au prochain début de match d'une équipe suivie, au plus tard dans 30 min.
    public static func reloadDate(now: Date, input: WidgetInput) -> Date {
        let latest = now.addingTimeInterval(reloadInterval)
        guard let next = upcomingStarts(input).filter({ $0 > now }).min() else { return latest }
        return min(next, latest)
    }

    // MARK: - Interne

    /// Débuts des matchs pas encore commencés (dans le cache) d'au moins une équipe suivie.
    static func upcomingStarts(_ input: WidgetInput) -> [Date] {
        (input.schedule?.value.events ?? [])
            .filter { $0.state == .unstarted && input.follows.involves($0.match.teams) }
            .map(\.startTime)
    }

    /// Matchs en direct à `date` : `getLive` en cache tant qu'il fait foi ; sinon nil (les cartes retombent sur les
    /// matchs en cours du calendrier, comme dans l'appli) si le calendrier a moins de `liveTrust` ; sinon personne
    /// n'est donné pour en direct ([]) : un vieux calendrier ne dit plus qui joue.
    static func liveEvents(at date: Date, input: WidgetInput) -> [MatchEvent]? {
        if let live = RefreshPolicy.usableLive(input.live, now: date) {
            return live
        }
        if let schedule = input.schedule {
            let age = schedule.age(now: date)
            if age >= 0 && age <= RefreshPolicy.liveTrust {
                return nil
            }
        }
        return []
    }

    /// Le calendrier vu à `date` : un match commencé dont le direct ne dit rien (en cours dans un calendrier qui ne
    /// fait plus foi, ou pas commencé dans le cache alors que son heure est passée) devient « terminé ». Il n'est
    /// plus ni en direct ni à venir, mais reste le dernier match de ses équipes : si l'une est en anti-spoiler, leur
    /// ligne « Prochain » reste masquée (spec §8).
    static func presumed(_ events: [MatchEvent], at date: Date, live: [MatchEvent]?) -> [MatchEvent] {
        let liveIds = Set((live ?? []).map(\.id))
        return events.map { event in
            if liveIds.contains(event.id) { return event }
            let started: Bool
            switch event.state {
            case .inProgress: started = live != nil
            case .unstarted: started = event.startTime <= date
            case .completed, .unknown: started = false
            }
            guard started else { return event }
            return MatchEvent(startTime: event.startTime, state: .completed, type: event.type, blockName: event.blockName,
                              league: event.league, match: event.match, streams: event.streams)
        }
    }

    /// Ligne d'un match pour la carte d'une équipe : ordre d'affichage (l'équipe de la carte à gauche), score et
    /// numéro de game de `Presenter.scoreLine` (nil si masqué). nil pour un match terminé : les widgets ne montrent
    /// que le direct et l'à-venir.
    static func makeLine(for event: MatchEvent, card: TeamCard, follows: FollowList,
                         revealed: Set<String>) -> WidgetLine? {
        let scoreLine = Presenter.scoreLine(for: event, follows: follows, revealed: revealed)
        let order = follows.displayOrder(event.match.teams, preferring: card.team)
        let teams = reorder(event.match.teams, order) ?? event.match.teams
        let status: WidgetLine.Status
        switch scoreLine.status {
        case let .live(gameNumber):
            status = .live(score: scoreLine.score.flatMap { reorder($0, order) }, gameNumber: gameNumber)
        case let .upcoming(start):
            status = .upcoming(start)
        case .finished:
            return nil
        }
        return WidgetLine(
            matchId: event.id,
            leagueName: event.league.name,
            codes: teams.map(\.code),
            colorHexes: teams.map { team in follows.teams.first { team.isSame(as: $0) }?.colorHex },
            status: status,
            isMasked: scoreLine.isMasked
        )
    }
}
```

- [ ] **Step 5 : Lancer les tests, vérifier qu'ils passent**

Run : `bash scripts/lolkit.sh test --filter WidgetTimelineTests` → Expected : PASS (15 tests).
Run : `bash scripts/lolkit.sh test` → Expected : aucun échec (total de la Task 1 + 15), aucun avertissement de compilation.

- [ ] **Step 6 : Commit, push, CI LoLKit**

```bash
git add LoLKit/Sources/LoLKit/Widget/WidgetContent.swift LoLKit/Sources/LoLKit/Widget/WidgetTimeline.swift LoLKit/Tests/LoLKitTests/WidgetTimelineTests.swift
git commit -m "feat(lolkit): planning des widgets — contenu à une date, entrées, rechargement, anti-spoiler" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : LoLKit vert (Linux + macOS). Le run iOS de ce commit doit aussi rester vert (rien ne change côté appli) : `gh run list --workflow iOS --commit "$(git rev-parse HEAD)" …` puis `gh run watch --exit-status <id>`.

---

### Task 3 : Textes des widgets et dates courtes (LoLKit)

**Files :**
- Modify : `LoLKit/Sources/LoLKit/Presentation/Format.swift` (ajouts après `matchDate`)
- Create : `LoLKit/Sources/LoLKit/Widget/WidgetText.swift`
- Create : `LoLKit/Tests/LoLKitTests/WidgetTextTests.swift`

**Interfaces :**
- Consumes : `WidgetContent`, `WidgetLine`, `WidgetTeam` (Task 2) ; `Format.maskedStatus` (Task 1) ; `Format.countdown(from:to:)`, `Format.matchDate(_:timeZone:)`, `Format.time(_:timeZone:)` (existants) ; tableaux privés `days` / `months` de `Format.swift`.
- Produces :
  - `Format.day(_ date: Date, timeZone: TimeZone = .current) -> String` — « ven. 16 oct. »
  - `Format.shortDate(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String` — « jeu. 11:00 » d'ici 6 jours, sinon « mar. 20 oct. »
  - `WidgetText.countdownSpan` (86 400 s)
  - `WidgetText.emptyMessage(_ content: WidgetContent) -> String`
  - `WidgetText.inline(_ content: WidgetContent, timeZone: TimeZone = .current) -> String`
  - `WidgetText.rectangular(_ content: WidgetContent, timeZone: TimeZone = .current) -> WidgetText.Rectangular` (`label`, `title`, `detail`, `isLive`, `isMasked`)
  - `WidgetText.circular(_ content: WidgetContent) -> WidgetText.Circular` (`.countdown(text:code:progress:)`, `.live(code:)`, `.empty`)
  - `WidgetText.row(_ line: WidgetLine, now: Date, timeZone: TimeZone = .current) -> WidgetText.Row` (`title`, `trailing`, `isLive`, `isMasked`)
  - `WidgetText.small(_ team: WidgetTeam?, timeZone: TimeZone = .current) -> WidgetText.Small` (`label`, `title`, `day`, `time`, `note`, `isLive`, `isMasked`)

- [ ] **Step 1 : Écrire les tests qui échouent**

Créer `LoLKit/Tests/LoLKitTests/WidgetTextTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Textes des widgets (spec §7) ; un match masqué ne montre jamais ni score ni numéro de game (spec §8).
@Suite struct WidgetTextTests {
    /// Mardi 13 octobre 2026, 14:00 à Paris.
    private let now = date("2026-10-13T12:00:00Z")
    private let paris = TimeZone(secondsFromGMT: 2 * 3600)!
    private let kc = FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")

    private func line(_ codes: [String], _ status: WidgetLine.Status, masked: Bool = false) -> WidgetLine {
        WidgetLine(matchId: codes.joined(separator: "-"), leagueName: "Mondial", codes: codes, colorHexes: [nil, nil],
                   status: status, isMasked: masked)
    }

    private func content(_ lines: [WidgetLine], teams: [FollowedTeam]? = nil) -> WidgetContent {
        WidgetContent(date: now, teams: (teams ?? [kc]).map { WidgetTeam(team: $0, next: .noMatch) }, lines: lines)
    }

    private var live: WidgetLine { line(["KC", "C9"], .live(score: [1, 0], gameNumber: 2)) }
    private var maskedLive: WidgetLine { line(["T1", "FLY"], .live(score: nil, gameNumber: nil), masked: true) }
    /// Jeudi 15 octobre, 11:00 à Paris.
    private var upcoming: WidgetLine { line(["GEN", "FUR"], .upcoming(date("2026-10-15T09:00:00Z"))) }

    @Test func shortDatesInFrench() {
        #expect(Format.day(date("2026-10-16T09:00:00Z"), timeZone: paris) == "ven. 16 oct.")
        #expect(Format.shortDate(date("2026-10-13T20:00:00Z"), now: now, timeZone: paris) == "mar. 22:00")
        #expect(Format.shortDate(date("2026-10-15T09:00:00Z"), now: now, timeZone: paris) == "jeu. 11:00")
        #expect(Format.shortDate(date("2026-10-19T12:00:00Z"), now: now, timeZone: paris) == "lun. 14:00")
        #expect(Format.shortDate(date("2026-10-20T12:00:00Z"), now: now, timeZone: paris) == "mar. 20 oct.")
    }

    @Test func inlineWidget() {
        #expect(WidgetText.inline(content([live]), timeZone: paris) == "KC 1–0 C9 · G2")
        #expect(WidgetText.inline(content([maskedLive]), timeZone: paris) == "T1 vs FLY · En direct")
        #expect(WidgetText.inline(content([upcoming]), timeZone: paris) == "GEN vs FUR · jeu. 11:00")
        #expect(WidgetText.inline(content([]), timeZone: paris) == "Aucun match prévu")
        #expect(WidgetText.inline(content([], teams: []), timeZone: paris) == "Aucune équipe suivie")
    }

    @Test func rectangularWidget() {
        #expect(WidgetText.rectangular(content([live]), timeZone: paris)
                == WidgetText.Rectangular(label: "En direct", title: "KC 1 – 0 C9", detail: "Mondial · Game 2",
                                          isLive: true, isMasked: false))
        #expect(WidgetText.rectangular(content([maskedLive]), timeZone: paris)
                == WidgetText.Rectangular(label: "En direct", title: "T1 vs FLY", detail: "Mondial",
                                          isLive: true, isMasked: true))
        #expect(WidgetText.rectangular(content([upcoming]), timeZone: paris)
                == WidgetText.Rectangular(label: "Prochain", title: "GEN vs FUR", detail: "jeu. 15 oct. · 11:00",
                                          isLive: false, isMasked: false))
        #expect(WidgetText.rectangular(content([]), timeZone: paris)
                == WidgetText.Rectangular(label: "Prochain", title: "Aucun match prévu",
                                          detail: "Ouvre Faille pour actualiser", isLive: false, isMasked: false))
        #expect(WidgetText.rectangular(content([], teams: []), timeZone: paris)
                == WidgetText.Rectangular(label: "Faille", title: "Aucune équipe suivie",
                                          detail: "Ajoute-en dans l'appli", isLive: false, isMasked: false))
    }

    @Test func circularWidget() {
        let soon = line(["GEN", "FUR"], .upcoming(date("2026-10-14T09:00:00Z")))
        #expect(WidgetText.circular(content([soon])) == .countdown(text: "21h", code: "GEN", progress: 0.125))
        let far = line(["GEN", "FUR"], .upcoming(date("2026-10-16T12:00:00Z")))
        #expect(WidgetText.circular(content([far])) == .countdown(text: "3 j", code: "GEN", progress: 0))
        #expect(WidgetText.circular(content([live])) == .live(code: "KC"))
        #expect(WidgetText.circular(content([maskedLive])) == .live(code: "T1"))
        #expect(WidgetText.circular(content([])) == .empty)
    }

    @Test func mediumWidgetRows() {
        #expect(WidgetText.row(live, now: now, timeZone: paris)
                == WidgetText.Row(title: "KC 1 – 0 C9", trailing: "Game 2", isLive: true, isMasked: false))
        #expect(WidgetText.row(maskedLive, now: now, timeZone: paris)
                == WidgetText.Row(title: "T1 vs FLY", trailing: "En direct", isLive: true, isMasked: true))
        #expect(WidgetText.row(upcoming, now: now, timeZone: paris)
                == WidgetText.Row(title: "GEN vs FUR", trailing: "jeu. 11:00", isLive: false, isMasked: false))
    }

    @Test func smallWidget() {
        let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)
        #expect(WidgetText.small(WidgetTeam(team: kc, next: .match(upcoming)), timeZone: paris)
                == WidgetText.Small(label: "Prochain", title: "GEN vs FUR", day: "jeu. 15 oct.", time: "11:00",
                                    note: nil, isLive: false, isMasked: false))
        #expect(WidgetText.small(WidgetTeam(team: kc, next: .live(live)), timeZone: paris)
                == WidgetText.Small(label: "En direct", title: "KC 1 – 0 C9", day: nil, time: nil,
                                    note: "Mondial · Game 2", isLive: true, isMasked: false))
        #expect(WidgetText.small(WidgetTeam(team: t1, next: .live(maskedLive)), timeZone: paris)
                == WidgetText.Small(label: "En direct", title: "T1 vs FLY", day: nil, time: nil,
                                    note: "Mondial", isLive: true, isMasked: true))
        #expect(WidgetText.small(WidgetTeam(team: t1, next: .hidden), timeZone: paris)
                == WidgetText.Small(label: "Prochain", title: "T1", day: nil, time: nil,
                                    note: "masqué", isLive: false, isMasked: true))
        #expect(WidgetText.small(WidgetTeam(team: kc, next: .noMatch), timeZone: paris)
                == WidgetText.Small(label: "Prochain", title: "KC", day: nil, time: nil,
                                    note: "Aucun match prévu", isLive: false, isMasked: false))
        #expect(WidgetText.small(nil, timeZone: paris)
                == WidgetText.Small(label: "Faille", title: "Aucune équipe suivie", day: nil, time: nil,
                                    note: "Ajoute-en dans l'appli", isLive: false, isMasked: false))
    }

    @Test func maskedTextsNeverCarryAScoreOrAGame() {
        let texts = [
            WidgetText.inline(content([maskedLive]), timeZone: paris),
            WidgetText.rectangular(content([maskedLive]), timeZone: paris).title,
            WidgetText.rectangular(content([maskedLive]), timeZone: paris).detail,
            WidgetText.row(maskedLive, now: now, timeZone: paris).trailing,
            WidgetText.small(WidgetTeam(team: kc, next: .live(maskedLive)), timeZone: paris).note ?? "",
        ]
        for text in texts {
            #expect(!text.contains("–") && !text.contains("Game") && !text.contains(" · G"), "\(text)")
        }
    }
}
```

- [ ] **Step 2 : Lancer les tests, vérifier qu'ils échouent**

Run : `bash scripts/lolkit.sh test --filter WidgetTextTests`
Expected : FAIL à la compilation — `type 'Format' has no member 'day'` / `'shortDate'`, `cannot find 'WidgetText' in scope`.

- [ ] **Step 3 : Ajouter les dates courtes à `Format`**

Dans `LoLKit/Sources/LoLKit/Presentation/Format.swift`, insérer juste après la fermeture de `matchDate` (avant le commentaire `/// Compte à rebours court pour le widget rond…`) :

```swift
    /// « ven. 16 oct. » dans le fuseau donné.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        return "\(days[(parts.weekday ?? 1) - 1]) \(parts.day ?? 0) \(months[(parts.month ?? 1) - 1])"
    }

    /// Date courte des widgets : « jeu. 11:00 » d'ici 6 jours (au calendrier), sinon « mar. 20 oct. ».
    public static func shortDate(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                            to: calendar.startOfDay(for: date)).day ?? 0
        guard ahead <= 6 else { return day(date, timeZone: timeZone) }
        let weekday = calendar.component(.weekday, from: date)
        return "\(days[weekday - 1]) \(time(date, timeZone: timeZone))"
    }

```

- [ ] **Step 4 : Écrire `WidgetText`**

Créer `LoLKit/Sources/LoLKit/Widget/WidgetText.swift` :

```swift
import Foundation

/// Textes des widgets (spec §7), en français. L'anti-spoiler est déjà dans `WidgetLine` (spec §8) : une ligne
/// masquée n'a ni score ni numéro de game ; elle ne s'écrit qu'avec « En direct » ou sa date.
public enum WidgetText {
    /// La jauge du widget rond se remplit pendant les 24 h qui précèdent le match.
    public static let countdownSpan: TimeInterval = 24 * 3600

    /// Widget rectangulaire de l'écran verrouillé : étiquette, match, puis date ou ligue.
    public struct Rectangular: Sendable, Equatable {
        public let label: String
        public let title: String
        public let detail: String
        public let isLive: Bool
        public let isMasked: Bool

        public init(label: String, title: String, detail: String, isLive: Bool, isMasked: Bool) {
            self.label = label
            self.title = title
            self.detail = detail
            self.isLive = isLive
            self.isMasked = isMasked
        }
    }

    /// Widget rond de l'écran verrouillé.
    public enum Circular: Sendable, Equatable {
        /// « 21h » et le code de l'équipe suivie ; `progress` va de 0 (24 h ou plus avant) à 1 (le match commence).
        case countdown(text: String, code: String, progress: Double)
        /// Une équipe suivie joue (masquée ou non : seul « en direct » est dit).
        case live(code: String)
        /// Rien à annoncer.
        case empty
    }

    /// Une ligne du moyen widget.
    public struct Row: Sendable, Equatable {
        public let title: String
        public let trailing: String
        public let isLive: Bool
        public let isMasked: Bool

        public init(title: String, trailing: String, isLive: Bool, isMasked: Bool) {
            self.title = title
            self.trailing = trailing
            self.isLive = isLive
            self.isMasked = isMasked
        }
    }

    /// Le petit widget d'une équipe.
    public struct Small: Sendable, Equatable {
        public let label: String
        public let title: String
        public let day: String?
        public let time: String?
        public let note: String?
        public let isLive: Bool
        public let isMasked: Bool

        public init(label: String, title: String, day: String?, time: String?, note: String?, isLive: Bool,
                    isMasked: Bool) {
            self.label = label
            self.title = title
            self.day = day
            self.time = time
            self.note = note
            self.isLive = isLive
            self.isMasked = isMasked
        }
    }

    /// Rien à montrer : « Aucune équipe suivie » ou « Aucun match prévu ».
    public static func emptyMessage(_ content: WidgetContent) -> String {
        content.teams.isEmpty ? "Aucune équipe suivie" : "Aucun match prévu"
    }

    /// Widget en ligne : « KC 1–0 C9 · G2 », « T1 vs FLY · En direct », « GEN vs FUR · jeu. 11:00 ».
    public static func inline(_ content: WidgetContent, timeZone: TimeZone = .current) -> String {
        guard let line = content.headline else { return emptyMessage(content) }
        switch line.status {
        case let .live(score, gameNumber):
            guard score != nil else { return "\(title(line)) · \(Format.maskedStatus(.inGame))" }
            let compact = title(line, compact: true)
            return gameNumber.map { "\(compact) · G\($0)" } ?? compact
        case let .upcoming(start):
            return "\(title(line)) · \(Format.shortDate(start, now: content.date, timeZone: timeZone))"
        }
    }

    /// Widget rectangulaire : « Prochain · GEN vs FUR · jeu. 15 oct. · 11:00 » ; en direct : « En direct ·
    /// KC 1 – 0 C9 · Mondial · Game 2 » ; masqué : « En direct · T1 vs FLY · Mondial ».
    public static func rectangular(_ content: WidgetContent, timeZone: TimeZone = .current) -> Rectangular {
        guard let line = content.headline else {
            if content.teams.isEmpty {
                return Rectangular(label: "Faille", title: "Aucune équipe suivie", detail: "Ajoute-en dans l'appli",
                                   isLive: false, isMasked: false)
            }
            return Rectangular(label: "Prochain", title: "Aucun match prévu", detail: "Ouvre Faille pour actualiser",
                               isLive: false, isMasked: false)
        }
        switch line.status {
        case .live:
            return Rectangular(label: Format.maskedStatus(.inGame), title: title(line), detail: liveDetail(line),
                               isLive: true, isMasked: line.isMasked)
        case let .upcoming(start):
            return Rectangular(label: "Prochain", title: title(line), detail: Format.matchDate(start, timeZone: timeZone),
                               isLive: false, isMasked: line.isMasked)
        }
    }

    /// Widget rond : compte à rebours vers le prochain match et code de l'équipe suivie, ou « en direct ».
    public static func circular(_ content: WidgetContent) -> Circular {
        guard let line = content.headline, let code = line.codes.first else { return .empty }
        switch line.status {
        case .live:
            return .live(code: code)
        case let .upcoming(start):
            let remaining = start.timeIntervalSince(content.date)
            let progress = min(1, max(0, 1 - remaining / countdownSpan))
            return .countdown(text: Format.countdown(from: content.date, to: start), code: code, progress: progress)
        }
    }

    /// Ligne du moyen widget : « KC 1 – 0 C9 » + « Game 2 » ; masqué : « T1 vs FLY » + « En direct » ;
    /// à venir : « GEN vs FUR » + « jeu. 11:00 ».
    public static func row(_ line: WidgetLine, now: Date, timeZone: TimeZone = .current) -> Row {
        switch line.status {
        case let .live(_, gameNumber):
            return Row(title: title(line), trailing: gameNumber.map { "Game \($0)" } ?? Format.maskedStatus(.inGame),
                       isLive: true, isMasked: line.isMasked)
        case let .upcoming(start):
            return Row(title: title(line), trailing: Format.shortDate(start, now: now, timeZone: timeZone),
                       isLive: false, isMasked: line.isMasked)
        }
    }

    /// Petit widget : le prochain match de l'équipe (jour et heure), son match en direct, « masqué » (règle F1) ou rien.
    public static func small(_ team: WidgetTeam?, timeZone: TimeZone = .current) -> Small {
        guard let team else {
            return Small(label: "Faille", title: "Aucune équipe suivie", day: nil, time: nil,
                         note: "Ajoute-en dans l'appli", isLive: false, isMasked: false)
        }
        switch team.next {
        case let .live(line):
            return Small(label: Format.maskedStatus(.inGame), title: title(line), day: nil, time: nil,
                         note: liveDetail(line), isLive: true, isMasked: line.isMasked)
        case let .match(line):
            return Small(label: "Prochain", title: title(line),
                         day: line.upcomingStart.map { Format.day($0, timeZone: timeZone) },
                         time: line.upcomingStart.map { Format.time($0, timeZone: timeZone) },
                         note: nil, isLive: false, isMasked: line.isMasked)
        case .hidden:
            return Small(label: "Prochain", title: team.team.code, day: nil, time: nil, note: "masqué",
                         isLive: false, isMasked: true)
        case .noMatch:
            return Small(label: "Prochain", title: team.team.code, day: nil, time: nil, note: "Aucun match prévu",
                         isLive: false, isMasked: false)
        }
    }

    // MARK: - Interne

    /// « KC 1 – 0 C9 » (« KC 1–0 C9 » en compact) ; sans score (masqué ou à venir) : « T1 vs FLY ».
    static func title(_ line: WidgetLine, compact: Bool = false) -> String {
        if case let .live(score?, _) = line.status, score.count == 2, line.codes.count == 2 {
            let dash = compact ? "–" : " – "
            return "\(line.codes[0]) \(score[0])\(dash)\(score[1]) \(line.codes[1])"
        }
        return line.codes.joined(separator: " vs ")
    }

    /// « Mondial · Game 2 » ; masqué : « Mondial » (spec §8 : pas de numéro de game).
    static func liveDetail(_ line: WidgetLine) -> String {
        if case let .live(_, gameNumber?) = line.status {
            return "\(line.leagueName) · Game \(gameNumber)"
        }
        return line.leagueName
    }
}
```

- [ ] **Step 5 : Lancer les tests, vérifier qu'ils passent**

Run : `bash scripts/lolkit.sh test --filter WidgetTextTests` → Expected : PASS (7 tests).
Run : `bash scripts/lolkit.sh test` → Expected : aucun échec (total de la Task 2 + 7) ; `FormatTests` (dont `matchDateInFrench`, `countdown`) toujours verts.

- [ ] **Step 6 : Commit, push, CI LoLKit**

```bash
git add LoLKit/Sources/LoLKit/Presentation/Format.swift LoLKit/Sources/LoLKit/Widget/WidgetText.swift LoLKit/Tests/LoLKitTests/WidgetTextTests.swift
git commit -m "feat(lolkit): textes des cinq widgets et dates courtes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow LoLKit --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : LoLKit vert (Linux + macOS) ; le run iOS du même commit reste vert.

---

### Task 4 : Extension prête — Sora et icônes embarquées, lecture des fichiers, rechargements

**Files :**
- Modify : `project.yml` (cible `FailleWidgets`)
- Modify : `.github/workflows/ios.yml` (nouvelle étape après « Compiler sans signature »)
- Create : `Shared/Widgets/WidgetInput+Files.swift`
- Modify : `App/Store/AppStore.swift` (doc ~45, propriété après ~56, `cycle` ~317-330, `saveFollows` ~532-541, `saveSettings` ~551-554)
- Create : `Tests/FailleTests/WidgetDataTests.swift`

**Interfaces :**
- Consumes : `WidgetInput(follows:settings:schedule:live:)`, `WidgetTimeline.content(at:input:)` (Task 2) ; `FileStore(directory:readOnly:)`, `FileStore.load(_:from:)`, `FileStore.File.follows / .settings / .schedule / .live` ; `AppGroup.directory` ; `AppStore(transport:files:)`, `AppStore.refreshDue(opening:)`, `AppStore.reveal(matchId:)`, `AppStore.schedule`, `AppStore.isFailing` ; tests : `ScriptedTransport(mode:)`, `TemporaryFiles.directory()` / `.store()`, `SampleData.follows / .schedule / .live / .t1MatchId / .date(_:)`.
- Produces :
  - `extension WidgetInput { static func load(from files: FileStore) -> WidgetInput ; static func shared() -> WidgetInput }` (dans `Shared/`, donc appli + extension)
  - `AppStore.widgetReloadRequests: Int` (`private(set)`, `@ObservationIgnored`) — compteur lu par les tests
  - l'extension embarque `Sora-Variable.ttf`, `Assets.car` (icônes) et déclare `UIAppFonts`

- [ ] **Step 1 : `project.yml` — police, catalogue et Info.plist de l'extension**

Remplacer tout le bloc de la cible `FailleWidgets` :

```yaml
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

par :

```yaml
  FailleWidgets:
    type: app-extension
    platform: iOS
    sources:
      - Widgets
      - Shared
      # Sora et les icônes (spec §7, §9) : l'extension a son propre bundle, elle ne voit pas les ressources de l'appli.
      - Resources
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
        UIAppFonts:
          - Sora-Variable.ttf
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille.widgets
        # Pas d'icône ni de couleur d'accent dans le catalogue : actool ne doit pas les chercher.
        ASSETCATALOG_COMPILER_APPICON_NAME: ""
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: ""
```

- [ ] **Step 2 : CI — vérifier le contenu de l'`.appex`**

Dans `.github/workflows/ios.yml`, job `build`, insérer entre l'étape « Compiler sans signature » et l'étape « Signer en ad hoc avec les entitlements » :

```yaml
      - name: Vérifier Sora et les icônes dans l'extension
        # Le widget a son propre bundle : sans police ni catalogue embarqués, il retomberait sur la police système.
        run: |
          APPEX=build/Build/Products/Release-iphoneos/Faille.app/PlugIns/FailleWidgets.appex
          ls "$APPEX"
          test -f "$APPEX/Sora-Variable.ttf"
          test -f "$APPEX/Assets.car"
          /usr/libexec/PlistBuddy -c "Print :UIAppFonts:0" "$APPEX/Info.plist" | grep -qx "Sora-Variable.ttf"

```

- [ ] **Step 3 : Lecture seule des fichiers de l'appli**

Créer `Shared/Widgets/WidgetInput+Files.swift` :

```swift
import Foundation
import LoLKit

extension WidgetInput {
    /// Les fichiers de l'appli (spec §4.4) : un fichier absent ou illisible donne une valeur vide. Avec un `FileStore`
    /// en lecture seule, rien n'est écrit ni mis de côté.
    static func load(from files: FileStore) -> WidgetInput {
        WidgetInput(
            follows: files.load(FollowList.self, from: .follows) ?? FollowList(),
            settings: files.load(AppSettings.self, from: .settings) ?? AppSettings(),
            schedule: files.load(Cached<SchedulePage>.self, from: .schedule),
            live: files.load(Cached<[MatchEvent]>.self, from: .live)
        )
    }

    /// Ce que lit l'extension : le dossier de Faille dans le groupe d'apps résolu à l'exécution, en lecture seule.
    static func shared() -> WidgetInput {
        load(from: FileStore(directory: AppGroup.directory, readOnly: true))
    }
}
```

- [ ] **Step 4 : `AppStore` — recharger les widgets**

Dans `App/Store/AppStore.swift` :

(a) Remplacer :

```swift
    /// Recharger les widgets quand les équipes suivies changent (jamais en aperçu ni dans les tests hébergés).
    private let reloadsWidgets: Bool
```

par :

```swift
    /// Appeler WidgetKit pour recharger les widgets (jamais en aperçu ni dans les tests hébergés).
    private let reloadsWidgets: Bool
```

(b) Juste après la ligne `    @ObservationIgnored private var settingsUnreadable = false`, ajouter :

```swift
    /// Demandes de rechargement des widgets (lu par les tests ; WidgetKit n'est appelé que si `reloadsWidgets`).
    @ObservationIgnored private(set) var widgetReloadRequests = 0
```

(c) Dans `cycle(opening:pullToRefresh:)`, remplacer :

```swift
        // Le calendrier dépend des ligues (peut-être tout juste chargées) et des matchs sortis du direct : on redemande.
        if RefreshPolicy.due(refreshInput(opening: opening)).contains(.schedule) {
            await fetch(.schedule)
            if Task.isCancelled { return }
        }
```

par :

```swift
        // Le calendrier dépend des ligues (peut-être tout juste chargées) et des matchs sortis du direct : on redemande.
        var scheduleFetched = false
        if RefreshPolicy.due(refreshInput(opening: opening)).contains(.schedule) {
            scheduleFetched = await fetch(.schedule)
            if Task.isCancelled { return }
        }
        // Les widgets relisent le calendrier et le direct qui viennent d'être enregistrés (spec §7) : une fois par cycle.
        if liveFetched || scheduleFetched { reloadWidgets() }
```

(d) Remplacer `saveFollows` :

```swift
    private func saveFollows() {
        guard !followsUnreadable else { return }
        files?.save(follows, to: .follows)
        if reloadsWidgets {
            // Le widget (sonde, puis les vrais à l'étape 3) relit les équipes suivies tout de suite.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
```

par :

```swift
    private func saveFollows() {
        guard !followsUnreadable else { return }
        files?.save(follows, to: .follows)
        reloadWidgets()
    }
```

(e) Remplacer `saveSettings` :

```swift
    private func saveSettings() {
        guard !settingsUnreadable else { return }
        files?.save(settings, to: .settings)
    }
```

par :

```swift
    /// Réglages (mode Live Activity, matchs révélés) : une révélation se voit tout de suite dans les widgets (spec §8).
    private func saveSettings() {
        guard !settingsUnreadable else { return }
        files?.save(settings, to: .settings)
        reloadWidgets()
    }

    /// Les widgets relisent les fichiers du groupe d'apps (spec §7). Demandés au premier plan, ces rechargements ne
    /// sont pas décomptés du budget de WidgetKit.
    private func reloadWidgets() {
        widgetReloadRequests += 1
        if reloadsWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
```

- [ ] **Step 5 : Tests hébergés**

Créer `Tests/FailleTests/WidgetDataTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Ce que lisent les widgets (spec §4.4, §7) et quand l'appli leur demande de relire (spec §7, §8).
@MainActor
struct WidgetDataTests {
    @Test func widgetsReadWhatTheAppWrote() {
        let directory = TemporaryFiles.directory()
        let files = FileStore(directory: directory)
        let fetchedAt = SampleData.date("2026-10-15T17:05:00Z")
        files.save(SampleData.follows, to: .follows)
        files.save(AppSettings(revealedMatchIds: [SampleData.t1MatchId]), to: .settings)
        files.save(Cached(value: SchedulePage(leagueIds: ["98767975604431411"], events: SampleData.schedule),
                          fetchedAt: fetchedAt), to: .schedule)
        files.save(Cached(value: SampleData.live, fetchedAt: fetchedAt), to: .live)

        let input = WidgetInput.load(from: FileStore(directory: directory, readOnly: true))
        #expect(input.follows == SampleData.follows)
        #expect(input.settings.revealedMatchIds == [SampleData.t1MatchId])
        #expect(input.schedule?.value.events == SampleData.schedule)
        #expect(input.schedule?.fetchedAt == fetchedAt)
        #expect(input.live?.value == SampleData.live)
    }

    @Test func widgetsShowNothingBeforeTheAppHasWrittenAnything() {
        let input = WidgetInput.load(from: FileStore(directory: TemporaryFiles.directory(), readOnly: true))
        #expect(input == WidgetInput())
        #expect(WidgetTimeline.content(at: Date(), input: input).teams.isEmpty)
    }

    @Test func refreshingTheScheduleReloadsTheWidgetsOnce() async {
        let store = AppStore(transport: ScriptedTransport(), files: TemporaryFiles.store())
        #expect(store.widgetReloadRequests == 0)
        await store.refreshDue(opening: true)
        #expect(store.schedule.map(\.id) == ["300"])
        #expect(store.widgetReloadRequests == 1)
    }

    @Test func aFailedRefreshDoesNotReloadTheWidgets() async {
        let store = AppStore(transport: ScriptedTransport(mode: .failing), files: TemporaryFiles.store())
        await store.refreshDue(opening: true)
        #expect(store.isFailing)
        #expect(store.widgetReloadRequests == 0)
    }

    @Test func revealingAMatchReloadsTheWidgets() {
        let store = AppStore(transport: ScriptedTransport(), files: TemporaryFiles.store())
        store.reveal(matchId: SampleData.t1MatchId)
        #expect(store.widgetReloadRequests == 1)
    }
}
```

- [ ] **Step 6 : Commit et push**

```bash
git add project.yml .github/workflows/ios.yml Shared/Widgets/WidgetInput+Files.swift App/Store/AppStore.swift Tests/FailleTests/WidgetDataTests.swift
git commit -m "feat(widgets): Sora et icônes dans l'extension, lecture seule des fichiers, rechargements des widgets" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 7 : CI iOS**

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run view <id> --log | grep -A12 "Vérifier Sora et les icônes"
```

Expected : `build` vert (l'étape « Vérifier Sora et les icônes dans l'extension » liste `Sora-Variable.ttf`, `Assets.car`, `OFL.txt` dans l'`.appex`) ; `apercus` vert avec les 5 tests de `WidgetDataTests`. Erreurs probables : `test -f …Sora-Variable.ttf` en échec → le dossier `Resources` n'a pas été ajouté aux sources de l'extension (Step 1) ; `actool` réclame `AppIcon` → vérifier les deux réglages `ASSETCATALOG_COMPILER_*` de l'extension ; `refreshingTheScheduleReloadsTheWidgetsOnce` voit 2 → un autre appel à `reloadWidgets()` a été ajouté dans `fetch` (il ne doit être que dans `cycle`, `saveFollows`, `saveSettings`).

---

### Task 5 : Vues des cinq widgets et aperçus PNG

Les vues vivent dans `Shared/Widgets/` : compilées dans l'appli, elles se rendent en PNG dans les tests hébergés ; l'extension (Task 6) les pose dans ses configurations.

**Files :**
- Create : `Shared/Widgets/WidgetChrome.swift`
- Create : `Shared/Widgets/AccessoryWidgetViews.swift`
- Create : `Shared/Widgets/HomeWidgetViews.swift`
- Create : `Shared/Preview/WidgetSamples.swift`
- Create : `Tests/FailleTests/Support/WidgetBoard.swift`
- Create : `Tests/FailleTests/WidgetSnapshotTests.swift`

**Interfaces :**
- Consumes : `WidgetContent` (`date`, `teams`, `lines`, `headline`, `team(id:)`), `WidgetLine` (`codes`, `colorHexes`, `isLive`, `id`), `WidgetTeam` (`team`, `next`), `WidgetInput`, `WidgetTimeline.content(at:input:)` (Task 2) ; `WidgetText.inline / rectangular / circular / row / small / emptyMessage` et `Format.day` (Task 3) ; `Palette.abyss / text / secondary / blueWash / tealWash / chipFill / glassBorder`, `Palette.team(_:)`, `Sora.font(_:_:)`, `IconView(icon:size:)`, `Icon` (`.live`, `.clock`, `.trophy`, `.eyeOff`), `Image(icon:)`, `Icon.assetName` ; `SampleData.follows / .schedule / .live / .date(_:)`, `SampleData.kcMatchId`, `SampleData.t1MatchId` ; tests : `Snapshot.directory`, `Snapshot.Failure(description:)`, `ApercuTests.expectNotBlank(_:)`, `Typo.label`, `Typo.labelTracking`.
- Produces :
  - `WidgetBackdrop(tint: Color?)`, `MonogramBadge(code: String, tint: Color? = nil, size: CGFloat = 26)`, `InlineIcon.image(_ icon: Icon, size: CGFloat = 14) -> Image`
  - `InlineWidgetView(content: WidgetContent)`, `RectangularWidgetView(content:)`, `CircularWidgetView(content:)`
  - `SmallWidgetView(team: WidgetTeam?)`, `MediumWidgetView(content: WidgetContent)` (`MediumWidgetView.maxRows` = 4)
  - `WidgetSamples.now`, `.input`, `.live`, `.maskedLive`, `.upcoming`, `.empty`
  - PNG `09-widgets-verrouille.png`, `10-widgets-accueil.png`

- [ ] **Step 1 : Fond, monogramme, icône du widget en ligne**

Créer `Shared/Widgets/WidgetChrome.swift` :

```swift
import SwiftUI
import UIKit

/// Fond des widgets de l'écran d'accueil (spec §9, maquette ③) : l'abysse et ses deux nappes, ou, pour une équipe,
/// un dégradé à 160° de sa couleur vers l'abysse. Posé par `containerBackground(for: .widget)` dans l'extension.
struct WidgetBackdrop: View {
    var tint: Color?

    var body: some View {
        ZStack {
            Palette.abyss
            if let tint {
                LinearGradient(colors: [tint.opacity(0.30), Palette.abyss.opacity(0.95)],
                               startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
            } else {
                LinearGradient(colors: [Palette.blueWash, .clear], startPoint: .topLeading,
                               endPoint: UnitPoint(x: 0.5, y: 0.45))
                LinearGradient(colors: [Palette.tealWash, .clear], startPoint: .bottomTrailing,
                               endPoint: UnitPoint(x: 0.5, y: 0.55))
            }
        }
    }
}

/// Monogramme d'une équipe (spec §4.4 : pas de logo dans les widgets) : son code dans un badge bordé de sa couleur ;
/// verre neutre pour une équipe non suivie.
struct MonogramBadge: View {
    let code: String
    var tint: Color? = nil
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
        Text(code)
            .font(Sora.font(size * 0.32, .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .foregroundStyle(tint ?? Palette.text)
            .frame(width: size, height: size)
            .background(shape.fill(Palette.chipFill))
            .overlay(shape.strokeBorder(tint ?? Palette.glassBorder, lineWidth: 1))
    }
}

/// Icône du widget en ligne, redessinée à la taille du texte : sur l'écran verrouillé, iOS affiche l'image d'un widget
/// en ligne à sa taille propre (les cadres y sont ignorés). Rendue en « template » : iOS la colore comme le texte.
@MainActor
enum InlineIcon {
    static func image(_ icon: Icon, size: CGFloat = 14) -> Image {
        guard let source = UIImage(named: icon.assetName) else { return Image(icon: icon) }
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return Image(uiImage: drawn.withRenderingMode(.alwaysTemplate))
    }
}
```

- [ ] **Step 2 : Widgets de l'écran verrouillé**

Créer `Shared/Widgets/AccessoryWidgetViews.swift` :

```swift
import LoLKit
import SwiftUI
import WidgetKit

/// Widget en ligne de l'écran verrouillé (spec §7) : « KC 1–0 C9 · G2 », « GEN vs FUR · jeu. 11:00 ».
/// iOS n'en garde qu'une image et une ligne de texte, dans sa propre police.
struct InlineWidgetView: View {
    let content: WidgetContent

    var body: some View {
        Label {
            Text(WidgetText.inline(content))
        } icon: {
            InlineIcon.image(content.headline?.isLive == true ? .live : .clock)
        }
    }
}

/// Widget rectangulaire (spec §7, maquette ①) : « PROCHAIN », le match, la date ; en direct : la ligue et la game.
/// Monochrome sur l'écran verrouillé : seulement les niveaux primaire et secondaire, jamais de couleur d'équipe.
struct RectangularWidgetView: View {
    let content: WidgetContent

    var body: some View {
        let text = WidgetText.rectangular(content)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                IconView(icon: text.isLive ? .live : .trophy, size: 10)
                Text(text.label)
                    .font(Sora.font(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(.secondary)
            Text(text.title)
                .font(Sora.font(15, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            HStack(spacing: 4) {
                if text.isMasked {
                    IconView(icon: .eyeOff, size: 10)
                }
                Text(text.detail)
                    .font(Sora.font(11, .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Widget rond (spec §7) : jauge du compte à rebours jusqu'au prochain match, et code de l'équipe ; jauge pleine et
/// icône « en direct » quand une équipe suivie joue.
struct CircularWidgetView: View {
    let content: WidgetContent

    var body: some View {
        ZStack {
            switch WidgetText.circular(content) {
            case let .countdown(text, code, progress):
                ring(progress)
                VStack(spacing: 0) {
                    Text(text)
                        .font(Sora.font(14, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(code)
                        .font(Sora.font(9, .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            case let .live(code):
                ring(1)
                VStack(spacing: 2) {
                    IconView(icon: .live, size: 16)
                    Text(code)
                        .font(Sora.font(10, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            case .empty:
                ring(0)
                IconView(icon: .trophy, size: 18)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Piste pâle et arc plein jusqu'à `progress` (0 : 24 h ou plus avant le match ; 1 : il commence ou il est en direct).
    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(3)
    }
}
```

- [ ] **Step 3 : Widgets de l'écran d'accueil**

Créer `Shared/Widgets/HomeWidgetViews.swift` :

```swift
import LoLKit
import SwiftUI
import WidgetKit

/// Petit widget (spec §7, maquette ③) : le prochain match d'une équipe, teinté à sa couleur (le fond est un
/// `WidgetBackdrop` posé par l'extension). Monogrammes des deux équipes, match, jour et heure.
struct SmallWidgetView: View {
    let team: WidgetTeam?

    var body: some View {
        let text = WidgetText.small(team)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(text.label)
                    .font(Sora.font(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                if let team {
                    Circle()
                        .fill(Palette.team(team.team.colorHex))
                        .frame(width: 7, height: 7)
                        .shadow(color: Palette.team(team.team.colorHex), radius: 4)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    MonogramBadge(code: badge.code, tint: badge.tint, size: 26)
                }
            }
            .padding(.bottom, 6)
            Text(text.title)
                .font(Sora.font(17, .bold))
                .tracking(-0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Spacer(minLength: 6)
            if let day = text.day {
                Text(day)
                    .font(Sora.font(11, .regular))
                    .foregroundStyle(Palette.secondary)
            }
            if let time = text.time {
                Text(time)
                    .font(Sora.font(15, .bold))
            }
            if let note = text.note {
                HStack(spacing: 4) {
                    if text.isMasked {
                        IconView(icon: .eyeOff, size: 11)
                    }
                    Text(note)
                        .font(Sora.font(11, .regular))
                        .lineLimit(2)
                }
                .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Monogrammes : les deux équipes du match (couleur des équipes suivies), sinon l'équipe seule.
    private var badges: [(code: String, tint: Color?)] {
        guard let team else { return [] }
        switch team.next {
        case let .live(line), let .match(line):
            return zip(line.codes, line.colorHexes).map { (code: $0, tint: $1.map(Palette.team)) }
        case .hidden, .noMatch:
            return [(code: team.team.code, tint: Palette.team(team.team.colorHex))]
        }
    }
}

/// Moyen widget (spec §7, maquette ③) : matchs en direct, puis prochains matchs de toutes les équipes suivies.
struct MediumWidgetView: View {
    let content: WidgetContent
    static let maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mes équipes")
                    .font(Sora.font(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                Spacer()
                Text(Format.day(content.date))
                    .font(Sora.font(10, .medium))
            }
            .foregroundStyle(Palette.secondary)
            if content.lines.isEmpty {
                Spacer(minLength: 0)
                Text(WidgetText.emptyMessage(content))
                    .font(Sora.font(13, .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(content.lines.prefix(Self.maxRows).enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.07))
                    }
                    row(line)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// « ● KC 1 – 0 C9   [en direct Game 2] » ; à venir : « ● GEN vs FUR   jeu. 11:00 ».
    private func row(_ line: WidgetLine) -> some View {
        let text = WidgetText.row(line, now: content.date)
        return HStack(spacing: 6) {
            HStack(spacing: -3) {
                ForEach(Array(line.colorHexes.compactMap { $0 }.enumerated()), id: \.offset) { _, hex in
                    Circle()
                        .fill(Palette.team(hex))
                        .frame(width: 7, height: 7)
                }
            }
            Text(text.title)
                .font(Sora.font(13, .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            if text.isLive {
                HStack(spacing: 3) {
                    IconView(icon: text.isMasked ? .eyeOff : .live, size: 10)
                    Text(text.trailing)
                }
                .font(Sora.font(10, .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12), in: Capsule())
            } else {
                Text(text.trailing)
                    .font(Sora.font(11, .regular))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}
```

- [ ] **Step 4 : Contenus d'exemple**

Créer `Shared/Preview/WidgetSamples.swift` :

```swift
import Foundation
import LoLKit

/// Contenus d'exemple des widgets (galerie quand aucune équipe n'est suivie, aperçus PNG), tirés de `SampleData`.
enum WidgetSamples {
    /// 15 oct., 17:05 UTC : KC en direct (1 – 0, game 2), T1 en direct masqué, GEN à venir le lendemain.
    static let now = SampleData.date("2026-10-15T17:05:00Z")

    static var input: WidgetInput {
        WidgetInput(follows: SampleData.follows, settings: AppSettings(),
                    schedule: Cached(value: SchedulePage(leagueIds: [], events: SampleData.schedule), fetchedAt: now),
                    live: Cached(value: SampleData.live, fetchedAt: now))
    }

    static var live: WidgetContent {
        WidgetTimeline.content(at: now, input: input)
    }

    /// Seule T1 (anti-spoiler) est suivie : son match en direct ne montre que « En direct ».
    static var maskedLive: WidgetContent {
        var masked = input
        masked.follows = FollowList(teams: SampleData.follows.teams.filter(\.spoilerFree))
        return WidgetTimeline.content(at: now, input: masked)
    }

    /// Le lendemain à 7 h (Paris) : plus rien n'est sûr d'être en direct ; GEN vs FUR à 11 h, T1 « Prochain · masqué ».
    static var upcoming: WidgetContent {
        WidgetTimeline.content(at: SampleData.date("2026-10-16T05:00:00Z"), input: input)
    }

    /// Aucune équipe suivie.
    static var empty: WidgetContent {
        WidgetTimeline.content(at: now, input: WidgetInput())
    }
}
```

- [ ] **Step 5 : Planches et rendu `ImageRenderer` (support de test)**

Créer `Tests/FailleTests/Support/WidgetBoard.swift` :

```swift
import LoLKit
import SwiftUI
import UIKit
@testable import Faille

/// Tailles approximatives des familles de widgets sur un iPhone de 6,3 pouces (écran de 402 × 874 pt).
enum WidgetSize {
    static let screen = CGSize(width: 402, height: 874)
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let rectangular = CGSize(width: 172, height: 76)
    static let circular = CGSize(width: 76, height: 76)
    static let inline = CGSize(width: 257, height: 26)
    /// Marge que iOS met autour du contenu des widgets de l'écran d'accueil.
    static let homeMargin: CGFloat = 16
}

/// Un état d'un widget sur une planche : sa légende et ce qu'il montre.
struct BoardState {
    let caption: String
    let content: WidgetContent
}

/// Un petit widget sur la planche : sa légende et l'équipe qu'il montre.
struct SmallState {
    let caption: String
    let team: WidgetTeam?
}

/// Fond d'écran sombre des planches (comme la maquette de l'écran verrouillé).
struct BoardWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.20), Color(red: 0.04, green: 0.05, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.23, green: 0.31, blue: 0.56), .clear],
                           center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.12, green: 0.43, blue: 0.47), .clear],
                           center: UnitPoint(x: 0.9, y: 0.8), startRadius: 0, endRadius: 360)
        }
    }
}

/// Légende d'un état sur une planche.
struct BoardCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.label)
            .tracking(Typo.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.6))
    }
}

/// Planche de l'écran verrouillé (spec §7) : pour chaque état, les widgets en ligne, rectangulaire et rond, en blanc
/// sur le fond d'écran, avec le fond translucide que iOS pose sous le rectangulaire et le rond.
struct LockScreenBoard: View {
    let states: [BoardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 8) {
                    BoardCaption(text: state.caption)
                    InlineWidgetView(content: state.content)
                        .frame(width: WidgetSize.inline.width, height: WidgetSize.inline.height, alignment: .leading)
                    HStack(spacing: 12) {
                        RectangularWidgetView(content: state.content)
                            .padding(.horizontal, 10)
                            .frame(width: WidgetSize.rectangular.width, height: WidgetSize.rectangular.height)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        CircularWidgetView(content: state.content)
                            .frame(width: WidgetSize.circular.width, height: WidgetSize.circular.height)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white)
        .padding(24)
        .frame(width: WidgetSize.screen.width, height: WidgetSize.screen.height, alignment: .topLeading)
        .background(BoardWallpaper())
    }
}

/// Planche de l'écran d'accueil (spec §7) : petits widgets (une équipe chacun), puis moyens, sur leur fond DA.
struct HomeScreenBoard: View {
    let smalls: [SmallState]
    let mediums: [BoardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(stride(from: 0, to: smalls.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(start..<min(start + 2, smalls.count), id: \.self) { index in
                        smallTile(smalls[index])
                    }
                }
            }
            ForEach(Array(mediums.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 4) {
                    BoardCaption(text: state.caption)
                    tile(MediumWidgetView(content: state.content), size: WidgetSize.medium, tint: nil)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(width: WidgetSize.screen.width, height: WidgetSize.screen.height, alignment: .topLeading)
        .background(BoardWallpaper())
    }

    private func smallTile(_ state: SmallState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BoardCaption(text: state.caption)
            tile(SmallWidgetView(team: state.team), size: WidgetSize.small,
                 tint: state.team.map { Palette.team($0.team.colorHex) })
        }
    }

    /// Un widget de l'écran d'accueil comme iOS le pose : marge, fond DA (`WidgetBackdrop`), coins arrondis.
    private func tile(_ content: some View, size: CGSize, tint: Color?) -> some View {
        content
            .padding(WidgetSize.homeMargin)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackdrop(tint: tint))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Rendu des widgets par `ImageRenderer` : leurs vues sont de simples vues SwiftUI (ni ScrollView, ni verre, ni
/// matière), contrairement aux écrans de l'appli, photographiés par `Snapshot` (drawHierarchy).
@MainActor
enum WidgetRender {
    /// Écrit la planche en PNG (×3) dans `build/apercus/`, à côté des captures d'écran de `Snapshot`.
    @discardableResult
    static func write(_ view: some View, size: CGSize, named name: String) throws -> URL {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        guard let png = renderer.uiImage?.pngData() else {
            throw Snapshot.Failure(description: "ImageRenderer n'a rien rendu pour \(name)")
        }
        try FileManager.default.createDirectory(at: Snapshot.directory, withIntermediateDirectories: true)
        let url = Snapshot.directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }

    /// Part des pixels non transparents d'une vue rendue seule, sur fond transparent : 0 si elle ne dessine rien.
    static func inkRatio(_ view: some View, size: CGSize) -> Double {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return 0 }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        let ink = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
        return Double(ink) / Double(width * height)
    }
}
```

- [ ] **Step 6 : Tests des planches et des familles**

Créer `Tests/FailleTests/WidgetSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Écran verrouillé (spec §7) : en ligne, rectangulaire et rond, dans quatre états.
    @Test func lockScreenWidgets() throws {
        let board = LockScreenBoard(states: [
            BoardState(caption: "En direct · KC", content: WidgetSamples.live),
            BoardState(caption: "En direct masqué · T1", content: WidgetSamples.maskedLive),
            BoardState(caption: "À venir · GEN", content: WidgetSamples.upcoming),
            BoardState(caption: "Aucune équipe suivie", content: WidgetSamples.empty),
        ])
        let url = try WidgetRender.write(board, size: WidgetSize.screen, named: "09-widgets-verrouille")
        expectNotBlank(url)
    }

    /// Écran d'accueil (spec §7) : quatre petits widgets (une équipe chacun) et deux moyens.
    @Test func homeScreenWidgets() throws {
        let board = HomeScreenBoard(
            smalls: [
                SmallState(caption: "KC · en direct", team: WidgetSamples.live.team(id: "kc")),
                SmallState(caption: "T1 · en direct masqué", team: WidgetSamples.live.team(id: "t1")),
                SmallState(caption: "GEN · prochain", team: WidgetSamples.live.team(id: "gen")),
                SmallState(caption: "T1 · prochain masqué", team: WidgetSamples.upcoming.team(id: "t1")),
            ],
            mediums: [
                BoardState(caption: "Mes équipes · en direct", content: WidgetSamples.live),
                BoardState(caption: "Mes équipes · le lendemain", content: WidgetSamples.upcoming),
            ]
        )
        let url = try WidgetRender.write(board, size: WidgetSize.screen, named: "10-widgets-accueil")
        expectNotBlank(url)
    }

    /// Chaque famille dessine vraiment quelque chose : une vue vide passerait inaperçue sur une planche dont le fond
    /// pèse déjà son poids.
    @Test func everyWidgetFamilyDrawsItsContent() {
        let content = WidgetSamples.live
        #expect(WidgetRender.inkRatio(InlineWidgetView(content: content), size: WidgetSize.inline) > 0.01)
        #expect(WidgetRender.inkRatio(RectangularWidgetView(content: content), size: WidgetSize.rectangular) > 0.01)
        #expect(WidgetRender.inkRatio(CircularWidgetView(content: content), size: WidgetSize.circular) > 0.01)
        #expect(WidgetRender.inkRatio(SmallWidgetView(team: content.team(id: "kc")), size: WidgetSize.small) > 0.01)
        #expect(WidgetRender.inkRatio(MediumWidgetView(content: content), size: WidgetSize.medium) > 0.01)
    }
}

/// Les exemples des planches et de la galerie couvrent chaque état : direct, masqué, à venir, rien.
struct WidgetSampleTests {
    @Test func samplesCoverEveryState() {
        #expect(WidgetSamples.live.lines.map(\.matchId) == [SampleData.kcMatchId, SampleData.t1MatchId, "m-gen-fur"])
        #expect(WidgetSamples.live.headline?.status == .live(score: [1, 0], gameNumber: 2))
        #expect(WidgetSamples.maskedLive.headline?.isMasked == true)
        #expect(WidgetSamples.upcoming.headline?.matchId == "m-gen-fur")
        #expect(WidgetSamples.upcoming.team(id: "t1")?.next == .hidden)
        #expect(WidgetSamples.empty.teams.isEmpty)
    }
}
```

- [ ] **Step 7 : Commit et push**

```bash
git add Shared/Widgets/WidgetChrome.swift Shared/Widgets/AccessoryWidgetViews.swift Shared/Widgets/HomeWidgetViews.swift Shared/Preview/WidgetSamples.swift Tests/FailleTests/Support/WidgetBoard.swift Tests/FailleTests/WidgetSnapshotTests.swift
git commit -m "feat(widgets): vues des cinq widgets (Sora, monochrome, Vitrail) et planches PNG" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 8 : CI iOS et aperçus**

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
cp "$HOME/Downloads/faille-apercus-<id>/"*.png .superpowers/apercus/
```

Expected : `build` et `apercus` verts ; l'artefact contient `09-widgets-verrouille.png` et `10-widgets-accueil.png` (1206 × 2622 px, chacun > 100 000 octets) en plus des 10 PNG de l'étape 2. Les vues compilent aussi dans l'extension (encore en Swift 5 à ce stade). Erreurs probables et replis :
- `capture quasi vide` sur une planche (< 100 000 octets) ou planche blanche : rendre cette planche avec `Snapshot.write(board, named:)` (drawHierarchy, async — passer le test en `async throws` et `try await`) au lieu de `WidgetRender.write` ; ne jamais baisser le seuil ni ajouter de bruit.
- `inkRatio` à 0 pour `InlineWidgetView` : `ImageRenderer` ne rend pas ce `Label` ; remplacer `Label { … } icon: { … }` par `HStack(spacing: 4) { InlineIcon.image(…); Text(…) }` dans `InlineWidgetView`.
- Erreur Swift 6 sur `InlineIcon` (isolation) : garder `@MainActor` sur l'enum (les `body` sont `@MainActor`) ; ne pas ajouter de `@preconcurrency` global.

---

### Task 6 : Les cinq widgets dans l'extension (la sonde widget s'en va)

**Files :**
- Create : `Widgets/WidgetTimelines.swift`
- Create : `Widgets/SelectTeamIntent.swift`
- Create : `Widgets/LockScreenWidget.swift`
- Create : `Widgets/HomeWidgets.swift`
- Modify (réécrit) : `Widgets/FailleWidgets.swift`
- Modify : `project.yml` (commentaire de la cible `Faille` ; `SWIFT_VERSION` de `FailleWidgets`)
- Modify : `.github/workflows/ios.yml` (étape « Vérifier Sora et les icônes dans l'extension »)

**Interfaces :**
- Consumes : `WidgetInput.shared()` (Task 4) ; `WidgetTimeline.content(at:input:)`, `.entryDates(now:input:)`, `.reloadDate(now:input:)`, `WidgetContent.team(id:)` (Task 2) ; `InlineWidgetView`, `RectangularWidgetView`, `CircularWidgetView`, `SmallWidgetView(team:)`, `MediumWidgetView(content:)`, `WidgetBackdrop(tint:)`, `WidgetSamples.live` (Task 5) ; `FileStore(directory:readOnly:)`, `AppGroup.directory`, `Palette.team(_:)` ; `ProbeAttributes` (inchangé).
- Produces :
  - `struct FailleEntry: TimelineEntry { date: Date; content: WidgetContent }` ; `struct TeamEntry: TimelineEntry { date; content; teamId: String? }`
  - `enum FailleTimeline { static func make<Entry: TimelineEntry>(now: Date = Date(), input: WidgetInput = .shared(), _ entry: (Date, WidgetContent) -> Entry) -> Timeline<Entry> ; static func current(isPreview: Bool, now: Date = Date()) -> WidgetContent }`
  - `struct FailleProvider: TimelineProvider`, `struct TeamProvider: AppIntentTimelineProvider`
  - `struct SelectTeamIntent: WidgetConfigurationIntent` (`team: TeamEntity?`), `struct TeamEntity: AppEntity` (`id`, `code`, `name`, `static func followed() -> [TeamEntity]`), `struct TeamQuery: EntityQuery`
  - kinds `FailleLockScreen`, `FailleTeam`, `FailleTeams` ; `ProbeLiveActivity` gardée

- [ ] **Step 1 : Entrées et fournisseurs de planning**

Créer `Widgets/WidgetTimelines.swift` :

```swift
import AppIntents
import LoLKit
import WidgetKit

/// Entrée des widgets non configurables : ce qu'ils montrent à sa date.
struct FailleEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
}

/// Entrée du petit widget : la même chose, plus l'équipe choisie dans ses réglages (nil = la première suivie).
struct TeamEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
    let teamId: String?
}

/// Planning commun (spec §7) : une entrée à chaque date de `WidgetTimeline.entryDates` (début de chaque match, paliers
/// du compte à rebours, fin de confiance du direct), rechargement à `WidgetTimeline.reloadDate` (prochain début de
/// match, au plus tard 30 min). Lecture seule du groupe d'apps.
enum FailleTimeline {
    static func make<Entry: TimelineEntry>(now: Date = Date(), input: WidgetInput = .shared(),
                                           _ entry: (Date, WidgetContent) -> Entry) -> Timeline<Entry> {
        let entries = WidgetTimeline.entryDates(now: now, input: input).map { date in
            entry(date, WidgetTimeline.content(at: date, input: input))
        }
        return Timeline(entries: entries, policy: .after(WidgetTimeline.reloadDate(now: now, input: input)))
    }

    /// Instantané (galerie, réglages du widget) : l'état présent ; un exemple si aucune équipe n'est encore suivie.
    static func current(isPreview: Bool, now: Date = Date()) -> WidgetContent {
        let input = WidgetInput.shared()
        if isPreview && input.follows.teams.isEmpty {
            return WidgetSamples.live
        }
        return WidgetTimeline.content(at: now, input: input)
    }
}

/// Planning des widgets de l'écran verrouillé et du moyen widget.
struct FailleProvider: TimelineProvider {
    func placeholder(in context: Context) -> FailleEntry {
        FailleEntry(date: Date(), content: WidgetSamples.live)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FailleEntry) -> Void) {
        completion(FailleEntry(date: Date(), content: FailleTimeline.current(isPreview: context.isPreview)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FailleEntry>) -> Void) {
        completion(FailleTimeline.make { FailleEntry(date: $0, content: $1) })
    }
}

/// Planning du petit widget : celui des autres widgets, avec l'équipe choisie dans ses réglages.
struct TeamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamEntry {
        TeamEntry(date: Date(), content: WidgetSamples.live, teamId: nil)
    }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> TeamEntry {
        TeamEntry(date: Date(), content: FailleTimeline.current(isPreview: context.isPreview),
                  teamId: configuration.team?.id)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<TeamEntry> {
        let teamId = configuration.team?.id
        return FailleTimeline.make { TeamEntry(date: $0, content: $1, teamId: teamId) }
    }
}
```

- [ ] **Step 2 : Réglage du petit widget (AppIntent)**

Créer `Widgets/SelectTeamIntent.swift` :

```swift
import AppIntents
import LoLKit
import WidgetKit

/// Réglage du petit widget (spec §7) : l'équipe suivie dont il montre le prochain match. Sans choix, la première
/// équipe suivie. Propriétés statiques calculées (forme du modèle de widget de Xcode) : rien de mutable partagé.
struct SelectTeamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Équipe" }
    static var description: IntentDescription { "Le prochain match de l'équipe choisie." }

    @Parameter(title: "Équipe")
    var team: TeamEntity?
}

/// Une équipe suivie, proposée dans les réglages du petit widget (lue dans follows.json, en lecture seule).
struct TeamEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Équipe" }
    static var defaultQuery: TeamQuery { TeamQuery() }

    let id: String
    let code: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(code)")
    }

    /// Équipes suivies, dans l'ordre de suivi.
    static func followed() -> [TeamEntity] {
        let follows = FileStore(directory: AppGroup.directory, readOnly: true).load(FollowList.self, from: .follows)
            ?? FollowList()
        return follows.teams.map { TeamEntity(id: $0.id, code: $0.code, name: $0.name) }
    }
}

/// Les équipes proposées : celles que l'appli suit ; par défaut, la première.
struct TeamQuery: EntityQuery {
    func entities(for identifiers: [TeamEntity.ID]) async throws -> [TeamEntity] {
        TeamEntity.followed().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TeamEntity] {
        TeamEntity.followed()
    }

    func defaultResult() async -> TeamEntity? {
        TeamEntity.followed().first
    }
}
```

- [ ] **Step 3 : Widgets de l'écran verrouillé**

Créer `Widgets/LockScreenWidget.swift` :

```swift
import LoLKit
import SwiftUI
import WidgetKit

/// Widgets de l'écran verrouillé (spec §7) : en ligne, rectangulaire, rond. iOS les rend en monochrome : Sora et les
/// icônes, sans couleur d'équipe.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FailleLockScreen", provider: FailleProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Prochain match")
        .description("Le match en direct ou le prochain match de tes équipes.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

/// Une famille, une vue ; le fond est celui de iOS (translucide pour le rectangulaire et le rond).
struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FailleEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineWidgetView(content: entry.content)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            CircularWidgetView(content: entry.content)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            RectangularWidgetView(content: entry.content)
                .padding(.horizontal, 2)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }
}
```

- [ ] **Step 4 : Widgets de l'écran d'accueil**

Créer `Widgets/HomeWidgets.swift` :

```swift
import AppIntents
import LoLKit
import SwiftUI
import WidgetKit

/// Petit widget (spec §7) : le prochain match d'une équipe suivie, teinté à sa couleur ; l'équipe se choisit dans les
/// réglages du widget (par défaut, la première suivie).
struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FailleTeam", intent: SelectTeamIntent.self, provider: TeamProvider()) { entry in
            TeamWidgetView(entry: entry)
        }
        .configurationDisplayName("Mon équipe")
        .description("Le prochain match d'une équipe suivie, à sa couleur.")
        .supportedFamilies([.systemSmall])
    }
}

struct TeamWidgetView: View {
    let entry: TeamEntry

    var body: some View {
        let team = entry.content.team(id: entry.teamId)
        SmallWidgetView(team: team)
            .containerBackground(for: .widget) {
                WidgetBackdrop(tint: team.map { Palette.team($0.team.colorHex) })
            }
    }
}

/// Moyen widget (spec §7) : matchs en direct, puis prochains matchs de toutes les équipes suivies.
struct TeamsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FailleTeams", provider: FailleProvider()) { entry in
            MediumWidgetView(content: entry.content)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: nil) }
        }
        .configurationDisplayName("Mes équipes")
        .description("Les matchs en direct, puis les prochains matchs de tes équipes.")
        .supportedFamilies([.systemMedium])
    }
}
```

- [ ] **Step 5 : Le bundle — la sonde widget s'en va, la Live Activity sonde reste**

Remplacer tout le contenu de `Widgets/FailleWidgets.swift` par :

```swift
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        LockScreenWidget()
        TeamWidget()
        TeamsWidget()
        // Sonde de l'étape 0 : la Live Activity des matchs la remplace à l'étape 4.
        ProbeLiveActivity()
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

- [ ] **Step 6 : Extension en Swift 6**

Dans `project.yml`, cible `Faille`, remplacer le commentaire :

```yaml
        # Appli en Swift 6 (concurrence stricte) ; l'extension reste en Swift 5 jusqu'à l'étape 3.
```

par :

```yaml
        # Appli en Swift 6 (concurrence stricte), comme l'extension depuis l'étape 3.
```

et, cible `FailleWidgets`, ajouter `SWIFT_VERSION` sous `settings.base` :

```yaml
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille.widgets
        SWIFT_VERSION: "6.0"
        # Pas d'icône ni de couleur d'accent dans le catalogue : actool ne doit pas les chercher.
        ASSETCATALOG_COMPILER_APPICON_NAME: ""
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: ""
```

- [ ] **Step 7 : CI — métadonnées de l'AppIntent**

Dans `.github/workflows/ios.yml`, à la fin du `run:` de l'étape « Vérifier Sora et les icônes dans l'extension », ajouter :

```yaml
          # Réglages du petit widget (AppIntent) : métadonnées extraites à la compilation.
          ls "$APPEX/Metadata.appintents" || echo "::warning::Metadata.appintents absent de l'extension : le choix d'équipe du petit widget risque de manquer"
```

- [ ] **Step 8 : Commit et push**

```bash
git add Widgets/WidgetTimelines.swift Widgets/SelectTeamIntent.swift Widgets/LockScreenWidget.swift Widgets/HomeWidgets.swift Widgets/FailleWidgets.swift project.yml .github/workflows/ios.yml
git commit -m "feat(widgets): les cinq widgets remplacent la sonde ; extension en Swift 6" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 9 : CI iOS**

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run view <id> --log | grep -E "Metadata.appintents|::warning::"
```

Expected : `build` et `apercus` verts ; `Metadata.appintents` listé dans l'`.appex` (sinon un avertissement, à signaler dans le rapport) ; les deux planches toujours produites. Erreurs probables et replis (dans cet ordre) :
1. « sendability of function types in instance method 'getSnapshot(in:completion:)' (ou 'getTimeline') does not match requirement in protocol 'TimelineProvider' » → retirer `@Sendable` des deux signatures de `FailleProvider` (ou l'ajouter, selon ce que dit le message).
2. Erreur de concurrence sur une propriété statique de `SelectTeamIntent` / `TeamEntity` (ex. « not concurrency-safe ») → elles sont déjà calculées ; si l'extracteur de métadonnées exige une valeur littérale stockée (« Expected a literal »), écrire `static let title: LocalizedStringResource = "Équipe"` (idem `description`, `typeDisplayRepresentation`) et, si Swift 6 le refuse, préfixer de `nonisolated(unsafe)`.
3. Si une erreur de concurrence venant d'un protocole WidgetKit / AppIntents persiste : remettre `SWIFT_VERSION: "5.0"` dans la cible `FailleWidgets` (une ligne) et le noter dans le rapport — `Shared/` reste en Swift 6 par l'appli.
4. « Ambiguous use of 'WidgetContent' » (ou d'un autre nom `Widget…` de LoLKit) avec un futur symbole de WidgetKit → qualifier `LoLKit.WidgetContent` dans le fichier fautif.

---

### Task 7 : Sur l'iPhone — checklist de Dan (manuelle)

**Files :**
- Create : `docs/superpowers/notes/2026-10-etape-3-verdict.md`

**Interfaces :**
- Consumes : l'IPA du dernier run iOS vert (artefact `Faille-ipa`), installée avec AltServer (`docs/superpowers/notes/2026-10-etape-0-verdict.md`).
- Produces : le verdict de l'étape 3 (spec §13 : « Widgets justes sur l'iPhone, aperçus PNG en CI »).

- [ ] **Step 1 : Préparer l'IPA**

```bash
gh run list --workflow iOS --branch main --status success --limit 1 --json databaseId,headSha --jq '.[0]'
gh run download <id> --name Faille-ipa --dir "$HOME/Downloads/faille-ipa-<id>" && ls -la "$HOME/Downloads/faille-ipa-<id>"
```

Expected : `Faille.ipa`. Le contrôleur la donne à Dan avec les vérifications du Step 2 ; Dan l'installe avec AltServer (le widget « Sonde Faille » déjà posé sur son écran d'accueil devient vide : il le retire).

- [ ] **Step 2 : Vérifications de Dan (une réponse par ligne)**

1. Ouvrir Faille, tirer pour rafraîchir. Écran verrouillé → Personnaliser → ajouter « Prochain match » en ligne (au-dessus de l'heure), rectangulaire et rond. Monochrome, police Sora (pas la police système), icônes au trait ; le contenu correspond à l'onglet Matchs (match en direct, sinon le prochain).
2. Le rond : compte à rebours (« 21h », « 45 min ») et code de l'équipe ; la jauge avance au fil des heures ; il descend par paliers de 5 min dans la dernière heure.
3. Écran d'accueil : ajouter « Mon équipe » (petit) → il montre la première équipe suivie, teinté à sa couleur, avec les monogrammes ; Modifier le widget → choisir une autre équipe → il bascule sur elle.
4. Ajouter « Mes équipes » (moyen) : matchs en direct d'abord, puis les prochains matchs (4 lignes au plus), points de couleur des équipes.
5. Anti-spoiler : une équipe en anti-spoiler dont le dernier match est terminé → widgets « Prochain · masqué » / « masqué », jamais de score ni de numéro de game ; pendant un de ses matchs, seulement « En direct ».
6. Révéler ce match dans l'appli, revenir à l'écran d'accueil : les widgets montrent le score / le prochain match en quelques secondes.
7. Suivre ou ne plus suivre une équipe : les widgets suivent en quelques secondes.
8. Pendant un match des Worlds, appli ouverte puis fermée : le widget en ligne affiche « KC 1–0 C9 · G2 » ; une dizaine de minutes après la fermeture, la ligne « en direct » disparaît (le widget ne prétend pas connaître le direct sans données fraîches).
9. À l'heure de début d'un prochain match (si l'occasion se présente) : les widgets passent au match suivant.
10. iPad (si disponible) : petit et moyen widgets.

- [ ] **Step 3 : Écrire le verdict**

Créer `docs/superpowers/notes/2026-10-etape-3-verdict.md` avec, pour en-tête, la date, l'id du run et le SHA de l'IPA, puis le tableau des 10 vérifications du Step 2 (colonnes : n°, vérification, résultat « OK » / « KO » + remarque de Dan), puis les écarts constatés et les décisions qui en découlent (ex. icône du widget en ligne trop grande → widget en ligne sans icône ; Sora absente → enregistrement de la police par `CTFontManagerRegisterFontsForURL` à l'initialisation du bundle).

- [ ] **Step 4 : Commit et push**

```bash
git add docs/superpowers/notes/2026-10-etape-3-verdict.md
git commit -m "docs: verdict de l'étape 3 sur l'iPhone" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

Expected : verdict commité ; chaque KO devient une tâche de correction (même cycle : code, push, CI) avant l'étape 4.

---

## Auto-relecture

**1. Couverture de la spec**

| Exigence | Tâche |
|---|---|
| §7 widget en ligne « KC 1–0 C9 · G2 » / « GEN vs FUR · jeu. 11:00 » | T3 (`WidgetText.inline`, testé), T5 (vue), T6 (famille `.accessoryInline`) |
| §7 rectangulaire « PROCHAIN », match, date et heure (ou direct) | T3 (`rectangular`), T5, T6 |
| §7 rond : compte à rebours (jauge) + code de l'équipe | T3 (`circular` : texte, code, progression sur 24 h), T5, T6 |
| §7 petit : prochain match d'une équipe, teinté ; équipe choisie par AppIntent, défaut = première suivie | T2 (`team(id:)`), T3 (`small`), T5, T6 (`SelectTeamIntent`, `TeamEntity`, `TeamQuery`) |
| §7 moyen : direct puis prochains matchs de toutes les équipes (4 lignes) | T2 (`lines`), T3 (`row`), T5 (`maxRows = 4`), T6 |
| §7 monochrome, Sora et icônes sur l'écran verrouillé | T4 (police + catalogue dans l'extension, vérifiés en CI), T5 (`.primary` / `.secondary` seulement) |
| §7 planning : entrée à chaque début de match, rechargement 30 min ou prochain début | T2 (`entryDates`, `reloadDate`, testés), T6 (`Timeline(…, policy: .after(…))`) |
| §7 `reloadAllTimelines` à chaque rafraîchissement du calendrier au premier plan | T4 (`cycle` → `reloadWidgets()`, testé) |
| §8 match masqué : ni score, ni game, ni vainqueur ; « En direct » / date | T2 (`Presenter.scoreLine`), T3 (`maskedTextsNeverCarryAScoreOrAGame`), T2 (`noEntryEverShows…`) |
| §8 « Prochain · masqué » (F1) partout, y compris quand le cache vieillit | T2 (`Presenter.nextLine`, `presumed`, tests 3, 7, 8) |
| §8 widgets suivent une révélation | T2 (`revealed`), T4 (`saveSettings` → rechargement, testé) |
| §4.4 groupe résolu à l'exécution, lecture seule, monogrammes sans logo | T4 (`WidgetInput.shared()`), T5 (`MonogramBadge`), T6 (`TeamEntity.followed()`) |
| §9 DA : abysse, teinte d'équipe, Sora, icônes | T5 (`WidgetBackdrop`, `SmallWidgetView`, `MediumWidgetView`) |
| §11.3 PNG des widgets en artefact | T5 (`09-widgets-verrouille.png`, `10-widgets-accueil.png`, contrôle par famille) |
| §13 widgets justes sur l'iPhone | T7 |
| Dettes étape 2 : `reorder`, `lastRowText`, libellés masqués vers LoLKit | T1 |

Hors périmètre, assumé : log de `LossyArray` (M14, optionnel) ; fuite inter-équipes héritée de F1 (voir « Décisions ») ; plan B sans groupe d'apps (inutile depuis le verdict de l'étape 0).

**2. Recherche de trous** : chaque fichier créé a son code complet ; chaque fichier modifié a son ancien et son nouveau texte exacts ; les seuls champs à remplir sont l'id de run (`<id>`, sortie d'une commande donnée) et les résultats de Dan (T7, manuels par nature).

**3. Cohérence des types** (vérifiée contre les sources) : `TeamCards.build(follows:schedule:live:revealed:)`, `Presenter.nextLine(for:follows:revealed:)` → `NextLine` (`.hidden` / `.none` / `.match`), `Presenter.scoreLine(for:follows:revealed:)` → `ScoreLine.Status` (`.upcoming(Date)`, `.live(gameNumber:)`, `.finished(winnerCode:)`), `FollowList.displayOrder(_:preferring:)`, `RefreshPolicy.usableLive(_:now:)` / `.liveTrust`, `Cached.age(now:)`, `SchedulePage(leagueIds:events:)`, `AppSettings(revealedMatchIds:)`, `FileStore(directory:readOnly:)` / `.load(_:from:)`, `AppGroup.directory`, `Palette.team(_:)`, `Sora.font(_:_:)`, `IconView(icon:size:)`, `Icon.eyeOff`, `Snapshot.directory`, `Snapshot.Failure(description:)`, `ApercuTests.expectNotBlank(_:)`, `ScriptedTransport(mode:)`, `TemporaryFiles.directory()`. Noms produits et réutilisés à l'identique : `WidgetInput`, `WidgetLine.Status.live(score:gameNumber:)` / `.upcoming(_:)`, `WidgetLine.isLive` / `.upcomingStart`, `WidgetTeam.Next.live / .match / .hidden / .noMatch`, `WidgetContent.headline` / `.team(id:)`, `WidgetTimeline.content(at:input:)` / `.entryDates(now:input:)` / `.reloadDate(now:input:)`, `WidgetText.Rectangular / Circular / Row / Small`, `WidgetSamples.live / .maskedLive / .upcoming / .empty`, `FailleEntry`, `TeamEntry`, `FailleTimeline.make` / `.current(isPreview:)`. `WidgetTeam.Next` n'a volontairement pas de cas `.none` (confusion avec `Optional.none` dans `team(id:)?.next == …`).

**4. API iOS 26 / WidgetKit / AppIntents — prudence et replis**

| API | Tâche | Risque | Repli |
|---|---|---|---|
| `TimelineProvider` avec `completion: @escaping @Sendable` en Swift 6 | T6 | signature du SDK différente → « sendability … does not match requirement » | retirer / ajouter `@Sendable` ; sinon extension en Swift 5 |
| `WidgetConfigurationIntent`, `@Parameter`, `AppEntity`, `EntityQuery.defaultResult()` | T6 | concurrence stricte sur les statiques ; extraction des métadonnées ; `defaultResult` peut ne pas pré-remplir le réglage | statiques calculées (forme du modèle Xcode) → `static let` (+ `nonisolated(unsafe)`) ; sans pré-remplissage, `team == nil` donne quand même la première équipe (`WidgetContent.team(id:)`) |
| `UIAppFonts` dans une extension widget + `Resources` dans l'`.appex` | T4 | police non enregistrée | présence vérifiée en CI ; sur l'iPhone, `Sora.uiFont` retombe sur la police système ; repli : `CTFontManagerRegisterFontsForURL` à l'init du bundle (T7) |
| `ImageRenderer` (`uiImage`, `cgImage`, `isOpaque`, `scale`) | T5 | `Label` ou image mal rendus ; planche < 100 000 octets | `HStack` au lieu de `Label` ; planche rendue par `Snapshot.write` (drawHierarchy) |
| Image d'un widget `.accessoryInline` | T5, T7 | taille propre de l'image, cadres ignorés | redessinée à 14 pt (`InlineIcon`) ; sinon widget en ligne sans icône |
| `containerBackground(for: .widget)` + `AccessoryWidgetBackground()` | T6 | obligatoire depuis iOS 17 (sinon « adopt containerBackground API ») | posé sur chaque famille, y compris en ligne (`Color.clear`) |
| `.widgetAccentable()` dans `Shared/` (compilé dans l'appli) | T5 | aucun : WidgetKit est déjà importé par l'appli | — |
| `glassEffect` / matières | — | réservés aux barres système (étape 2) ; illisibles dans un widget | non utilisés : dégradés seulement |
