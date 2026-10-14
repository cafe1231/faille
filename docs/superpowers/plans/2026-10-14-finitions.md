# Finitions — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** donner à Faille le style « A — sobre et fluide, façon Apple » de la spec finitions : un vocabulaire de mouvement unique (`Motion`), des surfaces qui s'enfoncent au toucher, des retours haptiques sur les actions, des chiffres qui défilent, un halo « en direct » qui respire, la transition zoom carte → Détail, des listes animées, la révélation anti-spoiler qui sort d'un flou, des pilules dont la capsule glisse, des squelettes de chargement, un bandeau d'erreur qui glisse, la lueur d'équipe, et l'icône de l'appli — sans rien changer aux données ni aux règles, et sans jamais trahir un match masqué. Terminé quand la checklist « Finitions » passe sur l'iPhone de Dan.

**Architecture :** `Shared/DA/Motion.swift` porte tout le vocabulaire (durées, ressorts, règle « Réduire les animations », transitions, chiffres qui défilent), compilé dans l'appli et l'extension. « Réduire les animations » se lit partout par `@ReduceMotion` (réglage du système, sauf si la valeur d'environnement `reduceMotionOverride` le force : les aperçus PNG la mettent à vrai pour être rendus dans leur état final). Les effets de l'appli sont des briques de `App/DA/` (`PressableStyle`, `Haptic`/`HapticTrigger`, `LiveIndicator`, `TeamGlow`, `CascadeIn`, `SkeletonBlock`…) posées sur les écrans existants ; elles ne s'appliquent qu'aux valeurs déjà décidées par `Presenter` / `SpoilerPolicy` / `LiveMatchBuilder`. L'icône est dessinée par une vue SwiftUI (`AppIconArt`), rendue à 1024 px par un test hébergé, puis versée dans le catalogue.

**Tech Stack :** Swift 6 (appli, extension, tests), SwiftUI iOS 26 (`.sensoryFeedback(trigger:_:)`, `.contentTransition(.numericText())`, `matchedGeometryEffect`, `.matchedTransitionSource(id:in:)` + `.navigationTransition(.zoom(sourceID:in:))`, `phaseAnimator`, `TimelineView(.animation)`, `AnyTransition`, `@Entry`, `DynamicProperty`), `ImageRenderer`, Swift Testing (tests hébergés), XcodeGen, actool (jeu d'icônes une taille, apparences sombre / teintée), GitHub Actions `macos-26` (Xcode 26), `gh`.

**Spec :** `docs/superpowers/specs/2026-10-14-faille-finitions-design.md` (contraignante : 12 points, Principes, Vérification) ; `docs/superpowers/specs/2026-10-13-faille-design.md` §5 (écrans), §8 (anti-spoiler), §9 (DA). Conventions : `docs/superpowers/notes/2026-10-14-etape-3-journal.md`, `docs/superpowers/notes/2026-10-14-etape-4-journal.md`. Checklist de l'iPhone : `docs/superpowers/notes/2026-10-14-checklist-iphone.md`.

## Global Constraints

- iOS minimum **26.0** ; appli, extension et tests en Swift 6 (`SWIFT_VERSION: "6.0"`) ; iPhone + iPad.
- Style **A — sobre et fluide, façon Apple** : « pas de particules, pas de rebond exagéré, pas d'effet qui retarde l'information » ; rebond au plus 0,08 (listes), 0 ailleurs ; pas de sons.
- Jetons nommés (spec) : `press` (≈0,18 s), `snappy` (≈0,3 s), `smooth` (≈0,45 s), `number` (chiffres), `list` (listes), `reveal` (≈0,5 s). Valeurs du plan : press 0,18 s ; snappy 0,3 s ; number 0,35 s ; list 0,4 s ; smooth 0,45 s ; reveal 0,5 s ; fondu 0,2 s ; halo « en direct » 1,6 s ; lueur d'équipe 2,4 s ; reflet des squelettes 1,6 s ; cascade 40 ms par carte, 8 cartes au plus ; échelle d'appui 0,97 ; échelle d'arrivée 0,96 ; flou de révélation 10 → 0.
- « Aucune durée en dur dans les vues » : toute durée, tout ressort passe par `Motion`.
- « Réduire les animations » : lu par `@ReduceMotion` (= `reduceMotionOverride ?? accessibilityReduceMotion`) ; « mouvements, zooms, cascades, pulsations et scintillements remplacés par un simple fondu (ou rien) ; les retours haptiques restent ».
- Anti-spoiler (spec §8) : « aucune animation ne trahit un match masqué » ; les effets ne s'appliquent qu'à des valeurs déjà affichées, donc déjà jugées par `Presenter` / `SpoilerPolicy` / `LiveMatchBuilder` ; jamais de `numericChange` sur un texte d'état masqué ; lueur seulement si `TeamCardView.glows(_:)` est vrai.
- Liquid Glass système (barre d'onglets, boutons de barre d'outils) : inchangé ; jamais de `glassEffect` sur les cartes.
- Widgets et Live Activity : « numericText content transitions only » — `.numericTransition()` seulement, jamais posé sur un conteneur qui contient un chrono qui tourne (`Text(_, style: .timer)`, `.reference`) ; ni `phaseAnimator`, ni `TimelineView`, ni `repeatForever` dans `Shared/Widgets` et `Shared/LiveActivity`.
- Zones tactiles inchangées (≥ 44 pt) : `PressableStyle` n'agit que sur le rendu.
- Icônes de l'interface : images du catalogue en rendu template (pas de SF Symbols, donc pas de `symbolEffect`).
- Icône de l'appli : 1024 × 1024 px, `ImageRenderer` à l'échelle 1 ; `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` pour l'appli seulement, `""` pour l'extension ; « Nothing may assume a fixed bundle id or app group ».
- Aperçus : `Snapshot.write` rend avec `reduceMotionOverride = true` ; les PNG existants (`00-da` … `13-dynamic-island`) restent > 100 000 octets (`ApercuTests.expectNotBlank`) et gardent leur mise en page ; nouveaux : `app-icon-1024.png`, `app-icon-1024-dark.png`, `app-icon-1024-tinted.png`, `14-icone.png` (1024 px de large), `15-chargement.png`, `03b-equipes-chargement.png`.
- LoLKit ne change pas (aucune modification sous `LoLKit/`).
- Le code iOS ne se compile **qu'en CI** : commit, `git push origin main`, run du workflow `iOS` retrouvé par le SHA **complet** (`gh run list --workflow iOS --commit "$(git rev-parse HEAD)"` ; un SHA court ne renvoie rien), `gh run watch --exit-status <id>` ; échec : `gh run view <id> --log-failed`.
- Avant chaque tâche : `git pull --ff-only origin main`, puis relire à HEAD les ancres citées par la tâche (d'autres lots peuvent avoir poussé entre-temps).
- Textes de l'interface en français ; identifiants en anglais ; commentaires en français ; fins de ligne LF.
- Commits avec l'adresse noreply déjà configurée ; chaque message se termine par un second `-m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Pousser sur `main` est autorisé.

## Décisions prises par ce plan (au-delà de la spec)

- **`Motion.swift` dans `Shared/DA/`** (la spec le permet) : les widgets et la Live Activity utilisent `numericTransition()` ; les effets animés de l'appli restent dans `App/DA/`.
- **Aperçus figés** : `Snapshot.write` force « Réduire les animations » par `reduceMotionOverride` : une capture prise 1 s après l'affichage ne tombe ni au milieu de la cascade ni à mi-respiration du halo ; le halo et la lueur y apparaissent fixes.
- **Règle « Réduire les animations » détaillée** : appui (échelle) et largeur de la barre de gold → immédiats (`nil`) ; chiffres, listes, révélation, bandeau, pilules, onglet des joueurs → fondu de 0,2 s ; halo, lueur → fixes ; reflet des squelettes, cascade, glissement de la capsule → retirés ; zoom → transition standard d'iOS (qui applique ses propres réglages d'accessibilité) ; révélation → fondu sans flou ; l'appui garde sa baisse d'opacité (ce n'est pas un mouvement).
- **Cascade une seule fois par vie de l'onglet Matchs** (première apparition) : pas au retour du Détail (la ligne vers laquelle le zoom se referme doit être visible), ni en changeant d'onglet.
- **Retours haptiques déclenchés par l'écran** (`HapticTrigger` dans la vue qui reste affichée : écran ou carte), uniquement sur une action de l'utilisateur ; « Épingler » refusé (3 déjà affichées, désactivé) : pas de retour ; couleur : au « Valider » qui enregistre un changement et à « Couleur automatique » (feuille et menu contextuel), pas pendant le choix dans le sélecteur ; pilule de game : seulement si la game affichée change.
- **Icône « en direct » ajoutée à la pilule de la game en cours** (« G2 · en direct » + icône) : la spec place le halo « derrière l'icône « en direct » … des pilules », qui n'en avaient pas.
- **Squelettes** : aussi à la place de « Stats en chargement… » (game en cours dont la première frame n'est pas arrivée) ; recherche sans catalogue et API en panne : « Équipes indisponibles pour l'instant. » au lieu de « Chargement des équipes… ».
- **Source du zoom** : la ligne touchée (bloc « En direct », ligne « Prochain », ligne « Dernier »), identifiant `"<id équipe>/<ligne>/<id match>"` ; `MatchRoute` porte `sourceID` (nil : transition standard).
- **Listes animées** : cartes de Matchs et lignes de « Mes équipes » ; pas les lignes du catalogue (des centaines, chargées à la demande), dont seule l'étoile change.
- **Onglet des joueurs** : fondu des lignes (`.id` + `.opacity`) animé par `Motion.snappy`.
- **Chiffres qui défilent aussi sur « N équipes suivies »** (même `ScreenHeader` que « N en direct · N à venir »).
- **Variantes de l'icône** : claire opaque (abysse `#0B1020` → `#040712`) ; sombre à fond transparent ; teintée opaque, fond noir, faille en niveaux de gris. Fichiers `app-icon-1024*.png` (mêmes noms dans l'artefact et dans `AppIcon.appiconset`). Planche `14-icone.png` : 512 × 680 pt à l'échelle 2.
- **Jeu `AppIcon` dans `Resources/Assets.xcassets`** (compilé aussi dans l'extension, qui garde `APPICON_NAME: ""`) ; repli nommé en T2 si actool s'en plaint.

## Structure des fichiers

```
Shared/DA/
└─ Motion.swift                     (T1) Motion, BlurFade, reduceMotionOverride, @ReduceMotion, numericChange / numericTransition
App/DA/
├─ Pressable.swift                  (T1) PressableStyle, .pressable
├─ Haptics.swift                    (T1) Haptic, Haptic.Style, HapticTrigger, .haptics(_:)
├─ AppIconArt.swift                 (T2) AppIconVariant, AppIconArt, RiftShape
├─ LiveEffects.swift                (T3) LiveIndicator, ChipIcon, TeamGlow / .teamGlow, CascadeIn / .cascadeIn
├─ Skeleton.swift                   (T5) SkeletonBlock, StatsSkeleton, DetailLoadingSkeleton, TeamRowsSkeleton, LeagueLoadingSkeleton
└─ Components.swift                 (T3 ScreenHeader ; T5 PillButton)
App/Matches/
├─ MatchesView.swift                (T3 réécrit ; T4 zoom, MatchRoute déplacé)
├─ TeamCardView.swift               (T3 réécrit ; T4 sources du zoom)
├─ MatchParts.swift                 (T3) LiveChipText, ScoreRow, MiniStats, RevealButton
└─ MatchRoute.swift                 (T4) MatchRoute (+ sourceID), zoomSource / zoomTransition
App/RootView.swift                  (T4) espace de noms du zoom, destination
App/Detail/
├─ MatchDetailView.swift            (T5 réécrit)
├─ StatsPanels.swift                (T5)
└─ LiveActivityPinButton.swift      (T5 réécrit)
App/Teams/TeamsView.swift           (T6 réécrit)
App/Teams/TeamRows.swift            (T6)
App/Teams/TeamColorSheet.swift      (T6)
App/Settings/SettingsView.swift     (T6)
Shared/Widgets/HomeWidgetViews.swift, AccessoryWidgetViews.swift          (T7)
Shared/LiveActivity/LiveActivityViews.swift, IslandViews.swift            (T7)
Resources/Assets.xcassets/AppIcon.appiconset/   (T2) Contents.json + 3 PNG
project.yml                         (T2) APPICON_NAME de l'appli
.github/workflows/ios.yml           (T2) contrôle de l'icône dans l'Info.plist
Tests/FailleTests/
├─ Support/Snapshot.swift           (T1) rendu figé
├─ MotionTests.swift                (T1)
├─ Support/AppIconRender.swift      (T2) AppIconRender, Bitmap, AppIconBoard
├─ AppIconTests.swift               (T2)
├─ MatchesMotionTests.swift         (T3)
├─ ZoomSourceTests.swift            (T4)
├─ DetailSnapshotTests.swift        (T5) + 15-chargement
└─ TeamsSnapshotTests.swift         (T6) + 03b-equipes-chargement
docs/superpowers/notes/2026-10-14-checklist-iphone.md   (T8) section D « Finitions »
```

## Commandes de vérification CI (utilisées par chaque tâche iOS)

Après `git push origin main` :

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
```

Expected : un identifiant numérique. Vide → le run n'est pas encore enregistré : relancer la commande quelques secondes plus tard (jamais avec un SHA court). Puis :

```bash
gh run watch --exit-status <id>
```

Expected : jobs `build` et `apercus` verts (la file des runners macOS peut durer 15 min ; un job « cancelled » sans étape se relance par `gh run rerun --failed <id>`). Échec : `gh run view <id> --log-failed`, corriger, nouveau commit, recommencer.

Aperçus d'un run :

```bash
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

Les PNG s'ouvrent avec l'outil Read (image). Pour comparer avant/après, garder le dossier du run de la tâche précédente.

Note TDD : sans Mac, un test iOS « rouge » ne peut être lancé qu'en poussant du code qui ne compile pas, ce qui casse aussi l'IPA du job `build`. Les tâches iOS écrivent donc les tests puis le code, et poussent une fois (comme les étapes 2-4) ; chaque test est écrit pour échouer si le code qu'il garde régresse.

---

### Task 1 : Vocabulaire de mouvement, toucher, retours haptiques, aperçus figés

**Files :**
- Create : `Shared/DA/Motion.swift`
- Create : `App/DA/Pressable.swift`
- Create : `App/DA/Haptics.swift`
- Modify : `Tests/FailleTests/Support/Snapshot.swift:46` (racine de la fenêtre)
- Test : `Tests/FailleTests/MotionTests.swift` (créé)

**Interfaces :**
- Consumes : `IconView(icon: Icon, size: CGFloat = 14)` (`Shared/DA/Icon.swift`) ; `@MainActor enum Snapshot` avec `static func write(_ view: some View, named name: String) async throws -> URL` (`Tests/FailleTests/Support/Snapshot.swift`) ; SwiftUI `EnvironmentValues.accessibilityReduceMotion`.
- Produces (utilisés par T2-T7) :
  - `enum Motion` : `enum Duration { static let press, snappy, number, list, smooth, reveal, fade, livePulse, teamGlow, shimmer, cascadeStep: Double }` ; `enum Kind: CaseIterable { case press, snappy, smooth, number, list, reveal }` ; `enum Reduced: Equatable { case full, fade, instant }` ; `enum Effect: CaseIterable { case livePulse, teamGlow, shimmer, cascade, zoom, pillSlide }` ; `static func reduced(_ kind: Kind, reduceMotion: Bool) -> Reduced` ; `static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation?` ; `static func runs(_ effect: Effect, reduceMotion: Bool) -> Bool` ; `static var press, snappy, smooth, number, list, reveal, fade: Animation` ; `static func pressScale(pressed: Bool, reduceMotion: Bool) -> CGFloat` ; `static func pressOpacity(pressed: Bool) -> Double` ; `static let cascadeLimit: Int` (8) ; `static func cascadeDelay(index: Int) -> Double` ; `static let cascadeOffset: CGFloat` ; `static let insertScale: CGFloat` ; `static let revealBlur: CGFloat` ; `@MainActor static func listTransition(reduceMotion: Bool) -> AnyTransition` ; `@MainActor static func bannerTransition(reduceMotion: Bool) -> AnyTransition` ; `@MainActor static func revealTransition(reduceMotion: Bool) -> AnyTransition`.
  - `struct BlurFade: ViewModifier` (`radius: CGFloat`, `opacity: Double`).
  - `EnvironmentValues.reduceMotionOverride: Bool?` (défaut nil).
  - `@propertyWrapper struct ReduceMotion: DynamicProperty` — usage : `@ReduceMotion var reduceMotion` (jamais `private`, voir Step 2).
  - `View.numericChange<Value: Equatable>(_ value: Value) -> some View` (appli) ; `View.numericTransition() -> some View` (widgets, Live Activity).
  - `struct PressableStyle: ButtonStyle` ; `.buttonStyle(.pressable)`.
  - `enum Haptic { case follow, unfollow, spoilerToggle, pin, unpin, reveal, refreshSucceeded, refreshFailed, colorPicked, gamePicked }` ; `Haptic.Style { case success, lightImpact, mediumImpact, selection, warning }` ; `var style: Haptic.Style` ; `var feedback: SensoryFeedback` ; `struct HapticTrigger: Equatable { var haptic: Haptic? { get } ; var count: Int { get } ; mutating func play(_ haptic: Haptic) }` ; `View.haptics(_ trigger: HapticTrigger) -> some View`.

- [ ] **Step 1 : Écrire les tests (ils échouent à la compilation tant que Step 2-4 manquent)**

Créer `Tests/FailleTests/MotionTests.swift` :

```swift
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Faille

/// Vocabulaire de mouvement, « Réduire les animations », toucher et retours haptiques (spec finitions : Principes,
/// §2, §3, §7, Vérification).
@MainActor
struct MotionTests {
    @Test func everyAnimationRunsWhenReduceMotionIsOff() {
        for kind in Motion.Kind.allCases {
            #expect(Motion.reduced(kind, reduceMotion: false) == .full)
            #expect(Motion.animation(kind, reduceMotion: false) != nil)
        }
        for effect in Motion.Effect.allCases {
            #expect(Motion.runs(effect, reduceMotion: false))
        }
    }

    /// Spec, Principes : sous « Réduire les animations », un mouvement pur devient immédiat (nil), un changement de
    /// contenu devient un fondu ; zoom, cascade, pulsation, lueur, reflet et glissement s'arrêtent.
    @Test func reduceMotionReplacesMovesWithAFadeOrNothing() {
        #expect(Motion.reduced(.press, reduceMotion: true) == .instant)
        #expect(Motion.reduced(.smooth, reduceMotion: true) == .instant)
        #expect(Motion.animation(.press, reduceMotion: true) == nil)
        #expect(Motion.animation(.smooth, reduceMotion: true) == nil)
        for kind in [Motion.Kind.snappy, .number, .list, .reveal] {
            #expect(Motion.reduced(kind, reduceMotion: true) == .fade)
            #expect(Motion.animation(kind, reduceMotion: true) != nil)
        }
        for effect in Motion.Effect.allCases {
            #expect(!Motion.runs(effect, reduceMotion: true))
        }
    }

    /// Les durées nommées de la spec (≈ 0,18 / 0,3 / 0,45 / 0,5 s ; halo 1,6 s ; lueur 2,4 s ; cascade 40 ms).
    @Test func namedDurationsFollowTheSpec() {
        #expect(Motion.Duration.press == 0.18)
        #expect(Motion.Duration.snappy == 0.3)
        #expect(Motion.Duration.smooth == 0.45)
        #expect(Motion.Duration.reveal == 0.5)
        #expect(Motion.Duration.livePulse == 1.6)
        #expect(Motion.Duration.teamGlow == 2.4)
        #expect(Motion.Duration.cascadeStep == 0.04)
        #expect(Motion.revealBlur == 10)
        #expect(Motion.insertScale == 0.96)
    }

    @Test func aPressedSurfaceShrinksOnlyWhenMotionIsAllowed() {
        #expect(Motion.pressScale(pressed: true, reduceMotion: false) == 0.97)
        #expect(Motion.pressScale(pressed: true, reduceMotion: true) == 1)
        #expect(Motion.pressScale(pressed: false, reduceMotion: false) == 1)
        #expect(Motion.pressOpacity(pressed: true) < 1)
        #expect(Motion.pressOpacity(pressed: false) == 1)
    }

    /// Spec finitions §7 : ≈ 40 ms par carte, 8 cartes au plus.
    @Test func theCascadeIsFortyMillisecondsPerCardForEightCardsAtMost() {
        #expect(Motion.cascadeLimit == 8)
        #expect(Motion.cascadeDelay(index: 0) == 0)
        #expect(abs(Motion.cascadeDelay(index: 3) - 0.12) < 1e-9)
        #expect(abs(Motion.cascadeDelay(index: 7) - 0.28) < 1e-9)
        #expect(Motion.cascadeDelay(index: 30) == Motion.cascadeDelay(index: 7))
        #expect(Motion.cascadeDelay(index: -1) == 0)
    }

    /// Spec finitions §2 : zone tactile inchangée — même taille mesurée qu'avec `.plain`, au moins 44 × 44 pt.
    @Test func pressableStyleKeepsTheHitArea() {
        let pressable = Self.fittingSize(Button(action: {}) { HitTarget() }.buttonStyle(.pressable))
        let plain = Self.fittingSize(Button(action: {}) { HitTarget() }.buttonStyle(.plain))
        #expect(pressable == plain)
        #expect(pressable.width >= 44 && pressable.height >= 44)
    }

    /// `@ReduceMotion` : la valeur forcée d'abord (aperçus PNG), sinon le réglage du système (coupé sur le simulateur
    /// de la CI).
    @Test func reduceMotionReadsTheOverrideThenTheSystem() {
        #expect(MotionProbe.read(override: true) == true)
        #expect(MotionProbe.read(override: false) == false)
        #expect(MotionProbe.read(override: nil) == false)
    }

    /// Spec finitions §3 : la nature de chaque retour.
    @Test func eachActionHasItsHaptic() {
        #expect(Haptic.follow.style == .success)
        #expect(Haptic.unfollow.style == .lightImpact)
        #expect(Haptic.spoilerToggle.style == .selection)
        #expect(Haptic.pin.style == .success)
        #expect(Haptic.unpin.style == .lightImpact)
        #expect(Haptic.reveal.style == .mediumImpact)
        #expect(Haptic.refreshSucceeded.style == .success)
        #expect(Haptic.refreshFailed.style == .warning)
        #expect(Haptic.colorPicked.style == .selection)
        #expect(Haptic.gamePicked.style == .selection)
    }

    /// Deux révélations de suite jouent deux retours : la valeur observée par `.sensoryFeedback` change à chaque fois.
    @Test func twoIdenticalHapticsInARowStillChangeTheTrigger() {
        var trigger = HapticTrigger()
        let start = trigger
        trigger.play(.reveal)
        let first = trigger
        trigger.play(.reveal)
        #expect(first != start)
        #expect(trigger != first)
        #expect(trigger.haptic == .reveal)
        #expect(trigger.count == 2)
    }

    private static func fittingSize(_ view: some View) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 400, height: 400))
    }
}

/// Cible tactile type de l'appli (œil, étoile) : glyphe de 20 pt dans un cadre de 44 × 44 pt.
private struct HitTarget: View {
    var body: some View {
        IconView(icon: .star, size: 20)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Lit `@ReduceMotion` pendant un rendu (`ImageRenderer` évalue `body`).
private struct MotionProbe: View {
    final class Box {
        var value: Bool?

        func record(_ value: Bool) {
            self.value = value
        }
    }

    let box: Box
    @ReduceMotion var reduceMotion

    var body: some View {
        let _ = box.record(reduceMotion)
        Color.clear.frame(width: 1, height: 1)
    }

    static func read(override: Bool?) -> Bool? {
        let box = Box()
        let renderer = ImageRenderer(content: MotionProbe(box: box).environment(\.reduceMotionOverride, override))
        _ = renderer.cgImage
        return box.value
    }
}
```

- [ ] **Step 2 : `Shared/DA/Motion.swift`**

```swift
import SwiftUI

/// Vocabulaire de mouvement de Faille (spec finitions, « Principes ») : ressorts et durées nommés, et ce qu'ils
/// deviennent sous « Réduire les animations ». Aucune durée en dur dans les vues : elles passent toutes par ici.
/// Dans `Shared/` : les widgets et la Live Activity utilisent `numericTransition()`.
enum Motion {
    /// Durées, en secondes.
    enum Duration {
        static let press: Double = 0.18
        static let snappy: Double = 0.3
        static let number: Double = 0.35
        static let list: Double = 0.4
        static let smooth: Double = 0.45
        static let reveal: Double = 0.5
        /// Fondu : remplaçant des mouvements sous « Réduire les animations », et masquage par l'œil.
        static let fade: Double = 0.2
        /// Un aller-retour du halo « en direct ».
        static let livePulse: Double = 1.6
        /// Un aller-retour de la lueur d'équipe.
        static let teamGlow: Double = 2.4
        /// Un passage du reflet d'un squelette de chargement.
        static let shimmer: Double = 1.6
        /// Décalage entre deux cartes de la cascade d'apparition.
        static let cascadeStep: Double = 0.04
    }

    /// Les animations nommées de la spec.
    enum Kind: CaseIterable, Sendable {
        /// Appui sur une surface touchable.
        case press
        /// Bandeau d'erreur, capsule des pilules, onglet des joueurs.
        case snappy
        /// Largeur de la barre de gold.
        case smooth
        /// Chiffres qui défilent.
        case number
        /// Cartes et lignes qui arrivent, partent ou changent d'ordre.
        case list
        /// Révélation anti-spoiler.
        case reveal
    }

    /// Ce que devient une animation sous « Réduire les animations ».
    enum Reduced: Equatable, Sendable {
        /// Réglage coupé : l'animation de la spec.
        case full
        /// Un fondu court remplace le mouvement.
        case fade
        /// Plus d'animation : le changement est immédiat.
        case instant
    }

    /// Effets continus ou spatiaux, arrêtés (ou figés) sous « Réduire les animations ».
    enum Effect: CaseIterable, Sendable {
        case livePulse, teamGlow, shimmer, cascade, zoom, pillSlide
    }

    /// Règle « Réduire les animations » (spec, Principes) : un mouvement pur (appui, largeur de la barre de gold)
    /// devient immédiat ; un changement de contenu (chiffres, listes, révélation, bandeau, pilules) devient un fondu.
    static func reduced(_ kind: Kind, reduceMotion: Bool) -> Reduced {
        guard reduceMotion else { return .full }
        switch kind {
        case .press, .smooth: return .instant
        case .snappy, .number, .list, .reveal: return .fade
        }
    }

    /// L'animation à poser ; nil : aucune (changement immédiat).
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        switch reduced(kind, reduceMotion: reduceMotion) {
        case .full: return base(kind)
        case .fade: return fade
        case .instant: return nil
        }
    }

    /// Un effet continu ou spatial tourne-t-il ? Jamais sous « Réduire les animations » (halo et lueur restent, fixes).
    static func runs(_ effect: Effect, reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    // MARK: Animations de la spec (sobres : aucun rebond, sauf 8 % pour les listes)

    static var press: Animation { .spring(duration: Duration.press, bounce: 0) }
    static var snappy: Animation { .snappy(duration: Duration.snappy) }
    static var smooth: Animation { .smooth(duration: Duration.smooth) }
    static var number: Animation { .smooth(duration: Duration.number) }
    static var list: Animation { .spring(duration: Duration.list, bounce: 0.08) }
    static var reveal: Animation { .easeOut(duration: Duration.reveal) }
    static var fade: Animation { .easeInOut(duration: Duration.fade) }

    private static func base(_ kind: Kind) -> Animation {
        switch kind {
        case .press: return press
        case .snappy: return snappy
        case .smooth: return smooth
        case .number: return number
        case .list: return list
        case .reveal: return reveal
        }
    }

    // MARK: Valeurs

    /// Échelle d'une surface appuyée (spec finitions §2) ; 1 sous « Réduire les animations ».
    static func pressScale(pressed: Bool, reduceMotion: Bool) -> CGFloat {
        pressed && !reduceMotion ? 0.97 : 1
    }

    /// Opacité d'une surface appuyée : légère baisse, gardée sous « Réduire les animations » (ce n'est pas un mouvement).
    static func pressOpacity(pressed: Bool) -> Double {
        pressed ? 0.85 : 1
    }

    /// Cascade d'apparition (spec finitions §7) : au plus 8 cartes décalées ; les suivantes arrivent avec la 8e.
    static let cascadeLimit = 8

    /// Retard de la carte `index` dans la cascade : 40 ms par carte.
    static func cascadeDelay(index: Int) -> Double {
        Double(min(max(index, 0), cascadeLimit - 1)) * Duration.cascadeStep
    }

    /// Distance que parcourt une carte qui arrive en cascade (points).
    static let cascadeOffset: CGFloat = 12
    /// Échelle de départ d'une carte ou d'une ligne qui arrive (spec finitions §7).
    static let insertScale: CGFloat = 0.96
    /// Rayon du flou d'où sort un score révélé (spec finitions §8).
    static let revealBlur: CGFloat = 10

    // MARK: Transitions

    /// Carte ou ligne : arrive en fondu en grandissant depuis 0,96, part en fondu ; fondu seul sous « Réduire les
    /// animations ».
    @MainActor static func listTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: insertScale)),
                                              removal: .opacity)
    }

    /// Bandeau d'erreur : glisse du haut en fondu ; fondu seul sous « Réduire les animations ».
    @MainActor static func bannerTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    /// Révélation (spec finitions §8) : le contenu sort d'un flou (10 → 0) en fondu ; masquage : fondu simple. Fondu
    /// seul sous « Réduire les animations ».
    @MainActor static func revealTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: BlurFade(radius: revealBlur, opacity: 0),
                                 identity: BlurFade(radius: 0, opacity: 1)),
            removal: .opacity
        )
    }
}

/// Flou et opacité : les deux états de la transition de révélation.
struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

extension EnvironmentValues {
    /// Force « Réduire les animations » ; nil : réglage du système. Les aperçus PNG le mettent à vrai : rendus figés,
    /// dans l'état final (ni cascade en cours, ni halo à mi-respiration, ni reflet de squelette).
    @Entry var reduceMotionOverride: Bool? = nil
}

/// « Réduire les animations » tel que les vues de Faille le lisent : la valeur forcée (`reduceMotionOverride`) si elle
/// existe, sinon le réglage du système (`accessibilityReduceMotion`). Les retours haptiques n'en dépendent pas.
/// S'emploie sans `private` (`@ReduceMotion var reduceMotion`) : l'initialiseur membre à membre des vues reste interne.
@propertyWrapper
struct ReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.reduceMotionOverride) private var override

    init() {}

    @MainActor var wrappedValue: Bool {
        override ?? system
    }
}

/// Chiffres qui défilent dans l'appli (spec finitions §4) : transition numérique animée par `Motion.number` quand
/// `value` change ; fondu sous « Réduire les animations ». À poser seulement sur une valeur affichée, donc déjà jugée
/// non masquée (un score masqué n'est jamais rendu : il ne peut pas défiler).
struct NumericChange<Value: Equatable>: ViewModifier {
    let value: Value
    @ReduceMotion var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(Motion.animation(.number, reduceMotion: reduceMotion), value: value)
    }
}

/// Chiffres qui défilent dans un widget ou la Live Activity : WidgetKit et ActivityKit animent eux-mêmes le passage
/// d'une entrée (ou d'une mise à jour) à la suivante. Aucune animation continue (spec finitions §4, Hors périmètre) :
/// ne jamais le poser sur un conteneur qui contient un chrono qui tourne.
struct NumericTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText())
    }
}

extension View {
    /// Chiffres qui défilent quand `value` change (appli).
    func numericChange<Value: Equatable>(_ value: Value) -> some View {
        modifier(NumericChange(value: value))
    }

    /// Chiffres qui défilent d'une entrée à l'autre (widgets, Live Activity).
    func numericTransition() -> some View {
        modifier(NumericTransition())
    }
}
```

- [ ] **Step 3 : `App/DA/Pressable.swift`**

```swift
import SwiftUI

/// Toucher (spec finitions §2) : la surface s'enfonce (échelle 0,97) et pâlit un peu pendant l'appui, avec le ressort
/// `Motion.press` ; sous « Réduire les animations », elle pâlit seulement. Remplace `.buttonStyle(.plain)` : comme lui,
/// il ne colore pas le libellé. La zone tactile ne change pas : `scaleEffect` n'agit que sur le rendu, ni sur la mise
/// en page ni sur la forme de toucher (`contentShape` du libellé).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

/// Le libellé appuyé ; une vue à part pour lire « Réduire les animations ».
private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    @ReduceMotion var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(Motion.pressScale(pressed: configuration.isPressed, reduceMotion: reduceMotion))
            .opacity(Motion.pressOpacity(pressed: configuration.isPressed))
            .animation(Motion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// `.buttonStyle(.pressable)` : cartes, lignes, pilules, boutons en verre.
    static var pressable: PressableStyle { PressableStyle() }
}
```

- [ ] **Step 4 : `App/DA/Haptics.swift`**

```swift
import SwiftUI

/// Retours haptiques de Faille (spec finitions §3) : un par action de l'utilisateur, jamais sur une mise à jour des
/// données (pas à chaque relecture des stats). Ils restent sous « Réduire les animations ».
enum Haptic: Equatable, Sendable {
    case follow, unfollow
    case spoilerToggle
    case pin, unpin
    case reveal
    case refreshSucceeded, refreshFailed
    case colorPicked
    case gamePicked

    /// Nature du retour, testable sans `SensoryFeedback`.
    enum Style: Equatable, Sendable {
        case success, lightImpact, mediumImpact, selection, warning
    }

    /// Suivre, épingler, rafraîchir : succès ; ne plus suivre, retirer : impact léger ; œil, couleur, pilule :
    /// sélection ; révéler : impact moyen ; rafraîchir en échec : avertissement.
    var style: Style {
        switch self {
        case .follow, .pin, .refreshSucceeded: return .success
        case .unfollow, .unpin: return .lightImpact
        case .spoilerToggle, .colorPicked, .gamePicked: return .selection
        case .reveal: return .mediumImpact
        case .refreshFailed: return .warning
        }
    }

    var feedback: SensoryFeedback {
        switch style {
        case .success: return .success
        case .lightImpact: return .impact(weight: .light)
        case .mediumImpact: return .impact(weight: .medium)
        case .selection: return .selection
        case .warning: return .warning
        }
    }
}

/// Déclencheur de `.sensoryFeedback` : chaque `play` change la valeur observée, même pour deux retours identiques de
/// suite. À garder dans une vue qui reste à l'écran après l'action (l'écran ou la carte, pas la ligne ni le bouton qui
/// disparaissent avec elle).
struct HapticTrigger: Equatable {
    private(set) var haptic: Haptic?
    private(set) var count = 0

    mutating func play(_ haptic: Haptic) {
        self.haptic = haptic
        count += 1
    }
}

extension View {
    /// Joue le retour de chaque `trigger.play(_:)`.
    func haptics(_ trigger: HapticTrigger) -> some View {
        sensoryFeedback(trigger: trigger) { _, new in new.haptic?.feedback }
    }
}
```

- [ ] **Step 5 : Aperçus figés — `Tests/FailleTests/Support/Snapshot.swift`**

Remplacer :

```swift
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: AnyView(view))
```

par :

```swift
        window.overrideUserInterfaceStyle = .dark
        // Rendu figé (finitions) : « Réduire les animations » forcé, l'écran est capturé dans son état final — ni
        // cascade en cours, ni halo à mi-respiration, ni reflet de squelette.
        window.rootViewController = UIHostingController(rootView: AnyView(view.environment(\.reduceMotionOverride, true)))
```

- [ ] **Step 6 : Commit et push**

```bash
git add Shared/DA/Motion.swift App/DA/Pressable.swift App/DA/Haptics.swift Tests/FailleTests/Support/Snapshot.swift Tests/FailleTests/MotionTests.swift
git commit -m "feat(app): vocabulaire de mouvement (Motion), toucher (PressableStyle), retours haptiques, aperçus figés" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 7 : CI**

```bash
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

Expected : `build` (appli **et** extension : `Shared/DA/Motion.swift` est compilé dans les deux) et `apercus` verts ; les 9 tests de `MotionTests` passent ; mêmes PNG qu'avant (`00-da` … `13-dynamic-island`), même mise en page (aucune vue ne consomme encore `Motion`). Erreurs probables et replis :
- `@Entry` refusé : clé classique à la place, même nom :
  ```swift
  private struct ReduceMotionOverrideKey: EnvironmentKey {
      static let defaultValue: Bool? = nil
  }

  extension EnvironmentValues {
      var reduceMotionOverride: Bool? {
          get { self[ReduceMotionOverrideKey.self] }
          set { self[ReduceMotionOverrideKey.self] = newValue }
      }
  }
  ```
- Erreur d'isolation sur `ReduceMotion` (« main actor-isolated … from a nonisolated context ») : annoter toute la structure `@MainActor @propertyWrapper struct ReduceMotion` ; si l'erreur persiste, garder la structure et, dans chaque vue qui l'utilise (T1-T6), remplacer `@ReduceMotion var reduceMotion` par `@Environment(\.accessibilityReduceMotion) private var systemReduceMotion`, `@Environment(\.reduceMotionOverride) private var reduceMotionOverride` et `private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }` (même nom `reduceMotion` : le reste du code ne change pas).
- `sensoryFeedback(trigger:_:)` refusé (signature de la fermeture) : `sensoryFeedback(trigger: trigger) { (_: HapticTrigger, new: HapticTrigger) -> SensoryFeedback? in new.haptic?.feedback }`.
- `MotionProbe.read(override: nil)` vaut nil : `ImageRenderer` n'a pas évalué `body` → lire `renderer.uiImage` au lieu de `cgImage`.

---

### Task 2 : Icône de l'appli

**Files :**
- Create : `App/DA/AppIconArt.swift`
- Create : `Tests/FailleTests/Support/AppIconRender.swift`
- Test : `Tests/FailleTests/AppIconTests.swift` (créé)
- Create (Step 6, depuis l'artefact) : `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`, `app-icon-1024.png`, `app-icon-1024-dark.png`, `app-icon-1024-tinted.png`
- Modify : `project.yml:65-67` (cible `Faille`)
- Modify : `.github/workflows/ios.yml` (étape « Vérifier l'Info.plist de l'appli »)

**Interfaces :**
- Consumes : `Palette.abyss`, `Palette.accent` (`Shared/DA/Palette.swift`) ; `Snapshot.directory: URL`, `Snapshot.Failure(description:)` (`Tests/FailleTests/Support/Snapshot.swift`) ; `BoardWallpaper`, `BoardCaption(text:)` (`Tests/FailleTests/Support/WidgetBoard.swift`) ; `ApercuTests.expectNotBlank(_:)`.
- Produces : `enum AppIconVariant: String, CaseIterable { case standard, dark, tinted ; var fileName: String }` ; `struct AppIconArt: View { init(variant: AppIconVariant, size: CGFloat) }` ; `struct RiftShape: Shape` ; tests : `AppIconRender.write(_:) throws -> URL`, `AppIconRender.writeBoard() throws -> URL`, `struct Bitmap { init?(contentsOf:) ; pixel(x:y:) }`, `struct AppIconBoard: View`. Artefact : `app-icon-1024.png`, `app-icon-1024-dark.png`, `app-icon-1024-tinted.png`, `14-icone.png`. Jeu `AppIcon` du catalogue ; `CFBundleIcons › CFBundlePrimaryIcon › CFBundleIconName = AppIcon` dans l'Info.plist de l'appli.

- [ ] **Step 1 : Le dessin — `App/DA/AppIconArt.swift`**

```swift
import SwiftUI

/// Variantes de l'icône (iOS 18+) : claire (par défaut), sombre (fond transparent : iOS pose son fond sombre),
/// teintée (niveaux de gris : iOS applique la teinte choisie).
enum AppIconVariant: String, CaseIterable, Sendable {
    case standard, dark, tinted

    /// Nom du PNG, dans l'artefact `Faille-apercus` comme dans `AppIcon.appiconset`.
    var fileName: String {
        switch self {
        case .standard: return "app-icon-1024"
        case .dark: return "app-icon-1024-dark"
        case .tinted: return "app-icon-1024-tinted"
        }
    }
}

/// Icône de Faille (spec finitions §1) : fond abysse (`#0B1020` vers plus profond), une faille verticale lumineuse à
/// l'accent `#6FD3FF` avec un halo doux, rien d'autre (pas de texte). Dessinée dans un carré de `size` points : rendue
/// à 1024 × 1024 px par un test hébergé (`ImageRenderer`, échelle 1), puis copiée dans `AppIcon.appiconset`.
struct AppIconArt: View {
    let variant: AppIconVariant
    /// Côté du carré, en points (rendu à l'échelle 1 : en pixels).
    let size: CGFloat

    var body: some View {
        ZStack {
            background
            // Halo doux autour de la faille.
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(haloOpacity), glow.opacity(haloOpacity * 0.25), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.36))
                .frame(width: size * 0.62, height: size * 0.95)
                .blur(radius: size * 0.04)
            // Lueur large, lueur serrée, puis la faille : blanche au milieu, à l'accent vers les pointes.
            RiftShape()
                .fill(glow)
                .blur(radius: size * 0.03)
            RiftShape()
                .fill(glow.opacity(0.6))
                .blur(radius: size * 0.008)
            RiftShape()
                .fill(LinearGradient(colors: [glow, Color.white, glow], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var background: some View {
        switch variant {
        case .standard:
            LinearGradient(colors: [Palette.abyss, Color(red: 4 / 255, green: 7 / 255, blue: 18 / 255)],
                           startPoint: .top, endPoint: .bottom)
        case .dark:
            Color.clear
        case .tinted:
            Color.black
        }
    }

    /// Lueur : l'accent, ou un gris clair pour la variante teintée (niveaux de gris seulement).
    private var glow: Color {
        variant == .tinted ? Color(white: 0.82) : Palette.accent
    }

    private var haloOpacity: Double {
        variant == .tinted ? 0.30 : 0.38
    }
}

/// La faille : une fente verticale en zigzag, effilée aux deux pointes, plus large au milieu (fractions du carré).
struct RiftShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Pointe du haut, bord gauche de haut en bas, pointe du bas, bord droit de bas en haut.
        let outline: [(x: CGFloat, y: CGFloat)] = [
            (0.500, 0.140),
            (0.471, 0.280), (0.500, 0.400), (0.442, 0.520), (0.496, 0.640), (0.478, 0.760),
            (0.505, 0.870),
            (0.506, 0.760), (0.556, 0.640), (0.522, 0.520), (0.560, 0.400), (0.499, 0.280),
        ]
        var path = Path()
        for (index, point) in outline.enumerated() {
            let location = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            if index == 0 {
                path.move(to: location)
            } else {
                path.addLine(to: location)
            }
        }
        path.closeSubpath()
        return path
    }
}
```

- [ ] **Step 2 : Rendu et planche — `Tests/FailleTests/Support/AppIconRender.swift`**

```swift
import SwiftUI
import UIKit
@testable import Faille

/// Rendu de l'icône (spec finitions §1) : PNG de 1024 × 1024 px pour le catalogue, et planche `14-icone.png`.
@MainActor
enum AppIconRender {
    static let pixels: CGFloat = 1024

    /// Une variante à 1024 × 1024 px (échelle 1) dans `build/apercus/`. Claire et teintée : opaques ; sombre : fond
    /// transparent.
    @discardableResult
    static func write(_ variant: AppIconVariant) throws -> URL {
        let renderer = ImageRenderer(content: AppIconArt(variant: variant, size: pixels))
        renderer.scale = 1
        renderer.isOpaque = variant != .dark
        guard let png = renderer.uiImage?.pngData() else {
            throw Snapshot.Failure(description: "ImageRenderer n'a rien rendu pour \(variant.fileName)")
        }
        return try save(png, named: variant.fileName)
    }

    /// La planche : 512 × 680 pt à l'échelle 2 (1024 px de large).
    @discardableResult
    static func writeBoard() throws -> URL {
        let renderer = ImageRenderer(content: AppIconBoard().environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let png = renderer.uiImage?.pngData() else {
            throw Snapshot.Failure(description: "ImageRenderer n'a rien rendu pour 14-icone")
        }
        return try save(png, named: "14-icone")
    }

    private static func save(_ png: Data, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: Snapshot.directory, withIntermediateDirectories: true)
        let url = Snapshot.directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }
}

/// Pixels d'un PNG lus en RGBA 8 bits (prémultipliés) : contrôles de l'icône.
struct Bitmap {
    struct Pixel {
        let r, g, b, a: UInt8
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(contentsOf url: URL) {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false))?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let index = (y * width + x) * 4
        return Pixel(r: bytes[index], g: bytes[index + 1], b: bytes[index + 2], a: bytes[index + 3])
    }
}

/// Planche de l'icône (`14-icone.png`) : les trois variantes en grand, puis l'icône aux tailles de l'écran d'accueil
/// sur fond clair et sur fond sombre, avec le masque arrondi d'iOS.
struct AppIconBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BoardCaption(text: "Variantes · claire, sombre, teintée")
            HStack(spacing: 16) {
                ForEach(AppIconVariant.allCases, id: \.self) { variant in
                    tile(variant, size: 140, backdrop: variant == .dark ? Color(white: 0.11) : .clear)
                }
            }
            BoardCaption(text: "Sur fond clair")
            sizes(on: Color(white: 0.93))
            BoardCaption(text: "Sur fond sombre")
            sizes(on: Color(red: 0.04, green: 0.05, blue: 0.11))
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 512, height: 680, alignment: .topLeading)
        .background(BoardWallpaper())
    }

    private func sizes(on background: Color) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            ForEach([120, 80, 60, 40] as [CGFloat], id: \.self) { size in
                tile(.standard, size: size, backdrop: .clear)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func tile(_ variant: AppIconVariant, size: CGFloat, backdrop: Color) -> some View {
        AppIconArt(variant: variant, size: size)
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}
```

- [ ] **Step 3 : Le test — `Tests/FailleTests/AppIconTests.swift`**

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Icône de l'appli (spec finitions §1) : trois PNG de 1024 × 1024 px (claire, sombre, teintée) pour
    /// `AppIcon.appiconset`, et la planche `14-icone.png`.
    @Test func appIcon() throws {
        for variant in AppIconVariant.allCases {
            let url = try AppIconRender.write(variant)
            let bitmap = try #require(Bitmap(contentsOf: url), "PNG illisible : \(variant.fileName)")
            #expect(bitmap.width == 1024 && bitmap.height == 1024,
                    "\(variant.fileName) : \(bitmap.width) × \(bitmap.height) px")
            let corner = bitmap.pixel(x: 4, y: 4)
            // Dans la faille, un peu sous le milieu (sa partie la plus large).
            let rift = bitmap.pixel(x: 512, y: 530)
            let side = bitmap.pixel(x: 300, y: 700)
            switch variant {
            case .standard:
                #expect(corner.a == 255, "claire : opaque")
                #expect(Self.brightness(corner) < 120, "claire : coin abysse sombre")
                #expect(Self.brightness(rift) > 450, "claire : faille lumineuse")
            case .dark:
                #expect(corner.a == 0, "sombre : fond transparent")
                #expect(rift.a > 200, "sombre : faille opaque")
            case .tinted:
                #expect(corner.a == 255, "teintée : opaque")
                for pixel in [corner, rift, side] {
                    #expect(Self.isGray(pixel), "teintée : niveaux de gris")
                }
                #expect(Self.brightness(rift) > 450, "teintée : faille claire")
            }
        }
        expectNotBlank(try AppIconRender.writeBoard())
    }

    private static func brightness(_ pixel: Bitmap.Pixel) -> Int {
        Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
    }

    private static func isGray(_ pixel: Bitmap.Pixel) -> Bool {
        abs(Int(pixel.r) - Int(pixel.g)) <= 2 && abs(Int(pixel.g) - Int(pixel.b)) <= 2
    }
}
```

- [ ] **Step 4 : Commit, push, CI**

```bash
git add App/DA/AppIconArt.swift Tests/FailleTests/Support/AppIconRender.swift Tests/FailleTests/AppIconTests.swift
git commit -m "feat(app): dessin de l'icône (AppIconArt) rendu à 1024 px, variantes sombre et teintée, planche 14-icone" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : `build` et `apercus` verts ; `appIcon` vert. Replis : `uiImage` nil à 1024 → ajouter `renderer.proposedSize = ProposedViewSize(width: pixels, height: pixels)` ; coin de la variante sombre opaque → vérifier `renderer.isOpaque = false` et que `background` rend `Color.clear`.

- [ ] **Step 5 : Juger l'icône**

```bash
RUN=<id du run du Step 4>
DIR="$HOME/Downloads/faille-apercus-$RUN"
gh run download "$RUN" --name Faille-apercus --dir "$DIR" && ls -la "$DIR"/app-icon-1024*.png "$DIR"/14-icone.png
```

Ouvrir `14-icone.png` (outil Read) puis les trois `app-icon-1024*.png`. Expected : 14-icone.png fait 1024 px de large ; faille centrée, lisible jusqu'à 40 pt, halo doux sans bord dur, aucun texte ; variante sombre sur fond transparent ; teintée en gris. Leviers si la faille est trop fine à 40 pt : multiplier par 1,3 l'écart de chaque point à `x = 0,5` dans `RiftShape` ; halo trop faible ou trop fort : `haloOpacity` (0,30-0,50). Tout changement → recommencer Step 4 et Step 5.

- [ ] **Step 6 : Le jeu d'icônes**

```bash
mkdir -p Resources/Assets.xcassets/AppIcon.appiconset
cp "$DIR/app-icon-1024.png" "$DIR/app-icon-1024-dark.png" "$DIR/app-icon-1024-tinted.png" Resources/Assets.xcassets/AppIcon.appiconset/
```

Créer `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` :

```json
{
  "images" : [
    {
      "filename" : "app-icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "app-icon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "app-icon-1024-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 7 : `project.yml` — l'appli seulement**

Remplacer (cible `Faille`) :

```yaml
        # Pas d'icône d'appli ni de couleur d'accent dans le catalogue à l'étape 2 : actool ne doit pas les chercher.
        ASSETCATALOG_COMPILER_APPICON_NAME: ""
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: ""
```

par :

```yaml
        # Icône de l'appli (finitions §1) : jeu « AppIcon » du catalogue (une taille, variantes sombre et teintée).
        # Toujours pas de couleur d'accent dans le catalogue : actool ne doit pas la chercher.
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: ""
```

La cible `FailleWidgets` garde `ASSETCATALOG_COMPILER_APPICON_NAME: ""` (l'extension n'a pas d'icône).

- [ ] **Step 8 : `.github/workflows/ios.yml` — contrôle de l'icône**

Remplacer :

```yaml
      - name: Vérifier l'Info.plist de l'appli (Live Activities, arrière-plan)
        # Sans ces clés, iOS refuse les Live Activities ou ne réveille jamais l'appli en arrière-plan (spec §6.4).
        run: |
          PLIST=build/Build/Products/Release-iphoneos/Faille.app/Info.plist
          /usr/libexec/PlistBuddy -c "Print :NSSupportsLiveActivities" "$PLIST" | grep -qx true
          /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" | grep -q fetch
          /usr/libexec/PlistBuddy -c "Print :BGTaskSchedulerPermittedIdentifiers" "$PLIST" | grep -q faille.live-refresh
```

par :

```yaml
      - name: Vérifier l'Info.plist de l'appli (Live Activities, arrière-plan, icône)
        # Sans ces clés, iOS refuse les Live Activities ou ne réveille jamais l'appli en arrière-plan (spec §6.4).
        # Icône (finitions §1) : actool n'inscrit CFBundleIcons que si le catalogue contient le jeu AppIcon.
        run: |
          APP=build/Build/Products/Release-iphoneos/Faille.app
          PLIST="$APP/Info.plist"
          /usr/libexec/PlistBuddy -c "Print :NSSupportsLiveActivities" "$PLIST" | grep -qx true
          /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" | grep -q fetch
          /usr/libexec/PlistBuddy -c "Print :BGTaskSchedulerPermittedIdentifiers" "$PLIST" | grep -q faille.live-refresh
          /usr/libexec/PlistBuddy -c "Print :CFBundleIcons:CFBundlePrimaryIcon:CFBundleIconName" "$PLIST" | grep -qx AppIcon
          ls "$APP"/AppIcon*.png || echo "::warning::aucun PNG AppIcon* à la racine de l'appli : l'icône n'est que dans Assets.car"
```

- [ ] **Step 9 : Commit, push, CI**

```bash
git add Resources/Assets.xcassets/AppIcon.appiconset project.yml .github/workflows/ios.yml
git commit -m "feat(app): icône de l'appli dans le catalogue (AppIcon, sombre et teintée) et contrôle CI de l'Info.plist" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : `build` vert, étape « Vérifier l'Info.plist de l'appli (Live Activities, arrière-plan, icône) » verte (`CFBundleIconName` = `AppIcon`) ; « Vérifier Sora et les icônes dans l'extension » toujours verte ; `apercus` vert. Replis :
- actool refuse les apparences `dark` / `tinted` : garder seulement la première entrée de `Contents.json` (iOS dérive alors seul les variantes), noter la décision dans le message de commit.
- La compilation de l'extension se plaint du jeu `AppIcon` (Resources est aussi compilé dans l'extension) : déplacer le jeu dans un catalogue propre à l'appli — `App/AppIcon.xcassets/Contents.json` (même contenu que `Resources/Assets.xcassets/Contents.json`) et `App/AppIcon.xcassets/AppIcon.appiconset/` (mêmes fichiers) ; la cible `Faille` compile `App/`, l'extension non.
- `CFBundleIconName` absent : `gh run view <id> --log-failed`, vérifier l'orthographe `AppIcon` dans `project.yml` et que `xcodegen generate` a bien été relancé par la CI.

---

### Task 3 : Écran Matchs — toucher, chiffres, halo « en direct », lueur d'équipe, listes et cascade, bandeau, révélation

**Files :**
- Create : `App/DA/LiveEffects.swift`
- Modify (réécrit) : `App/Matches/MatchesView.swift`, `App/Matches/TeamCardView.swift`
- Modify : `App/Matches/MatchParts.swift` (`LiveChipText`, `ScoreRow`, `MiniStats`, `RevealButton`)
- Modify : `App/DA/Components.swift` (`ScreenHeader`)
- Test : `Tests/FailleTests/MatchesMotionTests.swift` (créé)

**Interfaces :**
- Consumes : T1 (`Motion`, `@ReduceMotion`, `.numericChange(_:)`, `.pressable`, `Haptic`, `HapticTrigger`, `.haptics(_:)`) ; `AppStore` : `var cards: [TeamCard]`, `func nextLine(for: TeamCard) -> NextLine`, `func cardsSubtitle(_: [TeamCard]) -> String`, `func liveState(for: MatchEvent) -> LiveMatchState`, `func scoreLine(_: MatchEvent) -> ScoreLine`, `func reveal(matchId: String)`, `func refreshNow() async`, `var isFailing: Bool`, `var bannerText: String?`, `func tint(for: MatchTeam) -> Color?`, `follows.displayOrder(_:preferring:)` ; `LiveMatchState.displayed(for: MatchEvent?) -> LiveMatchState` (`MatchParts.swift`) ; `LiveChipText.icon(for:) -> Icon` ; `Chip(muted:content:)`, `SectionLabel(text:dot:)`, `ErrorBanner(text:)`, `glassCard(tint:radius:padding:)`, `Radius.card` ; `Format.score(_:)`, `Format.goldDiff(_:)`, `Format.clock(_:)`, `Format.followCount(_:)`, `Format.lastRow(_:order:date:)`, `Format.matchDate(_:)` ; `reorder(_:_:)` (LoLKit).
- Produces : `struct LiveIndicator: View { init(size: CGFloat = 12) }` ; `struct ChipIcon: View { init(icon: Icon, size: CGFloat = 12) }` ; `struct TeamGlow: ViewModifier` + `View.teamGlow(_ color: Color, active: Bool) -> some View` ; `struct CascadeIn: ViewModifier` + `View.cascadeIn(index: Int, shown: Bool) -> some View` ; `static func TeamCardView.glows(_ state: LiveMatchState?) -> Bool` ; `ScoreRow` avec chiffres qui défilent et révélation ; `RevealButton` en `.pressable`. `MatchRoute(matchId:)` reste dans `MatchesView.swift` (T4 le déplace).

- [ ] **Step 1 : Le test — `Tests/FailleTests/MatchesMotionTests.swift`**

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Lueur d'équipe (spec finitions §12) : seulement pour un match en direct non masqué, jamais sur une carte masquée.
@MainActor
struct MatchesMotionTests {
    private func state(_ phase: LiveMatchState.Phase, spoilerFree: Bool) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: spoilerFree ? nil : [1, 0], gameNumber: spoilerFree ? nil : 2,
                       gameClockStart: nil, gameClockStoppedAt: nil, stats: nil, statsAvailable: true,
                       spoilerFree: spoilerFree, winnerCode: nil, updatedAt: Date())
    }

    @Test func onlyAnUnmaskedLiveMatchMakesTheCardGlow() {
        #expect(TeamCardView.glows(state(.inGame, spoilerFree: false)))
        #expect(TeamCardView.glows(state(.betweenGames, spoilerFree: false)))
        #expect(!TeamCardView.glows(state(.inGame, spoilerFree: true)))
        #expect(!TeamCardView.glows(state(.finished, spoilerFree: false)))
        #expect(!TeamCardView.glows(state(.upcoming, spoilerFree: false)))
        #expect(!TeamCardView.glows(nil))
    }

    /// Cartes de l'aperçu : KC (en direct, non masqué) brille ; T1 (en direct, anti-spoiler) et GEN (à venir) non.
    @Test func inThePreviewOnlyKCGlows() throws {
        let store = AppStore(preview: .standard)
        func glows(_ code: String) throws -> Bool {
            let card = try #require(store.cards.first { $0.team.code == code })
            return TeamCardView.glows(card.live.map { store.liveState(for: $0).displayed(for: $0) })
        }
        #expect(try glows("KC"))
        #expect(try !glows("T1"))
        #expect(try !glows("GEN"))
    }
}
```

- [ ] **Step 2 : `App/DA/LiveEffects.swift`**

```swift
import SwiftUI

/// Icône « en direct » et son halo doux qui respire (spec finitions §5 : ≈ 1,6 s, opacité + échelle), dans les
/// pastilles des cartes et du Détail et dans la pilule de la game en cours. Halo fixe sous « Réduire les animations ».
/// Le halo est un fond : il ne change ni la taille ni la place de l'icône. Jamais dans les widgets ni la Live Activity.
struct LiveIndicator: View {
    var size: CGFloat = 12
    @ReduceMotion var reduceMotion

    var body: some View {
        IconView(icon: .live, size: size)
            .background {
                if Motion.runs(.livePulse, reduceMotion: reduceMotion) {
                    Circle()
                        .fill(Palette.accent)
                        .phaseAnimator([false, true]) { halo, expanded in
                            halo
                                .scaleEffect(expanded ? 1.7 : 1.05)
                                .opacity(expanded ? 0.04 : 0.30)
                        } animation: { _ in
                            .easeInOut(duration: Motion.Duration.livePulse / 2)
                        }
                } else {
                    Circle()
                        .fill(Palette.accent)
                        .scaleEffect(1.3)
                        .opacity(0.18)
                }
            }
    }
}

/// Icône d'une pastille d'état : « en direct » avec son halo, sinon l'icône seule (terminé, à venir).
struct ChipIcon: View {
    let icon: Icon
    var size: CGFloat = 12

    var body: some View {
        if icon == .live {
            LiveIndicator(size: size)
        } else {
            IconView(icon: icon, size: size)
        }
    }
}

/// Lueur d'équipe (spec finitions §12) : contour doux à la couleur de l'équipe, qui respire lentement (≈ 2,4 s, faible
/// amplitude) ; fixe sous « Réduire les animations ». `active` vient de `TeamCardView.glows(_:)` : jamais sur une carte
/// dont le match en direct est masqué.
struct TeamGlow: ViewModifier {
    let color: Color
    let active: Bool
    var radius: CGFloat = Radius.card
    @ReduceMotion var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                if Motion.runs(.teamGlow, reduceMotion: reduceMotion) {
                    glow
                        .phaseAnimator([false, true]) { view, bright in
                            view.opacity(bright ? 0.95 : 0.65)
                        } animation: { _ in
                            .easeInOut(duration: Motion.Duration.teamGlow / 2)
                        }
                } else {
                    glow.opacity(0.8)
                }
            }
        }
    }

    private var glow: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color.opacity(0.55), lineWidth: 1.2)
            .shadow(color: color.opacity(0.55), radius: 9)
            .allowsHitTesting(false)
    }
}

/// Apparition en cascade (spec finitions §7) : la carte `index` arrive en fondu en montant de 12 pt, 40 ms après la
/// précédente (8 cartes au plus). `shown` passe à vrai une fois ; il est vrai d'emblée sous « Réduire les animations ».
struct CascadeIn: ViewModifier {
    let index: Int
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Motion.cascadeOffset)
            .animation(Motion.list.delay(Motion.cascadeDelay(index: index)), value: shown)
    }
}

extension View {
    /// Lueur d'équipe sur le contour d'une carte.
    func teamGlow(_ color: Color, active: Bool) -> some View {
        modifier(TeamGlow(color: color, active: active))
    }

    /// Place de la carte dans la cascade d'apparition.
    func cascadeIn(index: Int, shown: Bool) -> some View {
        modifier(CascadeIn(index: index, shown: shown))
    }
}
```

- [ ] **Step 3 : Remplacer tout `App/Matches/MatchesView.swift`**

```swift
import LoLKit
import SwiftUI

/// Destination de navigation : le Détail d'un match (branchée dans `RootView` à la Task 11).
struct MatchRoute: Hashable {
    let matchId: String
}

/// Onglet Matchs, version B (spec §5.1) : « Mes équipes », une carte Vitrail par équipe suivie, tirer pour rafraîchir.
/// Finitions : cartes qui arrivent en cascade à la première apparition, insertions, retraits et changements d'ordre
/// animés, bandeau d'erreur qui glisse du haut, retour haptique à la fin du tirer-pour-rafraîchir.
struct MatchesView: View {
    @Environment(AppStore.self) private var store
    let openTeams: () -> Void
    @ReduceMotion var reduceMotion
    /// Retour haptique du tirer-pour-rafraîchir.
    @State private var haptics = HapticTrigger()
    /// La cascade d'apparition a eu lieu : une seule fois, à la première apparition de l'écran (pas au retour du Détail,
    /// où la ligne vers laquelle le zoom se referme doit rester visible, ni en changeant d'onglet).
    @State private var cascaded = false

    var body: some View {
        let cards = store.cards
        // Sous « Réduire les animations », pas de cascade : les cartes sont là d'emblée.
        let cardsShown = cascaded || !Motion.runs(.cascade, reduceMotion: reduceMotion)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Mes équipes", subtitle: cards.isEmpty ? Format.followCount(0) : store.cardsSubtitle(cards))
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                        .transition(Motion.bannerTransition(reduceMotion: reduceMotion))
                }
                if cards.isEmpty {
                    WelcomeCard(action: openTeams)
                } else {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        TeamCardView(card: card)
                            .cascadeIn(index: index, shown: cardsShown)
                            .transition(Motion.listTransition(reduceMotion: reduceMotion))
                    }
                }
            }
            // Bandeau (spec finitions §11) et cartes (§7) : seules ces deux valeurs animent l'écran.
            .animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: store.isFailing)
            .animation(Motion.animation(.list, reduceMotion: reduceMotion), value: cards.map(\.id))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .haptics(haptics)
        .onAppear { cascaded = true }
        .abyssBackground()
        .navigationTitle("Matchs")
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Tirer pour rafraîchir, puis son retour (spec finitions §3) : succès si l'API a répondu, avertissement sinon.
    /// Une méthode de la vue (isolée au fil principal) : l'action de `.refreshable` est `@Sendable`.
    private func refresh() async {
        await store.refreshNow()
        haptics.play(store.isFailing ? .refreshFailed : .refreshSucceeded)
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
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }
}

#Preview {
    NavigationStack { MatchesView(openTeams: {}) }.environment(AppStore(preview: .standard))
}
```

- [ ] **Step 4 : Remplacer tout `App/Matches/TeamCardView.swift`**

```swift
import LoLKit
import SwiftUI

/// Carte Vitrail d'une équipe suivie (spec §5.1) : en direct, prochain, dernier.
/// Chaque match est un lien vers son Détail ; l'anti-spoiler (§8) vient de LoLKit.
/// Finitions : lignes qui s'enfoncent au toucher, chiffres qui défilent, halo « en direct », lueur d'équipe pour un
/// match en direct non masqué, révélation qui sort d'un flou avec un retour haptique.
struct TeamCardView: View {
    @Environment(AppStore.self) private var store
    let card: TeamCard
    @ReduceMotion var reduceMotion
    /// Retours haptiques de la carte : elle reste à l'écran quand « toucher pour révéler » disparaît.
    @State private var haptics = HapticTrigger()

    private var tint: Color {
        Palette.team(card.team.colorHex)
    }

    /// Lueur d'équipe (spec finitions §12) : seulement pour un match en direct (en jeu ou entre deux games) que LoLKit
    /// n'a pas masqué. `state` est déjà passé par `displayed(for:)` : un match que l'API donne pour terminé ne brille pas.
    static func glows(_ state: LiveMatchState?) -> Bool {
        guard let state, !state.spoilerFree else { return false }
        return state.phase == .inGame || state.phase == .betweenGames
    }

    var body: some View {
        // Jamais `card.next` directement : la ligne « Prochain » passe par LoLKit (anti-spoiler, spec §8).
        let nextLine = store.nextLine(for: card)
        // Un match que `getLive` donne pour terminé est « Terminé », jamais « En direct » (spec §8).
        let liveState = card.live.map { store.liveState(for: $0).displayed(for: $0) }
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: header, dot: tint)
            if let live = card.live, let liveState {
                liveBlock(live, state: liveState)
            }
            switch nextLine {
            case let .match(next):
                nextRow(next)
            case .hidden:
                hiddenNextRow
            case .none:
                EmptyView()
            }
            if let last = card.last {
                lastRow(last)
            }
            if card.live == nil, card.last == nil, case .none = nextLine {
                Text("Aucun match dans le calendrier récent")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
        .teamGlow(tint, active: Self.glows(liveState))
        .haptics(haptics)
    }

    private var header: String {
        [card.team.name, card.team.homeLeagueName].compactMap { $0 }.joined(separator: " · ")
    }

    /// « Toucher pour révéler » (spec §8) : le score sort d'un flou en fondu (`Motion.reveal`), avec un retour haptique.
    private func reveal(_ matchId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.reveal(matchId: matchId)
        }
    }

    @ViewBuilder private func liveBlock(_ event: MatchEvent, state: LiveMatchState) -> some View {
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let teams = order.map { event.match.teams[$0] }
        let icon = LiveChipText.icon(for: state.phase)
        NavigationLink(value: MatchRoute(matchId: event.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip(muted: icon != .live) {
                        ChipIcon(icon: icon, size: 12)
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
                    // Jamais rendus tant que le match est masqué ; à la révélation, ils sortent d'un flou (spec
                    // finitions §8). Même espacement que le bloc : la mise en page ne change pas.
                    VStack(alignment: .leading, spacing: 8) {
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
                    .transition(Motion.revealTransition(reduceMotion: reduceMotion))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        if state.spoilerFree {
            RevealButton { reveal(event.id) }
        }
    }

    /// `NextLine.hidden` (spec §8) : dernier match masqué, ou prochain match contre une autre équipe suivie en
    /// anti-spoiler dont le dernier match est masqué (règle C) ; ligne fixe, qu'un prochain match existe ou non. Pas un
    /// lien : rien à ouvrir.
    private var hiddenNextRow: some View {
        HStack(spacing: 6) {
            IconView(icon: .eyeOff, size: 13)
            Text("Prochain · masqué")
        }
        .font(Typo.secondary)
        .foregroundStyle(Palette.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .buttonStyle(.pressable)
    }

    /// « Dernier · GEN 3 – 0 HLE » ; masqué : « Dernier · T1 vs GEN · Terminé · sam. 11 oct. · 09:00 » (aucun résultat, spec §8).
    private func lastRow(_ event: MatchEvent) -> some View {
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let text = Format.lastRow(line, order: order, date: Format.matchDate(event.startTime))
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}
```

- [ ] **Step 5 : `App/Matches/MatchParts.swift`**

(a) Chrono figé — remplacer :

```swift
                    if let stopped = state.gameClockStoppedAt {
                        Text(Format.clock(stopped.timeIntervalSince(start)))
                    } else {
```

par :

```swift
                    if let stopped = state.gameClockStoppedAt {
                        // Chrono figé (pause, fin de game) : ses chiffres défilent quand il change (spec finitions §4).
                        Text(Format.clock(stopped.timeIntervalSince(start)))
                            .numericChange(stopped.timeIntervalSince(start))
                    } else {
```

(b) `ScoreRow` — remplacer :

```swift
    let tints: [Color?]
    var large = false

    var body: some View {
```

par :

```swift
    let tints: [Color?]
    var large = false
    @ReduceMotion var reduceMotion

    var body: some View {
```

puis remplacer :

```swift
            if let score {
                Text(Format.score(score))
                    .font(large ? Typo.scoreLarge : Typo.score)
                    .monospacedDigit()
            } else {
```

par :

```swift
            if let score {
                // Score non masqué (nil quand masqué : rien ne peut défiler) ; à la révélation, il sort d'un flou
                // (spec finitions §4, §8).
                Text(Format.score(score))
                    .font(large ? Typo.scoreLarge : Typo.score)
                    .monospacedDigit()
                    .numericChange(score)
                    .transition(Motion.revealTransition(reduceMotion: reduceMotion))
            } else {
```

(c) `MiniStats` — remplacer toute la structure :

```swift
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
```

par :

```swift
/// Ligne de stats d'une carte (spec §5.1) : kills, écart de gold, drakes, tours ; équipe de gauche d'abord.
/// Les chiffres défilent quand ils changent (spec finitions §4) ; cette ligne n'existe que pour un match non masqué.
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
                        .numericChange(diff)
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
                .numericChange(text)
        }
    }
}
```

(d) `RevealButton` — remplacer (seule occurrence du fichier) :

```swift
        .buttonStyle(.plain)
```

par :

```swift
        .buttonStyle(.pressable)
```

- [ ] **Step 6 : `App/DA/Components.swift` — compteur « N à venir »**

Remplacer :

```swift
                Text(subtitle)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
```

par :

```swift
                // « N en direct · N à venir », « N équipes suivies » : les chiffres défilent (spec finitions §4) ; les
                // comptes viennent de LoLKit (une carte à « Prochain » masqué ne compte pas).
                Text(subtitle)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
                    .numericChange(subtitle)
```

- [ ] **Step 7 : Commit, push, CI**

```bash
git add App/DA/LiveEffects.swift App/Matches/MatchesView.swift App/Matches/TeamCardView.swift App/Matches/MatchParts.swift App/DA/Components.swift Tests/FailleTests/MatchesMotionTests.swift
git commit -m "feat(app): finitions de l'écran Matchs — toucher, chiffres qui défilent, halo en direct, lueur d'équipe, cascade, bandeau, révélation" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

Expected : verts ; `MatchesMotionTests` (2 tests) passent. PNG à ouvrir et comparer au run de T2 : `01-matchs.png` — carte KC avec un contour lumineux bleu (#5B8CFF) fixe, halo cyan pâle derrière l'icône « en direct » des pastilles KC et T1, carte T1 **sans** lueur, carte GEN sans lueur ; mises en page identiques (mêmes hauteurs de cartes) ; `02-matchs-vide.png` et `08-bandeau-erreur.png` (bandeau à la même place) inchangés. Replis :
- `phaseAnimator` refusé (fermetures `@Sendable`, isolation) : remplacer dans `LiveIndicator` (et de même dans `TeamGlow`) par un état local — `@State private var breathing = false`, `.scaleEffect(breathing ? 1.7 : 1.05).opacity(breathing ? 0.04 : 0.30)` sur le cercle et `.onAppear { withAnimation(.easeInOut(duration: Motion.Duration.livePulse / 2).repeatForever(autoreverses: true)) { breathing = true } }`.
- Vérification de type trop lente sur `ForEach(Array(cards.enumerated()), …)` : `let indexed = Array(cards.enumerated())` avant le `ScrollView`, puis `ForEach(indexed, id: \.element.id)`.

---

### Task 4 : Transition zoom carte → Détail

**Files :**
- Create : `App/Matches/MatchRoute.swift`
- Modify : `App/Matches/MatchesView.swift` (`MatchRoute` retiré, `zoom` ajouté)
- Modify : `App/Matches/TeamCardView.swift` (`zoom`, routes des trois lignes, sources)
- Modify (réécrit) : `App/RootView.swift`
- Test : `Tests/FailleTests/ZoomSourceTests.swift` (créé)

**Interfaces :**
- Consumes : T3 (`MatchesView`, `TeamCardView` tels que réécrits) ; T1 (`Motion.runs(_:reduceMotion:)`, `Motion.Effect.zoom`, `@ReduceMotion`) ; `AppStore(preview:)`, `PreviewData.standard` (`var follows`), `SampleData.follows`, `SampleData.kcMatchId` ; `FollowList(teams:)` ; `FollowedTeam(id:code:name:image:homeLeagueName:spoilerFree:autoColorHex:colorOverrideHex:)` ; `NextLine.match(MatchEvent)` ; SwiftUI iOS 18+ `matchedTransitionSource(id:in:)`, `navigationTransition(_:)`, `NavigationTransition.zoom(sourceID:in:)`.
- Produces : `struct MatchRoute: Hashable { enum Row: String, CaseIterable { case live, next, last } ; let matchId: String ; let sourceID: String? ; init(matchId: String, sourceID: String? = nil) ; init(teamId: String, row: Row, matchId: String) }` ; `View.zoomSource(_ id: String?, in namespace: Namespace.ID?) -> some View` ; `View.zoomTransition(_ id: String?, in namespace: Namespace.ID, enabled: Bool) -> some View` ; `MatchesView(openTeams:zoom:)` ; `TeamCardView(card:zoom:)`.

- [ ] **Step 1 : Le test — `Tests/FailleTests/ZoomSourceTests.swift`**

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Zoom carte → Détail (spec finitions §6) : l'identifiant de source réunit la carte (équipe), la ligne et le match.
@MainActor
struct ZoomSourceTests {
    /// Chaque ligne de chaque carte a sa propre source, même quand deux cartes montrent le même match (KC et C9 suivies :
    /// KC – C9 en direct sur les deux cartes).
    @Test func everyCardRowHasItsOwnSource() {
        var data = PreviewData.standard
        data.follows = FollowList(teams: SampleData.follows.teams + [
            FollowedTeam(id: "c9", code: "C9", name: "Cloud9 Kia", homeLeagueName: "LCS", autoColorHex: "#4FC3F7"),
        ])
        let store = AppStore(preview: data)
        var routes: [MatchRoute] = []
        for card in store.cards {
            if let live = card.live {
                routes.append(MatchRoute(teamId: card.team.id, row: .live, matchId: live.id))
            }
            if case let .match(next) = store.nextLine(for: card) {
                routes.append(MatchRoute(teamId: card.team.id, row: .next, matchId: next.id))
            }
            if let last = card.last {
                routes.append(MatchRoute(teamId: card.team.id, row: .last, matchId: last.id))
            }
        }
        let ids = routes.compactMap(\.sourceID)
        #expect(ids.count == routes.count)
        #expect(Set(ids).count == ids.count)
        // Le même match sur deux cartes : deux sources, une seule destination.
        let kcC9 = routes.filter { $0.matchId == SampleData.kcMatchId }
        #expect(kcC9.count == 2)
        #expect(Set(kcC9.map(\.sourceID)).count == 2)
    }

    @Test func theSourceNamesTheCardTheRowAndTheMatch() {
        let route = MatchRoute(teamId: "kc", row: .live, matchId: "m1")
        #expect(route.matchId == "m1")
        #expect(route.sourceID != MatchRoute(teamId: "c9", row: .live, matchId: "m1").sourceID)
        #expect(route.sourceID != MatchRoute(teamId: "kc", row: .last, matchId: "m1").sourceID)
        #expect(route.sourceID != MatchRoute(teamId: "kc", row: .live, matchId: "m2").sourceID)
        // Sans source : transition standard.
        #expect(MatchRoute(matchId: "m1").sourceID == nil)
    }
}
```

- [ ] **Step 2 : `App/Matches/MatchRoute.swift`**

```swift
import SwiftUI

/// Destination de navigation : le Détail d'un match. `sourceID` désigne la ligne de carte touchée, d'où part le zoom
/// carte → Détail (spec finitions §6) ; nil : transition standard.
struct MatchRoute: Hashable {
    /// Ligne d'une carte qui ouvre le Détail.
    enum Row: String, CaseIterable, Sendable {
        case live, next, last
    }

    let matchId: String
    let sourceID: String?

    init(matchId: String, sourceID: String? = nil) {
        self.matchId = matchId
        self.sourceID = sourceID
    }

    /// Route d'une ligne de carte. Un même match peut être sur deux cartes (deux équipes suivies qui s'affrontent), et
    /// sur deux lignes d'une carte : la source réunit l'équipe de la carte, la ligne et le match, elle est donc unique.
    init(teamId: String, row: Row, matchId: String) {
        self.init(matchId: matchId, sourceID: "\(teamId)/\(row.rawValue)/\(matchId)")
    }
}

extension View {
    /// Source du zoom carte → Détail ; sans espace de noms (aperçus Xcode) ni identifiant : rien.
    @ViewBuilder func zoomSource(_ id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Transition de l'écran Détail : zoom depuis la ligne touchée ; sans ligne source, ou sous « Réduire les
    /// animations » (`enabled` faux), transition standard d'iOS.
    @ViewBuilder func zoomTransition(_ id: String?, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if let id, enabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
```

- [ ] **Step 3 : `App/Matches/MatchesView.swift`**

(a) Retirer l'ancienne route — remplacer :

```swift
import LoLKit
import SwiftUI

/// Destination de navigation : le Détail d'un match (branchée dans `RootView` à la Task 11).
struct MatchRoute: Hashable {
    let matchId: String
}

/// Onglet Matchs, version B
```

par :

```swift
import LoLKit
import SwiftUI

/// Onglet Matchs, version B
```

(b) Espace de noms du zoom — remplacer :

```swift
    let openTeams: () -> Void
    @ReduceMotion var reduceMotion
```

par :

```swift
    let openTeams: () -> Void
    /// Espace de noms du zoom carte → Détail (`RootView`) ; nil (aperçus Xcode) : pas de zoom.
    var zoom: Namespace.ID? = nil
    @ReduceMotion var reduceMotion
```

(c) Remplacer :

```swift
                        TeamCardView(card: card)
```

par :

```swift
                        TeamCardView(card: card, zoom: zoom)
```

- [ ] **Step 4 : `App/Matches/TeamCardView.swift`**

(a) Remplacer :

```swift
    let card: TeamCard
    @ReduceMotion var reduceMotion
```

par :

```swift
    let card: TeamCard
    /// Espace de noms du zoom carte → Détail ; nil : transition standard.
    var zoom: Namespace.ID? = nil
    @ReduceMotion var reduceMotion
```

(b) Bloc « En direct » — remplacer :

```swift
        let icon = LiveChipText.icon(for: state.phase)
        NavigationLink(value: MatchRoute(matchId: event.id)) {
```

par :

```swift
        let icon = LiveChipText.icon(for: state.phase)
        let route = MatchRoute(teamId: card.team.id, row: .live, matchId: event.id)
        NavigationLink(value: route) {
```

puis remplacer :

```swift
                    .transition(Motion.revealTransition(reduceMotion: reduceMotion))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        if state.spoilerFree {
```

par :

```swift
                    .transition(Motion.revealTransition(reduceMotion: reduceMotion))
                }
            }
            .contentShape(Rectangle())
            .zoomSource(route.sourceID, in: zoom)
        }
        .buttonStyle(.pressable)
        if state.spoilerFree {
```

(c) Ligne « Prochain » — remplacer :

```swift
        let date = Format.matchDate(event.startTime)
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
```

par :

```swift
        let date = Format.matchDate(event.startTime)
        let route = MatchRoute(teamId: card.team.id, row: .next, matchId: event.id)
        return NavigationLink(value: route) {
```

puis remplacer :

```swift
                IconView(icon: .clock, size: 16)
                    .foregroundStyle(Palette.secondary)
            }
            .contentShape(Rectangle())
        }
```

par :

```swift
                IconView(icon: .clock, size: 16)
                    .foregroundStyle(Palette.secondary)
            }
            .contentShape(Rectangle())
            .zoomSource(route.sourceID, in: zoom)
        }
```

(d) Ligne « Dernier » — remplacer :

```swift
        let text = Format.lastRow(line, order: order, date: Format.matchDate(event.startTime))
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
```

par :

```swift
        let text = Format.lastRow(line, order: order, date: Format.matchDate(event.startTime))
        let route = MatchRoute(teamId: card.team.id, row: .last, matchId: event.id)
        return NavigationLink(value: route) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .zoomSource(route.sourceID, in: zoom)
        }
```

Contrôle : `grep -n "MatchRoute(matchId" App/Matches/TeamCardView.swift` → aucune ligne.

- [ ] **Step 5 : Remplacer tout `App/RootView.swift`**

```swift
import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab
    @ReduceMotion var reduceMotion
    /// Zoom carte → Détail (spec finitions §6) : les lignes des cartes en sont les sources, l'écran Détail la destination.
    @Namespace private var zoom

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
                        .navigationDestination(for: MatchRoute.self) { route in
                            // Sans ligne source, ou sous « Réduire les animations » : transition standard d'iOS.
                            MatchDetailView(matchId: route.matchId)
                                .zoomTransition(route.sourceID, in: zoom,
                                                enabled: Motion.runs(.zoom, reduceMotion: reduceMotion))
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

- [ ] **Step 6 : Commit, push, CI**

```bash
git add App/Matches/MatchRoute.swift App/Matches/MatchesView.swift App/Matches/TeamCardView.swift App/RootView.swift Tests/FailleTests/ZoomSourceTests.swift
git commit -m "feat(app): transition zoom carte → Détail (source unique par carte et par ligne), standard sous Réduire les animations" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
```

Expected : verts ; `ZoomSourceTests` (2 tests) passent ; PNG inchangés (le zoom ne se voit que sur l'iPhone : checklist D.6). Replis :
- `matchedTransitionSource` ou `navigationTransition` refusés pour un identifiant `String` : passer `AnyHashable(id)` aux deux.
- Un comportement gênant vu sur l'iPhone (zoom qui ne revient pas vers sa ligne, ligne restée invisible) : désactiver le zoom en passant `enabled: false` dans `RootView` (transition standard), et le noter dans la checklist.

---

### Task 5 : Détail — pilules qui glissent, barre de gold, chiffres, révélation, squelettes, onglet des joueurs, retours haptiques

**Files :**
- Create : `App/DA/Skeleton.swift`
- Modify (réécrit) : `App/Detail/MatchDetailView.swift`, `App/Detail/LiveActivityPinButton.swift`
- Modify : `App/Detail/StatsPanels.swift` (`TeamStatsPanel`, `GoldBar`, `PlayersPanel`)
- Modify : `App/DA/Components.swift` (`PillButton`)
- Test : `Tests/FailleTests/DetailSnapshotTests.swift` (+ `loadingSkeletons`)

**Interfaces :**
- Consumes : T1 (`Motion`, `@ReduceMotion`, `.numericChange`, `.pressable`, `Haptic`, `HapticTrigger`, `.haptics`) ; T3 (`LiveIndicator(size:)`, `ScoreRow` avec révélation) ; `MatchDetailModel` : `matchId`, `var selectedGameNumber: Int?`, `var playersTeamIndex: Int`, `attempted`, `selectedGame(in:) -> GameRef?`, `run(store:) async`, `loadSelectedGame(store:) async` ; `AppStore` : `event(id:)`, `details`, `snapshots`, `statsUnavailable`, `isMasked(_:matchId:)`, `detailState(matchId:)`, `scoreLine(_:)`, `tint(for:)`, `reveal(matchId:)`, `pinActivity(matchId:) -> PinOutcome`, `removeActivity(matchId:)`, `liveActivities.shownMatchIds`, `liveActivities.isEnabled`, `settings.revealedMatchIds` ; `PinOutcome { pinned, full, disabled }` ; `NoteCard(icon:text:)`, `Chip`, `glassCard`, `Radius.inner` ; `GameSnapshot.stats(for:)`, `players(for:)` ; `Format.gold`, `Format.dragons`, `Format.role`, `Format.champion`, `Format.kda`.
- Produces : `struct SkeletonBlock: View { init(width: CGFloat? = nil, height: CGFloat, radius: CGFloat = 6) }` ; `struct StatsSkeleton: View` ; `struct DetailLoadingSkeleton: View` ; `struct TeamRowsSkeleton: View { init(count: Int = 5) }` ; `struct LeagueLoadingSkeleton: View` ; `PillButton(selected:selection:action:label:)` (`selection: Namespace.ID? = nil`) ; `LiveActivityPinButton(matchId:onHaptic:)` (`onHaptic: (Haptic) -> Void = { _ in }`). Aperçu `15-chargement.png`.

- [ ] **Step 1 : Le test d'aperçu — ajouter à la fin de l'extension de `Tests/FailleTests/DetailSnapshotTests.swift`**

Remplacer :

```swift
    @Test func detailMasked() async throws {
        let url = try await Snapshot.write(detail(SampleData.t1MatchId), named: "06-detail-masque")
        expectNotBlank(url)
    }
}
```

par :

```swift
    @Test func detailMasked() async throws {
        let url = try await Snapshot.write(detail(SampleData.t1MatchId), named: "06-detail-masque")
        expectNotBlank(url)
    }

    /// Squelettes de chargement (spec finitions §10), figés comme tous les aperçus : Détail, puis « Toutes les ligues ».
    @Test func loadingSkeletons() async throws {
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Chargement", subtitle: "Squelettes · Détail et catalogue")
                SectionLabel(text: "Détail d'un match")
                DetailLoadingSkeleton()
                SectionLabel(text: "Toutes les ligues")
                LeagueLoadingSkeleton()
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "15-chargement")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 2 : `App/DA/Skeleton.swift`**

```swift
import SwiftUI

/// Chargement (spec finitions §10) : une forme arrondie au gabarit du contenu attendu, balayée lentement par un reflet ;
/// figée sous « Réduire les animations ». Remplace les `ProgressView` et les textes d'attente (Détail, catalogue).
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 6
    @ReduceMotion var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Color.white.opacity(0.09))
            .overlay {
                if Motion.runs(.shimmer, reduceMotion: reduceMotion) {
                    Shimmer().clipShape(shape)
                }
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// Reflet qui traverse un squelette de gauche à droite, une fois toutes les `Motion.Duration.shimmer` secondes ; calculé
/// à partir de l'heure : tous les squelettes de l'écran balaient ensemble.
private struct Shimmer: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            TimelineView(.animation) { context in
                let band = max(width * 0.5, 40)
                let period = Motion.Duration.shimmer
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: -band + (width + band) * progress)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Squelette du panneau de stats d'une game : six lignes « valeur · libellé · valeur » et la barre de gold, au gabarit
/// de `TeamStatsPanel`.
struct StatsSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { row in
                HStack {
                    SkeletonBlock(width: 34, height: 14)
                    Spacer()
                    SkeletonBlock(width: 84, height: 11)
                    Spacer()
                    SkeletonBlock(width: 34, height: 14)
                }
                if row == 1 {
                    SkeletonBlock(height: 5, radius: 2.5)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stats en chargement")
    }
}

/// Squelette du Détail avant `getEventDetails` : pilules de games, puis panneau de stats.
struct DetailLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(width: 48, height: 30, radius: 15)
                }
            }
            StatsSkeleton()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement du match")
    }
}

/// Squelette de lignes d'équipes (catalogue, recherche) : badge, nom, ligue, étoile — gabarit de `CatalogTeamRow`.
struct TeamRowsSkeleton: View {
    var count = 5

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 10) {
                    SkeletonBlock(width: 34, height: 34, radius: 11)
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock(width: 140, height: 13)
                        SkeletonBlock(width: 64, height: 10)
                    }
                    Spacer(minLength: 8)
                    SkeletonBlock(width: 20, height: 20, radius: 10)
                        .frame(width: 44, height: 44)
                }
                .padding(.vertical, 2)
            }
        }
        .glassCard(radius: Radius.inner, padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des équipes")
    }
}

/// Squelette de « Toutes les ligues » : pilules de ligues, puis lignes d'équipes.
struct LeagueLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach([72, 56, 88, 64], id: \.self) { width in
                    SkeletonBlock(width: CGFloat(width), height: 30, radius: 15)
                }
            }
            TeamRowsSkeleton()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des ligues")
    }
}
```

- [ ] **Step 3 : `App/DA/Components.swift` — `PillButton`**

Remplacer toute la structure :

```swift
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
```

par :

```swift
/// Pilule sélectionnable (ligues, games) : blanche quand elle est choisie, verre sinon (onglets d'Échap).
/// `selection` : espace de noms de la capsule blanche, qui glisse alors d'une pilule à l'autre (spec finitions §9) ;
/// nil : la capsule change de place sans glisser (ligues, « Réduire les animations »).
struct PillButton<Content: View>: View {
    let selected: Bool
    var selection: Namespace.ID? = nil
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
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .slidingSelection(selection)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                }
            }
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

private extension View {
    /// Capsule de sélection partagée par les pilules (`matchedGeometryEffect`) ; rien sans espace de noms.
    @ViewBuilder func slidingSelection(_ namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: "pill-selection", in: namespace)
        } else {
            self
        }
    }
}
```

- [ ] **Step 4 : `App/Detail/StatsPanels.swift`**

(a) Lignes de stats — remplacer :

```swift
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
```

par :

```swift
        // Les chiffres défilent quand ils changent (spec finitions §4) ; le panneau n'existe que pour un match non masqué.
        HStack {
            Text(a)
                .font(Typo.stat)
                .numericChange(a)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: icon, text: label)
            Text(b)
                .font(Typo.stat)
                .numericChange(b)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
```

(b) Drakes — remplacer :

```swift
                Text("\(left.dragons.count)").font(Typo.stat)
```

par :

```swift
                Text("\(left.dragons.count)").font(Typo.stat).numericChange(left.dragons.count)
```

et remplacer :

```swift
                Text("\(right.dragons.count)").font(Typo.stat)
```

par :

```swift
                Text("\(right.dragons.count)").font(Typo.stat).numericChange(right.dragons.count)
```

(c) `GoldBar` — remplacer toute la structure :

```swift
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
```

par :

```swift
/// Barre d'écart de gold : la part de l'équipe de gauche, à sa couleur. Sa largeur glisse vers la nouvelle part
/// (`Motion.smooth`, spec finitions §9) ; immédiate sous « Réduire les animations ».
struct GoldBar: View {
    let left: Int
    let right: Int
    let tint: Color
    @ReduceMotion var reduceMotion

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
        .animation(Motion.animation(.smooth, reduceMotion: reduceMotion), value: share)
    }
}
```

(d) `PlayersPanel` — remplacer :

```swift
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
```

par :

```swift
            // Changement d'équipe animé (spec finitions §9) : les lignes de l'autre équipe arrivent en fondu (l'animation
            // vient de la liaison `selection`). Même espacement que le panneau : la mise en page ne change pas.
            VStack(alignment: .leading, spacing: 8) {
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
            .id(index)
            .transition(.opacity)
```

- [ ] **Step 5 : Remplacer tout `App/Detail/LiveActivityPinButton.swift`**

```swift
import LoLKit
import SwiftUI

/// « Épingler sur l'écran verrouillé » / « Retirer de l'écran verrouillé » (spec §5.3, §6.4). Explique pourquoi rien
/// ne s'affiche quand iOS a désactivé les Live Activities (spec §10) ou quand 3 sont déjà à l'écran.
struct LiveActivityPinButton: View {
    @Environment(AppStore.self) private var store
    let matchId: String
    @State private var refused: PinOutcome?
    /// Retour haptique de l'action (spec finitions §3), joué par l'écran Détail : ce bouton peut disparaître juste après
    /// « Retirer » (match terminé). Épinglé : succès ; retiré : impact léger ; refusé : rien.
    var onHaptic: (Haptic) -> Void = { _ in }

    var body: some View {
        let controller = store.liveActivities
        let shown = controller.shownMatchIds.contains(matchId)
        VStack(spacing: 6) {
            Button {
                if shown {
                    refused = nil
                    store.removeActivity(matchId: matchId)
                    onHaptic(.unpin)
                } else {
                    let outcome = store.pinActivity(matchId: matchId)
                    refused = outcome == .pinned ? nil : outcome
                    if outcome == .pinned {
                        onHaptic(.pin)
                    }
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
            .buttonStyle(.pressable)
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

- [ ] **Step 6 : Remplacer tout `App/Detail/MatchDetailView.swift`**

```swift
import LoLKit
import SwiftUI

/// Détail d'un match (spec §5.3) : en-tête teinté (ligue, bloc, Bo, chrono, équipes, score), pilules de games,
/// stats d'équipe et joueurs de la game choisie, et bouton « Épingler sur l'écran verrouillé » (iPhone, spec §6.4).
/// Anti-spoiler (spec §8) : tant que le match est masqué, rien ne s'affiche sauf l'en-tête sans score et « toucher pour
/// révéler » (ni pilules de games, ni stats, ni joueurs).
/// Finitions : capsule des pilules qui glisse, barre de gold et chiffres animés, révélation qui sort d'un flou,
/// squelettes de chargement, onglet des joueurs animé, retours haptiques (pilule, révélation, épingler, retirer).
struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var model: MatchDetailModel
    @ReduceMotion var reduceMotion
    /// Retours haptiques de l'écran : il reste affiché quand « toucher pour révéler » ou le bouton « Épingler » disparaît.
    @State private var haptics = HapticTrigger()
    /// Capsule de sélection des pilules de games, qui glisse de l'une à l'autre (`matchedGeometryEffect`).
    @Namespace private var pillSelection

    init(matchId: String) {
        _model = State(initialValue: MatchDetailModel(matchId: matchId))
    }

    /// Ce qui relance le chargement de la game affichée : un autre choix de game, ou la révélation du match
    /// (les stats arrivent aussitôt, sans attendre le cycle suivant de 10 s).
    private struct LoadKey: Equatable, Sendable {
        let game: Int?
        let revealed: Bool
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
        .haptics(haptics)
        .task { await model.run(store: store) }
        .task(id: LoadKey(game: model.selectedGameNumber, revealed: store.settings.revealedMatchIds.contains(model.matchId))) {
            await model.loadSelectedGame(store: store)
        }
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
            RevealButton { reveal() }
        } else if let details {
            // Pilules, stats et joueurs ; à la révélation, ils sortent d'un flou (spec finitions §8). Même espacement
            // que l'écran : la mise en page ne change pas.
            VStack(alignment: .leading, spacing: 14) {
                gamePills(details)
                if details.statsDisabled || event?.statsDisabled == true {
                    NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
                } else if let game = model.selectedGame(in: details) {
                    gameStats(game: game, teams: ordered)
                }
            }
            .transition(Motion.revealTransition(reduceMotion: reduceMotion))
        } else if model.attempted {
            NoteCard(icon: .refresh, text: "Détails du match indisponibles pour l'instant")
        } else {
            // Chargement (spec finitions §10) : le gabarit des pilules et des stats, à la place d'un `ProgressView`.
            DetailLoadingSkeleton()
        }
        if showsPinButton(event: event) {
            LiveActivityPinButton(matchId: model.matchId, onHaptic: { haptics.play($0) })
        }
    }

    /// « Toucher pour révéler » (spec §8) : le score et les stats sortent d'un flou en fondu, avec un retour haptique.
    private func reveal() {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.reveal(matchId: model.matchId)
        }
    }

    /// Choix d'une pilule : la capsule glisse (`Motion.snappy`) ; retour « sélection » si la game affichée change.
    private func selectGame(_ number: Int, shown: Int?) {
        if number != shown {
            haptics.play(.gamePicked)
        }
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) {
            model.selectedGameNumber = number
        }
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : iPhone seulement (Apple n'affiche pas les Live Activities sur
    /// iPad), pour un match en direct ou dont la Live Activity est encore à l'écran.
    private func showsPinButton(event: MatchEvent?) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && (event?.state == .inProgress || store.liveActivities.shownMatchIds.contains(model.matchId))
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
                // La pastille ne se coupe ni ne passe à la ligne : c'est le texte de gauche qui s'abrège.
                statusChip(event: event, state: state)
                    .lineLimit(1)
                    .fixedSize()
            }
            ScoreRow(teams: teams, score: seriesScore(event: event, state: state, order: order, masked: masked),
                     tints: teams.map { store.tint(for: $0) }, large: true)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }

    /// Score de série dans l'ordre d'affichage ; nil si masqué ou pas commencé (R-M5). Détails chargés : le score de
    /// `LiveMatchBuilder.state` (anti-spoiler appliqué par LoLKit) ; sinon celui de `Presenter.scoreLine`, jamais les
    /// victoires brutes du match.
    private func seriesScore(event: MatchEvent?, state: LiveMatchState?, order: [Int], masked: Bool) -> [Int]? {
        guard !masked else { return nil }
        if let state {
            return state.phase == .upcoming ? nil : state.seriesScore.flatMap { reorder($0, order) }
        }
        guard let event else { return nil }
        return store.scoreLine(event).score.flatMap { reorder($0, order) }
    }

    @ViewBuilder private func statusChip(event: MatchEvent?, state: LiveMatchState?) -> some View {
        // Comme sur la carte : un match que l'API donne pour terminé est « Terminé » (jamais « En direct », spec §8),
        // même si ses détails n'ont pas encore rattrapé la fin de la série.
        let shown = state?.displayed(for: event)
        switch shown?.phase ?? phase(of: event) {
        case .inGame, .betweenGames:
            Chip {
                LiveIndicator(size: 12)
                if let shown {
                    LiveChipText(state: shown, opponent: nil)
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

    /// « G1 ✓ », « G2 · en direct » (avec le halo « en direct »), « G3 »… une pilule par game jouée ou à venir ; la
    /// capsule blanche glisse vers la pilule touchée (spec finitions §9), sauf sous « Réduire les animations ».
    private func gamePills(_ details: EventDetails) -> some View {
        let games = details.match.games.filter { $0.state != .unneeded }
        let selected = model.selectedGame(in: details)?.number
        let slide: Namespace.ID? = Motion.runs(.pillSlide, reduceMotion: reduceMotion) ? pillSelection : nil
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(games, id: \.number) { game in
                    PillButton(selected: game.number == selected, selection: slide,
                               action: { selectGame(game.number, shown: selected) }) {
                        Text(game.state == .inProgress ? "G\(game.number) · en direct" : "G\(game.number)")
                        if game.state == .inProgress {
                            LiveIndicator(size: 12)
                        }
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
            PlayersPanel(teams: teams, snapshot: snapshot,
                         selection: $model.playersTeamIndex.animation(Motion.animation(.snappy, reduceMotion: reduceMotion)))
        } else if game.state == .inProgress {
            // Première frame pas encore arrivée (spec finitions §10) : le gabarit du panneau.
            StatsSkeleton()
        } else {
            NoteCard(icon: .refresh, text: "Stats de cette game indisponibles")
        }
    }
}

#Preview {
    NavigationStack { MatchDetailView(matchId: SampleData.kcMatchId) }.environment(AppStore(preview: .standard))
}
```

- [ ] **Step 7 : Commit, push, CI**

```bash
git add App/DA/Skeleton.swift App/DA/Components.swift App/Detail/MatchDetailView.swift App/Detail/StatsPanels.swift App/Detail/LiveActivityPinButton.swift Tests/FailleTests/DetailSnapshotTests.swift
git commit -m "feat(app): finitions du Détail — pilules qui glissent, barre de gold et chiffres animés, révélation, squelettes, onglet des joueurs, retours haptiques" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

Expected : verts. PNG à comparer au run de T4 : `04-detail.png` — pastille d'état avec le halo fixe derrière l'icône « en direct », pilule « G2 · en direct » suivie de l'icône « en direct » (seule différence de mise en page : la pilule G2 un peu plus large), stats et joueurs inchangés ; `04-detail-bas.png` (bouton « Retirer de l'écran verrouillé »), `05-detail-sans-stats.png`, `06-detail-masque.png` inchangés ; nouveau `15-chargement.png` (> 100 000 octets) : formes grises arrondies au gabarit des pilules, du panneau de stats et des lignes d'équipes, sans reflet (figé). Replis :
- `Binding.animation(_:)` refusé avec un `Animation?` : `$model.playersTeamIndex.animation(Motion.animation(.snappy, reduceMotion: reduceMotion) ?? .default)` n'est **pas** acceptable (animerait sous « Réduire les animations ») → à la place, garder `$model.playersTeamIndex` et ajouter `.animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: model.playersTeamIndex)` sur `PlayersPanel(…)`.
- La capsule « saute » au lieu de glisser sur l'iPhone : c'est que la sélection a changé hors de `withAnimation` ; vérifier que `selectGame` est bien le seul chemin (checklist D.9).

---

### Task 6 : Équipes, Réglages, feuille de couleur — toucher, retours haptiques, listes, squelettes du catalogue, bandeau

**Files :**
- Modify (réécrit) : `App/Teams/TeamsView.swift`
- Modify : `App/Teams/TeamRows.swift` (deux styles de bouton)
- Modify : `App/Teams/TeamColorSheet.swift` (`onPicked`)
- Modify : `App/Settings/SettingsView.swift` (« À propos »)
- Test : `Tests/FailleTests/TeamsSnapshotTests.swift` (+ `teamsLoading`)

**Interfaces :**
- Consumes : T1 (`Motion`, `@ReduceMotion`, `.pressable`, `Haptic`, `HapticTrigger`, `.haptics`) ; T5 (`LeagueLoadingSkeleton`, `TeamRowsSkeleton(count:)`) ; `AppStore` : `follows.teams`, `follows.contains(id:)`, `toggleFollow(_: Team)`, `unfollow(id:)`, `setSpoilerFree(_:id:)`, `setColorOverride(_:id:)`, `leaguePills`, `teams(in:)`, `search(_:)`, `catalog`, `isFailing`, `bannerText`, `logoFile(for:)` ; `FollowedTeamRow(team:logoFile:onToggleSpoiler:onUnfollow:)`, `CatalogTeamRow(team:followed:logoFile:onToggle:)` ; `TeamColorSheet.hexToSave(team:picked:)` (testé par `StoreTests`) ; `PreviewData(follows:)`, `SampleData.follows`.
- Produces : `TeamColorSheet(team: FollowedTeam, onPicked: @escaping () -> Void = {})` ; aperçu `03b-equipes-chargement.png` ; plus aucun `.buttonStyle(.plain)` dans `App/`.

- [ ] **Step 1 : Le test d'aperçu — `Tests/FailleTests/TeamsSnapshotTests.swift`**

Remplacer :

```swift
    @Test func teamsScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .teams).environment(AppStore(preview: .standard)), named: "03-equipes")
        expectNotBlank(url)
    }
}
```

par :

```swift
    @Test func teamsScreen() async throws {
        let url = try await Snapshot.write(RootView(tab: .teams).environment(AppStore(preview: .standard)), named: "03-equipes")
        expectNotBlank(url)
    }

    /// Catalogue pas encore chargé, API qui répond (spec finitions §10) : squelettes des pilules et des lignes sous
    /// « Toutes les ligues », au lieu de « Chargement des ligues… ».
    @Test func teamsLoading() async throws {
        let store = AppStore(preview: PreviewData(follows: SampleData.follows))
        let url = try await Snapshot.write(RootView(tab: .teams).environment(store), named: "03b-equipes-chargement")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 2 : Remplacer tout `App/Teams/TeamsView.swift`**

```swift
import LoLKit
import SwiftUI

/// Onglet Équipes (spec §5.2) : recherche, mes équipes (œil, étoile, couleur), toutes les ligues en pilules, réglages.
/// Finitions : boutons qui s'enfoncent, retours haptiques (suivre, ne plus suivre, œil, couleur), lignes de « Mes
/// équipes » qui arrivent et partent en douceur, squelettes pendant le chargement du catalogue, bandeau qui glisse.
struct TeamsView: View {
    @Environment(AppStore.self) private var store
    @ReduceMotion var reduceMotion
    @State private var query = ""
    @State private var selectedLeagueId: String?
    @State private var showSettings = false
    @State private var colorTeam: FollowedTeam?
    /// Retours haptiques de l'onglet : l'écran reste quand une ligne disparaît ou qu'une feuille se ferme.
    @State private var haptics = HapticTrigger()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Équipes", subtitle: Format.followCount(store.follows.teams.count)) {
                    Button { showSettings = true } label: {
                        IconView(icon: .settings, size: 22)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .foregroundStyle(Palette.text)
                    .accessibilityLabel("Réglages")
                }
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                        .transition(Motion.bannerTransition(reduceMotion: reduceMotion))
                }
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    myTeams
                    leagueSection
                } else {
                    searchResults
                }
            }
            // Bandeau (spec finitions §11) et lignes de « Mes équipes » (§7) : seules ces deux valeurs animent l'écran.
            .animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: store.isFailing)
            .animation(Motion.animation(.list, reduceMotion: reduceMotion), value: store.follows.teams.map(\.id))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .haptics(haptics)
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(store)
        }
        .sheet(item: $colorTeam) { team in
            TeamColorSheet(team: team, onPicked: { haptics.play(.colorPicked) }).environment(store)
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
                // Cible de 44 × 44 pt ; le retrait négatif garde le glyphe (16 pt) à sa place, au bord du champ.
                Button { query = "" } label: {
                    IconView(icon: .off, size: 16)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel("Effacer")
                .padding(.trailing, -14)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
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
                        onToggleSpoiler: { toggleSpoiler(team) },
                        onUnfollow: { unfollow(team) }
                    )
                    .transition(Motion.listTransition(reduceMotion: reduceMotion))
                    .contextMenu {
                        Button("Changer la couleur") { colorTeam = team }
                        Button("Couleur automatique") {
                            haptics.play(.colorPicked)
                            store.setColorOverride(nil, id: team.id)
                        }
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
            // Les pilules défilent jusqu'au bord de l'écran : la zone de défilement déborde des marges de 16 pt de la
            // page (retrait négatif), le contenu garde sa marge de départ, et rien n'est rogné au bord de la zone.
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
            .scrollClipDisabled()
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            teamList(store.teams(in: selected))
        } else if store.isFailing {
            NoteCard(icon: .refresh, text: "Ligues indisponibles pour l'instant.")
        } else {
            // Chargement (spec finitions §10) : le gabarit des pilules et des lignes, à la place d'un texte d'attente.
            LeagueLoadingSkeleton()
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = store.search(query)
        SectionLabel(text: "Résultats")
        if results.isEmpty {
            if store.catalog.isEmpty && !store.isFailing {
                TeamRowsSkeleton(count: 4)
            } else {
                NoteCard(icon: .search, text: store.catalog.isEmpty ? "Équipes indisponibles pour l'instant." : "Aucune équipe ne correspond.")
            }
        } else {
            teamList(results)
        }
    }

    /// Équipes non suivies du catalogue ou de la recherche (plusieurs centaines) : rangées créées à la demande.
    private func teamList(_ teams: [Team]) -> some View {
        LazyVStack(spacing: 4) {
            ForEach(teams) { team in
                CatalogTeamRow(team: team, followed: store.follows.contains(id: team.id),
                               logoFile: store.logoFile(for: team.image)) {
                    toggleFollow(team)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 12)
    }

    /// Étoile du catalogue (spec finitions §3) : suivre (succès) ou ne plus suivre (impact léger).
    private func toggleFollow(_ team: Team) {
        haptics.play(store.follows.contains(id: team.id) ? .unfollow : .follow)
        store.toggleFollow(team)
    }

    /// Étoile de « Mes équipes » : ne plus suivre (impact léger) ; la ligne part en fondu.
    private func unfollow(_ team: FollowedTeam) {
        haptics.play(.unfollow)
        store.unfollow(id: team.id)
    }

    /// Œil (spec §8) : masquer ou afficher en simple fondu (spec finitions §8), retour « sélection ».
    private func toggleSpoiler(_ team: FollowedTeam) {
        haptics.play(.spoilerToggle)
        withAnimation(Motion.fade) {
            store.setSpoilerFree(!team.spoilerFree, id: team.id)
        }
    }
}

#Preview {
    NavigationStack { TeamsView() }.environment(AppStore(preview: .standard))
}
```

- [ ] **Step 3 : `App/Teams/TeamRows.swift`**

Dans `FollowedTeamRow`, remplacer :

```swift
                .accessibilityLabel("Ne plus suivre")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
```

par :

```swift
                .accessibilityLabel("Ne plus suivre")
            }
        }
        .buttonStyle(.pressable)
        .padding(.vertical, 2)
```

Dans `CatalogTeamRow`, remplacer :

```swift
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(followed ? "Ne plus suivre" : "Suivre")
```

par :

```swift
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(followed ? "Ne plus suivre" : "Suivre")
```

- [ ] **Step 4 : `App/Teams/TeamColorSheet.swift`**

Remplacer :

```swift
    let team: FollowedTeam
    @State private var color: Color

    init(team: FollowedTeam) {
        self.team = team
        _color = State(initialValue: Palette.team(team.colorHex))
    }
```

par :

```swift
    let team: FollowedTeam
    /// Couleur validée ou remise en automatique : l'onglet Équipes joue le retour « sélection » (spec finitions §3) ; la
    /// feuille se ferme aussitôt, le retour est donc joué par l'écran qui reste.
    let onPicked: () -> Void
    @State private var color: Color

    init(team: FollowedTeam, onPicked: @escaping () -> Void = {}) {
        self.team = team
        self.onPicked = onPicked
        _color = State(initialValue: Palette.team(team.colorHex))
    }
```

Remplacer :

```swift
                Button("Couleur automatique (tirée du logo)") {
                    store.setColorOverride(nil, id: team.id)
                    dismiss()
                }
```

par :

```swift
                Button("Couleur automatique (tirée du logo)") {
                    store.setColorOverride(nil, id: team.id)
                    onPicked()
                    dismiss()
                }
```

Remplacer :

```swift
                        if let hex = Self.hexToSave(team: team, picked: color) {
                            store.setColorOverride(hex, id: team.id)
                        }
                        dismiss()
```

par :

```swift
                        if let hex = Self.hexToSave(team: team, picked: color) {
                            store.setColorOverride(hex, id: team.id)
                            onPicked()
                        }
                        dismiss()
```

- [ ] **Step 5 : `App/Settings/SettingsView.swift`**

Remplacer :

```swift
                        .foregroundStyle(Palette.text)
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    .buttonStyle(.plain)
```

par :

```swift
                        .foregroundStyle(Palette.text)
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    .buttonStyle(.pressable)
```

- [ ] **Step 6 : Plus aucun style « plain »**

```bash
grep -rn "buttonStyle(.plain)" App
```

Expected : aucune ligne (spec finitions §2 : `PressableStyle` partout).

- [ ] **Step 7 : Commit, push, CI**

```bash
git add App/Teams/TeamsView.swift App/Teams/TeamRows.swift App/Teams/TeamColorSheet.swift App/Settings/SettingsView.swift Tests/FailleTests/TeamsSnapshotTests.swift
git commit -m "feat(app): finitions d'Équipes et des Réglages — toucher, retours haptiques, lignes animées, squelettes du catalogue, bandeau" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

Expected : verts (y compris `StoreTests`, qui appelle `TeamColorSheet.hexToSave`). PNG à comparer au run de T5 : `03-equipes.png`, `07-reglages.png`, `07b-a-propos.png` inchangés ; nouveau `03b-equipes-chargement.png` : « Mes équipes » (KC, T1, GEN) puis, sous « Toutes les ligues », pilules et lignes en squelettes figés.

---

### Task 7 : Widgets et Live Activity — chiffres qui défilent

**Files :**
- Modify : `Shared/LiveActivity/LiveActivityViews.swift` (`LiveActivityStatusView`, `LiveActivityScoreRow`, `LiveActivityStatRows`)
- Modify : `Shared/LiveActivity/IslandViews.swift` (compacte, minimale, centre, bas)
- Modify : `Shared/Widgets/HomeWidgetViews.swift` (petit, moyen)
- Modify : `Shared/Widgets/AccessoryWidgetViews.swift` (en ligne, rectangulaire, rond)

**Interfaces :**
- Consumes : T1 (`View.numericTransition()`, `Shared/DA/Motion.swift`, compilé dans l'extension).
- Produces : transitions numériques posées sur les textes de score et de stats ; aucune animation continue ; vues et tests de l'étape 3-4 inchangés (`LockScreenBoard`, `HomeScreenBoard`, `LiveActivityBoard`, `DynamicIslandBoard`, contrôles d'encre et de hauteur).

- [ ] **Step 1 : `Shared/LiveActivity/LiveActivityViews.swift`**

(a) Chrono figé — remplacer :

```swift
            case let .clock(.stopped(text)):
                if let prefix {
                    Text(prefix)
                }
                Text(text)
                    .monospacedDigit()
```

par :

```swift
            case let .clock(.stopped(text)):
                if let prefix {
                    Text(prefix)
                }
                Text(text)
                    .monospacedDigit()
                    .numericTransition()
```

(b) Score — remplacer :

```swift
            if let score = display.score, score.count == 2 {
                Text(Format.score(score))
                    .font(Sora.font(22, .bold))
                    .monospacedDigit()
            } else {
```

par :

```swift
            if let score = display.score, score.count == 2 {
                // Score non masqué (`display.score` est nil pour un match masqué) : ses chiffres défilent d'une mise à
                // jour à l'autre (spec finitions §4).
                Text(Format.score(score))
                    .font(Sora.font(22, .bold))
                    .monospacedDigit()
                    .numericTransition()
            } else {
```

(c) Lignes de stats (la grille ne contient aucun chrono) — remplacer :

```swift
        .font(Sora.font(11.5, .bold))
        .monospacedDigit()
    }
```

par :

```swift
        .font(Sora.font(11.5, .bold))
        .monospacedDigit()
        .numericTransition()
    }
```

- [ ] **Step 2 : `Shared/LiveActivity/IslandViews.swift`**

(a) Compacte — remplacer :

```swift
        .font(Sora.font(14, .bold))
        .monospacedDigit()
        .foregroundStyle(Color.white)
```

par :

```swift
        .font(Sora.font(14, .bold))
        .monospacedDigit()
        .foregroundStyle(Color.white)
        .numericTransition()
```

(b) Minimale — remplacer :

```swift
                    Text(score)
                        .font(Sora.font(11, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
```

par :

```swift
                    Text(score)
                        .font(Sora.font(11, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .numericTransition()
```

(c) Centre (le chrono est à côté : la transition va sur le score seul) — remplacer :

```swift
                Text(Format.score(score))
                    .font(Sora.font(26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
```

par :

```swift
                Text(Format.score(score))
                    .font(Sora.font(26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .numericTransition()
```

(d) Bas — remplacer :

```swift
            .font(Sora.font(11, .semibold))
            .monospacedDigit()
            .opacity(display.faded ? 0.55 : 1)
```

par :

```swift
            .font(Sora.font(11, .semibold))
            .monospacedDigit()
            .opacity(display.faded ? 0.55 : 1)
            .numericTransition()
```

- [ ] **Step 3 : `Shared/Widgets/HomeWidgetViews.swift`** (aucun chrono dans ces vues : la transition va sur la racine)

Remplacer :

```swift
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Monogrammes : les deux équipes du match (couleur des équipes suivies), sinon l'équipe seule.
```

par :

```swift
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // WidgetKit anime le passage d'une entrée à l'autre : les chiffres défilent (spec finitions §4).
        .numericTransition()
    }

    /// Monogrammes : les deux équipes du match (couleur des équipes suivies), sinon l'équipe seule.
```

Remplacer :

```swift
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// « ● KC 1 – 0 C9   [en direct Game 2] » ; à venir : « ● GEN vs FUR   jeu. 11:00 » ;
```

par :

```swift
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .numericTransition()
    }

    /// « ● KC 1 – 0 C9   [en direct Game 2] » ; à venir : « ● GEN vs FUR   jeu. 11:00 » ;
```

- [ ] **Step 4 : `Shared/Widgets/AccessoryWidgetViews.swift`**

(a) En ligne — remplacer :

```swift
        } icon: {
            InlineIcon.image(content.headline?.isLive == true ? .live : .clock)
        }
    }
```

par :

```swift
        } icon: {
            InlineIcon.image(content.headline?.isLive == true ? .live : .clock)
        }
        .numericTransition()
    }
```

(b) Rectangulaire — remplacer :

```swift
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
```

par :

```swift
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .numericTransition()
    }
```

(c) Rond — remplacer :

```swift
            case .empty:
                ring(0)
                IconView(icon: .trophy, size: 18)
                    .foregroundStyle(.secondary)
            }
        }
    }
```

par :

```swift
            case .empty:
                ring(0)
                IconView(icon: .trophy, size: 18)
                    .foregroundStyle(.secondary)
            }
        }
        .numericTransition()
    }
```

- [ ] **Step 5 : Aucune animation continue dans les widgets ni la Live Activity**

```bash
grep -rn "phaseAnimator\|TimelineView\|repeatForever\|LiveIndicator\|TeamGlow\|SkeletonBlock" Shared/Widgets Shared/LiveActivity Widgets
```

Expected : aucune ligne.

- [ ] **Step 6 : Commit, push, CI**

```bash
git add Shared/LiveActivity/LiveActivityViews.swift Shared/LiveActivity/IslandViews.swift Shared/Widgets/HomeWidgetViews.swift Shared/Widgets/AccessoryWidgetViews.swift
git commit -m "feat(widgets): chiffres qui défilent dans les widgets et la Live Activity (transitions numériques seulement)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch --exit-status <id>
gh run download <id> --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-<id>" && ls -la "$HOME/Downloads/faille-apercus-<id>"
```

Expected : `build` (l'extension compile `numericTransition`) et `apercus` verts, y compris `everyStateOfEveryAccessoryAndMediumFamilyDrawsItsContent`, `theMediumWidgetFitsFourRowsInEverySize`, `liveActivityFitsAndDraws`, `everyPieceOfEveryStateDrawsItsContent` ; `09-widgets-verrouille.png`, `10-widgets-accueil.png`, `11-widgets-moyen.png`, `12-live-activity.png`, `13-dynamic-island.png` identiques au run de T6. Garder l'id de ce run pour T8 (IPA).

---

### Task 8 : Checklist « Finitions » sur l'iPhone de Dan (manuelle)

**Files :**
- Modify : `docs/superpowers/notes/2026-10-14-checklist-iphone.md` (titre ; section D ajoutée à la fin)

**Interfaces :**
- Consumes : l'IPA du dernier run vert (T7) ; tous les comportements de T1-T7.
- Produces : section « D. Finitions » ; `C:\Users\Dan\Downloads\faille\Faille-finitions.ipa`.

- [ ] **Step 1 : Préparer l'IPA**

```bash
RUN=<id du run de T7>
gh run download "$RUN" --name Faille-ipa --dir "$HOME/Downloads/faille-finitions-$RUN"
mkdir -p "$HOME/Downloads/faille"
cp "$HOME/Downloads/faille-finitions-$RUN/Faille.ipa" "$HOME/Downloads/faille/Faille-finitions.ipa"
ls -la "$HOME/Downloads/faille/Faille-finitions.ipa"
```

Expected : le fichier existe (plusieurs Mo).

- [ ] **Step 2 : Titre de la checklist**

Remplacer :

```markdown
# Faille — checklist de test sur l'iPhone (étapes 2, 3 et 4)
```

par :

```markdown
# Faille — checklist de test sur l'iPhone (étapes 2, 3, 4 et finitions)
```

- [ ] **Step 3 : Ajouter la section D à la fin du fichier**

Remplacer :

```markdown
Variante possible : garder le chrono **et** ajouter un petit « màj il y a X min ». Le chrono reste juste (il est calculé à partir du début de la game), sauf si la game s'est terminée entre-temps. À toi de choisir après l'avoir vu en vrai.
```

par :

```markdown
Variante possible : garder le chrono **et** ajouter un petit « màj il y a X min ». Le chrono reste juste (il est calculé à partir du début de la game), sauf si la game s'est terminée entre-temps. À toi de choisir après l'avoir vu en vrai.

## D. Finitions (animations, retours tactiles, icône)

À faire avec `C:\Users\Dan\Downloads\faille\Faille-finitions.ipa` (installer comme au §0). Un match en direct d'une équipe suivie aide pour D.4, D.5, D.12 et D.14 ; le reste se vérifie à tout moment. Pour chaque ligne : OK / KO + une remarque (« trop lent », « trop fort », « on ne le voit pas »…) : c'est ici que se juge le style « sobre et fluide ».

1. **Icône** : sur l'écran d'accueil, l'icône Faille (fond abysse, faille verticale lumineuse cyan, halo doux, aucun texte) remplace l'icône vide ; la même dans Réglages › Faille, Spotlight et le sélecteur d'applis. Appui long sur l'accueil › Personnaliser › **Sombre** : la faille sur fond sombre ; **Teinté** : une version d'une seule teinte, lisible.
2. **Toucher** : le bloc « En direct » d'une carte, les lignes Prochain et Dernier, une pilule de ligue ou de game, l'étoile, l'œil, « Choisir mes équipes », « Épingler », « À propos » s'enfoncent légèrement et pâlissent pendant l'appui, puis reviennent sans rebond. Les zones de toucher n'ont pas rétréci (œil et étoile toujours faciles à viser).
3. **Retours haptiques**, un seul par action : suivre une équipe (succès) ; ne plus suivre (léger) ; œil (petit clic) ; Épingler (succès) ; Retirer (léger) ; toucher pour révéler (moyen) ; tirer pour rafraîchir (succès ; en mode avion : avertissement) ; Valider une couleur ou « Couleur automatique » (petit clic) ; changer de pilule de game (petit clic). **Aucun** retour pendant un match quand les stats se mettent à jour toutes les 10 s.
4. **Chiffres qui défilent** (match en direct) : sur la carte et dans le Détail, kills, gold, tours, inhibs, barons, drakes et le score de série changent en faisant défiler leurs chiffres ; le sous-titre « N en direct · N à venir » aussi. Sur une carte masquée : aucun chiffre, donc rien ne défile.
5. **« En direct »** : un halo doux respire lentement (≈ 1,6 s) derrière l'icône « en direct » de la pastille de la carte, de la pastille du Détail et de la pilule de la game en cours ; il ne clignote pas.
6. **Zoom** : toucher le bloc « En direct » d'une carte → le Détail s'ouvre en zoomant depuis ce bloc ; revenir (bouton retour, glisser depuis le bord gauche ou vers le bas) → il se referme vers le même bloc. Pareil depuis « Prochain » et « Dernier ». Si les deux équipes d'un match sont suivies (deux cartes), le zoom part de la carte touchée.
7. **Listes** : dans Équipes, suivre / ne plus suivre fait apparaître (fondu, léger grossissement) ou disparaître (fondu) la ligne dans « Mes équipes », sans saut. À l'ouverture de l'appli, les cartes de Matchs arrivent en cascade rapide, une fois ; en revenant du Détail, pas de nouvelle cascade.
8. **Révéler** : sur une carte masquée, « toucher pour révéler » → le score et les stats sortent d'un flou en fondu (≈ 0,5 s), avec un retour moyen ; pareil dans le Détail. Remettre l'œil dans Équipes → la carte redevient masquée en simple fondu. Aucun chiffre n'apparaît, même un instant, sur un match encore masqué.
9. **Détail** : la capsule blanche glisse d'une pilule de game à l'autre ; la barre de gold change de largeur en douceur ; changer d'équipe dans « Joueurs » fait un fondu des lignes.
10. **Chargement** : ouvrir un match pas encore chargé (ou, au premier lancement, l'onglet Équipes) → des formes grises arrondies au gabarit du contenu, parcourues d'un reflet lent, au lieu d'une roue ; le contenu les remplace dès qu'il arrive.
11. **Bandeau d'erreur** : mode avion puis tirer pour rafraîchir → le bandeau descend du haut en fondu ; sortir du mode avion → il remonte et disparaît.
12. **Lueur d'équipe** : une carte dont le match est en direct et non masqué a un contour qui luit doucement à la couleur de l'équipe et respire lentement (≈ 2,4 s) ; une carte masquée (équipe en anti-spoiler) n'a **aucune** lueur.
13. **Réduire les animations** (Réglages › Accessibilité › Mouvement › Réduire les animations, activé) : plus de zoom (transition standard), plus de cascade, halo et lueur fixes, squelettes sans reflet, les surfaces ne s'enfoncent plus (elles pâlissent seulement), la capsule des pilules ne glisse plus, chiffres et révélation en simple fondu ; les retours haptiques sont toujours là. Désactiver ensuite.
14. **Widgets et Live Activity** : quand le score ou une stat change, les chiffres défilent au passage (si iOS l'anime) ; rien ne bouge en continu (pas de halo, pas de pulsation).
15. **Fluidité** : pendant un match en direct, faire défiler Matchs et le Détail : aucun à-coup ; le téléphone ne chauffe pas plus qu'avant.
```

- [ ] **Step 4 : Commit et push**

```bash
git add docs/superpowers/notes/2026-10-14-checklist-iphone.md
git commit -m "docs(notes): checklist « Finitions » pour l'iPhone (icône, toucher, haptique, zoom, Réduire les animations)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 5 : Vérifications de Dan** — une réponse par ligne de la section D, sur l'iPhone. Les KO deviennent des corrections (nouvelle tâche, mêmes règles) ; les réglages de dosage (durée, amplitude, opacité) se font dans `Shared/DA/Motion.swift` et `App/DA/LiveEffects.swift` uniquement.

---

## Auto-relecture

**1. Couverture de la spec (12 points + principes + vérification)**

| Spec | Où |
|---|---|
| §1 Icône (AppIconArt, 1024 px, échelle 1, sombre transparent, teintée gris, appiconset une taille, `APPICON_NAME: AppIcon` appli seule, `14-icone.png` fonds clair et sombre) | T2 |
| §2 Toucher (`PressableStyle` 0,97, opacité, `press`, partout à la place de `.plain`, zone tactile mesurée) | T1 (style + test), T3, T5, T6 (pose ; T6 Step 6 vérifie qu'il ne reste aucun `.plain`) |
| §3 Retours haptiques (suivre/ne plus suivre, œil, épingler/retirer, révéler, rafraîchir succès/avertissement, couleur, pilule ; jamais en boucle) | T1 (`Haptic`, `HapticTrigger`), T3 (révéler, rafraîchir), T5 (révéler, pilule, épingler/retirer), T6 (suivre, ne plus suivre, œil, couleur) |
| §4 Chiffres qui défilent (score de série, kills, gold, tours, inhibs, barons, drakes, chrono figé, « N à venir » ; cartes, Détail, widgets, Live Activity) | T1 (modificateurs), T3 (cartes, chrono figé, compteur), T5 (Détail), T7 (widgets, Live Activity) |
| §5 Point « en direct » qui pulse (cartes, Détail, pilules ; statique sous Réduire ; pas dans widgets / LA) | T3 (`LiveIndicator`, cartes), T5 (pastille et pilule du Détail), T7 Step 5 (contrôle) |
| §6 Zoom carte → Détail (source = carte + ligne ; repli standard) | T4 |
| §7 Listes animées (fondu + 0,96 / fondu, `Motion.list`, cascade 40 ms, 8 au plus, une fois) | T1 (valeurs), T3 (cartes, cascade), T6 (« Mes équipes ») |
| §8 Révélation (flou 10 → 0 + fondu + haptique ; masquage en fondu) | T1 (`revealTransition`), T3 (carte), T5 (Détail, en-tête par `ScoreRow`), T6 (œil en fondu) |
| §9 Pilules (`matchedGeometryEffect`), barre de gold (`smooth`), onglet des joueurs | T5 |
| §10 Chargement (`SkeletonBlock`, reflet, statique sous Réduire ; Détail, catalogue) | T5 (composants, Détail, `15-chargement`), T6 (catalogue, `03b-equipes-chargement`) |
| §11 Bandeau d'erreur (glisse du haut + fondu, `snappy`) | T3 (Matchs), T6 (Équipes) |
| §12 Lueur d'équipe (direct et non masqué, 2,4 s, statique sous Réduire, rien sur carte masquée) | T3 (`TeamGlow`, `TeamCardView.glows` + 2 tests) |
| Principes : vocabulaire unique, aucune durée en dur | T1 (`Motion`) ; toutes les vues passent par `Motion` |
| Principes : Réduire les animations | T1 (règle + tests), chaque effet ci-dessous |
| Principes : sobre, Liquid Glass système inchangé | Global Constraints ; aucun `glassEffect`, `TabView`/barres non touchés |
| Principes : anti-spoiler | voir point 3 |
| Vérification : PNG existants, `14-icone.png`, tests Motion / zoom / zone tactile, checklist | T1 (aperçus figés, tests), T2, T4, T8 |

**2. « Réduire les animations » partout**

| Effet | Sous « Réduire les animations » |
|---|---|
| Appui (`PressableStyle`) | échelle 1, pas d'animation ; opacité gardée |
| Chiffres (`numericChange`, `numericTransition`) | transition `.opacity`, fondu 0,2 s |
| Halo « en direct » (`LiveIndicator`) | halo fixe |
| Lueur d'équipe (`TeamGlow`) | lueur fixe |
| Cascade (`CascadeIn`) | aucune (`cardsShown` vrai d'emblée) |
| Listes (`listTransition`, `Motion.list`) | `.opacity` + fondu |
| Bandeau (`bannerTransition`, `snappy`) | `.opacity` + fondu |
| Révélation (`revealTransition`, `reveal`) | `.opacity` + fondu, sans flou |
| Zoom (`zoomTransition`) | transition standard d'iOS |
| Capsule des pilules (`slidingSelection`) | pas de `matchedGeometryEffect`, fondu |
| Barre de gold (`smooth`) | immédiate |
| Onglet des joueurs (`snappy`) | fondu |
| Reflet des squelettes (`Shimmer`) | retiré (bloc fixe) |
| Retours haptiques | inchangés |

**3. Anti-spoiler** — `numericChange` n'est posé que sur : `ScoreRow` quand `score` n'est pas nil (nil si masqué : `seriesScore(…masked:)`, `state.seriesScore` de LoLKit), `MiniStats` et le bloc de score de la carte (rendus seulement si `!state.spoilerFree`), le chrono figé (branche non masquée de `LiveChipText`), `TeamStatsPanel` (rendu seulement si `!masked`), le sous-titre (comptes de `Format.cardsSubtitle`, qui exclut déjà les « Prochain · masqué »). Aucun sur `Format.lastRow` ni sur le texte masqué de `LiveChipText`. Lueur : `TeamCardView.glows` exige `!spoilerFree` (testé sur T1 de l'aperçu). Révélation : seul le contenu révélé est inséré (le contenu masqué n'a jamais été rendu). Halo : il accompagne « En direct », que la spec §8 affiche aussi pour un match masqué. Ordre des cartes animé : l'ordre vient de `TeamCards.build` (déjà anti-spoiler). Widgets / LA : textes issus de `WidgetText` / `LiveActivityDisplay` (déjà masqués).

**4. API et replis** — `@Entry` (repli : `EnvironmentKey`, T1) ; `@ReduceMotion` / `DynamicProperty` en Swift 6 (repli : `@MainActor`, puis deux `@Environment` par vue, T1) ; `.sensoryFeedback(trigger:_:)` (repli : fermeture typée, T1) ; `phaseAnimator` (repli : `@State` + `repeatForever` dans `onAppear`, T3) ; `matchedTransitionSource` / `navigationTransition(.zoom)` (repli : `AnyHashable`, puis `enabled: false`, T4) ; `Binding.animation` (repli : `.animation(_:value:)`, T5) ; `ImageRenderer` 1024 px (repli : `proposedSize`, T2) ; apparences `dark`/`tinted` d'actool (repli : entrée universelle seule, T2) ; `AppIcon` vu par l'extension (repli : `App/AppIcon.xcassets`, T2) ; `.contentTransition(.numericText())` (iOS 16+, aucune). Pas de `symbolEffect` (icônes du catalogue).

**5. Cohérence des noms et des types** — `Motion.animation(_:reduceMotion:) -> Animation?`, `Motion.runs(_:reduceMotion:) -> Bool`, `Motion.Effect.{livePulse, teamGlow, shimmer, cascade, zoom, pillSlide}`, `Motion.Reduced.{full, fade, instant}` (pas de cas `none`, qui se confondrait avec `Optional.none` dans `#expect(… == .none)`), `Motion.listTransition / bannerTransition / revealTransition(reduceMotion:)` (`@MainActor`, appelés depuis des `body`), `Motion.list` (T3 `CascadeIn`), `Motion.fade` (T6 œil) ; `@ReduceMotion var reduceMotion` partout sans `private` ; `HapticTrigger.play(_:)` / `.haptics(_:)` ; `Haptic.colorPicked` (T6), `.gamePicked` (T5), `.pin/.unpin` (T5), `.reveal` (T3, T5), `.refreshSucceeded/.refreshFailed` (T3), `.follow/.unfollow/.spoilerToggle` (T6) ; `LiveIndicator(size:)` (T3 → T5) ; `ChipIcon(icon:size:)` (T3) ; `View.teamGlow(_:active:)`, `View.cascadeIn(index:shown:)` (T3) ; `MatchRoute(matchId:sourceID:)` et `MatchRoute(teamId:row:matchId:)` (T4), `MatchRoute.Row.{live,next,last}` ; `View.zoomSource(_:in:)` (`Namespace.ID?`) et `View.zoomTransition(_:in:enabled:)` (`Namespace.ID`) ; `MatchesView(openTeams:zoom:)`, `TeamCardView(card:zoom:)` ; `SkeletonBlock(width:height:radius:)`, `StatsSkeleton()`, `DetailLoadingSkeleton()`, `TeamRowsSkeleton(count:)`, `LeagueLoadingSkeleton()` (T5 → T6) ; `PillButton(selected:selection:action:label:)` (T5 ; ligues sans `selection`) ; `LiveActivityPinButton(matchId:onHaptic:)` (T5) ; `TeamColorSheet(team:onPicked:)` (T6 ; `hexToSave` inchangé) ; `AppIconVariant.fileName` = noms des PNG de l'artefact et du `Contents.json` (T2) ; `View.numericChange(_:)` (appli) / `View.numericTransition()` (widgets, LA).

**6. Recherche de trous** — aucun « TBD », aucun « comme la tâche N » pour du code ; chaque étape de code donne le code entier ou l'ancre exacte et son remplacement ; les ancres de T4 citent le texte écrit par T3.
