# Fonctionnalités (appli) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** brancher dans l'appli Faille les cinq fonctionnalités du lot — « Regarder » / « Revoir », notifications locales de début de match, draft et builds avec icônes (champions, objets, runes, sorts) et sorts d'invocateur des games terminées, fil des événements, courbe de l'écart de gold — en consommant les modules LoLKit déjà fusionnés, sans jamais rien montrer ni rien demander au réseau pour un match masqué. Terminé quand la checklist « Fonctionnalités » passe sur l'iPhone de Dan.

**Architecture :** chaque fonctionnalité vit dans ses propres fichiers (`App/Watch/`, `App/Reminders/`, `App/DataDragon/` + `App/Cache/`, `App/Timeline/`, `App/Spells/`, `App/Builds/`) : un petit store `@Observable` par donnée réseau (`DataDragonStore`, `GameDetailsStore`, `TimelineStore`, `SummonerSpellsStore`), construit avec un `HTTPTransport` et un `DiskCache` (nil = aperçu inerte), et des vues qui ne reçoivent que des valeurs. Six tâches de fonctionnalité, menées en parallèle par vagues dans des worktrees séparés, ne touchent aucun fichier partagé (sauf les quelques-uns attribués à une seule tâche dans la matrice) ; une tâche d'intégration finale ajoute les propriétés à `AppStore`, branche le Détail, la carte, les Réglages, la racine et le lancement, met à jour les données d'aperçu et la checklist. La garde anti-spoiler est unique : `MatchDetailModel.featureGame(store:)` (nil pour un match masqué ou sans stats) commande toutes les requêtes des fonctionnalités du Détail ; les vues n'existent que dans la branche « non masqué ».

**Tech Stack :** Swift 6 (appli, extension, tests), SwiftUI iOS 26, Swift Charts (`Chart`, `AreaMark`, `LineMark`, `RuleMark`), UserNotifications (`UNUserNotificationCenter`, `UNCalendarNotificationTrigger`, délégué), `openURL`, Observation, Swift Testing (tests hébergés + aperçus PNG `Snapshot.write`), LoLKit (Swift 6.2, Docker `swift:6.2` via `scripts/lolkit.sh`), XcodeGen, GitHub Actions `macos-26` (workflow `iOS`, aussi sur `fonc/**`) et `ubuntu` (workflow `LoLKit`), `gh`.

**Spec :** `docs/superpowers/specs/2026-10-14-faille-fonctionnalites-design.md` (contraignante : principes, §1-§5, Vérification) et `docs/superpowers/notes/2026-10-14-idees.md` ; spec principale `docs/superpowers/specs/2026-10-13-faille-design.md` (§4 données et règle des 80 s, §5 écrans, §8 anti-spoiler, §9 DA) ; finitions `docs/superpowers/specs/2026-10-14-faille-finitions-design.md` (`Motion`, `PressableStyle`, retours haptiques, « Réduire les animations », squelettes : réutilisés, style A sobre). Modules consommés : plan `docs/superpowers/plans/2026-10-14-fonctionnalites-lolkit.md` (journal `.superpowers/sdd/2026-10-14-fonctionnalites-lolkit/progress.md`). Checklist : `docs/superpowers/notes/2026-10-14-checklist-iphone.md`.

## Global Constraints

- iOS minimum **26.0** ; appli, extension et tests en Swift 6 (`SWIFT_VERSION: "6.0"`) ; LoLKit en Swift 6.2 ; iPhone + iPad.
- **Pas de Mac** : le code iOS ne se compile et ne se teste qu'en CI (GitHub Actions `macos-26`, Xcode 26, SDK iOS 26). Les changements de LoLKit se font en TDD avec `bash scripts/lolkit.sh test` (Docker Desktop lancé, Git Bash, depuis la racine du worktree).
- **Nouvelle règle de CI (demande de Dan) : on n'attend pas la CI après chaque commit ni après chaque étape.** On commit et on pousse, puis on continue ; la CI est vérifiée **une fois par branche de tâche, avant sa fusion** (dernière étape de chaque tâche), puis **une fois à la fin du lot sur `main`**. Run retrouvé par le SHA **complet** : `gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'` (un SHA court ne renvoie rien ; le run peut mettre quelques secondes à apparaître), puis `gh run watch --exit-status <id>` ; échec : `gh run view <id> --log-failed`. Tâches qui touchent `LoLKit/**` : même chose avec `--workflow LoLKit`.
- **Exécution en parallèle** : une tâche = une branche `fonc/appli-tN-<slug>` dans son propre worktree (`git worktree add ../faille-appli-tN -b <branche> main`), poussée avec `git push -u origin <branche>` ; jamais de push sur `main` depuis une tâche (le contrôleur fusionne). Une tâche ne modifie **que** les fichiers de sa ligne de la « Matrice des fichiers ».
- **Anti-spoiler (contraignant)** : pour un match masqué, rien de ceci n'est affiché ni demandé au réseau — stream « en direct », rediffusion (le nombre de games trahit la série), draft, objets, runes, sorts, fil, courbe de gold, sorts d'invocateur ; aucune requête `details`, `window` de relecture, Leaguepedia ni image Data Dragon de sa draft. Les notifications ne visent que les matchs que `Presenter.nextLine` montre (`MatchReminders.plan`) et ne portent jamais de score.
- **Sobriété réseau** : versions Data Dragon gardées sur disque 24 h (`DataDragon.versionsMaxAge`), catalogues et images sur disque pour toujours (`cache/ddragon/<version>/…`), images décodées hors du `body` ; `details` toutes les 60 s (`LoLClient.detailsInterval`) seulement tant que le Détail d'une game en cours est affiché, une seule fois pour une game terminée ; relecture `window` à pas de 60 s seulement pour une game terminée ou une ouverture tardive, à la demande (Détail ouvert), gardée sur disque, une pause de 0,5 s entre deux requêtes ; Leaguepedia : une requête par match pour toutes ses games, sous `SpellLookupPolicy` (3 essais, 10 min d'écart, 30 min après un refus, plus rien après un succès) **et** les règles de l'appli : premier essai ≥ 30 min après la fin du match, essais espacés d'au moins 1 h, jamais pour un match masqué ni pas terminé.
- Caches des fonctionnalités : un seul dossier `cache/` à côté des fichiers de Faille (`files.directory/cache`), exclu de la sauvegarde iCloud ; chemins relatifs sûrs (`DiskCache.safePath`), JSON en `JSONEncoder()` / `JSONDecoder()` par défaut. Aucun bundle ID ni nom de groupe en dur (notifications : identifiant `match-start-<matchId>` de LoLKit).
- Notifications : `UNUserNotificationCenter`, notifications locales seulement ; réglage désactivé par défaut, délai 5 / 15 / 30 min (défaut 15) dans `AppSettings` (décodage tolérant) ; l'autorisation n'est demandée qu'en activant le réglage ; reprogrammation à chaque changement du plan (calendrier, équipes suivies, révélations, réglages) ; toucher une notification ouvre le Détail du match (`userInfo["matchId"]` → `MatchRoute`).
- DA et finitions réutilisées : `Motion` (aucune durée en dur), `@ReduceMotion`, `.buttonStyle(.pressable)` sur toute surface touchable (zone ≥ 44 pt), `HapticTrigger` joué par la vue qui reste affichée, `SkeletonBlock` pour les chargements, `.glassCard`, `Palette`, `Typo`, `IconView` (icônes du catalogue, jamais de SF Symbols ni d'emoji), une teinte = une équipe suivie.
- Aperçus PNG figés (`Snapshot.write`, « Réduire les animations » forcé) : chaque PNG > 100 000 octets (`expectNotBlank`) ; images des aperçus = vignettes de repli ou fausses icônes générées dans le test (`TestImages`), **aucun réseau dans les tests**, aucune image de Riot dans le dépôt. Nouveaux PNG : `16-regarder`, `17-notifications`, `18-data-dragon`, `19-fil-et-courbe`, `20-joueurs`, `20b-fiche-joueur`, `21-detail-direct` (+ `-milieu`, `-bas`), `22-detail-termine` (+ `-bas`), `23-fiche-joueur`, `24-carte-regarder` ; `06-detail-masque` et `07-reglages` restent (le second montre la section Notifications).
- **Vague de corrections des finitions** : elle a pu toucher `App/Detail/MatchDetailView.swift`, `App/Matches/TeamCardView.swift` et `App/Detail/LiveActivityPinButton.swift` après l'écriture de ce plan (ancres prises à `origin/main` 8571588). Avant chaque remplacement « Remplacer … par … » dans ces trois fichiers, l'implémenteur relit l'ancre à HEAD (`git pull --ff-only origin main` d'abord) et l'adapte si elle a bougé, sans changer le sens.
- Textes de l'interface en français, identifiants en anglais, commentaires en français, fins de ligne LF (`.gitattributes`).
- Commits avec l'adresse noreply déjà configurée : `git commit -m "<message>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.

## Décisions prises par ce plan (au-delà de la spec)

- **« Regarder » absent pour un match masqué** (carte et Détail) : la spec interdit le « stream en direct avec score » ; un stream montre toujours le score, donc le bouton n'apparaît qu'après révélation. **« Revoir la game N » pour la game choisie** dans les pilules (une à la fois), y compris quand Riot ne fournit pas les stats live du match.
- **Châtiment du jungler en direct** (demande du brief) : les sorts d'invocateur ne sont pas dans le flux ; en direct (ou tant que Leaguepedia n'a pas la game), seul le Châtiment du jungler est montré — déduction sûre (tout jungler le prend), qui ne révèle rien. Game terminée : les deux sorts de Leaguepedia pour les dix joueurs.
- **Leaguepedia : une requête par match**, centrée sur le milieu des débuts de ses games (± 3 h couvrent une série dont les games commencent à moins de 6 h d'écart), seulement match terminé ; début et champions de chaque game lus une fois (fenêtre `window` sans `startingTime`) et gardés ; fin du match = frame `finished` de sa dernière game si le Détail l'a lue, sinon début de la dernière game + 1 h ; succès seulement si toutes les games sont trouvées (sinon un essai compté, résultats partiels gardés) ; une requête annulée après son envoi compte comme un essai.
- **Relecture à la demande = à l'ouverture du Détail** d'une game jouée (ou en cours, ouverte en retard) non masquée, progressive (la courbe se dessine pas à pas), reprise au pas suivant si l'écran est quitté ; 90 pas au plus. Les frames du direct (10 s) ne sont gardées qu'en mémoire.
- **Patch d'une game** : gardé par `AppStore.loadWindow` à chaque fenêtre lue (`patches[gameId]`), donc sans requête de plus ; la version Data Dragon n'est cherchée qu'une fois ce patch connu (avant : vignettes de repli). Catalogues (objets, runes, sorts d'invocateur) chargés à l'ouverture du Détail ; sorts d'un champion (`champion/<id>.json`) seulement à l'ouverture de sa fiche.
- **Images** : chemin de cache = chemin de l'URL Data Dragon après `/cdn/` ; une image absente chez Data Dragon (≠ 200) n'est plus redemandée de la session, une panne réseau si. Aperçus : vignettes de repli (initiales du champion, cases vides), pas de fausses icônes dans les captures du Détail.
- **Joueurs** : la section « Joueurs » enrichie remplace `PlayersPanel` (supprimé), avec son squelette de même hauteur (`BuildPlayersSkeleton`) ; jointure flux `window` ↔ `details` par position (bleu 1-5, rouge 6-10). Balise mise à part par le catalogue, sinon par les ids connus 3340 / 3363 / 3364. Fiche : feuille `.medium` / `.large`.
- **Ordre du Détail** : en-tête → « Regarder » → pilules → « Revoir » → draft → stats d'équipe → courbe → joueurs → fil → « Épingler ». Fil : 10 événements, « Tout le fil » pour le reste.
- **Notifications** : reprogrammées par une tâche de la scène (`.task(id: store.reminderSignature)` dans `FailleApp`) ; rien pendant un réveil d'arrière-plan sans scène (le plan est rejoué à la prochaine ouverture). Au premier plan, une notification de Faille s'affiche quand même (bannière). Autorisation refusée : l'interrupteur se recoupe et la section dit où l'autoriser. Délai hors 5 / 15 / 30 min : ramené à 15 min (décodage et `didSet`).
- **Retours haptiques** : `.watch` (impact léger) pour « Regarder » / « Revoir », `.playerPicked` (sélection) à l'ouverture d'une fiche ; rien pour l'interrupteur des notifications (contrôle système).
- **Icône `play`** (écran + triangle, trait 1,8, grille 24) ajoutée au catalogue pour « Regarder » / « Revoir » (`Icon.allCases.count` passe à 23).
- **`project.yml` inchangé** : Swift Charts et UserNotifications se lient d'eux-mêmes (modules système) et les notifications locales ne demandent aucune clé d'Info.plist.

## Structure des fichiers

```
LoLKit/Sources/LoLKit/Storage/AppSettings.swift          (T2) + matchRemindersEnabled, matchReminderLead
LoLKit/Tests/LoLKitTests/ReminderSettingsTests.swift     (T2)
LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift, SpellMatcher.swift   (T5) lignes « Anti-spoiler » des docs
App/Watch/WatchLinks.swift                               (T1) liens permis (anti-spoiler), libellés
App/Watch/WatchButtons.swift                             (T1) WatchButton (menu des autres streams), ReplayButton
App/Reminders/ReminderCenter.swift                       (T2) ReminderCenter, InertReminderCenter, ReminderPayload, ReminderSync
App/Reminders/SystemReminderCenter.swift                 (T2) UNUserNotificationCenter, ReminderNotificationDelegate
App/Reminders/NotificationRouter.swift                   (T2) match à ouvrir après un toucher
App/Reminders/MatchRemindersSection.swift                (T2) section des Réglages
App/Store/AppStore+Reminders.swift                       (T2) plan, signature, reprogrammation
App/Cache/DiskCache.swift                                (T3) cache disque des fonctionnalités
App/DataDragon/DataDragon+Cache.swift                    (T3) chemin de cache d'une URL Data Dragon
App/DataDragon/DataDragonStore.swift                     (T3) versions, catalogues, images
App/DataDragon/DDragonIcon.swift                         (T3) icône + environnement \.dataDragon
App/Timeline/ReplayFrames.swift                          (T4) CachedFrame, ReplayRecord, ReplaySchedule
App/Timeline/TimelineFormat.swift                        (T4) TimelineText, GoldChartData
App/Timeline/TimelineStore.swift                         (T4) relecture + direct
App/Timeline/TimelineSamples.swift                       (T4) scénarios d'exemple
App/Timeline/TimelineCard.swift                          (T4) fil
App/Timeline/GoldChartCard.swift                         (T4) courbe (Swift Charts)
App/Spells/SpellSchedule.swift                           (T5) règles de l'appli envers Leaguepedia
App/Spells/SummonerSpellsStore.swift                     (T5) une requête par match, disque
App/Builds/GameDetailsStore.swift                        (T6) flux details (60 s / une fois)
App/Builds/PlayerBuilds.swift                            (T6) jointure, draft, balise, sorts montrés
App/Builds/BuildSamples.swift                            (T6) détails d'exemple
App/Builds/DraftStrip.swift                              (T6) draft
App/Builds/BuildPlayersPanel.swift                       (T6) section « Joueurs » enrichie, ligne, squelette
App/Builds/PlayerSheet.swift                             (T6) fiche du joueur
App/Preview/FeatureSamples.swift                         (T7) données des fonctionnalités des aperçus
App/Detail/MatchDetailModel+Features.swift               (T7) garde anti-spoiler et chargements du Détail
App/Detail/GameFeatureSections.swift                     (T7) sections du Détail branchées sur le store
App/Store/AppStore.swift, App/Detail/MatchDetailView.swift, App/Detail/StatsPanels.swift, App/DA/Skeleton.swift,
App/Matches/TeamCardView.swift, App/Settings/SettingsView.swift, App/RootView.swift, App/FailleApp.swift,
Shared/Preview/SampleData.swift                          (T7) intégration
Shared/DA/Icon.swift, App/DA/Haptics.swift, Resources/Assets.xcassets/icon-play.imageset/   (T1)
Tests/FailleTests/…                                      une suite et un fichier d'aperçus par tâche (voir matrice)
docs/superpowers/notes/2026-10-14-checklist-iphone.md    (T7) section E « Fonctionnalités »
```

## Matrice des fichiers

Une ligne par tâche ; aucun fichier n'apparaît sur deux lignes (vérifié). « Modifie » = la seule tâche autorisée à toucher ce fichier existant.

| Tâche | Branche | Crée | Modifie |
|---|---|---|---|
| T1 Regarder / Revoir | `fonc/appli-t1-regarder` | `App/Watch/WatchLinks.swift`, `App/Watch/WatchButtons.swift`, `Resources/Assets.xcassets/icon-play.imageset/{Contents.json,icon-play.svg}`, `Tests/FailleTests/WatchTests.swift`, `Tests/FailleTests/WatchSnapshotTests.swift` | `Shared/DA/Icon.swift`, `App/DA/Haptics.swift`, `Tests/FailleTests/ApercuTests.swift`, `Tests/FailleTests/MotionTests.swift` |
| T2 Notifications | `fonc/appli-t2-notifications` | `LoLKit/Tests/LoLKitTests/ReminderSettingsTests.swift`, `App/Reminders/ReminderCenter.swift`, `App/Reminders/SystemReminderCenter.swift`, `App/Reminders/NotificationRouter.swift`, `App/Reminders/MatchRemindersSection.swift`, `App/Store/AppStore+Reminders.swift`, `Tests/FailleTests/RemindersTests.swift`, `Tests/FailleTests/RemindersSnapshotTests.swift` | `LoLKit/Sources/LoLKit/Storage/AppSettings.swift` |
| T3 Socle Data Dragon | `fonc/appli-t3-data-dragon` | `App/Cache/DiskCache.swift`, `App/DataDragon/DataDragon+Cache.swift`, `App/DataDragon/DataDragonStore.swift`, `App/DataDragon/DDragonIcon.swift`, `Tests/FailleTests/Support/TestImages.swift`, `Tests/FailleTests/DiskCacheTests.swift`, `Tests/FailleTests/DataDragonStoreTests.swift`, `Tests/FailleTests/DataDragonSnapshotTests.swift` | — |
| T4 Fil et courbe | `fonc/appli-t4-fil-courbe` | `App/Timeline/ReplayFrames.swift`, `App/Timeline/TimelineFormat.swift`, `App/Timeline/TimelineStore.swift`, `App/Timeline/TimelineSamples.swift`, `App/Timeline/TimelineCard.swift`, `App/Timeline/GoldChartCard.swift`, `Tests/FailleTests/TimelineStoreTests.swift`, `Tests/FailleTests/TimelineSnapshotTests.swift` | — |
| T5 Sorts d'invocateur | `fonc/appli-t5-sorts` | `App/Spells/SpellSchedule.swift`, `App/Spells/SummonerSpellsStore.swift`, `Tests/FailleTests/SummonerSpellsTests.swift` | `LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift`, `LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift` (documentation) |
| T6 Draft et builds | `fonc/appli-t6-builds` | `App/Builds/GameDetailsStore.swift`, `App/Builds/PlayerBuilds.swift`, `App/Builds/BuildSamples.swift`, `App/Builds/DraftStrip.swift`, `App/Builds/BuildPlayersPanel.swift`, `App/Builds/PlayerSheet.swift`, `Tests/FailleTests/BuildsTests.swift`, `Tests/FailleTests/BuildsSnapshotTests.swift` | — |
| T7 Intégration | `fonc/appli-t7-integration` | `App/Preview/FeatureSamples.swift`, `App/Detail/MatchDetailModel+Features.swift`, `App/Detail/GameFeatureSections.swift`, `Tests/FailleTests/FeaturesIntegrationTests.swift`, `Tests/FailleTests/FeaturesSnapshotTests.swift` | `App/Store/AppStore.swift`, `App/Detail/MatchDetailView.swift`, `App/Detail/StatsPanels.swift`, `App/DA/Skeleton.swift`, `App/Matches/TeamCardView.swift`, `App/Settings/SettingsView.swift`, `App/RootView.swift`, `App/FailleApp.swift`, `Shared/Preview/SampleData.swift`, `docs/superpowers/notes/2026-10-14-checklist-iphone.md` |

Fichiers partagés de la consigne et leur unique propriétaire : `MatchDetailView`, `TeamCardView`, `SettingsView`, `RootView`, `AppStore.swift` (propriétés), `SampleData`/`PreviewData` → **T7** ; `AppSettings` (LoLKit) → **T2** ; `project.yml` → personne (aucun changement). `LiveActivityPinButton.swift` n'est touché par aucune tâche. Noms de types, de suites de tests et d'aperçus uniques (vérifié) ; les aides de test sont `private` à leur fichier.

## Exécution en parallèle

- **Vague A (en parallèle)** : T1, T2, T3, branches créées depuis `main`.
- **Vague B (en parallèle, après la fusion de T3 dans `main`)** : T4, T5, T6, branches créées depuis `main` à jour (ils utilisent `DiskCache` ; T6 aussi `DataDragonStore` et `DDragonIcon`). T4 et T5 peuvent démarrer dès que T3 est fusionnée, même si T1 et T2 ne le sont pas encore.
- **Vague C** : T7, depuis `main` qui contient T1 à T6.
- Le contrôleur, pour chaque tâche : `git pull --ff-only origin main` puis `git worktree add ../faille-appli-tN -b fonc/appli-tN-<slug> main` ; l'implémenteur travaille dans ce dossier (`scripts/lolkit.sh` y crée son propre volume Docker). Fusion de chaque branche dans `main` par le contrôleur, après la CI verte de la branche (`git merge --no-ff`, aucun conflit attendu : fichiers disjoints). À la fin : CI de `main` sur le SHA de la dernière fusion, `bash scripts/lolkit.sh test` sur `main` (attendu : `Test run with 320 tests in 37 suites passed`), puis l'IPA de ce run pour Dan.

## Dépendances

- **T1 :** aucune.
- **T2 :** aucune.
- **T3 :** aucune.
- **T4 :** T3 (`DiskCache`).
- **T5 :** T3 (`DiskCache`).
- **T6 :** T3 (`DiskCache`, `DataDragonStore`, `DDragonIcon`, `EnvironmentValues.dataDragon`).
- **T7 :** T1 à T6.

**Vérifié avant d'écrire ce plan** (copie d'`origin/main` 8571588 hors du dépôt) : les 41 remplacements « Remplacer … par … » s'appliquent chacun à une ancre unique ; le code sans UIKit / SwiftUI / UserNotifications des tâches (liens, programmation des notifications, cache disque, chemins et store Data Dragon avec un `UIImage` de substitution, relecture, scénarios, Leaguepedia, détails, jointure, échantillons, `SampleData`) compile sans avertissement en Swift 6.2 (Docker `swift:6.2`) et ses tests passent (les 38 tests sans UIKit du plan, plus deux contrôles de cohérence des données d'aperçu) ; LoLKit avec T2 et T5 : `Test run with 320 tests in 37 suites passed` (316 / 36 avant). Le reste (vues, iOS) n'est compilé qu'en CI.

---

### Task 1: « Regarder » et « Revoir » (liens, boutons, icône, retours haptiques)

**Branche :** `fonc/appli-t1-regarder` · **Vague :** A · **Dépendances :** aucune.

**Files:**
- Create: `App/Watch/WatchLinks.swift`
- Create: `App/Watch/WatchButtons.swift`
- Create: `Resources/Assets.xcassets/icon-play.imageset/Contents.json`, `Resources/Assets.xcassets/icon-play.imageset/icon-play.svg`
- Modify: `Shared/DA/Icon.swift` (enum `Icon`), `App/DA/Haptics.swift` (enum `Haptic`), `Tests/FailleTests/ApercuTests.swift:23`, `Tests/FailleTests/MotionTests.swift:101`
- Test: `Tests/FailleTests/WatchTests.swift`, `Tests/FailleTests/WatchSnapshotTests.swift` (aperçu `16-regarder.png`)

**Interfaces:**
- Consumes (à `origin/main`) : LoLKit `StreamPicker.preferred(_ streams: [StreamInfo]) -> StreamLink?`, `StreamPicker.others(_ streams: [StreamInfo]) -> [StreamLink]`, `StreamPicker.replay(_ vods: [Vod]) -> StreamLink?` ; `struct StreamLink { provider: String; locale: String?; url: URL }` + `init(provider:locale:url:)` ; `StreamInfo(statsStatus: String?, provider: String? = nil, parameter: String? = nil, locale: String? = nil)` ; `Vod(provider:parameter:locale:startMillis:)` ; `GameRef(number:id:state:teams:vods: [Vod]? = nil)`, `GameRef.vods: [Vod]?`, `GameRef.state` ; appli `Haptic`, `IconView(icon:size:)`, `Palette`, `Typo`, `Radius.inner`, `.glassCard(tint:radius:padding:)`, `.buttonStyle(.pressable)`, `ScreenHeader(_:subtitle:)`, `SectionLabel(text:)`, `.abyssBackground()` ; tests `Snapshot.write(_:named:)`, `ApercuTests.expectNotBlank(_:)`.
- Produces :
  - `enum WatchLinks` : `struct Live: Equatable, Sendable { let preferred: StreamLink; let others: [StreamLink] }` ; `static func live(_ streams: [StreamInfo]?, inProgress: Bool, masked: Bool) -> Live?` (nil si masqué, pas en cours ou sans fournisseur connu) ; `static func replay(_ game: GameRef, masked: Bool) -> StreamLink?` (game `completed` d'un match non masqué) ; `static func label(_ link: StreamLink) -> String` (« Français · Twitch »).
  - `struct WatchButton: View` — `init(live: WatchLinks.Live, compact: Bool = false, onHaptic: @escaping (Haptic) -> Void = { _ in })` (memberwise).
  - `struct ReplayButton: View` — `init(gameNumber: Int, link: StreamLink, onHaptic: @escaping (Haptic) -> Void = { _ in })`.
  - `Icon.play` (asset `icon-play`) ; `Haptic.watch` (style `.lightImpact`), `Haptic.playerPicked` (style `.selection`, utilisé par T7 à l'ouverture d'une fiche).

Les tests iOS ne tournent qu'en CI : ils sont écrits d'abord (ils fixent le comportement), puis le code ; la CI de la branche les exécute une fois, à la fin de la tâche.

- [ ] **Step 1: Écrire les tests des liens**

Créer `Tests/FailleTests/WatchTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// « Regarder » et « Revoir » (spec fonctionnalités §1) : quels liens l'appli montre, et jamais pour un match masqué.
struct WatchTests {
    private static let streams = [
        StreamInfo(statsStatus: "enabled", provider: "youtube", parameter: "lolesports", locale: "en-US"),
        StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR"),
        StreamInfo(statsStatus: "enabled", provider: "afreecatv", parameter: "aflol", locale: "ko-KR"),
        StreamInfo(statsStatus: "enabled", provider: "huya", parameter: "lpl", locale: "zh-CN"),
    ]

    @Test func liveMatchWatchesTheFrenchStreamAndOffersTheOthers() throws {
        let live = try #require(WatchLinks.live(Self.streams, inProgress: true, masked: false))
        #expect(live.preferred.url.absoluteString == "https://www.twitch.tv/otplol_")
        #expect(live.others.map(\.provider) == ["youtube", "afreecatv"]) // fournisseur inconnu : ignoré
    }

    /// Anti-spoiler : un match masqué n'a pas de « Regarder » (l'image du stream montre le score).
    @Test func maskedOrFinishedMatchHasNoWatchButton() {
        #expect(WatchLinks.live(Self.streams, inProgress: true, masked: true) == nil)
        #expect(WatchLinks.live(Self.streams, inProgress: false, masked: false) == nil)
        #expect(WatchLinks.live(nil, inProgress: true, masked: false) == nil)
        #expect(WatchLinks.live([StreamInfo(statsStatus: "enabled")], inProgress: true, masked: false) == nil)
    }

    @Test func replayOfAPlayedGameStartsAtTheGame() throws {
        let vods = [Vod(provider: "youtube", parameter: "abc123", locale: "en-US", startMillis: 95_000)]
        let game = GameRef(number: 2, id: "g2", state: .completed, teams: nil, vods: vods)
        let link = try #require(WatchLinks.replay(game, masked: false))
        #expect(link.url.absoluteString == "https://www.youtube.com/watch?v=abc123&t=95s")
        // Anti-spoiler : masqué, rien (le nombre de games trahirait la série) ; game pas jouée : rien.
        #expect(WatchLinks.replay(game, masked: true) == nil)
        let live = GameRef(number: 3, id: "g3", state: .inProgress, teams: nil, vods: vods)
        #expect(WatchLinks.replay(live, masked: false) == nil)
        let without = GameRef(number: 1, id: "g1", state: .completed, teams: nil)
        #expect(WatchLinks.replay(without, masked: false) == nil)
    }

    @Test func labelsNameTheLanguageAndThePlatform() throws {
        func link(_ provider: String, _ locale: String?) -> StreamLink {
            StreamLink(provider: provider, locale: locale, url: URL(string: "https://example.com")!)
        }
        #expect(WatchLinks.label(link("twitch", "fr-FR")) == "Français · Twitch")
        #expect(WatchLinks.label(link("youtube", "en-US")) == "Anglais · YouTube")
        #expect(WatchLinks.label(link("afreecatv", "ko-KR")) == "Coréen · AfreecaTV")
        #expect(WatchLinks.label(link("twitch", "xx-XX")) == "xx-XX · Twitch")
        #expect(WatchLinks.label(link("youtube", nil)) == "YouTube")
    }
}
```

- [ ] **Step 2: Écrire `WatchLinks`**

Créer `App/Watch/WatchLinks.swift` :

```swift
import Foundation
import LoLKit

/// « Regarder » et « Revoir » (spec fonctionnalités §1) : les liens que l'appli a le droit de montrer. Le choix du stream et
/// de la rediffusion vient de LoLKit (`StreamPicker`). Anti-spoiler : rien pour un match masqué — ni stream en direct
/// (l'image montre le score), ni rediffusion (le nombre de games trahit la série).
enum WatchLinks {
    /// Le stream du bouton « Regarder » et ceux du menu de l'appui long.
    struct Live: Equatable, Sendable {
        let preferred: StreamLink
        let others: [StreamLink]
    }

    /// Streams d'un match en cours et non masqué ; nil sinon, ou si aucun fournisseur n'est connu.
    static func live(_ streams: [StreamInfo]?, inProgress: Bool, masked: Bool) -> Live? {
        guard inProgress, !masked, let streams, let preferred = StreamPicker.preferred(streams) else { return nil }
        return Live(preferred: preferred, others: StreamPicker.others(streams))
    }

    /// « Revoir la game N » : la rediffusion d'une game jouée d'un match non masqué ; nil sinon.
    static func replay(_ game: GameRef, masked: Bool) -> StreamLink? {
        guard !masked, game.state == .completed, let vods = game.vods else { return nil }
        return StreamPicker.replay(vods)
    }

    /// Langues les plus courantes des streams lolesports, par code de langue.
    private static let languages = [
        "fr": "Français", "en": "Anglais", "ko": "Coréen", "zh": "Chinois", "es": "Espagnol", "pt": "Portugais",
        "de": "Allemand", "it": "Italien", "ja": "Japonais", "vi": "Vietnamien", "ru": "Russe", "pl": "Polonais",
        "tr": "Turc", "ar": "Arabe", "th": "Thaï",
    ]

    private static let platforms = ["twitch": "Twitch", "youtube": "YouTube", "afreecatv": "AfreecaTV"]

    /// « Français · Twitch » ; langue inconnue : son code tel quel (« xx-XX · Twitch ») ; sans langue : la plateforme seule.
    static func label(_ link: StreamLink) -> String {
        let platform = platforms[link.provider] ?? link.provider
        guard let locale = link.locale, !locale.isEmpty else { return platform }
        let code = String(locale.prefix { $0 != "-" && $0 != "_" }).lowercased()
        return "\(languages[code] ?? locale) · \(platform)"
    }
}
```

- [ ] **Step 3: Ajouter l'icône `play`**

Créer `Resources/Assets.xcassets/icon-play.imageset/icon-play.svg` (même trait que les autres icônes : 1,8, grille 24, rendu « template ») :

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><rect fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" x="3" y="5" width="18" height="14" rx="3"/><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M10.5 9.5v5l4.2-2.5z"/></svg>
```

Créer `Resources/Assets.xcassets/icon-play.imageset/Contents.json` :

```json
{
  "images" : [
    {
      "filename" : "icon-play.svg",
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
```

Dans `Shared/DA/Icon.swift` :

Remplacer :

```swift
    case trophy, settings, search, back, arrow, pin, check, refresh, off, pause
```

par :

```swift
    case trophy, settings, search, back, arrow, pin, check, refresh, off, pause
    /// « Regarder » / « Revoir » (spec fonctionnalités §1) : écran avec un triangle de lecture.
    case play
```

Dans `Tests/FailleTests/ApercuTests.swift` (`iconsAreInTheCatalog`) :

Remplacer :

```swift
        #expect(Icon.allCases.count == 22)
```

par :

```swift
        #expect(Icon.allCases.count == 23)
```

- [ ] **Step 4: Ajouter les retours haptiques `watch` et `playerPicked`**

Dans `App/DA/Haptics.swift` :

1. Remplacer :

```swift
    case colorPicked
    case gamePicked
```

par :

```swift
    case colorPicked
    case gamePicked
    /// « Regarder » / « Revoir » (spec fonctionnalités §1).
    case watch
    /// Fiche d'un joueur ouverte depuis « Joueurs » (spec fonctionnalités §3).
    case playerPicked
```

2. Remplacer :

```swift
    /// Suivre, épingler, rafraîchir : succès ; ne plus suivre, retirer : impact léger ; œil, couleur, pilule :
    /// sélection ; révéler : impact moyen ; rafraîchir en échec : avertissement.
    var style: Style {
        switch self {
        case .follow, .pin, .refreshSucceeded: return .success
        case .unfollow, .unpin: return .lightImpact
        case .spoilerToggle, .colorPicked, .gamePicked: return .selection
```

par :

```swift
    /// Suivre, épingler, rafraîchir : succès ; ne plus suivre, retirer, regarder : impact léger ; œil, couleur, pilule,
    /// joueur : sélection ; révéler : impact moyen ; rafraîchir en échec : avertissement.
    var style: Style {
        switch self {
        case .follow, .pin, .refreshSucceeded: return .success
        case .unfollow, .unpin, .watch: return .lightImpact
        case .spoilerToggle, .colorPicked, .gamePicked, .playerPicked: return .selection
```

Dans `Tests/FailleTests/MotionTests.swift` (`eachActionHasItsHaptic`) :

Remplacer :

```swift
        #expect(Haptic.gamePicked.style == .selection)
```

par :

```swift
        #expect(Haptic.gamePicked.style == .selection)
        #expect(Haptic.watch.style == .lightImpact)
        #expect(Haptic.playerPicked.style == .selection)
```

- [ ] **Step 5: Écrire les boutons**

Créer `App/Watch/WatchButtons.swift` :

```swift
import LoLKit
import SwiftUI

/// Bouton « Regarder » (spec fonctionnalités §1) : ouvre le stream préféré par `openURL` (l'app Twitch ou YouTube prend le
/// relais si elle est installée) ; appui long : menu des autres streams (langue · plateforme). N'existe que pour un match
/// en direct non masqué (`WatchLinks.live`). Carte : pastille compacte ; Détail : bouton en verre pleine largeur.
struct WatchButton: View {
    let live: WatchLinks.Live
    var compact = false
    /// Retour haptique (impact léger), joué par la vue qui reste affichée (carte ou Détail).
    var onHaptic: (Haptic) -> Void = { _ in }
    @Environment(\.openURL) private var openURL

    var body: some View {
        if live.others.isEmpty {
            Button(action: watch) { label }
                .buttonStyle(.pressable)
                .accessibilityLabel(accessibilityText)
        } else {
            Menu {
                ForEach(live.others, id: \.url) { link in
                    Button(WatchLinks.label(link)) { open(link.url) }
                }
            } label: {
                label
            } primaryAction: {
                watch()
            }
            .menuStyle(.button)
            .buttonStyle(.pressable)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Appui long : autres langues")
        }
    }

    private var accessibilityText: String {
        "Regarder · \(WatchLinks.label(live.preferred))"
    }

    @ViewBuilder private var label: some View {
        if compact {
            HStack(spacing: 5) {
                IconView(icon: .play, size: 12)
                Text("Regarder")
            }
            .font(Typo.chip)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.chipFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
            // Zone tactile de 44 pt de haut, la pastille reste petite.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 6) {
                IconView(icon: .play, size: 15)
                Text("Regarder")
                Text("· \(WatchLinks.label(live.preferred))")
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .font(Typo.bodyMedium)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .glassCard(radius: Radius.inner, padding: 4)
        }
    }

    private func watch() {
        open(live.preferred.url)
    }

    private func open(_ url: URL) {
        onHaptic(.watch)
        openURL(url)
    }
}

/// « Revoir la game N » (spec fonctionnalités §1) : la rediffusion YouTube de la game choisie, dans la langue préférée,
/// au début de la game. N'existe que pour une game jouée d'un match non masqué (`WatchLinks.replay`).
struct ReplayButton: View {
    let gameNumber: Int
    let link: StreamLink
    var onHaptic: (Haptic) -> Void = { _ in }
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            onHaptic(.watch)
            openURL(link.url)
        } label: {
            HStack(spacing: 6) {
                IconView(icon: .play, size: 15)
                Text("Revoir la game \(gameNumber)")
                Text("· \(WatchLinks.label(link))")
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .font(Typo.bodyMedium)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .glassCard(radius: Radius.inner, padding: 4)
        }
        .buttonStyle(.pressable)
    }
}
```

- [ ] **Step 6: Écrire l'aperçu**

Créer `Tests/FailleTests/WatchSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// « Regarder » et « Revoir » (spec fonctionnalités §1) : pastille de la carte, bouton du Détail, rediffusions.
    @Test func watchBoard() async throws {
        let streams = [
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "riotgames", locale: "en-US"),
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR"),
        ]
        let live = try #require(WatchLinks.live(streams, inProgress: true, masked: false))
        let alone = try #require(WatchLinks.live([streams[1]], inProgress: true, masked: false))
        let vod = [Vod(provider: "youtube", parameter: "abc123", locale: "en-US", startMillis: 95_000)]
        let replay = try #require(WatchLinks.replay(GameRef(number: 2, id: "g2", state: .completed, teams: nil, vods: vod),
                                                    masked: false))
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Regarder", subtitle: "Stream en direct · rediffusions")
                SectionLabel(text: "Carte en direct")
                VStack(alignment: .leading, spacing: 8) {
                    Text("KC 1 – 0 C9").font(Typo.headline)
                    WatchButton(live: live, compact: true)
                }
                .foregroundStyle(Palette.text)
                .glassCard(tint: Palette.team("#5B8CFF"))
                SectionLabel(text: "Détail en direct")
                WatchButton(live: live)
                WatchButton(live: alone)
                SectionLabel(text: "Détail terminé")
                ReplayButton(gameNumber: 2, link: replay)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "16-regarder")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 7: Vérifier le périmètre, committer, pousser**

```bash
git status --short
```

Expected : seulement les fichiers de la ligne T1 de la matrice (`?? App/Watch/`, `?? Resources/Assets.xcassets/icon-play.imageset/`, `?? Tests/FailleTests/WatchTests.swift`, `?? Tests/FailleTests/WatchSnapshotTests.swift`, ` M Shared/DA/Icon.swift`, ` M App/DA/Haptics.swift`, ` M Tests/FailleTests/ApercuTests.swift`, ` M Tests/FailleTests/MotionTests.swift`).

```bash
git add App/Watch Resources/Assets.xcassets/icon-play.imageset Shared/DA/Icon.swift App/DA/Haptics.swift \
  Tests/FailleTests/WatchTests.swift Tests/FailleTests/WatchSnapshotTests.swift Tests/FailleTests/ApercuTests.swift \
  Tests/FailleTests/MotionTests.swift
git commit -m "feat(app): Regarder et Revoir — stream préféré (fr-FR, en-US), menu des autres langues, rediffusions, jamais pour un match masqué" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t1-regarder
```

- [ ] **Step 8: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
```

Expected : jobs `build` et `apercus` verts ; suites `WatchTests` (4 tests) et `ApercuTests` vertes (dont `iconsAreInTheCatalog` à 23 icônes, `eachActionHasItsHaptic`) ; `16-regarder.png` dans l'artefact `Faille-apercus` (pastille « Regarder », deux boutons pleine largeur dont « Regarder · Français · Twitch », « Revoir la game 2 · Anglais · YouTube »), `00-da.png` montre l'icône `play`. Échec : `gh run view "$RUN" --log-failed`, corriger, commit, push, relancer cette étape. Si `ButtonMenuStyle` n'applique pas `PressableStyle` au bouton à menu (rien ne casse : seule la pâleur d'appui diffère), le laisser tel quel et le noter pour la checklist.


### Task 2: Notifications de début de match (réglages, centre iOS, section des Réglages, toucher → Détail)

**Branche :** `fonc/appli-t2-notifications` · **Vague :** A · **Dépendances :** aucune.

**Files:**
- Modify: `LoLKit/Sources/LoLKit/Storage/AppSettings.swift` (fichier entier) — **T2 est la seule tâche qui touche ce fichier.**
- Test (LoLKit) : `LoLKit/Tests/LoLKitTests/ReminderSettingsTests.swift`
- Create: `App/Reminders/ReminderCenter.swift`, `App/Reminders/SystemReminderCenter.swift`, `App/Reminders/NotificationRouter.swift`, `App/Reminders/MatchRemindersSection.swift`, `App/Store/AppStore+Reminders.swift`
- Test: `Tests/FailleTests/RemindersTests.swift`, `Tests/FailleTests/RemindersSnapshotTests.swift` (aperçu `17-notifications.png`)

**Interfaces:**
- Consumes (à `origin/main`) : LoLKit `MatchReminders.plan(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>, now: Date, lead: TimeInterval) -> [MatchReminder]`, `MatchReminders.identifier(matchId: String) -> String` (« match-start-<id> »), `MatchReminders.leadOptions: [TimeInterval]` (300, 900, 1800), `MatchReminders.defaultLead` (900) ; `struct MatchReminder: Sendable, Equatable { id, matchId: String; fireDate: Date; title, subtitle: String }` + `init(id:matchId:fireDate:title:subtitle:)` ; `AppSettings(liveActivityMode:revealedMatchIds:)` et son décodage tolérant ; appli `AppStore.settings`, `.schedule`, `.follows` (`private(set) var`, lisibles d'une extension), `AppStore.followsUnreadable` (`@ObservationIgnored private(set) var`), `AppStore(transport:files:)`, `FileStore.save(_:to:)` (`.follows`, `.settings`, `.schedule`), `Cached(value:fetchedAt:)`, `SchedulePage(leagueIds:events:)`, `SampleData.worlds` ; tests `ScriptedTransport(mode:)`, `TemporaryFiles.store()`.
- Produces :
  - LoLKit `AppSettings.matchRemindersEnabled: Bool` (défaut `false`), `AppSettings.matchReminderLead: TimeInterval` (défaut `MatchReminders.defaultLead`, toujours une valeur de `leadOptions`) ; `init(liveActivityMode: = .automatic, revealedMatchIds: = [], matchRemindersEnabled: Bool = false, matchReminderLead: TimeInterval = MatchReminders.defaultLead)`.
  - `enum ReminderAuthorization: Sendable, Equatable { case notDetermined, denied, authorized }` ; `protocol ReminderCenter: Sendable { authorization() async -> ReminderAuthorization; requestAuthorization() async -> Bool; pendingIdentifiers() async -> [String]; remove(identifiers: [String]) async; add(_ reminder: MatchReminder) async throws }` ; `struct InertReminderCenter: ReminderCenter` ; `struct SystemReminderCenter: ReminderCenter` + `static func request(for: MatchReminder, calendar: Calendar = .current) -> UNNotificationRequest`.
  - `enum ReminderPayload` : `matchIdKey`, `userInfo(matchId:) -> [String: String]`, `matchId(from: [AnyHashable: Any]) -> String?` ; `enum ReminderSync` : `identifierPrefix`, `static func apply(_ reminders: [MatchReminder], enabled: Bool, center: any ReminderCenter) async`.
  - `@MainActor @Observable final class NotificationRouter` : `private(set) var pendingMatchId: String?`, `func open(matchId: String)`, `func consume() -> String?`.
  - `final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable` : `init(router: NotificationRouter)`.
  - `extension AppStore` : `func plannedReminders(now: Date = Date()) -> [MatchReminder]`, `var reminderSignature: ReminderSignature`, `func syncReminders(center: any ReminderCenter, now: Date = Date()) async` ; `struct ReminderSignature: Equatable, Sendable { let enabled: Bool; let reminders: [MatchReminder] }`.
  - `struct MatchRemindersSection: View` : `init(enabled: Bool, lead: TimeInterval, center: any ReminderCenter, denied: Bool = false, setEnabled: @escaping (Bool) -> Void, setLead: @escaping (TimeInterval) -> Void)`, `static func leadLabel(_ lead: TimeInterval) -> String` (« 15 min »).
  - Branchés par T7 : `AppStore.reminderCenter`, `setMatchReminders(enabled:)`, `setMatchReminderLead(_:)`, la section dans `SettingsView`, le délégué et la reprogrammation dans `FailleApp`, le routeur dans `RootView`.

- [ ] **Step 1: Écrire le test LoLKit qui échoue**

Créer `LoLKit/Tests/LoLKitTests/ReminderSettingsTests.swift` :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli lit et écrit ces réglages avec la seule API publique.
import LoLKit

/// Réglages des notifications de début de match (spec fonctionnalités §2) : désactivées par défaut, délai de 15 min,
/// décodage tolérant (un `settings.json` d'avant ce lot, ou un délai inconnu, garde les valeurs par défaut).
struct ReminderSettingsTests {
    @Test func remindersAreOffByDefaultWithAFifteenMinuteLead() {
        let settings = AppSettings()
        #expect(settings.matchRemindersEnabled == false)
        #expect(settings.matchReminderLead == 15 * 60)
        #expect(settings.matchReminderLead == MatchReminders.defaultLead)
    }

    @Test func reminderSettingsRoundTrip() throws {
        let custom = AppSettings(liveActivityMode: .manual, revealedMatchIds: ["m1"], matchRemindersEnabled: true,
                                 matchReminderLead: 5 * 60)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
        #expect(decoded.matchRemindersEnabled)
        #expect(decoded.matchReminderLead == 300)
    }

    @Test func settingsFromBeforeThisLotKeepTheDefaults() throws {
        let old = #"{"liveActivityMode":"manual","revealedMatchIds":["m1"]}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.liveActivityMode == .manual)
        #expect(decoded.revealedMatchIds == ["m1"])
        #expect(decoded.matchRemindersEnabled == false)
        #expect(decoded.matchReminderLead == MatchReminders.defaultLead)
    }

    @Test func unknownLeadOrUnreadableSwitchFallsBackToTheDefaults() throws {
        let odd = #"{"matchRemindersEnabled":"oui","matchReminderLead":600}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(odd.utf8))
        #expect(decoded.matchRemindersEnabled == false)
        #expect(decoded.matchReminderLead == MatchReminders.defaultLead)
        #expect(AppSettings(matchReminderLead: 42).matchReminderLead == MatchReminders.defaultLead)
        var settings = AppSettings(matchReminderLead: 30 * 60)
        #expect(settings.matchReminderLead == 1800)
        settings.matchReminderLead = 7
        #expect(settings.matchReminderLead == MatchReminders.defaultLead)
    }
}
```

- [ ] **Step 2: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter ReminderSettingsTests`
Expected : échec de compilation — `extra argument 'matchRemindersEnabled' in call` / `value of type 'AppSettings' has no member 'matchRemindersEnabled'`.

- [ ] **Step 3: Ajouter les réglages à `AppSettings`**

Remplacer tout `LoLKit/Sources/LoLKit/Storage/AppSettings.swift` par :

```swift
import Foundation

/// Réglages de l'appli, enregistrés dans le groupe d'apps (lus aussi par les widgets et la Live Activity aux étapes 3-4).
public struct AppSettings: Codable, Sendable, Equatable {
    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    public var liveActivityMode: LiveActivityMode
    /// Matchs que l'utilisateur a choisi de révéler malgré l'anti-spoiler (spec §8).
    public var revealedMatchIds: Set<String>
    /// Notifications de début de match (spec fonctionnalités §2) : désactivées par défaut.
    public var matchRemindersEnabled: Bool
    /// Délai de ces notifications avant le début du match, en secondes : une valeur de `MatchReminders.leadOptions`
    /// (5, 15 ou 30 min) ; toute autre valeur devient `MatchReminders.defaultLead` (15 min).
    public var matchReminderLead: TimeInterval {
        didSet {
            if !MatchReminders.leadOptions.contains(matchReminderLead) {
                matchReminderLead = MatchReminders.defaultLead
            }
        }
    }

    public init(liveActivityMode: LiveActivityMode = .automatic, revealedMatchIds: Set<String> = [],
                matchRemindersEnabled: Bool = false, matchReminderLead: TimeInterval = MatchReminders.defaultLead) {
        self.liveActivityMode = liveActivityMode
        self.revealedMatchIds = revealedMatchIds
        self.matchRemindersEnabled = matchRemindersEnabled
        self.matchReminderLead = Self.lead(matchReminderLead)
    }

    private enum CodingKeys: String, CodingKey {
        case liveActivityMode, revealedMatchIds, matchRemindersEnabled, matchReminderLead
    }

    /// Décodage tolérant : champ absent ou valeur inconnue (version plus récente, ou plus ancienne sans ce champ) → valeur
    /// par défaut.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveActivityMode = (try? container.decodeIfPresent(LiveActivityMode.self, forKey: .liveActivityMode)) ?? .automatic
        revealedMatchIds = (try? container.decodeIfPresent(Set<String>.self, forKey: .revealedMatchIds)) ?? []
        matchRemindersEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .matchRemindersEnabled)) ?? false
        matchReminderLead = Self.lead((try? container.decodeIfPresent(TimeInterval.self, forKey: .matchReminderLead))
            ?? MatchReminders.defaultLead)
    }

    /// Délai proposé dans les réglages, sinon le délai par défaut.
    private static func lead(_ value: TimeInterval) -> TimeInterval {
        MatchReminders.leadOptions.contains(value) ? value : MatchReminders.defaultLead
    }
}
```

- [ ] **Step 4: Lancer les tests LoLKit**

Run : `bash scripts/lolkit.sh test --filter ReminderSettingsTests` puis `bash scripts/lolkit.sh test`
Expected : `Test run with 4 tests in 1 suite passed`, puis `Test run with 320 tests in 37 suites passed` (316 / 36 à `origin/main`), aucun avertissement. Les widgets et la Live Activity relisent `settings.json` sans changement (champs nouveaux optionnels au décodage).

- [ ] **Step 5: Committer la partie LoLKit**

```bash
git add LoLKit/Sources/LoLKit/Storage/AppSettings.swift LoLKit/Tests/LoLKitTests/ReminderSettingsTests.swift
git commit -m "feat(lolkit): réglages des notifications de début de match (désactivées par défaut, délai 5/15/30 min, décodage tolérant)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t2-notifications
```

- [ ] **Step 6: Écrire les tests de l'appli**

Créer `Tests/FailleTests/RemindersTests.swift` (faux centre, programmation, charge utile, routeur ; puis le store et iOS) :

```swift
import Foundation
import LoLKit
import Testing
import UserNotifications
@testable import Faille

/// Faux centre de notifications : garde ce qui est programmé ; l'autorisation et la réponse à la demande se règlent.
actor FakeReminderCenter: ReminderCenter {
    private(set) var pending: [String: MatchReminder] = [:]
    /// Notifications d'une autre origine : elles ne doivent jamais être retirées.
    private(set) var foreign: Set<String>
    private(set) var status: ReminderAuthorization
    private let grants: Bool
    private(set) var authorizationRequests = 0

    init(status: ReminderAuthorization = .authorized, grants: Bool = true, foreign: Set<String> = []) {
        self.status = status
        self.grants = grants
        self.foreign = foreign
    }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) + Array(foreign) }

    func remove(identifiers: [String]) async {
        for id in identifiers {
            pending[id] = nil
            foreign.remove(id)
        }
    }

    func add(_ reminder: MatchReminder) async throws {
        pending[reminder.id] = reminder
    }
}

/// Programmation des notifications de début de match (spec fonctionnalités §2) : remplacement de celles de Faille seules,
/// rien sans réglage ni autorisation, et l'id du match transporté pour ouvrir son Détail.
@MainActor
struct RemindersTests {
    private static func reminder(_ matchId: String, in minutes: Double) -> MatchReminder {
        MatchReminder(id: MatchReminders.identifier(matchId: matchId), matchId: matchId,
                      fireDate: Date().addingTimeInterval(minutes * 60), title: "KC vs G2 dans 15 min",
                      subtitle: "Mondial · Play-in · Bo5")
    }

    @Test func applyReplacesFailleRemindersOnly() async {
        let center = FakeReminderCenter(foreign: ["autre-appli"])
        await ReminderSync.apply([Self.reminder("old", in: 30)], enabled: true, center: center)
        await ReminderSync.apply([Self.reminder("m1", in: 60), Self.reminder("m2", in: 90)], enabled: true, center: center)
        #expect(Set(await center.pending.keys) == ["match-start-m1", "match-start-m2"])
        #expect(await center.foreign == ["autre-appli"])
    }

    @Test func switchedOffRemovesEveryFailleReminder() async {
        let center = FakeReminderCenter(foreign: ["autre-appli"])
        await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: true, center: center)
        await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: false, center: center)
        #expect(await center.pending.isEmpty)
        #expect(await center.foreign == ["autre-appli"])
    }

    /// Sans autorisation d'iOS, rien n'est programmé (et l'autorisation n'est jamais demandée ici : seulement par le
    /// réglage, quand on l'active).
    @Test func withoutAuthorizationNothingIsScheduled() async {
        for status in [ReminderAuthorization.denied, .notDetermined] {
            let center = FakeReminderCenter(status: status)
            await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: true, center: center)
            #expect(await center.pending.isEmpty)
            #expect(await center.authorizationRequests == 0)
        }
    }

    @Test func payloadCarriesTheMatchToOpen() {
        #expect(ReminderPayload.matchId(from: ReminderPayload.userInfo(matchId: "m1")) == "m1")
        #expect(ReminderPayload.matchId(from: ["matchId": 3]) == nil)
        #expect(ReminderPayload.matchId(from: ["matchId": ""]) == nil)
        #expect(ReminderPayload.matchId(from: [:]) == nil)
    }

    @Test func routerHandsTheMatchOverOnce() {
        let router = NotificationRouter()
        #expect(router.consume() == nil)
        router.open(matchId: "m1")
        #expect(router.pendingMatchId == "m1")
        #expect(router.consume() == "m1")
        #expect(router.consume() == nil)
    }
}

/// Le store et iOS : plan tiré du calendrier en cache et des réglages, requête iOS (texte, déclenchement, match à ouvrir),
/// délégué réellement branché sur les deux rappels d'iOS.
@MainActor
@Suite(.serialized)
struct RemindersStoreTests {
    /// Store dont le disque contient : KC suivie, réglages donnés, et un calendrier avec KC – G2 dans 3 h.
    private static func store(settings: AppSettings) -> (AppStore, Date) {
        let files = TemporaryFiles.store()
        let start = Date().addingTimeInterval(3 * 3600)
        files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")]), to: .follows)
        files.save(settings, to: .settings)
        let teams = [
            MatchTeam(id: nil, name: "Karmine Corp", code: "KC", image: nil, result: nil),
            MatchTeam(id: nil, name: "G2 Esports", code: "G2", image: nil, result: nil),
        ]
        let event = MatchEvent(startTime: start, state: .unstarted, type: "match", blockName: "Play-in",
                               league: SampleData.worlds,
                               match: MatchInfo(id: "m1", teams: teams, strategy: Strategy(type: "bestOf", count: 5),
                                                games: nil),
                               streams: nil)
        files.save(Cached(value: SchedulePage(leagueIds: [], events: [event]), fetchedAt: Date()), to: .schedule)
        return (AppStore(transport: ScriptedTransport(mode: .failing), files: files), start)
    }

    @Test func storePlansFromTheCachedScheduleAndSettings() {
        let (store, start) = Self.store(settings: AppSettings(matchRemindersEnabled: true, matchReminderLead: 30 * 60))
        let planned = store.plannedReminders()
        #expect(planned.count == 1)
        #expect(planned.first?.title == "KC vs G2 dans 30 min")
        #expect(planned.first?.subtitle == "Mondial · Play-in · Bo5")
        #expect(planned.first?.fireDate == start.addingTimeInterval(-1800))
        #expect(store.reminderSignature.enabled)

        let (off, _) = Self.store(settings: AppSettings())
        #expect(off.plannedReminders().isEmpty)
        #expect(off.reminderSignature == ReminderSignature(enabled: false, reminders: []))
    }

    @Test func storeSyncSchedulesThroughTheCenter() async {
        let (store, _) = Self.store(settings: AppSettings(matchRemindersEnabled: true))
        let center = FakeReminderCenter()
        await store.syncReminders(center: center)
        #expect(Set(await center.pending.keys) == ["match-start-m1"])
    }

    @Test func iosRequestCarriesTextTimeAndMatch() throws {
        let fire = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60 + 7_200)
        let reminder = MatchReminder(id: "match-start-m1", matchId: "m1", fireDate: fire, title: "KC vs G2 dans 15 min",
                                     subtitle: "Mondial · Play-in · Bo5")
        let request = SystemReminderCenter.request(for: reminder)
        #expect(request.identifier == "match-start-m1")
        #expect(request.content.title == "KC vs G2 dans 15 min")
        #expect(request.content.subtitle == "Mondial · Play-in · Bo5")
        #expect(ReminderPayload.matchId(from: request.content.userInfo) == "m1")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats == false)
        #expect(trigger.nextTriggerDate() == fire)
    }

    /// Le délégué répond vraiment aux deux rappels d'iOS : une signature qui ne correspondrait pas au protocole serait
    /// ignorée sans erreur (méthode optionnelle d'Objective-C), et toucher une notification n'ouvrirait rien.
    @Test func delegateAnswersBothCallbacks() {
        let delegate = ReminderNotificationDelegate(router: NotificationRouter())
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))))
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))))
    }
}
```

- [ ] **Step 7: Écrire le centre, la programmation et le routeur**

Créer `App/Reminders/ReminderCenter.swift` :

```swift
import Foundation
import LoLKit

/// Autorisation des notifications, telle que l'appli la lit.
enum ReminderAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// Centre des notifications locales (spec fonctionnalités §2) : `SystemReminderCenter` (`UNUserNotificationCenter`) dans
/// l'appli, `InertReminderCenter` dans les aperçus et les tests hébergés, un faux dans les tests unitaires.
protocol ReminderCenter: Sendable {
    func authorization() async -> ReminderAuthorization
    /// Demande l'autorisation à iOS (alertes et sons) ; vrai si elle est accordée.
    func requestAuthorization() async -> Bool
    /// Identifiants des notifications en attente, de Faille ou non.
    func pendingIdentifiers() async -> [String]
    func remove(identifiers: [String]) async
    /// Programme une notification ; un identifiant déjà programmé est remplacé.
    func add(_ reminder: MatchReminder) async throws
}

/// Aperçus et tests hébergés : rien n'est demandé à iOS ni programmé.
struct InertReminderCenter: ReminderCenter {
    func authorization() async -> ReminderAuthorization { .notDetermined }
    func requestAuthorization() async -> Bool { false }
    func pendingIdentifiers() async -> [String] { [] }
    func remove(identifiers: [String]) async {}
    func add(_ reminder: MatchReminder) async throws {}
}

/// Ce qu'une notification de Faille transporte : l'id du match à ouvrir quand on la touche (spec fonctionnalités §2).
enum ReminderPayload {
    static let matchIdKey = "matchId"

    static func userInfo(matchId: String) -> [String: String] {
        [matchIdKey: matchId]
    }

    /// Id du match d'une notification touchée ; nil si elle ne vient pas de Faille.
    static func matchId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let id = userInfo[matchIdKey] as? String, !id.isEmpty else { return nil }
        return id
    }
}

/// Programmation des notifications de début de match : celles de Faille (préfixe `match-start-`) sont remplacées par le
/// plan de LoLKit (`MatchReminders.plan`) ; celles d'autres origines ne sont jamais touchées.
enum ReminderSync {
    static let identifierPrefix = MatchReminders.identifier(matchId: "")

    /// - Parameters:
    ///   - reminders: plan de LoLKit (au plus 60, les plus proches d'abord).
    ///   - enabled: réglage « Notifications de début de match ».
    static func apply(_ reminders: [MatchReminder], enabled: Bool, center: any ReminderCenter) async {
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(identifierPrefix) }
        var allowed = false
        if enabled {
            allowed = await center.authorization() == .authorized
        }
        let wanted = allowed ? reminders : []
        let wantedIds = Set(wanted.map(\.id))
        let stale = ours.filter { !wantedIds.contains($0) }
        if !stale.isEmpty {
            await center.remove(identifiers: stale)
        }
        for reminder in wanted {
            try? await center.add(reminder)
        }
    }
}
```

Créer `App/Reminders/NotificationRouter.swift` :

```swift
import Foundation
import Observation

/// Match à ouvrir après le toucher d'une notification de début de match (spec fonctionnalités §2) : le délégué des
/// notifications le dépose, `RootView` passe sur l'onglet Matchs, pousse le Détail du match, puis le consomme.
@MainActor
@Observable
final class NotificationRouter {
    private(set) var pendingMatchId: String?

    func open(matchId: String) {
        pendingMatchId = matchId
    }

    /// Le match à ouvrir, une seule fois.
    func consume() -> String? {
        defer { pendingMatchId = nil }
        return pendingMatchId
    }
}
```

Créer `App/Reminders/SystemReminderCenter.swift` (si la CI signale que le délégué ne correspond plus au protocole — le test `delegateAnswersBothCallbacks` échoue, ou un avertissement « nearly matches optional requirement » apparaît —, remplacer les deux méthodes par leurs variantes `async` : `func userNotificationCenter(_:didReceive:) async` qui lit l'id puis `await target.open(matchId:)` sur le fil principal, et `func userNotificationCenter(_:willPresent:) async -> UNNotificationPresentationOptions` qui rend `[.banner, .list, .sound]` ; garder le test) :

```swift
import Foundation
import LoLKit
import UserNotifications

/// Notifications locales d'iOS (`UNUserNotificationCenter`, spec fonctionnalités §2) : aucune n'est envoyée par un serveur.
/// Le centre est relu à chaque appel : rien de non `Sendable` n'est gardé.
struct SystemReminderCenter: ReminderCenter {
    func authorization() async -> ReminderAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func remove(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ reminder: MatchReminder) async throws {
        try await UNUserNotificationCenter.current().add(Self.request(for: reminder))
    }

    /// Requête iOS d'une notification de début de match : titre « KC vs C9 dans 15 min », sous-titre
    /// « Mondial · Play-in · Bo5 » (LoLKit : jamais de score), son par défaut, id du match pour ouvrir son Détail au
    /// toucher ; déclenchée à l'heure dite (date du calendrier, pas un compte à rebours).
    static func request(for reminder: MatchReminder, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = reminder.subtitle
        content.sound = .default
        content.threadIdentifier = "match-start"
        content.userInfo = ReminderPayload.userInfo(matchId: reminder.matchId)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}

/// Délégué des notifications (spec fonctionnalités §2) : toucher une notification de Faille ouvre le Détail du match
/// (par `NotificationRouter`) ; au premier plan, elle s'affiche quand même. Posé au lancement par `FailleApp`, avant la fin
/// du démarrage : un toucher qui lance l'appli le trouve déjà là.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let matchId = ReminderPayload.matchId(from: response.notification.request.content.userInfo)
        let target = router
        Task { @MainActor in
            if let matchId {
                target.open(matchId: matchId)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
```

- [ ] **Step 8: Écrire l'extension du store**

Créer `App/Store/AppStore+Reminders.swift` :

```swift
import Foundation
import LoLKit

/// Ce qui oblige à reprogrammer les notifications : le réglage et le plan de LoLKit. Il change quand le calendrier, les
/// équipes suivies, les révélations ou les réglages changent (spec fonctionnalités §2), et quand une notification passe
/// son heure. Sert d'`id` à la tâche de la scène qui reprogramme (`FailleApp`).
struct ReminderSignature: Equatable, Sendable {
    let enabled: Bool
    let reminders: [MatchReminder]
}

// MARK: - Notifications de début de match (fonctionnalités, Task 2)

extension AppStore {
    /// Notifications à programmer maintenant ; aucune si le réglage est coupé. La sélection (le prochain match de chaque
    /// équipe suivie que `Presenter.nextLine` montre, 60 au plus, jamais un match caché par l'anti-spoiler) et les textes
    /// (jamais de score) viennent de LoLKit (`MatchReminders.plan`).
    func plannedReminders(now: Date = Date()) -> [MatchReminder] {
        guard settings.matchRemindersEnabled else { return [] }
        return MatchReminders.plan(schedule: schedule, follows: follows, revealed: settings.revealedMatchIds, now: now,
                                   lead: settings.matchReminderLead)
    }

    var reminderSignature: ReminderSignature {
        ReminderSignature(enabled: settings.matchRemindersEnabled, reminders: plannedReminders())
    }

    /// Reprogramme les notifications de Faille (celles des autres applis ne sont jamais touchées). Rien tant que
    /// `follows.json` est illisible : la liste des équipes suivies serait vide par défaut, et on supprimerait des
    /// notifications voulues (même règle que pour les Live Activities).
    func syncReminders(center: any ReminderCenter, now: Date = Date()) async {
        guard !followsUnreadable else { return }
        await ReminderSync.apply(plannedReminders(now: now), enabled: settings.matchRemindersEnabled, center: center)
    }
}
```

- [ ] **Step 9: Écrire la section des Réglages et son aperçu**

Créer `App/Reminders/MatchRemindersSection.swift` :

```swift
import LoLKit
import SwiftUI

/// Réglage « Notifications de début de match » (spec fonctionnalités §2) : interrupteur (désactivé par défaut ; l'activer
/// demande l'autorisation d'iOS) et délai de 5, 15 ou 30 min. Une seule source de vérité : les valeurs viennent du store
/// et y retournent par `setEnabled` / `setLead`, rien n'est recopié dans la vue. Si iOS refuse, l'interrupteur reste coupé
/// et la section dit où l'autoriser.
struct MatchRemindersSection: View {
    let enabled: Bool
    let lead: TimeInterval
    let center: any ReminderCenter
    let setEnabled: (Bool) -> Void
    let setLead: (TimeInterval) -> Void
    @State private var denied: Bool

    /// - Parameter denied: état initial « refusé par iOS » (aperçus) ; l'écran le vérifie lui-même à l'affichage.
    init(enabled: Bool, lead: TimeInterval, center: any ReminderCenter, denied: Bool = false,
         setEnabled: @escaping (Bool) -> Void, setLead: @escaping (TimeInterval) -> Void) {
        self.enabled = enabled
        self.lead = lead
        self.center = center
        self.setEnabled = setEnabled
        self.setLead = setLead
        _denied = State(initialValue: denied)
    }

    /// « 15 min »
    static func leadLabel(_ lead: TimeInterval) -> String {
        "\(Int((lead / 60).rounded())) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { enabled }, set: { on in Task { await toggle(on) } })) {
                Text("Début de match")
                    .font(Typo.body)
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.accent)
            if enabled {
                Picker("Délai", selection: Binding(get: { lead }, set: { setLead($0) })) {
                    ForEach(MatchReminders.leadOptions, id: \.self) { option in
                        Text(Self.leadLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(explanation)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
            if denied {
                Text("Notifications refusées par iOS : Réglages › Faille › Notifications.")
                    .font(Typo.secondaryMedium)
                    .foregroundStyle(Palette.accent)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .task {
            if enabled, await center.authorization() == .denied {
                denied = true
            }
        }
    }

    private var explanation: String {
        enabled
            ? "« KC vs C9 dans \(Self.leadLabel(lead)) » avant le prochain match de chaque équipe suivie. Jamais pour un match que l'anti-spoiler cache, jamais de score."
            : "Désactivées : aucune notification. Les activer demande l'autorisation d'iOS."
    }

    /// Activer : autorisation d'iOS d'abord (demandée la première fois) ; refusée, l'interrupteur reste coupé.
    private func toggle(_ on: Bool) async {
        guard on else {
            denied = false
            setEnabled(false)
            return
        }
        var granted = false
        switch await center.authorization() {
        case .authorized: granted = true
        case .denied: granted = false
        case .notDetermined: granted = await center.requestAuthorization()
        }
        denied = !granted
        setEnabled(granted)
    }
}
```

Créer `Tests/FailleTests/RemindersSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Réglage « Notifications de début de match » (spec fonctionnalités §2) : coupé (défaut), activé à 15 min, refusé
    /// par iOS.
    @Test func remindersBoard() async throws {
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Notifications", subtitle: "Coupées · 15 min · refusées par iOS")
                SectionLabel(text: "Notifications")
                MatchRemindersSection(enabled: false, lead: MatchReminders.defaultLead, center: InertReminderCenter(),
                                      setEnabled: { _ in }, setLead: { _ in })
                MatchRemindersSection(enabled: true, lead: MatchReminders.defaultLead, center: InertReminderCenter(),
                                      setEnabled: { _ in }, setLead: { _ in })
                MatchRemindersSection(enabled: false, lead: MatchReminders.defaultLead, center: InertReminderCenter(),
                                      denied: true, setEnabled: { _ in }, setLead: { _ in })
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "17-notifications")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 10: Vérifier le périmètre, committer, pousser**

```bash
git status --short
```

Expected : seulement `?? App/Reminders/`, `?? App/Store/AppStore+Reminders.swift`, `?? Tests/FailleTests/RemindersTests.swift`, `?? Tests/FailleTests/RemindersSnapshotTests.swift` (la partie LoLKit est déjà commitée).

```bash
git add App/Reminders App/Store/AppStore+Reminders.swift Tests/FailleTests/RemindersTests.swift \
  Tests/FailleTests/RemindersSnapshotTests.swift
git commit -m "feat(app): notifications de début de match — centre iOS, programmation depuis le plan de LoLKit, section des réglages, toucher qui ouvre le Détail" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 11: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
LK=$(gh run list --workflow LoLKit --branch fonc/appli-t2-notifications --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$LK"
gh run watch --exit-status "$LK"
```

Expected : workflow `iOS` vert (suites `RemindersTests` 5 tests et `RemindersStoreTests` 4 tests, aperçu `17-notifications.png` : section coupée, activée avec le choix 5 / 15 / 30 min sur 15, et « Notifications refusées par iOS… » en accent) ; workflow `LoLKit` vert (Linux et macOS). Échec : `gh run view <id> --log-failed`, corriger, commit, push, relancer.


### Task 3: Socle Data Dragon (cache disque, versions, catalogues, images, icône)

**Branche :** `fonc/appli-t3-data-dragon` · **Vague :** A · **Dépendances :** aucune (T4, T5 et T6 en dépendent).

**Files:**
- Create: `App/Cache/DiskCache.swift`, `App/DataDragon/DataDragon+Cache.swift`, `App/DataDragon/DataDragonStore.swift`, `App/DataDragon/DDragonIcon.swift`
- Create (support de test) : `Tests/FailleTests/Support/TestImages.swift`
- Test: `Tests/FailleTests/DiskCacheTests.swift`, `Tests/FailleTests/DataDragonStoreTests.swift`, `Tests/FailleTests/DataDragonSnapshotTests.swift` (aperçu `18-data-dragon.png`)

**Interfaces:**
- Consumes (à `origin/main`) : LoLKit `DataDragon.versionsURL`, `DataDragon.versionsMaxAge` (24 h), `DataDragon.version(forPatch: String?, versions: [String]) -> String?`, `DataDragon.decodeVersions(_ data: Data) throws -> [String]`, `DataDragon.championImage(version:championId:)`, `.itemImage(version:itemId:)`, `.spellImage(version:file:)`, `.summonerSpellImage(version:spellId:)`, `.runeIcon(_:)`, `.itemsURL(version:)`, `.runesURL(version:)`, `.summonerSpellsURL(version:)`, `.championURL(version:championId:)` (toutes `-> URL`, sur `https://ddragon.leagueoflegends.com/cdn/…`) ; `ItemCatalog(json:) throws`, `RuneCatalog(json:) throws`, `SummonerCatalog(json:) throws`, `ChampionSpells(json:) throws` (+ `.item(_:)`, `.rune(_:)`, `.spell(_:)`, `.spell(forAbility:)`, `.passive`) ; `Cached<Value>(value:fetchedAt:)`, `.age(now:)` ; `HTTPTransport.get(_:headers:) async throws -> HTTPResponse` ; appli `Palette.chipFill`, `Palette.glassBorder`, `Palette.secondary`, `Sora.font(_:_:)`, `LogoImages` (même schéma : décodage détaché, `preparingForDisplay()`) ; tests `ScriptedTransport(mode:extra:)`, `.requests`, `TemporaryFiles.directory()`.
- Produces :
  - `struct DiskCache: Sendable` : `init(root: URL)` (crée le dossier, l'exclut de la sauvegarde), `let root`, `static func safePath(_:) -> String?`, `func url(_:) -> URL?`, `func data(_:) -> Data?`, `func write(_ data: Data, to path: String)`, `func load<T: Decodable>(_ type: T.Type, from path: String) -> T?`, `func save<T: Encodable>(_ value: T, to path: String)`.
  - `extension DataDragon` : `static let versionsCachePath = "ddragon/versions.json"`, `static func cachePath(for url: URL) -> String?`.
  - `@MainActor @Observable final class DataDragonStore` : `init(transport: (any HTTPTransport)?, cache: DiskCache?)`, `static func preview() -> DataDragonStore`, `private(set) var versions: [String: String]`, `items: [String: ItemCatalog]`, `runes: [String: RuneCatalog]`, `summoners: [String: SummonerCatalog]`, `champions: [String: ChampionSpells]` (clé « version/championId ») ; `func version(forPatch: String?, now: Date = Date()) async -> String?`, `func knownVersion(forPatch: String?) -> String?`, `func loadCatalogs(version: String) async`, `func champion(version: String, championId: String) async -> ChampionSpells?`, `func cachedImage(_ url: URL) -> UIImage?`, `func image(_ url: URL) async -> UIImage?` ; `static let versionsRetry: TimeInterval = 60`.
  - `extension EnvironmentValues { @Entry var dataDragon: DataDragonStore? = nil }`.
  - `struct DDragonIcon: View` : `init(url: URL?, size: CGFloat = 28, radius: CGFloat? = nil, fallback: String = "")` (memberwise), `static func initials(_ name: String) -> String`.
  - Tests : `enum TestImages` : `static func png(_ color: UIColor, letter: String = "", side: CGFloat = 48) -> Data`, `static func seed(_ cache: DiskCache, _ icons: [(url: URL, color: UIColor, letter: String)])`.

- [ ] **Step 1: Écrire les tests du cache disque**

Créer `Tests/FailleTests/DiskCacheTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Cache disque des fonctionnalités : chemins sûrs, aller-retour JSON et octets, chemins Data Dragon.
struct DiskCacheTests {
    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-cache-\(UUID().uuidString)", isDirectory: true))
    }

    @Test func pathsNeverLeaveTheCache() {
        #expect(DiskCache.safePath("ddragon/16.18.1/img/item/1054.png") == "ddragon/16.18.1/img/item/1054.png")
        #expect(DiskCache.safePath("/replays//g1.json") == "replays/g1.json")
        #expect(DiskCache.safePath("./details/g1.json") == "details/g1.json")
        #expect(DiskCache.safePath("../follows.json") == nil)
        #expect(DiskCache.safePath("spells/../../settings.json") == nil)
        #expect(DiskCache.safePath("") == nil)
        #expect(Self.cache().url("../x.json") == nil)
    }

    @Test func valuesAndBytesRoundTrip() throws {
        let cache = Self.cache()
        let value = Cached(value: ["16.20.1", "16.19.1"], fetchedAt: Date(timeIntervalSinceReferenceDate: 1_000))
        cache.save(value, to: "ddragon/versions.json")
        #expect(cache.load(Cached<[String]>.self, from: "ddragon/versions.json") == value)
        cache.write(Data([1, 2, 3]), to: "ddragon/16.20.1/img/item/1054.png")
        #expect(cache.data("ddragon/16.20.1/img/item/1054.png") == Data([1, 2, 3]))
        #expect(cache.data("ddragon/absent.png") == nil)
        // Fichier illisible : ignoré (la donnée sera relue sur le réseau).
        cache.write(Data("pas du json".utf8), to: "replays/g1.json")
        #expect(cache.load(Cached<[String]>.self, from: "replays/g1.json") == nil)
    }

    @Test func dataDragonUrlsMapToTheirCachePath() throws {
        #expect(DataDragon.cachePath(for: DataDragon.championImage(version: "16.18.1", championId: "KSante"))
            == "ddragon/16.18.1/img/champion/KSante.png")
        #expect(DataDragon.cachePath(for: DataDragon.itemImage(version: "16.18.1", itemId: 3364))
            == "ddragon/16.18.1/img/item/3364.png")
        #expect(DataDragon.cachePath(for: DataDragon.runeIcon("perk-images/Styles/7204_Resolve.png"))
            == "ddragon/img/perk-images/Styles/7204_Resolve.png")
        #expect(DataDragon.cachePath(for: DataDragon.itemsURL(version: "16.18.1")) == "ddragon/16.18.1/data/fr_FR/item.json")
        #expect(DataDragon.cachePath(for: DataDragon.versionsURL) == nil) // `api/` : gardée à part, avec sa date
        #expect(DataDragon.cachePath(for: try #require(URL(string: "https://example.com/cdn/1.png"))) == nil)
    }
}
```

- [ ] **Step 2: Écrire le cache disque et les chemins Data Dragon**

Créer `App/Cache/DiskCache.swift` :

```swift
import Foundation

/// Cache disque des fonctionnalités (spec fonctionnalités, « Sobriété réseau ») : images et données Data Dragon
/// (`ddragon/…`), détails des games (`details/…`), relectures du flux (`replays/…`), sorts d'invocateur (`spells/…`).
/// Un dossier racine — `cache/` à côté des fichiers de Faille —, exclu de la sauvegarde iCloud : tout s'y retrouve par le
/// réseau. Chemins relatifs « a/b/c.json » ; un chemin qui tenterait d'en sortir (« .. ») est refusé. JSON en
/// `JSONEncoder()` / `JSONDecoder()` par défaut (dates en secondes depuis 2001), comme `FileStore`. Un fichier illisible
/// est simplement ignoré : la donnée sera relue sur le réseau.
struct DiskCache: Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    /// Chemin relatif sûr : composants non vides, sans « . » ni « .. » ; nil s'il ne reste rien ou s'il sort du dossier.
    static func safePath(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }

    func url(_ path: String) -> URL? {
        Self.safePath(path).map { root.appendingPathComponent($0, isDirectory: false) }
    }

    func data(_ path: String) -> Data? {
        url(path).flatMap { try? Data(contentsOf: $0) }
    }

    func write(_ data: Data, to path: String) {
        guard let url = url(path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        data(path).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func save<T: Encodable>(_ value: T, to path: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, to: path)
    }
}
```

Créer `App/DataDragon/DataDragon+Cache.swift` :

```swift
import Foundation
import LoLKit

extension DataDragon {
    /// Liste des versions gardée sur disque (24 h, `DataDragon.versionsMaxAge`).
    static let versionsCachePath = "ddragon/versions.json"

    /// Chemin dans le cache d'une URL Data Dragon : « ddragon/ » + le chemin après « /cdn/ »
    /// (« …/cdn/16.18.1/img/champion/KSante.png » → « ddragon/16.18.1/img/champion/KSante.png » ; icônes de runes sans
    /// version : « ddragon/img/perk-images/… » ; données : « ddragon/16.18.1/data/fr_FR/item.json »). nil pour un autre
    /// hôte ou un autre chemin.
    static func cachePath(for url: URL) -> String? {
        guard url.host() == "ddragon.leagueoflegends.com" else { return nil }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/cdn/") else { return nil }
        return DiskCache.safePath("ddragon/" + path.dropFirst("/cdn/".count))
    }
}
```

- [ ] **Step 3: Écrire le support des fausses icônes et les tests du store**

Créer `Tests/FailleTests/Support/TestImages.swift` :

```swift
import Foundation
import LoLKit
import UIKit
@testable import Faille

/// Fausses icônes Data Dragon pour les tests et les aperçus : aucun réseau, aucune image de Riot dans le dépôt.
enum TestImages {
    /// PNG carré uni avec une lettre (48 pt, à l'échelle de l'écran).
    static func png(_ color: UIColor, letter: String = "", side: CGFloat = 48) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.45, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let text = letter as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attributes)
        }
    }

    /// Dépose de fausses icônes dans le cache, au chemin de leur URL Data Dragon : `DataDragonStore` les lit comme les vraies.
    static func seed(_ cache: DiskCache, _ icons: [(url: URL, color: UIColor, letter: String)]) {
        for icon in icons {
            guard let path = DataDragon.cachePath(for: icon.url) else { continue }
            cache.write(png(icon.color, letter: icon.letter), to: path)
        }
    }
}
```

Créer `Tests/FailleTests/DataDragonStoreTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
import UIKit
@testable import Faille

// Réponses Data Dragon réduites (forme réelle de `api/versions.json` et des fichiers `data/fr_FR/…`).
private let versionsJSON = #"["16.20.1","16.19.1","16.18.1","lolpatch_3.7"]"#
private let itemsJSON = #"{"type":"item","version":"16.18.1","data":{"1054":{"name":"Bouclier de Doran","image":{"full":"1054.png"},"tags":["Health"]},"3364":{"name":"Lentille de l'oracle","image":{"full":"3364.png"},"tags":["Trinket","Vision"]}}}"#
private let runesJSON = #"[{"id":8400,"key":"Resolve","icon":"perk-images/Styles/7204_Resolve.png","name":"Volonté","slots":[{"runes":[{"id":8437,"key":"GraspOfTheUndying","icon":"perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png","name":"Poigne de l'immortel"}]}]}]"#
private let summonersJSON = #"{"type":"summoner","version":"16.18.1","data":{"SummonerFlash":{"id":"SummonerFlash","name":"Saut éclair","image":{"full":"SummonerFlash.png"}}}}"#
private let championJSON = #"{"type":"champion","version":"16.18.1","data":{"KSante":{"id":"KSante","name":"K'Santé","spells":[{"name":"Coups de ntofo","image":{"full":"KSanteQ.png"}},{"name":"Pour Nazumah !","image":{"full":"KSanteW.png"}},{"name":"Jeu de jambes","image":{"full":"KSanteE.png"}},{"name":"Tout donner","image":{"full":"KSanteR.png"}}],"passive":{"name":"Instinct de l'ntofo","image":{"full":"KSante_P.png"}}}}}"#

/// Data Dragon (spec fonctionnalités §3) : version du patch (liste relue au plus toutes les 24 h), catalogues et images
/// gardés sur disque, rien de redemandé inutilement, aucune requête pour le store d'aperçu.
@MainActor
@Suite(.serialized)
struct DataDragonStoreTests {
    private static func cache() -> DiskCache {
        DiskCache(root: TemporaryFiles.directory().appendingPathComponent("cache", isDirectory: true))
    }

    /// Faux Data Dragon : versions, catalogues, sorts de K'Santé et son icône (`png`) ; 404 pour le reste.
    private static func transport(png: Data = Data()) -> ScriptedTransport {
        ScriptedTransport(extra: { url in
            let path = url.path(percentEncoded: false)
            let body: Data?
            if path.hasSuffix("/api/versions.json") {
                body = Data(versionsJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/item.json") {
                body = Data(itemsJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/runesReforged.json") {
                body = Data(runesJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/summoner.json") {
                body = Data(summonersJSON.utf8)
            } else if path.hasSuffix("/data/fr_FR/champion/KSante.json") {
                body = Data(championJSON.utf8)
            } else if path.hasSuffix("/img/champion/KSante.png"), !png.isEmpty {
                body = png
            } else {
                body = nil
            }
            return body.map { HTTPResponse(status: 200, body: $0) }
        })
    }

    @Test func versionComesFromTheListWhichIsKeptADay() async {
        let cache = Self.cache()
        let transport = Self.transport()
        let store = DataDragonStore(transport: transport, cache: cache)
        let now = Date()
        #expect(await store.version(forPatch: "16.18.819.1060", now: now) == "16.18.1")
        #expect(store.knownVersion(forPatch: "16.18.819.1060") == "16.18.1")
        #expect(await store.version(forPatch: "16.19.300.1", now: now) == "16.19.1")
        #expect(await transport.requests.count == 1) // une seule lecture de la liste

        // Relancée moins de 24 h plus tard : la liste du disque, sans réseau.
        let offline = ScriptedTransport(mode: .failing)
        let later = DataDragonStore(transport: offline, cache: cache)
        #expect(await later.version(forPatch: "16.20.4.1", now: now.addingTimeInterval(20 * 3600)) == "16.20.1")
        #expect(await offline.requests.isEmpty)

        // Plus de 24 h : nouvel essai ; le réseau échoue, la liste périmée sert encore.
        let stale = DataDragonStore(transport: offline, cache: cache)
        #expect(await stale.version(forPatch: "16.18.1.1", now: now.addingTimeInterval(25 * 3600)) == "16.18.1")
        #expect(await offline.requests.count == 1)
    }

    @Test func catalogsAreReadOnceThenFromDisk() async {
        let cache = Self.cache()
        let transport = Self.transport()
        let store = DataDragonStore(transport: transport, cache: cache)
        await store.loadCatalogs(version: "16.18.1")
        #expect(store.items["16.18.1"]?.item(3364)?.isTrinket == true)
        #expect(store.runes["16.18.1"]?.rune(8437)?.name == "Poigne de l'immortel")
        #expect(store.summoners["16.18.1"]?.spell("SummonerFlash")?.name == "Saut éclair")
        #expect(await transport.requests.count == 3)
        await store.loadCatalogs(version: "16.18.1")
        #expect(await transport.requests.count == 3)

        let offline = ScriptedTransport(mode: .failing)
        let reopened = DataDragonStore(transport: offline, cache: cache)
        await reopened.loadCatalogs(version: "16.18.1")
        #expect(reopened.items["16.18.1"]?.item(1054)?.name == "Bouclier de Doran")
        #expect(await offline.requests.isEmpty)

        // Sorts d'un champion : lus à la demande (fiche du joueur), puis gardés.
        #expect(await reopened.champion(version: "16.18.1", championId: "KSante") == nil) // hors ligne, jamais lus
        let spells = await store.champion(version: "16.18.1", championId: "KSante")
        #expect(spells?.spell(forAbility: "R")?.image == "KSanteR.png")
        #expect(await reopened.champion(version: "16.18.1", championId: "KSante")?.passive?.image == "KSante_P.png")
    }

    @Test func imagesAreKeptOnDiskAndMissingOnesAreNotAskedAgain() async throws {
        let cache = Self.cache()
        let png = TestImages.png(.systemTeal, letter: "K")
        let transport = Self.transport(png: png)
        let store = DataDragonStore(transport: transport, cache: cache)
        let url = DataDragon.championImage(version: "16.18.1", championId: "KSante")
        #expect(store.cachedImage(url) == nil)
        #expect(await store.image(url) != nil)
        #expect(store.cachedImage(url) != nil)
        #expect(cache.data("ddragon/16.18.1/img/champion/KSante.png") == png)

        let offline = ScriptedTransport(mode: .failing)
        let reopened = DataDragonStore(transport: offline, cache: cache)
        #expect(await reopened.image(url) != nil)
        #expect(await offline.requests.isEmpty)

        let missing = DataDragon.itemImage(version: "16.18.1", itemId: 9999)
        #expect(await store.image(missing) == nil)
        #expect(await store.image(missing) == nil)
        #expect(await transport.requests.filter { $0 == missing }.count == 1)
    }

    @Test func previewStoreAsksNothing() async {
        let store = DataDragonStore.preview()
        #expect(await store.version(forPatch: "16.18.819.1060") == nil)
        await store.loadCatalogs(version: "16.18.1")
        #expect(store.items.isEmpty)
        #expect(await store.image(DataDragon.championImage(version: "16.18.1", championId: "KSante")) == nil)
    }

    @Test func fallbackInitialsReadTheChampionId() {
        #expect(DDragonIcon.initials("KSante") == "KS")
        #expect(DDragonIcon.initials("XinZhao") == "XZ")
        #expect(DDragonIcon.initials("Ahri") == "AH")
        #expect(DDragonIcon.initials("") == "")
    }
}
```

- [ ] **Step 4: Écrire le store Data Dragon**

Créer `App/DataDragon/DataDragonStore.swift` :

```swift
import Foundation
import LoLKit
import Observation
import UIKit

/// Images et données Data Dragon (spec fonctionnalités §3), sans clé : version du patch d'une game, catalogues fr_FR
/// (objets, runes, sorts d'invocateur, sorts d'un champion) et icônes. Tout est gardé dans le cache disque, sous
/// `ddragon/` : la liste des versions 24 h, le reste pour toujours (une version ne change pas). Les images sont décodées
/// hors du fil principal, jamais dans un `body`. Anti-spoiler : ce store ne connaît pas les matchs ; l'appli ne lui demande
/// rien pour un match masqué (les vues qui l'appellent n'existent pas tant qu'il est masqué).
@MainActor
@Observable
final class DataDragonStore {
    /// Version Data Dragon retenue pour chaque patch du flux (`gameMetadata.patchVersion`).
    private(set) var versions: [String: String] = [:]
    /// Catalogues par version.
    private(set) var items: [String: ItemCatalog] = [:]
    private(set) var runes: [String: RuneCatalog] = [:]
    private(set) var summoners: [String: SummonerCatalog] = [:]
    /// Sorts d'un champion, par « <version>/<championId> ».
    private(set) var champions: [String: ChampionSpells] = [:]

    /// Résultat d'un chargement d'image, transporté d'un fil à l'autre : l'image n'est jamais modifiée après sa création.
    struct LoadedImage: @unchecked Sendable {
        let image: UIImage?
        /// Absente chez Data Dragon (réponse autre que 200, ou illisible) : inutile de la redemander pendant la session.
        let missing: Bool
    }

    /// Pas plus d'un essai par minute pour la liste des versions quand le réseau échoue.
    static let versionsRetry: TimeInterval = 60

    private let transport: (any HTTPTransport)?
    private let cache: DiskCache?
    private let images = NSCache<NSURL, UIImage>()
    @ObservationIgnored private var versionList: Cached<[String]>?
    @ObservationIgnored private var versionsAttempt: Date?
    @ObservationIgnored private var catalogsLoading: Set<String> = []
    @ObservationIgnored private var imageLoads: [URL: Task<LoadedImage, Never>] = [:]
    @ObservationIgnored private var missingImages: Set<URL> = []

    /// - Parameters:
    ///   - transport: réseau ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil (aperçus) : rien n'est lu ni écrit.
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        self.transport = transport
        self.cache = cache
    }

    /// Aperçus : aucune requête, aucun fichier ; les vues montrent leurs vignettes de repli.
    static func preview() -> DataDragonStore {
        DataDragonStore(transport: nil, cache: nil)
    }

    // MARK: Version

    /// Version Data Dragon d'un patch du flux (« 16.18.819.1060 » → « 16.18.1 », `DataDragon.version(forPatch:versions:)`)
    /// sur la liste `api/versions.json`, relue au plus toutes les 24 h ; si le réseau échoue, la liste du disque, même
    /// périmée. nil si aucune liste n'a jamais pu être lue.
    func version(forPatch patch: String?, now: Date = Date()) async -> String? {
        let key = patch ?? ""
        if let known = versions[key] { return known }
        let list = await versionsList(now: now)
        guard let version = DataDragon.version(forPatch: patch, versions: list) else { return nil }
        versions[key] = version
        return version
    }

    /// Version déjà retenue pour ce patch (lecture instantanée pour un `body`) ; nil tant qu'elle n'est pas connue.
    func knownVersion(forPatch patch: String?) -> String? {
        versions[patch ?? ""]
    }

    private func versionsList(now: Date) async -> [String] {
        if versionList == nil {
            versionList = cache?.load(Cached<[String]>.self, from: DataDragon.versionsCachePath)
        }
        if let list = versionList, list.age(now: now) >= 0, list.age(now: now) < DataDragon.versionsMaxAge {
            return list.value
        }
        let mayTry = versionsAttempt.map { now.timeIntervalSince($0) >= Self.versionsRetry } ?? true
        if let transport, mayTry {
            versionsAttempt = now
            if let response = try? await transport.get(DataDragon.versionsURL, headers: [:]), response.status == 200,
               let fresh = try? DataDragon.decodeVersions(response.body), !fresh.isEmpty {
                let saved = Cached(value: fresh, fetchedAt: now)
                versionList = saved
                cache?.save(saved, to: DataDragon.versionsCachePath)
                return fresh
            }
        }
        return versionList?.value ?? []
    }

    // MARK: Catalogues

    /// Objets, runes et sorts d'invocateur d'une version : disque, sinon réseau (puis disque) ; une fois pour toutes.
    func loadCatalogs(version: String) async {
        guard !catalogsLoading.contains(version) else { return }
        catalogsLoading.insert(version)
        defer { catalogsLoading.remove(version) }
        if items[version] == nil {
            items[version] = await load(DataDragon.itemsURL(version: version)) { try ItemCatalog(json: $0) }
        }
        if runes[version] == nil {
            runes[version] = await load(DataDragon.runesURL(version: version)) { try RuneCatalog(json: $0) }
        }
        if summoners[version] == nil {
            summoners[version] = await load(DataDragon.summonerSpellsURL(version: version)) { try SummonerCatalog(json: $0) }
        }
    }

    /// Sorts (Q, W, E, R) et passif d'un champion : lus à l'ouverture de sa fiche seulement.
    func champion(version: String, championId: String) async -> ChampionSpells? {
        let key = "\(version)/\(championId)"
        if let known = champions[key] { return known }
        let url = DataDragon.championURL(version: version, championId: championId)
        guard let spells = await load(url, decode: { try ChampionSpells(json: $0) }) else { return nil }
        champions[key] = spells
        return spells
    }

    /// Un fichier de données : le disque, sinon le réseau ; décodé hors du fil principal, écrit sur disque seulement s'il
    /// se décode (un fichier abîmé ne reste jamais en cache).
    private func load<T: Sendable>(_ url: URL, decode: @escaping @Sendable (Data) throws -> T) async -> T? {
        guard let path = DataDragon.cachePath(for: url) else { return nil }
        let disk = cache
        if let saved = await Task.detached(priority: .utility, operation: {
            disk?.data(path).flatMap { try? decode($0) }
        }).value {
            return saved
        }
        guard let transport, let response = try? await transport.get(url, headers: [:]), response.status == 200 else {
            return nil
        }
        let body = response.body
        guard let fresh = await Task.detached(priority: .utility, operation: { try? decode(body) }).value else {
            return nil
        }
        cache?.write(body, to: path)
        return fresh
    }

    // MARK: Images

    /// Image déjà décodée (mémoire seulement : ni disque ni réseau) ; nil sinon.
    func cachedImage(_ url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    /// Image Data Dragon : mémoire, sinon disque, sinon réseau (puis disque) ; décodée hors du fil principal. nil si
    /// introuvable ; une image absente chez Data Dragon n'est plus redemandée pendant la session (une panne réseau, si).
    func image(_ url: URL) async -> UIImage? {
        if let hit = cachedImage(url) { return hit }
        guard !missingImages.contains(url), let path = DataDragon.cachePath(for: url) else { return nil }
        let load = imageLoads[url] ?? Task.detached(priority: .utility) {
            [transport = self.transport, cache = self.cache] in
            await Self.fetchImage(url, path: path, transport: transport, cache: cache)
        }
        imageLoads[url] = load
        let loaded = await load.value
        imageLoads[url] = nil
        if loaded.missing { missingImages.insert(url) }
        guard let image = loaded.image else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    private nonisolated static func fetchImage(_ url: URL, path: String, transport: (any HTTPTransport)?,
                                               cache: DiskCache?) async -> LoadedImage {
        if let data = cache?.data(path), let image = decode(data) {
            return LoadedImage(image: image, missing: false)
        }
        guard let transport else { return LoadedImage(image: nil, missing: false) }
        do {
            let response = try await transport.get(url, headers: [:])
            guard response.status == 200, let image = decode(response.body) else {
                return LoadedImage(image: nil, missing: true)
            }
            cache?.write(response.body, to: path)
            return LoadedImage(image: image, missing: false)
        } catch {
            return LoadedImage(image: nil, missing: false)
        }
    }

    private nonisolated static func decode(_ data: Data) -> UIImage? {
        UIImage(data: data)?.preparingForDisplay()
    }
}
```

- [ ] **Step 5: Écrire l'icône et son aperçu**

Créer `App/DataDragon/DDragonIcon.swift` (si `@Entry` refusait un type optionnel de classe isolée, le remplacer par une clé classique : `private struct DataDragonKey: EnvironmentKey { static let defaultValue: DataDragonStore? = nil }` et `var dataDragon: DataDragonStore? { get { self[DataDragonKey.self] } set { self[DataDragonKey.self] = newValue } }`) :

```swift
import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Store Data Dragon des vues de la game (draft, joueurs, fiche) ; nil (aperçus de composants) : vignettes de repli.
    @Entry var dataDragon: DataDragonStore? = nil
}

/// Icône Data Dragon (champion, objet, rune, sort) : l'image du cache, décodée par `DataDragonStore` hors du `body`, sinon
/// une vignette de repli (initiales sur verre, ou verre seul pour une case vide). La vue ne lit jamais de fichier ; sans
/// URL (version Data Dragon pas encore connue) ni store (aperçus), elle ne demande rien.
struct DDragonIcon: View {
    let url: URL?
    var size: CGFloat = 28
    /// Coins ; nil : 22 % de la taille. `size / 2` : rond (runes, balise).
    var radius: CGFloat? = nil
    /// Texte de la vignette de repli (« KS » pour K'Santé) ; vide : verre seul.
    var fallback = ""
    @Environment(\.dataDragon) private var store
    @State private var loaded: (url: URL, image: UIImage)?

    /// Image à afficher : celle déjà décodée pour cette URL, sinon celle de la mémoire du store, sinon nil (repli).
    private var image: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return store?.cachedImage(url)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? size * 0.22, style: .continuous)
        ZStack {
            shape.fill(Palette.chipFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !fallback.isEmpty {
                Text(fallback)
                    .font(Sora.font(max(8, size * 0.32), .semibold))
                    .foregroundStyle(Palette.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 0.5))
        .task(id: url) {
            guard let url, let store else {
                loaded = nil
                return
            }
            if let image = await store.image(url) {
                loaded = (url, image)
            }
        }
        .accessibilityHidden(true)
    }

    /// Initiales d'un id de champion pour la vignette de repli : « KSante » → « KS », « XinZhao » → « XZ », « Ahri » → « AH ».
    static func initials(_ name: String) -> String {
        let capitals = name.filter(\.isUppercase)
        if capitals.count >= 2 { return String(capitals.prefix(2)) }
        return String(name.filter(\.isLetter).prefix(2)).uppercased()
    }
}
```

Créer `Tests/FailleTests/DataDragonSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Icônes Data Dragon (spec fonctionnalités §3) : lues dans un cache rempli de fausses icônes (aucun réseau, aucune
    /// image de Riot dans le dépôt), puis vignettes de repli quand la version ou l'image manque.
    @Test func dataDragonBoard() async throws {
        let cache = DiskCache(root: TemporaryFiles.directory().appendingPathComponent("cache", isDirectory: true))
        let version = "16.18.1"
        let champion = DataDragon.championImage(version: version, championId: "KSante")
        let item = DataDragon.itemImage(version: version, itemId: 1054)
        let rune = DataDragon.runeIcon("perk-images/Styles/7204_Resolve.png")
        let spell = DataDragon.summonerSpellImage(version: version, spellId: "SummonerFlash")
        TestImages.seed(cache, [(champion, .systemIndigo, "K"), (item, .systemGreen, "D"), (rune, .systemTeal, "R"),
                                (spell, .systemYellow, "F")])
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Data Dragon", subtitle: "Icônes en cache · vignettes de repli")
                SectionLabel(text: "Depuis le cache")
                HStack(spacing: 10) {
                    DDragonIcon(url: champion, size: 48, fallback: "KS")
                    DDragonIcon(url: item, size: 32, radius: 6)
                    DDragonIcon(url: rune, size: 32, radius: 16)
                    DDragonIcon(url: spell, size: 32)
                }
                .glassCard(radius: Radius.inner, padding: 14)
                SectionLabel(text: "Vignettes de repli")
                HStack(spacing: 10) {
                    DDragonIcon(url: nil, size: 48, fallback: DDragonIcon.initials("XinZhao"))
                    DDragonIcon(url: DataDragon.championImage(version: version, championId: "Ahri"), size: 48,
                                fallback: DDragonIcon.initials("Ahri"))
                    DDragonIcon(url: nil, size: 32, radius: 6)
                    DDragonIcon(url: nil, size: 32, radius: 16)
                }
                .glassCard(radius: Radius.inner, padding: 14)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .environment(\.dataDragon, DataDragonStore(transport: nil, cache: cache))
        let url = try await Snapshot.write(board, named: "18-data-dragon")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 6: Vérifier le périmètre, committer, pousser**

```bash
git status --short
```

Expected : seulement `?? App/Cache/`, `?? App/DataDragon/`, `?? Tests/FailleTests/Support/TestImages.swift`, `?? Tests/FailleTests/DiskCacheTests.swift`, `?? Tests/FailleTests/DataDragonStoreTests.swift`, `?? Tests/FailleTests/DataDragonSnapshotTests.swift`.

```bash
git add App/Cache App/DataDragon Tests/FailleTests/Support/TestImages.swift Tests/FailleTests/DiskCacheTests.swift \
  Tests/FailleTests/DataDragonStoreTests.swift Tests/FailleTests/DataDragonSnapshotTests.swift
git commit -m "feat(app): socle Data Dragon — cache disque des fonctionnalités, version du patch (24 h), catalogues et icônes gardés sur disque, décodés hors du body" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t3-data-dragon
```

- [ ] **Step 7: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
```

Expected : jobs `build` et `apercus` verts ; suites `DiskCacheTests` (3 tests) et `DataDragonStoreTests` (5 tests) vertes ; `18-data-dragon.png` : quatre fausses icônes lues du cache (K indigo, D vert, R turquoise rond, F jaune), puis quatre vignettes de repli (« XZ », « AH », deux cases vides). Échec : `gh run view "$RUN" --log-failed`, corriger, commit, push, relancer. **T4, T5 et T6 attendent la fusion de cette branche.**


### Task 4: Fil des événements et courbe de l'écart de gold (relecture, direct, vues)

**Branche :** `fonc/appli-t4-fil-courbe` · **Vague :** B · **Dépendances :** T3 (`DiskCache`) fusionnée dans `main`.

**Files:**
- Create: `App/Timeline/ReplayFrames.swift`, `App/Timeline/TimelineFormat.swift`, `App/Timeline/TimelineStore.swift`, `App/Timeline/TimelineSamples.swift`, `App/Timeline/TimelineCard.swift`, `App/Timeline/GoldChartCard.swift`
- Test: `Tests/FailleTests/TimelineStoreTests.swift`, `Tests/FailleTests/TimelineSnapshotTests.swift` (aperçu `19-fil-et-courbe.png`)

**Interfaces:**
- Consumes : T3 `DiskCache(root:)`, `.load(_:from:)`, `.save(_:to:)` ; LoLKit `LoLClient(transport:)`, `LoLClient.window(gameId: String, startingTime: Date?) async throws -> LiveWindow`, `LiveWindow.snapshots() -> [GameSnapshot]`, `LiveWindow.latestSnapshot() -> GameSnapshot?`, `LiveWindow.firstFrameTime: Date?`, `LiveStatsTime.startingTime(now: Date, delay: TimeInterval = 90) -> Date`, `LoLAPIError.statsDisabled` / `.noData`, `GameTimeline.events(from: [GameSnapshot], firstFrameTime: Date) -> [TimelineEvent]`, `struct TimelineEvent { gameTime: TimeInterval; teamId: String; kind: Kind; count: Int; players: [String] }` + `init(gameTime:teamId:kind:count:players: [String] = [])`, `enum TimelineEvent.Kind { kills, dragon(String), baron, tower, inhibitor }`, `GoldSeries.points(from: [GameSnapshot], firstFrameTime: Date, orientedTo: String?) -> [GoldPoint]`, `struct GoldPoint: Equatable { gameTime: TimeInterval; difference: Int }` + init, `GameSnapshot(gameId:phase:timestamp:blueTeamId:redTeamId:blue:red:bluePlayers:redPlayers:)`, `PlayerLine(role:champion:name:level:kills:deaths:assists:creepScore:gold:)`, `GamePhase(rawValue:)`, `TeamStats` (`Codable`, `init(kills:gold:towers:inhibitors:barons:dragons:)`), `Format.clock(_:)`, `Format.dragons(_:)`, `Format.gold(_:)`, `Format.goldDiff(_:)`, `LoLDate.parse(_:)` / `.format(_:)` ; appli `SampleData.kcSnapshot`, `SampleData.kcGameStart`, `StatLabel(icon:text:)`, `SkeletonBlock(width:height:radius:)`, `IconView`, `Palette`, `Typo`, `.numericChange(_:)`, `.glassCard`, `.buttonStyle(.pressable)` ; tests `ScriptedTransport(mode:extra:)`.
- Produces :
  - `struct CachedFrame: Codable, Sendable, Equatable` (`init(_ snapshot: GameSnapshot)`, `var snapshot: GameSnapshot`) ; `struct ReplayRecord: Codable, Sendable, Equatable { firstFrame: Date; frames: [CachedFrame]; lastStep: Date?; complete: Bool }` ; `enum ReplaySchedule { maxSteps = 90; pause = .milliseconds(500); static func steps(firstFrame: Date, after: Date?, until: Date?) -> [Date] }`.
  - `enum TimelineText { static func text(_ event: TimelineEvent) -> String; static func isMarker(_ event: TimelineEvent) -> Bool }` ; `enum GoldChartData { static func withZeroCrossings(_ points: [GoldPoint]) -> [GoldPoint]; static func axisLimit(_ points: [GoldPoint]) -> Int }`.
  - `@MainActor @Observable final class TimelineStore` : `init(transport: (any HTTPTransport)?, cache: DiskCache?)`, `init(preview frames: [String: [GameSnapshot]])`, `private(set) var replayFrames`, `liveFrames: [String: [GameSnapshot]]`, `firstFrames: [String: Date]`, `replaying: Set<String>`, `unavailable: Set<String>` ; `func snapshots(gameId:) -> [GameSnapshot]`, `func events(gameId:) -> [TimelineEvent]`, `func goldPoints(gameId: String, orientedTo teamId: String?) -> [GoldPoint]`, `func load(gameId: String, inProgress: Bool, now: Date = Date()) async`, `func append(_ snapshot: GameSnapshot)`, `static func path(_ gameId: String) -> String`.
  - `enum TimelineSamples` : `struct Script` (`static let kcLive`, `static let redWins`), `static func frames(_ script: Script, start: Date, final: GameSnapshot) -> [GameSnapshot]`.
  - `struct TimelineTeam: Equatable { let id: String; let code: String; let tint: Color }` ; `struct TimelineCard: View` (`init(events:teams:loading: Bool = false)`, `static func icon(_ kind: TimelineEvent.Kind) -> Icon`) ; `struct GoldChartCard: View` (`init(points:markers:teams:loading: Bool = false)`).

- [ ] **Step 1: Écrire les tests**

Créer `Tests/FailleTests/TimelineStoreTests.swift` (la relecture fait une pause de 0,5 s entre deux fenêtres : la suite dure ≈ 6 s) :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Début de la game de test (comme la fixture `window_pregame.json` de LoLKit) : la relecture lit 20:19, 20:20…
private let gameStart = LoLDate.parse("2026-10-04T20:18:26.892Z")!

/// Fenêtre livestats d'une frame (forme réelle de `window`, joueurs omis) : gold bleu qui monte de 500 par minute, un
/// kill bleu à partir de 20:21, `finished` à partir de 20:24.
private func windowJSON(at time: Date) -> String {
    let minute = Int(time.timeIntervalSince(gameStart) / 60)
    let state = time >= gameStart.addingTimeInterval(5 * 60) ? "finished" : "in_game"
    let team = #""inhibitors":0,"towers":0,"barons":0,"dragons":[],"participants":[]"#
    return """
    {"esportsGameId":"G1","esportsMatchId":"M1","gameMetadata":{"patchVersion":"16.18.819.1060",\
    "blueTeamMetadata":{"esportsTeamId":"kc","participantMetadata":[]},\
    "redTeamMetadata":{"esportsTeamId":"c9","participantMetadata":[]}},\
    "frames":[{"rfc460Timestamp":"\(LoLDate.format(time))","gameState":"\(state)",\
    "blueTeam":{"totalGold":\(2500 + 500 * minute),"totalKills":\(minute >= 2 ? 1 : 0),\(team)},\
    "redTeam":{"totalGold":2500,"totalKills":0,\(team)}}]}
    """
}

/// Faux flux `window` de la game G1 : sans `startingTime`, la première frame ; sinon une frame 9 s après le début demandé.
private func replayTransport(statsDisabled: Bool = false) -> ScriptedTransport {
    ScriptedTransport(extra: { url in
        guard url.path.contains("/window/G1") else { return nil }
        if statsDisabled { return HTTPResponse(status: 404, body: Data()) }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let start = query?.first { $0.name == "startingTime" }?.value.flatMap(LoLDate.parse)
        let time = start.map { $0.addingTimeInterval(9) } ?? gameStart
        return HTTPResponse(status: 200, body: Data(windowJSON(at: time).utf8))
    })
}

/// Fil et courbe de gold (spec fonctionnalités §4, §5) : relecture à pas de 60 s gardée sur disque, reprise, arrêt à la
/// frame `finished`, jamais en avance sur la diffusion, frames du direct ajoutées une seule fois.
@MainActor
@Suite(.serialized)
struct TimelineStoreTests {
    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-timeline-\(UUID().uuidString)", isDirectory: true))
    }

    private static func windowRequests(_ transport: ScriptedTransport) async -> [URL] {
        await transport.requests.filter { $0.path.contains("/window/") }
    }

    @Test func cachedFramesRoundTrip() throws {
        let snapshot = SampleData.kcSnapshot
        let data = try JSONEncoder().encode(CachedFrame(snapshot))
        #expect(try JSONDecoder().decode(CachedFrame.self, from: data).snapshot == snapshot)
    }

    @Test func scheduleReadsEveryFullMinuteFromTheStart() throws {
        let steps = ReplaySchedule.steps(firstFrame: gameStart, after: nil, until: nil)
        #expect(steps.count == ReplaySchedule.maxSteps)
        #expect(LoLDate.format(try #require(steps.first)) == "2026-10-04T20:19:00.000Z")
        #expect(LoLDate.format(steps[35]) == "2026-10-04T20:54:00.000Z")
        let resumed = ReplaySchedule.steps(firstFrame: gameStart, after: steps[10], until: steps[12])
        #expect(resumed == [steps[11], steps[12]])
        #expect(ReplaySchedule.steps(firstFrame: gameStart, after: nil, until: gameStart).isEmpty)
    }

    @Test func finishedGameIsReplayedOnceThenReadFromDisk() async throws {
        let cache = Self.cache()
        let transport = replayTransport()
        let store = TimelineStore(transport: transport, cache: cache)
        await store.load(gameId: "G1", inProgress: false)
        // Première frame, puis 20:19 … 20:23 en jeu et 20:24 `finished` : la relecture s'arrête là.
        #expect(await Self.windowRequests(transport).count == 7)
        #expect(store.replayFrames["G1"]?.count == 7)
        #expect(store.replayFrames["G1"]?.last?.phase == .finished)
        #expect(store.firstFrames["G1"] == gameStart)
        let kill = try #require(store.events(gameId: "G1").first)
        #expect(kill.kind == .kills)
        #expect(kill.teamId == "kc")
        #expect(store.goldPoints(gameId: "G1", orientedTo: "c9").last?.difference == -2_500)

        // Relecture complète : plus aucune requête, ni dans ce store ni au prochain lancement.
        await store.load(gameId: "G1", inProgress: false)
        let offline = ScriptedTransport(mode: .failing)
        let reopened = TimelineStore(transport: offline, cache: cache)
        await reopened.load(gameId: "G1", inProgress: false)
        #expect(await offline.requests.isEmpty)
        #expect(reopened.replayFrames["G1"]?.count == 7)
        #expect(await Self.windowRequests(transport).count == 7)
    }

    /// Ouverture tardive d'une game en cours : relecture jusqu'à `LiveStatsTime.startingTime(now:)` seulement (jamais en
    /// avance sur la diffusion), puis reprise au pas suivant à la prochaine ouverture.
    @Test func liveGameIsReplayedUpToTheBroadcastDelayThenResumed() async {
        let cache = Self.cache()
        let transport = replayTransport()
        let store = TimelineStore(transport: transport, cache: cache)
        // 20:22:40 : `startingTime` au plus 20:21:10 → fenêtres de 20:19, 20:20 et 20:21.
        await store.load(gameId: "G1", inProgress: true, now: gameStart.addingTimeInterval(254))
        #expect(await Self.windowRequests(transport).count == 4)
        #expect(store.replayFrames["G1"]?.count == 4)

        let reopened = TimelineStore(transport: transport, cache: cache)
        await reopened.load(gameId: "G1", inProgress: true, now: gameStart.addingTimeInterval(374))
        // 20:24:40 : reprise à 20:22, puis 20:23.
        let requests = await Self.windowRequests(transport)
        #expect(requests.count == 6)
        #expect(requests.last?.query?.contains("2026-10-04T20:23:00.000Z") == true)
        #expect(reopened.replayFrames["G1"]?.count == 6)
    }

    @Test func statsDisabledStopsTheReplay() async {
        let transport = replayTransport(statsDisabled: true)
        let store = TimelineStore(transport: transport, cache: Self.cache())
        await store.load(gameId: "G1", inProgress: false)
        await store.load(gameId: "G1", inProgress: false)
        #expect(store.unavailable.contains("G1"))
        #expect(await Self.windowRequests(transport).count == 1)
    }

    @Test func liveFramesAreAddedOnceAndInOrder() {
        let start = SampleData.kcGameStart
        let frames = TimelineSamples.frames(.kcLive, start: start, final: SampleData.kcSnapshot)
        let store = TimelineStore(preview: [SampleData.kcSnapshot.gameId: frames])
        store.append(SampleData.kcSnapshot)
        store.append(SampleData.kcSnapshot)
        store.append(frames[3]) // plus ancienne que la dernière : ignorée
        #expect(store.liveFrames[SampleData.kcSnapshot.gameId]?.count == 1)
        #expect(store.snapshots(gameId: SampleData.kcSnapshot.gameId).count == frames.count + 1)
    }

    /// Le scénario d'exemple raconte la game que montre l'aperçu : 7 kills contre 4, nommés, trois drakes, +2,1k.
    @Test func sampleGameTellsItsStory() {
        let gameId = SampleData.kcSnapshot.gameId
        let frames = TimelineSamples.frames(.kcLive, start: SampleData.kcGameStart, final: SampleData.kcSnapshot)
        let store = TimelineStore(preview: [gameId: frames + [SampleData.kcSnapshot]])
        let events = store.events(gameId: gameId)
        let kills = events.filter { $0.kind == .kills }
        #expect(kills.filter { $0.teamId == "kc" }.map(\.count).reduce(0, +) == 7)
        #expect(kills.filter { $0.teamId == "c9" }.map(\.count).reduce(0, +) == 4)
        #expect(kills.allSatisfy { !$0.players.isEmpty })
        #expect(events.filter { TimelineText.isMarker($0) }.count == 3)
        #expect(store.goldPoints(gameId: gameId, orientedTo: "kc").last?.difference == 2_100)
    }

    @Test func textsNeverInventNames() {
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 1, players: ["KC Mid"]))
            == "Kill · KC Mid")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 2,
                                                players: ["KC Mid", "KC Bot"])) == "2 kills · KC Mid, KC Bot")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 2)) == "+2 kills")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .kills, count: 1)) == "+1 kill")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .dragon("ocean"), count: 1))
            == "Drake océan")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .baron, count: 1)) == "Baron")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .tower, count: 2)) == "2 tours")
        #expect(TimelineText.text(TimelineEvent(gameTime: 60, teamId: "kc", kind: .inhibitor, count: 1)) == "Inhibiteur")
    }

    @Test func goldCurveCrossesZeroOnTheAxis() {
        let points = [GoldPoint(gameTime: 0, difference: 0), GoldPoint(gameTime: 60, difference: -100),
                      GoldPoint(gameTime: 120, difference: 300)]
        let split = GoldChartData.withZeroCrossings(points)
        #expect(split.count == 4)
        #expect(split[2] == GoldPoint(gameTime: 75, difference: 0))
        #expect(GoldChartData.axisLimit(points) == 1_000)
        #expect(GoldChartData.axisLimit([GoldPoint(gameTime: 0, difference: -12_460)]) == 13_000)
    }
}
```

- [ ] **Step 2: Écrire les frames gardées et le calendrier de la relecture**

Créer `App/Timeline/ReplayFrames.swift` :

```swift
import Foundation
import LoLKit

/// Une frame du fil gardée sur disque : la forme de `GameSnapshot` en JSON (`GameSnapshot` n'est pas `Codable`), relue
/// avec les inits publics de LoLKit.
struct CachedFrame: Codable, Sendable, Equatable {
    struct Player: Codable, Sendable, Equatable {
        let role: String
        let champion: String
        let name: String
        let level: Int
        let kills: Int
        let deaths: Int
        let assists: Int
        let creepScore: Int
        let gold: Int

        init(_ line: PlayerLine) {
            role = line.role
            champion = line.champion
            name = line.name
            level = line.level
            kills = line.kills
            deaths = line.deaths
            assists = line.assists
            creepScore = line.creepScore
            gold = line.gold
        }

        var line: PlayerLine {
            PlayerLine(role: role, champion: champion, name: name, level: level, kills: kills, deaths: deaths,
                       assists: assists, creepScore: creepScore, gold: gold)
        }
    }

    let gameId: String
    /// `GamePhase.rawValue` (`inGame`, `paused`, `finished`).
    let phase: String
    let timestamp: Date
    let blueTeamId: String
    let redTeamId: String
    let blue: TeamStats
    let red: TeamStats
    let bluePlayers: [Player]
    let redPlayers: [Player]

    init(_ snapshot: GameSnapshot) {
        gameId = snapshot.gameId
        phase = snapshot.phase.rawValue
        timestamp = snapshot.timestamp
        blueTeamId = snapshot.blueTeamId
        redTeamId = snapshot.redTeamId
        blue = snapshot.blue
        red = snapshot.red
        bluePlayers = snapshot.bluePlayers.map(Player.init)
        redPlayers = snapshot.redPlayers.map(Player.init)
    }

    var snapshot: GameSnapshot {
        GameSnapshot(gameId: gameId, phase: GamePhase(rawValue: phase) ?? .inGame, timestamp: timestamp,
                     blueTeamId: blueTeamId, redTeamId: redTeamId, blue: blue, red: red,
                     bluePlayers: bluePlayers.map(\.line), redPlayers: redPlayers.map(\.line))
    }
}

/// Relecture d'une game gardée sur disque (`replays/<gameId>.json`).
struct ReplayRecord: Codable, Sendable, Equatable {
    /// Première frame de la game (fenêtre lue sans `startingTime`) : le 0:00 du temps de jeu.
    var firstFrame: Date
    /// Première frame de la game, puis la dernière frame de chaque fenêtre de la relecture, dans l'ordre.
    var frames: [CachedFrame]
    /// Début de la dernière fenêtre lue : la relecture reprend au pas suivant.
    var lastStep: Date?
    /// La frame `finished` est lue : plus aucune requête pour cette game.
    var complete: Bool
}

/// Calendrier de la relecture d'une game (spec fonctionnalités §4) : une fenêtre `window` par minute pleine depuis le
/// début, comme la capture `window_replay.json` de LoLKit ; on garde la dernière frame de chacune (≈ 35 requêtes pour une
/// game de 35 min).
enum ReplaySchedule {
    /// Au plus 90 pas (90 min de jeu) : une relecture ne tourne jamais sans fin.
    static let maxSteps = 90
    /// Pause entre deux requêtes : le flux n'a montré aucune limite à ≈ 1 requête/s (spec §4.1), on reste en dessous.
    static let pause: Duration = .milliseconds(500)

    /// Débuts des fenêtres à lire : les minutes pleines à partir de `firstFrame`, après `after` (reprise d'une relecture),
    /// jusqu'à `until` compris (game en cours : `LiveStatsTime.startingTime(now:)`, jamais en avance sur la diffusion) ;
    /// `maxSteps` au plus depuis le début de la game.
    static func steps(firstFrame: Date, after: Date?, until: Date?) -> [Date] {
        let firstMinute = (firstFrame.timeIntervalSince1970 / 60).rounded(.up) * 60
        var steps: [Date] = []
        for index in 0..<maxSteps {
            let step = Date(timeIntervalSince1970: firstMinute + Double(index) * 60)
            if let after, step <= after { continue }
            if let until, step > until { break }
            steps.append(step)
        }
        return steps
    }
}
```

- [ ] **Step 3: Écrire les textes du fil et les données de la courbe**

Créer `App/Timeline/TimelineFormat.swift` :

```swift
import Foundation
import LoLKit

/// Textes du fil des événements (spec fonctionnalités §4). Les joueurs ne sont nommés que si LoLKit a pu les déduire ;
/// sinon « +2 kills » : jamais d'attribution inventée.
enum TimelineText {
    /// « Kill · KC Mid », « 2 kills · KC Mid, KC Bot », « +2 kills », « Drake infernal », « Baron », « 2 tours »,
    /// « Inhibiteur ».
    static func text(_ event: TimelineEvent) -> String {
        switch event.kind {
        case .kills:
            let label = event.count == 1 ? "kill" : "kills"
            guard !event.players.isEmpty else { return "+\(event.count) \(label)" }
            let count = event.count == 1 ? "Kill" : "\(event.count) kills"
            return "\(count) · \(event.players.joined(separator: ", "))"
        case let .dragon(type):
            return "Drake \(Format.dragons([type]))"
        case .baron:
            return event.count == 1 ? "Baron" : "\(event.count) barons"
        case .tower:
            return event.count == 1 ? "Tour" : "\(event.count) tours"
        case .inhibitor:
            return event.count == 1 ? "Inhibiteur" : "\(event.count) inhibiteurs"
        }
    }

    /// Repères de la courbe de gold : drakes et barons seulement.
    static func isMarker(_ event: TimelineEvent) -> Bool {
        switch event.kind {
        case .dragon, .baron: return true
        case .kills, .tower, .inhibitor: return false
        }
    }
}

/// Données de la courbe de l'écart de gold (spec fonctionnalités §5).
enum GoldChartData {
    /// La courbe, avec un point ajouté à chaque passage par zéro : l'aire au-dessus de zéro (équipe de gauche en tête) et
    /// celle en dessous (l'autre équipe) se rejoignent exactement sur l'axe.
    static func withZeroCrossings(_ points: [GoldPoint]) -> [GoldPoint] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        for point in points.dropFirst() {
            if (previous.difference < 0 && point.difference > 0) || (previous.difference > 0 && point.difference < 0) {
                let ratio = Double(previous.difference) / Double(previous.difference - point.difference)
                let time = previous.gameTime + (point.gameTime - previous.gameTime) * ratio
                result.append(GoldPoint(gameTime: time, difference: 0))
            }
            result.append(point)
            previous = point
        }
        return result
    }

    /// Borne de l'axe vertical, symétrique : le plus grand écart (en valeur absolue) arrondi au millier supérieur,
    /// 1 000 au moins.
    static func axisLimit(_ points: [GoldPoint]) -> Int {
        let peak = points.map { abs($0.difference) }.max() ?? 0
        return max(1000, (peak + 999) / 1000 * 1000)
    }
}
```

- [ ] **Step 4: Écrire le store**

Créer `App/Timeline/TimelineStore.swift` :

```swift
import Foundation
import LoLKit
import Observation

/// Frames du fil des événements et de la courbe de gold, par game (spec fonctionnalités §4, §5) : relecture du flux à pas
/// de 60 s — game terminée, ou ouverture tardive d'une game en cours —, gardée sur disque (`replays/<gameId>.json`), puis
/// chaque frame lue en direct par l'écran Détail (10 s). Le fil et la courbe se calculent dans LoLKit (`GameTimeline`,
/// `GoldSeries`). Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué (le fil raconte la game, la courbe dit
/// qui mène) ; ce store ne connaît pas les matchs.
@MainActor
@Observable
final class TimelineStore {
    /// Frames de la relecture, par game : première frame de la game, puis une par minute.
    private(set) var replayFrames: [String: [GameSnapshot]] = [:]
    /// Frames reçues en direct après l'ouverture de l'écran (mémoire seulement).
    private(set) var liveFrames: [String: [GameSnapshot]] = [:]
    /// Première frame de chaque game : le 0:00 du temps de jeu.
    private(set) var firstFrames: [String: Date] = [:]
    /// Games en cours de relecture (gabarit de la courbe et du fil).
    private(set) var replaying: Set<String> = []
    /// Games dont Riot ne fournit pas les stats (404) : plus aucune requête.
    private(set) var unavailable: Set<String> = []

    private let client: LoLClient?
    private let cache: DiskCache?
    @ObservationIgnored private var records: [String: ReplayRecord] = [:]

    /// - Parameters:
    ///   - transport: réseau ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil : rien n'est gardé.
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        client = transport.map { LoLClient(transport: $0) }
        self.cache = cache
    }

    /// Aperçus : relectures figées (la première frame de chaque liste est le début de la game), aucune requête.
    init(preview frames: [String: [GameSnapshot]]) {
        client = nil
        cache = nil
        replayFrames = frames
        firstFrames = frames.compactMapValues { $0.first?.timestamp }
    }

    // MARK: Lectures pour les vues

    /// Toutes les frames connues de la game (relecture puis direct) ; `GameTimeline` et `GoldSeries` les remettent dans
    /// l'ordre chronologique.
    func snapshots(gameId: String) -> [GameSnapshot] {
        (replayFrames[gameId] ?? []) + (liveFrames[gameId] ?? [])
    }

    /// Fil de la game, dans l'ordre chronologique (l'écran l'affiche du plus récent au plus ancien) ; vide tant que la
    /// première frame n'est pas connue.
    func events(gameId: String) -> [TimelineEvent] {
        guard let first = firstFrames[gameId] else { return [] }
        return GameTimeline.events(from: snapshots(gameId: gameId), firstFrameTime: first)
    }

    /// Courbe de l'écart de gold, positive quand `teamId` mène (l'équipe de gauche de l'écran).
    func goldPoints(gameId: String, orientedTo teamId: String?) -> [GoldPoint] {
        guard let first = firstFrames[gameId] else { return [] }
        return GoldSeries.points(from: snapshots(gameId: gameId), firstFrameTime: first, orientedTo: teamId)
    }

    // MARK: Chargement

    /// Relecture de la game : le disque d'abord ; puis, sauf si elle est complète, la première frame (fenêtre sans
    /// `startingTime`) et une fenêtre par minute pleine (`ReplaySchedule`), une à une, avec une pause entre deux, en
    /// gardant la dernière frame de chacune et en enregistrant à chaque pas (une relecture interrompue reprend où elle
    /// s'était arrêtée). Game terminée : jusqu'à la frame `finished`. Game en cours : jusqu'à
    /// `LiveStatsTime.startingTime(now:)` (le flux refuse une fenêtre en avance sur la diffusion), le direct prend le
    /// relais (`append`). Une erreur réseau arrête la relecture sans rien perdre ; un 404 (stats désactivées) la clôt.
    func load(gameId: String, inProgress: Bool, now: Date = Date()) async {
        guard !unavailable.contains(gameId), !replaying.contains(gameId) else { return }
        if records[gameId] == nil, let saved = cache?.load(ReplayRecord.self, from: Self.path(gameId)) {
            publish(saved, gameId: gameId)
        }
        guard let client, records[gameId]?.complete != true else { return }
        replaying.insert(gameId)
        defer { replaying.remove(gameId) }
        do {
            var record: ReplayRecord
            if let known = records[gameId] {
                record = known
            } else {
                let opening = try await client.window(gameId: gameId, startingTime: nil)
                guard let first = opening.firstFrameTime else { return }
                record = ReplayRecord(firstFrame: first, frames: opening.snapshots().prefix(1).map(CachedFrame.init),
                                      lastStep: nil, complete: false)
                save(record, gameId: gameId)
            }
            let until = inProgress ? LiveStatsTime.startingTime(now: now) : nil
            for step in ReplaySchedule.steps(firstFrame: record.firstFrame, after: record.lastStep, until: until) {
                try await Task.sleep(for: ReplaySchedule.pause)
                do {
                    let window = try await client.window(gameId: gameId, startingTime: step)
                    if let last = window.latestSnapshot() {
                        record.frames.append(CachedFrame(last))
                        record.complete = last.phase == .finished
                    }
                } catch LoLAPIError.noData {
                    // Fenêtre vide (début de game) : on passe au pas suivant.
                }
                record.lastStep = step
                save(record, gameId: gameId)
                if record.complete { break }
            }
        } catch LoLAPIError.statsDisabled {
            unavailable.insert(gameId)
        } catch {
            // Réseau, refus du flux, annulation (écran quitté) : la relecture reprendra à la prochaine ouverture.
        }
    }

    /// Frame lue en direct par l'écran Détail : ajoutée au fil si elle est plus récente que tout ce qu'on a déjà pour
    /// cette game (la même frame relue n'est pas ajoutée deux fois).
    func append(_ snapshot: GameSnapshot) {
        let gameId = snapshot.gameId
        let latest = [replayFrames[gameId]?.last?.timestamp, liveFrames[gameId]?.last?.timestamp].compactMap { $0 }.max()
        guard latest.map({ snapshot.timestamp > $0 }) ?? true else { return }
        liveFrames[gameId, default: []].append(snapshot)
    }

    private func save(_ record: ReplayRecord, gameId: String) {
        publish(record, gameId: gameId)
        cache?.save(record, to: Self.path(gameId))
    }

    private func publish(_ record: ReplayRecord, gameId: String) {
        records[gameId] = record
        firstFrames[gameId] = record.firstFrame
        replayFrames[gameId] = record.frames.map(\.snapshot)
    }

    static func path(_ gameId: String) -> String {
        "replays/\(gameId).json"
    }
}
```

- [ ] **Step 5: Écrire les scénarios d'exemple**

Créer `App/Timeline/TimelineSamples.swift` :

```swift
import Foundation
import LoLKit

/// Frames d'exemple d'une game, minute par minute, pour les aperçus et les tests (aucune requête) : construites avec les
/// inits publics de LoLKit à partir d'un scénario (écart de gold, kills par joueur, drakes, barons, tours, inhibiteurs).
enum TimelineSamples {
    /// Un scénario de game, minute par minute.
    struct Script: Sendable {
        /// Écart de gold (bleu − rouge) à chaque minute, de 0:00 à la dernière frame.
        let goldDiffs: [Int]
        /// Kills : minute, et index (0-4, ordre du flux) du joueur qui tue.
        let blueKills: [(minute: Int, player: Int)]
        let redKills: [(minute: Int, player: Int)]
        let blueDragons: [(minute: Int, type: String)]
        let redDragons: [(minute: Int, type: String)]
        let blueBarons: [Int]
        let redBarons: [Int]
        let blueTowers: [Int]
        let redTowers: [Int]
        let blueInhibitors: [Int]
        let redInhibitors: [Int]
        /// La dernière frame est `finished`.
        let finished: Bool

        /// KC – C9, game 2 en cours (18 min) : finit sur les stats de `SampleData.kcSnapshot` (7 – 4, +2,1k, 3 – 1 tours,
        /// drakes infernal et océan contre nuage).
        static let kcLive = Script(
            goldDiffs: [0, 0, 30, 80, 260, 140, -120, 60, 480, 620, 540, 900, 760, 1_100, 1_480, 1_300, 1_720, 1_900,
                        2_100],
            blueKills: [(4, 2), (8, 0), (8, 1), (11, 2), (14, 0), (16, 2), (18, 3)],
            redKills: [(6, 1), (9, 2), (12, 2), (15, 3)],
            blueDragons: [(9, "infernal"), (15, "ocean")],
            redDragons: [(5, "cloud")],
            blueBarons: [], redBarons: [],
            blueTowers: [13, 16, 17], redTowers: [12],
            blueInhibitors: [], redInhibitors: [],
            finished: false
        )

        /// Game jouée de 34 min, gagnée par l'équipe rouge : finit sur les stats de `SampleData.kcG2Final`.
        static let redWins = Script(
            goldDiffs: [0, -20, 40, -80, -150, -300, -220, -480, -700, -540, -900, -1_250, -1_100, -1_600, -2_100,
                        -1_800, -2_300, -2_900, -3_400, -3_100, -3_900, -4_600, -5_200, -4_800, -5_600, -6_900, -7_400,
                        -8_100, -8_800, -9_600, -10_500, -11_800, -12_600, -13_900, -15_200],
            blueKills: [(6, 1), (13, 2), (19, 3), (24, 0), (27, 2)],
            redKills: [(4, 2), (9, 1), (9, 2), (14, 3), (17, 0), (20, 2), (22, 3), (25, 1), (28, 2), (30, 3), (31, 0),
                       (33, 2), (33, 3), (34, 1)],
            blueDragons: [(11, "ocean")],
            redDragons: [(6, "hextech"), (17, "hextech"), (23, "infernal"), (29, "hextech")],
            blueBarons: [], redBarons: [26, 33],
            blueTowers: [15, 21], redTowers: [12, 14, 18, 20, 24, 27, 29, 31, 32, 33, 34],
            blueInhibitors: [], redInhibitors: [31, 33, 34],
            finished: true
        )
    }

    /// Une frame par minute, de 0:00 à la fin du scénario (horodatée 9 s après chaque minute pleine, comme la relecture).
    /// Équipes, joueurs (rôle, champion, pseudo) et valeurs finales de chaque joueur viennent de `final` ; les kills de
    /// chaque joueur suivent le scénario (le fil peut donc les nommer), le reste croît au prorata du temps.
    static func frames(_ script: Script, start: Date, final: GameSnapshot) -> [GameSnapshot] {
        let last = script.goldDiffs.count - 1
        return script.goldDiffs.indices.map { minute in
            let base = 2_500 + minute * 1_750
            let diff = script.goldDiffs[minute]
            func count(_ minutes: [Int]) -> Int { minutes.filter { $0 <= minute }.count }
            let blue = TeamStats(kills: script.blueKills.filter { $0.minute <= minute }.count, gold: base + diff / 2,
                                 towers: count(script.blueTowers), inhibitors: count(script.blueInhibitors),
                                 barons: count(script.blueBarons),
                                 dragons: script.blueDragons.filter { $0.minute <= minute }.map(\.type))
            let red = TeamStats(kills: script.redKills.filter { $0.minute <= minute }.count, gold: base - diff / 2,
                                towers: count(script.redTowers), inhibitors: count(script.redInhibitors),
                                barons: count(script.redBarons),
                                dragons: script.redDragons.filter { $0.minute <= minute }.map(\.type))
            return GameSnapshot(
                gameId: final.gameId,
                phase: script.finished && minute == last ? .finished : .inGame,
                timestamp: start.addingTimeInterval(Double(minute) * 60 + (minute == 0 ? 0 : 9)),
                blueTeamId: final.blueTeamId, redTeamId: final.redTeamId, blue: blue, red: red,
                bluePlayers: players(final.bluePlayers, kills: script.blueKills, minute: minute, last: last),
                redPlayers: players(final.redPlayers, kills: script.redKills, minute: minute, last: last)
            )
        }
    }

    /// Joueurs à la minute `minute` : kills exacts du scénario, le reste au prorata de leur ligne finale.
    private static func players(_ finals: [PlayerLine], kills: [(minute: Int, player: Int)], minute: Int,
                                last: Int) -> [PlayerLine] {
        let share = last == 0 ? 1 : Double(minute) / Double(last)
        func part(_ value: Int) -> Int { Int((Double(value) * share).rounded()) }
        return finals.enumerated().map { index, final in
            PlayerLine(role: final.role, champion: final.champion, name: final.name, level: max(1, part(final.level)),
                       kills: kills.filter { $0.minute <= minute && $0.player == index }.count,
                       deaths: part(final.deaths), assists: part(final.assists), creepScore: part(final.creepScore),
                       gold: 500 + part(final.gold - 500))
        }
    }
}
```

- [ ] **Step 6: Écrire les vues**

Créer `App/Timeline/TimelineCard.swift` :

```swift
import LoLKit
import SwiftUI

/// Une équipe de la game telle que le fil et la courbe la montrent : code et couleur (Vitrail si suivie).
struct TimelineTeam: Equatable {
    let id: String
    let code: String
    let tint: Color
}

/// Fil des événements de la game (spec fonctionnalités §4) : du plus récent au plus ancien, temps de jeu, icône de la DA
/// (épées, drake, baron, tour, inhibiteur), équipe à sa couleur. Dix lignes, puis « Tout le fil ». N'existe que pour un
/// match non masqué.
struct TimelineCard: View {
    /// Événements dans l'ordre chronologique (`TimelineStore.events`).
    let events: [TimelineEvent]
    /// Les deux équipes, dans l'ordre d'affichage.
    let teams: [TimelineTeam]
    /// Relecture en cours : gabarit tant que rien n'est arrivé.
    var loading = false
    @State private var expanded = false

    static let collapsedCount = 10

    var body: some View {
        let recent = Array(events.reversed())
        let shown = expanded ? recent : Array(recent.prefix(Self.collapsedCount))
        VStack(alignment: .leading, spacing: 10) {
            StatLabel(icon: .swords, text: "Fil de la game")
                .frame(maxWidth: .infinity, alignment: .leading)
            if recent.isEmpty {
                if loading {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBlock(height: 14)
                    }
                } else {
                    Text("Rien de marquant pour l'instant")
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, event in
                row(event)
            }
            if recent.count > Self.collapsedCount {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? "Réduire le fil" : "Tout le fil (\(recent.count))")
                        .font(Typo.secondaryMedium)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func row(_ event: TimelineEvent) -> some View {
        let team = teams.first { $0.id == event.teamId }
        let tint = team?.tint ?? Palette.secondary
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Format.clock(event.gameTime))
                .font(Typo.secondaryMedium)
                .foregroundStyle(Palette.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            IconView(icon: Self.icon(event.kind), size: 14)
                .foregroundStyle(tint)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(team?.code ?? "")
                .font(Typo.secondaryMedium)
                .foregroundStyle(tint)
            Text(TimelineText.text(event))
                .font(Typo.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Icône de la DA de chaque événement.
    static func icon(_ kind: TimelineEvent.Kind) -> Icon {
        switch kind {
        case .kills: return .swords
        case .dragon: return .drake
        case .baron: return .baron
        case .tower: return .tower
        case .inhibitor: return .inhib
        }
    }
}
```

Créer `App/Timeline/GoldChartCard.swift` (si le compilateur peine sur le `Chart` — « unable to type-check this expression in reasonable time » —, sortir les marques dans des propriétés `@ChartContentBuilder private var areas: some ChartContent` et `markersContent`, sans rien changer d'autre) :

```swift
import Charts
import LoLKit
import SwiftUI

/// Courbe de l'écart de gold (spec fonctionnalités §5), Swift Charts : au-dessus de zéro quand l'équipe de gauche mène, à
/// sa couleur ; en dessous quand c'est l'autre, à la sienne ; repères des drakes et des barons du fil. En direct, elle
/// s'allonge à chaque frame. N'existe que pour un match non masqué.
struct GoldChartCard: View {
    /// Écart réorienté vers l'équipe de gauche (`TimelineStore.goldPoints(gameId:orientedTo:)`).
    let points: [GoldPoint]
    /// Drakes et barons du fil (`TimelineText.isMarker`).
    let markers: [TimelineEvent]
    /// Les deux équipes, dans l'ordre d'affichage (gauche = au-dessus de zéro).
    let teams: [TimelineTeam]
    var loading = false

    /// Hauteur de la courbe (et de son gabarit).
    static let height: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatLabel(icon: .gold, text: "Écart de gold")
                Spacer(minLength: 8)
                if let last = points.last, let leader = leaderText(last.difference) {
                    Text(leader)
                        .font(Typo.secondaryMedium)
                        .foregroundStyle(last.difference >= 0 ? tint(0) : tint(1))
                        .monospacedDigit()
                        .numericChange(last.difference)
                }
            }
            if points.count >= 2 {
                chart
                    .frame(height: Self.height)
            } else if loading {
                SkeletonBlock(height: Self.height, radius: 12)
            } else {
                Text("La courbe se dessine après quelques minutes de jeu")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func tint(_ index: Int) -> Color {
        teams.indices.contains(index) ? teams[index].tint : Palette.secondary
    }

    /// « KC +2,1k » ; « Égalité » à zéro.
    private func leaderText(_ difference: Int) -> String? {
        guard teams.count == 2 else { return nil }
        if difference == 0 { return "Égalité" }
        return "\(teams[difference > 0 ? 0 : 1].code) +\(Format.gold(abs(difference)))"
    }

    private var chart: some View {
        let data = GoldChartData.withZeroCrossings(points)
        let limit = GoldChartData.axisLimit(points)
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("Temps", point.gameTime), yStart: .value("Base", 0),
                         yEnd: .value("Écart", max(0, point.difference)))
                    .foregroundStyle(by: .value("Équipe", "gauche"))
                AreaMark(x: .value("Temps", point.gameTime), yStart: .value("Base", 0),
                         yEnd: .value("Écart", min(0, point.difference)))
                    .foregroundStyle(by: .value("Équipe", "droite"))
                LineMark(x: .value("Temps", point.gameTime), y: .value("Écart", point.difference))
                    .foregroundStyle(Palette.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Égalité", 0))
                .foregroundStyle(Palette.glassBorder)
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(Array(markers.enumerated()), id: \.offset) { _, event in
                RuleMark(x: .value("Temps", event.gameTime))
                    .foregroundStyle(Palette.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, spacing: 2) {
                        IconView(icon: TimelineCard.icon(event.kind), size: 10)
                            .foregroundStyle(teams.first { $0.id == event.teamId }?.tint ?? Palette.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: ["gauche", "droite"], range: [tint(0).opacity(0.45), tint(1).opacity(0.45)])
        .chartLegend(.hidden)
        .chartYScale(domain: -limit...limit)
        .chartXAxis {
            AxisMarks(values: .stride(by: 600)) { value in
                AxisGridLine().foregroundStyle(Palette.glassBorder.opacity(0.4))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text("\(Int(seconds / 60))'")
                            .font(Typo.label)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [-limit, 0, limit]) { value in
                AxisGridLine().foregroundStyle(Palette.glassBorder.opacity(0.4))
                AxisValueLabel {
                    if let gold = value.as(Int.self) {
                        Text(Format.goldDiff(gold))
                            .font(Typo.label)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(leaderText(points.last?.difference ?? 0).map { "Écart de gold : \($0)" } ?? "Écart de gold")
    }
}
```

- [ ] **Step 7: Écrire l'aperçu**

Créer `Tests/FailleTests/TimelineSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Fil des événements et courbe de l'écart de gold (spec fonctionnalités §4, §5) : la game en direct d'exemple (KC en
    /// tête), puis une game jouée gagnée par l'équipe de droite (courbe sous zéro), et le gabarit de chargement.
    @Test func timelineBoard() async throws {
        let live = SampleData.kcSnapshot
        let store = TimelineStore(preview: [
            live.gameId: TimelineSamples.frames(.kcLive, start: SampleData.kcGameStart, final: live) + [live],
            "fini": TimelineSamples.frames(.redWins, start: SampleData.kcGameStart, final: GameSnapshot(
                gameId: "fini", phase: .finished, timestamp: live.timestamp, blueTeamId: "kc", redTeamId: "c9",
                blue: live.blue, red: live.red, bluePlayers: live.bluePlayers, redPlayers: live.redPlayers)),
        ])
        let teams = [TimelineTeam(id: "kc", code: "KC", tint: Palette.team("#5B8CFF")),
                     TimelineTeam(id: "c9", code: "C9", tint: Palette.secondary)]
        func chart(_ gameId: String) -> GoldChartCard {
            GoldChartCard(points: store.goldPoints(gameId: gameId, orientedTo: "kc"),
                          markers: store.events(gameId: gameId).filter(TimelineText.isMarker), teams: teams)
        }
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Fil et courbe", subtitle: "En direct · game jouée · chargement")
                chart(live.gameId)
                TimelineCard(events: store.events(gameId: live.gameId), teams: teams)
                chart("fini")
                GoldChartCard(points: [], markers: [], teams: teams, loading: true)
                TimelineCard(events: [], teams: teams, loading: true)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "19-fil-et-courbe")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 8: Vérifier le périmètre, committer, pousser**

```bash
git status --short
```

Expected : seulement `?? App/Timeline/`, `?? Tests/FailleTests/TimelineStoreTests.swift`, `?? Tests/FailleTests/TimelineSnapshotTests.swift`.

```bash
git add App/Timeline Tests/FailleTests/TimelineStoreTests.swift Tests/FailleTests/TimelineSnapshotTests.swift
git commit -m "feat(app): fil des événements et courbe de l'écart de gold — relecture à pas de 60 s gardée sur disque, direct, Swift Charts" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t4-fil-courbe
```

- [ ] **Step 9: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
```

Expected : jobs verts ; suite `TimelineStoreTests` (9 tests) verte ; `19-fil-et-courbe.png` : courbe au-dessus de zéro à la couleur de KC (+2,1k, repères drakes), fil de 10 lignes (« 18:09 · KC · Kill · KC Bot », drakes…) et « Tout le fil (…) », courbe sous zéro à la couleur secondaire (C9 +15,2k), puis deux gabarits de chargement. Échec : `gh run view "$RUN" --log-failed`, corriger, commit, push, relancer.


### Task 5: Sorts d'invocateur des games terminées (Leaguepedia, règle stricte, disque)

**Branche :** `fonc/appli-t5-sorts` · **Vague :** B · **Dépendances :** T3 (`DiskCache`) fusionnée dans `main`.

**Files:**
- Create: `App/Spells/SpellSchedule.swift`, `App/Spells/SummonerSpellsStore.swift`
- Modify (documentation seulement, journal du lot LoLKit) : `LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift` (docs de `summonerSpells(champions:around:)` et `scoreboard(around:)`), `LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift` (doc de `match(champions:around:rows:)`) — **T5 est la seule tâche qui touche ces deux fichiers.**
- Test: `Tests/FailleTests/SummonerSpellsTests.swift`

**Interfaces:**
- Consumes : T3 `DiskCache` (`load(_:from:)`, `save(_:to:)`) ; LoLKit `LoLClient(transport:)`, `LoLClient.window(gameId:startingTime: nil)`, `LiveWindow.firstFrameTime`, `LiveWindow.gameMetadata.blueTeamMetadata.participantMetadata[].championId` (idem rouge), `LeaguepediaClient(transport:)`, `LeaguepediaClient.scoreboard(around start: Date) async throws -> [ScoreboardRow]` (une requête, ± 3 h, en-tête `User-Agent: Faille (usage personnel)`), `LeaguepediaError.rateLimited`, `SpellMatcher.match(champions: [String], around: Date, rows: [ScoreboardRow]) -> [String: [String]]?`, `struct SpellLookupPolicy: Codable` (`init()`, `canAttempt(now:)`, `mutating record(now:outcome:)`, `lastAttempt`, `attempts`, `lastWasRateLimited`, `succeeded`, `enum Outcome { success, rateLimited, failure }`) ; tests `ScriptedTransport(mode:extra:)`, `LoLDate.parse(_:)`.
- Produces :
  - `enum SpellSchedule` : `delayAfterEnd` (30 min), `gapBetweenAttempts` (1 h), `assumedGameLength` (1 h), `static func earliestAttempt(matchEnd: Date?, lastGameStart: Date) -> Date`, `static func mayAttempt(_ policy: SpellLookupPolicy, earliest: Date, now: Date) -> Bool`, `static func center(of starts: [Date]) -> Date?`.
  - `struct SpellRecord: Codable, Sendable, Equatable { var policy: SpellLookupPolicy; var openings: [String: Opening]; var spells: [String: [String: [String]]] }` (`struct Opening { start: Date; champions: [String] }`).
  - `@MainActor @Observable final class SummonerSpellsStore` : `init(transport: (any HTTPTransport)?, cache: DiskCache?)`, `init(preview spells: [String: [String: [String]]])`, `private(set) var spells: [String: [String: [String]]]` (game → champion → ids des sorts), `func spells(gameId: String, championId: String) -> [String]?`, `func lookUp(matchId: String, gameIds: [String], matchEnd: Date?, now: Date = Date()) async`, `static func path(_ matchId: String) -> String`.

- [ ] **Step 1: Écrire les tests**

Créer `Tests/FailleTests/SummonerSpellsTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Deux games d'un match terminé : champions (ids Data Dragon du flux, noms Leaguepedia) et début de chaque game.
private let games: [(id: String, start: String, champions: [(feed: String, wiki: String, spells: String)])] = [
    ("G1", "2026-10-04T18:02:00.000Z", [
        ("KSante", "K'Sante", "Flash,Teleport"), ("LeeSin", "Lee Sin", "Flash,Smite"), ("Ahri", "Ahri", "Flash,Ignite"),
        ("Kalista", "Kalista", "Flash,Heal"), ("Rakan", "Rakan", "Flash,Ignite"), ("Gnar", "Gnar", "Flash,Teleport"),
        ("Vi", "Vi", "Flash,Smite"), ("Orianna", "Orianna", "Flash,Teleport"), ("Varus", "Varus", "Flash,Cleanse"),
        ("Braum", "Braum", "Flash,Exhaust"),
    ]),
    ("G2", "2026-10-04T18:55:00.000Z", [
        ("Rumble", "Rumble", "Flash,Teleport"), ("XinZhao", "Xin Zhao", "Flash,Smite"), ("Taliyah", "Taliyah", "Flash,Ignite"),
        ("Kaisa", "Kai'Sa", "Flash,Heal"), ("Rell", "Rell", "Flash,Ignite"), ("Renekton", "Renekton", "Flash,Teleport"),
        ("Sejuani", "Sejuani", "Flash,Smite"), ("Azir", "Azir", "Flash,Teleport"), ("Ezreal", "Ezreal", "Flash,Heal"),
        ("Nautilus", "Nautilus", "Flash,Ignite"),
    ]),
]

/// Fenêtre de début d'une game (forme réelle de `window` : 5 joueurs par équipe, une frame).
private func openingJSON(_ game: (id: String, start: String, champions: [(feed: String, wiki: String, spells: String)])) -> String {
    func team(_ id: String, _ offset: Int) -> String {
        let players = (0..<5).map { index in
            #"{"participantId":\#(offset + index),"summonerName":"P\#(offset + index)","championId":"\#(game.champions[offset + index - 1].feed)","role":"top"}"#
        }
        return #"{"esportsTeamId":"\#(id)","participantMetadata":[\#(players.joined(separator: ","))]}"#
    }
    let frameTeam = #"{"totalGold":2500,"inhibitors":0,"towers":0,"barons":0,"totalKills":0,"dragons":[],"participants":[]}"#
    return #"{"esportsGameId":"\#(game.id)","esportsMatchId":"M1","gameMetadata":{"patchVersion":"16.18.819.1060","blueTeamMetadata":\#(team("kc", 1)),"redTeamMetadata":\#(team("g2", 6))},"frames":[{"rfc460Timestamp":"\#(game.start)","gameState":"in_game","blueTeam":\#(frameTeam),"redTeam":\#(frameTeam)}]}"#
}

/// Réponse Cargo de Leaguepedia pour les games données (forme réelle de `ScoreboardPlayers`).
private func scoreboardJSON(_ ids: [String]) -> String {
    let rows = games.filter { ids.contains($0.id) }.flatMap { game in
        game.champions.map { champion in
            let date = game.start.replacingOccurrences(of: "T", with: " ").prefix(19)
            return #"{"title":{"GameId":"Worlds_\#(game.id)","Link":"Joueur","Champion":"\#(champion.wiki)","SummonerSpells":"\#(champion.spells)","DateTime UTC":"\#(date)"}}"#
        }
    }
    return #"{"cargoquery":[\#(rows.joined(separator: ","))]}"#
}

/// Faux réseau : débuts des games G1 et G2, et Leaguepedia qui répond `wiki` (games trouvées, ou refus).
private func spellsTransport(wiki: @escaping @Sendable () -> String) -> ScriptedTransport {
    ScriptedTransport(extra: { url in
        if url.host() == "lol.fandom.com" {
            return HTTPResponse(status: 200, body: Data(wiki().utf8))
        }
        for game in games where url.path.hasSuffix("/window/\(game.id)") {
            return HTTPResponse(status: 200, body: Data(openingJSON(game).utf8))
        }
        return nil
    })
}

/// Sorts d'invocateur des games terminées (spec fonctionnalités §3) : une requête Leaguepedia par match, jamais avant
/// 30 min après la fin, une heure au moins entre deux essais, gardés sur disque.
@MainActor
@Suite(.serialized)
struct SummonerSpellsTests {
    private static let end = LoLDate.parse("2026-10-04T19:30:00.000Z")!

    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-spells-\(UUID().uuidString)", isDirectory: true))
    }

    private static func wikiRequests(_ transport: ScriptedTransport) async -> Int {
        await transport.requests.filter { $0.host() == "lol.fandom.com" }.count
    }

    @Test func scheduleWaitsForTheEndAndSpacesAttempts() {
        let start = Self.end.addingTimeInterval(-1_800)
        #expect(SpellSchedule.earliestAttempt(matchEnd: Self.end, lastGameStart: start) == Self.end.addingTimeInterval(1_800))
        #expect(SpellSchedule.earliestAttempt(matchEnd: nil, lastGameStart: start) == start.addingTimeInterval(5_400))
        let earliest = Self.end.addingTimeInterval(1_800)
        var policy = SpellLookupPolicy()
        #expect(!SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(-60)))
        #expect(SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest))
        policy.record(now: earliest, outcome: .failure)
        // La règle de LoLKit permettrait un essai 10 min plus tard ; l'appli attend une heure.
        #expect(!SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(30 * 60)))
        #expect(SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(3_600)))
        policy.record(now: earliest.addingTimeInterval(3_600), outcome: .success)
        #expect(!SpellSchedule.mayAttempt(policy, earliest: earliest, now: earliest.addingTimeInterval(9 * 3_600)))
        #expect(SpellSchedule.center(of: [Self.end, Self.end.addingTimeInterval(7_200)]) == Self.end.addingTimeInterval(3_600))
        #expect(SpellSchedule.center(of: []) == nil)
    }

    @Test func oneWikiRequestCoversTheWholeMatchAndIsKept() async {
        let cache = Self.cache()
        let transport = spellsTransport { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: cache)
        let now = Self.end.addingTimeInterval(3_600)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now)
        #expect(await Self.wikiRequests(transport) == 1)
        #expect(store.spells(gameId: "G1", championId: "LeeSin") == ["SummonerFlash", "SummonerSmite"])
        #expect(store.spells(gameId: "G2", championId: "Kaisa") == ["SummonerFlash", "SummonerHeal"])

        // Trouvés : plus jamais de requête, ni ici ni au prochain lancement.
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now.addingTimeInterval(7_200))
        let offline = ScriptedTransport(mode: .failing)
        let reopened = SummonerSpellsStore(transport: offline, cache: cache)
        await reopened.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: now.addingTimeInterval(9_000))
        #expect(reopened.spells(gameId: "G1", championId: "Vi") == ["SummonerFlash", "SummonerSmite"])
        #expect(await offline.requests.isEmpty)
        #expect(await Self.wikiRequests(transport) == 1)
    }

    /// Trop tôt (moins de 30 min après la fin connue) : aucune requête, même au flux.
    @Test func tooEarlyAsksNothing() async {
        let transport = spellsTransport { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: Self.cache())
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: Self.end.addingTimeInterval(600))
        #expect(await transport.requests.isEmpty)
        #expect(store.spells.isEmpty)
    }

    /// Fin inconnue : les débuts des games sont lus (flux), mais le wiki attend la fin estimée + 30 min.
    @Test func unknownEndWaitsForTheEstimate() async {
        let transport = spellsTransport { scoreboardJSON(["G1", "G2"]) }
        let store = SummonerSpellsStore(transport: transport, cache: Self.cache())
        let lastStart = LoLDate.parse("2026-10-04T18:55:00.000Z")!
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: lastStart.addingTimeInterval(3_600))
        #expect(await transport.requests.count == 2)
        #expect(await Self.wikiRequests(transport) == 0)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: lastStart.addingTimeInterval(5_400))
        #expect(await Self.wikiRequests(transport) == 1)
        #expect(await transport.requests.count == 3) // débuts déjà connus
    }

    /// Refus du wiki : noté ; pas de nouvel essai avant une heure ; une game absente du wiki garde l'autre.
    @Test func refusalAndMissingGameAreAttemptsWithoutLoops() async {
        let cache = Self.cache()
        let refusing = spellsTransport { #"{"error":{"code":"ratelimited","info":"Rate limit"}}"# }
        let store = SummonerSpellsStore(transport: refusing, cache: cache)
        let first = Self.end.addingTimeInterval(1_800)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: first)
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: first.addingTimeInterval(2_400))
        #expect(await Self.wikiRequests(refusing) == 1)
        #expect(cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1"))?.policy.lastWasRateLimited == true)

        let partial = spellsTransport { scoreboardJSON(["G1"]) }
        let later = SummonerSpellsStore(transport: partial, cache: cache)
        await later.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: Self.end, now: first.addingTimeInterval(3_600))
        #expect(await Self.wikiRequests(partial) == 1)
        #expect(later.spells(gameId: "G1", championId: "Ahri") == ["SummonerFlash", "SummonerDot"])
        #expect(later.spells(gameId: "G2", championId: "Azir") == nil)
        let record = cache.load(SpellRecord.self, from: SummonerSpellsStore.path("M1"))
        #expect(record?.policy.attempts == 2)
        #expect(record?.policy.succeeded == false)
    }

    @Test func previewStoreNeverAsks() async {
        let store = SummonerSpellsStore(preview: ["G1": ["LeeSin": ["SummonerFlash", "SummonerSmite"]]])
        await store.lookUp(matchId: "M1", gameIds: ["G1", "G2"], matchEnd: nil, now: Self.end.addingTimeInterval(86_400))
        #expect(store.spells(gameId: "G1", championId: "LeeSin") == ["SummonerFlash", "SummonerSmite"])
        #expect(store.spells(gameId: "G2", championId: "Azir") == nil)
    }
}
```

- [ ] **Step 2: Écrire la règle de l'appli**

Créer `App/Spells/SpellSchedule.swift` :

```swift
import Foundation
import LoLKit

/// Quand interroger Leaguepedia pour les sorts d'invocateur d'un match (spec fonctionnalités §3 ; journal du lot LoLKit) :
/// la règle de LoLKit (`SpellLookupPolicy` : 3 essais, 10 min d'écart, 30 min après un refus, plus rien après un succès),
/// plus celle de l'appli — premier essai 30 min au moins après la fin du match (le wiki n'a pas la game avant ; « pas
/// encore sur le wiki » compte comme un essai), essais espacés d'une heure au moins.
enum SpellSchedule {
    static let delayAfterEnd: TimeInterval = 30 * 60
    static let gapBetweenAttempts: TimeInterval = 60 * 60
    /// Fin estimée d'un match dont la frame `finished` n'est pas connue : début de sa dernière game + 1 h (une game
    /// professionnelle dure moins d'une heure ; l'estimation ne fait que retarder le premier essai).
    static let assumedGameLength: TimeInterval = 60 * 60

    /// Premier essai permis : 30 min après la fin du match (sa frame `finished` si on l'a, sinon l'estimation).
    static func earliestAttempt(matchEnd: Date?, lastGameStart: Date) -> Date {
        (matchEnd ?? lastGameStart.addingTimeInterval(assumedGameLength)).addingTimeInterval(delayAfterEnd)
    }

    /// Une requête est-elle permise à `now` ? Jamais avant `earliest`, jamais si `SpellLookupPolicy` la refuse, jamais
    /// moins d'une heure après la précédente.
    static func mayAttempt(_ policy: SpellLookupPolicy, earliest: Date, now: Date) -> Bool {
        guard now >= earliest, policy.canAttempt(now: now) else { return false }
        guard let last = policy.lastAttempt else { return true }
        return now.timeIntervalSince(last) >= gapBetweenAttempts
    }

    /// Centre de la requête (± 3 h, `SpellMatcher.window`) : le milieu entre le début de la première et de la dernière game
    /// du match ; une série dont les games commencent à moins de 6 h d'écart est couverte en une seule requête.
    static func center(of starts: [Date]) -> Date? {
        guard let first = starts.min(), let last = starts.max() else { return nil }
        return first.addingTimeInterval(last.timeIntervalSince(first) / 2)
    }
}
```

- [ ] **Step 3: Écrire le store**

Créer `App/Spells/SummonerSpellsStore.swift` :

```swift
import Foundation
import LoLKit
import Observation

/// Ce que Faille garde sur disque pour les sorts d'invocateur d'un match (`spells/<matchId>.json`).
struct SpellRecord: Codable, Sendable, Equatable {
    /// Début et champions d'une game (fenêtre du flux lue sans `startingTime`) : ce qui la retrouve dans Leaguepedia.
    struct Opening: Codable, Sendable, Equatable {
        let start: Date
        /// Ids Data Dragon des 10 champions de la game.
        let champions: [String]
    }

    var policy = SpellLookupPolicy()
    var openings: [String: Opening] = [:]
    /// Sorts trouvés, par game puis par champion.
    var spells: [String: [String: [String]]] = [:]
}

/// Sorts d'invocateur des games terminées (spec fonctionnalités §3), absents du flux de Riot : une seule requête
/// Leaguepedia par match pour toutes ses games, rapprochées par `SpellMatcher` (mêmes 10 champions, ± 3 h), sous la règle
/// stricte de `SpellSchedule` (Leaguepedia limite fortement les requêtes anonymes). Tout est gardé sur disque.
/// Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué, ni pour un match qui n'est pas terminé.
@MainActor
@Observable
final class SummonerSpellsStore {
    /// Sorts par game puis par champion (id Data Dragon du flux) : ids Data Dragon des sorts (« SummonerFlash »).
    private(set) var spells: [String: [String: [String]]] = [:]

    private let client: LoLClient?
    private let wiki: LeaguepediaClient?
    private let cache: DiskCache?
    @ObservationIgnored private var running: Set<String> = []

    /// - Parameters:
    ///   - transport: réseau (flux livestats et Leaguepedia) ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil : rien n'est gardé (et la règle repart de zéro à chaque lancement).
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        client = transport.map { LoLClient(transport: $0) }
        wiki = transport.map { LeaguepediaClient(transport: $0) }
        self.cache = cache
    }

    /// Aperçus : sorts figés, aucune requête.
    init(preview spells: [String: [String: [String]]]) {
        client = nil
        wiki = nil
        cache = nil
        self.spells = spells
    }

    /// Sorts d'un champion dans une game terminée ; nil s'ils ne sont pas (encore) connus.
    func spells(gameId: String, championId: String) -> [String]? {
        spells[gameId]?[championId]
    }

    /// Sorts des games jouées d'un match terminé. Rien si toutes sont déjà connues. Sinon, si la règle le permet : le début
    /// et les champions de chaque game (flux, une fois par game), puis UNE requête Leaguepedia centrée sur le match, notée
    /// dans la règle (succès seulement si toutes les games sont trouvées ; un refus du wiki est noté comme tel). Les sorts
    /// trouvés sont gardés même si d'autres games manquent.
    /// - Parameters:
    ///   - gameIds: games jouées du match (`completed`).
    ///   - matchEnd: frame `finished` de sa dernière game, si l'appli l'a ; sinon fin estimée (`SpellSchedule`).
    func lookUp(matchId: String, gameIds: [String], matchEnd: Date?, now: Date = Date()) async {
        guard !gameIds.isEmpty, !running.contains(matchId) else { return }
        running.insert(matchId)
        defer { running.remove(matchId) }
        var record = cache?.load(SpellRecord.self, from: Self.path(matchId)) ?? SpellRecord()
        publish(record)
        guard let client, let wiki, gameIds.contains(where: { record.spells[$0] == nil }) else { return }
        // La règle d'abord : aucune requête (même au flux) si un essai n'est pas permis.
        let knownEarliest = matchEnd.map { $0.addingTimeInterval(SpellSchedule.delayAfterEnd) } ?? .distantPast
        guard SpellSchedule.mayAttempt(record.policy, earliest: knownEarliest, now: now) else { return }
        for gameId in gameIds where record.openings[gameId] == nil {
            guard let opening = try? await client.window(gameId: gameId, startingTime: nil),
                  let start = opening.firstFrameTime else { return }
            let metadata = opening.gameMetadata
            let champions = (metadata.blueTeamMetadata.participantMetadata
                + metadata.redTeamMetadata.participantMetadata).compactMap(\.championId)
            record.openings[gameId] = SpellRecord.Opening(start: start, champions: champions)
            cache?.save(record, to: Self.path(matchId))
        }
        let starts = gameIds.compactMap { record.openings[$0]?.start }
        guard let lastStart = starts.max(), let center = SpellSchedule.center(of: starts),
              SpellSchedule.mayAttempt(record.policy,
                                       earliest: SpellSchedule.earliestAttempt(matchEnd: matchEnd, lastGameStart: lastStart),
                                       now: now) else { return }
        let outcome: SpellLookupPolicy.Outcome
        do {
            let rows = try await wiki.scoreboard(around: center)
            for gameId in gameIds {
                guard let opening = record.openings[gameId],
                      let found = SpellMatcher.match(champions: opening.champions, around: opening.start, rows: rows)
                else { continue }
                record.spells[gameId] = found
            }
            outcome = gameIds.allSatisfy { record.spells[$0] != nil } ? .success : .failure
        } catch LeaguepediaError.rateLimited {
            outcome = .rateLimited
        } catch {
            // Réseau, HTTP, API, ou requête annulée après son envoi : un essai compté, jamais de boucle.
            outcome = .failure
        }
        record.policy.record(now: now, outcome: outcome)
        cache?.save(record, to: Self.path(matchId))
        publish(record)
    }

    private func publish(_ record: SpellRecord) {
        for (gameId, found) in record.spells {
            spells[gameId] = found
        }
    }

    static func path(_ matchId: String) -> String {
        "spells/\(matchId).json"
    }
}
```

- [ ] **Step 4: Rappels anti-spoiler dans LoLKit (journal du lot LoLKit)**

Dans `LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift` :

1. Remplacer :

```swift
    /// wiki n'a pas (encore) la game.
```

par :

```swift
    /// wiki n'a pas (encore) la game.
    /// Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué (les sorts sont ceux d'une game jouée).
```

2. Remplacer :

```swift
    /// Lignes `ScoreboardPlayers` des games commencées à ± 3 h de `start` (une seule requête, 500 lignes au plus).
```

par :

```swift
    /// Lignes `ScoreboardPlayers` des games commencées à ± 3 h de `start` (une seule requête, 500 lignes au plus).
    /// Anti-spoiler : jamais pour un match masqué, et seulement quand `SpellLookupPolicy` le permet.
```

Dans `LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift` :

Remplacer :

```swift
    /// wiki n'a pas encore la game) ou si `champions` contient un doublon.
```

par :

```swift
    /// wiki n'a pas encore la game) ou si `champions` contient un doublon.
    /// Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué.
```

Run : `bash scripts/lolkit.sh test --filter LeaguepediaTests`
Expected : suite verte, inchangée (documentation seulement).

- [ ] **Step 5: Vérifier le périmètre, committer, pousser**

```bash
git status --short
```

Expected : seulement `?? App/Spells/`, `?? Tests/FailleTests/SummonerSpellsTests.swift`, ` M LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift`, ` M LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift`.

```bash
git add App/Spells Tests/FailleTests/SummonerSpellsTests.swift LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift \
  LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift
git commit -m "feat(app): sorts d'invocateur des games terminées — une requête Leaguepedia par match, 30 min après la fin, une heure entre deux essais, gardés sur disque" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t5-sorts
```

**Aucune requête réelle à Leaguepedia pendant le développement** (le wiki limite fortement les requêtes anonymes ; ruling 4 du lot LoLKit) : les tests passent par `ScriptedTransport`.

- [ ] **Step 6: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
LK=$(gh run list --workflow LoLKit --branch fonc/appli-t5-sorts --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$LK"
gh run watch --exit-status "$LK"
```

Expected : workflow `iOS` vert (suite `SummonerSpellsTests`, 6 tests) ; workflow `LoLKit` vert. Échec : `gh run view <id> --log-failed`, corriger, commit, push, relancer.


### Task 6: Draft et builds (détails par joueur, section « Joueurs » enrichie, fiche du joueur)

**Branche :** `fonc/appli-t6-builds` · **Vague :** B · **Dépendances :** T3 (`DiskCache`, `DataDragonStore`, `DDragonIcon`, `\.dataDragon`) fusionnée dans `main`.

**Files:**
- Create: `App/Builds/GameDetailsStore.swift`, `App/Builds/PlayerBuilds.swift`, `App/Builds/BuildSamples.swift`, `App/Builds/DraftStrip.swift`, `App/Builds/BuildPlayersPanel.swift`, `App/Builds/PlayerSheet.swift`
- Test: `Tests/FailleTests/BuildsTests.swift`, `Tests/FailleTests/BuildsSnapshotTests.swift` (aperçus `20-joueurs.png`, `20b-fiche-joueur.png`)

**Interfaces:**
- Consumes : T3 `DiskCache`, `DataDragonStore.champion(version:championId:) async -> ChampionSpells?`, `EnvironmentValues.dataDragon`, `DDragonIcon(url:size:radius:fallback:)`, `DDragonIcon.initials(_:)` ; LoLKit `LoLClient.details(gameId: String, now: Date) async throws -> GameDetails` (recul de 80 s partagé avec `window`), `LoLClient.detailsInterval` (60), `GameDetails(frames:)` (`Codable`), `.latestFrame`, `.latest(participantId:) -> ParticipantDetails?`, `DetailsFrame(rfc460Timestamp:participants:)`, `ParticipantDetails(participantId:level:kills:deaths:assists:creepScore:totalGoldEarned:killParticipation:championDamageShare:wardsPlaced:wardsDestroyed:items:perkMetadata:abilities:)`, `PerkMetadata(styleId:subStyleId:perks:)`, `.keystone`, `ItemCatalog.inventory(_:) -> ItemCatalog.Inventory`, `ItemCatalog.Inventory(items:trinket:)`, `ItemCatalog(version:items:)`, `ItemCatalog.Item(id:name:image:isTrinket:)`, `RuneCatalog.rune(_:)` / `.style(_:)` (`Entry { id, key, name, icon }`), `SummonerCatalog.spell(_:)`, `ChampionSpells.spell(forAbility:)`, `.name`, `DataDragon.championImage/itemImage/summonerSpellImage/runeIcon/spellImage`, `GameSnapshot.bluePlayers` / `.redPlayers` / `.players(for:)`, `PlayerLine`, `MatchTeam`, `Format.champion/.kda/.gold/.role`, `LoLAPIError.statsDisabled` ; appli `SampleData.kcSnapshot`, `SampleData.live`, `StatLabel`, `SectionLabel`, `SkeletonBlock`, `Palette`, `Typo`, `Sora.font`, `Radius.inner`, `.glassCard(tint:radius:padding:)`, `.buttonStyle(.pressable)`, `.abyssBackground()`.
- Produces :
  - `struct SavedDetails: Codable, Sendable, Equatable { let details: GameDetails; let isFinal: Bool }` ; `@MainActor @Observable final class GameDetailsStore` : `init(transport: (any HTTPTransport)?, cache: DiskCache?)`, `init(preview details: [String: GameDetails])`, `private(set) var details: [String: GameDetails]`, `unavailable: Set<String>`, `func refresh(gameId: String, finished: Bool, now: Date = Date()) async`, `func follow(gameId: String, finished: Bool) async`, `static func path(_:) -> String`.
  - `struct PlayerBuild: Identifiable, Equatable, Sendable { participantId: Int; line: PlayerLine; details: ParticipantDetails?; var level: Int }` ; `enum PlayerBuilds` : `knownTrinkets`, `rows(snapshot:details:teamId:) -> [PlayerBuild]`, `draft(snapshot:teamIds:) -> [[String]]`, `inventory(_:catalog:) -> ItemCatalog.Inventory`, `slots(_:) -> [Int?]`, `summonerSpells(role:leaguepedia:) -> [String]` (Leaguepedia, sinon `["SummonerSmite"]` pour le jungler), `percent(_:) -> String`.
  - `enum BuildSamples { static func details(for snapshot: GameSnapshot) -> GameDetails }`.
  - `struct DraftTeam: Equatable { code: String; tint: Color?; champions: [String] }` ; `struct DraftStrip: View` (`init(teams:version:)`).
  - `struct BuildContext: Equatable` (`version`, `items`, `runes`, `summoners`, `summonerSpells: [String: [String]]` ; `championURL(_:)`, `itemURL(_:)`, `summonerURL(_:)`, `keystone(_:)`, `secondaryTree(_:)`, `spells(for:)`) ; `struct BuildPlayersPanel: View` (`init(teams: [MatchTeam], rows: [[PlayerBuild]], context: BuildContext, selection: Binding<Int>, onSelect: @escaping (PlayerBuild, Int) -> Void)`) ; `struct PlayerBuildRow: View` ; `struct BuildPlayersSkeleton: View`.
  - `struct PlayerSheetItem: Identifiable, Equatable { player: PlayerBuild; teamCode: String; tint: Color?; context: BuildContext; finished: Bool }` ; `struct PlayerSheet: View` (`init(item:)`) ; `struct ShareBar: View` ; `struct AbilityOrderView: View`.

- [ ] **Step 1: Écrire les tests**

Créer `Tests/FailleTests/BuildsTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Flux `details` de la game GD (forme réelle, deux frames, deux joueurs).
private let detailsJSON = """
{"frames":[{"rfc460Timestamp":"2026-10-04T20:38:20.000Z","participants":[{"participantId":1,"level":11,"kills":1,\
"deaths":0,"assists":2,"creepScore":150,"totalGoldEarned":6000,"items":[1054,3340],"perkMetadata":{"styleId":8400,\
"subStyleId":8300,"perks":[8437,8401]},"abilities":["Q","E","W"]}]},{"rfc460Timestamp":"2026-10-04T20:38:29.000Z",\
"participants":[{"participantId":1,"level":12,"kills":2,"deaths":0,"assists":2,"creepScore":160,"totalGoldEarned":6500,\
"killParticipation":0.5,"championDamageShare":0.27,"wardsPlaced":7,"wardsDestroyed":1,"items":[1054,3340,3071],\
"perkMetadata":{"styleId":8400,"subStyleId":8300,"perks":[8437,8401]},"abilities":["Q","E","W","Q"]},\
{"participantId":6,"level":10,"kills":0,"deaths":2,"assists":0,"creepScore":120,"totalGoldEarned":4500,"items":[1055],\
"abilities":["Q"]}]}]}
"""

/// Faux flux `details` de la game GD (404 si `statsDisabled`).
private func detailsTransport(statsDisabled: Bool = false) -> ScriptedTransport {
    ScriptedTransport(extra: { url in
        guard url.path.contains("/details/GD") else { return nil }
        return statsDisabled ? HTTPResponse(status: 404, body: Data())
            : HTTPResponse(status: 200, body: Data(detailsJSON.utf8))
    })
}

/// Draft et builds (spec fonctionnalités §3) : jointure des lignes du flux et du détail par `participantId`, balise à part,
/// sorts d'invocateur (Leaguepedia, sinon Châtiment du jungler), détails gardés sur disque et lus au plus une fois pour
/// une game terminée.
@MainActor
@Suite(.serialized)
struct BuildsTests {
    private static func cache() -> DiskCache {
        DiskCache(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-builds-\(UUID().uuidString)", isDirectory: true))
    }

    private static func detailsRequests(_ transport: ScriptedTransport) async -> Int {
        await transport.requests.filter { $0.path.contains("/details/") }.count
    }

    @Test func rowsJoinTheFeedLinesToTheirDetails() throws {
        let snapshot = SampleData.kcSnapshot
        let details = BuildSamples.details(for: snapshot)
        let blue = PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "kc")
        let red = PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "c9")
        #expect(blue.map(\.participantId) == [1, 2, 3, 4, 5])
        #expect(red.map(\.participantId) == [6, 7, 8, 9, 10])
        #expect(red[0].line.champion == "KSante")
        #expect(red[0].details?.participantId == 6)
        #expect(blue[1].details?.items.contains(3364) == true) // balise du jungler
        #expect(PlayerBuilds.rows(snapshot: snapshot, details: nil, teamId: "kc").allSatisfy { $0.details == nil })
        #expect(PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "g2").isEmpty)
        #expect(PlayerBuilds.draft(snapshot: snapshot, teamIds: ["c9", "kc"])
            == [["KSante", "Vi", "Azir", "Ezreal", "Nautilus"], ["Rumble", "XinZhao", "Taliyah", "Kaisa", "Rell"]])
    }

    @Test func trinketIsSetApartAndSlotsArePadded() {
        let fallback = PlayerBuilds.inventory([1054, 2031, 6692, 1001, 3364, 3071, 1036], catalog: nil)
        #expect(fallback.trinket == 3364)
        #expect(fallback.items == [1054, 2031, 6692, 1001, 3071, 1036])
        let catalog = ItemCatalog(version: "16.18.1", items: [
            3330: ItemCatalog.Item(id: 3330, name: "Poupée épouvantail", image: "3330.png", isTrinket: true),
        ])
        let withCatalog = PlayerBuilds.inventory([1054, 3330], catalog: catalog)
        #expect(withCatalog.trinket == 3330)
        #expect(PlayerBuilds.slots(withCatalog) == [1054, nil, nil, nil, nil, nil])
    }

    @Test func summonerSpellsComeFromTheWikiElseSmiteForTheJungler() {
        #expect(PlayerBuilds.summonerSpells(role: "jungle", leaguepedia: ["SummonerFlash", "SummonerSmite"])
            == ["SummonerFlash", "SummonerSmite"])
        #expect(PlayerBuilds.summonerSpells(role: "jungle", leaguepedia: nil) == ["SummonerSmite"])
        #expect(PlayerBuilds.summonerSpells(role: "mid", leaguepedia: nil).isEmpty)
        #expect(PlayerBuilds.summonerSpells(role: "mid", leaguepedia: []).isEmpty)
        #expect(PlayerBuilds.percent(0.274) == "27 %")
        #expect(PlayerBuilds.percent(nil) == "—")
    }

    @Test func liveDetailsKeepTheLastFrameOnDisk() async {
        let cache = Self.cache()
        let transport = detailsTransport()
        let store = GameDetailsStore(transport: transport, cache: cache)
        await store.refresh(gameId: "GD", finished: false)
        #expect(store.details["GD"]?.frames.count == 1)
        #expect(store.details["GD"]?.latest(participantId: 1)?.items == [1054, 3340, 3071])
        // Game en cours : relue à chaque tour (toutes les 60 s, cadence tenue par `follow`).
        await store.refresh(gameId: "GD", finished: false)
        #expect(await Self.detailsRequests(transport) == 2)
        let saved = cache.load(SavedDetails.self, from: GameDetailsStore.path("GD"))
        #expect(saved?.isFinal == false)
        #expect(saved?.details.frames.count == 1)
    }

    @Test func finishedGameIsReadOnceEver() async {
        let cache = Self.cache()
        let transport = detailsTransport()
        let store = GameDetailsStore(transport: transport, cache: cache)
        await store.refresh(gameId: "GD", finished: true)
        await store.refresh(gameId: "GD", finished: true)
        await store.follow(gameId: "GD", finished: true)
        #expect(await Self.detailsRequests(transport) == 1)

        let offline = ScriptedTransport(mode: .failing)
        let reopened = GameDetailsStore(transport: offline, cache: cache)
        await reopened.refresh(gameId: "GD", finished: true)
        #expect(reopened.details["GD"]?.latest(participantId: 6)?.deaths == 2)
        #expect(await offline.requests.isEmpty)
    }

    @Test func statsDisabledStopsAsking() async {
        let transport = detailsTransport(statsDisabled: true)
        let store = GameDetailsStore(transport: transport, cache: Self.cache())
        await store.refresh(gameId: "GD", finished: false)
        await store.refresh(gameId: "GD", finished: false)
        #expect(store.unavailable.contains("GD"))
        #expect(await Self.detailsRequests(transport) == 1)
    }

    @Test func previewStoreNeverAsks() async {
        let details = BuildSamples.details(for: SampleData.kcSnapshot)
        let store = GameDetailsStore(preview: [SampleData.kcSnapshot.gameId: details])
        await store.refresh(gameId: SampleData.kcSnapshot.gameId, finished: false)
        #expect(store.details[SampleData.kcSnapshot.gameId] == details)
    }
}
```

- [ ] **Step 2: Écrire le store des détails**

Créer `App/Builds/GameDetailsStore.swift` :

```swift
import Foundation
import LoLKit
import Observation

/// Détails d'une game gardés sur disque (`details/<gameId>.json`) : la dernière frame, et si la game était terminée.
struct SavedDetails: Codable, Sendable, Equatable {
    let details: GameDetails
    /// Lus après la fin de la game : définitifs, plus jamais redemandés.
    let isFinal: Bool
}

/// Détails par joueur d'une game (`livestats/v1/details`, spec fonctionnalités §3) : objets, runes, ordre des sorts, part
/// des dégâts, participation, balises. Lourd (~200 Ko par lecture) : relu toutes les 60 s (`LoLClient.detailsInterval`)
/// tant que le Détail d'une game en cours est affiché, une seule fois pour une game terminée ; la dernière frame est
/// gardée sur disque. Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué.
@MainActor
@Observable
final class GameDetailsStore {
    /// Dernière frame connue de chaque game.
    private(set) var details: [String: GameDetails] = [:]
    /// Games dont Riot ne fournit pas les stats (404) : plus aucune requête.
    private(set) var unavailable: Set<String> = []

    private let client: LoLClient?
    private let cache: DiskCache?
    @ObservationIgnored private var finalGames: Set<String> = []

    /// - Parameters:
    ///   - transport: réseau ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil : rien n'est gardé.
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        client = transport.map { LoLClient(transport: $0) }
        self.cache = cache
    }

    /// Aperçus : détails figés, aucune requête.
    init(preview details: [String: GameDetails]) {
        client = nil
        cache = nil
        self.details = details
        finalGames = Set(details.keys)
    }

    /// Une lecture. Le disque d'abord (une game terminée déjà lue après sa fin n'est plus jamais demandée), puis le flux
    /// avec le recul de 80 s partagé avec `window` (`LoLClient.details(gameId:now:)`) ; seule la dernière frame est gardée.
    /// - Parameter finished: la game est terminée : ce qui sera lu est définitif.
    func refresh(gameId: String, finished: Bool, now: Date = Date()) async {
        guard !unavailable.contains(gameId) else { return }
        if !finalGames.contains(gameId), details[gameId] == nil || finished,
           let saved = cache?.load(SavedDetails.self, from: Self.path(gameId)) {
            details[gameId] = saved.details
            if saved.isFinal { finalGames.insert(gameId) }
        }
        guard let client, !finalGames.contains(gameId) else { return }
        do {
            guard let frame = try await client.details(gameId: gameId, now: now).latestFrame else { return }
            let kept = GameDetails(frames: [frame])
            details[gameId] = kept
            if finished { finalGames.insert(gameId) }
            cache?.save(SavedDetails(details: kept, isFinal: finished), to: Self.path(gameId))
        } catch LoLAPIError.statsDisabled {
            unavailable.insert(gameId)
        } catch {
            // Réseau, flux vide, annulation : on garde ce qu'on a ; nouvel essai au tour suivant.
        }
    }

    /// Tant que la tâche vit (Détail affiché) : une lecture, puis, si la game est en cours, une toutes les 60 s.
    func follow(gameId: String, finished: Bool) async {
        await refresh(gameId: gameId, finished: finished)
        guard !finished else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(LoLClient.detailsInterval))
            guard !Task.isCancelled else { return }
            await refresh(gameId: gameId, finished: false)
        }
    }

    static func path(_ gameId: String) -> String {
        "details/\(gameId).json"
    }
}
```

- [ ] **Step 3: Écrire l'assemblage des joueurs et les détails d'exemple**

Créer `App/Builds/PlayerBuilds.swift` :

```swift
import Foundation
import LoLKit

/// Un joueur de la section « Joueurs » (spec fonctionnalités §3) : sa ligne du flux `window` (rôle, champion, pseudo,
/// niveau, KDA, CS, gold), jointe à son détail du flux `details` (objets, runes, ordre des sorts, part des dégâts…) par
/// `participantId`.
struct PlayerBuild: Identifiable, Equatable, Sendable {
    let participantId: Int
    let line: PlayerLine
    /// nil tant que `details` n'est pas lu (les objets et les runes restent alors des cases vides).
    let details: ParticipantDetails?

    var id: Int { participantId }

    /// Niveau le plus frais : celui de `details` s'il est là.
    var level: Int { details?.level ?? line.level }
}

/// Assemblage de la draft et des builds à partir des données déjà chargées (aucune requête ici).
enum PlayerBuilds {
    /// Balises (Totem de vision, Altération : longue-vue, Lentille de l'oracle), quand le catalogue des objets manque.
    static let knownTrinkets: Set<Int> = [3340, 3363, 3364]

    /// Joueurs d'une équipe dans l'ordre du flux, qui donne toujours les joueurs par `participantId` : bleu = 1 à 5,
    /// rouge = 6 à 10. [] si l'équipe ne joue pas cette game.
    static func rows(snapshot: GameSnapshot, details: GameDetails?, teamId: String) -> [PlayerBuild] {
        let first: Int
        let lines: [PlayerLine]
        if teamId == snapshot.blueTeamId {
            first = 1
            lines = snapshot.bluePlayers
        } else if teamId == snapshot.redTeamId {
            first = 6
            lines = snapshot.redPlayers
        } else {
            return []
        }
        return lines.enumerated().map { index, line in
            PlayerBuild(participantId: first + index, line: line, details: details?.latest(participantId: first + index))
        }
    }

    /// Draft : les champions (ids Data Dragon) de chaque équipe, dans l'ordre donné ([] pour une équipe absente).
    static func draft(snapshot: GameSnapshot, teamIds: [String]) -> [[String]] {
        teamIds.map { snapshot.players(for: $0)?.map(\.champion) ?? [] }
    }

    /// Objets d'un joueur, balise à part : par le catalogue Data Dragon (tag « Trinket ») s'il est chargé, sinon par les
    /// ids des balises connues.
    static func inventory(_ items: [Int], catalog: ItemCatalog?) -> ItemCatalog.Inventory {
        if let catalog { return catalog.inventory(items) }
        let trinket = items.first { knownTrinkets.contains($0) }
        return ItemCatalog.Inventory(items: items.filter { $0 != trinket }, trinket: trinket)
    }

    /// Les six cases d'objets (vides à la fin).
    static func slots(_ inventory: ItemCatalog.Inventory) -> [Int?] {
        (0..<6).map { inventory.items.indices.contains($0) ? inventory.items[$0] : nil }
    }

    /// Sorts d'invocateur à montrer : ceux de Leaguepedia (game terminée) ; à défaut, Châtiment pour le jungler — tout
    /// jungler le prend (sans lui, pas d'objet de jungle), ce n'est pas une donnée du flux mais une déduction sûre, qui ne
    /// révèle rien ; sinon aucun.
    static func summonerSpells(role: String, leaguepedia: [String]?) -> [String] {
        if let leaguepedia, !leaguepedia.isEmpty { return leaguepedia }
        return role.lowercased() == "jungle" ? ["SummonerSmite"] : []
    }

    /// « 27 % » ; « — » si la valeur manque.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((min(max(value, 0), 1) * 100).rounded())) %"
    }
}
```

Créer `App/Builds/BuildSamples.swift` :

```swift
import Foundation
import LoLKit

/// Détails par joueur d'exemple (aperçus et tests, aucune requête) : objets, runes et ordre des sorts typiques du rôle de
/// chaque joueur d'une frame, construits avec les inits publics de LoLKit.
enum BuildSamples {
    private struct Kit: Sendable {
        let items: [Int]
        let perks: PerkMetadata
        let abilities: [String]
        let damageShare: Double
        let wards: Int
    }

    private static let mid = Kit(
        items: [6655, 3020, 3157, 1058, 3340],
        perks: PerkMetadata(styleId: 8200, subStyleId: 8300, perks: [8229, 8226, 8210, 8237, 8345, 8347, 5008, 5008]),
        abilities: ["Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"],
        damageShare: 0.31, wards: 9
    )

    private static let kits: [String: Kit] = [
        "top": Kit(items: [3071, 3047, 3053, 1029, 3340],
                   perks: PerkMetadata(styleId: 8400, subStyleId: 8300,
                                       perks: [8437, 8401, 8444, 8451, 8345, 8347, 5008, 5011]),
                   abilities: ["Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"],
                   damageShare: 0.22, wards: 8),
        "jungle": Kit(items: [6692, 3111, 3071, 1036, 3364],
                      perks: PerkMetadata(styleId: 8000, subStyleId: 8400,
                                          perks: [8010, 9111, 9104, 8299, 8444, 8453, 5005, 5008]),
                      abilities: ["Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"],
                      damageShare: 0.16, wards: 14),
        "mid": mid,
        "bottom": Kit(items: [3031, 3006, 3094, 1038, 3363],
                      perks: PerkMetadata(styleId: 8000, subStyleId: 8100,
                                          perks: [8008, 9111, 9104, 8017, 8135, 8106, 5005, 5008]),
                      abilities: ["Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"],
                      damageShare: 0.27, wards: 10),
        "support": Kit(items: [3190, 3158, 2055, 3364],
                       perks: PerkMetadata(styleId: 8400, subStyleId: 8300,
                                           perks: [8439, 8463, 8473, 8242, 8345, 8347, 5008, 5001]),
                       abilities: ["E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"],
                       damageShare: 0.06, wards: 31),
    ]

    /// Détails d'une frame : un joueur par ligne du flux (bleu 1-5, rouge 6-10), objets, runes et sorts de son rôle,
    /// ordre de montée coupé à son niveau.
    static func details(for snapshot: GameSnapshot) -> GameDetails {
        let lines = snapshot.bluePlayers + snapshot.redPlayers
        let blueKills = max(1, snapshot.blue.kills)
        let redKills = max(1, snapshot.red.kills)
        let participants = lines.enumerated().map { index, line in
            let kit = kits[line.role.lowercased()] ?? mid
            let teamKills = index < 5 ? blueKills : redKills
            return ParticipantDetails(
                participantId: index + 1, level: line.level, kills: line.kills, deaths: line.deaths,
                assists: line.assists, creepScore: line.creepScore, totalGoldEarned: line.gold,
                killParticipation: min(1, Double(line.kills + line.assists) / Double(teamKills)),
                championDamageShare: kit.damageShare, wardsPlaced: kit.wards, wardsDestroyed: kit.wards / 4,
                items: kit.items, perkMetadata: kit.perks, abilities: Array(kit.abilities.prefix(line.level))
            )
        }
        return GameDetails(frames: [DetailsFrame(rfc460Timestamp: snapshot.timestamp, participants: participants)])
    }
}
```

- [ ] **Step 4: Écrire la draft**

Créer `App/Builds/DraftStrip.swift` :

```swift
import LoLKit
import SwiftUI

/// Une équipe de la draft : code, couleur (Vitrail si suivie) et ses cinq champions (ids Data Dragon).
struct DraftTeam: Equatable {
    let code: String
    let tint: Color?
    let champions: [String]
}

/// Draft de la game (spec fonctionnalités §3), en haut des stats du Détail : les cinq champions de chaque équipe, dans
/// l'ordre d'affichage des équipes, en icônes Data Dragon (vignettes de repli tant que la version n'est pas connue).
/// Aucune requête de plus : les champions viennent du flux `window` déjà lu.
struct DraftStrip: View {
    let teams: [DraftTeam]
    let version: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                HStack(spacing: 8) {
                    Text(team.code)
                        .font(Typo.label)
                        .tracking(Typo.labelTracking)
                        .foregroundStyle(team.tint ?? Palette.secondary)
                        .lineLimit(1)
                        .frame(width: 36, alignment: .leading)
                    ForEach(Array(team.champions.enumerated()), id: \.offset) { _, champion in
                        DDragonIcon(url: version.map { DataDragon.championImage(version: $0, championId: champion) },
                                    size: 40, fallback: DDragonIcon.initials(champion))
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(team.code) : \(team.champions.map(Format.champion).joined(separator: ", "))")
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
```

- [ ] **Step 5: Écrire la section « Joueurs » enrichie**

Créer `App/Builds/BuildPlayersPanel.swift` :

```swift
import LoLKit
import SwiftUI

/// Ce dont les lignes et la fiche d'un joueur ont besoin en plus du joueur : version Data Dragon (liens des icônes),
/// catalogues (balise, noms, icônes des runes) et sorts d'invocateur de Leaguepedia par champion (game terminée).
struct BuildContext: Equatable {
    var version: String?
    var items: ItemCatalog?
    var runes: RuneCatalog?
    var summoners: SummonerCatalog?
    /// Sorts de Leaguepedia par champion ; vide en direct ou tant que le wiki n'a pas la game.
    var summonerSpells: [String: [String]] = [:]

    func championURL(_ championId: String) -> URL? {
        version.map { DataDragon.championImage(version: $0, championId: championId) }
    }

    func itemURL(_ itemId: Int?) -> URL? {
        guard let itemId, let version else { return nil }
        return DataDragon.itemImage(version: version, itemId: itemId)
    }

    func summonerURL(_ spellId: String) -> URL? {
        version.map { DataDragon.summonerSpellImage(version: $0, spellId: spellId) }
    }

    /// Rune principale (clé de voûte) d'un joueur.
    func keystone(_ details: ParticipantDetails?) -> RuneCatalog.Entry? {
        details?.perkMetadata?.keystone.flatMap { runes?.rune($0) }
    }

    /// Arbre secondaire d'un joueur.
    func secondaryTree(_ details: ParticipantDetails?) -> RuneCatalog.Entry? {
        details?.perkMetadata.flatMap { runes?.style($0.subStyleId) }
    }

    /// Sorts d'invocateur à montrer pour ce joueur (`PlayerBuilds.summonerSpells`).
    func spells(for line: PlayerLine) -> [String] {
        PlayerBuilds.summonerSpells(role: line.role, leaguepedia: summonerSpells[line.champion])
    }
}

/// Section « Joueurs » enrichie (spec fonctionnalités §3) : sélecteur d'équipe, puis une ligne par joueur — icône du
/// champion et niveau, pseudo, KDA, CS, gold, six objets et la balise, rune principale et arbre secondaire, sorts
/// d'invocateur. Toucher une ligne ouvre la fiche du joueur. Remplace `PlayersPanel` (spec §5.3).
struct BuildPlayersPanel: View {
    /// Équipes dans l'ordre d'affichage.
    let teams: [MatchTeam]
    /// Joueurs de chaque équipe affichée (`PlayerBuilds.rows`).
    let rows: [[PlayerBuild]]
    let context: BuildContext
    @Binding var selection: Int
    /// Joueur touché et index de son équipe (fiche du joueur).
    let onSelect: (PlayerBuild, Int) -> Void

    var body: some View {
        let index = rows.indices.contains(selection) ? selection : 0
        let players = rows.indices.contains(index) ? rows[index] : []
        VStack(alignment: .leading, spacing: 10) {
            Picker("Équipe", selection: $selection) {
                ForEach(teams.indices, id: \.self) { position in
                    Text(teams[position].code).tag(position)
                }
            }
            .pickerStyle(.segmented)
            // Changement d'équipe animé (spec finitions §9) : fondu des lignes, animation portée par `selection`.
            VStack(alignment: .leading, spacing: 12) {
                ForEach(players) { player in
                    Button {
                        onSelect(player, index)
                    } label: {
                        PlayerBuildRow(player: player, context: context)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
                if players.isEmpty {
                    Text("Joueurs indisponibles")
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .id(index)
            .transition(.opacity)
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Une ligne de joueur : champion (et niveau), pseudo et rôle, « Champion · KDA · CS · gold », sorts d'invocateur ; puis
/// six objets, la balise (ronde), la rune principale et l'arbre secondaire.
struct PlayerBuildRow: View {
    let player: PlayerBuild
    let context: BuildContext

    var body: some View {
        let line = player.line
        let inventory = PlayerBuilds.inventory(player.details?.items ?? [], catalog: context.items)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DDragonIcon(url: context.championURL(line.champion), size: 36,
                            fallback: DDragonIcon.initials(line.champion))
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(player.level)")
                            .font(Sora.font(9, .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 3)
                            .background(Palette.abyss.opacity(0.85), in: Capsule())
                            .offset(x: 4, y: 4)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(line.name.isEmpty ? Format.champion(line.champion) : line.name)
                            .font(Typo.secondaryMedium)
                            .lineLimit(1)
                        Text(Format.role(line.role))
                            .font(Typo.label)
                            .foregroundStyle(Palette.secondary)
                    }
                    Text("\(Format.champion(line.champion)) · \(Format.kda(line)) · \(line.creepScore) CS · \(Format.gold(line.gold))")
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    ForEach(context.spells(for: line), id: \.self) { spell in
                        DDragonIcon(url: context.summonerURL(spell), size: 18, radius: 4)
                    }
                }
            }
            HStack(spacing: 3) {
                ForEach(Array(PlayerBuilds.slots(inventory).enumerated()), id: \.offset) { _, item in
                    DDragonIcon(url: context.itemURL(item), size: 20, radius: 4)
                }
                DDragonIcon(url: context.itemURL(inventory.trinket), size: 20, radius: 10)
                Spacer(minLength: 6)
                DDragonIcon(url: context.keystone(player.details).map { DataDragon.runeIcon($0.icon) }, size: 20,
                            radius: 10)
                DDragonIcon(url: context.secondaryTree(player.details).map { DataDragon.runeIcon($0.icon) }, size: 16,
                            radius: 8)
            }
            .padding(.leading, 46)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.name), \(Format.champion(line.champion)), \(Format.kda(line)), \(line.creepScore) CS")
        .accessibilityHint("Ouvre la fiche du joueur")
    }
}

/// Squelette de la section « Joueurs » enrichie : sélecteur, puis cinq lignes à deux étages, à la hauteur de
/// `BuildPlayersPanel` (le Détail ne saute pas quand les joueurs arrivent).
struct BuildPlayersSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(height: 32, radius: 8)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            SkeletonBlock(width: 36, height: 36, radius: 8)
                            VStack(alignment: .leading, spacing: 6) {
                                SkeletonBlock(width: 110, height: 11)
                                SkeletonBlock(width: 180, height: 10)
                            }
                            Spacer()
                        }
                        SkeletonBlock(width: 160, height: 20, radius: 4)
                            .padding(.leading, 46)
                    }
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joueurs en chargement")
    }
}
```

- [ ] **Step 6: Écrire la fiche du joueur**

Créer `App/Builds/PlayerSheet.swift` :

```swift
import LoLKit
import SwiftUI

/// Ce que la fiche d'un joueur affiche : le joueur, son équipe (code et couleur) et le contexte de la game.
struct PlayerSheetItem: Identifiable, Equatable {
    let player: PlayerBuild
    let teamCode: String
    let tint: Color?
    let context: BuildContext
    /// Game terminée : les sorts d'invocateur viennent de Leaguepedia (sinon seul le Châtiment du jungler est connu).
    let finished: Bool

    var id: Int { player.participantId }
}

/// Fiche d'un joueur (spec fonctionnalités §3) : champion, KDA, CS, gold, niveau, participation aux kills, part des
/// dégâts (barre), balises posées et détruites, ordre de montée des sorts (icônes du champion), runes, objets nommés et
/// sorts d'invocateur. Tout est déjà chargé par le Détail, sauf les sorts du champion (`champion/<id>.json`), lus à
/// l'ouverture de la fiche.
struct PlayerSheet: View {
    let item: PlayerSheetItem
    @Environment(\.dataDragon) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var champion: ChampionSpells?

    var body: some View {
        let line = item.player.line
        let details = item.player.details
        let context = item.context
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(line)
                    stats(line, details)
                    if let share = details?.championDamageShare {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                StatLabel(icon: .swords, text: "Part des dégâts")
                                Spacer()
                                Text(PlayerBuilds.percent(share)).font(Typo.stat).monospacedDigit()
                            }
                            ShareBar(value: share, tint: item.tint ?? Palette.accent)
                        }
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    if let abilities = details?.abilities, !abilities.isEmpty {
                        section("Ordre des sorts") {
                            AbilityOrderView(abilities: abilities, champion: champion, version: context.version)
                        }
                    }
                    section("Runes") { runes(details) }
                    section("Objets") { items(details) }
                    section("Sorts d'invocateur") { summonerSpells(line) }
                }
                .padding(16)
            }
            .abyssBackground()
            .navigationTitle(line.name.isEmpty ? Format.champion(line.champion) : line.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task(id: line.champion) {
            guard let version = context.version, let store else { return }
            champion = await store.champion(version: version, championId: line.champion)
        }
    }

    private func header(_ line: PlayerLine) -> some View {
        HStack(spacing: 12) {
            DDragonIcon(url: item.context.championURL(line.champion), size: 56,
                        fallback: DDragonIcon.initials(line.champion))
            VStack(alignment: .leading, spacing: 3) {
                Text(champion?.name ?? Format.champion(line.champion))
                    .font(Typo.headline)
                Text("\(item.teamCode) · \(Format.role(line.role)) · niveau \(item.player.level)")
                    .font(Typo.secondary)
                    .foregroundStyle(item.tint ?? Palette.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: item.tint, radius: Radius.inner, padding: 14)
    }

    private func stats(_ line: PlayerLine, _ details: ParticipantDetails?) -> some View {
        let wards = details.flatMap { detail in
            detail.wardsPlaced.map { "\($0) / \(detail.wardsDestroyed ?? 0)" }
        } ?? "—"
        return VStack(spacing: 8) {
            statRow("KDA", Format.kda(line))
            statRow("Gold", Format.gold(line.gold))
            statRow("CS", "\(line.creepScore)")
            statRow("Participation aux kills", PlayerBuilds.percent(details?.killParticipation))
            statRow("Balises posées / détruites", wards)
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Typo.label)
                .tracking(Typo.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondary)
            Spacer()
            Text(value)
                .font(Typo.stat)
                .monospacedDigit()
        }
        .foregroundStyle(Palette.text)
    }

    @ViewBuilder private func runes(_ details: ParticipantDetails?) -> some View {
        let context = item.context
        if let keystone = context.keystone(details) {
            nameRow(url: DataDragon.runeIcon(keystone.icon), name: keystone.name, round: true)
        }
        if let tree = context.secondaryTree(details) {
            nameRow(url: DataDragon.runeIcon(tree.icon), name: tree.name, round: true)
        }
        if context.keystone(details) == nil, context.secondaryTree(details) == nil {
            Text("Runes indisponibles")
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
        }
    }

    @ViewBuilder private func items(_ details: ParticipantDetails?) -> some View {
        let context = item.context
        let inventory = PlayerBuilds.inventory(details?.items ?? [], catalog: context.items)
        ForEach(Array(inventory.items.enumerated()), id: \.offset) { _, id in
            nameRow(url: context.itemURL(id), name: context.items?.item(id)?.name ?? "Objet \(id)", round: false)
        }
        if let trinket = inventory.trinket {
            nameRow(url: context.itemURL(trinket), name: context.items?.item(trinket)?.name ?? "Balise", round: true)
        }
        if inventory.items.isEmpty, inventory.trinket == nil {
            Text("Aucun objet")
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
        }
    }

    @ViewBuilder private func summonerSpells(_ line: PlayerLine) -> some View {
        let context = item.context
        let spells = context.spells(for: line)
        ForEach(spells, id: \.self) { spell in
            nameRow(url: context.summonerURL(spell), name: context.summoners?.spell(spell)?.name ?? spell, round: false)
        }
        Text(item.finished
             ? (context.summonerSpells[line.champion] == nil
                ? "Leaguepedia n'a pas encore cette game : seul le Châtiment du jungler est connu."
                : "Source : Leaguepedia.")
             : "En direct, Riot ne donne pas les sorts d'invocateur : seul le Châtiment du jungler est connu.")
            .font(Typo.secondary)
            .foregroundStyle(Palette.secondary)
    }

    private func nameRow(url: URL?, name: String, round: Bool) -> some View {
        HStack(spacing: 10) {
            DDragonIcon(url: url, size: 28, radius: round ? 14 : 6)
            Text(name)
                .font(Typo.body)
                .foregroundStyle(Palette.text)
            Spacer(minLength: 0)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .glassCard(radius: Radius.inner, padding: 14)
        }
    }
}

/// Barre d'une part (0…1) à la couleur de l'équipe : part des dégâts.
struct ShareBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 5)
    }
}

/// Ordre de montée des sorts : les quatre sorts du champion (icônes, lettres Q W E R), puis la lettre montée à chaque
/// niveau ; R à l'accent.
struct AbilityOrderView: View {
    let abilities: [String]
    let champion: ChampionSpells?
    let version: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ForEach(["Q", "W", "E", "R"], id: \.self) { letter in
                    VStack(spacing: 3) {
                        DDragonIcon(url: url(letter), size: 30, fallback: letter)
                        Text(letter)
                            .font(Typo.label)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 4), count: 9), alignment: .leading,
                      spacing: 4) {
                ForEach(Array(abilities.enumerated()), id: \.offset) { level, letter in
                    Text(letter)
                        .font(Sora.font(11, .bold))
                        .foregroundStyle(letter == "R" ? Palette.abyss : Palette.text)
                        .frame(width: 24, height: 24)
                        .background(letter == "R" ? Palette.accent : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityLabel("Niveau \(level + 1) : \(letter)")
                }
            }
        }
    }

    private func url(_ letter: String) -> URL? {
        guard let version, let file = champion?.spell(forAbility: letter)?.image else { return nil }
        return DataDragon.spellImage(version: version, file: file)
    }
}
```

- [ ] **Step 7: Écrire l'aperçu**

Créer `Tests/FailleTests/BuildsSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Draft, section « Joueurs » enrichie et fiche d'un joueur (spec fonctionnalités §3), sur la game d'exemple avec ses
    /// détails d'exemple ; sans version Data Dragon : vignettes de repli (aucun réseau). Le jungler montre son Châtiment.
    @Test func buildsBoard() async throws {
        let snapshot = SampleData.kcSnapshot
        let details = BuildSamples.details(for: snapshot)
        let rows = [PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "kc"),
                    PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: "c9")]
        let teams = SampleData.live[0].match.teams
        let kc = Palette.team("#5B8CFF")
        let draft = PlayerBuilds.draft(snapshot: snapshot, teamIds: ["kc", "c9"])
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Joueurs", subtitle: "Draft · builds · fiche")
                DraftStrip(teams: [DraftTeam(code: "KC", tint: kc, champions: draft[0]),
                                   DraftTeam(code: "C9", tint: nil, champions: draft[1])], version: nil)
                BuildPlayersPanel(teams: teams, rows: rows, context: BuildContext(), selection: .constant(0),
                                  onSelect: { _, _ in })
                BuildPlayersSkeleton()
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "20-joueurs")
        expectNotBlank(url)

        let jungler = PlayerSheetItem(player: rows[0][1], teamCode: "KC", tint: kc, context: BuildContext(),
                                      finished: false)
        let sheet = try await Snapshot.write(PlayerSheet(item: jungler), named: "20b-fiche-joueur")
        expectNotBlank(sheet)
    }
}
```

- [ ] **Step 8: Vérifier le périmètre, committer, pousser**

```bash
git status --short
```

Expected : seulement `?? App/Builds/`, `?? Tests/FailleTests/BuildsTests.swift`, `?? Tests/FailleTests/BuildsSnapshotTests.swift`.

```bash
git add App/Builds Tests/FailleTests/BuildsTests.swift Tests/FailleTests/BuildsSnapshotTests.swift
git commit -m "feat(app): draft et builds — détails par joueur (60 s en direct, une fois joués), objets, runes, sorts, fiche du joueur, Châtiment du jungler" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t6-builds
```

- [ ] **Step 9: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
```

Expected : jobs verts ; suite `BuildsTests` (7 tests) verte ; `20-joueurs.png` : draft KC (à sa couleur) / C9 en vignettes « RU », « XZ »…, section « Joueurs » KC (cinq lignes à deux étages : champion et niveau, pseudo, rôle, « Rumble · 2/0/1 · 162 CS · 7,6k », six cases + balise ronde, deux runes ; Châtiment pour le jungler), squelette de même gabarit ; `20b-fiche-joueur.png` : fiche du jungler de KC (en-tête teinté, stats, part des dégâts, ordre des sorts avec lettres, runes, objets « Objet 6692 »…, Châtiment et la note « En direct, Riot ne donne pas les sorts d'invocateur… »). Échec : `gh run view "$RUN" --log-failed`, corriger, commit, push, relancer.


### Task 7: Intégration (store, Détail, carte, Réglages, notifications, aperçus, checklist)

**Branche :** `fonc/appli-t7-integration` · **Vague :** C · **Dépendances :** T1 à T6 fusionnées dans `main`.

Avant de commencer : `git pull --ff-only origin main` dans le dépôt principal, puis créer le worktree depuis ce `main` ; **relire à HEAD** chaque ancre de `App/Detail/MatchDetailView.swift` et `App/Matches/TeamCardView.swift` (vague de corrections des finitions, voir Global Constraints) avant de la remplacer.

**Files:**
- Modify: `App/Store/AppStore.swift` (propriétés, `init(transport:files:liveActivities:)`, `init(preview:)`, réglages, `loadWindow`), `App/Detail/MatchDetailView.swift`, `App/Detail/StatsPanels.swift` (suppression de `PlayersPanel`), `App/DA/Skeleton.swift` (`GameStatsSkeleton`, suppression de `PlayersSkeleton`), `App/Matches/TeamCardView.swift` (`liveBlock`), `App/Settings/SettingsView.swift`, `App/RootView.swift`, `App/FailleApp.swift`, `Shared/Preview/SampleData.swift`, `docs/superpowers/notes/2026-10-14-checklist-iphone.md`
- Create: `App/Preview/FeatureSamples.swift`, `App/Detail/MatchDetailModel+Features.swift`, `App/Detail/GameFeatureSections.swift`
- Test: `Tests/FailleTests/FeaturesIntegrationTests.swift`, `Tests/FailleTests/FeaturesSnapshotTests.swift` (aperçus `21-detail-direct`, `21-detail-direct-milieu`, `21-detail-direct-bas`, `22-detail-termine`, `22-detail-termine-bas`, `23-fiche-joueur`, `24-carte-regarder`)

**Interfaces:**
- Consumes : tout ce que T1 à T6 produisent (voir leurs blocs « Produces », noms et signatures exacts) ; à `origin/main` : `AppStore` (`transport`, `files`, `isPreview` privés à `AppStore.swift` ; `settings`, `snapshots`, `details`, `statsUnavailable`, `event(id:)`, `isMasked(_:matchId:)`, `tint(for:)`, `cards`, `loadWindow(gameId:inProgress:)`, `loadDetails(matchId:)`, `reveal(matchId:)`, `syncSettingsBeforeChange()` et `saveSettings()` privés), `MatchDetailModel` (`matchId`, `selectedGameNumber`, `playersTeamIndex`, `selectedGame(in:)`, `loadSelectedGame(store:)`), `MatchRoute(matchId:sourceID:)`, `RunEnvironment.isTesting`, `FileStore.directory`, `SampleData` (`worlds`, `side(_:wins:outcome:withId:)`, `player(…)`, `date(_:)`, `kcSnapshot`, `kcGameStart`, `kcLive`, `t1Live`, `live`), `PreviewData.standard`, `TeamStatsPanel`, `GameStatsSkeleton`, `StatsSkeleton`.
- Produces :
  - `AppStore` : `let dataDragon: DataDragonStore`, `let gameDetails: GameDetailsStore`, `let timelines: TimelineStore`, `let summonerSpells: SummonerSpellsStore`, `let reminderCenter: any ReminderCenter`, `private(set) var patches: [String: String]`, `init(transport:files:liveActivities:reminderCenter: (any ReminderCenter)? = nil)`, `func setMatchReminders(enabled: Bool)`, `func setMatchReminderLead(_ lead: TimeInterval)`.
  - `extension MatchDetailModel` : `func featureGame(store: AppStore) -> GameRef?` (la garde anti-spoiler unique), `func runFeatures(store: AppStore) async`, `func loadDataDragon(store: AppStore) async`, `func lookUpSpells(store: AppStore) async`.
  - Vues : `DraftSection(game:teams:snapshot:)`, `GoldCurveSection(game:teams:)`, `TimelineSection(game:teams:)`, `PlayersSection(game:teams:snapshot:selection:onSelect:)` + `static func context(store:game:) -> BuildContext`.
  - `enum FeatureSamples { static var timelines: [String: [GameSnapshot]]; static var details: [String: GameDetails]; static var spells: [String: [String: [String]]] }` ; `SampleData.kcG2MatchId`, `SampleData.kcG2Details`, `SampleData.kcG2GameStart`, `SampleData.kcG2Final` ; `RootView(tab:router:)` ; `AppRuntime.notificationRouter`, `AppRuntime.notificationDelegate`.

- [ ] **Step 1: Écrire les tests d'intégration**

Créer `Tests/FailleTests/FeaturesIntegrationTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Fonctionnalités branchées dans le store et le Détail (spec fonctionnalités) : rien pour un match masqué, sorts
/// d'invocateur seulement pour un match terminé, patch du flux gardé, réglages des notifications enregistrés, aperçus
/// cohérents.
@MainActor
@Suite(.serialized)
struct FeaturesIntegrationTests {
    private static let matchId = "M1"

    /// `getEventDetails` d'un Bo3 KC – C9 : game 1 jouée, game 2 dans l'état demandé, game 3 inutile.
    private static func detailsJSON(game2: String) -> String {
        let sides = #"[{"id":"kc","side":"blue"},{"id":"c9","side":"red"}]"#
        return """
        {"data":{"event":{"id":"M1","type":"match","league":{"id":"1","slug":"worlds","name":"Mondial","image":null},\
        "match":{"strategy":{"type":"bestOf","count":3},\
        "teams":[{"id":"kc","name":"Karmine Corp","code":"KC","image":null,"result":{"outcome":null,"gameWins":1}},\
        {"id":"c9","name":"Cloud9 Kia","code":"C9","image":null,"result":{"outcome":null,"gameWins":0}}],\
        "games":[{"number":1,"id":"g1","state":"completed","teams":\(sides)},\
        {"number":2,"id":"g2","state":"\(game2)","teams":\(sides)},\
        {"number":3,"id":"g3","state":"unneeded","teams":\(sides)}]},\
        "streams":[{"statsStatus":"enabled"}]}}}
        """
    }

    /// Fenêtre `window` de la game g2 (patch 16.19), une frame terminée.
    private static let windowJSON = """
    {"esportsGameId":"g2","esportsMatchId":"M1","gameMetadata":{"patchVersion":"16.19.300.1",\
    "blueTeamMetadata":{"esportsTeamId":"kc","participantMetadata":[]},\
    "redTeamMetadata":{"esportsTeamId":"c9","participantMetadata":[]}},\
    "frames":[{"rfc460Timestamp":"2026-10-04T20:53:40.101Z","gameState":"finished",\
    "blueTeam":{"totalGold":60000,"inhibitors":2,"towers":9,"barons":1,"totalKills":18,"dragons":[],"participants":[]},\
    "redTeam":{"totalGold":50000,"inhibitors":0,"towers":3,"barons":0,"totalKills":7,"dragons":[],"participants":[]}}]}
    """

    /// Store branché sur un faux réseau (détails du match, fenêtre de g2) qui garde toutes les requêtes ; détails chargés.
    private static func makeStore(game2: String, spoilerFree: Bool) async -> (AppStore, ScriptedTransport) {
        let details = detailsJSON(game2: game2)
        let window = windowJSON
        let transport = ScriptedTransport(extra: { url in
            if url.path.hasSuffix("/getEventDetails") { return HTTPResponse(status: 200, body: Data(details.utf8)) }
            if url.path.hasSuffix("/window/g2") { return HTTPResponse(status: 200, body: Data(window.utf8)) }
            return nil
        })
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", spoilerFree: spoilerFree)]),
                   to: .follows)
        let store = AppStore(transport: transport, files: files)
        await store.loadDetails(matchId: matchId)
        return (store, transport)
    }

    /// Anti-spoiler (spec fonctionnalités, principes) : pour un match masqué, ni fil, ni détails, ni Data Dragon, ni
    /// Leaguepedia — aucune requête en dehors de `getEventDetails`.
    @Test func maskedMatchLoadsNoFeature() async {
        let (store, transport) = await Self.makeStore(game2: "completed", spoilerFree: true)
        let model = MatchDetailModel(matchId: Self.matchId)
        #expect(model.featureGame(store: store) == nil)
        await model.runFeatures(store: store)
        await model.loadDataDragon(store: store)
        await model.lookUpSpells(store: store)
        let requests = await transport.requests
        #expect(!requests.isEmpty)
        #expect(requests.allSatisfy { $0.path.hasSuffix("/getEventDetails") })
        #expect(store.timelines.replayFrames.isEmpty)
        #expect(store.gameDetails.details.isEmpty)
    }

    @Test func revealedPlayedGameIsTheFeatureGame() async {
        let (store, _) = await Self.makeStore(game2: "completed", spoilerFree: true)
        store.reveal(matchId: Self.matchId)
        let model = MatchDetailModel(matchId: Self.matchId)
        #expect(model.featureGame(store: store)?.id == "g2")
        model.selectedGameNumber = 3 // game inutile : la game affichée reste g2
        #expect(model.featureGame(store: store)?.id == "g2")
    }

    /// Sorts d'invocateur : jamais pendant que le match se joue (le wiki n'aurait que des games partielles).
    @Test func spellsWaitForTheEndOfTheMatch() async {
        let (store, transport) = await Self.makeStore(game2: "inProgress", spoilerFree: false)
        let model = MatchDetailModel(matchId: Self.matchId)
        await model.lookUpSpells(store: store)
        #expect(await transport.requests.allSatisfy { $0.host() != "lol.fandom.com" && !$0.path.contains("/window/") })
    }

    /// Le patch du flux d'une game lue est gardé : il donne la version Data Dragon de ses images.
    @Test func loadedWindowKeepsItsPatch() async {
        let (store, _) = await Self.makeStore(game2: "completed", spoilerFree: false)
        await store.loadWindow(gameId: "g2", inProgress: false)
        #expect(store.snapshots["g2"]?.phase == .finished)
        #expect(store.patches["g2"] == "16.19.300.1")
    }

    @Test func reminderSettingsAreSavedAndReloaded() {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: ScriptedTransport(mode: .failing), files: files)
        #expect(store.settings.matchRemindersEnabled == false)
        store.setMatchReminders(enabled: true)
        store.setMatchReminderLead(30 * 60)
        let reloaded = AppStore(transport: ScriptedTransport(mode: .failing), files: files)
        #expect(reloaded.settings.matchRemindersEnabled)
        #expect(reloaded.settings.matchReminderLead == 1800)
    }

    /// Les aperçus racontent la même game partout : la dernière frame du fil de la game terminée est celle des stats.
    @Test func previewSamplesAgreeWithTheStats() throws {
        let frames = TimelineSamples.frames(.redWins, start: SampleData.kcG2GameStart, final: SampleData.kcG2Final)
        #expect(frames.last == SampleData.kcG2Final)
        let store = AppStore(preview: .standard)
        #expect(!store.timelines.events(gameId: SampleData.kcSnapshot.gameId).isEmpty)
        #expect(store.gameDetails.details[SampleData.kcG2Final.gameId] != nil)
        #expect(store.summonerSpells.spells[SampleData.kcG2Final.gameId]?.count == 10)
        let games = try #require(store.details[SampleData.kcG2MatchId]?.match.games)
        #expect(games.compactMap { WatchLinks.replay($0, masked: false) }.count == 4)
    }

    /// « Regarder » : le match en direct non masqué (KC) l'a, en français ; le match masqué (T1) ne l'a pas.
    @Test func watchOnlyForTheUnmaskedLiveMatch() {
        let store = AppStore(preview: .standard)
        let kc = SampleData.kcLive
        let t1 = SampleData.t1Live
        let kcWatch = WatchLinks.live(kc.streams, inProgress: true, masked: store.isMasked(kc.match.teams, matchId: kc.id))
        #expect(kcWatch?.preferred.locale == "fr-FR")
        let t1Masked = store.isMasked(t1.match.teams, matchId: t1.id)
        #expect(t1Masked)
        // Mêmes streams, match masqué : aucun bouton.
        #expect(WatchLinks.live(kc.streams, inProgress: true, masked: t1Masked) == nil)
    }
}
```

- [ ] **Step 2: Données d'aperçu**

Dans `Shared/Preview/SampleData.swift` (compilé aussi dans l'extension : seulement des types de LoLKit) :

1. Remplacer :

```swift
            details: Dictionary(uniqueKeysWithValues: SampleData.live.map { ($0.id, EventDetails(event: $0)) }),
            snapshots: [SampleData.kcSnapshot.gameId: SampleData.kcSnapshot],
```

par :

```swift
            details: Dictionary(uniqueKeysWithValues: SampleData.live.map { ($0.id, EventDetails(event: $0)) })
                .merging([SampleData.kcG2MatchId: SampleData.kcG2Details]) { live, _ in live },
            snapshots: [SampleData.kcSnapshot.gameId: SampleData.kcSnapshot,
                        SampleData.kcG2Final.gameId: SampleData.kcG2Final],
```

2. Remplacer :

```swift
    static let noStatsMatchId = "m-bro-lgd"
```

par :

```swift
    static let noStatsMatchId = "m-bro-lgd"
    /// KC 1 – 3 G2, match terminé du calendrier : Détail « terminé » des aperçus (rediffusions, sorts d'invocateur).
    static let kcG2MatchId = "m-kc-g2"
```

3. Remplacer :

```swift
                         games: games(count: 5, current: 2, blue: "kc", red: "c9")),
        streams: [StreamInfo(statsStatus: "enabled")]
    )
```

par :

```swift
                         games: games(count: 5, current: 2, blue: "kc", red: "c9")),
        // Comme `getLive` : des streams en plusieurs langues (« Regarder » choisit le français, spec fonctionnalités §1).
        streams: [
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "riotgames", locale: "en-US"),
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR"),
            StreamInfo(statsStatus: "enabled", provider: "youtube", parameter: "lolesports", locale: "en-US"),
        ]
    )
```

4. Remplacer :

```swift
            player("support", "Nautilus", "C9 Support", 0, 1, 3, 18),
        ]
    )
```

par :

```swift
            player("support", "Nautilus", "C9 Support", 0, 1, 3, 18),
        ]
    )

    /// `getEventDetails` de KC 1 – 3 G2 : quatre games jouées, chacune avec sa rediffusion YouTube (spec
    /// fonctionnalités §1), la cinquième inutile.
    static var kcG2Details: EventDetails {
        EventDetails(
            id: kcG2MatchId, league: worlds,
            match: EventDetails.Match(
                strategy: Strategy(type: "bestOf", count: 5),
                teams: [side("kc", wins: 1, outcome: "loss"), side("g2", wins: 3, outcome: "win")],
                games: (1...5).map { number in
                    GameRef(number: number, id: "g\(number)-kc-g2", state: number <= 4 ? .completed : .unneeded,
                            teams: [GameRef.Side(id: "kc", side: "blue"), GameRef.Side(id: "g2", side: "red")],
                            vods: number <= 4
                                ? [Vod(provider: "youtube", parameter: "kcg2-game\(number)", locale: "en-US",
                                       startMillis: number == 1 ? 0 : 95_000)]
                                : nil)
                }
            ),
            streams: nil
        )
    }

    /// Game 4 de KC – G2, gagnée par G2 en 34 min : sa dernière frame (`finished`), celle sur laquelle finit le fil
    /// d'exemple (`TimelineSamples.Script.redWins`).
    static let kcG2GameStart = date("2026-10-05T19:12:00Z")
    static let kcG2Final = GameSnapshot(
        gameId: "g4-kc-g2", phase: .finished, timestamp: date("2026-10-05T19:46:09Z"),
        blueTeamId: "kc", redTeamId: "g2",
        blue: TeamStats(kills: 5, gold: 54_400, towers: 2, inhibitors: 0, barons: 0, dragons: ["ocean"]),
        red: TeamStats(kills: 14, gold: 69_600, towers: 11, inhibitors: 3, barons: 2,
                       dragons: ["hextech", "hextech", "infernal", "hextech"]),
        bluePlayers: [
            player("top", "Gnar", "KC Top", 1, 3, 1, 268, level: 16),
            player("jungle", "Sejuani", "KC Jungle", 1, 4, 2, 182, level: 14),
            player("mid", "Orianna", "KC Mid", 2, 2, 1, 301, level: 16),
            player("bottom", "Varus", "KC Bot", 1, 3, 2, 322, level: 15),
            player("support", "Braum", "KC Support", 0, 2, 4, 41, level: 13),
        ],
        redPlayers: [
            player("top", "Rumble", "G2 Top", 2, 1, 6, 281, level: 17),
            player("jungle", "LeeSin", "G2 Jungle", 3, 1, 8, 205, level: 16),
            player("mid", "Ahri", "G2 Mid", 5, 1, 6, 320, level: 18),
            player("bottom", "Kalista", "G2 Bot", 4, 0, 7, 345, level: 17),
            player("support", "Rakan", "G2 Support", 0, 2, 12, 38, level: 15),
        ]
    )
```

5. Remplacer :

```swift
    private static func player(_ role: String, _ champion: String, _ name: String, _ kills: Int, _ deaths: Int,
                               _ assists: Int, _ cs: Int) -> PlayerLine {
        PlayerLine(role: role, champion: champion, name: name, level: 11, kills: kills, deaths: deaths,
                   assists: assists, creepScore: cs, gold: 6_000 + cs * 10)
    }
```

par :

```swift
    private static func player(_ role: String, _ champion: String, _ name: String, _ kills: Int, _ deaths: Int,
                               _ assists: Int, _ cs: Int, level: Int = 11) -> PlayerLine {
        PlayerLine(role: role, champion: champion, name: name, level: level, kills: kills, deaths: deaths,
                   assists: assists, creepScore: cs, gold: 6_000 + cs * 10)
    }
```

Créer `App/Preview/FeatureSamples.swift` :

```swift
import Foundation
import LoLKit

/// Données des fonctionnalités pour les aperçus (#Preview et PNG), aucune requête : fil et courbe, détails par joueur et
/// sorts d'invocateur des deux games que montrent les aperçus — KC – C9 game 2 en direct (`SampleData.kcSnapshot`) et
/// la game 4 terminée de KC – G2 (`SampleData.kcG2Final`).
enum FeatureSamples {
    static var timelines: [String: [GameSnapshot]] {
        [
            SampleData.kcSnapshot.gameId: TimelineSamples.frames(.kcLive, start: SampleData.kcGameStart,
                                                                 final: SampleData.kcSnapshot) + [SampleData.kcSnapshot],
            SampleData.kcG2Final.gameId: TimelineSamples.frames(.redWins, start: SampleData.kcG2GameStart,
                                                                final: SampleData.kcG2Final),
        ]
    }

    static var details: [String: GameDetails] {
        [
            SampleData.kcSnapshot.gameId: BuildSamples.details(for: SampleData.kcSnapshot),
            SampleData.kcG2Final.gameId: BuildSamples.details(for: SampleData.kcG2Final),
        ]
    }

    /// Sorts d'invocateur de la game terminée (comme Leaguepedia les donne, en ids Data Dragon).
    static var spells: [String: [String: [String]]] {
        [
            SampleData.kcG2Final.gameId: [
                "Gnar": ["SummonerFlash", "SummonerTeleport"], "Sejuani": ["SummonerSmite", "SummonerFlash"],
                "Orianna": ["SummonerFlash", "SummonerTeleport"], "Varus": ["SummonerFlash", "SummonerBoost"],
                "Braum": ["SummonerFlash", "SummonerExhaust"], "Rumble": ["SummonerFlash", "SummonerTeleport"],
                "LeeSin": ["SummonerFlash", "SummonerSmite"], "Ahri": ["SummonerFlash", "SummonerDot"],
                "Kalista": ["SummonerFlash", "SummonerHeal"], "Rakan": ["SummonerFlash", "SummonerDot"],
            ],
        ]
    }
}
```

- [ ] **Step 3: Brancher les fonctionnalités dans le store**

Dans `App/Store/AppStore.swift` :

1. Remplacer :

```swift
    private(set) var backgroundDiagnostic = BackgroundDiagnostic()
```

par :

```swift
    private(set) var backgroundDiagnostic = BackgroundDiagnostic()
    /// Fonctionnalités (spec fonctionnalités §3-§5) : images et données Data Dragon, détails par joueur, fil et courbe de
    /// gold, sorts d'invocateur — chacun avec son cache disque sous `cache/`, tous inertes dans les aperçus. Jamais
    /// sollicités pour un match masqué (`MatchDetailModel.featureGame`).
    let dataDragon: DataDragonStore
    let gameDetails: GameDetailsStore
    let timelines: TimelineStore
    let summonerSpells: SummonerSpellsStore
    /// Notifications de début de match (spec fonctionnalités §2) : `UNUserNotificationCenter` dans l'appli, inerte dans
    /// les aperçus et les tests hébergés.
    let reminderCenter: any ReminderCenter
    /// Patch du flux de chaque game lue (`gameMetadata.patchVersion`) : il donne la version Data Dragon de ses images.
    private(set) var patches: [String: String] = [:]
```

2. Remplacer :

```swift
    /// - Parameter liveActivities: contrôleur des Live Activities ; nil (l'appli) : celui du dossier `files`. Les tests
    ///   en passent un (aperçu) pour simuler des Live Activities à l'écran.
    init(transport: any HTTPTransport = URLSessionTransport(), files: FileStore,
         liveActivities: LiveActivityController? = nil) {
        self.transport = transport
        client = LoLClient(transport: transport)
        self.files = files
        isPreview = false
        reloadsWidgets = !RunEnvironment.isTesting
        // Tests hébergés : aucune Live Activity réelle (les choix restent enregistrés et testables).
        self.liveActivities = liveActivities
            ?? LiveActivityController(files: files, usesActivityKit: !RunEnvironment.isTesting)
        loadFromDisk(files)
    }
```

par :

```swift
    /// - Parameters:
    ///   - liveActivities: contrôleur des Live Activities ; nil (l'appli) : celui du dossier `files`. Les tests en passent
    ///     un (aperçu) pour simuler des Live Activities à l'écran.
    ///   - reminderCenter: centre des notifications ; nil : celui d'iOS (inerte dans les tests hébergés).
    init(transport: any HTTPTransport = URLSessionTransport(), files: FileStore,
         liveActivities: LiveActivityController? = nil, reminderCenter: (any ReminderCenter)? = nil) {
        self.transport = transport
        client = LoLClient(transport: transport)
        self.files = files
        isPreview = false
        reloadsWidgets = !RunEnvironment.isTesting
        // Tests hébergés : aucune Live Activity réelle (les choix restent enregistrés et testables).
        self.liveActivities = liveActivities
            ?? LiveActivityController(files: files, usesActivityKit: !RunEnvironment.isTesting)
        // Caches des fonctionnalités : `cache/` à côté des fichiers de Faille (exclu de la sauvegarde iCloud).
        let cache = DiskCache(root: files.directory.appendingPathComponent("cache", isDirectory: true))
        dataDragon = DataDragonStore(transport: transport, cache: cache)
        gameDetails = GameDetailsStore(transport: transport, cache: cache)
        timelines = TimelineStore(transport: transport, cache: cache)
        summonerSpells = SummonerSpellsStore(transport: transport, cache: cache)
        if let reminderCenter {
            self.reminderCenter = reminderCenter
        } else if RunEnvironment.isTesting {
            self.reminderCenter = InertReminderCenter()
        } else {
            self.reminderCenter = SystemReminderCenter()
        }
        loadFromDisk(files)
    }
```

3. Remplacer :

```swift
        liveActivities = LiveActivityController(preview: data.activityMatchIds)
        follows = data.follows
```

par :

```swift
        liveActivities = LiveActivityController(preview: data.activityMatchIds)
        // Fonctionnalités figées (`FeatureSamples`) : aucune requête, aucun fichier, aucune notification.
        dataDragon = DataDragonStore.preview()
        gameDetails = GameDetailsStore(preview: FeatureSamples.details)
        timelines = TimelineStore(preview: FeatureSamples.timelines)
        summonerSpells = SummonerSpellsStore(preview: FeatureSamples.spells)
        reminderCenter = InertReminderCenter()
        follows = data.follows
```

4. Remplacer :

```swift
        settings.liveActivityMode = mode
        saveSettings()
        runWithScene { await self.syncLiveActivities(canStart: true) }
    }
```

par :

```swift
        settings.liveActivityMode = mode
        saveSettings()
        runWithScene { await self.syncLiveActivities(canStart: true) }
    }

    /// Réglage « Notifications de début de match » (spec fonctionnalités §2) : enregistré tout de suite ; la
    /// reprogrammation suit d'elle-même (`reminderSignature` change, la scène relance `syncReminders`).
    func setMatchReminders(enabled: Bool) {
        syncSettingsBeforeChange()
        settings.matchRemindersEnabled = enabled
        saveSettings()
    }

    /// Délai des notifications de début de match : 5, 15 ou 30 min (`MatchReminders.leadOptions`).
    func setMatchReminderLead(_ lead: TimeInterval) {
        syncSettingsBeforeChange()
        settings.matchReminderLead = lead
        saveSettings()
    }
```

5. Remplacer :

```swift
            if let snapshot = window.latestSnapshot() {
                snapshots[gameId] = snapshot
                snapshotDates[gameId] = fetchedAt
            }
```

par :

```swift
            if let snapshot = window.latestSnapshot() {
                snapshots[gameId] = snapshot
                snapshotDates[gameId] = fetchedAt
            }
            if let patch = window.gameMetadata.patchVersion {
                patches[gameId] = patch
            }
```

- [ ] **Step 4: Écrire la garde et les chargements du Détail**

Créer `App/Detail/MatchDetailModel+Features.swift` :

```swift
import Foundation
import LoLKit

// MARK: - Fonctionnalités du Détail (fonctionnalités, Task 7)

extension MatchDetailModel {
    /// Game dont l'écran montre les fonctionnalités (draft et builds, fil, courbe, sorts d'invocateur) : la game affichée,
    /// en cours ou jouée, d'un match NON masqué dont Riot fournit les stats. nil sinon : aucune requête, aucun affichage
    /// (spec fonctionnalités, « Anti-spoiler d'abord » ; spec §8).
    func featureGame(store: AppStore) -> GameRef? {
        guard let details = store.details[matchId], let game = selectedGame(in: details),
              !store.isMasked(details.match.teams, matchId: matchId),
              !details.statsDisabled, store.event(id: matchId)?.statsDisabled != true,
              !store.statsUnavailable.contains(game.id),
              game.state == .inProgress || game.state == .completed else { return nil }
        return game
    }

    /// Données des fonctionnalités de la game affichée, tant que l'écran l'affiche (tâche annulée en le quittant) : le fil
    /// (disque, sinon relecture du flux à pas de 60 s) et les détails par joueur (toutes les 60 s en cours, une fois
    /// jouée), en parallèle ; puis, match terminé, les sorts d'invocateur (Leaguepedia, sous sa règle stricte).
    func runFeatures(store: AppStore) async {
        guard let game = featureGame(store: store) else { return }
        let inProgress = game.state == .inProgress
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await store.timelines.load(gameId: game.id, inProgress: inProgress) }
            group.addTask { await store.gameDetails.follow(gameId: game.id, finished: !inProgress) }
        }
        guard !Task.isCancelled, !inProgress else { return }
        await lookUpSpells(store: store)
    }

    /// Version Data Dragon de la game affichée (patch lu dans son flux) et catalogues (objets, runes, sorts d'invocateur).
    func loadDataDragon(store: AppStore) async {
        guard let game = featureGame(store: store), let patch = store.patches[game.id],
              let version = await store.dataDragon.version(forPatch: patch) else { return }
        await store.dataDragon.loadCatalogs(version: version)
    }

    /// Sorts d'invocateur d'un match terminé et non masqué : toutes ses games jouées, une seule requête Leaguepedia. La fin
    /// du match est la frame `finished` de sa dernière game si l'écran l'a déjà lue (sinon `SpellSchedule` l'estime).
    func lookUpSpells(store: AppStore) async {
        guard let details = store.details[matchId], !store.isMasked(details.match.teams, matchId: matchId) else { return }
        let games = details.match.games
        let finished = store.event(id: matchId)?.state == .completed
            || !games.contains { $0.state == .inProgress || $0.state == .unstarted }
        let played = games.filter { $0.state == .completed }
        guard finished, let last = played.last else { return }
        let end = store.snapshots[last.id].flatMap { $0.phase == .finished ? $0.timestamp : nil }
        await store.summonerSpells.lookUp(matchId: matchId, gameIds: played.map(\.id), matchEnd: end)
    }
}
```

Créer `App/Detail/GameFeatureSections.swift` :

```swift
import LoLKit
import SwiftUI

// Sections des fonctionnalités dans le Détail d'une game (spec fonctionnalités §3-§5). Elles n'existent que dans la
// branche « non masqué » de `MatchDetailView` (et seulement quand une frame de la game est arrivée) : rien ne peut fuiter.

/// Les deux équipes de la game (ordre d'affichage) pour le fil et la courbe : code et couleur Vitrail (accent pour celle
/// de gauche non suivie, secondaire pour l'autre).
@MainActor
private func timelineTeams(_ teams: [MatchTeam], store: AppStore) -> [TimelineTeam] {
    teams.enumerated().compactMap { index, team in
        team.id.map { TimelineTeam(id: $0, code: team.code,
                                   tint: store.tint(for: team) ?? (index == 0 ? Palette.accent : Palette.secondary)) }
    }
}

/// Draft (spec fonctionnalités §3) : les champions des deux équipes, depuis la frame déjà lue.
struct DraftSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]
    let snapshot: GameSnapshot

    var body: some View {
        let champions = PlayerBuilds.draft(snapshot: snapshot, teamIds: teams.compactMap(\.id))
        DraftStrip(teams: zip(teams, champions).map { team, picks in
                       DraftTeam(code: team.code, tint: store.tint(for: team), champions: picks)
                   },
                   version: store.dataDragon.knownVersion(forPatch: store.patches[game.id]))
    }
}

/// Courbe de l'écart de gold (spec fonctionnalités §5), orientée vers l'équipe de gauche.
struct GoldCurveSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]

    var body: some View {
        let timelines = store.timelines
        if !timelines.unavailable.contains(game.id) {
            GoldChartCard(points: timelines.goldPoints(gameId: game.id, orientedTo: teams.first?.id),
                          markers: timelines.events(gameId: game.id).filter(TimelineText.isMarker),
                          teams: timelineTeams(teams, store: store), loading: timelines.replaying.contains(game.id))
        }
    }
}

/// Fil des événements (spec fonctionnalités §4).
struct TimelineSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]

    var body: some View {
        let timelines = store.timelines
        if !timelines.unavailable.contains(game.id) {
            TimelineCard(events: timelines.events(gameId: game.id), teams: timelineTeams(teams, store: store),
                         loading: timelines.replaying.contains(game.id))
        }
    }
}

/// Section « Joueurs » enrichie (spec fonctionnalités §3) : lignes du flux + détails + catalogues + sorts d'invocateur
/// (Leaguepedia pour une game jouée).
struct PlayersSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]
    let snapshot: GameSnapshot
    @Binding var selection: Int
    let onSelect: (PlayerSheetItem) -> Void

    var body: some View {
        let context = Self.context(store: store, game: game)
        let details = store.gameDetails.details[game.id]
        let rows = teams.map { team in
            team.id.map { PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: $0) } ?? []
        }
        BuildPlayersPanel(teams: teams, rows: rows, context: context, selection: $selection) { player, index in
            let team = teams.indices.contains(index) ? teams[index] : nil
            onSelect(PlayerSheetItem(player: player, teamCode: team?.code ?? "", tint: team.flatMap { store.tint(for: $0) },
                                     context: context, finished: game.state == .completed))
        }
    }

    /// Version et catalogues Data Dragon de la game, sorts d'invocateur de Leaguepedia (game jouée seulement).
    static func context(store: AppStore, game: GameRef) -> BuildContext {
        let version = store.dataDragon.knownVersion(forPatch: store.patches[game.id])
        return BuildContext(
            version: version,
            items: version.flatMap { store.dataDragon.items[$0] },
            runes: version.flatMap { store.dataDragon.runes[$0] },
            summoners: version.flatMap { store.dataDragon.summoners[$0] },
            summonerSpells: game.state == .completed ? (store.summonerSpells.spells[game.id] ?? [:]) : [:]
        )
    }
}
```

- [ ] **Step 5: Brancher le Détail**

Dans `App/Detail/MatchDetailView.swift` (ancres à relire à HEAD) :

1. Remplacer :

```swift
/// Finitions : capsule des pilules qui glisse, barre de gold et chiffres animés, révélation qui sort d'un flou,
/// squelettes de chargement, onglet des joueurs animé, retours haptiques (pilule, révélation, épingler, retirer).
struct MatchDetailView: View {
```

par :

```swift
/// Finitions : capsule des pilules qui glisse, barre de gold et chiffres animés, révélation qui sort d'un flou,
/// squelettes de chargement, onglet des joueurs animé, retours haptiques (pilule, révélation, épingler, retirer).
/// Fonctionnalités : « Regarder » (match en direct) et « Revoir la game N » (game jouée), draft, courbe de l'écart de gold,
/// joueurs avec icônes, objets, runes et sorts d'invocateur (fiche au toucher), fil des événements. Rien de tout cela pour
/// un match masqué : ni affichage, ni requête (`MatchDetailModel.featureGame`).
struct MatchDetailView: View {
```

2. Remplacer :

```swift
    @Namespace private var pillSelection
```

par :

```swift
    @Namespace private var pillSelection
    /// Fiche du joueur touché dans « Joueurs » (spec fonctionnalités §3).
    @State private var player: PlayerSheetItem?
```

3. Remplacer :

```swift
    private struct LoadKey: Equatable, Sendable {
        let game: Int?
        let revealed: Bool
    }
```

par :

```swift
    private struct LoadKey: Equatable, Sendable {
        let game: Int?
        let revealed: Bool
    }

    /// Ce qui relance les fonctionnalités de la game affichée (fil, détails, sorts) : une autre game, la révélation (la
    /// game passe de nil à la game affichée), la fin de la game.
    private struct FeatureKey: Equatable, Sendable {
        let gameId: String?
        let inProgress: Bool
    }

    /// Ce qui relance la version Data Dragon : une autre game, ou son patch enfin connu (première frame lue).
    private struct VersionKey: Equatable, Sendable {
        let gameId: String?
        let patch: String?
    }
```

4. Remplacer :

```swift
        .task(id: LoadKey(game: model.selectedGameNumber, revealed: store.settings.revealedMatchIds.contains(model.matchId))) {
            await model.loadSelectedGame(store: store)
        }
    }
```

par :

```swift
        .task(id: LoadKey(game: model.selectedGameNumber, revealed: store.settings.revealedMatchIds.contains(model.matchId))) {
            await model.loadSelectedGame(store: store)
        }
        .task(id: featureKey) { await model.runFeatures(store: store) }
        .task(id: versionKey) { await model.loadDataDragon(store: store) }
        // Chaque frame lue en direct (10 s) allonge le fil et la courbe ; nil pour un match masqué (`featureGame`).
        .onChange(of: featureSnapshot) { _, snapshot in
            if let snapshot {
                store.timelines.append(snapshot)
            }
        }
        .environment(\.dataDragon, store.dataDragon)
        .sheet(item: $player) { item in
            PlayerSheet(item: item)
                .environment(\.dataDragon, store.dataDragon)
                .presentationDetents([.medium, .large])
        }
    }

    private var featureKey: FeatureKey {
        let game = model.featureGame(store: store)
        return FeatureKey(gameId: game?.id, inProgress: game?.state == .inProgress)
    }

    private var versionKey: VersionKey {
        let game = model.featureGame(store: store)
        return VersionKey(gameId: game?.id, patch: game.flatMap { store.patches[$0.id] })
    }

    /// Dernière frame de la game des fonctionnalités ; nil pour un match masqué ou sans stats.
    private var featureSnapshot: GameSnapshot? {
        model.featureGame(store: store).flatMap { store.snapshots[$0.id] }
    }
```

5. Remplacer :

```swift
        header(event: event, details: details, teams: ordered, order: order, state: state, masked: masked, tint: tint)
        if masked {
```

par :

```swift
        header(event: event, details: details, teams: ordered, order: order, state: state, masked: masked, tint: tint)
        // « Regarder » (spec fonctionnalités §1) : match en direct non masqué seulement (l'image montre le score).
        if let watch = WatchLinks.live(event?.streams ?? details?.streams, inProgress: event?.state == .inProgress,
                                       masked: masked) {
            WatchButton(live: watch, onHaptic: { haptics.play($0) })
        }
        if masked {
```

6. Remplacer :

```swift
                gamePills(details)
                if details.statsDisabled || event?.statsDisabled == true {
```

par :

```swift
                gamePills(details)
                // « Revoir la game N » (spec fonctionnalités §1) : game jouée, même sans stats live.
                if let game = model.selectedGame(in: details), let replay = WatchLinks.replay(game, masked: masked) {
                    ReplayButton(gameNumber: game.number, link: replay, onHaptic: { haptics.play($0) })
                }
                if details.statsDisabled || event?.statsDisabled == true {
```

7. Remplacer :

```swift
    /// « Toucher pour révéler » (spec §8) : le score et les stats sortent d'un flou en fondu, avec un retour haptique.
    private func reveal() {
```

par :

```swift
    /// Fiche d'un joueur (spec fonctionnalités §3), avec un retour « sélection ».
    private func openPlayer(_ item: PlayerSheetItem) {
        haptics.play(.playerPicked)
        player = item
    }

    /// « Toucher pour révéler » (spec §8) : le score et les stats sortent d'un flou en fondu, avec un retour haptique.
    private func reveal() {
```

8. Remplacer :

```swift
                TeamStatsPanel(left: left, right: right, tint: store.tint(for: teams[0]) ?? Palette.accent)
                PlayersPanel(teams: teams, snapshot: snapshot,
                             selection: $model.playersTeamIndex.animation(Motion.animation(.snappy, reduceMotion: reduceMotion)))
```

par :

```swift
                // Draft, stats, courbe de gold, joueurs enrichis, fil (spec fonctionnalités §3-§5).
                DraftSection(game: game, teams: teams, snapshot: snapshot)
                TeamStatsPanel(left: left, right: right, tint: store.tint(for: teams[0]) ?? Palette.accent)
                GoldCurveSection(game: game, teams: teams)
                PlayersSection(game: game, teams: teams, snapshot: snapshot,
                               selection: $model.playersTeamIndex.animation(Motion.animation(.snappy, reduceMotion: reduceMotion)),
                               onSelect: { openPlayer($0) })
                TimelineSection(game: game, teams: teams)
```

Dans `App/Detail/StatsPanels.swift` (`PlayersPanel` n'a plus d'appelant) :

Supprimer (jusqu'à la fin du fichier) :

```swift

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
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
```

Dans `App/DA/Skeleton.swift` :

Remplacer :

```swift
/// Squelette du panneau des joueurs d'une game : sélecteur d'équipe, en-tête et cinq lignes « rôle · champion · KDA · CS »,
/// à peu près à la hauteur de `PlayersPanel`.
struct PlayersSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(height: 32, radius: 8)
            HStack {
                SkeletonBlock(width: 60, height: 9)
                Spacer()
                SkeletonBlock(width: 24, height: 9)
            }
            .frame(height: 14)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack {
                        SkeletonBlock(width: 28, height: 11)
                        SkeletonBlock(width: 90, height: 11)
                        Spacer()
                        SkeletonBlock(width: 52, height: 11)
                        SkeletonBlock(width: 28, height: 11)
                    }
                    .frame(height: 16)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joueurs en chargement")
    }
}

/// Squelette de la zone des stats d'une game : le panneau d'équipe, puis celui des joueurs. Il a la hauteur des deux vrais
/// panneaux : quand ils arrivent, le bouton « Épingler » en dessous ne saute pas.
struct GameStatsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsSkeleton()
            PlayersSkeleton()
        }
    }
}
```

par :

```swift
/// Squelette de la zone des stats d'une game : le panneau d'équipe, puis la section « Joueurs » enrichie
/// (`BuildPlayersSkeleton`, spec fonctionnalités §3), à la hauteur des vrais panneaux. La draft, la courbe de gold et le
/// fil arrivent avec la première frame, avec leurs propres gabarits.
struct GameStatsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsSkeleton()
            BuildPlayersSkeleton()
        }
    }
}
```

Vérifier qu'il ne reste aucun appelant : `grep -rn "PlayersPanel\|PlayersSkeleton" App Tests` ne doit rien rendre (sauf `BuildPlayersPanel` / `BuildPlayersSkeleton`).

- [ ] **Step 6: Brancher la carte**

Dans `App/Matches/TeamCardView.swift` (ancres à relire à HEAD) :

1. Remplacer :

```swift
        .buttonStyle(.pressable)
        if state.spoilerFree {
            RevealButton { reveal(event.id) }
        }
```

par :

```swift
        .buttonStyle(.pressable)
        // « Regarder » (spec fonctionnalités §1) : hors du lien (un bouton dans un lien ne recevrait pas le toucher), et
        // jamais pour un match masqué (l'image du stream montre le score).
        if let watch = WatchLinks.live(event.streams, inProgress: event.state == .inProgress, masked: state.spoilerFree) {
            WatchButton(live: watch, compact: true, onHaptic: { haptics.play($0) })
        }
        if state.spoilerFree {
            RevealButton { reveal(event.id) }
        }
```

2. Remplacer :

```swift
/// Finitions : lignes qui s'enfoncent au toucher, chiffres qui défilent, halo « en direct », lueur d'équipe pour un
/// match en direct non masqué, révélation qui sort d'un flou avec un retour haptique.
```

par :

```swift
/// Finitions : lignes qui s'enfoncent au toucher, chiffres qui défilent, halo « en direct », lueur d'équipe pour un
/// match en direct non masqué, révélation qui sort d'un flou avec un retour haptique.
/// Fonctionnalités : pastille « Regarder » sous le match en direct non masqué (spec fonctionnalités §1).
```

- [ ] **Step 7: Brancher les Réglages**

Dans `App/Settings/SettingsView.swift` :

1. Remplacer :

```swift
/// Réglages (spec §5.4) : mode de la Live Activity et À propos.
```

par :

```swift
/// Réglages (spec §5.4) : mode de la Live Activity, notifications de début de match (spec fonctionnalités §2) et
/// À propos.
```

2. Remplacer :

```swift
                    .glassCard(radius: Radius.inner, padding: 14)

                    SectionLabel(text: "Faille")
```

par :

```swift
                    .glassCard(radius: Radius.inner, padding: 14)

                    SectionLabel(text: "Notifications")
                    MatchRemindersSection(enabled: store.settings.matchRemindersEnabled,
                                          lead: store.settings.matchReminderLead, center: store.reminderCenter,
                                          setEnabled: { store.setMatchReminders(enabled: $0) },
                                          setLead: { store.setMatchReminderLead($0) })

                    SectionLabel(text: "Faille")
```

- [ ] **Step 8: Brancher les notifications (lancement, reprogrammation, toucher → Détail)**

Dans `App/RootView.swift` :

1. Remplacer :

```swift
struct RootView: View {
    @State private var tab: AppTab
    @ReduceMotion var reduceMotion
    /// Zoom carte → Détail (spec finitions §6) : les lignes des cartes en sont les sources, l'écran Détail la destination.
    @Namespace private var zoom

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }
```

par :

```swift
struct RootView: View {
    @State private var tab: AppTab
    /// Pile de l'onglet Matchs : toucher une notification de début de match y pousse le Détail du match (spec
    /// fonctionnalités §2).
    @State private var matchesPath: [MatchRoute] = []
    /// Notifications touchées (l'appli) ; nil : aperçus et tests.
    private let router: NotificationRouter?
    @ReduceMotion var reduceMotion
    /// Zoom carte → Détail (spec finitions §6) : les lignes des cartes en sont les sources, l'écran Détail la destination.
    @Namespace private var zoom

    init(tab: AppTab = .matches, router: NotificationRouter? = nil) {
        _tab = State(initialValue: tab)
        self.router = router
    }
```

2. Remplacer :

```swift
                NavigationStack {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
```

par :

```swift
                NavigationStack(path: $matchesPath) {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
```

3. Remplacer :

```swift
        .tint(Palette.accent)
    }
}
```

par :

```swift
        .tint(Palette.accent)
        .onChange(of: router?.pendingMatchId, initial: true) { _, _ in
            openPendingMatch()
        }
    }

    /// Notification touchée : onglet Matchs, et le Détail du match par-dessus la liste (transition standard : aucune ligne
    /// de carte n'en est la source).
    private func openPendingMatch() {
        guard let matchId = router?.consume() else { return }
        tab = .matches
        matchesPath = [MatchRoute(matchId: matchId)]
    }
}
```

Dans `App/FailleApp.swift` :

1. Remplacer :

```swift
import SwiftUI
```

par :

```swift
import SwiftUI
import UserNotifications
```

2. Remplacer :

```swift
        : AppStore(files: FileStore(directory: AppGroup.directory))
```

par :

```swift
        : AppStore(files: FileStore(directory: AppGroup.directory))
    /// Notification de début de match touchée → Détail du match (spec fonctionnalités §2).
    static let notificationRouter = NotificationRouter()
    /// Délégué de `UNUserNotificationCenter`, retenu ici : le centre ne garde qu'une référence faible.
    static let notificationDelegate = ReminderNotificationDelegate(router: notificationRouter)
```

3. Remplacer :

```swift
    @State private var store = AppRuntime.store
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
```

par :

```swift
    @State private var store = AppRuntime.store
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Avant la fin du lancement : une notification touchée qui lance l'appli doit trouver son délégué.
        if !RunEnvironment.isTesting {
            UNUserNotificationCenter.current().delegate = AppRuntime.notificationDelegate
        }
    }

    var body: some Scene {
```

4. Remplacer :

```swift
                RootView()
                    .environment(store)
```

par :

```swift
                RootView(router: AppRuntime.notificationRouter)
                    .environment(store)
                    // Notifications de début de match (spec fonctionnalités §2) : reprogrammées dès que le calendrier, les
                    // équipes suivies, les révélations ou les réglages changent le plan (`reminderSignature`).
                    .task(id: store.reminderSignature) {
                        await store.syncReminders(center: store.reminderCenter)
                    }
```

- [ ] **Step 9: Écrire les aperçus**

Créer `Tests/FailleTests/FeaturesSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func featureDetail(_ matchId: String) -> some View {
        NavigationStack { MatchDetailView(matchId: matchId) }.environment(AppStore(preview: .standard))
    }

    /// Détail d'un match en direct révélé (spec fonctionnalités §1, §3-§5) : « Regarder », draft, stats, courbe de gold,
    /// joueurs avec icônes, objets et runes (vignettes de repli : aucun réseau), fil de la game. Trois captures : haut,
    /// milieu, bas.
    @Test func detailLiveWithFeatures() async throws {
        let top = try await Snapshot.write(featureDetail(SampleData.kcMatchId), named: "21-detail-direct")
        expectNotBlank(top)
        let middle = try await Snapshot.write(featureDetail(SampleData.kcMatchId).defaultScrollAnchor(.center),
                                              named: "21-detail-direct-milieu")
        expectNotBlank(middle)
        let bottom = try await Snapshot.write(featureDetail(SampleData.kcMatchId).defaultScrollAnchor(.bottom),
                                              named: "21-detail-direct-bas")
        expectNotBlank(bottom)
    }

    /// Détail d'un match terminé (KC 1 – 3 G2, game 4) : « Revoir la game 4 », draft, courbe sous zéro (G2 a gagné),
    /// joueurs avec leurs sorts d'invocateur (Leaguepedia), fil complet.
    @Test func detailFinishedWithFeatures() async throws {
        let top = try await Snapshot.write(featureDetail(SampleData.kcG2MatchId), named: "22-detail-termine")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(featureDetail(SampleData.kcG2MatchId).defaultScrollAnchor(.bottom),
                                              named: "22-detail-termine-bas")
        expectNotBlank(bottom)
    }

    /// Fiche du jungler de G2 (game 4 terminée) : sorts d'invocateur de Leaguepedia, ordre des sorts, part des dégâts.
    @Test func playerSheetOfAFinishedGame() async throws {
        let store = AppStore(preview: .standard)
        let game = try #require(store.details[SampleData.kcG2MatchId]?.match.games.first { $0.number == 4 })
        let rows = PlayerBuilds.rows(snapshot: SampleData.kcG2Final, details: store.gameDetails.details[game.id],
                                     teamId: "g2")
        let item = PlayerSheetItem(player: rows[1], teamCode: "G2", tint: nil,
                                   context: PlayersSection.context(store: store, game: game), finished: true)
        let url = try await Snapshot.write(PlayerSheet(item: item).environment(\.dataDragon, store.dataDragon),
                                           named: "23-fiche-joueur")
        expectNotBlank(url)
    }

    /// Carte de KC en direct avec sa pastille « Regarder » (spec fonctionnalités §1).
    @Test func cardWithWatchButton() async throws {
        let store = AppStore(preview: .standard)
        let card = try #require(store.cards.first { $0.team.id == "kc" })
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Carte", subtitle: "En direct · Regarder")
                TeamCardView(card: card)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .environment(store)
        let url = try await Snapshot.write(board, named: "24-carte-regarder")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 10: Checklist iPhone « Fonctionnalités »**

Dans `docs/superpowers/notes/2026-10-14-checklist-iphone.md` :

1. Remplacer :

```markdown
# Faille — checklist de test sur l'iPhone (étapes 2, 3, 4 et finitions)
```

par :

```markdown
# Faille — checklist de test sur l'iPhone (étapes 2, 3, 4, finitions et fonctionnalités)
```

2. Remplacer :

```markdown
15. **Fluidité** : pendant un match en direct, faire défiler Matchs et le Détail : aucun à-coup ; le téléphone ne chauffe pas plus qu'avant.
```

par :

```markdown
15. **Fluidité** : pendant un match en direct, faire défiler Matchs et le Détail : aucun à-coup ; le téléphone ne chauffe pas plus qu'avant.

## E. Fonctionnalités (Regarder, notifications, draft et builds, fil, courbe de gold)

À faire avec la même IPA (`C:\Users\Dan\Downloads\faille\Faille.ipa`, installée comme au §0). Un match en direct d'une équipe suivie sert pour E.1-E.3 et E.9-E.13 ; un match terminé depuis plus d'une heure pour E.4, E.14 et E.15 ; les notifications se testent avant un match (E.5-E.8). Pour chaque ligne : OK / KO + une remarque.

1. **Regarder (carte)** : pendant un match en direct d'une équipe suivie, sa carte montre une pastille « Regarder » sous le score. La toucher (léger retour) ouvre le stream français — l'app Twitch si elle est installée, sinon Safari. Appui long : un menu liste les autres streams (« Anglais · Twitch », « Anglais · YouTube »…) ; en choisir un l'ouvre.
2. **Regarder (Détail)** : dans le Détail du même match, sous l'en-tête, « Regarder · Français · Twitch » fait la même chose (appui long : les autres langues).
3. **Regarder et anti-spoiler** : un match en direct d'une équipe en anti-spoiler n'a **aucun** « Regarder », ni sur la carte ni dans le Détail, tant qu'il n'est pas révélé ; après « toucher pour révéler », la pastille apparaît.
4. **Revoir** : Détail d'un match terminé (révélé) → choisir une game → « Revoir la game N · Anglais · YouTube » ouvre la rediffusion au début de cette game. Un match masqué n'en montre aucune.
5. **Notifications — activer** : engrenage → Réglages → section « Notifications » → « Début de match » : iOS demande l'autorisation → **Autoriser**. Choisir 5 min. (Si tu refuses : l'interrupteur se recoupe et un texte dit où l'autoriser.)
6. **Notification reçue** : 5 min avant le prochain match d'une équipe suivie, une notification « KC vs C9 dans 5 min » / « Mondial · … · Bo5 », sans aucun score. La toucher ouvre Faille sur le Détail de ce match, même si Faille était fermée. Noter l'heure exacte d'arrivée.
7. **Notifications et anti-spoiler** : une équipe en anti-spoiler dont le dernier match est masqué ne déclenche **aucune** notification pour son prochain match (comme sa ligne « Prochain · masqué ») ; une fois ce dernier match révélé et Faille rouverte, la notification de son prochain match est programmée.
8. **Notifications — couper** : couper « Début de match » → plus aucune notification de Faille (les autres applis ne sont pas touchées).
9. **Draft** : Détail d'un match en direct (révélé) → au-dessus des stats, deux rangées de cinq icônes de champions, une par équipe, l'équipe suivie à gauche et à sa couleur.
10. **Joueurs** : pour chaque joueur, icône du champion avec son niveau, pseudo et rôle, « Champion · KDA · CS · gold », six cases d'objets + la balise (ronde), rune principale et arbre secondaire ; le jungler montre l'icône Châtiment. Les objets changent au fil de la game (une minute de décalage au plus avec les stats).
11. **Fiche d'un joueur** : toucher un joueur (petit clic) → fiche : KDA, gold, CS, participation aux kills, balises posées / détruites, part des dégâts (barre), ordre de montée des sorts (icônes Q W E R, puis une lettre par niveau, R en cyan), runes et objets nommés. « Fermer » ou un glissement vers le bas la ferme.
12. **Fil de la game** : sous les joueurs, « Fil de la game » : les événements du plus récent au plus ancien (« 18:42 · KC · 2 kills · … », « Drake infernal », « Baron », « Tour »…), icônes et couleurs des équipes ; il s'allonge pendant la game ; « Tout le fil » le déplie.
13. **Courbe de gold** : « Écart de gold » : au-dessus de zéro (couleur de l'équipe de gauche) quand elle mène, en dessous sinon, petits repères des drakes et des barons ; elle s'allonge pendant la game. Ouvrir le Détail en milieu de game : la courbe et le fil se remplissent depuis le début en une vingtaine de secondes (relecture), puis suivent le direct.
14. **Game terminée** : Détail d'un match terminé → courbe et fil complets de la game choisie (première ouverture : une vingtaine de secondes ; ensuite instantané, même en mode avion).
15. **Sorts d'invocateur** : une heure ou plus après la fin d'un match, ouvrir son Détail puis la fiche d'un joueur : ses deux sorts d'invocateur (« Saut éclair », « Téléportation »…), « Source : Leaguepedia ». Juste après le match : seul le Châtiment du jungler, « Leaguepedia n'a pas encore cette game » (Faille ne redemande pas avant une heure : c'est voulu, le wiki limite les requêtes).
16. **Icônes hors ligne** : après avoir vu un Détail en ligne, passer en mode avion et le rouvrir : icônes de champions, d'objets et de runes toujours là.
17. **Anti-spoiler (Détail)** : Détail d'un match masqué : ni draft, ni joueurs, ni fil, ni courbe, ni « Revoir », ni « Regarder » — seulement l'en-tête et « toucher pour révéler ».
18. **Fluidité** : pendant un match, faire défiler le Détail (draft, courbe, joueurs, fil) : aucun à-coup ; le téléphone ne chauffe pas plus qu'avant.
```

- [ ] **Step 11: Vérifier le périmètre, committer, pousser**

```bash
git status --short
grep -rn "PlayersPanel\|PlayersSkeleton" App Tests | grep -v "BuildPlayers"
```

Expected : seulement les fichiers de la ligne T7 de la matrice ; le `grep` ne rend rien.

```bash
git add App/Store/AppStore.swift App/Detail App/DA/Skeleton.swift App/Matches/TeamCardView.swift \
  App/Settings/SettingsView.swift App/RootView.swift App/FailleApp.swift App/Preview Shared/Preview/SampleData.swift \
  Tests/FailleTests/FeaturesIntegrationTests.swift Tests/FailleTests/FeaturesSnapshotTests.swift \
  docs/superpowers/notes/2026-10-14-checklist-iphone.md
git commit -m "feat(app): fonctionnalités branchées — Regarder et Revoir, notifications de début de match, draft et builds, fil et courbe de gold, sorts d'invocateur ; rien pour un match masqué" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin fonc/appli-t7-integration
```

- [ ] **Step 12: CI de la branche (une fois, avant fusion)**

```bash
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
gh run download "$RUN" --name Faille-apercus --dir "$HOME/Downloads/faille-apercus-$RUN"
```

Expected : jobs `build` et `apercus` verts, toutes les suites vertes (dont `FeaturesIntegrationTests`, 7 tests, et toutes les suites d'avant). Aperçus à regarder :
- `21-detail-direct*.png` : en-tête KC – C9 « En direct · Game 2 », « Regarder · Français · Twitch », pilules, draft (vignettes), stats, courbe au-dessus de zéro (KC +2,1k), joueurs à deux étages, fil (« 18:09 · KC · Kill · KC Bot »…), « Retirer de l'écran verrouillé » en bas ;
- `22-detail-termine*.png` : « Terminé », score 1 – 3, pilules G1-G4, « Revoir la game 4 · Anglais · YouTube », draft KC / G2, courbe sous zéro (G2 +15,2k, repères drakes et barons), joueurs avec deux sorts d'invocateur chacun, fil complet ;
- `23-fiche-joueur.png` : fiche de « G2 Jungle » (Lee Sin), Saut éclair / Châtiment avec « Source : Leaguepedia » (noms d'id sans catalogue dans l'aperçu : « SummonerFlash », « SummonerSmite ») ;
- `24-carte-regarder.png` : carte de KC avec la pastille « Regarder » sous les stats ;
- inchangés hors fonctionnalités : `06-detail-masque.png` (T1 – FLY : en-tête et « toucher pour révéler » seulement, ni « Regarder » ni rien d'autre), `07-reglages.png` (avec la section Notifications), `01-matchs.png` (la carte de KC gagne sa pastille).
Échec : `gh run view "$RUN" --log-failed`, corriger, commit, push, relancer.

- [ ] **Step 13: Fusion et vérification finale sur `main` (contrôleur)**

```bash
git checkout main && git pull --ff-only origin main
git merge --no-ff fonc/appli-t7-integration -m "Merge fonc/appli-t7-integration : intégration du lot fonctionnalités" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'); echo "$RUN"
gh run watch --exit-status "$RUN"
bash scripts/lolkit.sh test
gh run download "$RUN" --name Faille-ipa --dir "$HOME/Downloads/faille-ipa-$RUN"
```

Expected : CI `iOS` verte sur `main` ; `Test run with 320 tests in 37 suites passed` ; l'IPA copiée pour Dan sous `C:\Users\Dan\Downloads\faille\Faille.ipa` (même nom que pour les sections précédentes de la checklist). Dan déroule ensuite la section E de la checklist iPhone ; chaque KO devient une correction.


---

## Self-review

**Couverture de la spec fonctionnalités**

| Exigence | Tâche(s) |
|---|---|
| Principes : LoLKit calcule, l'appli affiche | T1-T6 n'appellent que `StreamPicker`, `MatchReminders`, `DataDragon`, catalogues, `LoLClient.details`, `LeaguepediaClient` + `SpellMatcher` + `SpellLookupPolicy`, `GameTimeline`, `GoldSeries` ; seules les règles propres à l'appli (cache, calendrier de relecture, règle Leaguepedia de l'appli) sont dans `App/` |
| Principes : anti-spoiler d'abord | `WatchLinks` (masqué → rien), branche « non masqué » du Détail, `MatchDetailModel.featureGame` (garde unique de toutes les requêtes), `MatchReminders.plan` (T2), tests `maskedMatchLoadsNoFeature`, `watchOnlyForTheUnmaskedLiveMatch`, `maskedOrFinishedMatchHasNoWatchButton`, aperçu `06-detail-masque` |
| Principes : sobriété réseau | `DiskCache` (T3) ; versions 24 h, catalogues et images une fois (T3) ; `details` 60 s / une fois (T6) ; relecture à la demande, gardée, reprise (T4) ; Leaguepedia une requête par match sous double règle (T5) ; patch sans requête de plus (T7, `loadWindow`) |
| Principes : sources sans clé, User-Agent identifiable | Data Dragon (T3), Leaguepedia via `LeaguepediaClient` (en-tête déjà dans LoLKit) (T5) ; aucun secret ajouté |
| §1 « Regarder » : fr-FR, sinon en-US, sinon le premier ; Twitch / YouTube / AfreecaTV ; carte + Détail ; appui long : autres streams ; `openURL` | T1 (`WatchLinks.live`, `WatchButton` avec `Menu` + `primaryAction`), T7 (carte, Détail) |
| §1 « Revoir la game N » avec `&t=`, absent si masqué | T1 (`WatchLinks.replay`, `ReplayButton`), T7 (Détail, game choisie) |
| §2 notifications locales, programmées à chaque rafraîchissement du calendrier / des équipes / des réglages | T2 (`ReminderSync`, `reminderSignature`), T7 (`.task(id:)` dans `FailleApp`) |
| §2 réglage désactivé par défaut, autorisation à l'activation, délai 5/15/30 (15) | T2 (`AppSettings`, `MatchRemindersSection`), T7 (setters, section dans Réglages) |
| §2 sélection `Presenter.nextLine`, 60 au plus, identifiant stable ; texte sans score ; toucher → Détail | LoLKit `MatchReminders` ; T2 (requête iOS, `ReminderPayload`, délégué, routeur) ; T7 (`RootView` + chemin typé, délégué posé dans `FailleApp.init`) |
| §3 version Data Dragon (patch → `major.minor`), cache 24 h | T3 (`version(forPatch:)`), T7 (`patches`, `loadDataDragon`) |
| §3 champions (draft, sans requête de plus) | T6 (`PlayerBuilds.draft`, `DraftStrip`), T7 (`DraftSection` depuis la frame déjà lue) |
| §3 objets (6 + balise), rune principale + arbre secondaire, ordre des sorts (icônes Q/W/E/R + passif dans le catalogue), part des dégâts, participation, balises | T6 (`GameDetailsStore`, `BuildPlayersPanel`, `PlayerSheet`, `AbilityOrderView`, `ShareBar`) |
| §3 sorts d'invocateur des games terminées par Leaguepedia (champions + ± 3 h), cache disque, rien si le wiki n'a pas la game ; Châtiment du jungler en direct | T5 (store, règle), T6 (`PlayerBuilds.summonerSpells`), T7 (`lookUpSpells`, contexte) |
| §3 fréquence `details` 60 s Détail ouvert / une fois jouée ; JSON et images sur disque, décodés hors du `body` | T6 (`follow`), T3 (`image(_:)` détaché, `DDragonIcon` sans lecture de fichier) |
| §3 écran : section « Joueurs » (icône + niveau, pseudo, KDA, CS, gold, objets, runes) ; appui → fiche ; draft en haut | T6 (vues), T7 (ordre du Détail, feuille) |
| §4 fil : différences de frames (LoLKit), direct à chaque frame lue, relecture 60 s à la demande gardée, liste inversée, icônes DA, couleur d'équipe | T4 (`TimelineStore`, `TimelineCard`), T7 (`append` à chaque frame, `TimelineSection`) |
| §5 courbe : réorientée vers l'équipe suivie (gauche), Swift Charts `AreaMark` / `LineMark`, couleur de l'équipe en tête au-dessus de zéro, l'autre en dessous, repères barons / drakes, prolongée en direct | T4 (`GoldChartCard`, `GoldChartData`), T7 (`GoldCurveSection`, `orientedTo: teams.first?.id`) |
| Vérification : aperçus PNG (Détail en direct, terminé, masqué ; carte « Regarder » ; réglages des notifications) | T7 (`21-…`, `22-…`, `24-…`, `06-…`, `07-…`), T1-T6 (planches 16-20b) |
| Vérification : tests hébergés anti-spoiler et notifications (sélection et texte) | T7 `FeaturesIntegrationTests`, T2 `RemindersTests` / `RemindersStoreTests` |
| Vérification : checklist iPhone « Fonctionnalités » | T7 step 10 (section E, 18 points) |

**Anti-spoiler, relu ligne à ligne :** pour un match masqué, `WatchLinks.live` / `.replay` rendent nil (carte et Détail) ; le Détail n'a que l'en-tête et « toucher pour révéler » (aucune section de fonctionnalité n'est construite) ; `featureGame` rend nil, donc `runFeatures`, `loadDataDragon` et la reprise du fil ne font rien, `lookUpSpells` vérifie aussi le masquage ; `featureSnapshot` est nil (rien n'est ajouté au fil) ; `loadWindow` (seul à remplir `patches`) n'est jamais appelé pour un match masqué (existant) ; `DDragonIcon` ne demande une image que si sa vue existe ; les notifications passent par `MatchReminders.plan` (F1 + C) et ne portent que les codes, le délai, la ligue, le bloc et le Bo. Résidu connu (spec) : la révélation reste l'unique porte d'entrée.

**Sobriété réseau, relue :** aucune requête dans les aperçus et les tests (stores `transport: nil`, `ScriptedTransport`) ; une seule liste des versions par 24 h (et pas plus d'un essai par minute en panne) ; catalogues et images une fois par version ; une image absente n'est plus redemandée ; `details` : boucle de 60 s liée à la tâche de l'écran (annulée en le quittant), une seule lecture pour une game jouée ; relecture : une fenêtre par minute, 0,5 s entre deux, 90 au plus, reprise sans relire ce qui est sur disque ; Leaguepedia : jamais avant fin + 30 min, jamais deux essais à moins d'une heure, 3 au plus, plus rien après un succès, aucune requête pendant le développement.

**Fichiers disjoints :** vérifié sur la matrice — chaque fichier existant modifié a un seul propriétaire ; les tâches d'une même vague créent des dossiers distincts (`App/Watch`, `App/Reminders` + `App/Store/AppStore+Reminders.swift`, `App/Cache` + `App/DataDragon` ; puis `App/Timeline`, `App/Spells`, `App/Builds`) ; noms de suites, de fichiers de test, de types et d'aperçus uniques ; les aides des tests sont `private` (fichier) ou propres à une suite.

**API à risque et repli prévu :**
- Délégué `UNUserNotificationCenterDelegate` en variantes à gestionnaire de fin : le test `delegateAnswersBothCallbacks` (sélecteurs) attrape une signature ignorée ; repli : variantes `async` (T2 step 7).
- `Menu(content:label:primaryAction:)` + `.menuStyle(.button)` + `.buttonStyle(.pressable)` : compile quoi qu'il arrive ; seul le rendu d'appui peut différer (noté pour la checklist).
- Swift Charts (`AreaMark(x:yStart:yEnd:)`, `foregroundStyle(by:)`, `chartForegroundStyleScale(domain:range:)`, `RuleMark.annotation`) : API iOS 16 ; repli si le vérificateur de types peine : contenus en `@ChartContentBuilder` (T4 step 6).
- `@Entry var dataDragon: DataDragonStore? = nil` : repli `EnvironmentKey` classique (T3 step 5).
- `Task.detached` avec liste de capture `[transport = self.transport, cache = self.cache]` et `UIImage` transporté dans `LoadedImage: @unchecked Sendable` (même schéma que `LogoImages`) ; logique vérifiée sous Linux avec un `UIImage` de substitution.

**Cohérence des types :** les noms et signatures des blocs « Produces » sont ceux du code des tâches (copié depuis la copie compilée) : `WatchLinks.live(_:inProgress:masked:)` / `.replay(_:masked:)`, `WatchButton(live:compact:onHaptic:)`, `ReplayButton(gameNumber:link:onHaptic:)`, `Haptic.watch` / `.playerPicked` ; `ReminderCenter`, `InertReminderCenter`, `SystemReminderCenter`, `ReminderSync.apply(_:enabled:center:)`, `NotificationRouter.consume()`, `ReminderNotificationDelegate(router:)`, `AppStore.reminderSignature`, `syncReminders(center:now:)`, `MatchRemindersSection(enabled:lead:center:denied:setEnabled:setLead:)` ; `DiskCache(root:)`, `DataDragon.cachePath(for:)`, `DataDragonStore(transport:cache:)`, `.knownVersion(forPatch:)`, `.loadCatalogs(version:)`, `.champion(version:championId:)`, `\.dataDragon`, `DDragonIcon(url:size:radius:fallback:)` ; `TimelineStore(transport:cache:)` / `(preview:)`, `.load(gameId:inProgress:now:)`, `.append(_:)`, `.events(gameId:)`, `.goldPoints(gameId:orientedTo:)`, `.replaying`, `.unavailable`, `TimelineTeam(id:code:tint:)`, `TimelineCard(events:teams:loading:)`, `GoldChartCard(points:markers:teams:loading:)`, `TimelineSamples.frames(_:start:final:)` (`.kcLive`, `.redWins`) ; `SummonerSpellsStore(transport:cache:)` / `(preview:)`, `.spells`, `.lookUp(matchId:gameIds:matchEnd:now:)` ; `GameDetailsStore(transport:cache:)` / `(preview:)`, `.details`, `.follow(gameId:finished:)`, `PlayerBuilds.rows(snapshot:details:teamId:)` / `.draft(snapshot:teamIds:)`, `BuildSamples.details(for:)`, `DraftTeam`, `DraftStrip(teams:version:)`, `BuildContext`, `BuildPlayersPanel(teams:rows:context:selection:onSelect:)`, `BuildPlayersSkeleton`, `PlayerSheetItem(player:teamCode:tint:context:finished:)`, `PlayerSheet(item:)` — et T7 les appelle exactement ainsi. `TimelineSamples.frames(.redWins, …).last == SampleData.kcG2Final` est vérifié (test `previewSamplesAgreeWithTheStats`).

**Recherche de trous :** aucun « TBD », « à compléter », « comme la tâche N » ; chaque étape de code donne le fichier complet ou le remplacement exact ; les commandes ont leur sortie attendue.
