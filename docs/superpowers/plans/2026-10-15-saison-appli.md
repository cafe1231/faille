# Saison (appli) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** faire de Faille le « compagnon de saison » côté appli — collecte progressive des stats de saison (`SeasonStore`), onglet **Accueil** en premier, page **équipe**, **duels** de joueurs et d'équipes dans le Détail, page **joueur**, **classements** et tableaux, **calendrier** complet, **ligues suivies**, **premier lancement**, puis **accessibilité et langue** (catalogue fr/en, VoiceOver, Dynamic Type) — en consommant les modules LoLKit du plan parallèle, sans jamais rien montrer ni rien demander au réseau pour un match masqué. Terminé quand les planches PNG des nouveaux écrans sont vertes en CI (anti-spoiler visible : « N matchs masqués », « Classement masqué »), que les tests hébergés de la collecte passent (ordre, ≥ 2 s entre deux requêtes, arrêt à 300, masqué jamais demandé, reprise) et que le lien profond des notifications ouvre toujours le Détail dans Matchs.

**Architecture :** un store `@Observable` de plus, `SeasonStore` (`App/Season/`), possédé par `AppStore` : il lit `cache/season/` hors du fil principal au lancement, publie les `GameSummary`, tournois, résultats et classements, et exécute la collecte (`SeasonCrawler`) dans la boucle du premier plan (`AppStore.poll`), à travers un `PacedTransport` qui impose la cadence de `CrawlPacer` à **toutes** ses requêtes ; la logique (quoi lire, dans quel ordre, quand réessayer, agrégats, masquage, « à ne pas rater », activité, tableaux, calendrier) est dans LoLKit. Chaque écran vit dans son dossier (`App/Home/`, `App/TeamPage/`, `App/Duel/`, `App/PlayerPage/`, `App/Standings/`, `App/Calendar/`, `App/Leagues/`, `App/Onboarding/`) avec un petit fichier de logique sans interface (testé) et des vues qui ne reçoivent que des valeurs ou lisent `AppStore`. Deux tâches d'intégration seules touchent les fichiers partagés : **I1** (navigation à trois onglets avec `NavigationPath` et `.failleDestinations`, `AppStore.season`, ligues suivies, révélation des classements, onboarding, icônes, composants communs, coquilles des écrans) et **I2** (branchements dans le Détail, les cartes, Équipes, Matchs, et le premier lancement). **P2** passe ensuite seule sur tout `App/` (catalogue, VoiceOver, Dynamic Type).

**Tech Stack :** Swift 6 (appli, extension, tests), SwiftUI iOS 26 (`NavigationPath`, `navigationDestination(for:)`, `fullScreenCover`, `TabView` à onglets `Tab`, `ScrollView` horizontales, `sensoryFeedback`), Observation, `UIFontMetrics` (Dynamic Type), Swift Testing (tests hébergés + planches PNG `Snapshot.write`), LoLKit (Swift 6.2), XcodeGen, GitHub Actions `macos-26` (workflow `iOS`, branches `nuit2/**` ajoutées par I1 étape 0) et `ubuntu` (workflow `LoLKit` + contrôle des chaînes de P2), `gh`, Python 3 (script `scripts/strings-check.py`, bibliothèque standard seulement).

**Spec :** `docs/superpowers/specs/2026-10-15-faille-saison-design.md` (**contraignante** : §0-§4, en particulier §1.5-§1.8 socle, §2 Accueil, §3 écrans, §4 découpage) ; `.superpowers/goal-nuit-2.md` (objectif, règles de données, politique CI) ; spec principale `2026-10-13-faille-design.md` (§8 anti-spoiler, §9 DA : contraignants) ; finitions `2026-10-14-faille-finitions-design.md` (`Motion`, `@ReduceMotion`, `PressableStyle`, `HapticTrigger`, `SkeletonBlock`, cascade : **réutilisés**, rien de nouveau) ; fonctionnalités `2026-10-14-faille-fonctionnalites-design.md` (Data Dragon, sobriété réseau). Modules consommés : plan LoLKit parallèle `docs/superpowers/plans/2026-10-15-saison-lolkit.md` (tâches L1-L8).

## Global Constraints

- iOS minimum **26.0** ; appli, extension et tests en Swift 6 (`SWIFT_VERSION: "6.0"`) ; LoLKit en Swift 6.2 ; iPhone + iPad.
- **Pas de Mac** : le code iOS ne se compile et ne se teste qu'en CI (GitHub Actions `macos-26`, Xcode 26). Le code sans SwiftUI de ce plan a été compilé et testé sous Linux (voir « Vérifié avant d'écrire ce plan ») ; les vues ne le sont qu'en CI.
- **Politique CI (objectif nuit 2) : aucune attente après chaque étape.** On commit et on pousse librement ; l'implémenteur attend **une seule fois**, à la fin de sa tâche, la CI iOS du dernier commit de sa branche, retrouvée par le SHA **complet** : `gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId'` (le run peut mettre quelques secondes à apparaître ; un SHA court ne renvoie rien), puis `gh run watch --exit-status <id>` ; échec : `gh run view <id> --log-failed`, corriger, pousser, attendre le nouveau dernier commit. `concurrency` (déjà dans `ios.yml`) annule les runs dépassés. Tâche qui touche `scripts/` ou `.github/workflows/lolkit.yml` (P2) : même chose avec `--workflow LoLKit`.
- **Exécution en parallèle** : une tâche = une branche `nuit2/appli-<id>-<slug>` (ex. `nuit2/appli-a2-page-equipe`) dans son propre worktree (`git worktree add ../faille-<id> -b <branche> main`), poussée avec `git push -u origin <branche>` ; jamais de push sur `main` depuis une tâche (le contrôleur fusionne côté serveur), **sauf l'étape 0 de I1** (une ligne de `ios.yml`, poussée par le contrôleur sur `main` au début du lot). Une tâche ne crée et ne modifie **que** les fichiers de sa ligne de la « Matrice des fichiers ».
- **Ancres** : chaque « Remplacer … par … » cite le texte réel d'`origin/main` à `4e37f00` (identique à `ab700f5` pour `App/`, `Shared/`, `Tests/`, `.github/`, `project.yml`) ou, pour I2, le texte laissé par I1 dans ce plan (c'est dit à chaque fois). **Avant chaque remplacement, l'implémenteur relit l'ancre à la tête de sa branche** (`git pull --ff-only origin main` au départ, puis lecture du fichier) **et l'adapte si elle a bougé, sans changer le sens** ; c'est obligatoire, d'autres tâches fusionnent pendant le lot.
- **Contrat LoLKit** : les noms et signatures du tableau « Contrat LoLKit consommé » sont relevés sur le vrai code (`origin/main` `4e37f00` pour L1-L6 et L8 ; plan LoLKit pour L7, pas encore fusionnée). Les tâches de l'appli démarrent **après** la fusion des tâches LoLKit dont elles dépendent ; **avant d'écrire du code, l'implémenteur relit les signatures à la tête de sa branche** (`grep -rn "public" LoLKit/Sources/LoLKit/{Season,Home,Calendar}`) et adapte les appels si elles ont bougé ; **LoLKit fait foi sur les noms, ce plan sur le comportement**. Si un point d'entrée manque, la tâche écrit la même règle en fonction privée de son fichier de logique (testée) et le note dans le journal (« Ruling: … — pourquoi — coût si faux »).
- **Anti-spoiler (contraignant, spec §8 et saison §1.8)** : pour un match masqué, rien n'est affiché ni demandé au réseau — score, vainqueur, nombre de games, composition, ligne « Cette game », stats de ses games ; toute ligne de match passe par `Presenter.scoreLine` (`store.scoreLine`) ; tout « prochain match » par `Presenter.nextLine` ; toute stat de saison reçoit `store.seasonMasked` ; un match masqué se compte (« N matchs masqués »), jamais ses games ; un classement est masqué selon `StandingsMasking` (révélation par tournoi, qui ne révèle aucun match). Aucune animation ne trahit un match masqué.
- **Sobriété réseau (contraignant)** : la collecte ne tourne qu'au premier plan (tâche de `AppStore.poll`, annulée avec la scène), jamais pendant un réveil d'arrière-plan ; **toutes** ses requêtes (énumération, paliers A/B, page de calendrier, classement ouvert à la demande) passent par le `PacedTransport` de `SeasonStore` : ≥ 2 s entre deux requêtes, recul 4-8-16-32-60 s sur 429/5xx/réseau, arrêt après 5 échecs d'affilée ou **300 requêtes par session**. Aucune requête n'est attendue pour afficher un écran (cache d'abord, squelettes sinon). Pas de requête Leaguepedia nouvelle.
- **Jamais de chiffre inventé** : une stat absente s'écrit « — » (`SeasonFormat.missing`) ; un vainqueur déduit porte l'étiquette « estimé ».
- **DA et finitions réutilisées** : `.glassCard` (verre neutre, ou teinté par la couleur d'une équipe suivie), `Palette`, `IconView` (icônes du catalogue, jamais de SF Symbols ni d'emoji), Sora — **nouveaux écrans en `.sora(_:)`** (créé par I1), `Motion` (aucune durée en dur), `@ReduceMotion`, `.buttonStyle(.pressable)` sur toute surface touchable (≥ 44 pt), `HapticTrigger` posé sur l'écran (cas existants seulement : `.follow`, `.unfollow`, `.reveal`, `.gamePicked` pour les pilules, `.playerPicked` pour un joueur, `.spoilerToggle`), `SkeletonBlock` au gabarit de chaque bloc pendant le chargement, cascade d'apparition (≤ 8 éléments, une fois) ; **aucune animation continue dans les listes** (le halo « en direct » seulement dans la section « En direct maintenant » de l'Accueil, 3 lignes au plus).
- **Accessibilité dès l'écriture** : chaque icône seule a un `accessibilityLabel` ; scores lus « Karmine Corp 2, G2 1 », masqué « Score masqué », pastilles de forme « Victoire / Défaite / Masqué », barres de duel « KDA : Canna 3,4, BrokenBlade 4,1 ».
- **Chaînes prêtes pour le catalogue (P2)** : tout texte affiché est un littéral français dans `Text("…")`, `Label("…")`, `Button("…")`, `.accessibilityLabel("…")` ou, quand un composant prend une `String` (`ScreenHeader`, `SectionLabel`, `NoteCard`, textes calculés), `String(localized: "…")` — jamais une `String` littérale nue passée à un composant (elle échapperait au catalogue et au contrôle de P2). Interpolations permises (`"\(n) matchs masqués"`).
- **Aperçus PNG figés** (`Snapshot.write`, « Réduire les animations » forcé, `.environment(\.seasonNow, …)` pour un « aujourd'hui » fixe : le 15/10/2026 15:05 UTC) : chaque PNG > 100 000 octets (`expectNotBlank`) ; images = monogrammes et vignettes de repli (aucun réseau dans les tests, aucune image de Riot dans le dépôt). Nouveaux PNG : `25-accueil` (+ `-bas`), `25b-accueil-sans-suivi`, `25c-accueil-collecte`, `26-equipe` (+ `-bas`), `26b-equipe-masquee`, `26c-equipe-chargement`, `27-duel`, `27b-duel-masque`, `28-joueur`, `28b-joueur-masque`, `29-classement`, `29b-classement-masque`, `29c-tableau-mondial`, `30-calendrier`, `31-ligues`, `32-onboarding-1` à `-3`, `33-detail-duel`, `33b-matchs-saison`, `34-grand-texte` (P2).
- **Lien profond inchangé** : toucher une notification ouvre l'onglet **Matchs** et pousse le Détail (`RootNavigation.deepLink`, testé par I1) ; `RemindersTests` reste vert.
- **Garde-fou de régression** : planches et tests existants verts (les planches `01-matchs`, `03-equipes`, `21`/`22-detail-*` changent de contenu après I2 : elles doivent rester non vides) ; Détail, widgets, Live Activity et notifications inchangés dans leur comportement.
- Textes de l'interface en français, identifiants en anglais, commentaires en français, fins de ligne LF (`.gitattributes`).
- Commits : `git commit -m "<message>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Jamais de secret dans le dépôt.

## Décisions prises par ce plan (au-delà de la spec)

- **Toutes les requêtes de la saison passent par un seul `PacedTransport`** (acteur, une requête à la fois, dans l'ordre d'arrivée, `CrawlPacer` de LoLKit) : la cadence vaut donc aussi pour les reculs internes de `LoLClient.liveWindow` (400), pour une page de calendrier (A7) et pour un classement ouvert à l'écran (A6), et leur budget est commun (300 par session). L'attente se compte depuis la **réponse** précédente : deux départs de requête sont toujours séparés d'au moins 2 s.
- **Replanification après chaque game** : `CrawlPlanner.jobs` est rappelé avant chaque game avec le contexte du moment (suivis, révélations, page ouverte) — révéler un match, suivre une équipe ou ouvrir une page d'équipe change l'ordre aussitôt, et fermer la page arrête la priorité 0 (spec §3.1).
- **Réveil de la collecte** : entre deux passes, la boucle attend 30 min ou un `season.wake()` (suivre / ne plus suivre une équipe ou une ligue, révéler, ouvrir une page d'équipe) ; la première passe démarre un tour (10 s) après l'ouverture : aucune requête de saison ne retarde le premier rafraîchissement.
- **Palier B = 4 requêtes** : LoLKit n'a pas de moyen d'enrichir une game déjà lue (`GameSummary.make` est la seule porte et exige le début et la fin) ; la collecte relit donc `window` sans `startingTime` et `liveWindow`, puis la fenêtre à 15 min et `details` (≈ 166 Ko au lieu de 131). Si ni l'une ni l'autre n'est fournie (204/404), la game est notée `noData` (réessai 1 h, 3 fois) au lieu d'être redemandée aussitôt. Suite possible (LoLKit) : `GameSummary.enriched(at15:details:)` ramènerait le palier B à 2 requêtes.
- **400 persistant ou réponse illisible → `noData`** : `CrawlFailure.reason(for:)` les range en `http`, que `CrawlFailure.record` n'enregistre jamais ; sans cette traduction, la même game serait redemandée jusqu'à épuiser le budget. 429, 5xx, réseau : recul du transport, rien d'enregistré. Une liste de l'énumération refusée (4xx hors 429) ou illisible est notée lue **pour la session** (mémoire).
- **Tournois énumérés** : ceux de la saison (`CrawlPlanner.seasonTournaments`) **déjà commencés** (un tournoi à venir n'a rien à lire) ; ligues = `ScheduleQuery.leagueIds` + ligues suivies + ligue d'attache de l'équipe ouverte. « En cours » = `CrawlPlanner.currentTournament` par ligue ; étape en cours du Mondial = `CrawlPlanner.currentStageMatchIds` ; fraîcheur = `CrawlPlanner.needsRefresh` / `maxAge` ; budget disque = `CrawlPlanner.evictions` ; échecs = `CrawlFailure.record`. **Jour** = jour UTC (« yyyy-MM-dd ») pour comparer aux dates de l'API ; l'affichage reste en jour local.
- **« Sans stats »** = games **sans résumé** en échec définitif (`withoutStats` de `SeasonStats.team`) : une game lue au palier A dont le palier B échoue n'y compte pas.
- **Coquilles des écrans créées par I1** (`TeamPageView`, `PlayerPageView`, `StandingsView`, `SeasonCalendarView`, `DuelView`, `HomeView`) : `.failleDestinations` les référence dès I1 ; chaque tâche A2-A7 en devient ensuite **la seule** propriétaire (même règle que `HomeView` dans la spec). Leur `init` est figé par I1 (contrat entre tâches).
- **Composants communs dans I1** (`App/DA/SeasonParts.swift`) : `ChampionIcon`, `FormPips`, `StatTile`, `MatchLine` (ligne de match anti-spoiler), `TeamLink`, `TeamTapZones`, `SeasonSkeletonCard`, `SeasonComingSoon`, environnement `\.seasonNow` ; et `App/Season/SeasonFormat.swift` (`SeasonFormat`, `SeasonNames` dont `role`). Évite que quatre tâches parallèles réinventent la même ligne de match ou les noms de postes.
- **Libellés de périmètre** : `SeasonScope.label` est une valeur (« 2026 » ou le slug du tournoi) ; l'appli formule (`SeasonLabels.scope` : « Saison 2026 », « LEC Split 3 », « Mondial »).
- **`.sora(_:)` créé par I1** dans un nouveau fichier `Shared/DA/SoraStyle.swift` (et non par P2 dans `Typography.swift`) : la spec demande les nouveaux écrans en `.sora`, or ils sont écrits avant P2. P2 migre ensuite les textes des anciens écrans de `App/` ; `Typography.swift` n'est touché par personne.
- **Données d'aperçu de la saison** : `SeasonSamples` (A1, dans `App/`) ; `PreviewData` (dans `Shared/`, compilé aussi dans l'extension) ne reçoit qu'un petit `enum SeasonSample` (I1) que `AppStore(preview:)` traduit en `SeasonPreview`. Les planches existantes (`.standard`) gardent une saison vide.
- **Accueil** : `HomeFeed.build` (L7) donne « À ne pas rater », le direct, le nombre de matchs du jour, les résultats et l'activité ; l'appli y ajoute le bandeau défilant (`WeekStrip.scrollRange`), les matchs par jour, les joueurs en forme des 6 combinaisons (`HomeFeed.topPlayers`) et le masquage du direct, le tout hors du fil principal (`HomeModel.compute`), une fois par `HomeKey`. « Comment c'est calculé » affiche le barème de la spec §3.6 (LoLKit n'expose que les points de chaque raison retenue).
- **« Prochains matchs » d'une page d'équipe** : le premier par `Presenter.nextLine` (carte construite pour l'équipe, même non suivie) ; jusqu'à 3 seulement si l'équipe n'est pas en anti-spoiler, sans jamais un match contre une équipe suivie en anti-spoiler dont le dernier match est masqué (règle C). L'adversaire du face-à-face : son id dans le match, sinon l'équipe du catalogue de même nom ou de même logo (le calendrier n'a pas d'id).
- **Résultat masqué de l'Accueil** : toute la ligne « Terminé · toucher pour révéler » est le bouton de révélation (avec `.reveal`) ; révélée, elle devient un lien vers le Détail.
- **Équipe dans le Détail** : deux zones de toucher transparentes sur le logo et le code de chaque équipe de l'en-tête (`TeamTapZones`, I1) plutôt qu'une modification de `ScoreRow` (partagé avec les cartes).
- **Photos des joueurs** : monogramme, aucune image de joueur téléchargée cette nuit (aucun cache d'images de joueurs ; sobriété réseau).
- **Onboarding** : vues à fermetures (A9, sans dépendre d'I1), branchées par I2 en `fullScreenCover`, décidé une fois à l'apparition et **seulement dans l'appli** (elle seule passe un routeur de notifications à `RootView` : jamais dans les aperçus ni les tests) ; un utilisateur qui a déjà des suivis au lancement est marqué « fait » par `AppStore` (I1) sans le voir.
- **Catalogue tenu à la main + `scripts/strings-check.py`** (P2) qui sait aussi **ajouter** les clés manquantes (`--add-missing`, anglais vide) avant traduction, refuse une traduction vide, et refuse un littéral nu passé à un composant qui prend une `String` (`ScreenHeader("…")`, `text: "…"`, `subtitle: "…"`) ; le job tourne dans `lolkit.yml`, dont les `paths` s'étendent à `App/**`, `Shared/**`, `Resources/Localizable.xcstrings`, `scripts/strings-check.py`.
- **CI des branches `nuit2/**`** : ajoutée par le contrôleur sur `main` dès le début du lot (I1, étape 0), car A9 (vague 2) et A1 (vague 3) ont besoin de leur CI avant I1.

## Contrat LoLKit consommé

Relevé sur `origin/main` **`4e37f00`** (L1-L6 et L8 fusionnées) et, pour L7 (vague 3, pas encore fusionnée), sur le code du plan `2026-10-15-saison-lolkit.md` (Task L7, Steps 3-4). Tout le code sans interface de ce plan a été **compilé et testé contre ces sources exactes** (voir « Vérifié avant d'écrire ce plan »). Les implémenteurs relisent quand même les signatures à la tête de leur branche (Global Constraints) : si L7 change en route, A3/A7/I2 s'adaptent.

| Tâche LoLKit | Symbole | Signature consommée | Utilisé par |
|---|---|---|---|
| L1 | `TournamentRef` | `id, slug, startDate, endDate: String`, `var leagueId`, `year: Int?`, `isActive(today:)`, `init(id:slug:startDate:endDate:leagueId:)` | A1, A2, A6 |
| L1 | `CompletedMatch` | `matchId, startTime, blockName, bestOf, teams, gameIds`, `playedGameIds` | A1 |
| L1 | `Standings` (+ `allMatches`, `stage(containing:)`, `match(id:)`), `StandingsStage`, `StandingsSection`, `BracketMatch`, `Ranking`, `RankedTeam` | inits publics memberwise | A1, A2, A6, A9 |
| L1 | `TeamPlayer`, `Team.players: [TeamPlayer]?` | `Team.init(…, homeLeague:, players: [TeamPlayer]? = nil)` | I1, A2, A4, A5 |
| L1 | `SeasonMatch` | champs §1.5, `involves(_:)`, `static join(completed:standings:tournamentId:leagueSlug:catalog:)`, init public | A1 et tous |
| L1 | `LoLClient.tournaments(leagueId:)`, `.completedEvents(tournamentId:)`, `.standings(tournamentId:)`, `.schedulePage(leagueIds:pageToken: String?)` ; `SchedulePageResult { events, older, newer }` | `async throws` | A1 (A7 via A1) |
| L2 | `GameSummary` | champs §1.5, `schemaVersion`, `init(v:gameId:matchId:tournamentId:leagueSlug:number:patch:startedAt:endedAt:durationSeconds:result:blue:red:enriched:)`, `line(teamId:)`, `opponentLine(of:)`, `player(_:)`, `static decodeStored(_:)`, `static make(first:final:at15:details:matchId:number:tournamentId:leagueSlug:) -> GameSummary?` (pas d'enrichissement d'une game lue : palier B à 4 requêtes) | A1, A3, A4, A5 |
| L2 | `GameResult` | `winnerTeamId`, `basis: GameResult.Basis { exact, inferred, unknown }`, `.unknown` | A1, A5 |
| L2 | `TeamGameLine`, `PlayerGameLine` | `TeamGameLine(teamId:kills:gold:towers:inhibitors:barons:dragons:gold15:players:)` (**`gold15` sans défaut**) ; `PlayerGameLine(…, damageShare: = nil, …)` | A1 |
| L2 | `GameWinners.apply(teams:playedGameIds:to:)` (et `assign(teams:playedGameIds:summaries:)`) | `-> [String: GameSummary]` | A1 |
| L2 | `PlayerName.display(_:teamCode:)` | | I1 (`SeasonNames`) |
| L3 | `SeasonStats.team(_:matches:games:scope:masked:now:withoutStats:)`, `.player(_:games:masked:since:)`, `.topPlayers(games:masked:metric:since:minGames:limit:)`, `.headToHead(_:_:matches:masked:)`, `.streak(_:matches:masked:)` | | A1, A2, A4, A5 |
| L3 | `TeamSeason` (`form: [FormPip]` du plus ancien au plus récent), `TeamAverages`, `Streak { kind: .wins/.losses, count }`, `FormPip { matchId, outcome: .win/.loss/.masked }`, `ChampionUse`, `HeadToHead { teamA, teamB, winsA, winsB, matchIds, maskedMatches }` | | I1, A2, A4 |
| L3 | `PlayerSeason`, `GameRefLine { gameId, matchId, teamId, startedAt, champion, kills, deaths, assists, creepScore, gold, won: Bool?, winEstimated, kda }`, `PlayerMetric { kda, kills (moyenne par game), csPerMin }` + `value(of:)` | | A3, A5 |
| L3 | `SeasonScope` | `tournamentIds`, `label` (valeur : année ou slug), `static season(_:tournaments:)`, `static tournament(_:)`, `contains(_:)` | A1, A2, A5 |
| L3 | `SeasonMasking.maskedMatchIds(_:follows:revealed:)` | | A1, I1 |
| L3 | `Duel.lineup(teamId:catalog:games:) -> [DuelSlot]` (`role, playerId?, name?, image?`), `Duel.players(left:right:games:masked:) -> PlayerDuel { left, right, bars: [DuelBar] }`, `DuelBar { metric: DuelMetric, left?, right?, leftRatio, rightRatio }`, `DuelMetric`, `Duel.roles` | | A4 |
| L4 | `CrawlJob` (`Tier.a/.b`), `CrawlWanted(openedTeamId:followedTeamIds:worldsStageMatchIds:followedLeagueSlugs:currentTournamentIds:)`, `CrawlPlanner.jobs(wanted:matches:have:failures:masked:now:)`, `.seasonTournaments(_:year:)`, `.currentTournament(_:today:)`, `.currentStageMatchIds(_:)`, `.evictions(_:followedTeamIds:limit:)`, `.tournamentsMaxAge`, `.maxAge(of:today:)`, `.needsRefresh(fetchedAt:now:maxAge:)` | | A1 |
| L4 | `CrawlFailure` (`record(_:previous:now:)`, `reason(for:)`, `isFinal`, `allowsRetry(now:)`), `CrawlPacer` (`init(budget:)`, `next(after:)`, `Outcome { answered, retryable }`, `Decision { wait, stop }`, `StopReason { budget, failures }`, `baseInterval`, `backoff`, `sessionRequestBudget`) | | A1 |
| L5 | `FollowedLeague(id:slug:name:image:notifyStarts:)`, `FollowedLeague(league:)` ; `FollowList(teams:leagues:)`, `.leagues`, `containsLeague(id:)`, `league(slug:)`, `follow(league:)`, `unfollowLeague(id:)`, `setNotifyStarts(_:leagueId:)` ; `AppSettings.onboardingDone`, `.revealedStandingIds` ; `ScheduleQuery.leagueIds` (ligues suivies comprises) | | I1, A3, A8 |
| L6 | `StandingsTable.build(standings:) -> [Stage]` ; `Stage { id, name, slug, content }` ; `Content { table([Row]), swiss([RecordGroup]), bracket([Round]), matches([BracketMatch]) }` ; `Row { ordinal, team, wins, losses }` ; `RecordGroup { wins, losses, teams, record }` ; `Round { kind: .quarterFinal/.semiFinal/.final, matches }` | | A2, A6 |
| L6 | `StandingsMasking.isMasked(_:tournamentId:follows:revealed:revealedStandings:)` | | I1 |
| L7 (plan) | `MustWatch.rank(schedule:follows:revealed:revealedStandings:standings:seasonMatches:catalog:now:calendar:limit:) -> [MustWatchPick]` ; `MustWatchPick { event, points, reasons: [MustWatchScore], explanation: [MustWatchReason] }` ; `MustWatchReason` (avec `.decider` et `.international(slug:)`) | | A3, I2 |
| L7 (plan) | `HomeFeed.Input(now:calendar:schedule:live:follows:revealed:revealedStandings:seasonMatches:games:standings:catalog:)`, `HomeFeed.build(_:) -> Sections { mustWatch, live, week, todayCount, recentResults, activity }`, `HomeFeed.followedMatchIds(_:follows:)`, `HomeFeed.topPlayers(games:masked:metric:period:now:)`, `HomeFeed.Period { week, season }` ; `ActivityItem { kind: ActivityKind, date }` | | A3, A7 |
| L8 | `CalendarMonth.days(events:month:calendar:followed: Set<String> (ids de match), now:) -> [CalendarDay]` (semaines entières), `.events(on:in:calendar:)`, `.pageNeeded(for:events:calendar:) -> SchedulePageDirection?` ; `CalendarDay { date, dayNumber, isInMonth, isToday, marker: DayMarker (.none/.followed/.international), matchIds }` ; `WeekStrip.scrollRange(today:events:calendar:followed:)` | | A3, A7 |
| existant | `Presenter.scoreLine/nextLine/maskedLatestTeamIds`, `TeamCards.build`, `SpoilerPolicy.isMasked`, `TeamDirectory`, `LoLClient.window/liveWindow/details(gameId:now:)`, `LoLAPIError`, `RefreshPolicy.tick`, `DataDragon.championImage`, `League.internationalSlugs`, `Cached`, `Format.score/matchDate/gold/goldDiff` | inchangés | tous |

## Structure des fichiers

```
App/Season/PacedTransport.swift        (A1) CrawlClock, SystemCrawlClock, CrawlStopped, PacedTransport (cadence, recul, budget)
App/Season/SeasonDisk.swift            (A1) cache/season/ : games, tournois, résultats, classements, échecs ; élagage 2 000
App/Season/SeasonPlanning.swift        (A1) SeasonContext, SeasonPlanning (ligues, saison, en cours, phase du Mondial, à 15 min)
App/Season/SeasonStore.swift           (A1) SeasonStore @Observable, CrawlProgress, CrawlEnd, SeasonPreview
App/Season/SeasonCrawler.swift         (A1) énumération + paliers A/B, erreurs
App/Season/SeasonLabels.swift          (A1) « Saison 2026 », « LEC Split 3 », « Mondial »
App/Season/SeasonSamples.swift         (A1) saison d'exemple (aperçus), cohérente avec SampleData
App/Season/SeasonFormat.swift          (I1) SeasonFormat (chiffres), SeasonNames (pseudos)
App/Navigation/Routes.swift            (I1) TeamRoute, PlayerRoute, StandingsRoute, CalendarRoute, DuelSide, DuelRoute,
                                            RootNavigation.deepLink, .failleDestinations(zoom:)
App/Store/AppStore+Season.swift        (I1) contexte et boucle de la collecte, masquages, noms, aperçus
App/DA/SeasonParts.swift               (I1) \.seasonNow, ChampionIcon, FormPips, StatTile, MatchLine, TeamLink, TeamTapZones,
                                            SeasonSkeletonCard
Shared/DA/SoraStyle.swift              (I1) SoraStyle, .sora(_:) (Dynamic Type, plafond accessibility2)
App/Home/HomeView.swift                (I1 coquille → A3)   App/Home/{HomeModel,HomeTexts,HomeStore,*Section}.swift (A3)
App/TeamPage/TeamPageView.swift        (I1 coquille → A2)   App/TeamPage/{TeamPageModel,TeamPageSections,TeamPageSkeleton}.swift (A2)
App/Duel/DuelView.swift                (I1 coquille → A4)   App/Duel/{DuelModel,DuelSection,DuelBars,DuelPicker}.swift (A4)
App/PlayerPage/PlayerPageView.swift    (I1 coquille → A5)   App/PlayerPage/{PlayerPageModel,PlayerPageSections}.swift (A5)
App/Standings/StandingsView.swift      (I1 coquille → A6)   App/Standings/{StandingsTables,StandingsTexts}.swift (A6)
App/Calendar/SeasonCalendarView.swift  (I1 coquille → A7)   App/Calendar/{CalendarModel,MonthGrid}.swift (A7)
App/Leagues/{LeagueRows,LeagueFollowRow,LeaguesSection}.swift                                   (A8)
App/Onboarding/{OnboardingModel,OnboardingView,OnboardingPages,OnboardingExampleCard}.swift      (A9)
Resources/Localizable.xcstrings, scripts/strings-check.py                                       (P2)
```

## Matrice des fichiers

Une ligne par tâche ; aucun fichier n'apparaît dans la colonne « Modifie » de deux tâches **en même temps** (vérifié). Les six coquilles sont créées par I1 puis modifiées par une seule tâche, après la fusion d'I1. Fichiers partagés (spec §4) et leur unique propriétaire : `RootView` (I1 puis I2, en séquence), `AppStore.swift` (I1), `MatchDetailView`, `TeamsView`, `TeamRows`, `MatchesView`, `TeamCardView` (I2), `SampleData` (I1), `Icon` (I1), `project.yml` (P2). `Typography.swift`, `Haptics.swift`, `MatchRoute.swift`, `MatchParts.swift` : personne.

| Tâche | Branche | Crée | Modifie |
|---|---|---|---|
| A1 Store + collecte | `nuit2/appli-a1-saison-store` | `App/Season/{PacedTransport,SeasonDisk,SeasonPlanning,SeasonStore,SeasonCrawler,SeasonLabels,SeasonSamples}.swift`, `Tests/FailleTests/SeasonStoreTests.swift` | — |
| I1 Intégration 1 | `nuit2/appli-i1-integration` (étape 0 : `main`) | `App/Navigation/Routes.swift`, `App/Store/AppStore+Season.swift`, `App/Season/SeasonFormat.swift`, `App/DA/SeasonParts.swift`, `Shared/DA/SoraStyle.swift`, coquilles `App/Home/HomeView.swift`, `App/TeamPage/TeamPageView.swift`, `App/PlayerPage/PlayerPageView.swift`, `App/Standings/StandingsView.swift`, `App/Calendar/SeasonCalendarView.swift`, `App/Duel/DuelView.swift`, `Resources/Assets.xcassets/icon-{home,calendar,standings,versus,player}.imageset/*`, `Tests/FailleTests/{SeasonIntegrationTests,SeasonFormatTests}.swift` | `.github/workflows/ios.yml` (étape 0), `App/RootView.swift`, `App/Store/AppStore.swift`, `Shared/Preview/SampleData.swift`, `Shared/DA/Icon.swift`, `Tests/FailleTests/ApercuTests.swift` |
| A2 Page équipe | `nuit2/appli-a2-page-equipe` | `App/TeamPage/{TeamPageModel,TeamPageSections,TeamPageSkeleton}.swift`, `Tests/FailleTests/{TeamPageTests,TeamPageSnapshotTests}.swift` | `App/TeamPage/TeamPageView.swift` |
| A3 Accueil | `nuit2/appli-a3-accueil` | `App/Home/{HomeModel,HomeTexts,HomeStore,MustWatchSection,LiveNowSection,WeekStripSection,RecentResultsSection,ActivitySection,HotPlayersSection}.swift`, `Tests/FailleTests/{HomeTests,HomeSnapshotTests}.swift` | `App/Home/HomeView.swift` |
| A4 Duels | `nuit2/appli-a4-duels` | `App/Duel/{DuelModel,DuelSection,DuelBars,DuelPicker}.swift`, `Tests/FailleTests/{DuelTests,DuelSnapshotTests}.swift` | `App/Duel/DuelView.swift` |
| A5 Page joueur | `nuit2/appli-a5-page-joueur` | `App/PlayerPage/{PlayerPageModel,PlayerPageSections}.swift`, `Tests/FailleTests/{PlayerPageTests,PlayerPageSnapshotTests}.swift` | `App/PlayerPage/PlayerPageView.swift` |
| A6 Classements | `nuit2/appli-a6-classements` | `App/Standings/{StandingsTables,StandingsTexts}.swift`, `Tests/FailleTests/{StandingsTests,StandingsSnapshotTests}.swift` | `App/Standings/StandingsView.swift` |
| A7 Calendrier | `nuit2/appli-a7-calendrier` | `App/Calendar/{CalendarModel,MonthGrid}.swift`, `Tests/FailleTests/{CalendarTests,CalendarSnapshotTests}.swift` | `App/Calendar/SeasonCalendarView.swift` |
| A8 Ligues (UI) | `nuit2/appli-a8-ligues` | `App/Leagues/{LeagueRows,LeagueFollowRow,LeaguesSection}.swift`, `Tests/FailleTests/{LeaguesTests,LeaguesSnapshotTests}.swift` | — |
| A9 Onboarding | `nuit2/appli-a9-onboarding` | `App/Onboarding/{OnboardingModel,OnboardingView,OnboardingPages,OnboardingExampleCard}.swift`, `Tests/FailleTests/{OnboardingTests,OnboardingSnapshotTests}.swift` | — |
| I2 Intégration 2 | `nuit2/appli-i2-integration` | `Tests/FailleTests/SeasonWiringTests.swift` | `App/Detail/MatchDetailView.swift`, `App/Teams/TeamsView.swift`, `App/Teams/TeamRows.swift`, `App/Matches/MatchesView.swift`, `App/Matches/TeamCardView.swift`, `App/RootView.swift`, `docs/superpowers/notes/2026-10-14-checklist-iphone.md` |
| P2 Accessibilité et langue | `nuit2/appli-p2-langue` | `Resources/Localizable.xcstrings`, `scripts/strings-check.py`, `Tests/FailleTests/AccessibilityTests.swift` | `project.yml`, `.github/workflows/lolkit.yml`, tout `App/**` et `Shared/**` (libellés VoiceOver, `.sora` des anciens écrans, `String(localized:)` des composants) — seule tâche en cours à ce moment |

Noms de types, de suites de tests et de planches uniques (vérifié) ; les aides de test sont `private` à leur fichier.

## Dépendances et vagues

- **Étape 0 (début du lot, contrôleur)** : I1 étape 0 sur `main` (CI des branches `nuit2/**`).
- **A9** : L1 (types des classements). Vague 2 (en parallèle de L3 ‖ L4 ‖ L6).
- **A1** : L1, L2, L3 (`SeasonStats`, `SeasonMasking`), L4. Vague 3, en parallèle de L7.
- **I1** : A1, L5, L6 (`StandingsMasking`). Fin de vague 3 (fusion, CI verte, IPA intermédiaire).
- **A2** : I1, L3, L6. **A3** : I1, L7, L8. **A4** : I1, L3. **A5** : I1, L3. Vague 4a, en parallèle (A2 prioritaire).
- **A6** : I1, L6. **A7** : I1, L7 (`HomeFeed.followedMatchIds`), L8. **A8** : I1, L5. Vague 4b, en parallèle.
- **I2** : A2 à A9 (celles qui sont fusionnées : une tâche coupée est simplement non branchée — voir « Coupe »). Vague 5 (fusion, IPA).
- **P2** : I2. Vague 5, dernière.
- **Coupe** (spec §4, dans cet ordre on garde) : A1 + I1 → A2 → A3 → A4 → A5 → A9 → A8 → A6 → A7 → P2. I2 ne branche que les tâches fusionnées (chaque branchement d'I2 est un pas séparé) ; une coquille non remplacée affiche son état vide « Bientôt » (I1), jamais un écran cassé.
- Le contrôleur, pour chaque tâche : `git pull --ff-only origin main`, puis `git worktree add ../faille-<id> -b nuit2/appli-<id>-<slug> main` ; fusion côté serveur (`gh api repos/cafe1231/faille/merges -f base=main -f head=<branche>`) après la CI verte du dernier commit de la branche. Aucun conflit attendu (fichiers disjoints) ; un conflit sur un fichier partagé est une erreur de matrice.

## Vérifié avant d'écrire ce plan

- **Compilé et testé sous Linux contre le vrai LoLKit** (Docker `swift:6.2`) : copie de `LoLKit/` d'`origin/main` **`4e37f00`** (L1-L6 et L8 fusionnées), plus `Home/MustWatch.swift` et `Home/HomeFeed.swift` recopiés du plan LoLKit (Task L7, Steps 3-4 : vague 3, pas encore fusionnée), plus une cale Linux pour `String(localized:)`. Fichiers de ce plan compilés **tels qu'ils figurent ici** : tout A1 (`PacedTransport`, `SeasonDisk`, `SeasonPlanning`, `SeasonStore`, `SeasonCrawler`, `SeasonLabels`, `SeasonSamples`), `SeasonFormat` (I1), `TeamPageModel` (A2), `HomeModel`, `HomeTexts` (A3), `DuelModel` (A4), `PlayerPageModel` (A5), `StandingsTexts` (A6), `CalendarModel` (A7), `LeagueRows` (A8), `OnboardingModel` (A9), avec `Shared/Preview/SampleData.swift` d'`origin/main` : **0 avertissement, 30 tests passés en 11 suites** — les 10 de `SeasonStoreTests` (ordre réel de `CrawlPlanner` : palier A des équipes suivies du plus récent au plus ancien puis palier B à 4 requêtes ; ≥ 2 s entre deux requêtes ; arrêt à 300 ; masqué jamais demandé puis demandé après révélation ; reprise depuis le disque sans requête de game ni relecture d'un tournoi terminé ; 404 définitif ; recul 4-8-16-32 puis arrêt au 5e échec ; aides de planification ; libellés ; cohérence des échantillons) et les tests de logique d'I1, A2-A9 (hors cas qui demandent `AppStore`, hébergés en CI).
- `scripts/strings-check.py` exécuté (Python 3) sur `App/` + `Shared/` d'`origin/main` : 73 littéraux trouvés, 19 littéraux nus signalés, `--add-missing` crée le catalogue, le contrôle passe (code 0) une fois l'anglais rempli et les littéraux nus corrigés, échoue sinon.
- Les 37 ancres « Remplacer … par … » (I1, I2, P2) ont été vérifiées par script : chacune trouvée **exactement une fois**, en appliquant les remplacements dans l'ordre d'exécution (I1 sur `origin/main`, puis I2 sur le résultat — dont les 3 ancres de `RootView.swift` laissées par I1 —, puis P2).
- **Pas compilé** (CI seulement) : toutes les vues SwiftUI, `Routes.swift`, `SeasonParts.swift`, `SoraStyle.swift`, `AppStore+Season.swift`, `HomeStore.swift`, les modifications d'`AppStore`, `RootView`, `SampleData`, `Icon`, des écrans existants, et les tests hébergés qui demandent `AppStore` ou une fenêtre (planches).

---

### Task A1: `SeasonStore` et collecte progressive

**Branche :** `nuit2/appli-a1-saison-store` · **Vague :** 3 (en parallèle de L7) · **Dépendances :** L1, L2, L3, L4 fusionnées.

**Files:**
- Create: `App/Season/PacedTransport.swift`, `App/Season/SeasonDisk.swift`, `App/Season/SeasonPlanning.swift`, `App/Season/SeasonStore.swift`, `App/Season/SeasonCrawler.swift`, `App/Season/SeasonLabels.swift`, `App/Season/SeasonSamples.swift`
- Test: `Tests/FailleTests/SeasonStoreTests.swift`

**Interfaces:**
- Consumes : LoLKit (contrat, relevé à `4e37f00`) `TournamentRef`, `CompletedMatch`, `Standings` et types liés, `SeasonMatch.join`, `SchedulePageResult`, `LoLClient.tournaments/completedEvents/standings/schedulePage`, `GameSummary.make` / `decodeStored`, `GameResult`, `TeamGameLine`, `PlayerGameLine`, `GameWinners.apply`, `SeasonStats.team(…withoutStats:)` / `.player`, `SeasonMasking.maskedMatchIds`, `SeasonScope.season/.tournament`, `CrawlPlanner.jobs/seasonTournaments/currentTournament/currentStageMatchIds/evictions/maxAge/needsRefresh/tournamentsMaxAge`, `CrawlWanted`, `CrawlFailure.record/reason(for:)/isFinal`, `CrawlPacer` ; existants `LoLClient.window(gameId:startingTime:)`, `liveWindow(gameId:now:)`, `details(gameId:now:)`, `ScheduleQuery.leagueIds`, `RefreshPolicy.tick`, `Cached`, `DiskCache` (appli), `SampleData` (aperçus).
- Produces (utilisé par I1 et A2-A8) :
  - `@MainActor @Observable final class SeasonStore` — `init(transport: any HTTPTransport, cache: DiskCache, clock: any CrawlClock = SystemCrawlClock())`, `init(preview: SeasonPreview)` ; lectures `games: [String: GameSummary]`, `tournaments: [String: [TournamentRef]]` (par ligue), `standings: [String: Standings]` (par tournoi), `matches: [SeasonMatch]` (du plus récent), `failures`, `isLoaded`, `progress: CrawlProgress`, `version: Int`, `openedTeamId`, `isPreview` ; `tournament(id:)`, `matches(ofTeam:)`, `withoutStats`, `teamSeason(_:scope:masked:now:) -> TeamSeason` (mémoïsé), `player(_:scope:masked:) -> PlayerSeason?`, `scopes(forTeam:now:) -> [SeasonScope]` (libellés = valeurs, à formuler par `SeasonLabels.scope`), `currentTournament(forTeam:now:) -> TournamentRef?` ; actions `loadFromDisk() async`, `open(teamId:)`, `close(teamId:)`, `wake()`, `waitForWake(maxSeconds:) async`, `beginSession() async`, `crawl(context: @MainActor () -> SeasonContext) async -> CrawlEnd`, `schedulePage(leagueIds:token:) async -> SchedulePageResult?`, `loadStandings(tournamentId:) async`.
  - `struct SeasonContext { follows, leagues, catalog, revealed, openedTeamId, now }` ; `enum SeasonPlanning { day(_:) -> String, year(_:) -> Int, leagueIds(_:), startedTournaments(_:leagueIds:now:), currentTournamentIds(_:leagueIds:now:), wanted(_:byLeague:standings:), at15(_:) }`.
  - `struct CrawlProgress { read, remaining, running }`, `enum CrawlEnd { done, budget, failures, cancelled, inert }`, `struct SeasonPreview`, `enum SeasonSamples { standard, collecting, loading, lecSplit3, lckSplit3, worlds, matches, games, standings, rosters }`, `enum SeasonLabels { season(year:), scope(_:), league(slug:), tournament(_:), tournament(slug:) }`.
  - `actor PacedTransport: HTTPTransport` (`sent`, `sentAt`, `beginSession()`, `stopReason`), `protocol CrawlClock`, `struct SystemCrawlClock`, `struct CrawlStopped`.

Les tests iOS ne tournent qu'en CI : ils sont écrits d'abord (ils fixent le comportement), puis le code ; la CI de la branche les exécute une fois, à la fin de la tâche.

- [ ] **Step 1: Relire le contrat LoLKit à la tête de la branche**

```bash
git pull --ff-only origin main
grep -rn "public" LoLKit/Sources/LoLKit/Season/ | grep -E "struct|enum|func|init|case|var|let" | less
grep -n "func tournaments\|func completedEvents\|func standings\|func schedulePage" LoLKit/Sources/LoLKit/API/*.swift
```

Comparer avec le tableau « Contrat LoLKit consommé » (lignes L1-L4, relevées à `4e37f00` : le code ci-dessous y compile tel quel). Un écart de nom à la tête de la branche s'adapte **sans changer le comportement**. Si LoLKit a gagné entre-temps un moyen d'enrichir une game déjà lue (`GameSummary.enriched(at15:details:)` ou équivalent), le cas `.b` de `SeasonCrawler.read` peut s'en servir et ne plus relire début et fin (2 requêtes au lieu de 4) : à noter au journal.

- [ ] **Step 2: Écrire les tests de la collecte**

Créer `Tests/FailleTests/SeasonStoreTests.swift` (faux monde lolesports en mémoire, horloge virtuelle : aucune vraie attente, aucun réseau) :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

// MARK: Faux monde lolesports

/// Horloge virtuelle : `sleep` avance l'heure sans attendre ; garde chaque attente demandée.
private actor VirtualClock: CrawlClock {
    private(set) var current: Date
    private(set) var sleeps: [TimeInterval] = []

    init(_ start: Date) {
        current = start
    }

    func now() async -> Date {
        current
    }

    func sleep(seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        sleeps.append(seconds)
        current = current.addingTimeInterval(seconds)
    }
}

/// Un match joué du faux monde : ses équipes (avec id), leurs victoires, ses games jouées (préfixe de `games`).
private struct FakeMatch {
    let id: String
    let start: String
    let teams: [(id: String, code: String, wins: Int)]
    var gameIds: [String] {
        (1...teams.reduce(0) { $0 + $1.wins }).map { "\(id)-g\($0)" }
    }
}

/// Faux API + flux livestats : une ligue (LEC) et le Mondial, un tournoi chacun, les matchs donnés ; `window` d'une game
/// sans `startingTime` → sa première frame, avec → sa frame `finished` ; `details` → 404. Garde les URL demandées.
private actor FakeLoLWorld: HTTPTransport {
    private(set) var requests: [URL] = []
    let lec: [FakeMatch]
    let worlds: [FakeMatch]
    /// Games dont le flux répond 404 (stats désactivées par Riot).
    let disabled: Set<String>
    /// Statut forcé pour les N premières requêtes `window` (503 : panne).
    private var failingWindows: Int

    init(lec: [FakeMatch], worlds: [FakeMatch] = [], disabled: Set<String> = [], failingWindows: Int = 0) {
        self.lec = lec
        self.worlds = worlds
        self.disabled = disabled
        self.failingWindows = failingWindows
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        let path = url.path(percentEncoded: false)
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        if path.hasSuffix("/getTournamentsForLeague") {
            let lecLeague = query["leagueId"] == "98767991302996019"
            let tournament = lecLeague
                ? #"{"id":"t-lec","slug":"lec_split_3_2026","startDate":"2026-07-23","endDate":"2026-09-20"}"#
                : #"{"id":"t-worlds","slug":"worlds_2026","startDate":"2026-10-01","endDate":"2026-11-15"}"#
            return ok(#"{"data":{"leagues":[{"tournaments":[\#(tournament)]}]}}"#)
        }
        if path.hasSuffix("/getCompletedEvents") {
            let matches = query["tournamentId"] == "t-lec" ? lec : worlds
            return ok(#"{"data":{"schedule":{"events":[\#(matches.map(Self.event).joined(separator: ","))]}}}"#)
        }
        if path.hasSuffix("/getStandings") {
            let matches = query["tournamentId"] == "t-lec" ? lec : worlds
            let bracket = matches.map(Self.bracket).joined(separator: ",")
            return ok(#"{"data":{"standings":[{"stages":[{"id":"s1","name":"Saison","slug":"regular_season","sections":[{"name":"Saison","matches":[\#(bracket)],"rankings":[]}]}]}]}}"#)
        }
        if path.contains("/livestats/v1/details/") {
            return HTTPResponse(status: 404, body: Data())
        }
        if path.contains("/livestats/v1/window/") {
            if failingWindows > 0 {
                failingWindows -= 1
                return HTTPResponse(status: 503, body: Data())
            }
            let gameId = String(path.split(separator: "/").last ?? "")
            if disabled.contains(gameId) { return HTTPResponse(status: 404, body: Data()) }
            let first = query["startingTime"] == nil
            return ok(Self.window(gameId: gameId, finished: !first))
        }
        return HTTPResponse(status: 404, body: Data())
    }

    private func ok(_ body: String) -> HTTPResponse {
        HTTPResponse(status: 200, body: Data(body.utf8))
    }

    private static func team(_ team: (id: String, code: String, wins: Int), withId: Bool, won: Bool) -> String {
        let id = withId ? #""id":"\#(team.id)","slug":"\#(team.id)","# : ""
        return #"{\#(id)"name":"\#(team.code) Esports","code":"\#(team.code)","image":null,"result":{"outcome":"\#(won ? "win" : "loss")","gameWins":\#(team.wins)}}"#
    }

    private static func event(_ match: FakeMatch) -> String {
        let best = match.teams.map(\.wins).max() ?? 0
        let teams = match.teams.map { team($0, withId: false, won: $0.wins == best) }.joined(separator: ",")
        // Une game listée de plus, jamais jouée (comme l'API : games[] liste aussi les games inutiles).
        let games = (match.gameIds + ["\(match.id)-unneeded"]).map { #"{"id":"\#($0)","vods":[]}"# }.joined(separator: ",")
        return #"{"startTime":"\#(match.start)","blockName":"Semaine 1","league":{"name":"LEC"},"match":{"id":"\#(match.id)","type":"normal","teams":[\#(teams)],"strategy":{"type":"bestOf","count":3}},"games":[\#(games)]}"#
    }

    private static func bracket(_ match: FakeMatch) -> String {
        let best = match.teams.map(\.wins).max() ?? 0
        let teams = match.teams.map { team($0, withId: true, won: $0.wins == best) }.joined(separator: ",")
        return #"{"id":"\#(match.id)","state":"completed","previousMatchIds":[],"flags":[],"teams":[\#(teams)]}"#
    }

    private static func window(gameId: String, finished: Bool) -> String {
        let time = finished ? "2026-09-01T18:35:00.000Z" : "2026-09-01T18:00:00.000Z"
        let side = #""inhibitors":0,"towers":5,"barons":0,"dragons":[],"participants":[]"#
        return #"{"esportsGameId":"\#(gameId)","esportsMatchId":"m","gameMetadata":{"patchVersion":"16.17.1","blueTeamMetadata":{"esportsTeamId":"kc","participantMetadata":[]},"redTeamMetadata":{"esportsTeamId":"g2","participantMetadata":[]}},"frames":[{"rfc460Timestamp":"\#(time)","gameState":"\#(finished ? "finished" : "in_game")","blueTeam":{"totalGold":60000,"totalKills":12,\#(side)},"redTeam":{"totalGold":55000,"totalKills":7,\#(side)}}]}"#
    }
}

private let lecId = "98767991302996019"
private let worldsId = "98767975604431411"
private let today = LoLDate.parse("2026-10-15T15:00:00Z")!

private let leagues = [
    League(id: worldsId, slug: "worlds", name: "Mondial", region: "INTERNATIONAL", image: nil, priority: 1),
    League(id: lecId, slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1),
]

private let kcTeam = Team(id: "kc", slug: "kc", name: "KC Esports", code: "KC", image: nil, status: "active",
                          homeLeague: Team.HomeLeague(name: "LEC"))

private func context(follows: FollowList, revealed: Set<String> = [], opened: String? = nil) -> SeasonContext {
    SeasonContext(follows: follows, leagues: leagues, catalog: [kcTeam], revealed: revealed, openedTeamId: opened, now: today)
}

private func kcFollowed(spoilerFree: Bool = false) -> FollowList {
    FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "KC Esports", homeLeagueName: "LEC",
                                    spoilerFree: spoilerFree)])
}

/// Matchs de KC en LEC, du plus ancien au plus récent (2-0 chacun), et un match sans KC.
private let lecMatches = [
    FakeMatch(id: "m1", start: "2026-08-01T17:00:00Z", teams: [("kc", "KC", 2), ("g2", "G2", 0)]),
    FakeMatch(id: "m2", start: "2026-08-08T17:00:00Z", teams: [("kc", "KC", 2), ("vit", "VIT", 1)]),
    FakeMatch(id: "m3", start: "2026-08-15T17:00:00Z", teams: [("sk", "SK", 0), ("kc", "KC", 2)]),
    FakeMatch(id: "m4", start: "2026-08-22T17:00:00Z", teams: [("th", "TH", 2), ("g2", "G2", 1)]),
]

@MainActor
private func makeStore(_ world: FakeLoLWorld, clock: VirtualClock, root: URL = TemporaryFiles.directory()) -> SeasonStore {
    SeasonStore(transport: world, cache: DiskCache(root: root), clock: clock)
}

private func gameIds(_ requests: [URL]) -> [String] {
    requests.filter { $0.path.contains("/window/") }.map { String($0.path.split(separator: "/").last ?? "") }
}

// MARK: Tests

/// Collecte de saison (spec saison §1.6) : ordre, cadence, budget, anti-spoiler, reprise, échecs.
@MainActor
struct SeasonStoreTests {
    @Test func followedTeamGamesAreReadMostRecentFirstAfterTheEnumeration() async throws {
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: VirtualClock(today))
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .done)
        let requests = await world.requests
        // Énumération d'abord : tournois du Mondial et de la LEC, puis résultats et classements de chaque tournoi.
        #expect(requests.prefix(6).allSatisfy { !$0.path.contains("/livestats/") })
        // Puis le palier A des games de KC (m3, m2, m1 : la plus récente d'abord), deux requêtes par game, jamais m4 (sans
        // KC) ni la game listée mais pas jouée…
        let feed = gameIds(requests)
        #expect(Array(feed.prefix(14)) == ["m3-g1", "m3-g1", "m3-g2", "m3-g2", "m2-g1", "m2-g1", "m2-g2", "m2-g2",
                                           "m2-g3", "m2-g3", "m1-g1", "m1-g1", "m1-g2", "m1-g2"])
        // … puis le palier B (équipe suivie, tournoi en cours) : début, fin et fenêtre à 15 min de chaque game (LoLKit
        // réduit la game à nouveau), et `details`.
        #expect(Array(feed.dropFirst(14)) == ["m3-g1", "m3-g1", "m3-g1", "m3-g2", "m3-g2", "m3-g2", "m2-g1", "m2-g1",
                                              "m2-g1", "m2-g2", "m2-g2", "m2-g2", "m2-g3", "m2-g3", "m2-g3", "m1-g1",
                                              "m1-g1", "m1-g1", "m1-g2", "m1-g2", "m1-g2"])
        #expect(requests.filter { $0.path.contains("/details/") }.count == 7)
        #expect(store.games.count == 7)
        #expect(store.games.values.allSatisfy { $0.enriched })
        #expect(store.games["m3-g2"]?.durationSeconds == 2100)
        #expect(store.matches.count == 4)
    }

    @Test func twoRequestsAreAlwaysAtLeastTwoSecondsApart() async throws {
        let clock = VirtualClock(today)
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: clock)
        await store.crawl { context(follows: kcFollowed()) }
        let sent = try #require(await store.paced?.sentAt)
        #expect(sent.count == (await world.requests.count))
        for (earlier, later) in zip(sent, sent.dropFirst()) {
            #expect(later.timeIntervalSince(earlier) >= CrawlPacer.baseInterval)
        }
    }

    @Test func aSessionStopsAtItsBudgetOfThreeHundredRequests() async throws {
        // 160 matchs de KC à 1 game : 6 requêtes d'énumération + 2 par game dépassent le budget.
        let many = (0..<160).map { index in
            FakeMatch(id: "b\(index)", start: "2026-08-01T\(String(format: "%02d", index % 24)):00:00Z",
                      teams: [("kc", "KC", 1), ("g2", "G2", 0)])
        }
        let world = FakeLoLWorld(lec: many)
        let store = makeStore(world, clock: VirtualClock(today))
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .budget)
        #expect(await world.requests.count == CrawlPacer.sessionRequestBudget)
        // Nouvelle session : le budget repart.
        await store.beginSession()
        #expect(await store.paced?.sent == 0)
    }

    @Test func aMaskedMatchIsNeverRequestedUntilItIsRevealed() async throws {
        let world = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(world, clock: VirtualClock(today))
        // KC en anti-spoiler : tous ses matchs masqués sauf m2, révélé.
        await store.crawl { context(follows: kcFollowed(spoilerFree: true), revealed: ["m2"]) }
        let read = Set(gameIds(await world.requests))
        #expect(read == ["m2-g1", "m2-g2", "m2-g3"])
        #expect(!(await world.requests).contains { $0.absoluteString.contains("m1-") || $0.absoluteString.contains("m3-") })
        // Révéler m3 le rend éligible à la passe suivante.
        await store.crawl { context(follows: kcFollowed(spoilerFree: true), revealed: ["m2", "m3"]) }
        #expect(Set(gameIds(await world.requests)).isSuperset(of: ["m3-g1", "m3-g2"]))
        #expect(!Set(gameIds(await world.requests)).contains("m1-g1"))
    }

    @Test func theDiskIsTheStateAResumedCrawlSkipsWhatIsKnown() async throws {
        let root = TemporaryFiles.directory()
        let first = FakeLoLWorld(lec: lecMatches)
        let store = makeStore(first, clock: VirtualClock(today), root: root)
        await store.crawl { context(follows: kcFollowed()) }
        // Relance de l'appli : un nouveau store, le même dossier ; plus aucune requête de game, ni de tournoi terminé.
        let second = FakeLoLWorld(lec: lecMatches)
        let resumed = makeStore(second, clock: VirtualClock(today.addingTimeInterval(3_600)), root: root)
        await resumed.loadFromDisk()
        #expect(resumed.games.count == 7)
        #expect(resumed.matches.count == 4)
        let end = await resumed.crawl { context(follows: kcFollowed()) }
        #expect(end == .done)
        let again = await second.requests
        #expect(gameIds(again).isEmpty)
        // LEC Split 3 est terminé : ses résultats ne sont jamais relus ; seuls les tournois du Mondial (en cours, lus il y a
        // plus de 30 min) le sont.
        #expect(!again.contains { $0.query?.contains("tournamentId=t-lec") == true })
    }

    @Test func statsDisabledGamesAreRecordedAndNeverAskedAgain() async throws {
        let world = FakeLoLWorld(lec: [lecMatches[0]], disabled: ["m1-g2"])
        let store = makeStore(world, clock: VirtualClock(today))
        await store.crawl { context(follows: kcFollowed()) }
        #expect(store.failures["m1-g2"]?.reason == .statsDisabled)
        #expect(store.games["m1-g1"] != nil)
        let before = gameIds(await world.requests).count
        await store.crawl { context(follows: kcFollowed()) }
        #expect(gameIds(await world.requests).count == before)
    }

    @Test func serverErrorsBackOffThenStopTheSessionAfterFiveInARow() async throws {
        let clock = VirtualClock(today)
        let world = FakeLoLWorld(lec: [lecMatches[0]], failingWindows: 5)
        let store = makeStore(world, clock: clock)
        let end = await store.crawl { context(follows: kcFollowed()) }
        #expect(end == .failures)
        // Après chaque 503 : 4, 8, 16 puis 32 s d'attente avant la requête suivante.
        let sleeps = await clock.sleeps
        #expect(sleeps.suffix(4) == [4, 8, 16, 32])
        #expect(store.games.isEmpty)
        #expect(store.failures.isEmpty) // une panne n'est pas un échec de game
    }

    @Test func planningHelpers() {
        #expect(SeasonPlanning.day(today) == "2026-10-15")
        #expect(SeasonPlanning.year(today) == 2026)
        #expect(SeasonPlanning.at15(LoLDate.parse("2026-09-06T15:17:23.939Z")!) == LoLDate.parse("2026-09-06T15:32:20Z")!)
        let refs = ["l": [
            TournamentRef(id: "s3", slug: "lec_split_3_2026", startDate: "2026-07-23", endDate: "2026-09-20", leagueId: "l"),
            TournamentRef(id: "late", slug: "lec_finals_2026", startDate: "2026-12-01", endDate: "2026-12-10", leagueId: "l"),
            TournamentRef(id: "s1", slug: "lec_split_1_2026", startDate: "2026-01-16", endDate: "2026-03-01", leagueId: "l"),
            TournamentRef(id: "old", slug: "lec_summer_2025", startDate: "2025-08-02", endDate: "2025-09-29", leagueId: "l"),
        ]]
        // Saison 2026, déjà commencée (le tournoi de décembre n'a rien à lire), du plus récent au plus ancien.
        #expect(SeasonPlanning.startedTournaments(refs, leagueIds: ["l"], now: today).map(\.id) == ["s3", "s1"])
        // Entre deux splits : le dernier commencé compte comme « en cours ».
        #expect(SeasonPlanning.currentTournamentIds(refs, leagueIds: ["l"], now: today) == ["s3"])
        // La ligue d'attache d'une équipe ouverte (non suivie) est énumérée.
        let opened = SeasonContext(follows: FollowList(), leagues: leagues, catalog: [kcTeam], revealed: [],
                                   openedTeamId: "kc", now: today)
        #expect(SeasonPlanning.leagueIds(opened) == [worldsId, lecId])
    }

    @Test func tournamentLabels() {
        func label(_ slug: String) -> String {
            SeasonLabels.tournament(TournamentRef(id: "x", slug: slug, startDate: "", endDate: "", leagueId: ""))
        }
        #expect(label("lec_split_3_2026") == "LEC Split 3")
        #expect(label("worlds_2026") == "Mondial")
        #expect(label("first_stand_2026") == "First Stand")
        #expect(label("lck_split_2_playoffs_2026") == "LCK Split 2 Play-offs")
        #expect(SeasonLabels.season(year: "2026") == "Saison 2026")
    }

    @Test func samplesAreConsistentWithTheAppSampleData() {
        let preview = SeasonSamples.standard
        // Chaque game jouée d'exemple existe, et les ids de games de KC 1 – 3 G2 sont ceux de `SampleData`.
        let ids = Set(preview.games.map(\.gameId))
        #expect(preview.matches.allSatisfy { $0.playedGameIds.allSatisfy(ids.contains) })
        #expect(preview.matches.first { $0.id == SampleData.kcG2MatchId }?.playedGameIds
                == ["g1-kc-g2", "g2-kc-g2", "g3-kc-g2", "g4-kc-g2"])
        // T1 est en anti-spoiler dans les aperçus : ses matchs d'exemple sont masqués.
        let masked = SeasonMasking.maskedMatchIds(preview.matches, follows: SampleData.follows, revealed: [])
        #expect(masked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
        #expect(SeasonSamples.games.map(\.durationSeconds) == SeasonSamples.games.map(\.durationSeconds)) // déterministe
    }
}
```

- [ ] **Step 3: Écrire le transport cadencé**

Créer `App/Season/PacedTransport.swift` :

```swift
import Foundation
import LoLKit

/// Horloge de la collecte de saison (spec saison §1.6) : l'heure et les attentes entre deux requêtes. L'appli prend celle du
/// système ; les tests une horloge virtuelle, qui avance d'un coup (aucune vraie attente).
protocol CrawlClock: Sendable {
    func now() async -> Date
    func sleep(seconds: TimeInterval) async throws
}

struct SystemCrawlClock: CrawlClock {
    func now() async -> Date {
        Date()
    }

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Fin de la collecte de la session : budget de requêtes épuisé, ou trop d'échecs d'affilée (spec saison §1.6).
struct CrawlStopped: Error, Equatable, Sendable {
    let reason: CrawlPacer.StopReason
}

/// Transport de la collecte de saison : TOUTES ses requêtes (énumération, paliers A et B, classement ou page de calendrier
/// ouverts à la demande) passent par lui, une à la fois et dans l'ordre d'arrivée, au rythme de `CrawlPacer` : 2 s entre
/// deux requêtes, recul de 4, 8, 16, 32 puis 60 s après un 429, un 5xx ou une erreur réseau, arrêt après 5 échecs
/// d'affilée ou 300 requêtes dans la session. Le rythme vaut aussi pour les reculs internes de `LoLClient.liveWindow` (un
/// 400 « en avance sur la diffusion ») : c'est le transport, pas l'appelant, qui attend. L'attente se compte depuis la
/// RÉPONSE de la requête précédente : deux débuts de requête sont toujours séparés d'au moins 2 s.
actor PacedTransport: HTTPTransport {
    private let base: any HTTPTransport
    private let clock: any CrawlClock
    private var pacer = CrawlPacer()
    private var nextAllowed: Date?
    private var stopped: CrawlPacer.StopReason?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Requêtes envoyées dans la session.
    private(set) var sent = 0
    /// Heure (de l'horloge) du départ de chaque requête de la session : tests de cadence.
    private(set) var sentAt: [Date] = []

    init(base: any HTTPTransport, clock: any CrawlClock) {
        self.base = base
        self.clock = clock
    }

    /// Nouvelle session au premier plan : budget, recul et arrêt remis à zéro.
    func beginSession() {
        pacer = CrawlPacer()
        nextAllowed = nil
        stopped = nil
        sent = 0
        sentAt = []
    }

    /// La collecte de cette session est finie (budget, échecs) : plus aucune requête jusqu'à la suivante.
    var stopReason: CrawlPacer.StopReason? {
        stopped
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        await acquire()
        defer { release() }
        if let stopped { throw CrawlStopped(reason: stopped) }
        guard sent < CrawlPacer.sessionRequestBudget else {
            stopped = .budget
            throw CrawlStopped(reason: .budget)
        }
        if let nextAllowed {
            let wait = nextAllowed.timeIntervalSince(await clock.now())
            if wait > 0 { try await clock.sleep(seconds: wait) }
        }
        try Task.checkCancellation()
        sent += 1
        sentAt.append(await clock.now())
        do {
            let response = try await base.get(url, headers: headers)
            // Même règle que `CrawlPacer.outcome(of:)` : 429 et 5xx reculent ; toute autre réponse (200, 204, 400, 404…)
            // est une réponse.
            let retryable = response.status == 429 || response.status >= 500
            await apply(pacer.next(after: retryable ? .retryable : .answered))
            return response
        } catch {
            if Self.isCancellation(error) {
                // Scène quittée : ni échec ni recul ; la prochaine requête (prochaine session) attendra le pas normal.
                nextAllowed = await clock.now().addingTimeInterval(CrawlPacer.baseInterval)
                throw error
            }
            await apply(pacer.next(after: .retryable))
            throw error
        }
    }

    private func apply(_ decision: CrawlPacer.Decision) async {
        switch decision {
        case let .wait(seconds):
            nextAllowed = await clock.now().addingTimeInterval(seconds)
        case let .stop(reason):
            stopped = reason
        }
    }

    /// Une requête à la fois : les appelants suivants attendent leur tour, dans l'ordre.
    private func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
```

- [ ] **Step 4: Écrire le cache disque de la saison**

Créer `App/Season/SeasonDisk.swift` :

```swift
import Foundation
import LoLKit

/// Fichiers de la saison sous `cache/season/` (spec saison §1.7), dans le `DiskCache` des fonctionnalités (exclu de la
/// sauvegarde iCloud) : une game jouée par fichier, gardée pour toujours (au-delà de 2 000, `CrawlPlanner.evictions`) ;
/// les tournois d'une ligue, les résultats et classements d'un tournoi (fraîcheur : `CrawlPlanner.needsRefresh`) ; les
/// échecs de la collecte.
struct SeasonDisk: Sendable {
    let cache: DiskCache

    static func gamePath(_ gameId: String) -> String { "season/games/\(gameId).json" }
    static func tournamentsPath(_ leagueId: String) -> String { "season/tournaments/\(leagueId).json" }
    static func completedPath(_ tournamentId: String) -> String { "season/completed/\(tournamentId).json" }
    static func standingsPath(_ tournamentId: String) -> String { "season/standings/\(tournamentId).json" }
    static let failuresPath = "season/crawl.json"

    /// Tout ce que le disque connaît de la saison, lu en une fois au lancement (hors du fil principal).
    struct Snapshot: Sendable {
        var games: [String: GameSummary] = [:]
        var tournaments: [String: Cached<[TournamentRef]>] = [:]
        var completed: [String: Cached<[CompletedMatch]>] = [:]
        var standings: [String: Cached<Standings>] = [:]
        var failures: [String: CrawlFailure] = [:]
    }

    /// Lecture complète. Une game d'un schéma plus récent que celui que l'appli connaît est ignorée (pas supprimée : une
    /// version suivante de l'appli la relira, `GameSummary.decodeStored`) ; un fichier illisible aussi.
    func load() -> Snapshot {
        var snapshot = Snapshot()
        let decoder = JSONDecoder()
        for (id, data) in files(in: "season/games") {
            guard let game = GameSummary.decodeStored(data) else { continue }
            snapshot.games[id] = game
        }
        for (id, data) in files(in: "season/tournaments") {
            snapshot.tournaments[id] = try? decoder.decode(Cached<[TournamentRef]>.self, from: data)
        }
        for (id, data) in files(in: "season/completed") {
            snapshot.completed[id] = try? decoder.decode(Cached<[CompletedMatch]>.self, from: data)
        }
        for (id, data) in files(in: "season/standings") {
            snapshot.standings[id] = try? decoder.decode(Cached<Standings>.self, from: data)
        }
        snapshot.failures = cache.load([String: CrawlFailure].self, from: Self.failuresPath) ?? [:]
        return snapshot
    }

    func save(_ game: GameSummary) {
        cache.save(game, to: Self.gamePath(game.gameId))
    }

    func save(tournaments: Cached<[TournamentRef]>, leagueId: String) {
        cache.save(tournaments, to: Self.tournamentsPath(leagueId))
    }

    func save(completed: Cached<[CompletedMatch]>, tournamentId: String) {
        cache.save(completed, to: Self.completedPath(tournamentId))
    }

    func save(standings: Cached<Standings>, tournamentId: String) {
        cache.save(standings, to: Self.standingsPath(tournamentId))
    }

    func save(failures: [String: CrawlFailure]) {
        cache.save(failures, to: Self.failuresPath)
    }

    func deleteGames(_ ids: [String]) {
        for id in ids {
            if let url = cache.url(Self.gamePath(id)) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Fichiers `<id>.json` d'un sous-dossier, par id.
    private func files(in folder: String) -> [(String, Data)] {
        guard let url = cache.url(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
        else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            guard let data = try? Data(contentsOf: url.appendingPathComponent(name)) else { return nil }
            return (String(name.dropLast(".json".count)), data)
        }
    }
}
```

- [ ] **Step 5: Écrire la planification côté appli**

Créer `App/Season/SeasonPlanning.swift` :

```swift
import Foundation
import LoLKit

/// Ce que la collecte doit savoir de l'appli à chaque tour (relu à chaque game : suivre une équipe, ouvrir une page
/// d'équipe ou révéler un match change aussitôt la suite).
struct SeasonContext: Sendable {
    var follows: FollowList
    var leagues: [League]
    var catalog: [Team]
    var revealed: Set<String>
    var openedTeamId: String?
    var now: Date
}

/// Ce que l'appli assemble autour de `CrawlPlanner` (spec saison §1.2, §1.6) : quelles ligues énumérer, quels tournois de
/// la saison lire (commencés), ce que veut la collecte. Les règles elles-mêmes (saison, tournoi en cours, étape en cours
/// du Mondial, fraîcheur, budget disque) sont dans LoLKit. Pur.
enum SeasonPlanning {
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// « 2026-10-15 » (jour UTC : les dates des tournois de l'API sont des jours sans fuseau).
    static func day(_ date: Date) -> String {
        let parts = utc.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 2026 : la saison est l'année civile (spec saison §1.2).
    static func year(_ date: Date) -> Int {
        utc.component(.year, from: date)
    }

    /// Ligues à énumérer : celles du calendrier de l'appli (ligues d'attache des équipes suivies, ligues suivies,
    /// compétitions internationales — `ScheduleQuery`), plus la ligue d'attache de l'équipe dont la page est ouverte.
    static func leagueIds(_ context: SeasonContext) -> [String] {
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

    /// Tournois de la saison de ces ligues déjà commencés (un tournoi à venir n'a ni résultat ni classement à lire), du
    /// plus récent au plus ancien (`CrawlPlanner.seasonTournaments`).
    static func startedTournaments(_ byLeague: [String: [TournamentRef]], leagueIds: [String], now: Date) -> [TournamentRef] {
        let today = day(now)
        return CrawlPlanner.seasonTournaments(leagueIds.flatMap { byLeague[$0] ?? [] }, year: year(now))
            .filter { !$0.startDate.isEmpty && $0.startDate <= today }
    }

    /// Tournois « en cours » (un par ligue : `CrawlPlanner.currentTournament`, l'actif sinon le dernier commencé).
    static func currentTournamentIds(_ byLeague: [String: [TournamentRef]], leagueIds: [String], now: Date) -> Set<String> {
        let today = day(now)
        return Set(leagueIds.compactMap { CrawlPlanner.currentTournament(byLeague[$0] ?? [], today: today)?.id })
    }

    /// Ce que veut la collecte (`CrawlWanted`) : équipe ouverte, équipes suivies, étape en cours du Mondial
    /// (`CrawlPlanner.currentStageMatchIds`), ligues suivies, tournois en cours.
    static func wanted(_ context: SeasonContext, byLeague: [String: [TournamentRef]],
                       standings: [String: Standings]) -> CrawlWanted {
        let ids = leagueIds(context)
        let worldsIds = context.leagues.filter { $0.slug == "worlds" }.map(\.id)
        let stage = currentTournamentIds(byLeague, leagueIds: worldsIds, now: context.now)
            .compactMap { standings[$0] }
            .reduce(into: Set<String>()) { $0.formUnion(CrawlPlanner.currentStageMatchIds($1)) }
        return CrawlWanted(openedTeamId: context.openedTeamId,
                           followedTeamIds: context.follows.teams.map(\.id),
                           worldsStageMatchIds: stage,
                           followedLeagueSlugs: context.follows.leagues.map(\.slug),
                           currentTournamentIds: currentTournamentIds(byLeague, leagueIds: ids, now: context.now))
    }

    /// Heure de la fenêtre « à 15 min » du palier B : début de la game + 900 s, arrondi aux 10 s inférieures (le flux
    /// refuse un `startingTime` qui n'est pas un multiple de 10 s).
    static func at15(_ startedAt: Date) -> Date {
        let seconds = startedAt.timeIntervalSince1970 + 900
        return Date(timeIntervalSince1970: (seconds / 10).rounded(.down) * 10)
    }
}
```

- [ ] **Step 6: Écrire le store**

Créer `App/Season/SeasonStore.swift` :

```swift
import Foundation
import LoLKit
import Observation

/// Avancement de la collecte, pour « Les stats arrivent : 12 games lues sur 40 » (spec saison §2.2).
struct CrawlProgress: Sendable, Equatable {
    /// Games lues (sur disque).
    var read = 0
    /// Games que la collecte veut encore lire (palier A), d'après le dernier plan.
    var remaining = 0
    /// Une passe de collecte tourne.
    var running = false
}

/// Fin d'une passe de collecte.
enum CrawlEnd: Equatable, Sendable {
    /// Plus rien à lire.
    case done
    /// Budget de la session épuisé (300 requêtes).
    case budget
    /// 5 échecs d'affilée : arrêt jusqu'à la prochaine session.
    case failures
    /// Scène quittée.
    case cancelled
    /// Store d'aperçu : aucune requête.
    case inert
}

/// Données figées d'un `SeasonStore` d'aperçu (planches PNG, #Preview) : rien n'est lu sur le disque ni sur le réseau.
struct SeasonPreview: Sendable {
    var tournaments: [TournamentRef] = []
    var matches: [SeasonMatch] = []
    var games: [GameSummary] = []
    var standings: [String: Standings] = [:]
    var failures: [String: CrawlFailure] = [:]
    var progress = CrawlProgress()
    var isLoaded = true
}

/// Statistiques de saison (spec saison §1) : les `GameSummary` des games jouées (gardés pour toujours sur disque), les
/// tournois, résultats et classements, et la collecte progressive qui les remplit au premier plan. Les agrégats
/// (`TeamSeason`, `PlayerSeason`…) sont calculés par LoLKit à la lecture, jamais stockés ; ceux des équipes sont mémoïsés
/// tant qu'aucune game n'arrive. Anti-spoiler : la collecte ne demande jamais rien pour un match masqué
/// (`SeasonMasking` → `CrawlPlanner`), et chaque agrégat reçoit les matchs masqués à exclure.
@MainActor
@Observable
final class SeasonStore {
    // MARK: Données

    private(set) var games: [String: GameSummary] = [:]
    /// Tournois de chaque ligue (par id de ligue), du plus récent au plus ancien.
    private(set) var tournaments: [String: [TournamentRef]] = [:]
    /// Classements de chaque tournoi lu (par id de tournoi).
    private(set) var standings: [String: Standings] = [:]
    /// Matchs joués de tous les tournois lus (jointure résultats + classements, `SeasonMatch.join`).
    private(set) var matches: [SeasonMatch] = []
    private(set) var failures: [String: CrawlFailure] = [:]
    /// Le disque a été lu : avant, les écrans montrent leurs squelettes.
    private(set) var isLoaded = false
    private(set) var progress = CrawlProgress()
    /// Change à chaque game lue ou tournoi relu : clé de mémoïsation des écrans (Accueil).
    private(set) var version = 0
    /// Équipe dont la page est ouverte (collecte priorité 0 si elle n'est pas suivie).
    private(set) var openedTeamId: String?

    // MARK: Interne

    @ObservationIgnored private var completed: [String: [CompletedMatch]] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private var joinCatalog: [Team] = []
    @ObservationIgnored private var joinLeagues: [League] = []
    @ObservationIgnored private var teamMemo: [TeamSeasonKey: TeamSeason] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var wakeRequested = false
    @ObservationIgnored private var schedulePages: [String: SchedulePageResult] = [:]
    let disk: SeasonDisk?
    let paced: PacedTransport?
    let clock: any CrawlClock

    /// - Parameters:
    ///   - transport: réseau de l'appli ; la collecte l'enveloppe dans un `PacedTransport` (cadence, recul, budget).
    ///   - cache: `cache/` de l'appli ; la saison vit sous `cache/season/`.
    ///   - clock: horloge des attentes (tests : horloge virtuelle).
    init(transport: any HTTPTransport, cache: DiskCache, clock: any CrawlClock = SystemCrawlClock()) {
        disk = SeasonDisk(cache: cache)
        paced = PacedTransport(base: transport, clock: clock)
        self.clock = clock
    }

    /// Aperçus : données figées, aucune requête, aucun fichier.
    init(preview: SeasonPreview) {
        disk = nil
        paced = nil
        clock = SystemCrawlClock()
        games = Dictionary(preview.games.map { ($0.gameId, $0) }, uniquingKeysWith: { first, _ in first })
        tournaments = Dictionary(grouping: preview.tournaments, by: \.leagueId)
        standings = preview.standings
        matches = preview.matches.sorted { $0.startTime > $1.startTime }
        failures = preview.failures
        progress = preview.progress
        isLoaded = preview.isLoaded
    }

    var isPreview: Bool {
        paced == nil
    }

    // MARK: Lecture du disque

    /// Lit `cache/season/` une fois, hors du fil principal (≈ 2 000 petits fichiers au plus), puis publie tout d'un coup.
    /// Les appels suivants attendent la première lecture.
    func loadFromDisk() async {
        if let loading {
            await loading.value
            return
        }
        guard let disk else {
            isLoaded = true
            return
        }
        let task = Task {
            let snapshot = await Task.detached(priority: .utility) { disk.load() }.value
            self.publish(snapshot)
        }
        loading = task
        await task.value
    }

    private func publish(_ snapshot: SeasonDisk.Snapshot) {
        games.merge(snapshot.games) { current, _ in current }
        for (leagueId, cached) in snapshot.tournaments where tournaments[leagueId] == nil {
            tournaments[leagueId] = cached.value
            fetchedAt[Self.tournamentsKey(leagueId)] = cached.fetchedAt
        }
        for (tournamentId, cached) in snapshot.completed where completed[tournamentId] == nil {
            completed[tournamentId] = cached.value
            fetchedAt[Self.completedKey(tournamentId)] = cached.fetchedAt
        }
        for (tournamentId, cached) in snapshot.standings where standings[tournamentId] == nil {
            standings[tournamentId] = cached.value
            fetchedAt[Self.standingsKey(tournamentId)] = cached.fetchedAt
        }
        failures.merge(snapshot.failures) { current, _ in current }
        rejoin()
        isLoaded = true
        version += 1
    }

    // MARK: Lectures pour les vues

    func tournament(id: String) -> TournamentRef? {
        tournaments.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    /// Matchs joués d'une équipe (id), du plus récent au plus ancien.
    func matches(ofTeam teamId: String) -> [SeasonMatch] {
        matches.filter { $0.teams.contains { $0.id == teamId } }
    }

    /// Games sans résumé en échec définitif de collecte (« N games sans stats ») ; une game lue au palier A dont le palier
    /// B échoue n'en fait pas partie.
    var withoutStats: Set<String> {
        Set(failures.filter { $0.value.isFinal && games[$0.key] == nil }.keys)
    }

    /// Bilan, forme, moyennes… d'une équipe sur un périmètre (`SeasonStats.team`), sans ses matchs masqués ; mémoïsé tant
    /// qu'aucune game n'arrive et que le jour ne change pas.
    func teamSeason(_ teamId: String, scope: SeasonScope, masked: Set<String>, now: Date) -> TeamSeason {
        let key = TeamSeasonKey(teamId: teamId, scope: scope, masked: masked, version: version,
                                day: SeasonPlanning.day(now))
        if let known = teamMemo[key] { return known }
        let value = SeasonStats.team(teamId, matches: matches, games: games, scope: scope, masked: masked, now: now,
                                     withoutStats: withoutStats)
        if teamMemo.count > 64 { teamMemo.removeAll() }
        teamMemo[key] = value
        return value
    }

    /// Stats de saison d'un joueur sur un périmètre (nil : toute la saison connue), sans les matchs masqués.
    func player(_ playerId: String, scope: SeasonScope?, masked: Set<String>) -> PlayerSeason? {
        let pool = scope.map { scope in games.values.filter { scope.tournamentIds.contains($0.tournamentId) } }
            ?? Array(games.values)
        return SeasonStats.player(playerId, games: pool, masked: masked, since: nil)
    }

    /// Périmètres d'une équipe (spec saison §3.1) : la saison (`SeasonScope.season`) puis un par tournoi de l'année où
    /// elle a joué (`SeasonScope.tournament`), du plus récent au plus ancien ; aucun si elle n'a joué aucun match connu.
    /// Les libellés sont des valeurs (année, slug) : l'écran les formule (`SeasonLabels.scope`).
    func scopes(forTeam teamId: String, now: Date) -> [SeasonScope] {
        let ids = Set(matches(ofTeam: teamId).map(\.tournamentId))
        let played = CrawlPlanner.seasonTournaments(tournaments.values.flatMap { $0 }, year: SeasonPlanning.year(now))
            .filter { ids.contains($0.id) }
        guard !played.isEmpty else { return [] }
        return [SeasonScope.season(SeasonPlanning.year(now), tournaments: played)] + played.map(SeasonScope.tournament)
    }

    /// Tournoi en cours de l'équipe (classement de sa page) : le plus récent de l'année où elle a joué.
    func currentTournament(forTeam teamId: String, now: Date) -> TournamentRef? {
        let ids = Set(matches(ofTeam: teamId).map(\.tournamentId))
        return tournaments.values.flatMap { $0 }
            .filter { ids.contains($0.id) && $0.startDate <= SeasonPlanning.day(now) }
            .max { ($0.startDate, $0.id) < ($1.startDate, $1.id) }
    }

    // MARK: Page d'équipe ouverte, réveil de la collecte

    /// Page d'équipe ouverte : la collecte passe d'abord par son tournoi en cours (priorité 0) si elle n'est pas suivie.
    func open(teamId: String) {
        openedTeamId = teamId
        wake()
    }

    /// Page fermée : la priorité 0 s'arrête (seulement si c'est bien elle qui était ouverte).
    func close(teamId: String) {
        if openedTeamId == teamId { openedTeamId = nil }
    }

    /// Quelque chose a changé ce que veut la collecte (suivi, révélation, page ouverte) : la boucle de la scène relance
    /// une passe sans attendre ses 30 min.
    func wake() {
        wakeRequested = true
    }

    /// Attente de la boucle de la scène entre deux passes : rend la main à un réveil (`wake`), après `maxSeconds`, ou à
    /// l'annulation de la tâche (scène quittée).
    func waitForWake(maxSeconds: TimeInterval) async {
        var waited: TimeInterval = 0
        while !wakeRequested && waited < maxSeconds && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
            waited += RefreshPolicy.tick
        }
        wakeRequested = false
    }

    /// Nouvelle session au premier plan (`AppStore.poll`) : budget et recul de la collecte remis à zéro.
    func beginSession() async {
        await paced?.beginSession()
    }

    // MARK: Collecte

    /// Une passe de collecte (spec saison §1.6), au premier plan seulement : énumération (tournois, résultats,
    /// classements), puis une game à la fois dans l'ordre de `CrawlPlanner` — replanifié après chaque game avec le
    /// contexte du moment (`context`). Rend la main quand il n'y a plus rien à lire, quand le budget de la session est
    /// épuisé, après 5 échecs d'affilée, ou quand la tâche est annulée.
    @discardableResult
    func crawl(context: @MainActor () -> SeasonContext) async -> CrawlEnd {
        guard let paced else { return .inert }
        await loadFromDisk()
        progress.running = true
        defer { progress.running = false }
        let crawler = SeasonCrawler(store: self, client: LoLClient(transport: paced), clock: clock)
        return await crawler.run(context: context)
    }

    /// Une page `older` / `newer` du calendrier (spec saison §3.2), gardée en mémoire pour la session ; nil si elle n'a
    /// pas pu être lue. Passe par le transport de la collecte (cadence et budget communs).
    func schedulePage(leagueIds: [String], token: String?) async -> SchedulePageResult? {
        let key = leagueIds.joined(separator: ",") + "#" + (token ?? "")
        if let known = schedulePages[key] { return known }
        guard let paced else { return nil }
        guard let page = try? await LoLClient(transport: paced).schedulePage(leagueIds: leagueIds, pageToken: token)
        else { return nil }
        schedulePages[key] = page
        return page
    }

    /// Classement d'un tournoi ouvert à l'écran et pas encore lu par la collecte : une requête, au rythme de la collecte.
    func loadStandings(tournamentId: String) async {
        guard standings[tournamentId] == nil, let paced else { return }
        guard let value = try? await LoLClient(transport: paced).standings(tournamentId: tournamentId) else { return }
        record(standings: value, tournamentId: tournamentId, at: await clock.now())
    }

    // MARK: Écritures (collecte)

    static func tournamentsKey(_ leagueId: String) -> String { "tournaments/\(leagueId)" }
    static func completedKey(_ tournamentId: String) -> String { "completed/\(tournamentId)" }
    static func standingsKey(_ tournamentId: String) -> String { "standings/\(tournamentId)" }

    func lastFetch(_ key: String) -> Date? {
        fetchedAt[key]
    }

    /// Liste refusée par l'API ou illisible : notée lue pour la session (mémoire seulement), sans quoi la passe la
    /// redemanderait sans fin.
    func markFetched(_ key: String, at date: Date) {
        fetchedAt[key] = date
    }

    func record(tournaments value: [TournamentRef], leagueId: String, at date: Date) {
        tournaments[leagueId] = value
        fetchedAt[Self.tournamentsKey(leagueId)] = date
        disk?.save(tournaments: Cached(value: value, fetchedAt: date), leagueId: leagueId)
    }

    func record(completed value: [CompletedMatch], tournamentId: String, at date: Date) {
        completed[tournamentId] = value
        fetchedAt[Self.completedKey(tournamentId)] = date
        disk?.save(completed: Cached(value: value, fetchedAt: date), tournamentId: tournamentId)
    }

    func record(standings value: Standings, tournamentId: String, at date: Date) {
        standings[tournamentId] = value
        fetchedAt[Self.standingsKey(tournamentId)] = date
        disk?.save(standings: Cached(value: value, fetchedAt: date), tournamentId: tournamentId)
        rejoin()
    }

    /// Jointure résultats + classements de chaque tournoi lu (`SeasonMatch.join`), avec le catalogue et les ligues du
    /// moment ; recalcule les vainqueurs des séries complètes.
    func rejoin(catalog: [Team]? = nil, leagues: [League]? = nil) {
        if let catalog { joinCatalog = catalog }
        if let leagues { joinLeagues = leagues }
        var all: [SeasonMatch] = []
        for (tournamentId, events) in completed {
            let leagueId = tournament(id: tournamentId)?.leagueId
            let slug = joinLeagues.first { $0.id == leagueId }?.slug ?? ""
            all += SeasonMatch.join(completed: events, standings: standings[tournamentId], tournamentId: tournamentId,
                                    leagueSlug: slug, catalog: joinCatalog)
        }
        let sorted = all.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        if sorted != matches {
            matches = sorted
            teamMemo.removeAll()
            version += 1
        }
    }

    /// Une game lue (palier A, ou B qui réécrit le même fichier) : en mémoire, sur disque ; vainqueurs de sa série
    /// rejoués si toutes ses games jouées sont là ; games anciennes d'équipes non suivies supprimées au-delà de 2 000.
    func record(_ game: GameSummary, followedTeamIds: Set<String>) {
        games[game.gameId] = game
        failures[game.gameId] = nil
        disk?.save(game)
        assignWinners(matchId: game.matchId)
        let excess = CrawlPlanner.evictions(Array(games.values), followedTeamIds: followedTeamIds)
        if !excess.isEmpty {
            for id in excess { games[id] = nil }
            disk?.deleteGames(excess)
        }
        progress.read = games.count
        teamMemo.removeAll()
        version += 1
    }

    /// Échec d'une game (`CrawlFailure.record` : essais comptés par raison ; `http` n'est jamais enregistré).
    func recordFailure(_ reason: CrawlFailure.Reason, gameId: String, at date: Date) {
        failures[gameId] = CrawlFailure.record(reason, previous: failures[gameId], now: date)
        disk?.save(failures: failures)
    }

    func setProgress(remaining: Int) {
        progress.read = games.count
        progress.remaining = remaining
    }

    /// `GameWinners.apply` dès que toutes les games jouées du match sont en cache (spec saison §1.6) ; seules les games
    /// dont le résultat change sont réécrites.
    private func assignWinners(matchId: String) {
        guard let match = matches.first(where: { $0.id == matchId }),
              match.playedGameIds.allSatisfy({ games[$0] != nil }) else { return }
        let updated = GameWinners.apply(teams: match.teams, playedGameIds: match.playedGameIds, to: games)
        for gameId in match.playedGameIds {
            guard let game = updated[gameId], game.result != games[gameId]?.result else { continue }
            games[gameId] = game
            disk?.save(game)
        }
    }
}

/// Clé de mémoïsation d'un `TeamSeason`.
private struct TeamSeasonKey: Hashable {
    let teamId: String
    let scope: SeasonScope
    let masked: Set<String>
    let version: Int
    let day: String
}
```

- [ ] **Step 7: Écrire le collecteur**

Créer `App/Season/SeasonCrawler.swift` :

```swift
import Foundation
import LoLKit

/// Exécute la collecte de saison (spec saison §1.6) : la logique (quoi lire, dans quel ordre, quand réessayer, à quel
/// rythme) est dans LoLKit (`CrawlPlanner`, `CrawlPacer`) ; ici, les requêtes et leur rangement dans `SeasonStore`.
/// Toutes les requêtes passent par le `PacedTransport` du store (2 s entre deux, recul, budget de 300 par session).
@MainActor
struct SeasonCrawler {
    let store: SeasonStore
    let client: LoLClient
    let clock: any CrawlClock

    func run(context: @MainActor () -> SeasonContext) async -> CrawlEnd {
        while !Task.isCancelled {
            let now = await clock.now()
            var current = context()
            current.now = now
            do {
                try await enumerate(current)
                let masked = SeasonMasking.maskedMatchIds(store.matches, follows: current.follows,
                                                          revealed: current.revealed)
                let wanted = SeasonPlanning.wanted(current, byLeague: store.tournaments, standings: store.standings)
                let jobs = CrawlPlanner.jobs(wanted: wanted, matches: store.matches, have: store.games,
                                             failures: store.failures, masked: masked, now: now)
                store.setProgress(remaining: jobs.filter { $0.tier == .a }.count)
                guard let job = jobs.first else { return .done }
                try await read(job, followedTeamIds: Set(current.follows.teams.map(\.id)))
            } catch let stop as CrawlStopped {
                return stop.reason == .budget ? .budget : .failures
            } catch {
                if Task.isCancelled || PacedTransport.isCancellation(error) { return .cancelled }
                // 429, 5xx, réseau : le transport a déjà posé son recul ; on reprend au même endroit.
            }
        }
        return .cancelled
    }

    // MARK: Énumération

    /// Tournois des ligues voulues (24 h), puis résultats et classements de chaque tournoi de la saison déjà commencé :
    /// relus après 30 min s'il est en cours, jamais s'il est terminé et déjà lu. Le catalogue et les ligues du moment
    /// servent à la jointure.
    private func enumerate(_ context: SeasonContext) async throws {
        let now = context.now
        let leagueIds = SeasonPlanning.leagueIds(context)
        for leagueId in leagueIds {
            let key = SeasonStore.tournamentsKey(leagueId)
            guard CrawlPlanner.needsRefresh(fetchedAt: store.lastFetch(key), now: now,
                                            maxAge: CrawlPlanner.tournamentsMaxAge) else { continue }
            if let refs = try await fetch(key, now: now, { try await client.tournaments(leagueId: leagueId) }) {
                store.record(tournaments: refs, leagueId: leagueId, at: now)
            }
        }
        let today = SeasonPlanning.day(now)
        for tournament in SeasonPlanning.startedTournaments(store.tournaments, leagueIds: leagueIds, now: now) {
            // En cours : relu après 30 min ; terminé et déjà lu : jamais relu (`CrawlPlanner.maxAge` nil).
            let maxAge = CrawlPlanner.maxAge(of: tournament, today: today)
            let completedKey = SeasonStore.completedKey(tournament.id)
            if CrawlPlanner.needsRefresh(fetchedAt: store.lastFetch(completedKey), now: now, maxAge: maxAge),
               let events = try await fetch(completedKey, now: now, {
                   try await client.completedEvents(tournamentId: tournament.id)
               }) {
                store.record(completed: events, tournamentId: tournament.id, at: now)
            }
            let standingsKey = SeasonStore.standingsKey(tournament.id)
            if CrawlPlanner.needsRefresh(fetchedAt: store.lastFetch(standingsKey), now: now, maxAge: maxAge),
               let value = try await fetch(standingsKey, now: now, {
                   try await client.standings(tournamentId: tournament.id)
               }) {
                store.record(standings: value, tournamentId: tournament.id, at: now)
            }
        }
        store.rejoin(catalog: context.catalog, leagues: context.leagues)
    }

    /// Une liste de l'énumération. Refus définitif de l'API (4xx hors 429) ou réponse illisible : la liste est notée lue
    /// pour cette session (en mémoire seulement), sans quoi la passe la redemanderait sans fin ; 429, 5xx, réseau :
    /// l'erreur remonte (recul du transport).
    private func fetch<T>(_ key: String, now: Date, _ read: () async throws -> T) async throws -> T? {
        do {
            return try await read()
        } catch {
            if Self.mustPropagate(error) { throw error }
            store.markFetched(key, at: now)
            return nil
        }
    }

    /// Erreurs qui arrêtent ou font reculer la collecte, au lieu d'être rangées comme un échec de la donnée : arrêt de
    /// session, annulation, 429, 5xx, réseau.
    static func mustPropagate(_ error: any Error) -> Bool {
        if error is CrawlStopped || PacedTransport.isCancellation(error) || error is URLError { return true }
        if case let LoLAPIError.http(status) = error { return status == 429 || status >= 500 }
        return false
    }

    // MARK: Une game

    /// Palier A : début de la game (`window` sans `startingTime`) puis sa fin (`liveWindow`, recul compris) ; accepté
    /// seulement avec la frame `finished` (`GameSummary.make`), écrit en un seul fichier. Palier B : LoLKit n'enrichit pas
    /// une game déjà lue, `make` reçoit donc à nouveau le début et la fin, plus la fenêtre à 15 min et la dernière frame
    /// de `details` (4 requêtes), et réécrit le même fichier ; si ni l'une ni l'autre n'est fournie, la game est notée
    /// `noData` (réessai dans 1 h, 3 fois) au lieu d'être redemandée aussitôt.
    /// Erreurs : 404 → `statsDisabled` (définitif) ; 204 → `noData` ; game pas finie → `notFinished` (réessais de
    /// `CrawlPlanner`) ; 400 persistant ou réponse illisible (`CrawlFailure.reason` les range en `http`, jamais
    /// enregistré) → `noData`, sinon la même game serait redemandée sans fin ; 429, 5xx, réseau → l'erreur remonte, le
    /// transport recule, la game sera reprise.
    private func read(_ job: CrawlJob, followedTeamIds: Set<String>) async throws {
        let now = await clock.now()
        do {
            let first = try await client.window(gameId: job.gameId, startingTime: nil)
            let final = try await client.liveWindow(gameId: job.gameId, now: await clock.now())
            switch job.tier {
            case .a:
                guard let summary = GameSummary.make(first: first, final: final, at15: nil, details: nil,
                                                     matchId: job.matchId, number: job.number,
                                                     tournamentId: job.tournamentId, leagueSlug: job.leagueSlug)
                else {
                    store.recordFailure(.notFinished, gameId: job.gameId, at: now)
                    return
                }
                store.record(summary, followedTeamIds: followedTeamIds)
            case .b:
                guard let known = store.games[job.gameId] else { return }
                let start = first.frames.map(\.rfc460Timestamp).min() ?? known.startedAt
                let at15 = try await optional {
                    try await client.window(gameId: job.gameId, startingTime: SeasonPlanning.at15(start))
                }
                let details = try await optional { try await client.details(gameId: job.gameId, now: await clock.now()) }
                guard at15 != nil || details != nil,
                      var enriched = GameSummary.make(first: first, final: final, at15: at15, details: details,
                                                      matchId: job.matchId, number: job.number,
                                                      tournamentId: job.tournamentId, leagueSlug: job.leagueSlug)
                else {
                    store.recordFailure(.noData, gameId: job.gameId, at: now)
                    return
                }
                enriched.result = known.result
                store.record(enriched, followedTeamIds: followedTeamIds)
            }
        } catch {
            if Self.mustPropagate(error) { throw error }
            let reason = CrawlFailure.reason(for: error)
            store.recordFailure(reason == .http ? .noData : reason, gameId: job.gameId, at: now)
        }
    }

    /// Une lecture facultative du palier B : absente (204, 404, 400, illisible) → nil ; arrêt, annulation, 429, 5xx et
    /// réseau remontent.
    private func optional<T>(_ read: () async throws -> T) async throws -> T? {
        do {
            return try await read()
        } catch {
            if Self.mustPropagate(error) { throw error }
            return nil
        }
    }
}
```

- [ ] **Step 8: Écrire les libellés de périmètre**

Créer `App/Season/SeasonLabels.swift` :

```swift
import Foundation
import LoLKit

/// Noms affichés des périmètres de saison (spec saison §3.1, §3.8 : LoLKit donne des valeurs, l'appli formule) :
/// « Saison 2026 », « LEC Split 3 », « Mondial ». Chaînes prêtes pour `Localizable.xcstrings` (P2).
enum SeasonLabels {
    static func season(year: String) -> String {
        String(localized: "Saison \(year)")
    }

    /// Libellé d'un périmètre (`SeasonScope.label` est une valeur : l'année « 2026 » ou le slug d'un tournoi).
    static func scope(_ scope: SeasonScope) -> String {
        Int(scope.label) != nil ? season(year: scope.label) : tournament(slug: scope.label)
    }

    /// Nom d'une compétition par son slug de ligue : internationales traduites (« Mondial » / « Worlds »), les autres en
    /// capitales (« LEC », « LCK », « LFL »).
    static func league(slug: String) -> String {
        switch slug {
        case "worlds": return String(localized: "Mondial")
        case "msi": return "MSI"
        case "first_stand": return "First Stand"
        default: return slug.uppercased()
        }
    }

    /// « lec_split_3_2026 » → « LEC Split 3 » ; « worlds_2026 » → « Mondial » ; « lck_split_2_playoffs_2026 » →
    /// « LCK Split 2 Play-offs ». Le slug de ligue est le premier mot connu (`first_stand` en compte deux) ; l'année finale
    /// est retirée ; les autres mots prennent une capitale.
    static func tournament(_ tournament: TournamentRef) -> String {
        self.tournament(slug: tournament.slug)
    }

    static func tournament(slug: String) -> String {
        var words = slug.split(separator: "_").map(String.init)
        if let last = words.last, last.count == 4, Int(last) != nil { words.removeLast() }
        guard !words.isEmpty else { return slug }
        let leagueSlug: String
        if words.count >= 2, words[0] == "first", words[1] == "stand" {
            leagueSlug = "first_stand"
            words.removeFirst(2)
        } else {
            leagueSlug = words.removeFirst()
        }
        let rest = words.map { word -> String in
            switch word {
            case "playoffs": return String(localized: "Play-offs")
            case "split": return String(localized: "Split")
            default: return word.prefix(1).uppercased() + word.dropFirst()
            }
        }
        return ([league(slug: leagueSlug)] + rest).joined(separator: " ")
    }
}
```

- [ ] **Step 9: Écrire la saison d'exemple**

Créer `App/Season/SeasonSamples.swift` (les ids d'équipe, de match et de game sont ceux de `SampleData` ; « aujourd'hui » des planches = 15/10/2026 15:05 UTC) :

```swift
import Foundation
import LoLKit

/// Saison d'exemple des aperçus (planches PNG, #Preview), cohérente avec `SampleData` : mêmes ids d'équipe (« kc »,
/// « g2 », « t1 »…), même match KC 1 – 3 G2 (« m-kc-g2 », games « g1-kc-g2 »…), « aujourd'hui » = 15/10/2026. T1 est en
/// anti-spoiler dans `SampleData.follows` : ses matchs sont masqués (« 2 matchs masqués » dans les planches).
/// Chiffres inventés mais plausibles, construits uniquement avec les inits publics de LoLKit ; aucune image.
enum SeasonSamples {
    static let lecId = "98767991302996019"
    static let lckId = "98767991310872058"
    static let worldsId = "98767975604431411"

    static let lecSplit3 = TournamentRef(id: "t-lec-s3", slug: "lec_split_3_2026", startDate: "2026-07-23",
                                         endDate: "2026-09-20", leagueId: lecId)
    static let lckSplit3 = TournamentRef(id: "t-lck-s3", slug: "lck_split_3_2026", startDate: "2026-07-16",
                                         endDate: "2026-09-27", leagueId: lckId)
    static let worlds = TournamentRef(id: "t-worlds-26", slug: "worlds_2026", startDate: "2026-10-01",
                                      endDate: "2026-11-15", leagueId: worldsId)

    /// Joueurs d'exemple par équipe, du top au support : (id, pseudo du flux).
    static let rosters: [String: [(id: String, name: String)]] = [
        "kc": [("p-canna", "KC Canna"), ("p-yike", "KC Yike"), ("p-kyeahoo", "KC kyeahoo"), ("p-caliste", "KC Caliste"),
               ("p-busio", "KC Busio")],
        "g2": [("p-bb", "G2 BrokenBlade"), ("p-skewmond", "G2 SkewMond"), ("p-caps", "G2 Caps"),
               ("p-hans", "G2 Hans Sama"), ("p-labrov", "G2 Labrov")],
        "t1": [("p-doran", "T1 Doran"), ("p-oner", "T1 Oner"), ("p-faker", "T1 Faker"), ("p-gumayusi", "T1 Gumayusi"),
               ("p-keria", "T1 Keria")],
        "gen": [("p-kiin", "GEN Kiin"), ("p-canyon", "GEN Canyon"), ("p-chovy", "GEN Chovy"), ("p-ruler", "GEN Ruler"),
                ("p-duro", "GEN Duro")],
        "hle": [("p-zeus", "HLE Zeus"), ("p-peanut", "HLE Peanut"), ("p-zeka", "HLE Zeka"), ("p-viper", "HLE Viper"),
                ("p-delight", "HLE Delight")],
        "vit": [("p-naak", "VIT Naak Nako"), ("p-lyncas", "VIT Lyncas"), ("p-humanoid", "VIT Humanoid"),
                ("p-carzzy", "VIT Carzzy"), ("p-fleshy", "VIT Fleshy")],
        "blg": [("p-bin", "BLG Bin"), ("p-xun", "BLG Xun"), ("p-knight", "BLG knight"), ("p-elk", "BLG Elk"),
                ("p-on", "BLG ON")],
    ]

    private static let champions: [[String]] = [
        ["Jayce", "Rumble", "KSante", "Gnar"], ["Vi", "XinZhao", "Sejuani", "LeeSin"],
        ["Ahri", "Taliyah", "Orianna", "Azir"], ["Caitlyn", "Kaisa", "Varus", "Ezreal"],
        ["Bard", "Rell", "Braum", "Rakan"],
    ]

    private static let roles = ["top", "jungle", "mid", "bottom", "support"]

    /// Matchs d'exemple : (id, tournoi, étape, début, équipe A et ses victoires, équipe B et ses victoires).
    private static let schedule: [(String, TournamentRef, String?, String, (String, Int), (String, Int))] = [
        ("m-gen-hle", worlds, "play_ins", "2026-10-11T09:00:00Z", ("gen", 3), ("hle", 0)),
        ("m-t1-blg", worlds, "play_ins", "2026-10-08T12:00:00Z", ("t1", 2), ("blg", 1)),
        ("m-kc-g2", worlds, "play_ins", "2026-10-05T16:00:00Z", ("kc", 1), ("g2", 3)),
        ("m-t1-hle", worlds, "play_ins", "2026-10-03T12:00:00Z", ("t1", 0), ("hle", 2)),
        ("m-kc-g2-s3", lecSplit3, "playoffs", "2026-09-06T15:00:00Z", ("g2", 3), ("kc", 2)),
        ("m-kc-vit", lecSplit3, "regular_season", "2026-08-30T17:00:00Z", ("kc", 2), ("vit", 0)),
        ("m-gen-t1", lckSplit3, "regular_season", "2026-08-29T08:00:00Z", ("gen", 2), ("t1", 1)),
        ("m-kc-g2-rs", lecSplit3, "regular_season", "2026-08-16T17:00:00Z", ("kc", 2), ("g2", 1)),
        ("m-vit-kc", lecSplit3, "regular_season", "2026-08-02T17:00:00Z", ("vit", 1), ("kc", 2)),
    ]

    static var matches: [SeasonMatch] {
        schedule.map { id, tournament, stage, start, a, b in
            SeasonMatch(id: id, tournamentId: tournament.id, leagueSlug: leagueSlug(tournament), stageSlug: stage,
                        startTime: SampleData.date(start), blockName: nil, bestOf: a.1 + b.1 > 3 || max(a.1, b.1) == 3 ? 5 : 3,
                        teams: [side(a.0, wins: a.1, won: a.1 > b.1), side(b.0, wins: b.1, won: b.1 > a.1)],
                        playedGameIds: (1...(a.1 + b.1)).map { "g\($0)-\(id.dropFirst(2))" })
        }
    }

    /// Une game par game jouée, palier B pour les games du Mondial (gold à 15 min, part des dégâts), palier A sinon.
    static var games: [GameSummary] {
        matches.flatMap { match -> [GameSummary] in
            let a = match.teams[0], b = match.teams[1]
            // Ordre des victoires : l'équipe qui perd la série gagne ses games d'abord (série serrée).
            let loserWins = min(a.gameWins, b.gameWins)
            let winner = a.gameWins > b.gameWins ? a : b
            let loser = a.gameWins > b.gameWins ? b : a
            return match.playedGameIds.enumerated().map { index, gameId in
                let winnerId = index < loserWins ? loser.id! : winner.id!
                let seed = gameId.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 7 + index
                return game(gameId, match: match, number: index + 1, blue: a.id!, red: b.id!, winner: winnerId,
                            seed: seed, enriched: match.tournamentId == worlds.id,
                            basis: index == match.playedGameIds.count - 1 || loserWins == 0 ? .exact : .inferred)
            }
        }
    }

    /// Classements : LEC Split 3 (saison régulière classée), Mondial (play-ins, puis système suisse à venir).
    static var standings: [String: Standings] {
        func ranked(_ ordinal: Int, _ id: String, _ wins: Int, _ losses: Int) -> Ranking {
            let team = SampleData.catalog.first { $0.id == id }
            return Ranking(ordinal: ordinal, teams: [RankedTeam(id: id, code: team?.code ?? id.uppercased(),
                                                               name: team?.name ?? id, image: nil, wins: wins,
                                                               losses: losses)])
        }
        func bracket(_ match: SeasonMatch) -> BracketMatch {
            BracketMatch(id: match.id, state: .completed, teams: match.teams)
        }
        let worldsMatches = matches.filter { $0.tournamentId == worlds.id }
        let upcoming = BracketMatch(id: "m-kc-c9", state: .inProgress,
                                    teams: [side("kc", wins: 1, won: false), side("c9", wins: 0, won: false)])
        return [
            lecSplit3.id: Standings(stages: [
                StandingsStage(id: "s-lec-rs", name: "Saison régulière", slug: "regular_season", sections: [
                    StandingsSection(name: "Saison régulière",
                                     matches: matches.filter { $0.stageSlug == "regular_season" && $0.tournamentId == lecSplit3.id }
                                         .map(bracket),
                                     rankings: [ranked(1, "kc", 9, 0), ranked(2, "vit", 7, 2), ranked(3, "g2", 6, 3)]),
                ]),
                StandingsStage(id: "s-lec-po", name: "Play-offs", slug: "playoffs", sections: [
                    StandingsSection(name: "Tableau", matches: matches.filter { $0.stageSlug == "playoffs" }.map(bracket),
                                     rankings: []),
                ]),
            ]),
            worlds.id: Standings(stages: [
                StandingsStage(id: "s-w-pi", name: "Play-ins", slug: "play_ins", sections: [
                    StandingsSection(name: "Play-ins", matches: worldsMatches.map(bracket) + [upcoming], rankings: []),
                ]),
                StandingsStage(id: "s-w-sw", name: "Système suisse", slug: "swiss", sections: [
                    StandingsSection(name: "Système suisse", matches: [], rankings: []),
                ]),
            ]),
        ]
    }

    /// Saison complète, tout lu.
    static var standard: SeasonPreview {
        SeasonPreview(tournaments: [lecSplit3, lckSplit3, worlds], matches: matches, games: games, standings: standings,
                      progress: CrawlProgress(read: games.count, remaining: 0, running: false))
    }

    /// Collecte en cours : seules les games du Mondial sont lues, 14 restent à lire.
    static var collecting: SeasonPreview {
        var preview = standard
        preview.games = preview.games.filter { $0.tournamentId == worlds.id }
        preview.progress = CrawlProgress(read: preview.games.count, remaining: 14, running: true)
        return preview
    }

    /// Disque pas encore lu : squelettes.
    static var loading: SeasonPreview {
        SeasonPreview(isLoaded: false)
    }

    // MARK: Construction

    private static func leagueSlug(_ tournament: TournamentRef) -> String {
        switch tournament.leagueId {
        case lecId: return "lec"
        case lckId: return "lck"
        default: return "worlds"
        }
    }

    private static func side(_ id: String, wins: Int, won: Bool) -> MatchTeam {
        let team = SampleData.catalog.first { $0.id == id }
        return MatchTeam(id: id, name: team?.name ?? id.uppercased(), code: team?.code ?? id.uppercased(), image: nil,
                         result: MatchTeam.Result(outcome: won ? "win" : "loss", gameWins: wins))
    }

    private static func game(_ gameId: String, match: SeasonMatch, number: Int, blue: String, red: String,
                             winner: String, seed: Int, enriched: Bool, basis: GameResult.Basis) -> GameSummary {
        let start = match.startTime.addingTimeInterval(Double(number - 1) * 3_000 + 900)
        let duration = 1_740 + seed * 137
        func line(_ teamId: String, won: Bool) -> TeamGameLine {
            let kills = won ? 16 + seed : 8 + seed / 2
            let shares: [Double] = [0.24, 0.14, 0.27, 0.28, 0.07]
            let killWeights = [2, 3, 4, 5, 0]
            let players = (0..<5).map { (index: Int) -> PlayerGameLine in
                let fallback = (id: "p-\(teamId)-\(index)", name: "\(teamId.uppercased()) \(roles[index])")
                let roster: (id: String, name: String) = rosters[teamId]?[index] ?? fallback
                let share = shares[index]
                return PlayerGameLine(
                    playerId: roster.id, name: roster.name, role: roles[index],
                    champion: champions[index][(seed + index + (won ? 0 : 1)) % champions[index].count],
                    level: won ? 17 : 15, kills: index == 4 ? 1 : (kills * killWeights[index]) / 14,
                    deaths: won ? 1 + index % 2 : 3 + index % 3, assists: won ? 6 + index * 2 : 3 + index,
                    creepScore: index == 4 ? 38 : (index == 1 ? 190 : 280) + seed * 3,
                    gold: (won ? 13_500 : 11_200) - index * 600 + seed * 40,
                    damageShare: enriched ? share : nil, wardsPlaced: enriched ? 10 + index * 3 : nil,
                    wardsDestroyed: enriched ? 3 + index : nil, gold15: enriched ? 5_000 + index * 120 : nil,
                    creepScore15: enriched ? (index == 4 ? 18 : 120 + index * 4) : nil)
            }
            return TeamGameLine(teamId: teamId, kills: kills, gold: players.reduce(0) { $0 + $1.gold },
                                towers: won ? 9 + seed % 3 : 3 + seed % 2, inhibitors: won ? 2 : 0, barons: won ? 1 + seed % 2 : 0,
                                dragons: won ? ["ocean", "infernal", "mountain"].prefix(2 + seed % 2).map { $0 } : ["cloud"],
                                gold15: enriched ? (won ? 26_400 : 24_900) : nil, players: players)
        }
        return GameSummary(gameId: gameId, matchId: match.id, tournamentId: match.tournamentId, leagueSlug: match.leagueSlug,
                           number: number, patch: "16.19.1", startedAt: start,
                           endedAt: start.addingTimeInterval(Double(duration)), durationSeconds: duration,
                           result: GameResult(winnerTeamId: winner, basis: basis),
                           blue: line(blue, won: winner == blue), red: line(red, won: winner == red), enriched: enriched)
    }
}
```

- [ ] **Step 10: Commit, push, CI une fois**

```bash
git add App/Season Tests/FailleTests/SeasonStoreTests.swift
git commit -m "feat(app): SeasonStore — collecte de saison au premier plan (cadence 2 s, recul, budget 300, jamais un match masqué), cache disque, saison d'exemple" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a1-saison-store
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

Attendu : CI iOS verte (compilation + `SeasonStoreTests` 11/11 + toutes les suites existantes). Rien n'est encore branché : `AppStore` ne connaît pas `SeasonStore` (I1).

---

### Task I1: Intégration 1 — navigation à trois onglets, `AppStore.season`, ligues suivies, composants communs, coquilles

**Branche :** `nuit2/appli-i1-integration` (sauf l'étape 0, poussée par le contrôleur sur `main` au début du lot) · **Vague :** 3, après A1 · **Dépendances :** A1, L5, L6 fusionnées.

**Files:**
- Modify (étape 0, sur `main`) : `.github/workflows/ios.yml`
- Create: `App/Season/SeasonFormat.swift`, `Shared/DA/SoraStyle.swift`, `App/DA/SeasonParts.swift`, `App/Navigation/Routes.swift`, `App/Store/AppStore+Season.swift`, coquilles `App/Home/HomeView.swift`, `App/TeamPage/TeamPageView.swift`, `App/PlayerPage/PlayerPageView.swift`, `App/Standings/StandingsView.swift`, `App/Calendar/SeasonCalendarView.swift`, `App/Duel/DuelView.swift`, `Resources/Assets.xcassets/icon-{home,calendar,standings,versus,player}.imageset/{Contents.json,icon-*.svg}`
- Modify: `Shared/DA/Icon.swift`, `Tests/FailleTests/ApercuTests.swift`, `Shared/Preview/SampleData.swift`, `App/Store/AppStore.swift`, `App/RootView.swift`
- Test: `Tests/FailleTests/SeasonFormatTests.swift`, `Tests/FailleTests/SeasonIntegrationTests.swift`

**Interfaces:**
- Consumes : A1 (`SeasonStore`, `SeasonContext`, `SeasonPlanning`, `SeasonPreview`, `SeasonSamples`) ; L5 (`FollowedLeague`, `FollowList.leagues`, `follow(league:)`, `unfollowLeague(id:)`, `containsLeague(id:)`, `setNotifyStarts(_:leagueId:)`, `AppSettings.onboardingDone`, `.revealedStandingIds`) ; L6 (`StandingsMasking.isMasked(_:tournamentId:follows:revealed:revealedStandings:)`) ; L3 `FormPip` ; L2 `PlayerName.display` ; existants `DDragonIcon`, `DataDragonStore.knownVersion/version(forPatch:)`, `Presenter`, `TeamBadge`, `Chip`, `NoteCard`, `ScreenHeader`, `Format.score/matchDate`, `MatchRoute`, `zoomTransition`, `Motion`, `@ReduceMotion`, `SkeletonBlock`.
- Produces (contrat pour A2-A9, I2, P2) :
  - Routes : `TeamRoute(teamId:)`, `PlayerRoute(playerId:)`, `StandingsRoute(tournamentId:)`, `CalendarRoute()`, `enum DuelSide { player(String), team(String) }`, `DuelRoute(left:right:)` ; `RootNavigation.deepLink(matchId:) -> (tab: AppTab, route: MatchRoute)` ; `View.failleDestinations(zoom:)` ; `AppTab.home`.
  - Coquilles (init figés) : `HomeView(zoom: Namespace.ID? = nil, openTeams: @escaping () -> Void)`, `TeamPageView(teamId:)`, `PlayerPageView(playerId:)`, `StandingsView(tournamentId:)`, `SeasonCalendarView()`, `DuelView(left: DuelSide, right: DuelSide)`.
  - `AppStore` : `let season: SeasonStore` ; `toggleFollowLeague(_ league: League)`, `followAllTeams(in league: League)`, `setLeagueNotifications(_ on: Bool, leagueId: String)`, `revealStandings(tournamentId: String)`, `completeOnboarding()` ; (extension) `seasonContext()`, `seasonLoop()`, `seasonMasked`, `isStandingsMasked(tournamentId:)`, `maskedStandingIds`, `maskedLatestTeamIds`, `showsOnboarding`, `team(id:)`, `teamName(id:)`, `teamCode(id:)`, `playerName(id:raw:teamId:)`, `league(id:)`, `currentTournamentId(leagueId:now:)`, `openTeamPage(_:)`, `closeTeamPage(_:)`, `static seasonPreview(_:)`.
  - `PreviewData.season: SeasonSample` (`.none` par défaut), `enum SeasonSample { none, standard, collecting, loading }`, statiques `.withSeason`, `.withSeasonCollecting`, `.withSeasonLoading`, `.withSeasonNoFollows` ; effectifs de KC, G2, T1 dans `SampleData.catalog`.
  - Composants : `\.seasonNow`, `ChampionIcon(champion:size:)`, `FormPips(form:)`, `StatTile(value:label:footnote:)`, `MatchLine(event:showsDay:onReveal:)`, `TeamLink(teamId:label:)`, `TeamTapZones(teams:)`, `SeasonSkeletonCard(lines:label:)`, `SeasonComingSoon()` ; `SeasonFormat` (`decimal`, `integer`, `percent`, `duration`, `record`, `signed`, `kda`, `missing`), `SeasonNames` (`player`, `role`) ; `SoraStyle`, `View.sora(_:)`.
  - `Icon.home`, `.calendar`, `.standings`, `.versus`, `.player` (`Icon.allCases.count` = 28).

- [ ] **Step 0 (contrôleur, sur `main`, au début du lot) : CI des branches `nuit2/**`**

Dans `.github/workflows/ios.yml`, remplacer :

```yaml
    # main, et les branches de travail des lots menés en parallèle (fin/…, fonc/…) : elles ont leur CI iOS avant fusion.
    branches: [main, 'fin/**', 'fonc/**']
```

par :

```yaml
    # main, et les branches de travail des lots menés en parallèle (fin/…, fonc/…, nuit2/…) : elles ont leur CI iOS avant
    # fusion.
    branches: [main, 'fin/**', 'fonc/**', 'nuit2/**']
```

```bash
git add .github/workflows/ios.yml
git commit -m "ci(ios): CI des branches nuit2/** (lot saison)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

(`concurrency` est déjà en place : seul le dernier commit d'une branche est vérifié.)

- [ ] **Step 1: Relire le contrat L5 / L6 et l'état d'A1**

```bash
git pull --ff-only origin main
grep -n "leagues\|func.*League\|onboardingDone\|revealedStandingIds" LoLKit/Sources/LoLKit/Follow/FollowList.swift LoLKit/Sources/LoLKit/Storage/AppSettings.swift
grep -rn "enum StandingsMasking" -A12 LoLKit/Sources/LoLKit/Season/
ls App/Season/
```

Les noms du contrat sont ceux de `4e37f00` ; adapter les appels des étapes 10 et 11 s'ils ont bougé.

- [ ] **Step 2: Écrire les tests**

Créer `Tests/FailleTests/SeasonFormatTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

private let fr = Locale(identifier: "fr_FR")

/// Espaces insécables de la langue (U+00A0 ou U+202F selon la version d'ICU) ramenées à une espace simple.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

struct SeasonFormatTests {
    @Test func numbersFollowTheSpecDisplayRules() {
        #expect(SeasonFormat.decimal(3.4285, locale: fr) == "3,4")
        #expect(SeasonFormat.integer(531.2, locale: fr) == "531")
        #expect(plain(SeasonFormat.percent(0.2278, locale: fr)) == "23 %")
        #expect(SeasonFormat.percent(nil, locale: fr) == "—")
        #expect(SeasonFormat.duration(seconds: 2031.036) == "33:51")
        #expect(SeasonFormat.duration(seconds: 3723) == "1:02:03")
        #expect(SeasonFormat.signed(228, locale: fr) == "+228")
        #expect(plain(SeasonFormat.signed(-1450, locale: fr)) == "\u{2212}1 450")
        #expect(SeasonFormat.signed(nil) == "—")
        #expect(SeasonFormat.record(9, 0) == "9-0")
        #expect(SeasonFormat.kda(kills: 4, deaths: 6, assists: 4) == "4/6/4")
        #expect(SeasonNames.role("bottom") == "ADC")
        #expect(SeasonNames.role(nil) == "Remplaçant")
    }
}
```

Créer `Tests/FailleTests/SeasonIntegrationTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Intégration 1 (spec saison §2.1, §3.5, §3.7, §3.8) : lien profond inchangé, saison d'exemple branchée, ligues suivies,
/// révélation d'un classement, onboarding d'un utilisateur existant, Dynamic Type.
@MainActor
struct SeasonIntegrationTests {
    /// Le lien profond d'une notification ouvre toujours le Détail dans l'onglet Matchs, sans source de zoom.
    @Test func notificationDeepLinkStillOpensTheDetailInMatches() {
        let link = RootNavigation.deepLink(matchId: "m1")
        #expect(link.tab == .matches)
        #expect(link.route == MatchRoute(matchId: "m1"))
        #expect(link.route.sourceID == nil)
    }

    @Test func previewStoresCarryTheSeasonSample() {
        #expect(AppStore(preview: .standard).season.matches.isEmpty)   // planches existantes inchangées
        let store = AppStore(preview: .withSeason)
        #expect(!store.season.matches.isEmpty)
        #expect(store.season.isPreview)
        // T1 est en anti-spoiler dans les aperçus : ses trois matchs d'exemple sont masqués.
        #expect(store.seasonMasked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
        #expect(AppStore(preview: .withSeasonLoading).season.isLoaded == false)
    }

    /// Effectifs du catalogue d'exemple = joueurs des games d'exemple (mêmes ids).
    @Test func sampleRostersMatchTheSampleGames() {
        let ids = Set(SeasonSamples.games.flatMap { $0.blue.players + $0.red.players }.map(\.playerId))
        let roster = SampleData.catalog.flatMap { $0.players ?? [] }
        #expect(roster.count == 15)
        #expect(roster.allSatisfy { ids.contains($0.id) })
    }

    @Test func standingsAreMaskedUntilRevealed() {
        let store = AppStore(preview: .withSeason)
        // Le Mondial contient des matchs masqués de T1 (anti-spoiler) ; la LEC non.
        #expect(store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.lecSplit3.id))
        store.revealStandings(tournamentId: SeasonSamples.worlds.id)
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        // Révéler le classement ne révèle aucun match.
        #expect(store.seasonMasked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
    }

    @Test func followingALeagueIsSavedAndWakesTheCollection() throws {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: StubTransport(), files: files)
        let lec = League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1)
        store.toggleFollowLeague(lec)
        #expect(store.follows.leagues.map(\.id) == [lec.id])
        let saved = try #require(files.load(FollowList.self, from: .follows))
        #expect(saved.leagues.map(\.slug) == ["lec"])
        store.toggleFollowLeague(lec)
        #expect(store.follows.leagues.isEmpty)
        store.endScene()
    }

    /// Un utilisateur qui suit déjà des équipes ne voit pas l'onboarding ; un nouveau, si.
    @Test func existingUsersSkipTheOnboarding() {
        let existing = TemporaryFiles.store()
        existing.save(SampleData.follows, to: .follows)
        let store = AppStore(transport: StubTransport(), files: existing)
        #expect(store.settings.onboardingDone)
        #expect(!store.showsOnboarding)
        #expect(existing.load(AppSettings.self, from: .settings)?.onboardingDone == true)
        let fresh = AppStore(transport: StubTransport(), files: TemporaryFiles.store())
        #expect(fresh.showsOnboarding)
        fresh.completeOnboarding()
        #expect(!fresh.showsOnboarding)
    }

    /// Dynamic Type : taille de `Typo` à la taille par défaut, plus grande au-delà, plafonnée à `accessibility2`.
    @Test func soraStylesScaleWithDynamicTypeUpToACap() {
        #expect(SoraStyle.body.pointSize(for: .large) == 15)
        #expect(SoraStyle.title.pointSize(for: .large) == 32)
        #expect(SoraStyle.body.pointSize(for: .accessibility1) > 15)
        #expect(SoraStyle.body.pointSize(for: .accessibility5) == SoraStyle.body.pointSize(for: .accessibility2))
    }

    @Test func seasonPartsSpeakTheForm() {
        let form = [FormPip(matchId: "a", outcome: .win), FormPip(matchId: "b", outcome: .loss),
                    FormPip(matchId: "c", outcome: .masked)]
        #expect(FormPips.spoken(form) == "Victoire, Défaite, Masqué")
    }
}
```

- [ ] **Step 3: Écrire les chiffres et les noms de la saison**

Créer `App/Season/SeasonFormat.swift` :

```swift
import Foundation
import LoLKit

/// Chiffres des écrans de saison (spec saison §1.5, « Affichage ») : KDA et CS/min à 1 décimale, gold/min entier, parts
/// en % entier, durée « 35:10 », bilans « 9-0 ». Séparateur décimal de la langue de l'appareil (« 3,4 » en français).
/// Une valeur absente s'écrit « — » (jamais de chiffre inventé).
enum SeasonFormat {
    static let missing = "—"

    static func decimal(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    static func integer(_ value: Double, locale: Locale = .current) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    /// Part (0…1) en pourcentage entier : « 23 % » (espace de la langue).
    static func percent(_ share: Double?, locale: Locale = .current) -> String {
        guard let share else { return missing }
        return (share.rounded(toPlaces: 2)).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// « 35:10 » ; une heure ou plus : « 1:02:03 ».
    static func duration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// Bilan « 9-0 ».
    static func record(_ wins: Int, _ losses: Int) -> String {
        "\(wins)-\(losses)"
    }

    /// Écart signé « +228 » / « −1 450 » (signe moins typographique) ; nil → « — ».
    static func signed(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return missing }
        let magnitude = integer(abs(value), locale: locale)
        return value < 0 ? "\u{2212}\(magnitude)" : "+\(magnitude)"
    }

    /// K/D/A « 4/6/4 ».
    static func kda(kills: Int, deaths: Int, assists: Int) -> String {
        "\(kills)/\(deaths)/\(assists)"
    }
}

/// Noms affichés des écrans de saison (spec saison §1.5).
enum SeasonNames {
    /// Joueur : pseudo du catalogue (`Team.players`) s'il est connu, sinon le pseudo du flux sans le préfixe du code de son
    /// équipe (« KC Canna » → « Canna », `PlayerName.display`).
    static func player(_ playerId: String, raw: String, teamCode: String?, catalog: [Team]) -> String {
        for team in catalog {
            if let player = team.players?.first(where: { $0.id == playerId }) { return player.summonerName }
        }
        return PlayerName.display(raw, teamCode: teamCode)
    }

    /// Poste : « top » → « Top », « bottom » → « ADC »… ; inconnu → « Remplaçant ».
    static func role(_ role: String?) -> String {
        switch role {
        case "top": String(localized: "Top")
        case "jungle": String(localized: "Jungle")
        case "mid": String(localized: "Mid")
        case "bottom": String(localized: "ADC")
        case "support": String(localized: "Support")
        default: String(localized: "Remplaçant")
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
```

- [ ] **Step 4: Écrire `.sora(_:)` (Dynamic Type)**

Créer `Shared/DA/SoraStyle.swift` :

```swift
import SwiftUI
import UIKit

/// Styles de texte Sora qui suivent la taille du texte de l'appareil (spec saison §3.8, Dynamic Type) : la taille de
/// `Typo` est mise à l'échelle par `UIFontMetrics` du style iOS correspondant (titres ↔ `.largeTitle`, corps ↔ `.body`,
/// secondaire ↔ `.footnote`, étiquettes ↔ `.caption2`), plafonnée à `.accessibility2` (au-delà, les cartes débordent).
/// Nouveaux écrans : `.sora(.body)` plutôt que `.font(Typo.body)` ; les tracking (`Typo.titleTracking`,
/// `Typo.labelTracking`) restent posés à part. Widgets et Live Activity gardent `Typo` (tailles fixes).
enum SoraStyle: CaseIterable, Sendable {
    case title, scoreLarge, score, headline, body, bodyMedium, stat, secondary, secondaryMedium, label, chip

    /// Taille de `Typo` à la taille de texte par défaut (`.large`).
    var size: CGFloat {
        switch self {
        case .title: 32
        case .scoreLarge: 28
        case .score: 22
        case .headline, .body, .bodyMedium, .stat: 15
        case .secondary, .secondaryMedium: 12
        case .label: 11
        case .chip: 11.5
        }
    }

    var weight: Sora.Weight {
        switch self {
        case .title, .scoreLarge, .score, .stat: .bold
        case .headline, .label, .chip: .semibold
        case .bodyMedium, .secondaryMedium: .medium
        case .body, .secondary: .regular
        }
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .title, .scoreLarge, .score: .largeTitle
        case .headline, .body, .bodyMedium, .stat: .body
        case .secondary, .secondaryMedium: .footnote
        case .label, .chip: .caption2
        }
    }

    /// Au-delà, le texte ne grandit plus.
    static let largestSize: DynamicTypeSize = .accessibility2

    func pointSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let capped = min(dynamicTypeSize, Self.largestSize)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(capped))
        return UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size, compatibleWith: traits)
    }
}

private struct SoraFont: ViewModifier {
    let style: SoraStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(Sora.font(style.pointSize(for: dynamicTypeSize), style.weight))
    }
}

extension View {
    /// Police Sora du style, à la taille de texte de l'appareil (plafonnée).
    func sora(_ style: SoraStyle) -> some View {
        modifier(SoraFont(style: style))
    }
}
```

Repli si `UIContentSizeCategory(_ dynamicTypeSize:)` ne compile pas : un `switch` sur les 12 cas de `DynamicTypeSize` vers `.extraSmall … .accessibilityExtraExtraLarge` (même correspondance, dans le même ordre).

- [ ] **Step 5: Ajouter les cinq icônes**

Dans `Shared/DA/Icon.swift`, remplacer :

```swift
    /// « Regarder » / « Revoir » (spec fonctionnalités §1) : écran avec un triangle de lecture.
    case play
```

par :

```swift
    /// « Regarder » / « Revoir » (spec fonctionnalités §1) : écran avec un triangle de lecture.
    case play
    /// Saison (spec saison §2.1) : onglet Accueil, calendrier, classements, duels, joueur.
    case home, calendar, standings, versus, player
```

Dans `Tests/FailleTests/ApercuTests.swift`, remplacer `        #expect(Icon.allCases.count == 23)` par `        #expect(Icon.allCases.count == 28)`.

Créer, pour chacune des cinq icônes, `Resources/Assets.xcassets/icon-<nom>.imageset/Contents.json` (copie exacte de celui d'`icon-play.imageset`, en remplaçant `"icon-play.svg"` par `"icon-<nom>.svg"` ; `"template-rendering-intent" : "template"` et `"preserves-vector-representation" : true` gardés) et `icon-<nom>.svg` (trait 1,8, grille 24, comme les autres) :

`icon-home.svg` :
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z"/></svg>
```

`icon-calendar.svg` :
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><rect fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" x="3.5" y="5" width="17" height="15.5" rx="3"/><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M3.5 10h17M8 3v4M16 3v4"/></svg>
```

`icon-standings.svg` :
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M3 20h18M6 20v-7M12 20V5M18 20v-10"/></svg>
```

`icon-versus.svg` :
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M4 5l5 7-5 7M20 5l-5 7 5 7"/></svg>
```

`icon-player.svg` :
```xml
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><circle fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" cx="12" cy="8" r="4"/><path fill="none" stroke="#000000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" d="M4.5 20c1.5-3.5 4.3-5 7.5-5s6 1.5 7.5 5"/></svg>
```

- [ ] **Step 6: Écrire les composants communs des écrans de saison**

Créer `App/DA/SeasonParts.swift` :

```swift
import LoLKit
import SwiftUI

extension EnvironmentValues {
    /// « Maintenant » des écrans de saison ; nil : l'heure réelle. Les planches PNG le fixent (15/10/2026 15:05 UTC).
    @Entry var seasonNow: Date? = nil
}

/// Icône d'un champion (`championId` du flux, ex. « KSante ») : Data Dragon à la dernière version connue, vignette de repli
/// (initiales) sinon. La version est demandée une fois (`DataDragonStore.version(forPatch: nil)`, liste gardée 24 h) ;
/// toutes les icônes se mettent à jour quand elle arrive. Aperçus : repli, aucune requête.
struct ChampionIcon: View {
    let champion: String
    var size: CGFloat = 28
    @Environment(\.dataDragon) private var dataDragon

    var body: some View {
        let version = dataDragon?.knownVersion(forPatch: nil)
        ZStack {
            DDragonIcon(url: version.map { DataDragon.championImage(version: $0, championId: champion) }, size: size,
                        fallback: DDragonIcon.initials(champion))
        }
        .task {
            if version == nil { _ = await dataDragon?.version(forPatch: nil) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: champion))
    }
}

/// Forme sur 5 matchs (spec saison §3.1) : pastille pleine (victoire), creuse (défaite), œil barré (masqué), dans
/// l'ordre de `TeamSeason.form` (du plus ancien au plus récent : la plus récente à droite). Lue « Forme : Victoire,
/// Défaite, Masqué ».
struct FormPips: View {
    let form: [FormPip]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(form.enumerated()), id: \.offset) { _, pip in
                ZStack {
                    Circle().fill(fill(pip.outcome))
                    Circle().strokeBorder(pip.outcome == .win ? Palette.accent : Palette.glassBorder, lineWidth: 1)
                    if pip.outcome == .masked {
                        IconView(icon: .eyeOff, size: 8).foregroundStyle(Palette.secondary)
                    }
                }
                .frame(width: 14, height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Forme : \(Self.spoken(form))"))
    }

    private func fill(_ outcome: FormPip.Outcome) -> Color {
        switch outcome {
        case .win: Palette.accent
        case .loss: Color.white.opacity(0.08)
        case .masked: Color.clear
        }
    }

    static func spoken(_ form: [FormPip]) -> String {
        form.map { pip in
            switch pip.outcome {
            case .win: String(localized: "Victoire")
            case .loss: String(localized: "Défaite")
            case .masked: String(localized: "Masqué")
            }
        }.joined(separator: ", ")
    }
}

/// Une stat moyenne : grand chiffre, libellé dessous, précision optionnelle (« sur 12 games »). Lue d'un bloc.
struct StatTile: View {
    let value: String
    let label: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .sora(.stat)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(label)
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
            if let footnote {
                Text(footnote)
                    .sora(.label)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Ligne de match des écrans de saison (Accueil, calendrier, page d'équipe, ligues). Anti-spoiler par `Presenter.scoreLine`
/// (`store.scoreLine`) : à venir → l'heure ; en direct → « En direct » (+ score s'il n'est pas masqué ; icône fixe, aucune
/// pulsation dans une liste) ; terminé → le score, ou « Terminé · toucher pour révéler » si masqué. Une ligne masquée
/// terminée avec `onReveal` est tout entière le bouton de révélation ; toute autre ligne est un lien vers le Détail.
struct MatchLine: View {
    @Environment(AppStore.self) private var store
    let event: MatchEvent
    /// Afficher le jour en plus de l'heure (listes sur plusieurs jours).
    var showsDay = false
    var onReveal: ((String) -> Void)? = nil

    var body: some View {
        let line = store.scoreLine(event)
        if line.isMasked, event.state == .completed, let onReveal {
            Button { onReveal(event.id) } label: { row(line) }
                .buttonStyle(.pressable)
                .accessibilityHint(Text("Révèle le score"))
        } else {
            NavigationLink(value: MatchRoute(matchId: event.id)) { row(line) }
                .buttonStyle(.pressable)
        }
    }

    private func row(_ line: ScoreLine) -> some View {
        let teams = event.match.teams
        return HStack(spacing: 8) {
            if let left = teams.first { side(left) }
            Spacer(minLength: 6)
            status(line)
            Spacer(minLength: 6)
            if teams.count > 1 { side(teams[1], trailing: true) }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(event, line: line)))
    }

    private func side(_ team: MatchTeam, trailing: Bool = false) -> some View {
        HStack(spacing: 6) {
            if trailing { code(team) }
            TeamBadge(code: team.code, logoFile: store.logoFile(for: team.image), tint: store.tint(for: team), size: 26)
            if !trailing { code(team) }
        }
    }

    private func code(_ team: MatchTeam) -> some View {
        Text(team.code)
            .sora(.headline)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
    }

    @ViewBuilder private func status(_ line: ScoreLine) -> some View {
        switch event.state {
        case .inProgress:
            HStack(spacing: 5) {
                IconView(icon: .live, size: 11)
                if let score = line.score {
                    Text(Format.score(score)).sora(.stat).monospacedDigit()
                } else {
                    Text("En direct").sora(.chip)
                }
            }
            .foregroundStyle(Palette.text)
        case .completed:
            if let score = line.score {
                Text(Format.score(score))
                    .sora(.stat)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
            } else {
                HStack(spacing: 4) {
                    IconView(icon: .eyeOff, size: 11)
                    Text("Terminé")
                    if onReveal != nil {
                        Text("· toucher pour révéler").foregroundStyle(Palette.accent)
                    }
                }
                .sora(.secondaryMedium)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        case .unstarted, .unknown:
            Text(showsDay ? Format.matchDate(event.startTime)
                          : event.startTime.formatted(date: .omitted, time: .shortened))
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
        }
    }

    /// « Karmine Corp 2, G2 Esports 1 » ; masqué : « Karmine Corp contre G2 Esports, score masqué » ; à venir :
    /// « Karmine Corp contre G2 Esports, jeu. 16 oct. · 11:00 ».
    static func spoken(_ event: MatchEvent, line: ScoreLine) -> String {
        let names = event.match.teams.map(\.name)
        guard names.count == 2 else { return names.joined(separator: ", ") }
        if let score = line.score, score.count == 2 {
            return String(localized: "\(names[0]) \(score[0]), \(names[1]) \(score[1])")
        }
        switch event.state {
        case .completed, .inProgress:
            return String(localized: "\(names[0]) contre \(names[1]), score masqué")
        case .unstarted, .unknown:
            return String(localized: "\(names[0]) contre \(names[1]), \(Format.matchDate(event.startTime))")
        }
    }
}

/// Lien vers la page d'une équipe (spec saison §2.1 : toucher une équipe partout) ; sans id : le contenu seul.
struct TeamLink<Label: View>: View {
    let teamId: String?
    @ViewBuilder var label: Label

    var body: some View {
        if let teamId {
            NavigationLink(value: TeamRoute(teamId: teamId)) {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        } else {
            label
        }
    }
}

/// Deux zones de toucher transparentes à poser en `overlay` sur un `ScoreRow` : le logo et le code de chaque équipe ouvrent
/// sa page ; le score, au centre, reste inerte. Une équipe sans id (calendrier) ou « TBD » n'a pas de zone.
struct TeamTapZones: View {
    let teams: [MatchTeam]

    var body: some View {
        HStack(spacing: 0) {
            zone(teams.first)
            Spacer(minLength: 96)
            zone(teams.count > 1 ? teams[1] : nil)
        }
    }

    @ViewBuilder private func zone(_ team: MatchTeam?) -> some View {
        if let team, let id = team.id, !team.isPlaceholder {
            NavigationLink(value: TeamRoute(teamId: id)) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Page de \(team.name)"))
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

/// Squelette d'un bloc de saison : un titre et `lines` lignes, au gabarit d'une carte de verre (spec finitions §10).
struct SeasonSkeletonCard: View {
    var lines = 3
    /// Libellé VoiceOver (« Stats en chargement »), déjà localisé par l'appelant.
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 110, height: 11)
            ForEach(0..<lines, id: \.self) { _ in
                SkeletonBlock(height: 14)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }
}

/// État d'une coquille d'écran pas encore livrée (coupe du lot) : jamais un écran cassé.
struct SeasonComingSoon: View {
    var body: some View {
        ScrollView {
            NoteCard(icon: .clock, text: String(localized: "Bientôt disponible"))
                .padding(.horizontal, 16)
                .padding(.top, 16)
        }
        .abyssBackground()
    }
}
```

- [ ] **Step 7: Écrire les routes et les destinations**

Créer `App/Navigation/Routes.swift` :

```swift
import SwiftUI

/// Page d'une équipe (spec saison §3.1).
struct TeamRoute: Hashable, Sendable {
    let teamId: String
}

/// Page d'un joueur (spec saison §3.4), par `esportsPlayerId`.
struct PlayerRoute: Hashable, Sendable {
    let playerId: String
}

/// Classements et tableaux d'un tournoi (spec saison §3.5).
struct StandingsRoute: Hashable, Sendable {
    let tournamentId: String
}

/// Calendrier complet (spec saison §3.2).
struct CalendarRoute: Hashable, Sendable {}

/// Un côté d'un duel choisi librement (spec saison §3.3).
enum DuelSide: Hashable, Sendable {
    case player(String)
    case team(String)
}

/// Duel de deux joueurs ou de deux équipes (spec saison §3.3).
struct DuelRoute: Hashable, Sendable {
    let left: DuelSide
    let right: DuelSide
}

/// Navigation de la racine.
enum RootNavigation {
    /// Notification touchée (spec fonctionnalités §2, inchangé) : onglet Matchs, Détail du match par-dessus la liste
    /// (transition standard : aucune ligne de carte n'en est la source).
    static func deepLink(matchId: String) -> (tab: AppTab, route: MatchRoute) {
        (.matches, MatchRoute(matchId: matchId))
    }
}

/// Destinations communes aux trois onglets (spec saison §2.1) : le Détail (zoom depuis la ligne touchée, inchangé), et les
/// écrans de la saison.
private struct FailleDestinations: ViewModifier {
    let zoom: Namespace.ID
    @ReduceMotion var reduceMotion

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: MatchRoute.self) { route in
                // Sans ligne source, ou sous « Réduire les animations » : transition standard d'iOS.
                MatchDetailView(matchId: route.matchId)
                    .zoomTransition(route.sourceID, in: zoom, enabled: Motion.runs(.zoom, reduceMotion: reduceMotion))
            }
            .navigationDestination(for: TeamRoute.self) { TeamPageView(teamId: $0.teamId) }
            .navigationDestination(for: PlayerRoute.self) { PlayerPageView(playerId: $0.playerId) }
            .navigationDestination(for: StandingsRoute.self) { StandingsView(tournamentId: $0.tournamentId) }
            .navigationDestination(for: CalendarRoute.self) { _ in SeasonCalendarView() }
            .navigationDestination(for: DuelRoute.self) { DuelView(left: $0.left, right: $0.right) }
    }
}

extension View {
    /// À poser sur la racine de chaque `NavigationStack` de l'appli.
    func failleDestinations(zoom: Namespace.ID) -> some View {
        modifier(FailleDestinations(zoom: zoom))
    }
}
```

- [ ] **Step 8: Écrire les six coquilles**

Chaque coquille sera remplacée par sa tâche (A2-A7), qui garde son `init`. Créer :

`App/Home/HomeView.swift` :
```swift
import SwiftUI

/// Onglet Accueil (spec saison §2) — coquille d'I1, remplie par A3.
struct HomeView: View {
    /// Espace de noms du zoom carte → Détail (`RootView`) ; nil (aperçus Xcode) : pas de zoom.
    var zoom: Namespace.ID? = nil
    /// Aller à l'onglet Équipes (carte « Suis tes équipes »).
    let openTeams: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(String(localized: "Accueil"), subtitle: "")
                NoteCard(icon: .clock, text: String(localized: "Bientôt disponible"))
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}
```

`App/TeamPage/TeamPageView.swift` :
```swift
import SwiftUI

/// Page d'une équipe (spec saison §3.1) — coquille d'I1, remplie par A2.
struct TeamPageView: View {
    let teamId: String

    var body: some View {
        SeasonComingSoon()
    }
}
```

`App/PlayerPage/PlayerPageView.swift`, `App/Standings/StandingsView.swift`, `App/Calendar/SeasonCalendarView.swift`, `App/Duel/DuelView.swift` : même forme, avec respectivement `struct PlayerPageView: View { let playerId: String … }` (A5), `struct StandingsView: View { let tournamentId: String … }` (A6), `struct SeasonCalendarView: View { … }` sans propriété (A7), `struct DuelView: View { let left: DuelSide; let right: DuelSide … }` (A4), chacune avec son commentaire « coquille d'I1, remplie par Ax » et `var body: some View { SeasonComingSoon() }`.

- [ ] **Step 9: Données d'aperçu**

Dans `Shared/Preview/SampleData.swift`, remplacer :

```swift
    /// Matchs dont la Live Activity est à l'écran (bouton du Détail).
    var activityMatchIds: Set<String> = []
```

par :

```swift
    /// Matchs dont la Live Activity est à l'écran (bouton du Détail).
    var activityMatchIds: Set<String> = []
    /// Saison d'exemple (spec saison), traduite par `AppStore(preview:)` en `SeasonSamples` (dans l'appli) ; aucune par
    /// défaut : les planches existantes ne changent pas.
    var season: SeasonSample = .none
```

Remplacer :

```swift
    /// L'API ne répond plus : données en cache et bandeau.
    static var failing: PreviewData {
        var data = standard
        data.isFailing = true
        return data
    }
}
```

par :

```swift
    /// L'API ne répond plus : données en cache et bandeau.
    static var failing: PreviewData {
        var data = standard
        data.isFailing = true
        return data
    }

    /// Comme `standard`, avec la saison d'exemple complète (KC, GEN ; T1 en anti-spoiler, ses matchs masqués).
    static var withSeason: PreviewData {
        var data = standard
        data.season = .standard
        return data
    }

    /// Collecte en cours : seules les games du Mondial sont lues.
    static var withSeasonCollecting: PreviewData {
        var data = standard
        data.season = .collecting
        return data
    }

    /// Disque de la saison pas encore lu : squelettes.
    static var withSeasonLoading: PreviewData {
        var data = standard
        data.season = .loading
        return data
    }

    /// Aucune équipe suivie, saison connue (Accueil « Suis tes équipes », premier lancement).
    static var withSeasonNoFollows: PreviewData {
        var data = empty
        data.season = .standard
        return data
    }
}

/// Saison d'exemple d'un `AppStore` d'aperçu (les données vivent dans l'appli : `SeasonSamples`).
enum SeasonSample: Sendable {
    case none, standard, collecting, loading
}
```

Remplacer :

```swift
        team("kc", "KC", "Karmine Corp", "LEC"),
        team("g2", "G2", "G2 Esports", "LEC"),
        team("t1", "T1", "T1", "LCK"),
```

par :

```swift
        team("kc", "KC", "Karmine Corp", "LEC", players: roster([("p-canna", "Canna", "top"), ("p-yike", "Yike", "jungle"),
                                                                 ("p-kyeahoo", "kyeahoo", "mid"),
                                                                 ("p-caliste", "Caliste", "bottom"),
                                                                 ("p-busio", "Busio", "support")])),
        team("g2", "G2", "G2 Esports", "LEC", players: roster([("p-bb", "BrokenBlade", "top"),
                                                               ("p-skewmond", "SkewMond", "jungle"),
                                                               ("p-caps", "Caps", "mid"), ("p-hans", "Hans Sama", "bottom"),
                                                               ("p-labrov", "Labrov", "support")])),
        team("t1", "T1", "T1", "LCK", players: roster([("p-doran", "Doran", "top"), ("p-oner", "Oner", "jungle"),
                                                       ("p-faker", "Faker", "mid"), ("p-gumayusi", "Gumayusi", "bottom"),
                                                       ("p-keria", "Keria", "support")])),
```

Remplacer :

```swift
    private static func team(_ id: String, _ code: String, _ name: String, _ home: String?) -> Team {
        Team(id: id, slug: id, name: name, code: code, image: nil, status: "active",
             homeLeague: home.map { Team.HomeLeague(name: $0) })
    }
```

par :

```swift
    private static func team(_ id: String, _ code: String, _ name: String, _ home: String?,
                             players: [TeamPlayer]? = nil) -> Team {
        Team(id: id, slug: id, name: name, code: code, image: nil, status: "active",
             homeLeague: home.map { Team.HomeLeague(name: $0) }, players: players)
    }

    /// Effectif d'exemple (spec saison §3.1) : mêmes ids que les games de `SeasonSamples`.
    private static func roster(_ players: [(id: String, name: String, role: String)]) -> [TeamPlayer] {
        players.map { TeamPlayer(id: $0.id, summonerName: $0.name, image: nil, role: $0.role) }
    }
```

- [ ] **Step 10: Brancher la saison dans `AppStore`**

Dans `App/Store/AppStore.swift`, remplacer :

```swift
    let timelines: TimelineStore
    let summonerSpells: SummonerSpellsStore
```

par :

```swift
    let timelines: TimelineStore
    let summonerSpells: SummonerSpellsStore
    /// Statistiques de saison (spec saison §1) : games lues, tournois, classements, et leur collecte au premier plan
    /// (`seasonLoop`). Inerte dans les aperçus.
    let season: SeasonStore
```

Remplacer :

```swift
        summonerSpells = SummonerSpellsStore(transport: transport, cache: cache)
```

par :

```swift
        summonerSpells = SummonerSpellsStore(transport: transport, cache: cache)
        season = SeasonStore(transport: transport, cache: cache)
```

Remplacer :

```swift
            self.reminderCenter = SystemReminderCenter()
        }
        loadFromDisk(files)
    }
```

par :

```swift
            self.reminderCenter = SystemReminderCenter()
        }
        loadFromDisk(files)
        markOnboardedIfExistingUser()
        // Saison : lecture du disque hors du fil principal, publiée d'un coup (spec saison §2.3).
        Task { [season] in await season.loadFromDisk() }
    }
```

Remplacer :

```swift
        summonerSpells = SummonerSpellsStore(preview: FeatureSamples.spells)
```

par :

```swift
        summonerSpells = SummonerSpellsStore(preview: FeatureSamples.spells)
        season = SeasonStore(preview: AppStore.seasonPreview(data.season))
```

Remplacer :

```swift
            group.addTask { await self.refreshLoop() }
            group.addTask { await self.colorLoop() }
```

par :

```swift
            group.addTask { await self.refreshLoop() }
            group.addTask { await self.colorLoop() }
            // Collecte des stats de saison (spec saison §1.6) : au premier plan seulement, arrêtée avec la scène.
            group.addTask { await self.seasonLoop() }
```

Remplacer :

```swift
        saveFollows()
        // Une équipe d'une autre ligue change les ligues du calendrier : la politique le voit tout de suite.
```

par :

```swift
        saveFollows()
        season.wake()
        // Une équipe d'une autre ligue change les ligues du calendrier : la politique le voit tout de suite.
```

Remplacer :

```swift
        settings.revealedMatchIds.insert(matchId)
        saveSettings()
```

par :

```swift
        settings.revealedMatchIds.insert(matchId)
        saveSettings()
        // Un match révélé devient éligible à la collecte (spec saison §1.6).
        season.wake()
```

Remplacer :

```swift
    func setMatchReminderLead(_ lead: TimeInterval) {
        syncSettingsBeforeChange()
        settings.matchReminderLead = lead
        saveSettings()
    }
```

par :

```swift
    func setMatchReminderLead(_ lead: TimeInterval) {
        syncSettingsBeforeChange()
        settings.matchReminderLead = lead
        saveSettings()
    }

    /// Suivre une ligue, ou ne plus la suivre (spec saison §3.5) : son calendrier, sa collecte (priorité 3) et, si
    /// demandé, les notifications de début de ses matchs suivent.
    func toggleFollowLeague(_ league: League) {
        syncFollowsBeforeChange()
        if follows.containsLeague(id: league.id) {
            follows.unfollowLeague(id: league.id)
        } else {
            follows.follow(league: league)
        }
        saveFollows()
        season.wake()
        runWithScene { await self.refreshDue(opening: false) }
    }

    /// « Suivre ses N équipes » (spec saison §3.5) : toutes les équipes de la ligue (`TeamDirectory`), d'un coup.
    func followAllTeams(in league: League) {
        syncFollowsBeforeChange()
        for team in teams(in: league) where !follows.contains(id: team.id) {
            follows.follow(team)
        }
        colorsDirty = true
        saveFollows()
        season.wake()
        runWithScene {
            await self.refreshDue(opening: false)
            guard !Task.isCancelled else { return }
            await self.syncLiveActivities(canStart: true)
        }
    }

    /// Notifications de début des matchs d'une ligue suivie (spec saison §3.5, désactivées par défaut).
    func setLeagueNotifications(_ on: Bool, leagueId: String) {
        syncFollowsBeforeChange()
        follows.setNotifyStarts(on, leagueId: leagueId)
        saveFollows()
    }

    /// « Classement masqué · toucher pour révéler » (spec saison §3.5) : mémorisé par tournoi ; ne révèle aucun match.
    func revealStandings(tournamentId: String) {
        syncSettingsBeforeChange()
        settings.revealedStandingIds.insert(tournamentId)
        saveSettings()
    }

    /// Fin du premier lancement (« C'est parti » ou « Passer », spec saison §3.7).
    func completeOnboarding() {
        syncSettingsBeforeChange()
        settings.onboardingDone = true
        saveSettings()
    }

    /// Un utilisateur qui suit déjà des équipes au lancement (version précédente) est marqué « fait » sans voir
    /// l'onboarding (spec saison §3.7). Jamais tant que les réglages sont illisibles (ils ne doivent pas être écrasés).
    private func markOnboardedIfExistingUser() {
        guard !settings.onboardingDone, !follows.teams.isEmpty, !settingsUnreadable else { return }
        settings.onboardingDone = true
        files?.save(settings, to: .settings)
    }
```

- [ ] **Step 11: Écrire l'extension `AppStore+Season`**

Créer `App/Store/AppStore+Season.swift` :

```swift
import Foundation
import LoLKit

/// Saison dans l'appli (spec saison §1-§3) : contexte et boucle de la collecte, masquages, noms, aperçus.
extension AppStore {
    // MARK: Collecte

    /// Ce que la collecte lit de l'appli, relu avant chaque game (spec saison §1.6).
    func seasonContext() -> SeasonContext {
        SeasonContext(follows: follows, leagues: leagues, catalog: catalog, revealed: settings.revealedMatchIds,
                      openedTeamId: season.openedTeamId, now: Date())
    }

    /// Boucle de la collecte, troisième tâche de `poll` (spec saison §1.6) : premier plan seulement, annulée avec la
    /// scène (jamais pendant un réveil d'arrière-plan : `refreshInBackground` ne l'appelle pas). Une session = une
    /// boucle : budget remis à zéro. Un tour d'attente d'abord (le premier rafraîchissement passe avant) ; puis une passe
    /// tant que l'API répond et que les ligues sont connues ; entre deux passes, 30 min ou un réveil (`season.wake()`).
    func seasonLoop() async {
        guard !season.isPreview else { return }
        await season.beginSession()
        await season.loadFromDisk()
        try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        while !Task.isCancelled {
            if !isFailing, !leagues.isEmpty {
                await season.crawl { self.seasonContext() }
            }
            guard !Task.isCancelled else { break }
            await season.waitForWake(maxSeconds: 30 * 60)
        }
    }

    /// Page d'équipe ouverte / fermée : priorité 0 de la collecte (équipe non suivie, tournoi en cours).
    func openTeamPage(_ teamId: String) {
        season.open(teamId: teamId)
    }

    func closeTeamPage(_ teamId: String) {
        season.close(teamId: teamId)
    }

    // MARK: Anti-spoiler

    /// Matchs de la saison masqués (spec saison §1.8) : à passer à toute stat de saison.
    var seasonMasked: Set<String> {
        SeasonMasking.maskedMatchIds(season.matches, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// Classement d'un tournoi masqué (spec saison §3.5, `StandingsMasking`) : une équipe suivie en anti-spoiler y figure
    /// avec un match masqué (ou un bilan que ses matchs révélés ne couvrent pas), sans révélation du classement.
    func isStandingsMasked(tournamentId: String) -> Bool {
        guard let standings = season.standings[tournamentId] else { return false }
        return StandingsMasking.isMasked(standings, tournamentId: tournamentId, follows: follows,
                                         revealed: settings.revealedMatchIds,
                                         revealedStandings: settings.revealedStandingIds)
    }

    /// Tournois dont le classement est masqué (« À ne pas rater » : leurs raisons tirées des résultats valent 0).
    var maskedStandingIds: Set<String> {
        Set(season.standings.keys.filter { isStandingsMasked(tournamentId: $0) })
    }

    /// Équipes suivies en anti-spoiler dont le dernier match est masqué (règles F1/C), sur toutes les cartes.
    var maskedLatestTeamIds: Set<String> {
        Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: settings.revealedMatchIds)
    }

    // MARK: Premier lancement

    /// Onboarding au premier lancement (spec saison §3.7) : pas fait, et rien n'est suivi.
    var showsOnboarding: Bool {
        !settings.onboardingDone && follows.teams.isEmpty && follows.leagues.isEmpty
    }

    // MARK: Noms

    func team(id: String) -> Team? {
        catalog.first { $0.id == id }
    }

    /// Nom d'une équipe : catalogue, sinon celui d'un match de la saison, sinon l'id.
    func teamName(id: String) -> String {
        if let team = team(id: id) { return team.name }
        for match in season.matches {
            if let team = match.teams.first(where: { $0.id == id }) { return team.name }
        }
        return id
    }

    func teamCode(id: String) -> String? {
        if let team = team(id: id) { return team.code }
        for match in season.matches {
            if let team = match.teams.first(where: { $0.id == id }) { return team.code }
        }
        return nil
    }

    /// Pseudo d'un joueur (spec saison §1.5) : catalogue, sinon pseudo du flux sans le code de son équipe.
    func playerName(id: String, raw: String, teamId: String?) -> String {
        SeasonNames.player(id, raw: raw, teamCode: teamId.flatMap { teamCode(id: $0) }, catalog: catalog)
    }

    func league(id: String) -> League? {
        leagues.first { $0.id == id }
    }

    /// Tournoi en cours d'une ligue (lien « Classement ») ; nil tant que ses tournois ne sont pas lus.
    func currentTournamentId(leagueId: String, now: Date = Date()) -> String? {
        SeasonPlanning.currentTournamentIds(season.tournaments, leagueIds: [leagueId], now: now).first
    }

    // MARK: Aperçus

    static func seasonPreview(_ sample: SeasonSample) -> SeasonPreview {
        switch sample {
        case .none: SeasonPreview()
        case .standard: SeasonSamples.standard
        case .collecting: SeasonSamples.collecting
        case .loading: SeasonSamples.loading
        }
    }
}
```

- [ ] **Step 12: Trois onglets, piles `NavigationPath`, destinations communes**

Dans `App/RootView.swift`, remplacer :

```swift
/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}
```

par :

```swift
/// Onglets de l'appli (spec §5, spec saison §2.1) : Accueil (par défaut), Matchs, Équipes. Barre flottante en Liquid
/// Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case home, matches, teams
}
```

Remplacer :

```swift
    /// Pile de l'onglet Matchs : toucher une notification de début de match y pousse le Détail du match (spec
    /// fonctionnalités §2).
    @State private var matchesPath: [MatchRoute] = []
```

par :

```swift
    /// Piles des onglets (spec saison §2.1). Toucher une notification de début de match pousse le Détail du match dans
    /// celle de Matchs (spec fonctionnalités §2, inchangé).
    @State private var homePath = NavigationPath()
    @State private var matchesPath = NavigationPath()
    @State private var teamsPath = NavigationPath()
```

Remplacer `    init(tab: AppTab = .matches, router: NotificationRouter? = nil) {` par `    init(tab: AppTab = .home, router: NotificationRouter? = nil) {`.

Remplacer :

```swift
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack(path: $matchesPath) {
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
```

par :

```swift
        TabView(selection: $tab) {
            Tab("Accueil", image: Icon.home.assetName, value: AppTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView(zoom: zoom, openTeams: { tab = .teams })
                        .failleDestinations(zoom: zoom)
                }
            }
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack(path: $matchesPath) {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
                        .failleDestinations(zoom: zoom)
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack(path: $teamsPath) {
                    TeamsView()
                        .failleDestinations(zoom: zoom)
                }
            }
        }
        .tint(Palette.accent)
        // Icônes de champions des écrans de saison (`ChampionIcon`) : le store Data Dragon de l'appli.
        .environment(\.dataDragon, store.dataDragon)
```

Remplacer :

```swift
        guard let matchId = router?.consume() else { return }
        tab = .matches
        matchesPath = [MatchRoute(matchId: matchId)]
```

par :

```swift
        guard let matchId = router?.consume() else { return }
        let link = RootNavigation.deepLink(matchId: matchId)
        tab = link.tab
        matchesPath = NavigationPath([link.route])
```

La propriété `@ReduceMotion var reduceMotion` de `RootView` n'est plus lue (la transition est dans `failleDestinations`) : la supprimer avec son ancre `    @ReduceMotion var reduceMotion` (unique dans le fichier).

- [ ] **Step 13: Commit, push, CI une fois**

```bash
git add App Shared Resources Tests
git commit -m "feat(app): intégration saison 1 — onglet Accueil par défaut, piles NavigationPath et destinations communes (lien profond inchangé), AppStore.season et sa collecte au premier plan, ligues suivies, révélation des classements, onboarding des utilisateurs existants, composants et coquilles des écrans, .sora, cinq icônes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-i1-integration
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

Attendu : CI verte ; `SeasonIntegrationTests`, `SeasonFormatTests`, `ApercuTests` (28 icônes), `RemindersTests` (routeur), `StoreRefreshTests` (la boucle de saison n'envoie rien avant 10 s : les tests de `poll` l'annulent avant) verts ; planches existantes non vides (`01-matchs` et `03-equipes` sont rendues avec `RootView(tab:)` explicite). Après la fusion : IPA intermédiaire (point de contrôle de la nuit).

---

### Task A2: Page équipe

**Branche :** `nuit2/appli-a2-page-equipe` · **Vague :** 4a (prioritaire) · **Dépendances :** I1, L3, L6 fusionnées.

**Files:**
- Modify: `App/TeamPage/TeamPageView.swift` (coquille d'I1 : `init(teamId:)` gardé)
- Create: `App/TeamPage/TeamPageModel.swift`, `App/TeamPage/TeamPageSections.swift`, `App/TeamPage/TeamPageSkeleton.swift`
- Test: `Tests/FailleTests/TeamPageTests.swift`, `Tests/FailleTests/TeamPageSnapshotTests.swift` (planches `26-equipe`, `26-equipe-bas`, `26b-equipe-masquee`, `26c-equipe-chargement`)

**Interfaces:**
- Consumes : I1 (`store.season`, `seasonMasked`, `isStandingsMasked`, `revealStandings`, `maskedLatestTeamIds`, `team(id:)`, `openTeamPage/closeTeamPage`, `toggleFollow`, `setSpoilerFree`, `MatchLine`, `FormPips`, `StatTile`, `ChampionIcon`, `TeamLink`, `SeasonSkeletonCard`, `\.seasonNow`, `.sora`, routes) ; A1 (`SeasonStore.scopes/teamSeason/currentTournament/matches(ofTeam:)`, `SeasonLabels`) ; LoLKit `SeasonStats.headToHead`, `TeamSeason`, `TeamAverages`, `Streak`, `FormPip`, `HeadToHead`, `StandingsTable.build` (`Content`), `TeamCards.build`, `Presenter.nextLine`, `Format.gold`.
- Produces : `TeamPageView(teamId:)` (écran), `enum UpcomingLines`, `enum StandingLine`, `enum TeamPageModel { asFollowed, upcoming, nextOpponentId, standing, roster, allMasked }`, `struct TeamPageContent` (+ `make(store:teamId:scopeIndex:now:)`).

- [ ] **Step 1: Relire le contrat (L3, L6) à la tête de la branche**

```bash
git pull --ff-only origin main
grep -n "public" LoLKit/Sources/LoLKit/Season/TeamSeason.swift LoLKit/Sources/LoLKit/Season/StandingsTable.swift | head -60
```

Relevé à `4e37f00` (le code ci-dessous y compile) : `TeamSeason.form` va du plus ancien au plus récent (la plus récente à droite, sans rien inverser), `Streak { kind, count }`, `StandingsTable.Stage.content` (`.table`, `.swiss`, `.bracket`, `.matches`), `HeadToHead.matchIds`. Adapter si cela a bougé.

- [ ] **Step 2: Écrire les tests de la logique**

Créer `Tests/FailleTests/TeamPageTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille


private func upcoming(_ id: String, _ start: String, _ a: (String, String), _ b: (String, String),
                      league: LeagueRef = SampleData.worlds) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: .unstarted, type: "match", blockName: nil, league: league,
               match: MatchInfo(id: id, teams: [MatchTeam(id: a.0, name: a.1, code: a.0.uppercased(), image: nil, result: nil),
                                                MatchTeam(id: b.0, name: b.1, code: b.0.uppercased(), image: nil, result: nil)],
                                strategy: Strategy(type: "bestOf", count: 3), games: nil),
               streams: nil)
}

private func completed(_ id: String, _ start: String, _ a: (String, String, Int), _ b: (String, String, Int)) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: .completed, type: "match", blockName: nil, league: SampleData.worlds,
               match: MatchInfo(id: id, teams: [
                   MatchTeam(id: a.0, name: a.1, code: a.0.uppercased(), image: nil,
                             result: MatchTeam.Result(outcome: a.2 > b.2 ? "win" : "loss", gameWins: a.2)),
                   MatchTeam(id: b.0, name: b.1, code: b.0.uppercased(), image: nil,
                             result: MatchTeam.Result(outcome: b.2 > a.2 ? "win" : "loss", gameWins: b.2)),
               ], strategy: Strategy(type: "bestOf", count: 3), games: nil),
               streams: nil)
}

struct TeamPageModelTests {
    private let gen = FollowedTeam(id: "gen", code: "GEN", name: "Gen.G")
    private let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)

    @Test func aSpoilerFreeTeamWithAMaskedLastMatchShowsOnlyAHiddenLine() {
        let schedule = [completed("last", "2026-10-14T10:00:00Z", ("t1", "T1", 2), ("blg", "BLG", 0)),
                        upcoming("next", "2026-10-17T12:00:00Z", ("t1", "T1"), ("hle", "HLE"))]
        let follows = FollowList(teams: [t1])
        let lines = TeamPageModel.upcoming(team: t1, schedule: schedule, live: nil, follows: follows, revealed: [],
                                           maskedLatestTeamIds: ["t1"])
        #expect(lines == .hidden)
        // Révélé : le prochain match seul (équipe en anti-spoiler).
        let revealed = TeamPageModel.upcoming(team: t1, schedule: schedule, live: nil, follows: follows, revealed: ["last"],
                                              maskedLatestTeamIds: [])
        #expect(revealed == .matches([schedule[1]]))
    }

    @Test func anOrdinaryTeamShowsUpToThreeMatchesButNeverOneAgainstAMaskedSpoilerFreeTeam() {
        let schedule = [upcoming("a", "2026-10-16T09:00:00Z", ("gen", "Gen.G"), ("fur", "FURIA")),
                        upcoming("b", "2026-10-17T12:00:00Z", ("t1", "T1"), ("gen", "Gen.G")),
                        upcoming("c", "2026-10-18T12:00:00Z", ("gen", "Gen.G"), ("hle", "HLE")),
                        upcoming("d", "2026-10-19T12:00:00Z", ("gen", "Gen.G"), ("blg", "BLG"))]
        let follows = FollowList(teams: [gen, t1])
        let lines = TeamPageModel.upcoming(team: gen, schedule: schedule, live: nil, follows: follows, revealed: [],
                                           maskedLatestTeamIds: ["t1"])
        #expect(lines == .matches([schedule[0], schedule[2], schedule[3]]))
        #expect(TeamPageModel.nextOpponentId(lines, team: gen, catalog: []) == "fur")
        // Calendrier sans id d'équipe : l'adversaire est retrouvé dans le catalogue par son nom.
        let anonymous = MatchEvent(startTime: schedule[0].startTime, state: .unstarted, type: "match", blockName: nil,
                                   league: SampleData.worlds,
                                   match: MatchInfo(id: "a", teams: [MatchTeam(id: nil, name: "Gen.G", code: "GEN", image: nil, result: nil),
                                                                     MatchTeam(id: nil, name: "FURIA", code: "FUR", image: nil, result: nil)],
                                                    strategy: nil, games: nil),
                                   streams: nil)
        #expect(TeamPageModel.nextOpponentId(.matches([anonymous]), team: gen, catalog: SampleData.catalog) == "fur")
    }

    @Test func standingLineIsMaskedRankedOrAbsent() {
        let standings = SeasonSamples.standings[SeasonSamples.lecSplit3.id]
        #expect(TeamPageModel.standing(teamId: "kc", tournamentId: "t", standings: standings, masked: false)
                == .ranked(tournamentId: "t", ordinal: 1, wins: 9, losses: 0))
        #expect(TeamPageModel.standing(teamId: "kc", tournamentId: "t", standings: standings, masked: true)
                == .masked(tournamentId: "t"))
        #expect(TeamPageModel.standing(teamId: "kc", tournamentId: "t", standings: nil, masked: false) == nil)
    }
}

/// Contenu de la page assemblé sur la saison d'exemple (T1 en anti-spoiler) : rien de ses matchs masqués.
@MainActor
struct TeamPageContentTests {
    private let now = SampleData.date("2026-10-15T15:05:00Z")

    @Test func aSpoilerFreeTeamCountsItsMaskedMatchesAndHidesItsNextOne() throws {
        let content = TeamPageContent.make(store: AppStore(preview: .withSeason), teamId: "t1", scopeIndex: 0, now: now)
        let season = try #require(content.season)
        #expect(season.maskedMatches == 3)
        #expect(season.seriesWins + season.seriesLosses == 0)
        #expect(TeamPageModel.allMasked(season))
        #expect(content.upcoming == .hidden)
        #expect(content.headToHead == nil)
    }

    @Test func scopesAndStandingOfKarmineCorp() {
        let content = TeamPageContent.make(store: AppStore(preview: .withSeason), teamId: "kc", scopeIndex: 0, now: now)
        #expect(content.scopes.map(SeasonLabels.scope) == ["Saison 2026", "Mondial", "LEC Split 3"])
        #expect(content.roster.map(\.summonerName) == ["Canna", "Yike", "kyeahoo", "Caliste", "Busio"])
        // Le classement du Mondial contient des matchs masqués de T1 : masqué, même sur la page de KC.
        #expect(content.standing == .masked(tournamentId: SeasonSamples.worlds.id))
        let lec = TeamPageContent.make(store: AppStore(preview: .withSeason), teamId: "kc", scopeIndex: 2, now: now)
        #expect(lec.scope.map(SeasonLabels.scope) == "LEC Split 3")
    }
}
```

- [ ] **Step 3: Écrire la logique sans interface**

Créer `App/TeamPage/TeamPageModel.swift` :

```swift
import Foundation
import LoLKit

/// Prochains matchs d'une page d'équipe (spec saison §3.1) : jamais lus directement dans le calendrier — le premier passe
/// par `Presenter.nextLine` (règles F1 et C), les suivants seulement si l'équipe n'est pas en anti-spoiler et qu'aucun
/// n'oppose l'équipe à une autre équipe suivie en anti-spoiler dont le dernier match est masqué.
enum UpcomingLines: Equatable, Sendable {
    /// « Prochain · masqué », et rien d'autre.
    case hidden
    case none
    case matches([MatchEvent])
}

/// Ligne « Classement » de la page d'équipe (spec saison §3.1, §3.5).
enum StandingLine: Equatable, Sendable {
    /// « Classement masqué · toucher pour révéler ».
    case masked(tournamentId: String)
    /// « 1er · 9-0 » (saison régulière classée).
    case ranked(tournamentId: String, ordinal: Int, wins: Int, losses: Int)
    /// Système suisse : « 2-1 ».
    case record(tournamentId: String, record: String)
}

/// Logique de la page d'équipe qui ne dépend pas de l'écran (testée sans interface).
enum TeamPageModel {
    /// L'équipe vue comme une équipe suivie (pour `TeamCards` / `Presenter.nextLine`) : sa fiche de suivi si elle est
    /// suivie, sinon une fiche construite depuis le catalogue (jamais enregistrée).
    static func asFollowed(_ teamId: String, follows: FollowList, catalog: [Team], fallback: MatchTeam?) -> FollowedTeam? {
        if let followed = follows.team(id: teamId) { return followed }
        if let team = catalog.first(where: { $0.id == teamId }) { return FollowedTeam(team: team) }
        guard let fallback else { return nil }
        return FollowedTeam(id: teamId, code: fallback.code, name: fallback.name, image: fallback.image)
    }

    static func upcoming(team: FollowedTeam, schedule: [MatchEvent], live: [MatchEvent]?, follows: FollowList,
                         revealed: Set<String>, maskedLatestTeamIds: Set<String>, limit: Int = 3) -> UpcomingLines {
        guard let card = TeamCards.build(follows: FollowList(teams: [team]), schedule: schedule, live: live,
                                         revealed: revealed).first else { return .none }
        switch Presenter.nextLine(for: card, follows: follows, revealed: revealed, maskedLatestTeamIds: maskedLatestTeamIds) {
        case .hidden:
            return .hidden
        case .none:
            return .none
        case let .match(next):
            // Anti-spoiler : une équipe en anti-spoiler n'annonce que son prochain match (la suite d'un tableau trahirait
            // des résultats à venir dès qu'ils tombent).
            if follows.team(id: team.id)?.spoilerFree == true { return .matches([next]) }
            let later = schedule
                .filter { event in
                    event.id != next.id && event.state == .unstarted && event.startTime >= next.startTime
                        && event.match.teams.contains { $0.isSame(as: team) }
                }
                .sorted { $0.startTime < $1.startTime }
                .filter { event in
                    revealed.contains(event.id) || !follows.followed(in: event.match.teams).contains {
                        $0.spoilerFree && $0.id != team.id && maskedLatestTeamIds.contains($0.id)
                    }
                }
            return .matches([next] + later.prefix(max(0, limit - 1)))
        }
    }

    /// Adversaire du prochain match montré (face-à-face), seulement si la ligne est un vrai match : son id dans le match
    /// (direct), sinon l'équipe du catalogue de même nom ou de même logo (le calendrier n'a pas d'id d'équipe) ; jamais
    /// « TBD ».
    static func nextOpponentId(_ lines: UpcomingLines, team: FollowedTeam, catalog: [Team]) -> String? {
        guard case let .matches(events) = lines, let next = events.first,
              let opponent = next.match.teams.first(where: { !$0.isSame(as: team) && !$0.isPlaceholder }) else { return nil }
        if let id = opponent.id { return id }
        return catalog.first { candidate in
            candidate.name.lowercased() == opponent.name.lowercased()
                || (opponent.image != nil && candidate.image == opponent.image)
        }?.id
    }

    /// Ligne de classement de l'équipe dans un tournoi : rang de la saison régulière, sinon bilan du système suisse
    /// (`StandingsTable`), sinon rien ; masquée si `masked`.
    static func standing(teamId: String, tournamentId: String, standings: Standings?, masked: Bool) -> StandingLine? {
        guard let standings else { return nil }
        if masked { return .masked(tournamentId: tournamentId) }
        for stage in StandingsTable.build(standings: standings).reversed() {
            switch stage.content {
            case let .table(rows):
                if let row = rows.first(where: { $0.team.id == teamId }) {
                    return .ranked(tournamentId: tournamentId, ordinal: row.ordinal, wins: row.wins, losses: row.losses)
                }
            case let .swiss(groups):
                if let group = groups.first(where: { $0.teams.contains { $0.id == teamId } }) {
                    return .record(tournamentId: tournamentId, record: group.record)
                }
            case .bracket, .matches:
                continue
            }
        }
        return nil
    }

    /// Effectif (spec saison §3.1) : joueurs du catalogue, dans l'ordre des postes.
    static func roster(_ team: Team?) -> [TeamPlayer] {
        let order = ["top", "jungle", "mid", "bottom", "support"]
        return (team?.players ?? []).sorted {
            (order.firstIndex(of: $0.role ?? "") ?? order.count, $0.summonerName)
                < (order.firstIndex(of: $1.role ?? "") ?? order.count, $1.summonerName)
        }
    }

    /// La saison de l'équipe n'a que des matchs masqués : « Stats masquées · 12 matchs masqués » à la place des stats.
    static func allMasked(_ season: TeamSeason) -> Bool {
        season.maskedMatches > 0 && season.seriesWins + season.seriesLosses == 0
    }
}
```

- [ ] **Step 4: Écrire les sections**

Créer `App/TeamPage/TeamPageSections.swift` :

```swift
import LoLKit
import SwiftUI

/// En-tête : logo, nom, ligue, étoile (suivre) et œil (anti-spoiler, si suivie) ; verre teinté (Vitrail) si l'équipe est
/// suivie, neutre sinon (spec saison §3.1).
struct TeamPageHeader: View {
    @Environment(AppStore.self) private var store
    let content: TeamPageContent
    let onToggleFollow: () -> Void
    let onToggleSpoiler: () -> Void

    var body: some View {
        let tint = content.followed.map { Palette.team($0.colorHex) }
        HStack(spacing: 12) {
            TeamBadge(code: content.code, logoFile: store.logoFile(for: content.image), tint: tint, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.name)
                    .sora(.title)
                    .tracking(Typo.titleTracking)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let league = content.leagueName {
                    Text(league).sora(.secondary).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            if let followed = content.followed {
                Button(action: onToggleSpoiler) {
                    IconView(icon: followed.spoilerFree ? .eyeOff : .eye, size: 20)
                        .foregroundStyle(followed.spoilerFree ? Palette.text : Palette.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(followed.spoilerFree ? Text("Afficher les scores") : Text("Masquer les scores"))
            }
            if content.catalogTeam != nil {
                Button(action: onToggleFollow) {
                    IconView(icon: content.followed == nil ? .star : .starFill, size: 20)
                        .foregroundStyle(content.followed == nil ? Palette.secondary : Palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(content.followed == nil ? Text("Suivre") : Text("Ne plus suivre"))
            }
        }
        .buttonStyle(.pressable)
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }
}

/// « Calculé sur 24 games · 7 à lire · 2 matchs masqués » (chiffres de `TeamSeason`, jamais le nombre de games d'un match
/// masqué).
struct TeamSeasonStatus: View {
    let season: TeamSeason

    var body: some View {
        Text(Self.text(season))
            .sora(.secondary)
            .foregroundStyle(Palette.secondary)
    }

    static func text(_ season: TeamSeason) -> String {
        var parts = [String(localized: "Calculé sur \(season.gamesCounted) games")]
        if season.gamesPending > 0 { parts.append(String(localized: "\(season.gamesPending) à lire")) }
        if season.gamesWithoutStats > 0 { parts.append(String(localized: "\(season.gamesWithoutStats) sans stats")) }
        if season.maskedMatches > 0 { parts.append(String(localized: "\(season.maskedMatches) matchs masqués")) }
        return parts.joined(separator: " · ")
    }
}

/// Bilan (séries et games V-D, série en cours) et forme sur 5 matchs.
struct TeamRecordCard: View {
    let season: TeamSeason

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: String(localized: "Bilan"))
            HStack(spacing: 12) {
                StatTile(value: SeasonFormat.record(season.seriesWins, season.seriesLosses),
                         label: String(localized: "Séries"))
                StatTile(value: SeasonFormat.record(season.gameWins, season.gameLosses),
                         label: String(localized: "Games"))
            }
            if let streak = season.streak, streak.count >= 2 {
                Text(Self.streakText(streak))
                    .sora(.bodyMedium)
                    .foregroundStyle(Palette.text)
            }
            if !season.form.isEmpty {
                HStack(spacing: 10) {
                    Text("Forme").sora(.secondary).foregroundStyle(Palette.secondary)
                    FormPips(form: season.form)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    static func streakText(_ streak: Streak) -> String {
        switch streak.kind {
        case .wins: String(localized: "\(streak.count) victoires d'affilée")
        case .losses: String(localized: "\(streak.count) défaites d'affilée")
        }
    }
}

/// Stats moyennes par game (spec saison §3.1) : « — » quand la valeur n'est pas lue (jamais de chiffre inventé).
struct TeamAveragesCard: View {
    let season: TeamSeason

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: String(localized: "Moyennes par game"))
            if let averages = season.averages {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(value: SeasonFormat.decimal(averages.kills), label: String(localized: "Kills"))
                        StatTile(value: SeasonFormat.decimal(averages.deaths), label: String(localized: "Morts"))
                        StatTile(value: Format.gold(Int(averages.gold.rounded())), label: String(localized: "Gold"))
                    }
                    GridRow {
                        StatTile(value: SeasonFormat.duration(seconds: averages.durationSeconds),
                                 label: String(localized: "Durée"))
                        StatTile(value: SeasonFormat.decimal(averages.towers), label: String(localized: "Tours"))
                        StatTile(value: SeasonFormat.decimal(averages.inhibitors), label: String(localized: "Inhibiteurs"))
                    }
                    GridRow {
                        StatTile(value: SeasonFormat.decimal(averages.dragons), label: String(localized: "Drakes"))
                        StatTile(value: SeasonFormat.decimal(averages.barons), label: String(localized: "Barons"))
                        StatTile(value: SeasonFormat.signed(averages.gold15Games > 0 ? averages.gold15Diff : nil),
                                 label: String(localized: "Écart de gold à 15 min"),
                                 footnote: String(localized: "sur \(averages.gold15Games) games"))
                    }
                }
                if !season.dragonTypes.isEmpty {
                    DragonTypesRow(types: season.dragonTypes)
                }
            } else {
                Text("Les stats de cette équipe arrivent")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Répartition des types de drakes : icône drake + type + nombre (« Océan × 12 »).
struct DragonTypesRow: View {
    let types: [String: Int]

    var body: some View {
        let sorted = types.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(sorted, id: \.key) { type, count in
                    Chip(muted: true) {
                        IconView(icon: .drake, size: 12)
                        Text("\(Self.name(type)) × \(count)")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(count) drakes \(Self.name(type))"))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    static func name(_ type: String) -> String {
        switch type {
        case "ocean": String(localized: "Océan")
        case "infernal": String(localized: "Infernal")
        case "mountain": String(localized: "Montagne")
        case "cloud": String(localized: "Nuage")
        case "hextech": String(localized: "Hextech")
        case "chemtech": String(localized: "Chemtech")
        case "elder": String(localized: "Ancien")
        default: type.capitalized
        }
    }
}

/// Champions les plus joués (8 au plus) : icône Data Dragon et nombre de games.
struct TeamChampionsCard: View {
    let champions: [ChampionUse]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "Champions les plus joués"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(champions.prefix(8), id: \.champion) { use in
                    VStack(spacing: 4) {
                        ChampionIcon(champion: use.champion, size: 40)
                        Text("\(use.games) games").sora(.label).foregroundStyle(Palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Prochains matchs (spec saison §3.1) : jamais lus directement (`UpcomingLines`).
struct TeamUpcomingCard: View {
    let lines: UpcomingLines

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: String(localized: "Prochains matchs"))
            switch lines {
            case .hidden:
                HStack(spacing: 6) {
                    IconView(icon: .eyeOff, size: 13)
                    Text("Prochain · masqué")
                }
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
            case .none:
                Text("Aucun match à venir dans le calendrier")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            case let .matches(events):
                ForEach(events) { event in
                    MatchLine(event: event, showsDay: true)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Effectif (catalogue `getTeams`) : poste et pseudo, toucher → page joueur. Monogramme à la place de la photo (aucune
/// image de joueur n'est téléchargée cette nuit).
struct TeamRosterCard: View {
    let players: [TeamPlayer]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: String(localized: "Effectif"))
            ForEach(players) { player in
                NavigationLink(value: PlayerRoute(playerId: player.id)) {
                    HStack(spacing: 10) {
                        Text(String(player.summonerName.prefix(2)).uppercased())
                            .sora(.label)
                            .frame(width: 34, height: 34)
                            .background(Palette.chipFill, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.summonerName).sora(.bodyMedium)
                            Text(SeasonNames.role(player.role)).sora(.secondary).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        IconView(icon: .arrow, size: 14).foregroundStyle(Palette.secondary)
                    }
                    .foregroundStyle(Palette.text)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("\(player.summonerName), \(SeasonNames.role(player.role))"))
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Face-à-face de la saison contre le prochain adversaire (matchs masqués exclus et comptés) + lien vers le duel
/// d'équipes.
struct TeamHeadToHeadCard: View {
    let teamId: String
    let opponentId: String
    let headToHead: HeadToHead
    let names: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "Face-à-face cette saison"))
            Text("\(names.0) \(headToHead.winsA) – \(headToHead.winsB) \(names.1)")
                .sora(.score)
                .monospacedDigit()
            if headToHead.maskedMatches > 0 {
                Text("\(headToHead.maskedMatches) matchs masqués")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            NavigationLink(value: DuelRoute(left: .team(teamId), right: .team(opponentId))) {
                HStack(spacing: 6) {
                    IconView(icon: .versus, size: 14)
                    Text("Comparer les équipes")
                }
                .sora(.bodyMedium)
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Ligne « Classement » du tournoi en cours (spec saison §3.5) : rang et bilan → classement complet ; masqué → « toucher
/// pour révéler » (révèle le classement, aucun match).
struct TeamStandingCard: View {
    let line: StandingLine
    let tournamentLabel: String
    let onReveal: (String) -> Void

    var body: some View {
        switch line {
        case let .masked(tournamentId):
            Button { onReveal(tournamentId) } label: {
                HStack(spacing: 6) {
                    IconView(icon: .eyeOff, size: 13)
                    Text("Classement masqué · ")
                    Text("toucher pour révéler").foregroundStyle(Palette.accent)
                }
                .sora(.secondaryMedium)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .glassCard(radius: Radius.inner, padding: 10)
        case let .ranked(tournamentId, ordinal, wins, losses):
            link(tournamentId, value: "\(Self.ordinal(ordinal)) · \(SeasonFormat.record(wins, losses))")
        case let .record(tournamentId, record):
            link(tournamentId, value: record)
        }
    }

    private func link(_ tournamentId: String, value: String) -> some View {
        NavigationLink(value: StandingsRoute(tournamentId: tournamentId)) {
            HStack {
                IconView(icon: .standings, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Classement · \(tournamentLabel)").sora(.secondary).foregroundStyle(Palette.secondary)
                    Text(value).sora(.headline)
                }
                Spacer()
                IconView(icon: .arrow, size: 14).foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    /// « 1er », « 2e » (« 1st », « 2nd » en anglais).
    static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
```

- [ ] **Step 5: Écrire les squelettes**

Créer `App/TeamPage/TeamPageSkeleton.swift` :

```swift
import SwiftUI

/// Chargement de la page d'équipe (disque de la saison pas encore lu, spec finitions §10) : le gabarit de chaque bloc.
struct TeamPageSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(width: 220, height: 12)
            SeasonSkeletonCard(lines: 2, label: String(localized: "Bilan en chargement"))
            SeasonSkeletonCard(lines: 3, label: String(localized: "Moyennes en chargement"))
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(width: 40, height: 40, radius: 9)
                }
            }
            .glassCard(radius: Radius.inner, padding: 14)
            .accessibilityHidden(true)
        }
    }
}
```

- [ ] **Step 6: Écrire l'écran**

Remplacer tout le contenu de `App/TeamPage/TeamPageView.swift` (coquille d'I1) par :

```swift
import LoLKit
import SwiftUI

/// Ce que montre la page d'une équipe, assemblé depuis les stores (spec saison §3.1).
struct TeamPageContent {
    let teamId: String
    let name: String
    let code: String
    let image: String?
    let leagueName: String?
    let catalogTeam: Team?
    let followed: FollowedTeam?
    let scopes: [SeasonScope]
    let scope: SeasonScope?
    /// nil : aucun match connu de l'équipe dans la saison (« Les stats de cette équipe arrivent »).
    let season: TeamSeason?
    let upcoming: UpcomingLines
    let roster: [TeamPlayer]
    let standing: StandingLine?
    let standingLabel: String
    let opponentId: String?
    let headToHead: HeadToHead?

    /// Anti-spoiler : stats calculées sans les matchs masqués (`seasonMasked`), prochains matchs par `nextLine`,
    /// classement masqué selon `StandingsMasking`, face-à-face seulement si le prochain match est montré.
    @MainActor
    static func make(store: AppStore, teamId: String, scopeIndex: Int, now: Date) -> TeamPageContent {
        let catalogTeam = store.team(id: teamId)
        let seasonTeam = store.season.matches(ofTeam: teamId).first?.teams.first { $0.id == teamId }
        let followed = store.follows.team(id: teamId)
        let asFollowed = TeamPageModel.asFollowed(teamId, follows: store.follows, catalog: store.catalog, fallback: seasonTeam)
        let scopes = store.season.scopes(forTeam: teamId, now: now)
        let scope = scopes.isEmpty ? nil : scopes[min(max(scopeIndex, 0), scopes.count - 1)]
        let masked = store.seasonMasked
        let season = scope.flatMap { scope in
            scope.tournamentIds.isEmpty ? nil
                : store.season.teamSeason(teamId, scope: scope, masked: masked, now: now)
        }
        let upcoming = asFollowed.map {
            TeamPageModel.upcoming(team: $0, schedule: store.schedule, live: store.live, follows: store.follows,
                                   revealed: store.settings.revealedMatchIds,
                                   maskedLatestTeamIds: store.maskedLatestTeamIds)
        } ?? .none
        let opponentId = asFollowed.flatMap { TeamPageModel.nextOpponentId(upcoming, team: $0, catalog: store.catalog) }
        let tournament = store.season.currentTournament(forTeam: teamId, now: now)
        let standing = tournament.flatMap { tournament in
            TeamPageModel.standing(teamId: teamId, tournamentId: tournament.id,
                                   standings: store.season.standings[tournament.id],
                                   masked: store.isStandingsMasked(tournamentId: tournament.id))
        }
        return TeamPageContent(
            teamId: teamId,
            name: catalogTeam?.name ?? seasonTeam?.name ?? followed?.name ?? teamId,
            code: catalogTeam?.code ?? seasonTeam?.code ?? followed?.code ?? "",
            image: catalogTeam?.image ?? seasonTeam?.image ?? followed?.image,
            leagueName: catalogTeam?.homeLeague?.name ?? followed?.homeLeagueName,
            catalogTeam: catalogTeam,
            followed: followed,
            scopes: scopes,
            scope: scope,
            season: season,
            upcoming: upcoming,
            roster: TeamPageModel.roster(catalogTeam),
            standing: standing,
            standingLabel: tournament.map(SeasonLabels.tournament) ?? "",
            opponentId: opponentId,
            headToHead: opponentId.map { SeasonStats.headToHead(teamId, $0, matches: store.season.matches, masked: masked) }
        )
    }
}

/// Page d'une équipe (spec saison §3.1) : en-tête, périmètres, bilan et forme, prochains matchs, effectif, moyennes,
/// champions, face-à-face, classement. Ouvrir la page lance la collecte priorité 0 de l'équipe (si elle n'est pas
/// suivie), la quitter l'arrête. Rien ne vient d'un match masqué ; si tous ses matchs le sont : « Stats masquées ».
struct TeamPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    let teamId: String
    @State private var scopeIndex = 0
    @State private var haptics = HapticTrigger()
    @State private var cascaded = false
    @ReduceMotion var reduceMotion

    var body: some View {
        let content = TeamPageContent.make(store: store, teamId: teamId, scopeIndex: scopeIndex, now: fixedNow ?? Date())
        let shown = cascaded || !Motion.runs(.cascade, reduceMotion: reduceMotion)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TeamPageHeader(content: content, onToggleFollow: { toggleFollow(content) },
                               onToggleSpoiler: { toggleSpoiler(content) })
                if content.scopes.count > 1 {
                    scopePills(content.scopes)
                }
                if !store.season.isLoaded {
                    TeamPageSkeleton()
                } else {
                    seasonBlocks(content)
                }
                TeamUpcomingCard(lines: content.upcoming)
                    .cascadeIn(index: 3, shown: shown)
                if !content.roster.isEmpty {
                    TeamRosterCard(players: content.roster)
                        .cascadeIn(index: 4, shown: shown)
                }
                if let season = content.season, !TeamPageModel.allMasked(season), season.averages != nil {
                    TeamAveragesCard(season: season)
                    if !season.champions.isEmpty {
                        TeamChampionsCard(champions: season.champions)
                    }
                }
                if let opponentId = content.opponentId, let headToHead = content.headToHead {
                    TeamHeadToHeadCard(teamId: teamId, opponentId: opponentId, headToHead: headToHead,
                                       names: (content.code, store.teamCode(id: opponentId) ?? opponentId))
                }
                if let standing = content.standing {
                    TeamStandingCard(line: standing, tournamentLabel: content.standingLabel, onReveal: revealStandings)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationTitle(content.name)
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
        .onAppear {
            cascaded = true
            store.openTeamPage(teamId)
        }
        .onDisappear { store.closeTeamPage(teamId) }
    }

    @ViewBuilder private func seasonBlocks(_ content: TeamPageContent) -> some View {
        if let season = content.season {
            TeamSeasonStatus(season: season)
            if TeamPageModel.allMasked(season) {
                // Ruling spec §3.1 : pas de « révéler la saison » ; la page dit seulement combien de matchs sont masqués.
                NoteCard(icon: .eyeOff, text: String(localized: "Stats masquées · \(season.maskedMatches) matchs masqués"))
            } else {
                TeamRecordCard(season: season)
            }
        } else {
            NoteCard(icon: .clock, text: String(localized: "Les stats de cette équipe arrivent"))
        }
    }

    private func scopePills(_ scopes: [SeasonScope]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(scopes.enumerated()), id: \.offset) { index, scope in
                    PillButton(selected: index == min(scopeIndex, scopes.count - 1), action: {
                        if index != scopeIndex { haptics.play(.gamePicked) }
                        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { scopeIndex = index }
                    }) {
                        Text(SeasonLabels.scope(scope))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func toggleFollow(_ content: TeamPageContent) {
        guard let team = content.catalogTeam else { return }
        haptics.play(content.followed == nil ? .follow : .unfollow)
        store.toggleFollow(team)
    }

    private func toggleSpoiler(_ content: TeamPageContent) {
        guard let followed = content.followed else { return }
        haptics.play(.spoilerToggle)
        withAnimation(Motion.fade) { store.setSpoilerFree(!followed.spoilerFree, id: followed.id) }
    }

    private func revealStandings(_ tournamentId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.revealStandings(tournamentId: tournamentId)
        }
    }
}
```

- [ ] **Step 7: Écrire les planches**

Créer `Tests/FailleTests/TeamPageSnapshotTests.swift` :

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func teamPage(_ teamId: String, _ data: PreviewData) -> some View {
        NavigationStack { TeamPageView(teamId: teamId) }
            .environment(AppStore(preview: data))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
    }

    /// Page de KC (spec saison §3.1) : bilan, forme, effectif, moyennes, champions ; classement du Mondial masqué (T1, en
    /// anti-spoiler, y figure avec des matchs masqués).
    @Test func teamPage() async throws {
        let top = try await Snapshot.write(teamPage("kc", .withSeason), named: "26-equipe")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(teamPage("kc", .withSeason).defaultScrollAnchor(.bottom), named: "26-equipe-bas")
        expectNotBlank(bottom)
    }

    /// T1 en anti-spoiler, tous ses matchs masqués : « Stats masquées · 3 matchs masqués », « Prochain · masqué ».
    @Test func teamPageMasked() async throws {
        let url = try await Snapshot.write(teamPage("t1", .withSeason), named: "26b-equipe-masquee")
        expectNotBlank(url)
    }

    /// Disque de la saison pas encore lu : squelettes.
    @Test func teamPageLoading() async throws {
        let url = try await Snapshot.write(teamPage("kc", .withSeasonLoading), named: "26c-equipe-chargement")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 8: Commit, push, CI une fois**

```bash
git add App/TeamPage Tests/FailleTests/TeamPageTests.swift Tests/FailleTests/TeamPageSnapshotTests.swift
git commit -m "feat(app): page équipe — périmètres, bilan, forme, prochains matchs (nextLine), effectif, moyennes, champions, face-à-face, classement masquable ; collecte priorité 0 à l'ouverture" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a2-page-equipe
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

Attendu : CI verte ; planches `26-*` non vides (`26b` montre « Stats masquées · 3 matchs masqués » et « Prochain · masqué » ; `26-equipe` « Classement masqué · toucher pour révéler »).

---

### Task A3: Accueil

**Branche :** `nuit2/appli-a3-accueil` · **Vague :** 4a · **Dépendances :** I1, L7, L8 fusionnées.

**Files:**
- Modify: `App/Home/HomeView.swift` (coquille d'I1 : `init(zoom:openTeams:)` gardé)
- Create: `App/Home/HomeModel.swift`, `App/Home/HomeTexts.swift`, `App/Home/HomeStore.swift`, `App/Home/MustWatchSection.swift`, `App/Home/LiveNowSection.swift`, `App/Home/WeekStripSection.swift`, `App/Home/RecentResultsSection.swift`, `App/Home/ActivitySection.swift`, `App/Home/HotPlayersSection.swift`
- Test: `Tests/FailleTests/HomeTests.swift`, `Tests/FailleTests/HomeSnapshotTests.swift` (planches `25-accueil`, `25-accueil-bas`, `25b-accueil-sans-suivi`, `25c-accueil-collecte`)

**Interfaces:**
- Consumes : L7 `HomeFeed.Input`, `HomeFeed.build`, `HomeFeed.Sections`, `HomeFeed.followedMatchIds`, `HomeFeed.topPlayers(games:masked:metric:period:now:)`, `HomeFeed.Period`, `MustWatch.rank(schedule:follows:revealed:revealedStandings:standings:seasonMatches:catalog:now:calendar:limit:)`, `MustWatchPick`, `MustWatchScore`, `MustWatchReason`, `ActivityItem`, `ActivityKind` ; L8 `WeekStrip.scrollRange`, `CalendarDay`, `DayMarker` ; L3 `PlayerMetric` (+ `value(of:)`), `PlayerSeason`, `SeasonMasking` ; I1 (`season`, `seasonMasked`, `playerName`, `teamCode`, `reveal`, `MatchLine`, `ChampionIcon`, `SeasonSkeletonCard`, `\.seasonNow`, `CalendarRoute`, `PlayerRoute`, `TeamRoute`) ; A1 `SeasonLabels.league`, `CrawlProgress` ; existants `WatchLinks.live`, `WatchButton`, `LiveIndicator`, `SpoilerPolicy`.
- Produces : `HomeView(zoom:openTeams:)` (écran) ; `struct HomeInputs`, `struct HomeContent`, `struct HotPlayersKey`, `struct HomeLiveItem`, `enum HomeModel { compute, merged, periods }` ; `extension AppStore { homeInputs(now:calendar:), mustWatchPicks(limit:now:calendar:) }`, `struct HomeKey` ; `struct MustWatchSection(picks:style:)` avec `enum MustWatchStyle { card, list }` (I2 l'utilise en tête de Matchs, `style: .list`) ; `enum HomeTexts`, `enum ActivityText`.

- [ ] **Step 1: Relire le contrat L7 / L8**

```bash
git pull --ff-only origin main
grep -rn "public" LoLKit/Sources/LoLKit/Home/ LoLKit/Sources/LoLKit/Calendar/ | grep -E "func|case|struct|enum|let|var"
```

Le code ci-dessous compile contre L8 (`4e37f00`) et contre L7 telle que l'écrit le plan LoLKit (Task L7) ; si L7 a bougé à sa fusion, adapter `HomeModel.compute`, `HomeStore` et les sections (mêmes règles).

- [ ] **Step 2: Écrire les tests de la logique**

Créer `Tests/FailleTests/HomeTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

private let fr = Locale(identifier: "fr_FR")
private let now = SampleData.date("2026-10-15T15:05:00Z")

private func paris() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    calendar.locale = fr
    return calendar
}

struct HomeModelTests {
    private func inputs(follows: FollowList, revealed: Set<String> = []) -> HomeInputs {
        let preview = SeasonSamples.standard
        let feed = HomeFeed.Input(now: now, calendar: paris(), schedule: SampleData.schedule, live: SampleData.live,
                                  follows: follows, revealed: revealed, revealedStandings: [],
                                  seasonMatches: preview.matches,
                                  games: Dictionary(uniqueKeysWithValues: preview.games.map { ($0.gameId, $0) }),
                                  standings: preview.standings, catalog: SampleData.catalog)
        return HomeInputs(feed: feed, progress: preview.progress, isLoaded: true)
    }

    @Test func liveMatchesPutFollowedTeamsFirstAndKeepMaskedOnesWithoutScore() {
        let content = HomeModel.compute(inputs(follows: SampleData.follows))
        // KC – C9 et T1 – FLY (suivis) d'abord, puis BRO – LGD (ni suivi ni international).
        #expect(content.live.map(\.id) == [SampleData.kcMatchId, SampleData.t1MatchId, SampleData.noStatsMatchId])
        #expect(content.live.map(\.masked) == [false, true, false])
        #expect(content.sections.todayCount == 2)
        #expect(content.masked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
        #expect(content.strip.count == 43)
        #expect(content.eventsByDay[paris().startOfDay(for: now)]?.count == 3)
    }

    @Test func recentResultsCoverSeventyTwoHours() {
        // 72 h avant le 15/10 15:05 : GEN – HLE (11/10) et KC – G2 (05/10) sont trop vieux.
        #expect(HomeModel.compute(inputs(follows: SampleData.follows)).sections.recentResults.isEmpty)
    }

    @Test func withoutFollowsTheHomeStillShowsTheWorlds() {
        let content = HomeModel.compute(inputs(follows: FollowList()))
        #expect(!content.hasFollows)
        #expect(Array(content.live.map(\.id).prefix(2)) == [SampleData.kcMatchId, SampleData.t1MatchId])
        #expect(content.live.allSatisfy { !$0.masked })
        #expect(content.masked.isEmpty)
    }

    @Test func hotPlayersExistForEveryPeriodAndMetric() {
        let content = HomeModel.compute(inputs(follows: SampleData.follows))
        #expect(content.hotPlayers.count == 6)
        // Saison : 5 games au moins ; aucun joueur de T1 (tous ses matchs sont masqués).
        let season = content.hotPlayers[HotPlayersKey(period: .season, metric: .kda)] ?? []
        #expect(!season.isEmpty)
        #expect(!season.contains { $0.playerId == "p-faker" })
    }
}

/// Textes de l'Accueil (spec saison §2.2, §3.6) : LoLKit donne des valeurs, l'appli formule.
struct HomeTextsTests {
    @Test func reasonsAndExplanation() {
        #expect(HomeTexts.reason(.followedTeam) == "Tes équipes")
        #expect(HomeTexts.reason(.elimination) == "Élimination en jeu")
        #expect(HomeTexts.reason(.international(slug: "worlds")) == "Mondial")
        #expect(HomeTexts.reason(.decider) == "Tout se joue")
        let pick = MustWatchPick(event: SampleData.kcLive, points: 90,
                                 reasons: [MustWatchScore(reason: .followedTeam, points: 50),
                                           MustWatchScore(reason: .elimination, points: 30),
                                           MustWatchScore(reason: .bestOf5, points: 10)])
        #expect(HomeTexts.explanation(pick) == "Tes équipes · Élimination en jeu")
    }

    @Test func subtitleCountsTodaysMatches() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = SampleData.date("2026-10-15T15:05:00Z")
        let fr = Locale(identifier: "fr_FR")
        #expect(HomeTexts.subtitle(now: now, todayCount: 3, calendar: calendar, locale: fr) == "jeudi 15 octobre · 3 matchs aujourd'hui")
        #expect(HomeTexts.subtitle(now: now, todayCount: 0, calendar: calendar, locale: fr) == "jeudi 15 octobre · aucun match aujourd'hui")
    }
}
```

- [ ] **Step 3: Écrire le calcul de l'Accueil**

Créer `App/Home/HomeModel.swift` :

```swift
import Foundation
import LoLKit

/// Ce que l'Accueil lit : l'entrée de `HomeFeed` (copie figée des stores) et l'état de la collecte, envoyés hors du fil
/// principal.
struct HomeInputs: Sendable {
    var feed: HomeFeed.Input
    var progress: CrawlProgress
    var isLoaded: Bool
}

/// Joueurs en forme : période × mesure (pilules « Semaine / Saison » × « KDA / Kills / CS/min »).
struct HotPlayersKey: Hashable, Sendable {
    let period: HomeFeed.Period
    let metric: PlayerMetric
}

/// Un match de « En direct maintenant » : masqué → « En direct » seul (ni score ni « Regarder »).
struct HomeLiveItem: Equatable, Sendable, Identifiable {
    let event: MatchEvent
    let masked: Bool
    var id: String { event.id }
}

/// Sections de l'Accueil (spec saison §2.2), calculées d'un coup.
struct HomeContent: Equatable, Sendable {
    /// « À ne pas rater » (3), direct, nombre de matchs du jour, résultats (72 h, 8), activité (6) : `HomeFeed.build`.
    var sections: HomeFeed.Sections
    var live: [HomeLiveItem]
    /// Bandeau : ± 3 semaines autour d'aujourd'hui (`WeekStrip.scrollRange`), 7 jours à l'écran.
    var strip: [CalendarDay]
    /// Matchs de chaque jour (début du jour local → matchs, par heure).
    var eventsByDay: [Date: [MatchEvent]]
    var hotPlayers: [HotPlayersKey: [PlayerSeason]]
    var masked: Set<String>
    var hasFollows: Bool
    var progress: CrawlProgress
    var isLoaded: Bool
}

/// Calcul de l'Accueil (spec saison §2.2, §2.3) : la logique est dans LoLKit (`HomeFeed`), ici l'assemblage pour l'écran.
/// Rien n'attend le réseau ; l'anti-spoiler passe par `HomeFeed` (activité, joueurs en forme, « À ne pas rater »),
/// `SpoilerPolicy` (direct) et `Presenter` (chaque ligne de match, à l'écran).
enum HomeModel {
    static let periods: [HomeFeed.Period] = [.week, .season]

    static func compute(_ inputs: HomeInputs) -> HomeContent {
        let feed = inputs.feed
        let sections = HomeFeed.build(feed)
        let masked = SeasonMasking.maskedMatchIds(feed.seasonMatches, follows: feed.follows, revealed: feed.revealed)
        let events = merged(schedule: feed.schedule, live: feed.live)
        var hot: [HotPlayersKey: [PlayerSeason]] = [:]
        for period in periods {
            for metric in PlayerMetric.allCases {
                hot[HotPlayersKey(period: period, metric: metric)] = HomeFeed.topPlayers(
                    games: feed.games, masked: masked, metric: metric, period: period, now: feed.now)
            }
        }
        return HomeContent(
            sections: sections,
            live: sections.live.map {
                HomeLiveItem(event: $0, masked: SpoilerPolicy.isMasked($0.match.teams, matchId: $0.id,
                                                                       follows: feed.follows, revealed: feed.revealed))
            },
            strip: WeekStrip.scrollRange(today: feed.now, events: events, calendar: feed.calendar,
                                         followed: HomeFeed.followedMatchIds(events, follows: feed.follows)),
            eventsByDay: Dictionary(grouping: events) { feed.calendar.startOfDay(for: $0.startTime) }
                .mapValues { $0.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) } },
            hotPlayers: hot,
            masked: masked,
            hasFollows: !feed.follows.teams.isEmpty || !feed.follows.leagues.isEmpty,
            progress: inputs.progress,
            isLoaded: inputs.isLoaded)
    }

    /// Le direct (`getLive`) fait foi pour un match qu'il connaît ; le calendrier pour le reste (même règle que les cartes).
    static func merged(schedule: [MatchEvent], live: [MatchEvent]?) -> [MatchEvent] {
        guard let live else { return schedule }
        let liveIds = Set(live.map(\.id))
        return live + schedule.filter { !liveIds.contains($0.id) }
    }
}
```

- [ ] **Step 4: Écrire les textes**

Créer `App/Home/HomeTexts.swift` :

```swift
import Foundation
import LoLKit

/// Textes de l'Accueil (spec saison §3.8 : LoLKit renvoie des valeurs, l'appli formule ; chaînes du catalogue).
enum HomeTexts {
    /// « jeudi 15 octobre · 3 matchs aujourd'hui ».
    static func subtitle(now: Date, todayCount: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        style = style.weekday(.wide).day().month(.wide)
        let day = now.formatted(style)
        let count = todayCount == 0 ? String(localized: "aucun match aujourd'hui")
                                    : String(localized: "\(todayCount) matchs aujourd'hui")
        return "\(day) · \(count)"
    }

    static func reason(_ reason: MustWatchReason) -> String {
        switch reason {
        case .followedTeam: String(localized: "Tes équipes")
        case .followedLeague: String(localized: "Ta ligue")
        case let .international(slug): SeasonLabels.league(slug: slug)
        case .elimination: String(localized: "Élimination en jeu")
        case .qualification: String(localized: "Qualification en jeu")
        case .decider: String(localized: "Tout se joue")
        case .final: String(localized: "Finale")
        case .semiFinal: String(localized: "Demi-finale")
        case .quarterFinal: String(localized: "Quart de finale")
        case .playoffs: String(localized: "Play-offs")
        case .topClash: String(localized: "Choc du haut de tableau")
        case .closeRanks: String(localized: "Duel serré")
        case .rematch: String(localized: "Revanche")
        case .derby: String(localized: "Derby")
        case .bestOf5: String(localized: "Bo5")
        case .bestOf3: String(localized: "Bo3")
        case .live: String(localized: "En direct")
        }
    }

    /// Les deux raisons qui rapportent le plus (`MustWatchPick.explanation`).
    static func explanation(_ pick: MustWatchPick) -> String {
        pick.explanation.map(reason).joined(separator: " · ")
    }

    /// Barème de « Comment c'est calculé » (spec saison §3.6) : raison et points, tels que les calcule `MustWatch`.
    static let scoring: [(reason: MustWatchReason, points: String)] = [
        (.followedTeam, String(localized: "+50 par équipe, 100 au plus")), (.followedLeague, "+25"),
        (.international(slug: "worlds"), "+20"), (.elimination, "+30"), (.qualification, "+30"), (.decider, "+40"),
        (.final, "+40"), (.semiFinal, "+30"), (.quarterFinal, "+20"), (.playoffs, "+20"), (.topClash, "+15"),
        (.closeRanks, "+10"), (.rematch, "+10"), (.derby, "+10"), (.bestOf5, "+10"), (.bestOf3, "+5"), (.live, "+15"),
    ]
}
```

- [ ] **Step 5: Écrire les lectures du store pour l'Accueil**

Créer `App/Home/HomeStore.swift` :

```swift
import Foundation
import LoLKit

extension AppStore {
    /// Ce que l'Accueil lit, figé pour un calcul hors du fil principal (spec saison §2.3) : tout vient du cache.
    func homeInputs(now: Date, calendar: Calendar = .current) -> HomeInputs {
        HomeInputs(feed: HomeFeed.Input(now: now, calendar: calendar, schedule: schedule, live: live, follows: follows,
                                        revealed: settings.revealedMatchIds,
                                        revealedStandings: settings.revealedStandingIds, seasonMatches: season.matches,
                                        games: season.games, standings: season.standings, catalog: catalog),
                   progress: season.progress, isLoaded: season.isLoaded)
    }

    /// « À ne pas rater » (spec saison §3.6) : 3 dans l'Accueil (`HomeFeed.build`), 5 au plus en tête de Matchs (I2).
    func mustWatchPicks(limit: Int, now: Date = Date(), calendar: Calendar = .current) -> [MustWatchPick] {
        MustWatch.rank(schedule: schedule, follows: follows, revealed: settings.revealedMatchIds,
                       revealedStandings: settings.revealedStandingIds, standings: season.standings,
                       seasonMatches: season.matches, catalog: catalog, now: now, calendar: calendar, limit: limit)
    }
}

/// Ce qui relance le calcul de l'Accueil (spec saison §2.3) : une game lue (`version`), les suivis, les révélations, le
/// jour, une relecture du calendrier ou du direct, la fin de la lecture du disque, l'état de la collecte, un classement
/// masqué ou révélé.
struct HomeKey: Equatable {
    let version: Int
    let follows: FollowList
    let revealed: Set<String>
    let day: Date
    let updated: Date?
    let liveIds: [String]?
    let loaded: Bool
    let running: Bool
    let revealedStandings: Set<String>
}
```

- [ ] **Step 6: Écrire les sections**

Créer `App/Home/MustWatchSection.swift` :

```swift
import LoLKit
import SwiftUI

/// Présentation de « À ne pas rater » : carte d'en-tête de l'Accueil (1 en grand + 2 lignes), ou liste en tête de Matchs.
enum MustWatchStyle {
    case card, list
}

/// « À ne pas rater » (spec saison §3.6) : matchs du jour classés par enjeu, avec la ligne d'explication et « Comment
/// c'est calculé ». Le classement (et ses exclusions anti-spoiler) vient de LoLKit ; les lignes passent par `MatchLine`.
/// Rien à proposer : la section n'existe pas.
struct MustWatchSection: View {
    @Environment(AppStore.self) private var store
    let picks: [MustWatchPick]
    var style: MustWatchStyle = .card
    @State private var showsScoring = false

    var body: some View {
        if let first = picks.first {
            let tint = first.event.match.teams.compactMap { store.tint(for: $0) }.first
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: String(localized: "À ne pas rater"), dot: tint)
                    Button { showsScoring = true } label: {
                        Text("Comment c'est calculé").sora(.label).foregroundStyle(Palette.accent)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }
                ForEach(Array(picks.enumerated()), id: \.element.event.id) { index, pick in
                    VStack(alignment: .leading, spacing: 2) {
                        MatchLine(event: pick.event, showsDay: true)
                            .scaleEffect(style == .card && index == 0 ? 1.04 : 1, anchor: .leading)
                        Text(HomeTexts.explanation(pick))
                            .sora(.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if index == 0, style == .card, picks.count > 1 {
                        Divider().overlay(Palette.glassBorder)
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(tint: style == .card ? tint : nil, radius: style == .card ? Radius.card : Radius.inner,
                       padding: style == .card ? 16 : 12)
            .sheet(isPresented: $showsScoring) { MustWatchScoringSheet() }
        }
    }
}

/// « Comment c'est calculé » : le barème de la spec §3.6 (points entiers) et la règle anti-spoiler.
struct MustWatchScoringSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Comment c'est calculé").sora(.title).tracking(Typo.titleTracking)
                Text("Chaque match du jour gagne des points ; les plus hauts passent en premier, puis par heure de début.")
                    .sora(.secondary).foregroundStyle(Palette.secondary)
                ForEach(Array(HomeTexts.scoring.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(HomeTexts.reason(row.reason)).sora(.body)
                        Spacer()
                        Text(row.points).sora(.stat).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Les raisons tirées des résultats (classement, élimination, revanche) ne comptent pas quand le classement du tournoi est masqué.")
                    .sora(.secondary).foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            .padding(20)
        }
        .abyssBackground()
        .presentationDetents([.medium, .large])
    }
}
```

Créer `App/Home/LiveNowSection.swift` :

```swift
import LoLKit
import SwiftUI

/// « En direct maintenant » (spec saison §2.2) : équipes suivies d'abord, puis ligues suivies, puis internationaux ;
/// score et « Regarder » ; masqué → « En direct » seul (ni score ni « Regarder »). Le halo « en direct » respire sur les
/// 3 premières lignes seulement (aucune animation continue au-delà). Aucun match en cours : la section n'existe pas.
struct LiveNowSection: View {
    let items: [HomeLiveItem]
    let onHaptic: (Haptic) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: String(localized: "En direct maintenant"))
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        if index < 3 {
                            LiveIndicator(size: 12)
                        } else {
                            IconView(icon: .live, size: 12)
                        }
                        MatchLine(event: item.event)
                    }
                    if let watch = WatchLinks.live(item.event.streams, inProgress: true, masked: item.masked) {
                        WatchButton(live: watch, compact: true, onHaptic: onHaptic)
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }
}
```

Créer `App/Home/WeekStripSection.swift` :

```swift
import LoLKit
import SwiftUI

/// Bandeau du calendrier (spec saison §2.2) : 7 jours à l'écran (aujourd'hui − 1 → + 5), ± 3 semaines en défilant ;
/// pastille pleine = match d'une équipe ou ligue suivie, anneau = international. Toucher un jour → ses matchs (lignes
/// anti-spoiler) ; « Tout le calendrier » → vue mois.
struct WeekStripSection: View {
    let days: [CalendarDay]
    let eventsByDay: [Date: [MatchEvent]]
    let today: Date
    let calendar: Calendar
    @Binding var selected: Date?
    let onReveal: (String) -> Void
    let onHaptic: (Haptic) -> Void

    var body: some View {
        let day = selected ?? today
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: String(localized: "Calendrier"))
                NavigationLink(value: CalendarRoute()) {
                    Text("Tout le calendrier").sora(.label).foregroundStyle(Palette.accent).frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(days) { cell in
                            dayCell(cell, selected: calendar.isDate(cell.date, inSameDayAs: day))
                                .id(cell.date)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) {
                        proxy.scrollTo(start, anchor: .leading)
                    }
                }
            }
            let events = eventsByDay[calendar.startOfDay(for: day)] ?? []
            if events.isEmpty {
                Text("Aucun match ce jour-là").sora(.secondary).foregroundStyle(Palette.secondary)
            } else {
                ForEach(events) { event in
                    MatchLine(event: event, onReveal: onReveal)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 12)
    }

    private func dayCell(_ cell: CalendarDay, selected: Bool) -> some View {
        Button {
            if !selected { onHaptic(.gamePicked) }
            self.selected = cell.date
        } label: {
            VStack(spacing: 4) {
                Text(cell.date.formatted(.dateTime.weekday(.abbreviated))).sora(.label)
                Text("\(cell.dayNumber)").sora(.headline).monospacedDigit()
                dot(cell.marker)
            }
            .foregroundStyle(selected ? Palette.abyss : Palette.text)
            .frame(width: 44, height: 64)
            .background(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(cell.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(cell.marker == .none ? Text("") : Text("Matchs suivis"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func dot(_ marker: DayMarker) -> some View {
        switch marker {
        case .followed: Circle().fill(Palette.accent).frame(width: 6, height: 6)
        case .international: Circle().strokeBorder(Palette.accent, lineWidth: 1.2).frame(width: 6, height: 6)
        case .none: Color.clear.frame(width: 6, height: 6)
        }
    }
}
```

Créer `App/Home/RecentResultsSection.swift` :

```swift
import LoLKit
import SwiftUI

/// « Résultats récents » (spec saison §2.2) : 72 h, 8 au plus, suivis d'abord ; masqué → « Terminé · toucher pour
/// révéler » (la ligne entière révèle, `store.reveal`).
struct RecentResultsSection: View {
    let events: [MatchEvent]
    let onReveal: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: String(localized: "Résultats récents"))
            if events.isEmpty {
                Text("Pas de résultat ces 3 derniers jours").sora(.secondary).foregroundStyle(Palette.secondary)
            } else {
                ForEach(events) { event in
                    MatchLine(event: event, showsDay: true, onReveal: onReveal)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 12)
    }
}
```

Créer `App/Home/ActivitySection.swift` :

```swift
import LoLKit
import SwiftUI

/// « Activité récente » (spec saison §2.4) : ce que les données disent vraiment (`HomeFeed.activity`, jamais pour un
/// match masqué). Squelette de 2 lignes pendant la lecture du disque ; vide : la section n'existe pas.
struct ActivitySection: View {
    @Environment(AppStore.self) private var store
    let items: [ActivityItem]
    let loading: Bool

    var body: some View {
        if loading {
            SeasonSkeletonCard(lines: 2, label: String(localized: "Activité en chargement"))
        } else if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: String(localized: "Activité récente"))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    row(item.kind)
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }

    @ViewBuilder private func row(_ kind: ActivityKind) -> some View {
        let text = ActivityText.text(kind, store: store)
        if let route = ActivityText.matchRoute(kind, store: store) {
            NavigationLink(value: route) { line(kind, text) }.buttonStyle(.pressable)
        } else if case let .streak(teamId, _, _) = kind {
            NavigationLink(value: TeamRoute(teamId: teamId)) { line(kind, text) }.buttonStyle(.pressable)
        } else {
            line(kind, text)
        }
    }

    private func line(_ kind: ActivityKind, _ text: String) -> some View {
        HStack(spacing: 8) {
            IconView(icon: ActivityText.icon(kind), size: 14).foregroundStyle(Palette.accent)
            Text(text).sora(.body).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Phrases de l'activité (spec saison §2.4 : LoLKit donne des valeurs, l'appli formule).
@MainActor
enum ActivityText {
    static func text(_ kind: ActivityKind, store: AppStore) -> String {
        switch kind {
        case let .justFinished(matchId):
            guard let event = store.event(id: matchId) else { return String(localized: "Un match vient de se terminer") }
            let line = store.scoreLine(event)
            let codes = line.teamCodes
            if let score = line.score, codes.count == 2, score.count == 2 {
                return String(localized: "Terminé : \(codes[0]) \(score[0]) – \(score[1]) \(codes[1])")
            }
            return String(localized: "Terminé : \(codes.joined(separator: " – "))")
        case let .streak(teamId, streakKind, count):
            let code = store.teamCode(id: teamId) ?? teamId
            return streakKind == .wins ? String(localized: "\(code) : \(count) victoires d'affilée")
                                       : String(localized: "\(code) : \(count) défaites d'affilée")
        case let .killRecord(_, teamId, kills):
            return String(localized: "Record de kills : \(store.teamCode(id: teamId) ?? teamId), \(kills) kills en une game")
        case let .bigGame(gameId, playerId, kills):
            return String(localized: "\(playerName(playerId, gameId: gameId, store: store)) : \(kills) kills en une game")
        case let .fastGame(_, seconds):
            return String(localized: "Game éclair : \(SeasonFormat.duration(seconds: Double(seconds)))")
        case let .longGame(_, seconds):
            return String(localized: "Game marathon : \(SeasonFormat.duration(seconds: Double(seconds)))")
        case let .comeback15(_, teamId, deficit):
            return String(localized: "Retournement : \(store.teamCode(id: teamId) ?? teamId) gagne après \(SeasonFormat.signed(Double(-deficit))) gold à 15 min")
        }
    }

    static func icon(_ kind: ActivityKind) -> Icon {
        switch kind {
        case .justFinished: .check
        case .streak: .trophy
        case .killRecord, .bigGame: .swords
        case .fastGame, .longGame: .clock
        case .comeback15: .gold
        }
    }

    /// Détail du match d'une game (jamais masqué : `HomeFeed.activity` l'exclut).
    static func matchRoute(_ kind: ActivityKind, store: AppStore) -> MatchRoute? {
        switch kind {
        case let .justFinished(matchId): return MatchRoute(matchId: matchId)
        case let .killRecord(gameId, _, _), let .bigGame(gameId, _, _), let .fastGame(gameId, _),
             let .longGame(gameId, _), let .comeback15(gameId, _, _):
            return store.season.games[gameId].map { MatchRoute(matchId: $0.matchId) }
        case .streak: return nil
        }
    }

    private static func playerName(_ playerId: String, gameId: String, store: AppStore) -> String {
        guard let found = store.season.games[gameId]?.player(playerId) else { return playerId }
        return store.playerName(id: playerId, raw: found.line.name, teamId: found.team.teamId)
    }
}
```

Créer `App/Home/HotPlayersSection.swift` :

```swift
import LoLKit
import SwiftUI

/// « Joueurs en forme » (spec saison §2.2) : pilules « Semaine / Saison » × « KDA / Kills / CS/min », 5 joueurs (icône
/// du champion le plus joué, pseudo, équipe, valeur) ; toucher → page joueur. Minimum 2 games (semaine) / 5 (saison),
/// matchs masqués exclus (`SeasonStats.topPlayers`). Pendant la collecte : « Les stats arrivent : 12 games lues sur
/// 40 » ; rien de lu : la section n'existe pas.
struct HotPlayersSection: View {
    @Environment(AppStore.self) private var store
    let players: [HotPlayersKey: [PlayerSeason]]
    let progress: CrawlProgress
    @Binding var key: HotPlayersKey
    let onHaptic: (Haptic) -> Void

    var body: some View {
        let list = players[key] ?? []
        if !list.isEmpty || progress.remaining > 0 || progress.read > 0 {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: String(localized: "Joueurs en forme"))
                HStack(spacing: 6) {
                    pill(String(localized: "Semaine"), selected: key.period == .week) {
                        key = HotPlayersKey(period: .week, metric: key.metric)
                    }
                    pill(String(localized: "Saison"), selected: key.period == .season) {
                        key = HotPlayersKey(period: .season, metric: key.metric)
                    }
                    Spacer(minLength: 4)
                    ForEach(PlayerMetric.allCases, id: \.self) { metric in
                        pill(Self.metricName(metric), selected: key.metric == metric) {
                            key = HotPlayersKey(period: key.period, metric: metric)
                        }
                    }
                }
                if list.isEmpty {
                    Text(progress.remaining > 0
                         ? String(localized: "Les stats arrivent : \(progress.read) games lues sur \(progress.read + progress.remaining)")
                         : String(localized: "Pas assez de games pour un classement"))
                        .sora(.secondary)
                        .foregroundStyle(Palette.secondary)
                } else {
                    ForEach(list, id: \.playerId) { player in
                        NavigationLink(value: PlayerRoute(playerId: player.playerId)) { row(player) }
                            .buttonStyle(.pressable)
                            .simultaneousGesture(TapGesture().onEnded { onHaptic(.playerPicked) })
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }

    private func row(_ player: PlayerSeason) -> some View {
        let code = store.teamCode(id: player.teamId) ?? ""
        let name = store.playerName(id: player.playerId, raw: player.name, teamId: player.teamId)
        let value = Self.value(player, metric: key.metric)
        return HStack(spacing: 10) {
            ChampionIcon(champion: player.champions.first?.champion ?? "", size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).sora(.bodyMedium)
                Text(code).sora(.secondary).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(value).sora(.stat).monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(code), \(Self.metricName(key.metric)) \(value)"))
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        PillButton(selected: selected, action: {
            if !selected { onHaptic(.gamePicked) }
            action()
        }) {
            Text(title)
        }
    }

    static func metricName(_ metric: PlayerMetric) -> String {
        switch metric {
        case .kda: String(localized: "KDA")
        case .kills: String(localized: "Kills")
        case .csPerMin: String(localized: "CS/min")
        }
    }

    /// KDA, kills moyens par game, CS/min : 1 décimale (`PlayerMetric.value(of:)`).
    static func value(_ player: PlayerSeason, metric: PlayerMetric) -> String {
        SeasonFormat.decimal(metric.value(of: player))
    }
}
```

- [ ] **Step 7: Écrire l'écran**

Remplacer tout le contenu de `App/Home/HomeView.swift` (coquille d'I1) par :

```swift
import LoLKit
import SwiftUI

/// Onglet Accueil (spec saison §2) : en-tête, « Suis tes équipes » (sans suivi), « À ne pas rater », « En direct
/// maintenant », calendrier de la semaine, résultats récents, activité, joueurs en forme. Tout vient des stores (cache
/// d'abord) ; les sections sont calculées hors du fil principal (`HomeModel.compute`), une fois par `HomeKey`. Cascade
/// d'apparition une fois ; aucune animation continue hors de la section « En direct ».
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    /// Espace de noms du zoom carte → Détail (`RootView`) ; nil (aperçus Xcode) : pas de zoom.
    var zoom: Namespace.ID? = nil
    /// Aller à l'onglet Équipes (carte « Suis tes équipes »).
    let openTeams: () -> Void
    @State private var content: HomeContent?
    @State private var selectedDay: Date?
    @State private var hotKey = HotPlayersKey(period: .week, metric: .kda)
    @State private var haptics = HapticTrigger()
    @State private var cascaded = false
    @ReduceMotion var reduceMotion

    var body: some View {
        let now = fixedNow ?? Date()
        let calendar = Calendar.current
        let shown = cascaded || !Motion.runs(.cascade, reduceMotion: reduceMotion)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(String(localized: "Accueil"),
                             subtitle: HomeTexts.subtitle(now: now, todayCount: content?.sections.todayCount ?? 0))
                if let banner = store.bannerText {
                    ErrorBanner(text: banner).transition(Motion.bannerTransition(reduceMotion: reduceMotion))
                }
                if let content {
                    sections(content, now: now, calendar: calendar, shown: shown)
                } else {
                    SeasonSkeletonCard(lines: 3, label: String(localized: "Accueil en chargement"))
                    SeasonSkeletonCard(lines: 2, label: String(localized: "Accueil en chargement"))
                }
            }
            .animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: store.isFailing)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .haptics(haptics)
        .onAppear { cascaded = true }
        .task(id: key(now: now, calendar: calendar)) {
            let inputs = store.homeInputs(now: now, calendar: calendar)
            let computed = await Task.detached(priority: .userInitiated) { HomeModel.compute(inputs) }.value
            guard !Task.isCancelled else { return }
            content = computed
        }
        .abyssBackground()
        .navigationTitle(String(localized: "Accueil"))
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func sections(_ content: HomeContent, now: Date, calendar: Calendar, shown: Bool) -> some View {
        if !content.hasFollows {
            FollowPromptCard(action: openTeams).cascadeIn(index: 0, shown: shown)
        }
        MustWatchSection(picks: content.sections.mustWatch).cascadeIn(index: 1, shown: shown)
        LiveNowSection(items: content.live, onHaptic: { haptics.play($0) }).cascadeIn(index: 2, shown: shown)
        WeekStripSection(days: content.strip, eventsByDay: content.eventsByDay, today: calendar.startOfDay(for: now),
                         calendar: calendar, selected: $selectedDay, onReveal: reveal,
                         onHaptic: { haptics.play($0) })
            .cascadeIn(index: 3, shown: shown)
        RecentResultsSection(events: content.sections.recentResults, onReveal: reveal).cascadeIn(index: 4, shown: shown)
        ActivitySection(items: content.sections.activity, loading: !content.isLoaded).cascadeIn(index: 5, shown: shown)
        HotPlayersSection(players: content.hotPlayers, progress: content.progress, key: $hotKey,
                          onHaptic: { haptics.play($0) })
            .cascadeIn(index: 6, shown: shown)
    }

    private func key(now: Date, calendar: Calendar) -> HomeKey {
        HomeKey(version: store.season.version, follows: store.follows, revealed: store.settings.revealedMatchIds,
                day: calendar.startOfDay(for: now), updated: store.lastUpdate, liveIds: store.live?.map(\.id),
                loaded: store.season.isLoaded, running: store.season.progress.running,
                revealedStandings: store.settings.revealedStandingIds)
    }

    /// « Toucher pour révéler » (spec §8) : retour haptique et fondu de révélation.
    private func reveal(_ matchId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.reveal(matchId: matchId)
        }
    }

    private func refresh() async {
        await store.refreshNow()
        guard !Task.isCancelled else { return }
        haptics.play(store.isFailing ? .refreshFailed : .refreshSucceeded)
    }
}

/// Sans équipe suivie (spec saison §2.2) : l'Accueil montre quand même le Mondial, avec cette carte en tête.
struct FollowPromptCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suis tes équipes pour un accueil sur mesure").sora(.headline)
            Text("En attendant, voici le Mondial.").sora(.secondary).foregroundStyle(Palette.secondary)
            Button(action: action) {
                HStack(spacing: 6) {
                    IconView(icon: .star, size: 15)
                    Text("Choisir mes équipes")
                }
                .sora(.bodyMedium)
                .foregroundStyle(Palette.abyss)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }
}
```

- [ ] **Step 8: Écrire les planches**

Créer `Tests/FailleTests/HomeSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Deux résultats d'hier ajoutés au calendrier d'exemple : T1 – HLE (T1 en anti-spoiler : « Terminé · toucher pour
    /// révéler ») et GEN 2 – 0 FUR (score visible).
    private func homeData(_ base: PreviewData) -> PreviewData {
        var data = base
        func team(_ id: String, _ wins: Int, _ won: Bool) -> MatchTeam {
            let catalog = SampleData.catalog.first { $0.id == id }
            return MatchTeam(id: nil, name: catalog?.name ?? id, code: catalog?.code ?? id.uppercased(), image: nil,
                             result: MatchTeam.Result(outcome: won ? "win" : "loss", gameWins: wins))
        }
        func completed(_ id: String, _ start: String, _ a: MatchTeam, _ b: MatchTeam) -> MatchEvent {
            MatchEvent(startTime: SampleData.date(start), state: .completed, type: "match", blockName: "Play-in",
                       league: SampleData.worlds,
                       match: MatchInfo(id: id, teams: [a, b], strategy: Strategy(type: "bestOf", count: 3), games: nil),
                       streams: nil)
        }
        data.schedule += [completed("m-t1-hle-r", "2026-10-14T12:00:00Z", team("t1", 2, true), team("hle", 1, false)),
                          completed("m-gen-fur-r", "2026-10-14T09:00:00Z", team("gen", 2, true), team("fur", 0, false))]
        return data
    }

    private func home(_ data: PreviewData) -> some View {
        NavigationStack { HomeView(openTeams: {}) }
            .environment(AppStore(preview: homeData(data)))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
    }

    /// Accueil avec suivis (spec saison §2.2) : à ne pas rater, direct (T1 – FLY masqué : « En direct » seul), calendrier,
    /// résultats (T1 – HLE « toucher pour révéler »), activité, joueurs en forme.
    @Test func homeWithFollows() async throws {
        let top = try await Snapshot.write(home(.withSeason), named: "25-accueil")
        expectNotBlank(top)
        let bottom = try await Snapshot.write(home(.withSeason).defaultScrollAnchor(.bottom), named: "25-accueil-bas")
        expectNotBlank(bottom)
    }

    /// Sans équipe suivie : « Suis tes équipes pour un accueil sur mesure », et le Mondial quand même.
    @Test func homeWithoutFollows() async throws {
        let url = try await Snapshot.write(home(.withSeasonNoFollows), named: "25b-accueil-sans-suivi")
        expectNotBlank(url)
    }

    /// Collecte en cours : « Les stats arrivent : … games lues sur … ».
    @Test func homeWhileCollecting() async throws {
        let url = try await Snapshot.write(home(.withSeasonCollecting).defaultScrollAnchor(.bottom),
                                           named: "25c-accueil-collecte")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 9: Commit, push, CI une fois**

```bash
git add App/Home Tests/FailleTests/HomeTests.swift Tests/FailleTests/HomeSnapshotTests.swift
git commit -m "feat(app): Accueil — à ne pas rater, en direct (masqué : « En direct » seul), calendrier de la semaine, résultats récents révélables, activité, joueurs en forme ; calcul hors du fil principal" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a3-accueil
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

Attendu : CI verte ; planches `25-*` non vides ; T1 – FLY sans score ni « Regarder », T1 – HLE « Terminé · toucher pour révéler ».

---

### Task A4: Duels de joueurs et d'équipes

**Branche :** `nuit2/appli-a4-duels` · **Vague :** 4a · **Dépendances :** I1, L3 fusionnées.

**Files:**
- Modify: `App/Duel/DuelView.swift` (coquille d'I1 : `init(left:right:)` gardé)
- Create: `App/Duel/DuelModel.swift`, `App/Duel/DuelBars.swift`, `App/Duel/DuelSection.swift`, `App/Duel/DuelPicker.swift`
- Test: `Tests/FailleTests/DuelTests.swift`, `Tests/FailleTests/DuelSnapshotTests.swift` (planches `27-duel`, `27b-duel-masque`)

**Interfaces:**
- Consumes : L3 `Duel.lineup(teamId:catalog:games:) -> [DuelSlot]`, `Duel.players(left:right:games:masked:) -> PlayerDuel`, `DuelBar` (`metric: DuelMetric`, `left`, `right`, `leftRatio`, `rightRatio`), `DuelMetric`, `Duel.roles`, `SeasonStats.headToHead`, `HeadToHead` (`winsA`, `winsB`, `matchIds`, `maskedMatches`), `PlayerSeason`, `SeasonScope` ; L2 `GameSummary`, `PlayerGameLine` ; I1 (`season`, `seasonMasked`, `teamCode`, `ChampionIcon`, `MatchLine`, `StatTile`, `SeasonNames`, `SeasonFormat`, `DuelRoute`, `DuelSide`, `PlayerRoute`) , `SeasonNames.role` (noms des postes).
- Produces : `DuelSection(matchId:teams:selectedGameId:masked:)` (inséré dans le Détail par I2), `DuelView(left:right:)` (écran), `struct DuelPlayer`, `struct DuelLine`, `enum DuelModel { lineup, lines, candidates }`, `DuelBarRow`, `enum DuelTexts`, `PlayerDuelCard`, `TeamDuelCard`, `DuelPicker`.

- [ ] **Step 1: Relire le contrat L3 (`Duel`, `HeadToHead`, `PlayerSeason`)**

```bash
git pull --ff-only origin main
grep -n "public" LoLKit/Sources/LoLKit/Season/Duel.swift LoLKit/Sources/LoLKit/Season/PlayerSeason.swift LoLKit/Sources/LoLKit/Season/SeasonStats.swift
```

Relevé à `4e37f00` : `Duel.lineup` rend un `DuelSlot` par poste (effectif du catalogue, règle du remplaçant, repli sur la game la plus récente) et attend des games **sans les matchs masqués** ; `Duel.players` rend les deux saisons et les barres (largeurs déjà calculées). Le type `DuelBar` est celui de LoLKit : l'appli n'en déclare pas. Adapter si cela a bougé, sans changer la règle (composition de la game seulement si jouée et non masquée).

- [ ] **Step 2: Écrire les tests de la logique**

Créer `Tests/FailleTests/DuelTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

struct DuelModelTests {
    private let catalog = [Team(id: "kc", slug: "kc", name: "KC", code: "KC", image: nil, status: "active", homeLeague: nil,
                                players: [TeamPlayer(id: "p-canna", summonerName: "Canna", image: nil, role: "top")])]

    @Test func aMaskedMatchNeverLendsItsLineupNorItsGameLine() throws {
        let game = try #require(SeasonSamples.games.first { $0.gameId == "g1-kc-g2" })
        // Match masqué : ni sa composition ni ses games (l'appelant passe les games sans les matchs masqués).
        let masked = DuelModel.lineup(teamId: "kc", game: game, masked: true, catalog: catalog, games: [], teamCode: "KC")
        #expect(masked["top"] == DuelPlayer(id: "p-canna", name: "Canna", thisGame: nil))
        #expect(masked["jungle"] == nil)
        let shown = DuelModel.lineup(teamId: "kc", game: game, masked: false, catalog: catalog, games: [game], teamCode: "KC")
        #expect(shown.count == 5)
        #expect(shown["top"]?.name == "Canna")
        #expect(shown["jungle"]?.name == "Yike") // pas au catalogue : préfixe « KC » retiré
        #expect(shown["top"]?.thisGame != nil)
    }

    @Test func pickerSearchesCatalogAndCachedGames() {
        let found = DuelModel.candidates(query: "canna", games: SeasonSamples.games, catalog: catalog)
        #expect(found.map(\.id) == ["p-canna"])
        #expect(DuelModel.candidates(query: "", games: SeasonSamples.games, catalog: catalog).count == 35)
    }
}

/// Duel d'un match masqué (spec saison §3.3) : stats de saison seulement, composition du catalogue, aucune ligne « Cette
/// game ».
@MainActor
struct DuelSectionContentTests {
    @Test func aMaskedMatchShowsOnlySeasonStatsFromTheCatalogLineup() {
        let store = AppStore(preview: .withSeason)
        let lines = DuelSection.lines(store: store, teams: SampleData.t1Live.match.teams, selectedGameId: "g1-t1-blg",
                                      masked: true)
        #expect(lines.first?.left?.name == "Doran")
        #expect(lines.allSatisfy { $0.left?.thisGame == nil && $0.right?.thisGame == nil })
    }

    @Test func aRevealedPlayedGameLendsItsLineupAndItsLine() {
        let store = AppStore(preview: .withSeason)
        let teams = SampleData.kcG2Details.match.teams
        let lines = DuelSection.lines(store: store, teams: teams, selectedGameId: "g4-kc-g2", masked: false)
        #expect(lines.count == 5)
        #expect(lines.first?.left?.name == "Canna")
        #expect(lines.first?.right?.name == "BrokenBlade")
        #expect(lines.allSatisfy { $0.left?.thisGame != nil })
    }
}
```

- [ ] **Step 3: Écrire la logique sans interface**

Créer `App/Duel/DuelModel.swift` :

```swift
import Foundation
import LoLKit

/// Un joueur d'un côté du duel : son id (`esportsPlayerId`), son nom affiché, et sa ligne de la game affichée si elle est
/// jouée et non masquée.
struct DuelPlayer: Equatable, Sendable {
    let id: String
    let name: String
    let thisGame: PlayerGameLine?
}

/// Une ligne poste contre poste (spec saison §3.3).
struct DuelLine: Equatable, Sendable, Identifiable {
    let role: String
    let left: DuelPlayer?
    let right: DuelPlayer?
    var id: String { role }
}

/// Assemblage des duels pour l'écran (spec saison §3.3) ; les règles (effectif, remplaçant, barres) sont dans LoLKit
/// (`Duel.lineup`, `Duel.players`).
enum DuelModel {
    /// Composition d'une équipe pour le duel : celle de la game affichée si elle est jouée ET non masquée, sinon
    /// `Duel.lineup` (effectif du catalogue, règle du remplaçant, repli sur la game la plus récente de l'équipe).
    /// Anti-spoiler : pour un match masqué, rien n'est lu dans ce match — ni composition, ni ligne « Cette game ».
    /// - Parameter games: games lues **sans les matchs masqués** (comme l'exige `Duel.lineup`).
    static func lineup(teamId: String, game: GameSummary?, masked: Bool, catalog: [Team], games: [GameSummary],
                       teamCode: String?) -> [String: DuelPlayer] {
        if !masked, let line = game?.line(teamId: teamId) {
            return Dictionary(line.players.map { player in
                (player.role, DuelPlayer(id: player.playerId,
                                         name: SeasonNames.player(player.playerId, raw: player.name, teamCode: teamCode,
                                                                  catalog: catalog),
                                         thisGame: player))
            }, uniquingKeysWith: { first, _ in first })
        }
        return Dictionary(Duel.lineup(teamId: teamId, catalog: catalog, games: games).compactMap { slot in
            slot.playerId.map { id in
                (slot.role, DuelPlayer(id: id, name: SeasonNames.player(id, raw: slot.name ?? id, teamCode: teamCode,
                                                                        catalog: catalog),
                                       thisGame: nil))
            }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Lignes dans l'ordre des postes (`Duel.roles`) ; un poste vide des deux côtés n'a pas de ligne.
    static func lines(left: [String: DuelPlayer], right: [String: DuelPlayer]) -> [DuelLine] {
        Duel.roles.compactMap { role in
            guard left[role] != nil || right[role] != nil else { return nil }
            return DuelLine(role: role, left: left[role], right: right[role])
        }
    }

    /// Joueurs proposés par le sélecteur « Changer » : ceux des games en cache et des effectifs du catalogue, sans doublon,
    /// filtrés par la recherche (pseudo), triés par nom.
    static func candidates(query: String, games: [GameSummary], catalog: [Team], limit: Int = 40) -> [DuelPlayer] {
        var seen: [String: DuelPlayer] = [:]
        for team in catalog {
            for player in team.players ?? [] where seen[player.id] == nil {
                seen[player.id] = DuelPlayer(id: player.id, name: player.summonerName, thisGame: nil)
            }
        }
        for game in games {
            for player in game.blue.players + game.red.players where seen[player.playerId] == nil && !player.playerId.isEmpty {
                seen[player.playerId] = DuelPlayer(id: player.playerId, name: player.name, thisGame: nil)
            }
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return seen.values
            .filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
            .prefix(limit).map { $0 }
    }
}
```

- [ ] **Step 4: Écrire les barres en miroir**

Créer `App/Duel/DuelBars.swift` :

```swift
import LoLKit
import SwiftUI

/// Une barre en miroir (spec saison §3.3) : valeur de gauche, deux demi-barres partant du centre (largeur = valeur / max
/// des deux, `Motion.smooth`), valeur de droite ; « — » sans valeur. Lue « KDA : Canna 3,4, BrokenBlade 4,1 ».
struct DuelBarRow: View {
    let bar: DuelBar
    let names: (String, String)
    var tints: (Color, Color) = (Palette.accent, Palette.text.opacity(0.7))
    @ReduceMotion var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(DuelTexts.metric(bar.metric)).sora(.label).foregroundStyle(Palette.secondary)
            HStack(spacing: 8) {
                Text(DuelTexts.value(bar.left, metric: bar.metric))
                    .sora(.stat).monospacedDigit().frame(width: 52, alignment: .trailing)
                GeometryReader { proxy in
                    let half = proxy.size.width / 2
                    HStack(spacing: 2) {
                        Spacer(minLength: 0)
                        Capsule().fill(tints.0).frame(width: max(0, (half - 1) * bar.leftRatio))
                        Capsule().fill(tints.1).frame(width: max(0, (half - 1) * bar.rightRatio))
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width)
                }
                .frame(height: 6)
                .animation(Motion.animation(.smooth, reduceMotion: reduceMotion), value: bar)
                Text(DuelTexts.value(bar.right, metric: bar.metric))
                    .sora(.stat).monospacedDigit().frame(width: 52, alignment: .leading)
            }
        }
        .foregroundStyle(Palette.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(DuelTexts.metric(bar.metric)) : \(names.0) \(DuelTexts.value(bar.left, metric: bar.metric)), \(names.1) \(DuelTexts.value(bar.right, metric: bar.metric))"))
    }
}

/// Textes du duel.
enum DuelTexts {
    static func metric(_ metric: DuelMetric) -> String {
        switch metric {
        case .kda: String(localized: "KDA")
        case .csPerMin: String(localized: "CS/min")
        case .goldPerMin: String(localized: "Gold/min")
        case .damageShare: String(localized: "Part des dégâts")
        case .killParticipation: String(localized: "Participation aux kills")
        }
    }

    static func value(_ value: Double?, metric: DuelMetric) -> String {
        guard let value else { return SeasonFormat.missing }
        switch metric {
        case .kda, .csPerMin: return SeasonFormat.decimal(value)
        case .goldPerMin: return SeasonFormat.integer(value)
        case .damageShare, .killParticipation: return SeasonFormat.percent(value)
        }
    }
}

/// Un face-à-face de joueurs : noms, barres, 3 champions favoris de chaque côté, et la ligne « Cette game » si elle est
/// connue (game jouée d'un match non masqué).
struct PlayerDuelCard: View {
    @Environment(AppStore.self) private var store
    let role: String?
    let left: DuelPlayer?
    let right: DuelPlayer?
    var onChange: ((DuelSidePosition) -> Void)? = nil

    var body: some View {
        // Stats de saison sans les matchs masqués (`Duel.players`) ; un côté vide : « — ».
        let duel = Duel.players(left: left?.id ?? "", right: right?.id ?? "", games: Array(store.season.games.values),
                                masked: store.seasonMasked)
        let leftSeason = duel.left
        let rightSeason = duel.right
        let names = (left?.name ?? SeasonFormat.missing, right?.name ?? SeasonFormat.missing)
        VStack(spacing: 10) {
            HStack {
                playerName(left, season: leftSeason, position: .left)
                Spacer()
                if let role { Text(SeasonNames.role(role)).sora(.label).foregroundStyle(Palette.secondary) }
                Spacer()
                playerName(right, season: rightSeason, position: .right)
            }
            ForEach(duel.bars, id: \.metric) { bar in
                DuelBarRow(bar: bar, names: names)
            }
            HStack {
                champions(leftSeason)
                Spacer()
                champions(rightSeason)
            }
            if left?.thisGame != nil || right?.thisGame != nil {
                HStack {
                    thisGame(left?.thisGame)
                    Spacer()
                    Text("Cette game").sora(.label).foregroundStyle(Palette.secondary)
                    Spacer()
                    thisGame(right?.thisGame)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func playerName(_ player: DuelPlayer?, season: PlayerSeason?, position: DuelSidePosition) -> some View {
        VStack(alignment: position == .left ? .leading : .trailing, spacing: 2) {
            if let player {
                NavigationLink(value: PlayerRoute(playerId: player.id)) {
                    Text(player.name).sora(.headline).lineLimit(1)
                }
                .buttonStyle(.pressable)
            } else {
                Text(SeasonFormat.missing).sora(.headline)
            }
            Text(season.map { String(localized: "sur \($0.games) games") } ?? String(localized: "aucune game lue"))
                .sora(.label).foregroundStyle(Palette.secondary)
            if let onChange {
                Button { onChange(position) } label: {
                    Text("Changer").sora(.label).foregroundStyle(Palette.accent).frame(minHeight: 32)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Changer de joueur"))
            }
        }
    }

    private func champions(_ season: PlayerSeason?) -> some View {
        HStack(spacing: 4) {
            ForEach(season?.champions.prefix(3).map(\.champion) ?? [], id: \.self) { champion in
                ChampionIcon(champion: champion, size: 26)
            }
        }
    }

    private func thisGame(_ line: PlayerGameLine?) -> some View {
        HStack(spacing: 6) {
            if let line {
                ChampionIcon(champion: line.champion, size: 22)
                Text(SeasonFormat.kda(kills: line.kills, deaths: line.deaths, assists: line.assists))
                    .sora(.secondaryMedium).monospacedDigit()
                Text("\(line.creepScore) CS").sora(.secondary).foregroundStyle(Palette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Côté d'un face-à-face (bouton « Changer »).
enum DuelSidePosition: Hashable {
    case left, right
}

/// Duel d'équipes (spec saison §3.3) : bilans et moyennes de la saison côte à côte, et face-à-face de la saison
/// (matchs masqués exclus et comptés).
struct TeamDuelCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    let leftId: String
    let rightId: String

    var body: some View {
        let now = fixedNow ?? Date()
        let masked = store.seasonMasked
        let left = season(leftId, now: now, masked: masked)
        let right = season(rightId, now: now, masked: masked)
        let h2h = SeasonStats.headToHead(leftId, rightId, matches: store.season.matches, masked: masked)
        let codes = (store.teamCode(id: leftId) ?? leftId, store.teamCode(id: rightId) ?? rightId)
        VStack(alignment: .leading, spacing: 12) {
            Text("Cette saison : \(codes.0) \(h2h.winsA) – \(h2h.winsB) \(codes.1)").sora(.headline)
            if h2h.maskedMatches > 0 {
                Text("\(h2h.maskedMatches) matchs masqués").sora(.secondary).foregroundStyle(Palette.secondary)
            }
            ForEach(store.season.matches.filter { h2h.matchIds.contains($0.id) }) { match in
                if let event = store.event(id: match.id) {
                    MatchLine(event: event, showsDay: true)
                }
            }
            row(String(localized: "Séries"), left.map { SeasonFormat.record($0.seriesWins, $0.seriesLosses) },
                right.map { SeasonFormat.record($0.seriesWins, $0.seriesLosses) })
            row(String(localized: "Games"), left.map { SeasonFormat.record($0.gameWins, $0.gameLosses) },
                right.map { SeasonFormat.record($0.gameWins, $0.gameLosses) })
            row(String(localized: "Kills par game"), left?.averages.map { SeasonFormat.decimal($0.kills) },
                right?.averages.map { SeasonFormat.decimal($0.kills) })
            row(String(localized: "Morts par game"), left?.averages.map { SeasonFormat.decimal($0.deaths) },
                right?.averages.map { SeasonFormat.decimal($0.deaths) })
            row(String(localized: "Durée moyenne"), left?.averages.map { SeasonFormat.duration(seconds: $0.durationSeconds) },
                right?.averages.map { SeasonFormat.duration(seconds: $0.durationSeconds) })
            row(String(localized: "Drakes par game"), left?.averages.map { SeasonFormat.decimal($0.dragons) },
                right?.averages.map { SeasonFormat.decimal($0.dragons) })
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func season(_ teamId: String, now: Date, masked: Set<String>) -> TeamSeason? {
        guard let scope = store.season.scopes(forTeam: teamId, now: now).first, !scope.tournamentIds.isEmpty else { return nil }
        return store.season.teamSeason(teamId, scope: scope, masked: masked, now: now)
    }

    private func row(_ label: String, _ left: String?, _ right: String?) -> some View {
        HStack {
            Text(left ?? SeasonFormat.missing).sora(.stat).monospacedDigit()
            Spacer()
            Text(label).sora(.secondary).foregroundStyle(Palette.secondary)
            Spacer()
            Text(right ?? SeasonFormat.missing).sora(.stat).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
```

Note : la liste des matchs du face-à-face utilise `store.event(id:)` (calendrier/direct) ; un match de la saison absent du calendrier n'a pas de ligne (le compte `winsA – winsB` reste juste).

- [ ] **Step 5: Écrire la section du Détail**

Créer `App/Duel/DuelSection.swift` :

```swift
import LoLKit
import SwiftUI

/// Section « Duel » du Détail (spec saison §3.3), sous les stats : onglets « Joueurs » (poste contre poste) et
/// « Équipes ». Anti-spoiler : pour un match masqué (à venir, en cours ou terminé), seules les stats de saison (matchs
/// masqués exclus) ; aucune ligne « Cette game », aucune composition lue dans ce match. « Changer » ouvre le sélecteur
/// et pousse un duel libre.
struct DuelSection: View {
    @Environment(AppStore.self) private var store
    let matchId: String
    /// Équipes du match, dans l'ordre d'affichage du Détail.
    let teams: [MatchTeam]
    /// Game affichée par le Détail si elle est jouée ; nil sinon.
    let selectedGameId: String?
    let masked: Bool
    @State private var showsTeams = false
    @State private var picking: (role: String, position: DuelSidePosition)?
    @State private var freeDuel: DuelRoute?
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    var body: some View {
        let ids = teams.compactMap(\.id)
        if ids.count == 2 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: String(localized: "Duel"))
                    PillButton(selected: !showsTeams, action: { select(teams: false) }) { Text("Joueurs") }
                    PillButton(selected: showsTeams, action: { select(teams: true) }) { Text("Équipes") }
                }
                if showsTeams {
                    TeamDuelCard(leftId: ids[0], rightId: ids[1])
                } else {
                    let lines = Self.lines(store: store, teams: teams, selectedGameId: selectedGameId, masked: masked)
                    if lines.isEmpty {
                        NoteCard(icon: .player, text: String(localized: "Effectifs inconnus pour ce match"))
                    }
                    ForEach(lines) { line in
                        PlayerDuelCard(role: line.role, left: line.left, right: line.right,
                                       onChange: { picking = (line.role, $0) })
                    }
                }
            }
            .haptics(haptics)
            .sheet(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } })) {
                DuelPicker { chosen in
                    guard let picking else { return }
                    let lines = Self.lines(store: store, teams: teams, selectedGameId: selectedGameId, masked: masked)
                    let line = lines.first { $0.role == picking.role }
                    let other = picking.position == .left ? line?.right?.id : line?.left?.id
                    self.picking = nil
                    haptics.play(.playerPicked)
                    if let other {
                        freeDuel = picking.position == .left ? DuelRoute(left: .player(chosen), right: .player(other))
                                                             : DuelRoute(left: .player(other), right: .player(chosen))
                    }
                }
                .environment(store)
            }
            .navigationDestination(item: $freeDuel) { DuelView(left: $0.left, right: $0.right) }
        }
    }

    private func select(teams: Bool) {
        guard teams != showsTeams else { return }
        haptics.play(.gamePicked)
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { showsTeams = teams }
    }

    /// Lignes poste contre poste (testées) : composition de la game affichée si elle est jouée et non masquée, sinon
    /// effectifs du catalogue (`DuelModel.lineup`).
    @MainActor
    static func lines(store: AppStore, teams: [MatchTeam], selectedGameId: String?, masked: Bool) -> [DuelLine] {
        let ids = teams.compactMap(\.id)
        guard ids.count == 2 else { return [] }
        let game = masked ? nil : selectedGameId.flatMap { store.season.games[$0] }
        // `Duel.lineup` ne lit que des games sans matchs masqués.
        let hidden = store.seasonMasked
        let all = store.season.games.values.filter { !hidden.contains($0.matchId) }
        let left = DuelModel.lineup(teamId: ids[0], game: game, masked: masked, catalog: store.catalog, games: all,
                                    teamCode: teams[0].code)
        let right = DuelModel.lineup(teamId: ids[1], game: game, masked: masked, catalog: store.catalog, games: all,
                                     teamCode: teams[1].code)
        return DuelModel.lines(left: left, right: right)
    }
}
```

- [ ] **Step 6: Écrire le sélecteur**

Créer `App/Duel/DuelPicker.swift` :

```swift
import LoLKit
import SwiftUI

/// Sélecteur « Changer » (spec saison §3.3) : recherche parmi les joueurs des games en cache et des effectifs du
/// catalogue.
struct DuelPicker: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        let candidates = DuelModel.candidates(query: query, games: Array(store.season.games.values), catalog: store.catalog)
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisir un joueur").sora(.title).tracking(Typo.titleTracking)
            TextField("", text: $query, prompt: Text("Rechercher un joueur").foregroundStyle(Palette.secondary))
                .sora(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(candidates, id: \.id) { player in
                        Button {
                            onPick(player.id)
                            dismiss()
                        } label: {
                            Text(player.name).sora(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
        .foregroundStyle(Palette.text)
        .padding(20)
        .abyssBackground()
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 7: Écrire l'écran du duel libre**

Remplacer tout le contenu de `App/Duel/DuelView.swift` (coquille d'I1) par :

```swift
import LoLKit
import SwiftUI

/// Duel libre (spec saison §3.3) : deux joueurs (barres, champions favoris) ou deux équipes (bilans, face-à-face) ; stats
/// de saison sans les matchs masqués.
struct DuelView: View {
    @Environment(AppStore.self) private var store
    let left: DuelSide
    let right: DuelSide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(String(localized: "Duel"), subtitle: String(localized: "Stats de la saison"))
                switch (left, right) {
                case let (.player(a), .player(b)):
                    PlayerDuelCard(role: nil, left: player(a), right: player(b))
                case let (.team(a), .team(b)):
                    TeamDuelCard(leftId: a, rightId: b)
                default:
                    NoteCard(icon: .versus, text: String(localized: "Choisis deux joueurs ou deux équipes"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Joueur d'un duel libre : son nom (catalogue, sinon pseudo du flux sans le code d'équipe), sans ligne « Cette game ».
    private func player(_ id: String) -> DuelPlayer {
        for game in store.season.games.values {
            for line in [game.blue, game.red] {
                if let player = line.players.first(where: { $0.playerId == id }) {
                    return DuelPlayer(id: id, name: store.playerName(id: id, raw: player.name, teamId: line.teamId),
                                      thisGame: nil)
                }
            }
        }
        let name = store.catalog.lazy.compactMap { $0.players?.first { $0.id == id }?.summonerName }.first
        return DuelPlayer(id: id, name: name ?? id, thisGame: nil)
    }
}
```

- [ ] **Step 8: Écrire les planches**

Créer `Tests/FailleTests/DuelSnapshotTests.swift` :

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Duel libre Caps – Canna (spec saison §3.3) : barres en miroir, champions favoris (vignettes de repli).
    @Test func playerDuel() async throws {
        let view = NavigationStack { DuelView(left: .player("p-canna"), right: .player("p-caps")) }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        let url = try await Snapshot.write(view, named: "27-duel")
        expectNotBlank(url)
    }

    /// Duel du match T1 – FLY (masqué : T1 en anti-spoiler) : effectifs du catalogue, stats de saison sans les matchs
    /// masqués (« — »), aucune ligne « Cette game ».
    @Test func duelOfAMaskedMatch() async throws {
        let view = NavigationStack {
            ScrollView {
                DuelSection(matchId: SampleData.t1MatchId, teams: SampleData.t1Live.match.teams, selectedGameId: nil,
                            masked: true)
                    .padding(16)
            }
            .abyssBackground()
        }
        .environment(AppStore(preview: .withSeason))
        let url = try await Snapshot.write(view, named: "27b-duel-masque")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 9: Commit, push, CI une fois**

```bash
git add App/Duel Tests/FailleTests/DuelTests.swift Tests/FailleTests/DuelSnapshotTests.swift
git commit -m "feat(app): duels — section du Détail (joueurs poste par poste, équipes), barres en miroir, sélecteur, duel libre ; match masqué : stats de saison seulement" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a4-duels
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

Attendu : CI verte ; `27-duel` et `27b-duel-masque` non vides ; `27b` sans aucune ligne « Cette game ».

---

### Task A5: Page joueur

**Branche :** `nuit2/appli-a5-page-joueur` · **Vague :** 4a · **Dépendances :** I1, L3 fusionnées.

**Files:**
- Modify: `App/PlayerPage/PlayerPageView.swift` (coquille d'I1 : `init(playerId:)` gardé)
- Create: `App/PlayerPage/PlayerPageModel.swift`, `App/PlayerPage/PlayerPageSections.swift`
- Test: `Tests/FailleTests/PlayerPageTests.swift`, `Tests/FailleTests/PlayerPageSnapshotTests.swift` (planches `28-joueur`, `28b-joueur-masque`)

**Interfaces:**
- Consumes : L3 `PlayerSeason`, `ChampionUse`, `GameRefLine` (`teamId`, `won: Bool?`, `winEstimated`) ; L2 `PlayerName` (via `SeasonNames`) ; I1 (`season.player(_:scope:masked:)`, `season.scopes(forTeam:now:)`, `seasonMasked`, `teamCode`, `ChampionIcon`, `StatTile`, `SeasonFormat`, `SeasonNames.role`, `SeasonSkeletonCard`, `\.seasonNow`, `TeamRoute`, `MatchRoute`).
- Produces : `PlayerPageView(playerId:)`, `struct PlayerIdentity`, `enum PlayerPageModel { identity, bestGame, maskedMatchCount }`.

- [ ] **Step 1: Relire le contrat L3 (`PlayerSeason`, `GameRefLine`)**

```bash
git pull --ff-only origin main
grep -n "public" LoLKit/Sources/LoLKit/Season/PlayerSeason.swift
```

Relevé à `4e37f00` : `GameRefLine.won` (nil = vainqueur inconnu) et `winEstimated` (« estimé ») ; `PlayerSeason.name` = pseudo brut du flux (afficher `store.playerName`). Adapter si cela a bougé.

- [ ] **Step 2: Écrire les tests de la logique**

Créer `Tests/FailleTests/PlayerPageTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

struct PlayerPageModelTests {
    @Test func playerIdentityPrefersTheCatalogAndStripsTheTeamPrefixOtherwise() {
        let games = SeasonSamples.games
        let identity = PlayerPageModel.identity("p-caps", catalog: SampleData.catalog, games: games)
        #expect(identity?.name == "Caps")
        #expect(identity?.role == "mid")
        #expect(identity?.teamId == "g2")
        #expect(PlayerPageModel.identity("nobody", catalog: [], games: games) == nil)
        // Faker (T1, en anti-spoiler dans les aperçus) : ses 3 matchs d'exemple sont masqués.
        let masked = SeasonMasking.maskedMatchIds(SeasonSamples.matches, follows: SampleData.follows, revealed: [])
        #expect(PlayerPageModel.maskedMatchCount("p-faker", games: games, masked: masked) == 3)
    }
}
```

- [ ] **Step 3: Écrire la logique sans interface**

Créer `App/PlayerPage/PlayerPageModel.swift` :

```swift
import Foundation
import LoLKit

/// Identité d'un joueur pour sa page (spec saison §3.4) : pseudo du catalogue s'il est connu, sinon celui du flux sans
/// le préfixe d'équipe ; équipe et rôle de sa game la plus récente ; photo du catalogue.
struct PlayerIdentity: Equatable, Sendable {
    let playerId: String
    let name: String
    let role: String?
    let teamId: String?
    let image: String?
}

enum PlayerPageModel {
    static func identity(_ playerId: String, catalog: [Team], games: [GameSummary]) -> PlayerIdentity? {
        let latest = games
            .compactMap { game -> (GameSummary, TeamGameLine, PlayerGameLine)? in
                for line in [game.blue, game.red] {
                    if let player = line.players.first(where: { $0.playerId == playerId }) { return (game, line, player) }
                }
                return nil
            }
            .max { $0.0.startedAt < $1.0.startedAt }
        for team in catalog {
            if let player = team.players?.first(where: { $0.id == playerId }) {
                return PlayerIdentity(playerId: playerId, name: player.summonerName,
                                      role: latest?.2.role ?? player.role, teamId: latest?.1.teamId ?? team.id,
                                      image: player.image)
            }
        }
        guard let latest else { return nil }
        let code = catalog.first { $0.id == latest.1.teamId }?.code
        return PlayerIdentity(playerId: playerId, name: PlayerName.display(latest.2.name, teamCode: code),
                              role: latest.2.role, teamId: latest.1.teamId, image: nil)
    }

    /// Meilleure game montrée seulement si son match n'est pas masqué (spec saison §3.4) ; `SeasonStats.player` exclut
    /// déjà les matchs masqués, ce contrôle est une ceinture de plus.
    static func bestGame(_ season: PlayerSeason?, masked: Set<String>) -> GameRefLine? {
        guard let best = season?.bestGame, !masked.contains(best.matchId) else { return nil }
        return best
    }

    /// Matchs masqués où le joueur a joué (« N matchs masqués » sur sa page) : des matchs, jamais des games.
    static func maskedMatchCount(_ playerId: String, games: [GameSummary], masked: Set<String>) -> Int {
        Set(games.filter { game in
            masked.contains(game.matchId) && (game.blue.players + game.red.players).contains { $0.playerId == playerId }
        }.map(\.matchId)).count
    }
}
```

- [ ] **Step 4: Écrire les sections**

Créer `App/PlayerPage/PlayerPageSections.swift` :

```swift
import LoLKit
import SwiftUI

/// Moyennes d'un joueur (spec saison §3.4) : K/D/A par game, KDA, CS/min, gold/min, participation aux kills, part des
/// dégâts « sur N games enrichies » ou « — ».
struct PlayerAveragesCard: View {
    let season: PlayerSeason

    var body: some View {
        let games = Double(max(1, season.games))
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: String(localized: "Moyennes"))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(value: "\(SeasonFormat.decimal(Double(season.kills) / games))/\(SeasonFormat.decimal(Double(season.deaths) / games))/\(SeasonFormat.decimal(Double(season.assists) / games))",
                             label: String(localized: "K/D/A par game"))
                    StatTile(value: SeasonFormat.decimal(season.kda), label: String(localized: "KDA"))
                }
                GridRow {
                    StatTile(value: SeasonFormat.decimal(season.csPerMin), label: String(localized: "CS/min"))
                    StatTile(value: SeasonFormat.integer(season.goldPerMin), label: String(localized: "Gold/min"))
                }
                GridRow {
                    StatTile(value: SeasonFormat.percent(season.killParticipation),
                             label: String(localized: "Participation aux kills"))
                    StatTile(value: SeasonFormat.percent(season.damageShareGames > 0 ? season.damageShare : nil),
                             label: String(localized: "Part des dégâts"),
                             footnote: String(localized: "sur \(season.damageShareGames) games enrichies"))
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Champions joués : icône, games, bilan V-D (« estimé » si un vainqueur est déduit).
struct PlayerChampionsCard: View {
    let champions: [ChampionUse]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: String(localized: "Champions joués"))
            ForEach(champions, id: \.champion) { use in
                HStack(spacing: 10) {
                    ChampionIcon(champion: use.champion, size: 32)
                    Text(use.champion).sora(.bodyMedium)
                    Spacer()
                    Text("\(use.games) games").sora(.secondary).foregroundStyle(Palette.secondary)
                    Text(SeasonFormat.record(use.wins, use.games - use.wins)).sora(.stat).monospacedDigit()
                    if use.winsEstimated {
                        Text("estimé").sora(.label).foregroundStyle(Palette.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Une game de la liste (meilleure game, 5 dernières) : champion, K/D/A, CS, résultat si connu (« estimé » si déduit) ;
/// toucher → Détail du match. Les games d'un match masqué n'arrivent jamais ici (`SeasonStats.player`).
struct PlayerGameRow: View {
    let line: GameRefLine

    var body: some View {
        NavigationLink(value: MatchRoute(matchId: line.matchId)) {
            HStack(spacing: 10) {
                ChampionIcon(champion: line.champion, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SeasonFormat.kda(kills: line.kills, deaths: line.deaths, assists: line.assists))
                        .sora(.stat).monospacedDigit()
                    Text(line.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .sora(.secondary).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text("\(line.creepScore) CS").sora(.secondary).foregroundStyle(Palette.secondary)
                result
            }
            .foregroundStyle(Palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var result: some View {
        if let won = line.won {
            HStack(spacing: 3) {
                Text(won ? String(localized: "V") : String(localized: "D")).sora(.stat)
                if line.winEstimated {
                    Text("estimé").sora(.label).foregroundStyle(Palette.secondary)
                }
            }
            .accessibilityLabel(won ? Text("Victoire") : Text("Défaite"))
        }
    }
}
```

- [ ] **Step 5: Écrire l'écran**

Remplacer tout le contenu de `App/PlayerPage/PlayerPageView.swift` (coquille d'I1) par :

```swift
import LoLKit
import SwiftUI

/// Page d'un joueur (spec saison §3.4) : en-tête (pseudo, poste, équipe → page d'équipe), périmètres, « sur N games »,
/// moyennes, champions, meilleure game (jamais d'un match masqué), 5 dernières games. Squelettes pendant la lecture du
/// disque. Stats sans les matchs masqués ; s'il n'y a qu'eux : « N matchs masqués ».
struct PlayerPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    let playerId: String
    @State private var scopeIndex = 0
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    var body: some View {
        let now = fixedNow ?? Date()
        let games = Array(store.season.games.values)
        let identity = PlayerPageModel.identity(playerId, catalog: store.catalog, games: games)
        let scopes = identity?.teamId.map { store.season.scopes(forTeam: $0, now: now) } ?? []
        let scope = scopes.isEmpty ? nil : scopes[min(scopeIndex, scopes.count - 1)]
        let masked = store.seasonMasked
        let season = store.season.player(playerId, scope: scope, masked: masked)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(identity)
                if scopes.count > 1 {
                    pills(scopes)
                }
                if !store.season.isLoaded {
                    SeasonSkeletonCard(lines: 3, label: String(localized: "Stats en chargement"))
                    SeasonSkeletonCard(lines: 4, label: String(localized: "Champions en chargement"))
                } else if let season, season.games > 0 {
                    Text("sur \(season.games) games").sora(.secondary).foregroundStyle(Palette.secondary)
                    PlayerAveragesCard(season: season)
                    if !season.champions.isEmpty {
                        PlayerChampionsCard(champions: season.champions)
                    }
                    if let best = PlayerPageModel.bestGame(season, masked: masked) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: String(localized: "Meilleure game"))
                            PlayerGameRow(line: best)
                        }
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    if !season.recent.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: String(localized: "5 dernières games"))
                            ForEach(season.recent, id: \.gameId) { line in
                                PlayerGameRow(line: line)
                            }
                        }
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                } else {
                    let hidden = PlayerPageModel.maskedMatchCount(playerId, games: games, masked: masked)
                    NoteCard(icon: hidden > 0 ? .eyeOff : .clock,
                             text: hidden > 0 ? String(localized: "Stats masquées · \(hidden) matchs masqués")
                                              : String(localized: "Pas encore de game lue pour ce joueur"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationTitle(identity?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
    }

    private func header(_ identity: PlayerIdentity?) -> some View {
        HStack(spacing: 12) {
            Text(String((identity?.name ?? "?").prefix(2)).uppercased())
                .sora(.headline)
                .frame(width: 54, height: 54)
                .background(Palette.chipFill, in: Circle())
                .overlay(Circle().strokeBorder(Palette.glassBorder, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(identity?.name ?? SeasonFormat.missing).sora(.title).tracking(Typo.titleTracking)
                Text(SeasonNames.role(identity?.role)).sora(.secondary).foregroundStyle(Palette.secondary)
                if let teamId = identity?.teamId {
                    TeamLink(teamId: teamId) {
                        Text(store.teamName(id: teamId)).sora(.bodyMedium).foregroundStyle(Palette.accent)
                    }
                }
            }
            Spacer()
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }

    private func pills(_ scopes: [SeasonScope]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(scopes.enumerated()), id: \.offset) { index, scope in
                    PillButton(selected: index == min(scopeIndex, scopes.count - 1), action: {
                        if index != scopeIndex { haptics.play(.gamePicked) }
                        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { scopeIndex = index }
                    }) {
                        Text(SeasonLabels.scope(scope))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
```

- [ ] **Step 6: Écrire les planches**

Créer `Tests/FailleTests/PlayerPageSnapshotTests.swift` :

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func playerPage(_ playerId: String) -> some View {
        NavigationStack { PlayerPageView(playerId: playerId) }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
    }

    /// Page de Caps (spec saison §3.4) : moyennes, champions (vignettes de repli), meilleure game, 5 dernières games.
    @Test func playerPage() async throws {
        let url = try await Snapshot.write(playerPage("p-caps"), named: "28-joueur")
        expectNotBlank(url)
    }

    /// Faker (T1 en anti-spoiler) : « Stats masquées · 3 matchs masqués ».
    @Test func playerPageMasked() async throws {
        let url = try await Snapshot.write(playerPage("p-faker"), named: "28b-joueur-masque")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 7: Commit, push, CI une fois**

```bash
git add App/PlayerPage Tests/FailleTests/PlayerPageTests.swift Tests/FailleTests/PlayerPageSnapshotTests.swift
git commit -m "feat(app): page joueur — moyennes, champions (« estimé »), meilleure game et dernières games jamais masquées" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a5-page-joueur
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

---

### Task A6: Classements et tableaux

**Branche :** `nuit2/appli-a6-classements` · **Vague :** 4b · **Dépendances :** I1, L6 fusionnées.

**Files:**
- Modify: `App/Standings/StandingsView.swift` (coquille d'I1 : `init(tournamentId:)` gardé)
- Create: `App/Standings/StandingsTables.swift`, `App/Standings/StandingsTexts.swift`
- Test: `Tests/FailleTests/StandingsTests.swift`, `Tests/FailleTests/StandingsSnapshotTests.swift` (planches `29-classement`, `29b-classement-masque`, `29c-tableau-mondial`)

**Interfaces:**
- Consumes : L6 `StandingsTable.build(standings:)` (`Stage.content` : `.table([Row])`, `.swiss([RecordGroup])`, `.bracket([Round])` avec `Round.kind`, `.matches([BracketMatch])`) ; I1 (`season.standings`, `season.tournament(id:)`, `season.loadStandings(tournamentId:)`, `isStandingsMasked`, `revealStandings`, `follows`, `tint(for:)`, `TeamLink`, `SeasonSkeletonCard`) ; A1 `SeasonLabels.tournament`.
- Produces : `StandingsView(tournamentId:)`, `StandingsTableCard`, `SwissGroupsCard`, `BracketCard`, `enum StandingsTexts { roundName(_:), teamLabel(_:) }`.

- [ ] **Step 1: Relire le contrat L6**

```bash
git pull --ff-only origin main
grep -n "public" LoLKit/Sources/LoLKit/Season/StandingsTable.swift
```

Relevé à `4e37f00` : la phase finale (slug `knockouts`, 7 matchs) arrive en trois `Round` (`kind` : quarts, demies, finale) ; les autres tableaux (play-offs d'une ligue, play-ins) en `.matches` dans l'ordre de l'API. Adapter si cela a bougé.

- [ ] **Step 2: Écrire les tests**

Créer `Tests/FailleTests/StandingsTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Textes des tableaux (spec saison §3.5).
struct StandingsTests {
    @Test func roundNames() {
        #expect(StandingsTexts.roundName(.quarterFinal) == "Quarts de finale")
        #expect(StandingsTexts.roundName(.final) == "Finale")
    }

    @Test func placeholderTeamsAreToBeDetermined() {
        let tbd = MatchTeam(id: "0", name: "TBD", code: "TBD", image: nil, result: nil)
        let kc = MatchTeam(id: "kc", name: "Karmine Corp", code: "KC", image: nil, result: nil)
        #expect(StandingsTexts.teamLabel(tbd) == "À déterminer")
        #expect(StandingsTexts.teamLabel(kc) == "KC")
    }
}

/// Masquage d'un classement et révélation (qui ne révèle aucun match), sur la saison d'exemple.
@MainActor
struct StandingsMaskingWiringTests {
    @Test func worldsStandingsAreMaskedUntilRevealedAndLecIsNot() {
        let store = AppStore(preview: .withSeason)
        #expect(store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.lecSplit3.id))
        store.revealStandings(tournamentId: SeasonSamples.worlds.id)
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        #expect(!store.seasonMasked.isEmpty) // aucun match révélé
    }
}
```

- [ ] **Step 3: Écrire les textes**

Créer `App/Standings/StandingsTexts.swift` :

```swift
import Foundation
import LoLKit

/// Textes des tableaux (spec saison §3.5).
enum StandingsTexts {
    static func roundName(_ kind: StandingsTable.Round.Kind) -> String {
        switch kind {
        case .quarterFinal: String(localized: "Quarts de finale")
        case .semiFinal: String(localized: "Demi-finales")
        case .final: String(localized: "Finale")
        }
    }

    /// Équipe d'un tableau : son code, « À déterminer » pour l'équipe d'attente (`id "0"`, code « TBD »).
    static func teamLabel(_ team: MatchTeam) -> String {
        team.isPlaceholder || team.id == "0" ? String(localized: "À déterminer") : team.code
    }
}
```

- [ ] **Step 4: Écrire les tableaux**

Créer `App/Standings/StandingsTables.swift` :

```swift
import LoLKit
import SwiftUI

/// Classement d'une saison régulière : rang, équipe (lien vers sa page), bilan ; ligne teintée pour une équipe suivie.
struct StandingsTableCard: View {
    @Environment(AppStore.self) private var store
    let rows: [StandingsTable.Row]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows, id: \.team.id) { row in
                let followed = store.follows.team(id: row.team.id)
                TeamLink(teamId: row.team.id) {
                    HStack(spacing: 10) {
                        Text("\(row.ordinal)").sora(.stat).monospacedDigit().frame(width: 26, alignment: .trailing)
                        TeamBadge(code: row.team.code, logoFile: store.logoFile(for: row.team.image),
                                  tint: followed.map { Palette.team($0.colorHex) }, size: 28)
                        Text(row.team.name).sora(.bodyMedium).lineLimit(1)
                        Spacer()
                        Text(SeasonFormat.record(row.wins, row.losses)).sora(.stat).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(followed.map { Palette.team($0.colorHex).opacity(0.14) } ?? .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .foregroundStyle(Palette.text)
                .accessibilityElement(children: .combine)
            }
        }
        .glassCard(radius: Radius.inner, padding: 10)
    }
}

/// Système suisse : groupes par bilan (« 2-1 »), recalculés depuis les matchs terminés (`StandingsTable`).
struct SwissGroupsCard: View {
    @Environment(AppStore.self) private var store
    let groups: [StandingsTable.RecordGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.record) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.record).sora(.headline).monospacedDigit()
                    FlowRow(teams: group.teams)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Équipes d'un groupe, en pastilles qui passent à la ligne.
private struct FlowRow: View {
    @Environment(AppStore.self) private var store
    let teams: [MatchTeam]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                TeamLink(teamId: team.id) {
                    Chip(muted: store.tint(for: team) == nil) {
                        Text(StandingsTexts.teamLabel(team))
                    }
                }
            }
        }
    }
}

/// Tableau à élimination ou liste de matchs : tours nommés (quarts, demies, finale) ou matchs dans l'ordre de l'API,
/// chaque match avec ses deux équipes et son score (le tableau entier est déjà masqué ou révélé par `StandingsView`).
struct BracketCard: View {
    /// (nom du tour, ou nil pour une simple liste ; matchs).
    let rounds: [(name: String?, matches: [BracketMatch])]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rounds.enumerated()), id: \.offset) { _, round in
                VStack(alignment: .leading, spacing: 6) {
                    if let name = round.name {
                        Text(name).sora(.label).tracking(Typo.labelTracking).textCase(.uppercase)
                            .foregroundStyle(Palette.secondary)
                    }
                    ForEach(round.matches, id: \.id) { match in
                        BracketMatchRow(match: match)
                    }
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

private struct BracketMatchRow: View {
    let match: BracketMatch

    var body: some View {
        let teams = match.teams
        HStack {
            Text(teams.first.map(StandingsTexts.teamLabel) ?? "—").sora(.bodyMedium)
            Spacer()
            if match.state == .completed, teams.count == 2 {
                Text(Format.score(teams.map(\.gameWins))).sora(.stat).monospacedDigit()
            } else {
                Text("vs").sora(.secondary).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(teams.count > 1 ? StandingsTexts.teamLabel(teams[1]) : "—").sora(.bodyMedium)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 5: Écrire l'écran**

Remplacer tout le contenu de `App/Standings/StandingsView.swift` (coquille d'I1) par :

```swift
import LoLKit
import SwiftUI

/// Classements et tableaux d'un tournoi (spec saison §3.5) : saison régulière classée, système suisse, phase finale.
/// Masqué (une équipe suivie en anti-spoiler y figure avec un match masqué) : « Classement masqué · toucher pour
/// révéler » ; la révélation est mémorisée pour ce tournoi et ne révèle aucun match. Pas encore lu : une requête (au
/// rythme de la collecte), squelette en attendant ; rien : « Pas encore de classement pour ce tournoi ».
struct StandingsView: View {
    @Environment(AppStore.self) private var store
    let tournamentId: String
    @State private var attempted = false
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    var body: some View {
        let title = store.season.tournament(id: tournamentId).map(SeasonLabels.tournament) ?? String(localized: "Classement")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title, subtitle: String(localized: "Classement"))
                if let standings = store.season.standings[tournamentId] {
                    if store.isStandingsMasked(tournamentId: tournamentId) {
                        maskedCard
                    } else {
                        stages(standings)
                            .transition(Motion.revealTransition(reduceMotion: reduceMotion))
                    }
                } else if attempted {
                    NoteCard(icon: .standings, text: String(localized: "Pas encore de classement pour ce tournoi"))
                } else {
                    SeasonSkeletonCard(lines: 6, label: String(localized: "Classement en chargement"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
        .task {
            await store.season.loadStandings(tournamentId: tournamentId)
            attempted = true
        }
    }

    private var maskedCard: some View {
        Button {
            haptics.play(.reveal)
            withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
                store.revealStandings(tournamentId: tournamentId)
            }
        } label: {
            VStack(spacing: 8) {
                IconView(icon: .eyeOff, size: 22)
                Text("Classement masqué").sora(.headline)
                Text("toucher pour révéler").sora(.secondaryMedium).foregroundStyle(Palette.accent)
                Text("Révéler le classement ne révèle aucun match.").sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .glassCard()
    }

    @ViewBuilder private func stages(_ standings: Standings) -> some View {
        ForEach(StandingsTable.build(standings: standings), id: \.id) { stage in
            SectionLabel(text: stage.name)
            switch stage.content {
            case let .table(rows):
                if rows.isEmpty {
                    NoteCard(icon: .standings, text: String(localized: "Pas encore de classement pour cette étape"))
                } else {
                    StandingsTableCard(rows: rows)
                }
            case let .swiss(groups):
                SwissGroupsCard(groups: groups)
            case let .bracket(rounds):
                BracketCard(rounds: rounds.map { (StandingsTexts.roundName($0.kind), $0.matches) })
            case let .matches(matches):
                BracketCard(rounds: [(nil, matches)])
            }
        }
    }
}
```

- [ ] **Step 6: Écrire les planches**

Créer `Tests/FailleTests/StandingsSnapshotTests.swift` :

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func standings(_ tournamentId: String, store: AppStore) -> some View {
        NavigationStack { StandingsView(tournamentId: tournamentId) }.environment(store)
    }

    /// LEC Split 3 : saison régulière classée (KC 1er, ligne teintée), play-offs.
    @Test func leagueStandings() async throws {
        let url = try await Snapshot.write(standings(SeasonSamples.lecSplit3.id, store: AppStore(preview: .withSeason)),
                                           named: "29-classement")
        expectNotBlank(url)
    }

    /// Mondial : T1 (anti-spoiler) y figure avec des matchs masqués → « Classement masqué · toucher pour révéler ».
    @Test func maskedStandings() async throws {
        let url = try await Snapshot.write(standings(SeasonSamples.worlds.id, store: AppStore(preview: .withSeason)),
                                           named: "29b-classement-masque")
        expectNotBlank(url)
    }

    /// Mondial révélé : play-ins, système suisse à venir.
    @Test func revealedWorldsBracket() async throws {
        let store = AppStore(preview: .withSeason)
        store.revealStandings(tournamentId: SeasonSamples.worlds.id)
        let url = try await Snapshot.write(standings(SeasonSamples.worlds.id, store: store), named: "29c-tableau-mondial")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 7: Commit, push, CI une fois**

```bash
git add App/Standings Tests/FailleTests/StandingsTests.swift Tests/FailleTests/StandingsSnapshotTests.swift
git commit -m "feat(app): classements et tableaux — saison régulière, suisse, phase finale ; masqués tant qu'une équipe en anti-spoiler y a un match masqué, révélation par tournoi" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a6-classements
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

---

### Task A7: Calendrier complet

**Branche :** `nuit2/appli-a7-calendrier` · **Vague :** 4b · **Dépendances :** I1, L7 (`HomeFeed.followedMatchIds`), L8 fusionnées.

**Files:**
- Modify: `App/Calendar/SeasonCalendarView.swift` (coquille d'I1)
- Create: `App/Calendar/CalendarModel.swift`, `App/Calendar/MonthGrid.swift`
- Test: `Tests/FailleTests/CalendarTests.swift`, `Tests/FailleTests/CalendarSnapshotTests.swift` (planche `30-calendrier`)

**Interfaces:**
- Consumes : L8 `CalendarMonth.days(events:month:calendar:followed:now:)` (semaines entières, `CalendarDay.isInMonth/isToday/dayNumber/marker`), `CalendarMonth.events(on:in:calendar:)`, `CalendarMonth.pageNeeded(for:events:calendar:)`, `SchedulePageDirection`, `DayMarker` ; L7 `HomeFeed.followedMatchIds(_:follows:)` ; L1 `SchedulePageResult` (via `store.season.schedulePage(leagueIds:token:)`, A1) ; existants `ScheduleQuery.leagueIds`, `MatchLine`, `store.reveal`.
- Produces : `SeasonCalendarView()`, `enum CalendarEvents { merged(pages:schedule:live:), token(_:pages:) }`, `MonthGrid`.

- [ ] **Step 1: Relire le contrat L8**

```bash
git pull --ff-only origin main
grep -rn "public" LoLKit/Sources/LoLKit/Calendar/
```

Relevé à `4e37f00` : `CalendarMonth.days` rend des semaines entières (de `calendar.firstWeekday` : lundi en France) avec les jours hors du mois (`isInMonth` faux) ; `followed` = ids de match (`HomeFeed.followedMatchIds`) ; `pageNeeded` dit quelle page lire. Adapter si cela a bougé.

- [ ] **Step 2: Écrire les tests**

Créer `Tests/FailleTests/CalendarTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

/// Calendrier complet (spec saison §3.2) : matchs sans doublon, jeton de la page à lire.
struct CalendarEventsTests {
    private func page(_ events: [MatchEvent], older: String?, newer: String?) -> SchedulePageResult {
        SchedulePageResult(events: events, older: older, newer: newer)
    }

    private func event(_ id: String, _ start: String) -> MatchEvent {
        MatchEvent(startTime: SampleData.date(start), state: .completed, type: "match", blockName: nil,
                   league: SampleData.worlds, match: MatchInfo(id: id, teams: [], strategy: nil, games: nil),
                   streams: nil)
    }

    @Test func liveWinsOverTheScheduleAndPagesAddOlderMatches() {
        let merged = CalendarEvents.merged(pages: [page([event("m-old", "2026-09-01T12:00:00Z"), SampleData.kcLive],
                                                        older: "o", newer: nil)],
                                           schedule: SampleData.schedule, live: SampleData.live)
        #expect(merged.first?.id == "m-old")
        #expect(merged.filter { $0.id == SampleData.kcMatchId }.count == 1)
        #expect(Set(merged.map(\.id)).count == merged.count)
    }

    @Test func tokensComeFromTheFarthestPageInEachDirection() {
        let pages = [page(SampleData.schedule, older: "o1", newer: nil),
                     page([event("e", "2026-08-01T12:00:00Z")], older: "o2", newer: "n2")]
        #expect(CalendarEvents.token(.older, pages: pages) == "o2")
        #expect(CalendarEvents.token(.newer, pages: pages) == nil)
        #expect(CalendarEvents.token(.older, pages: []) == nil)
    }
}
```

- [ ] **Step 3: Écrire la logique**

Créer `App/Calendar/CalendarModel.swift` :

```swift
import Foundation
import LoLKit

/// Matchs du calendrier complet (spec saison §3.2) : ceux du calendrier de l'appli, du direct et des pages `older` /
/// `newer` lues pendant la session. Pur.
enum CalendarEvents {
    /// Sans doublon : le direct fait foi, puis le calendrier, puis les pages.
    static func merged(pages: [SchedulePageResult], schedule: [MatchEvent], live: [MatchEvent]?) -> [MatchEvent] {
        var byId: [String: MatchEvent] = [:]
        for event in pages.flatMap(\.events) + schedule + (live ?? []) {
            byId[event.id] = event
        }
        return byId.values.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
    }

    /// Jeton de la page à lire dans ce sens : `older` de la page aux matchs les plus anciens, `newer` de celle aux matchs
    /// les plus récents ; nil si rien de plus n'existe (`newer` nil = rien de plus récent) ou si aucune page n'est lue
    /// (lire d'abord la page 0).
    static func token(_ direction: SchedulePageDirection, pages: [SchedulePageResult]) -> String? {
        switch direction {
        case .older:
            pages.min { earliest($0) < earliest($1) }?.older
        case .newer:
            pages.max { latest($0) < latest($1) }?.newer
        }
    }

    private static func earliest(_ page: SchedulePageResult) -> Date {
        page.events.map(\.startTime).min() ?? .distantFuture
    }

    private static func latest(_ page: SchedulePageResult) -> Date {
        page.events.map(\.startTime).max() ?? .distantPast
    }
}
```

- [ ] **Step 4: Écrire la grille du mois**

Créer `App/Calendar/MonthGrid.swift` :

```swift
import LoLKit
import SwiftUI

/// Grille d'un mois (spec saison §3.2) : semaines entières de `CalendarMonth.days` (lundi en premier en France), jours
/// hors du mois estompés, pastille pleine = match suivi, anneau = international ; le jour choisi en blanc.
struct MonthGrid: View {
    let days: [CalendarDay]
    let calendar: Calendar
    @Binding var selected: Date?
    let onHaptic: (Haptic) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(Array(Self.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol).sora(.label).foregroundStyle(Palette.secondary)
            }
            ForEach(days) { day in
                cell(day)
            }
        }
    }

    private func cell(_ day: CalendarDay) -> some View {
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day.date) } ?? day.isToday
        return Button {
            if !isSelected { onHaptic(.gamePicked) }
            selected = day.date
        } label: {
            VStack(spacing: 3) {
                Text("\(day.dayNumber)").sora(.bodyMedium).monospacedDigit()
                switch day.marker {
                case .followed: Circle().fill(Palette.accent).frame(width: 5, height: 5)
                case .international: Circle().strokeBorder(Palette.accent, lineWidth: 1).frame(width: 5, height: 5)
                case .none: Color.clear.frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? Palette.abyss : Palette.text)
            .opacity(day.isInMonth ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Color.white.opacity(0.92) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(day.marker == .none ? Text("") : Text("Matchs suivis"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Initiales des jours, dans l'ordre de la locale (`firstWeekday`).
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
```

- [ ] **Step 5: Écrire l'écran**

Remplacer tout le contenu de `App/Calendar/SeasonCalendarView.swift` (coquille d'I1) par :

```swift
import LoLKit
import SwiftUI

/// Calendrier complet (spec saison §3.2) : vue mois des matchs du calendrier de l'appli (équipes et ligues suivies,
/// internationaux), liste du jour sous la grille (lignes anti-spoiler, révélables). Un mois hors du calendrier en cache
/// lit une page `older` / `newer` de `getSchedule` (`CalendarMonth.pageNeeded` ; ≈ 48 Ko, au rythme de la collecte),
/// gardée pour la session.
struct SeasonCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    @State private var month: Date?
    @State private var selected: Date?
    @State private var pages: [SchedulePageResult] = []
    @State private var loading = false
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    private var calendar: Calendar { .current }

    var body: some View {
        let now = fixedNow ?? Date()
        let shownMonth = month ?? now
        let events = CalendarEvents.merged(pages: pages, schedule: store.schedule, live: store.live)
        let days = CalendarMonth.days(events: events, month: shownMonth, calendar: calendar,
                                      followed: HomeFeed.followedMatchIds(events, follows: store.follows), now: now)
        let day = selected ?? now
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { move(-1, from: shownMonth) } label: {
                        IconView(icon: .back, size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Mois précédent"))
                    Spacer()
                    Text(shownMonth.formatted(.dateTime.month(.wide).year())).sora(.headline)
                    Spacer()
                    Button { move(1, from: shownMonth) } label: {
                        IconView(icon: .arrow, size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Mois suivant"))
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Palette.text)
                MonthGrid(days: days, calendar: calendar, selected: $selected, onHaptic: { haptics.play($0) })
                    .glassCard(radius: Radius.inner, padding: 12)
                if loading {
                    SeasonSkeletonCard(lines: 2, label: String(localized: "Calendrier en chargement"))
                }
                let list = CalendarMonth.events(on: day, in: events, calendar: calendar)
                SectionLabel(text: day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                if list.isEmpty {
                    NoteCard(icon: .calendar, text: String(localized: "Aucun match ce jour-là"))
                } else {
                    VStack(spacing: 2) {
                        ForEach(list) { event in
                            MatchLine(event: event, onReveal: reveal)
                        }
                    }
                    .glassCard(radius: Radius.inner, padding: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationTitle(String(localized: "Calendrier"))
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
        .task(id: month) { await loadIfNeeded(shownMonth) }
    }

    private func move(_ delta: Int, from current: Date) {
        haptics.play(.gamePicked)
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) {
            month = calendar.date(byAdding: .month, value: delta, to: current)
            selected = nil
        }
    }

    /// Mois hors du calendrier connu : la page 0 (pour ses jetons), puis `older` / `newer` jusqu'à le couvrir (3 pages au
    /// plus par mois demandé ; aucune quand `newer` est nil : rien de plus récent).
    private func loadIfNeeded(_ month: Date) async {
        let ids = ScheduleQuery.leagueIds(follows: store.follows, leagues: store.leagues)
        var attempts = 0
        while attempts < 3, let direction = CalendarMonth.pageNeeded(
            for: month, events: CalendarEvents.merged(pages: pages, schedule: store.schedule, live: store.live),
            calendar: calendar) {
            attempts += 1
            loading = true
            defer { loading = false }
            if pages.isEmpty {
                guard let first = await store.season.schedulePage(leagueIds: ids, token: nil) else { return }
                pages.append(first)
                continue
            }
            guard let token = CalendarEvents.token(direction, pages: pages),
                  let page = await store.season.schedulePage(leagueIds: ids, token: token) else { return }
            pages.append(page)
        }
    }

    private func reveal(_ matchId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) { store.reveal(matchId: matchId) }
    }
}
```

- [ ] **Step 6: Écrire la planche**

Créer `Tests/FailleTests/CalendarSnapshotTests.swift` :

```swift
import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Octobre 2026 (spec saison §3.2) : pastilles des jours de matchs suivis, liste du 15 (KC – C9, T1 – FLY masqué :
    /// « En direct » sans score).
    @Test func calendarMonth() async throws {
        let view = NavigationStack { SeasonCalendarView() }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        let url = try await Snapshot.write(view, named: "30-calendrier")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 7: Commit, push, CI une fois**

```bash
git add App/Calendar Tests/FailleTests/CalendarTests.swift Tests/FailleTests/CalendarSnapshotTests.swift
git commit -m "feat(app): calendrier complet — vue mois, liste du jour anti-spoiler, pages older/newer de getSchedule au rythme de la collecte" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a7-calendrier
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

---

### Task A8: Ligues suivies (interface)

**Branche :** `nuit2/appli-a8-ligues` · **Vague :** 4b · **Dépendances :** I1, L5 fusionnées.

**Files:**
- Create: `App/Leagues/LeagueRows.swift`, `App/Leagues/LeagueFollowRow.swift`, `App/Leagues/LeaguesSection.swift`
- Test: `Tests/FailleTests/LeaguesTests.swift`, `Tests/FailleTests/LeaguesSnapshotTests.swift` (planche `31-ligues`)

**Interfaces:**
- Consumes : L5 `FollowedLeague(id:slug:name:image:notifyStarts:)`, `FollowList(teams:leagues:)`, `FollowList.leagues` ; I1 (`toggleFollowLeague`, `followAllTeams(in:)`, `setLeagueNotifications`, `currentTournamentId(leagueId:)`, `maskedLatestTeamIds`, `MatchLine`, `StandingsRoute`) ; existants `TeamDirectory` (`store.teams(in:)`), `PillButton`.
- Produces (branchés par I2) : `LeagueFollowRow(league:followed:notifies:teamCount:allTeamsFollowed:onToggleFollow:onFollowAll:onToggleNotifications:)` (onglet Équipes, sous les pilules), `LeaguesSection(rows:)` + `LeaguesSection.rows(store:now:)` (onglet Matchs), `struct LeagueRowContent`, `enum LeagueRows`.

- [ ] **Step 1: Relire le contrat L5**

```bash
git pull --ff-only origin main
grep -n "FollowedLeague\|leagues\|League(" LoLKit/Sources/LoLKit/Follow/FollowList.swift
```

- [ ] **Step 2: Écrire les tests**

Créer `Tests/FailleTests/LeaguesTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

private let now = SampleData.date("2026-10-15T15:05:00Z")

private func upcoming(_ id: String, _ start: String, _ a: (String, String), _ b: (String, String),
                      league: LeagueRef = SampleData.worlds) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: .unstarted, type: "match", blockName: nil, league: league,
               match: MatchInfo(id: id, teams: [MatchTeam(id: a.0, name: a.1, code: a.0.uppercased(), image: nil, result: nil),
                                                MatchTeam(id: b.0, name: b.1, code: b.0.uppercased(), image: nil, result: nil)],
                                strategy: Strategy(type: "bestOf", count: 3), games: nil),
               streams: nil)
}

struct LeagueRowsTests {
    @Test func leagueRowHidesANextMatchAgainstAMaskedSpoilerFreeTeam() {
        let lck = FollowedLeague(id: "lck-id", slug: "lck", name: "LCK")
        let league = LeagueRef(id: "lck-id", slug: "lck", name: "LCK", image: nil)
        let match = upcoming("n", "2026-10-16T08:00:00Z", ("t1", "T1"), ("hle", "HLE"), league: league)
        let follows = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)], leagues: [lck])
        let hidden = LeagueRows.rows(follows: follows, schedule: [match], revealed: [], maskedLatestTeamIds: ["t1"],
                                     currentTournamentIds: [:], now: now)
        #expect(hidden.map(\.next) == [.hidden])
        let shown = LeagueRows.rows(follows: follows, schedule: [match], revealed: [], maskedLatestTeamIds: [],
                                    currentTournamentIds: ["lck-id": "t-lck"], now: now)
        #expect(shown.map(\.next) == [.match(match)])
        #expect(shown.first?.tournamentId == "t-lck")
    }
}
```

- [ ] **Step 3: Écrire la logique**

Créer `App/Leagues/LeagueRows.swift` :

```swift
import Foundation
import LoLKit

/// Une ligne de la section « Ligues » de l'onglet Matchs (spec saison §3.5).
struct LeagueRowContent: Equatable, Sendable, Identifiable {
    enum Next: Equatable, Sendable {
        case match(MatchEvent)
        /// Le prochain match oppose une équipe suivie en anti-spoiler dont le dernier match est masqué (règle C).
        case hidden
        case none
    }

    let league: FollowedLeague
    let next: Next
    /// Tournoi en cours de la ligue (lien « Classement ») ; nil tant qu'il n'est pas connu.
    let tournamentId: String?
    var id: String { league.id }
}

enum LeagueRows {
    static func rows(follows: FollowList, schedule: [MatchEvent], revealed: Set<String>,
                     maskedLatestTeamIds: Set<String>, currentTournamentIds: [String: String], now: Date) -> [LeagueRowContent] {
        follows.leagues.map { league in
            let upcoming = schedule
                .filter { $0.league.slug == league.slug && $0.state == .unstarted && $0.startTime >= now }
                .min { $0.startTime < $1.startTime }
            let next: LeagueRowContent.Next
            if let upcoming {
                let rulesC = !revealed.contains(upcoming.id) && follows.followed(in: upcoming.match.teams).contains {
                    $0.spoilerFree && maskedLatestTeamIds.contains($0.id)
                }
                next = rulesC ? .hidden : .match(upcoming)
            } else {
                next = .none
            }
            return LeagueRowContent(league: league, next: next, tournamentId: currentTournamentIds[league.id])
        }
    }
}
```

- [ ] **Step 4: Écrire la ligne « Suivre la ligue »**

Créer `App/Leagues/LeagueFollowRow.swift` :

```swift
import LoLKit
import SwiftUI

/// Sous les pilules de « Toutes les ligues » (spec saison §3.5) : « Suivre la ligue » (étoile), « Suivre ses N
/// équipes », et pour une ligue suivie l'interrupteur des notifications de début de ses matchs (désactivées par défaut).
struct LeagueFollowRow: View {
    let league: League
    let followed: Bool
    let notifies: Bool
    let teamCount: Int
    let allTeamsFollowed: Bool
    let onToggleFollow: () -> Void
    let onFollowAll: () -> Void
    let onToggleNotifications: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onToggleFollow) {
                    HStack(spacing: 6) {
                        IconView(icon: followed ? .starFill : .star, size: 18)
                            .foregroundStyle(followed ? Palette.accent : Palette.secondary)
                        (followed ? Text("Ligue suivie") : Text("Suivre la ligue")).sora(.bodyMedium)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(followed ? Text("Ne plus suivre \(league.name)") : Text("Suivre \(league.name)"))
                Spacer()
                if teamCount > 0, !allTeamsFollowed {
                    Button(action: onFollowAll) {
                        Text("Suivre ses \(teamCount) équipes").sora(.secondaryMedium).foregroundStyle(Palette.accent)
                            .frame(minHeight: 44)
                    }
                }
            }
            if followed {
                Toggle(isOn: Binding(get: { notifies }, set: onToggleNotifications)) {
                    Text("Prévenir au début de ses matchs").sora(.secondary)
                }
                .tint(Palette.accent)
            }
        }
        .buttonStyle(.pressable)
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 12)
    }
}
```

- [ ] **Step 5: Écrire la section « Ligues » de l'onglet Matchs**

Créer `App/Leagues/LeaguesSection.swift` :

```swift
import LoLKit
import SwiftUI

/// Section « Ligues » de l'onglet Matchs (spec saison §3.5), après les cartes : une ligne par ligue suivie — prochain
/// match (anti-spoiler : « Prochain · masqué » selon la règle C), lien « Classement » du tournoi en cours. Aucune ligue
/// suivie : la section n'existe pas.
struct LeaguesSection: View {
    let rows: [LeagueRowContent]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: String(localized: "Ligues"))
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.league.name).sora(.headline)
                            Spacer()
                            if let tournamentId = row.tournamentId {
                                NavigationLink(value: StandingsRoute(tournamentId: tournamentId)) {
                                    HStack(spacing: 4) {
                                        IconView(icon: .standings, size: 13)
                                        Text("Classement")
                                    }
                                    .sora(.secondaryMedium)
                                    .foregroundStyle(Palette.accent)
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        switch row.next {
                        case let .match(event):
                            MatchLine(event: event, showsDay: true)
                        case .hidden:
                            HStack(spacing: 6) {
                                IconView(icon: .eyeOff, size: 13)
                                Text("Prochain · masqué")
                            }
                            .sora(.secondary)
                            .foregroundStyle(Palette.secondary)
                        case .none:
                            Text("Aucun match à venir dans le calendrier").sora(.secondary)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .foregroundStyle(Palette.text)
                    .glassCard(radius: Radius.inner, padding: 12)
                }
            }
        }
    }

    /// Lignes depuis le store (I2 les passe à la section).
    @MainActor
    static func rows(store: AppStore, now: Date = Date()) -> [LeagueRowContent] {
        let current = Dictionary(uniqueKeysWithValues: store.follows.leagues.compactMap { league in
            store.currentTournamentId(leagueId: league.id, now: now).map { (league.id, $0) }
        })
        return LeagueRows.rows(follows: store.follows, schedule: store.schedule, revealed: store.settings.revealedMatchIds,
                               maskedLatestTeamIds: store.maskedLatestTeamIds, currentTournamentIds: current, now: now)
    }
}
```

- [ ] **Step 6: Écrire la planche**

Créer `Tests/FailleTests/LeaguesSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Ligues (spec saison §3.5) : « Suivre la ligue » / « Suivre ses N équipes » (LEC non suivie), ligue suivie avec
    /// l'interrupteur des notifications (Mondial), section « Ligues » de l'onglet Matchs (prochain match, Classement).
    @Test func leagues() async throws {
        var data = PreviewData.withSeason
        let worlds = SampleData.leagues[0]
        data.follows = FollowList(teams: SampleData.follows.teams,
                                  leagues: [FollowedLeague(id: worlds.id, slug: worlds.slug, name: worlds.name, image: nil,
                                                           notifyStarts: true)])
        let store = AppStore(preview: data)
        let now = SampleData.date("2026-10-15T15:05:00Z")
        let view = NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LeagueFollowRow(league: SampleData.leagues[2], followed: false, notifies: false, teamCount: 2,
                                    allTeamsFollowed: false, onToggleFollow: {}, onFollowAll: {},
                                    onToggleNotifications: { _ in })
                    LeagueFollowRow(league: worlds, followed: true, notifies: true, teamCount: 11,
                                    allTeamsFollowed: false, onToggleFollow: {}, onFollowAll: {},
                                    onToggleNotifications: { _ in })
                    LeaguesSection(rows: LeaguesSection.rows(store: store, now: now))
                }
                .padding(16)
            }
            .abyssBackground()
        }
        .environment(store)
        let url = try await Snapshot.write(view, named: "31-ligues")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 7: Commit, push, CI une fois**

```bash
git add App/Leagues Tests/FailleTests/LeaguesTests.swift Tests/FailleTests/LeaguesSnapshotTests.swift
git commit -m "feat(app): ligues suivies — suivre la ligue ou ses équipes, notifications de début, section Ligues (prochain match anti-spoiler, classement)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a8-ligues
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

---

### Task A9: Premier lancement (onboarding)

**Branche :** `nuit2/appli-a9-onboarding` · **Vague :** 2 (avant I1 : n'utilise ni `.sora`, ni les composants, ni les icônes d'I1 — P2 migrera ses textes vers `.sora`) · **Dépendances :** L1 fusionnée (types des classements). Branchement (`fullScreenCover`, `AppSettings.onboardingDone`) : I2.

**Files:**
- Create: `App/Onboarding/OnboardingModel.swift`, `App/Onboarding/OnboardingView.swift`, `App/Onboarding/OnboardingPages.swift`, `App/Onboarding/OnboardingExampleCard.swift`
- Test: `Tests/FailleTests/OnboardingTests.swift`, `Tests/FailleTests/OnboardingSnapshotTests.swift` (planches `32-onboarding-1`, `32-onboarding-2`, `32-onboarding-3`)

**Interfaces:**
- Consumes : L1 `Standings` et types liés ; existants `Team`, `League`, `TeamBadge`, `PillButton`, `Chip`, `.glassCard`, `Palette`, `Typo`, `IconView` (`star`, `starFill`, `eye`, `eyeOff`, `live`, `swords`, `gold`, `tower`, `search`), `Motion`, `@ReduceMotion`, `HapticTrigger`, `.abyssBackground()`.
- Produces : `OnboardingView(teams:leagues:followedTeams:followedLeagueIds:spoilerFreeIds:search:onToggleTeam:onToggleLeague:onSetSpoilerFree:onDone:initialPage:)` (vue à fermetures, sans `AppStore`), `enum OnboardingModel { worldsTeams(catalog:worldsStandings:fallback:) }`, `OnboardingExampleCard`.

- [ ] **Step 1: Écrire les tests de la logique**

Créer `Tests/FailleTests/OnboardingTests.swift` :

```swift
import Foundation
import LoLKit
import Testing
@testable import Faille

struct OnboardingModelTests {
    private static func team(_ id: String, _ name: String) -> Team {
        Team(id: id, slug: id, name: name, code: id.uppercased(), image: nil, status: "active", homeLeague: nil)
    }

    private static func side(_ id: String) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id == "0" ? "TBD" : id.uppercased(), image: nil, result: nil)
    }

    private let catalog = [team("t1", "T1"), team("kc", "Karmine Corp"), team("g2", "G2 Esports"), team("fly", "FlyQuest")]

    /// Équipes du Mondial : celles des classements (jamais l'équipe « TBD » d'id « 0 »), par nom.
    @Test func worldsTeamsComeFromTheStandings() {
        let standings = Standings(stages: [StandingsStage(id: "s", name: "Système suisse", slug: "swiss", sections: [
            StandingsSection(name: "Suisse", matches: [
                BracketMatch(id: "m1", state: .completed, teams: [Self.side("t1"), Self.side("kc")]),
                BracketMatch(id: "m2", state: .unstarted, teams: [Self.side("g2"), Self.side("0")]),
            ], rankings: []),
        ])])
        let teams = OnboardingModel.worldsTeams(catalog: catalog, worldsStandings: standings, fallback: [])
        #expect(teams.map(\.id) == ["g2", "kc", "t1"])
    }

    /// Sans classement (pas encore lu) : les équipes que l'annuaire rattache au Mondial.
    @Test func withoutStandingsTheDirectoryIsTheFallback() {
        let teams = OnboardingModel.worldsTeams(catalog: catalog, worldsStandings: nil, fallback: [catalog[3], catalog[1]])
        #expect(teams.map(\.id) == ["fly", "kc"])
    }
}
```

- [ ] **Step 2: Écrire la logique**

Créer `App/Onboarding/OnboardingModel.swift` :

```swift
import Foundation
import LoLKit

enum OnboardingModel {
    /// Équipes du Mondial 2026 (spec saison §3.7) : celles des classements du Mondial (ids réels, jamais « TBD »), trouvées
    /// dans le catalogue ; à défaut, celles que `TeamDirectory` rattache au Mondial (catalogue + calendrier). Par nom.
    static func worldsTeams(catalog: [Team], worldsStandings: Standings?, fallback: [Team]) -> [Team] {
        let ids = Set((worldsStandings?.stages ?? [])
            .flatMap { $0.sections.flatMap { $0.matches.flatMap(\.teams) } }
            .compactMap(\.id)
            .filter { $0 != "0" })
        let fromStandings = catalog.filter { ids.contains($0.id) }
        let teams = fromStandings.isEmpty ? fallback : fromStandings
        return teams.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
```

- [ ] **Step 3: Écrire l'exemple vivant**

Créer `App/Onboarding/OnboardingExampleCard.swift` :

```swift
import SwiftUI

/// Exemple vivant du premier écran (spec saison §3.7) : une carte Vitrail d'aperçu, étiquetée « Exemple », dont le chrono
/// et les kills avancent (une seconde par seconde, un kill toutes les 6 s) ; figée sous « Réduire les animations ». Rien
/// de réel : aucune donnée, aucune requête.
struct OnboardingExampleCard: View {
    @ReduceMotion var reduceMotion
    /// Départ du chrono d'exemple : 18:42 de jeu.
    private static let clockStart: TimeInterval = 18 * 60 + 42

    var body: some View {
        if Motion.runs(.livePulse, reduceMotion: reduceMotion) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(elapsed: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120))
            }
        } else {
            card(elapsed: 0)
        }
    }

    private func card(elapsed: TimeInterval) -> some View {
        let clock = Int(Self.clockStart + elapsed)
        let kills = 7 + Int(elapsed / 6) % 4
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mondial · Play-in · Bo5").font(Typo.secondary).foregroundStyle(Palette.secondary)
                Spacer()
                Chip { Text("Exemple") }
            }
            HStack(spacing: 8) {
                TeamBadge(code: "KC", tint: Palette.accent, size: 34)
                Text("KC").font(Typo.headline)
                Spacer()
                Text("1 – 0").font(Typo.scoreLarge).monospacedDigit()
                Spacer()
                Text("C9").font(Typo.headline)
                TeamBadge(code: "C9", size: 34)
            }
            HStack(spacing: 14) {
                Chip {
                    IconView(icon: .live, size: 12)
                    Text("Game 2 · \(clock / 60):\(String(format: "%02d", clock % 60))").monospacedDigit()
                }
                Label { Text("\(kills)").monospacedDigit() } icon: { IconView(icon: .swords, size: 13) }
                Label { Text("+2,1 k").monospacedDigit() } icon: { IconView(icon: .gold, size: 13) }
                Label { Text("3").monospacedDigit() } icon: { IconView(icon: .tower, size: 13) }
            }
            .font(Typo.secondaryMedium)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: Palette.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Exemple de carte : Karmine Corp 1, Cloud9 0, game 2 en direct"))
    }
}
```

- [ ] **Step 4: Écrire les trois pages**

Créer `App/Onboarding/OnboardingPages.swift` :

```swift
import LoLKit
import SwiftUI

/// Page 1 : « Ton compagnon de saison LoL esport », l'exemple vivant.
struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ton compagnon de saison LoL esport")
                .font(Typo.title).tracking(Typo.titleTracking)
            Text("Les matchs en direct, les résultats, les stats de saison de tes équipes et de leurs joueurs, au même endroit.")
                .font(Typo.body).foregroundStyle(Palette.secondary)
            OnboardingExampleCard()
        }
        .foregroundStyle(Palette.text)
    }
}

/// Page 2 : « Choisis tes équipes ou une ligue » — pilules de ligues, recherche, équipes du Mondial en grille de logos ;
/// toucher = suivre tout de suite.
struct OnboardingPickPage: View {
    let teams: [Team]
    let leagues: [League]
    let followedTeamIds: Set<String>
    let followedLeagueIds: Set<String>
    let search: (String) -> [Team]
    let onToggleTeam: (Team) -> Void
    let onToggleLeague: (League) -> Void
    @State private var query = ""

    var body: some View {
        let shown = query.trimmingCharacters(in: .whitespaces).isEmpty ? teams : search(query)
        VStack(alignment: .leading, spacing: 14) {
            Text("Choisis tes équipes ou une ligue").font(Typo.title).tracking(Typo.titleTracking)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(leagues) { league in
                        PillButton(selected: followedLeagueIds.contains(league.id), action: { onToggleLeague(league) }) {
                            if followedLeagueIds.contains(league.id) { IconView(icon: .starFill, size: 11) }
                            Text(league.name)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 8) {
                IconView(icon: .search, size: 16).foregroundStyle(Palette.secondary)
                TextField("", text: $query, prompt: Text("Rechercher une équipe").foregroundStyle(Palette.secondary))
                    .font(Typo.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            if query.isEmpty {
                Text("Équipes du Mondial").font(Typo.label).tracking(Typo.labelTracking).textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(shown.prefix(40)) { team in
                    teamCell(team, followed: followedTeamIds.contains(team.id))
                }
            }
        }
        .foregroundStyle(Palette.text)
    }

    private func teamCell(_ team: Team, followed: Bool) -> some View {
        Button { onToggleTeam(team) } label: {
            VStack(spacing: 6) {
                TeamBadge(code: team.code, tint: followed ? Palette.accent : nil, size: 46)
                Text(team.name).font(Typo.secondaryMedium).lineLimit(1).minimumScaleFactor(0.8)
                IconView(icon: followed ? .starFill : .star, size: 14)
                    .foregroundStyle(followed ? Palette.accent : Palette.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(Color.white.opacity(followed ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(followed ? Palette.accent : Palette.glassBorder,
                                                                     lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(team.name))
        .accessibilityValue(followed ? Text("Suivie") : Text("Pas suivie"))
        .accessibilityHint(followed ? Text("Ne plus suivre") : Text("Suivre"))
    }
}

/// Page 3 : « Pas de spoiler si tu veux » — la phrase, et un interrupteur par équipe choisie.
struct OnboardingSpoilerPage: View {
    let chosen: [Team]
    let spoilerFreeIds: Set<String>
    let onSetSpoilerFree: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pas de spoiler si tu veux").font(Typo.title).tracking(Typo.titleTracking)
            HStack(alignment: .top, spacing: 10) {
                IconView(icon: .eyeOff, size: 22).foregroundStyle(Palette.accent)
                Text("L'œil cache les scores d'une équipe jusqu'à ce que tu choisisses de les voir.")
                    .font(Typo.body)
            }
            .glassCard(radius: Radius.inner, padding: 14)
            if chosen.isEmpty {
                Text("Tu pourras l'activer plus tard dans l'onglet Équipes.").font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(chosen) { team in
                        Toggle(isOn: Binding(get: { spoilerFreeIds.contains(team.id) },
                                             set: { onSetSpoilerFree(team.id, $0) })) {
                            HStack(spacing: 10) {
                                TeamBadge(code: team.code, size: 30)
                                Text(team.name).font(Typo.bodyMedium)
                            }
                        }
                        .tint(Palette.accent)
                        .frame(minHeight: 44)
                    }
                }
                .glassCard(radius: Radius.inner, padding: 12)
            }
        }
        .foregroundStyle(Palette.text)
    }
}
```

- [ ] **Step 5: Écrire l'écran**

Créer `App/Onboarding/OnboardingView.swift` :

```swift
import LoLKit
import SwiftUI

/// Premier lancement (spec saison §3.7) : 3 écrans, « Passer » partout, points de pagination, glissement d'une page à
/// l'autre (`Motion.snappy` ; fondu sous « Réduire les animations »). Vue à fermetures : elle ne connaît pas `AppStore`
/// (I2 la branche en `fullScreenCover`). « C'est parti » ou « Passer » → `onDone` (Accueil).
struct OnboardingView: View {
    let teams: [Team]
    let leagues: [League]
    /// Équipes suivies (du catalogue), pour les étoiles de la page 2 et les interrupteurs de la page 3.
    let followedTeams: [Team]
    let followedLeagueIds: Set<String>
    let spoilerFreeIds: Set<String>
    let search: (String) -> [Team]
    let onToggleTeam: (Team) -> Void
    let onToggleLeague: (League) -> Void
    let onSetSpoilerFree: (String, Bool) -> Void
    let onDone: () -> Void
    @State private var page: Int
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    init(teams: [Team], leagues: [League], followedTeams: [Team], followedLeagueIds: Set<String>,
         spoilerFreeIds: Set<String>, search: @escaping (String) -> [Team], onToggleTeam: @escaping (Team) -> Void,
         onToggleLeague: @escaping (League) -> Void, onSetSpoilerFree: @escaping (String, Bool) -> Void,
         onDone: @escaping () -> Void, initialPage: Int = 0) {
        self.teams = teams
        self.leagues = leagues
        self.followedTeams = followedTeams
        self.followedLeagueIds = followedLeagueIds
        self.spoilerFreeIds = spoilerFreeIds
        self.search = search
        self.onToggleTeam = onToggleTeam
        self.onToggleLeague = onToggleLeague
        self.onSetSpoilerFree = onSetSpoilerFree
        self.onDone = onDone
        _page = State(initialValue: min(max(initialPage, 0), 2))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Passer").font(Typo.bodyMedium).foregroundStyle(Palette.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 16)
            ScrollView {
                Group {
                    switch page {
                    case 0:
                        OnboardingWelcomePage()
                    case 1:
                        OnboardingPickPage(teams: teams, leagues: leagues, followedTeamIds: followedTeamIds,
                                           followedLeagueIds: followedLeagueIds, search: search,
                                           onToggleTeam: toggle, onToggleLeague: toggle)
                    default:
                        OnboardingSpoilerPage(chosen: followedTeams, spoilerFreeIds: spoilerFreeIds, onSetSpoilerFree: { id, on in
                            haptics.play(.spoilerToggle)
                            onSetSpoilerFree(id, on)
                        })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                    removal: .opacity))
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { go(page + 1) }
                if value.translation.width > 60 { go(page - 1) }
            })
            footer
        }
        .abyssBackground()
        .haptics(haptics)
    }

    private var followedTeamIds: Set<String> {
        Set(followedTeams.map(\.id))
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Palette.accent : Color.white.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(page + 1) sur 3"))
            Button { page == 2 ? onDone() : go(page + 1) } label: {
                Group {
                    if page == 2 { Text("C'est parti") } else { Text("Continuer") }
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.abyss)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func go(_ target: Int) {
        guard (0...2).contains(target), target != page else { return }
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { page = target }
    }

    private func toggle(_ team: Team) {
        haptics.play(followedTeamIds.contains(team.id) ? .unfollow : .follow)
        onToggleTeam(team)
    }

    private func toggle(_ league: League) {
        haptics.play(followedLeagueIds.contains(league.id) ? .unfollow : .follow)
        onToggleLeague(league)
    }
}
```

- [ ] **Step 6: Écrire les planches**

Créer `Tests/FailleTests/OnboardingSnapshotTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    private func onboarding(page: Int) -> some View {
        OnboardingView(teams: Array(SampleData.catalog.prefix(8)), leagues: SampleData.leagues,
                       followedTeams: SampleData.catalog.filter { ["kc", "t1"].contains($0.id) }, followedLeagueIds: [SampleData.leagues[2].id],
                       spoilerFreeIds: ["t1"], search: { _ in [] }, onToggleTeam: { _ in }, onToggleLeague: { _ in },
                       onSetSpoilerFree: { _, _ in }, onDone: {}, initialPage: page)
    }

    /// Les trois écrans du premier lancement (spec saison §3.7) : exemple vivant (figé), choix des équipes et ligues
    /// (KC, T1 et la LEC suivies), anti-spoiler (T1 masquée).
    @Test func onboardingPages() async throws {
        for page in 0..<3 {
            let url = try await Snapshot.write(onboarding(page: page), named: "32-onboarding-\(page + 1)")
            expectNotBlank(url)
        }
    }
}
```

- [ ] **Step 7: Commit, push, CI une fois**

```bash
git add App/Onboarding Tests/FailleTests/OnboardingTests.swift Tests/FailleTests/OnboardingSnapshotTests.swift
git commit -m "feat(app): premier lancement — exemple vivant, choix des équipes du Mondial et des ligues, anti-spoiler en une phrase (vues à fermetures)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-a9-onboarding
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

(La CI de cette branche n'existe que si l'étape 0 d'I1 est déjà sur `main` : le contrôleur la pousse au début du lot.)

---

### Task I2: Intégration 2 — branchements dans les écrans existants

**Branche :** `nuit2/appli-i2-integration` · **Vague :** 5 · **Dépendances :** A2 à A9 fusionnées (chaque pas ci-dessous ne s'applique que si la tâche qu'il branche est dans `main` ; une tâche coupée est simplement non branchée, et son pas est noté « non fait (coupe) » dans le journal).

**Files:**
- Modify: `App/Detail/MatchDetailView.swift` (A4, A2), `App/Matches/TeamCardView.swift` (A2), `App/Teams/TeamRows.swift` (A2), `App/Teams/TeamsView.swift` (A8), `App/Matches/MatchesView.swift` (A3, A8), `App/RootView.swift` (A9 ; ancres = texte laissé par I1), `docs/superpowers/notes/2026-10-14-checklist-iphone.md`
- Test: `Tests/FailleTests/SeasonWiringTests.swift` (planches `33-detail-duel`, `33b-matchs-saison`)

**Interfaces:**
- Consumes : `DuelSection(matchId:teams:selectedGameId:masked:)` (A4), `TeamTapZones`, `TeamLink` (I1), `MustWatchSection(picks:style:)`, `AppStore.mustWatchPicks(limit:)` (A3), `LeagueFollowRow`, `LeaguesSection(rows:)`, `LeaguesSection.rows(store:)` (A8), `OnboardingView(…)`, `OnboardingModel.worldsTeams` (A9), `AppStore.showsOnboarding`, `completeOnboarding`, `toggleFollowLeague`, `followAllTeams(in:)`, `setLeagueNotifications`, `currentTournamentId` (I1).
- Produces : écrans existants branchés ; `RootView.presentsOnboarding(store:hasRouter:)`.

- [ ] **Step 1: Mettre la branche à jour et relire les ancres**

```bash
git pull --ff-only origin main
git log --oneline -20 | grep -E "nuit2/appli|feat\(app\)"
```

Relire chaque ancre ci-dessous dans son fichier à la tête de la branche (obligatoire) ; pour `RootView.swift`, les ancres sont celles qu'I1 a laissées (ce plan, Task I1, étape 12).

- [ ] **Step 2: Écrire les tests et les planches**

Créer `Tests/FailleTests/SeasonWiringTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Branchements de la saison dans les écrans existants (spec saison §2.1, §3.3, §3.5, §3.6, §3.7).
@MainActor
struct SeasonWiringTests {
    /// L'onboarding ne s'ouvre que dans l'appli (routeur de notifications présent), au premier lancement.
    @Test func onboardingIsPresentedOnlyInTheAppAtFirstLaunch() {
        let fresh = AppStore(transport: StubTransport(), files: TemporaryFiles.store())
        #expect(RootView.presentsOnboarding(store: fresh, hasRouter: true))
        #expect(!RootView.presentsOnboarding(store: fresh, hasRouter: false))   // aperçus et tests
        fresh.completeOnboarding()
        #expect(!RootView.presentsOnboarding(store: fresh, hasRouter: true))
        #expect(!RootView.presentsOnboarding(store: AppStore(preview: .standard), hasRouter: true)) // suivis : non
        fresh.endScene()
    }
}

extension ApercuTests {
    /// Détail de KC 1 – 3 G2 (game 4, révélé) avec la section « Duel » sous les stats (spec saison §3.3) : composition de
    /// la game, ligne « Cette game ».
    @Test func detailWithDuel() async throws {
        let view = NavigationStack { MatchDetailView(matchId: SampleData.kcG2MatchId) }
            .environment(AppStore(preview: .withSeason))
        let url = try await Snapshot.write(view.defaultScrollAnchor(.bottom), named: "33-detail-duel")
        expectNotBlank(url)
    }

    /// Onglet Matchs avec « À ne pas rater » en tête et la section « Ligues » (Mondial suivi).
    @Test func matchesWithMustWatchAndLeagues() async throws {
        var data = PreviewData.withSeason
        let worlds = SampleData.leagues[0]
        data.follows = FollowList(teams: SampleData.follows.teams,
                                  leagues: [FollowedLeague(id: worlds.id, slug: worlds.slug, name: worlds.name, image: nil,
                                                           notifyStarts: false)])
        let url = try await Snapshot.write(RootView(tab: .matches).environment(AppStore(preview: data)),
                                           named: "33b-matchs-saison")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 3: Détail — équipes touchables et section « Duel » (A2, A4)**

Dans `App/Detail/MatchDetailView.swift`, remplacer :

```swift
            ScoreRow(teams: teams, score: seriesScore(event: event, state: state, order: order, masked: masked),
                     tints: teams.map { store.tint(for: $0) }, large: true)
```

par :

```swift
            ScoreRow(teams: teams, score: seriesScore(event: event, state: state, order: order, masked: masked),
                     tints: teams.map { store.tint(for: $0) }, large: true)
                // Toucher une équipe → sa page (spec saison §2.1) ; le score, au centre, reste inerte.
                .overlay { TeamTapZones(teams: teams) }
```

Remplacer :

```swift
        if showsPinButton(event: event) {
            LiveActivityPinButton(matchId: model.matchId, onHaptic: { haptics.play($0) })
        }
```

par :

```swift
        // Duel (spec saison §3.3), match à venir ou joué : masqué → stats de saison seulement (ni composition ni ligne
        // « Cette game » de ce match) ; sinon la composition de la game affichée si elle est jouée.
        DuelSection(matchId: model.matchId, teams: ordered,
                    selectedGameId: details.flatMap { model.selectedGame(in: $0) }
                        .flatMap { $0.state == .completed ? $0.id : nil },
                    masked: masked)
        if showsPinButton(event: event) {
            LiveActivityPinButton(matchId: model.matchId, onHaptic: { haptics.play($0) })
        }
```

- [ ] **Step 4: Cartes — l'en-tête ouvre la page d'équipe (A2)**

Dans `App/Matches/TeamCardView.swift`, remplacer :

```swift
            SectionLabel(text: header, dot: tint)
```

par :

```swift
            // Toucher l'équipe → sa page (spec saison §2.1).
            TeamLink(teamId: card.team.id) {
                SectionLabel(text: header, dot: tint)
            }
```

- [ ] **Step 5: Équipes — toucher une ligne ouvre la page (A2)**

Dans `App/Teams/TeamRows.swift`, remplacer (ligne de « Mes équipes ») :

```swift
        HStack(spacing: 10) {
            TeamBadge(code: team.code, logoFile: logoFile, tint: Palette.team(team.colorHex), size: 34)
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
```

par :

```swift
        HStack(spacing: 10) {
            // Toucher la ligne → page de l'équipe (spec saison §2.1) ; l'œil et l'étoile restent des boutons.
            TeamLink(teamId: team.id) {
                HStack(spacing: 10) {
                    TeamBadge(code: team.code, logoFile: logoFile, tint: Palette.team(team.colorHex), size: 34)
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
                }
            }
```

Remplacer (ligne du catalogue) :

```swift
        HStack(spacing: 10) {
            TeamBadge(code: team.code, logoFile: logoFile, size: 34)
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
```

par :

```swift
        HStack(spacing: 10) {
            // Toucher la ligne → page de l'équipe (spec saison §2.1) ; l'étoile reste un bouton.
            TeamLink(teamId: team.id) {
                HStack(spacing: 10) {
                    TeamBadge(code: team.code, logoFile: logoFile, size: 34)
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
                }
            }
```

- [ ] **Step 6: Équipes — « Suivre la ligue » sous les pilules (A8)**

Dans `App/Teams/TeamsView.swift`, remplacer :

```swift
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            teamList(store.teams(in: selected))
```

par :

```swift
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            let leagueTeams = store.teams(in: selected)
            // Suivre la ligue, ou toutes ses équipes (spec saison §3.5).
            LeagueFollowRow(league: selected, followed: store.follows.containsLeague(id: selected.id),
                            notifies: store.follows.leagues.first { $0.id == selected.id }?.notifyStarts ?? false,
                            teamCount: leagueTeams.count,
                            allTeamsFollowed: leagueTeams.allSatisfy { store.follows.contains(id: $0.id) },
                            onToggleFollow: { toggleLeague(selected) },
                            onFollowAll: { followAll(selected) },
                            onToggleNotifications: { store.setLeagueNotifications($0, leagueId: selected.id) })
            teamList(leagueTeams)
```

Remplacer :

```swift
    /// Étoile du catalogue (spec finitions §3) : suivre (succès) ou ne plus suivre (impact léger).
```

par :

```swift
    /// Étoile d'une ligue (spec saison §3.5) : suivre (succès) ou ne plus suivre (impact léger).
    private func toggleLeague(_ league: League) {
        haptics.play(store.follows.containsLeague(id: league.id) ? .unfollow : .follow)
        store.toggleFollowLeague(league)
    }

    /// « Suivre ses N équipes » (spec saison §3.5).
    private func followAll(_ league: League) {
        haptics.play(.follow)
        store.followAllTeams(in: league)
    }

    /// Étoile du catalogue (spec finitions §3) : suivre (succès) ou ne plus suivre (impact léger).
```

- [ ] **Step 7: Matchs — « À ne pas rater » en tête et section « Ligues » (A3, A8)**

Dans `App/Matches/MatchesView.swift`, remplacer :

```swift
                if cards.isEmpty {
                    WelcomeCard(action: openTeams)
                } else {
```

par :

```swift
                // « À ne pas rater » (spec saison §3.6) : 5 au plus, en tête de Matchs.
                MustWatchSection(picks: store.mustWatchPicks(limit: 5), style: .list)
                if cards.isEmpty {
                    WelcomeCard(action: openTeams)
                } else {
```

Remplacer :

```swift
                            .transition(Motion.listTransition(reduceMotion: reduceMotion))
                    }
                }
            }
            // Bandeau (spec finitions §11) et cartes (§7) : seules ces deux valeurs animent l'écran.
```

par :

```swift
                            .transition(Motion.listTransition(reduceMotion: reduceMotion))
                    }
                }
                // Ligues suivies (spec saison §3.5) : prochain match, classement.
                LeaguesSection(rows: LeaguesSection.rows(store: store))
            }
            // Bandeau (spec finitions §11) et cartes (§7) : seules ces deux valeurs animent l'écran.
```

- [ ] **Step 8: Premier lancement en `fullScreenCover` (A9)**

Dans `App/RootView.swift` (texte laissé par I1), remplacer :

```swift
    @State private var teamsPath = NavigationPath()
```

par :

```swift
    @State private var teamsPath = NavigationPath()
    /// Premier lancement (spec saison §3.7), décidé une fois à l'apparition : suivre une équipe pendant l'onboarding ne
    /// le ferme pas.
    @State private var showsOnboarding = false
```

Remplacer :

```swift
        // Icônes de champions des écrans de saison (`ChampionIcon`) : le store Data Dragon de l'appli.
        .environment(\.dataDragon, store.dataDragon)
```

par :

```swift
        // Icônes de champions des écrans de saison (`ChampionIcon`) : le store Data Dragon de l'appli.
        .environment(\.dataDragon, store.dataDragon)
        .onAppear {
            if Self.presentsOnboarding(store: store, hasRouter: router != nil) { showsOnboarding = true }
        }
        .fullScreenCover(isPresented: $showsOnboarding) {
            OnboardingHost(onDone: {
                store.completeOnboarding()
                showsOnboarding = false
            })
            .environment(store)
        }
```

Remplacer :

```swift
#Preview {
    RootView().environment(AppStore(preview: .standard))
}
```

par :

```swift
extension RootView {
    /// L'onboarding s'ouvre dans l'appli seulement (elle seule passe un routeur de notifications : jamais dans les
    /// aperçus ni les tests), au premier lancement (`showsOnboarding` : pas fait, rien de suivi).
    static func presentsOnboarding(store: AppStore, hasRouter: Bool) -> Bool {
        hasRouter && store.showsOnboarding
    }
}

/// L'onboarding branché sur le store : équipes du Mondial (classements, sinon annuaire), ligues des pilules, recherche
/// dans le catalogue ; chaque toucher suit tout de suite (spec saison §3.7).
private struct OnboardingHost: View {
    @Environment(AppStore.self) private var store
    let onDone: () -> Void

    var body: some View {
        let worlds = store.leagues.first { $0.slug == "worlds" }
        let standings = worlds.flatMap { store.currentTournamentId(leagueId: $0.id) }.flatMap { store.season.standings[$0] }
        let teams = OnboardingModel.worldsTeams(catalog: store.catalog, worldsStandings: standings,
                                                fallback: worlds.map { store.teams(in: $0) } ?? [])
        OnboardingView(teams: teams, leagues: store.leaguePills,
                       followedTeams: store.catalog.filter { store.follows.contains(id: $0.id) },
                       followedLeagueIds: Set(store.follows.leagues.map(\.id)),
                       spoilerFreeIds: Set(store.follows.teams.filter(\.spoilerFree).map(\.id)),
                       search: { store.search($0) },
                       onToggleTeam: { store.toggleFollow($0) },
                       onToggleLeague: { store.toggleFollowLeague($0) },
                       onSetSpoilerFree: { id, on in store.setSpoilerFree(on, id: id) },
                       onDone: onDone)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
```

- [ ] **Step 9: Checklist iPhone, section F**

À la fin de `docs/superpowers/notes/2026-10-14-checklist-iphone.md`, ajouter :

```markdown

## F. Compagnon de saison (Accueil, équipes, joueurs, duels, ligues, classements)

1. **Ouverture** : Faille s'ouvre sur **Accueil** (premier onglet) ; rien n'attend le réseau (squelettes puis contenu en moins d'une seconde).
2. **Notification** : toucher une notification de début de match ouvre toujours le **Détail dans Matchs** (pas l'Accueil).
3. **Collecte** : laisser Faille ouverte 3 min sur l'Accueil : « Les stats arrivent : N games lues sur M » avance ; quitter Faille l'arrête ; la rouvrir reprend où elle en était (aucune game relue).
4. **Page équipe** : toucher une équipe (carte, ligne d'Équipes, en-tête du Détail) → sa page : bilan, forme, prochains matchs, effectif, moyennes, champions, classement. Une équipe non suivie : ses stats arrivent pendant que la page est ouverte.
5. **Anti-spoiler** : une équipe en anti-spoiler → « N matchs masqués » sur sa page, « Prochain · masqué », « Classement masqué · toucher pour révéler » ; révéler le classement ne révèle aucun match ; l'Accueil montre « En direct » sans score pour un match masqué, et « Terminé · toucher pour révéler » dans les résultats.
6. **Duel** : Détail d'un match → section « Duel » : joueurs poste par poste (barres), « Changer » ; un match masqué n'y montre que les stats de saison.
7. **Page joueur** : toucher un joueur (effectif, joueurs en forme, duel) → moyennes, champions, meilleure game.
8. **Ligues** : Équipes → une ligue → « Suivre la ligue » ; Matchs → section « Ligues » (prochain match, Classement).
9. **Classements** : LEC, Mondial (suisse, tableau) depuis la page équipe ou la section Ligues.
10. **Calendrier** : Accueil → « Tout le calendrier » → mois précédent / suivant (un mois hors du calendrier se charge en quelques secondes).
11. **Premier lancement** : supprimer puis réinstaller Faille → 3 écrans (exemple vivant, choix des équipes, anti-spoiler) ; « Passer » marche partout.
12. **Batterie / chaleur** : 10 min d'Accueil ouvert pendant la collecte : le téléphone ne chauffe pas plus qu'avant.
```

- [ ] **Step 10: Commit, push, CI une fois**

```bash
git add App Tests/FailleTests/SeasonWiringTests.swift docs/superpowers/notes/2026-10-14-checklist-iphone.md
git commit -m "feat(app): intégration saison 2 — duel et équipes touchables dans le Détail, page équipe depuis les cartes et Équipes, suivre une ligue, « À ne pas rater » et Ligues dans Matchs, premier lancement ; checklist F" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-i2-integration
RUN=$(gh run list --workflow iOS --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch --exit-status "$RUN"
```

Attendu : CI verte ; toutes les planches non vides (les existantes `01-matchs`, `03-equipes`, `21`/`22-detail-*` changent de contenu) ; `RemindersTests` et `SeasonIntegrationTests.notificationDeepLinkStillOpensTheDetailInMatches` verts. Après la fusion : IPA (point de contrôle).

---

### Task P2: Accessibilité et langue (catalogue fr/en, VoiceOver, Dynamic Type)

**Branche :** `nuit2/appli-p2-langue` · **Vague :** 5, après I2 (seule tâche en cours : elle touche tout `App/`) · **Dépendances :** I2 fusionnée (et tout ce qui doit être dans l'IPA).

**Files:**
- Create: `scripts/strings-check.py`, `Resources/Localizable.xcstrings`, `Tests/FailleTests/AccessibilityTests.swift` (planche `34-grand-texte`)
- Modify: `project.yml`, `.github/workflows/lolkit.yml`, et dans `App/**` / `Shared/**` : littéraux nus des composants (19 sur `origin/main`, plus ceux qui seraient arrivés), libellés VoiceOver des anciens écrans (`App/Matches/MatchParts.swift` : `ScoreRow`, `MiniStats` ; `App/Detail/StatsPanels.swift`), `.font(Typo.x)` → `.sora(.x)` dans `App/**` (pas dans `Shared/` : widgets et Live Activity gardent `Typo`).

**Interfaces:**
- Consumes : I1 `SoraStyle` / `.sora(_:)` ; tout ce que les tâches ont écrit (`String(localized:)`, `Text("…")`).
- Produces : catalogue `Localizable.xcstrings` (source **fr**, **en** complet) ; contrôle CI `strings-check.py` (job `strings` de `lolkit.yml`) ; `ScoreRow.spoken(teams:score:)`, `MiniStats.spoken(stats:)`.

- [ ] **Step 1: Écrire le contrôle des chaînes**

Créer `scripts/strings-check.py` (exécutable : `chmod +x`) :

```python
#!/usr/bin/env python3
"""Contrôle du catalogue de chaînes de Faille (spec saison §3.8, P2).

Chaque littéral affiché de `App/` et `Shared/` — `Text("…")`, `Label("…")`, `Button("…")`, `Tab("…")`, `Toggle("…")`,
`.navigationTitle("…")`, `.accessibilityLabel("…")`, `.accessibilityHint("…")`, `.accessibilityValue("…")`,
`String(localized: "…")` — doit avoir une entrée dans `Resources/Localizable.xcstrings` avec une traduction anglaise
non vide ; et aucun littéral nu ne doit être passé à un composant qui prend une `String` (`ScreenHeader("…")`,
`subtitle: "…"`, `text: "…"` : affiché tel quel, jamais traduit — écrire `String(localized: "…")`). Les interpolations `\\(…)` correspondent à n'importe quel format du catalogue (`%@`, `%lld`, `%1$@`…).

Usage :
  python3 scripts/strings-check.py                 # contrôle (code de sortie 1 s'il manque quelque chose)
  python3 scripts/strings-check.py --add-missing   # ajoute les clés manquantes (anglais vide, état « new »), puis contrôle
Aucune dépendance hors de la bibliothèque standard.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Resources" / "Localizable.xcstrings"
SOURCES = [ROOT / "App", ROOT / "Shared"]
PREFIXES = [
    "Text(", "Label(", "Button(", "Tab(", "Toggle(", ".navigationTitle(", ".accessibilityLabel(",
    ".accessibilityHint(", ".accessibilityValue(", "String(localized:",
]
# Littéral nu passé à un composant qui prend une `String` (affichée telle quelle, donc jamais traduite) : à écrire
# `String(localized: "…")`.
BARE = re.compile(r'(?:ScreenHeader\(|\bsubtitle:|\btext:)\s*"')
# Planche de la DA (outil de développement, jamais montrée à l'utilisateur).
EXCLUDED = {"App/DA/DASampler.swift"}
FORMAT = re.compile(r"%(?:\d+\$)?(?:ll[du]|l[du]|[@dfsue]|\.\d+f)")
PLACEHOLDER = "\u0000"


def literal_at(text, start):
    """Littéral Swift qui commence au guillemet `start` ; renvoie (contenu avec interpolations remplacées, fin) ou None."""
    if text.startswith('"""', start):
        return None
    i, out = start + 1, []
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text) and text[i + 1] == "(":
            depth, i = 1, i + 2
            while i < len(text) and depth:
                if text[i] == '"':
                    end = literal_at(text, i)
                    i = end[1] if end else i + 1
                    continue
                depth += {"(": 1, ")": -1}.get(text[i], 0)
                i += 1
            out.append(PLACEHOLDER)
            continue
        if c == "\\" and i + 1 < len(text):
            out.append(text[i:i + 2])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        if c == "\n":
            return None
        out.append(c)
        i += 1
    return None


def literals(path):
    text = path.read_text(encoding="utf-8")
    found = []
    for prefix in PREFIXES:
        for match in re.finditer(re.escape(prefix), text):
            j = match.end()
            while j < len(text) and text[j] in " \t":
                j += 1
            if j < len(text) and text[j] == '"':
                parsed = literal_at(text, j)
                if parsed and parsed[0].strip():
                    line = text.count("\n", 0, j) + 1
                    found.append((parsed[0], f"{path.relative_to(ROOT).as_posix()}:{line}"))
    return found


def bare_literals(path):
    text = path.read_text(encoding="utf-8")
    return [f"{path.relative_to(ROOT).as_posix()}:{text.count(chr(10), 0, m.start()) + 1}" for m in BARE.finditer(text)]


def normalize(key):
    return FORMAT.sub(PLACEHOLDER, key.replace("%%", "%"))


def has_english(entry):
    english = entry.get("localizations", {}).get("en", {})
    unit = english.get("stringUnit")
    if unit is not None:
        return bool(unit.get("value", "").strip())
    variations = english.get("variations", {})
    units = [v.get("stringUnit", {}) for group in variations.values() for v in group.values()]
    return bool(units) and all(u.get("value", "").strip() for u in units)


def main():
    add = "--add-missing" in sys.argv
    catalog = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {
        "sourceLanguage": "fr", "strings": {}, "version": "1.0"}
    entries = catalog.setdefault("strings", {})
    by_norm = {normalize(k): v for k, v in entries.items()}
    used, bare = {}, []
    for folder in SOURCES:
        for path in sorted(folder.rglob("*.swift")):
            if path.relative_to(ROOT).as_posix() in EXCLUDED:
                continue
            bare += bare_literals(path)
            for value, where in literals(path):
                used.setdefault(value, where)
    missing = [(v, w) for v, w in used.items() if normalize(v) not in by_norm]
    if add and missing:
        for value, _ in missing:
            key = value.replace(PLACEHOLDER, "%@")
            entries[key] = {"localizations": {"en": {"stringUnit": {"state": "new", "value": ""}}}}
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        by_norm = {normalize(k): v for k, v in entries.items()}
        missing = []
    untranslated = [(v, w) for v, w in used.items() if not has_english(by_norm.get(normalize(v), {}))]
    for value, where in missing:
        print(f"::error file={where.split(':')[0]},line={where.split(':')[1]}::absent du catalogue : {value!r}")
    for value, where in untranslated:
        if (value, where) not in missing:
            print(f"::error file={where.split(':')[0]},line={where.split(':')[1]}::sans traduction anglaise : {value!r}")
    for where in bare:
        print(f"::error file={where.split(':')[0]},line={where.split(':')[1]}::littéral nu passé à un composant "
              f"(écrire String(localized: \"…\"))")
    print(f"{len(used)} chaînes, {len(missing)} absentes, {len(untranslated)} sans anglais, {len(bare)} littéraux nus")
    return 1 if missing or untranslated or bare else 0


if __name__ == "__main__":
    sys.exit(main())
```

Vérifié sur `origin/main` `ab700f5` : 73 littéraux trouvés dans `App/` + `Shared/`, 19 littéraux nus (`ScreenHeader("Mes équipes"…)`, `SectionLabel(text: "…")`, `NoteCard(…, text: "…")`, `StatLabel(…, text: "…")`), aucun faux positif dans `App/DA/DASampler.swift` (exclu : planche de développement).

- [ ] **Step 2: Plus aucun littéral nu**

```bash
python3 scripts/strings-check.py | grep "littéral nu"
```

Pour chaque ligne signalée, remplacer le littéral par `String(localized: "…")` (même texte), par exemple dans `App/Teams/TeamsView.swift` `        SectionLabel(text: "Mes équipes")` → `        SectionLabel(text: String(localized: "Mes équipes"))`, et `ScreenHeader("Équipes", subtitle: …)` → `ScreenHeader(String(localized: "Équipes"), subtitle: …)`. Relancer jusqu'à « 0 littéraux nus ».

- [ ] **Step 3: Créer le catalogue et traduire**

```bash
python3 scripts/strings-check.py --add-missing
```

Le script crée `Resources/Localizable.xcstrings` (`"sourceLanguage": "fr"`, une entrée par clé, anglais vide en état `new`). Remplir **chaque** traduction anglaise (`"state": "translated"`), en gardant les formats (`%@`, `%lld`) et l'ordre des arguments (`%1$@`, `%2$@` si l'anglais les inverse). Comptes : variantes de pluriel en anglais, par exemple :

```json
"%lld matchs masqués" : {
  "localizations" : {
    "en" : { "variations" : { "plural" : {
      "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld hidden match" } },
      "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld hidden matches" } }
    } } }
  }
}
```

Repères de traduction (ton de l'appli, court) : « Accueil » → « Home », « Matchs » → « Matches », « Équipes » → « Teams », « À ne pas rater » → « Don't miss », « En direct maintenant » → « Live now », « Résultats récents » → « Recent results », « Activité récente » → « Recent activity », « Joueurs en forme » → « Players on form », « toucher pour révéler » → « tap to reveal », « Score masqué » → « Score hidden », « Classement masqué » → « Standings hidden », « Mondial » → « Worlds », « estimé » → « estimated », « Prochain · masqué » → « Next · hidden », « Suis tes équipes pour un accueil sur mesure » → « Follow your teams for a home made for you », « Ton compagnon de saison LoL esport » → « Your LoL esports season companion ». Puis :

```bash
python3 scripts/strings-check.py   # attendu : « … 0 absentes, 0 sans anglais, 0 littéraux nus », code 0
```

- [ ] **Step 4: Langue du projet**

Dans `project.yml`, remplacer :

```yaml
options:
  bundleIdPrefix: com.cafe1231
```

par :

```yaml
options:
  bundleIdPrefix: com.cafe1231
  # Langue source du catalogue de chaînes (spec saison §3.8) : français ; anglais traduit.
  developmentLanguage: fr
```

Remplacer (appli) :

```yaml
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        UILaunchScreen:
```

par :

```yaml
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        CFBundleDevelopmentRegion: fr
        CFBundleLocalizations: [fr, en]
        UILaunchScreen:
```

Remplacer (extension) :

```yaml
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        UIAppFonts:
```

par :

```yaml
        CFBundleDisplayName: Faille
        CFBundleShortVersionString: "0.1.0"
        CFBundleDevelopmentRegion: fr
        CFBundleLocalizations: [fr, en]
        UIAppFonts:
```

(`Resources/` est déjà une source des deux cibles : le catalogue est compilé dans l'appli et l'extension.)

- [ ] **Step 5: Contrôle en CI**

Dans `.github/workflows/lolkit.yml`, remplacer :

```yaml
    paths: ["LoLKit/**", ".github/workflows/lolkit.yml"]
```

par :

```yaml
    paths: ["LoLKit/**", ".github/workflows/lolkit.yml", "App/**", "Shared/**", "Resources/Localizable.xcstrings",
            "scripts/strings-check.py"]
```

Remplacer :

```yaml
      - name: Tests LoLKit (macOS)
        run: swift test --package-path LoLKit
```

par :

```yaml
      - name: Tests LoLKit (macOS)
        run: swift test --package-path LoLKit

  # Chaque texte de l'appli a sa traduction anglaise (spec saison §3.8) ; aucun littéral nu passé à un composant.
  strings:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Catalogue de chaînes (fr → en)
        run: python3 scripts/strings-check.py
```

- [ ] **Step 6: VoiceOver des anciens écrans**

Dans `App/Matches/MatchParts.swift`, sur la `HStack` de `ScoreRow.body`, ajouter `.accessibilityElement(children: .ignore)` et `.accessibilityLabel(Text(Self.spoken(teams: teams, score: score)))`, et :

```swift
    /// « Karmine Corp 2, G2 Esports 1 » ; sans score (masqué ou à venir) : « Karmine Corp contre G2 Esports » (le
    /// bouton « Score masqué · toucher pour révéler » est lu à part).
    static func spoken(teams: [MatchTeam], score: [Int]?) -> String {
        let names = teams.map(\.name)
        guard names.count == 2 else { return names.joined(separator: ", ") }
        if let score, score.count == 2 {
            return String(localized: "\(names[0]) \(score[0]), \(names[1]) \(score[1])")
        }
        return String(localized: "\(names[0]) contre \(names[1])")
    }
```

Sur `MiniStats`, même principe : `.accessibilityElement(children: .ignore)` + `.accessibilityLabel(Text(Self.spoken(stats: stats)))`, avec `spoken` = « Kills 7 à 4, écart de gold +2,1 k, drakes 2 à 1, tours 3 à 1 » (`String(localized:)`, valeurs de `stats[0]` puis `stats[1]`, `Format.goldDiff`). Puis passer sur chaque écran (`grep -rn "IconView(icon" App | grep -v accessibility`) : toute icône **seule** (sans texte voisin qui porte le sens) dans un bouton reçoit un `accessibilityLabel` ; les icônes à côté d'un texte restent décoratives (`IconView` est déjà masqué à VoiceOver).

- [ ] **Step 7: Dynamic Type des anciens écrans**

```bash
grep -rln "\.font(Typo\." App | xargs sed -i -E 's/\.font\(Typo\.(title|scoreLarge|score|headline|body|bodyMedium|stat|secondary|secondaryMedium|label|chip)\)/.sora(.\1)/g'
grep -rn "\.font(Typo\." App || echo "aucun reste"
```

`Shared/` n'est pas touché (widgets, Live Activity : `Typo` fixe, spec §3.8). Les `.font(selected ? Typo.x : Typo.y)` restants (pilules) restent en `Typo` (taille fixe des pilules, assumé).

- [ ] **Step 8: Test et planche**

Créer `Tests/FailleTests/AccessibilityTests.swift` :

```swift
import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Accessibilité (spec saison §3.8) : scores lus, Dynamic Type.
@MainActor
struct AccessibilityTests {
    @Test func scoresAreSpoken() {
        let teams = SampleData.kcG2Details.match.teams
        #expect(ScoreRow.spoken(teams: teams, score: [1, 3]) == "Karmine Corp 1, G2 Esports 3")
        #expect(ScoreRow.spoken(teams: teams, score: nil) == "Karmine Corp contre G2 Esports")
    }

    /// Le catalogue est compilé dans l'appli, en français et en anglais.
    @Test func catalogIsBundled() {
        #expect(Bundle.main.localizations.contains("en"))
        #expect(Bundle.main.localizations.contains("fr"))
    }
}

extension ApercuTests {
    /// Accueil en très grand texte (`accessibility2`, le plafond de `.sora`) : rien ne doit être coupé de façon illisible.
    @Test func homeWithLargeText() async throws {
        let view = RootView(tab: .home)
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
            .environment(\.dynamicTypeSize, .accessibility2)
        let url = try await Snapshot.write(view, named: "34-grand-texte")
        expectNotBlank(url)
    }
}
```

- [ ] **Step 9: Commit, push, CI une fois (iOS et LoLKit)**

```bash
git add -A App Shared Resources scripts project.yml .github/workflows/lolkit.yml Tests/FailleTests/AccessibilityTests.swift
git commit -m "feat(app): langue et accessibilité — catalogue fr/en contrôlé en CI, plus aucun littéral nu, VoiceOver des scores et des stats, Dynamic Type (.sora) sur les écrans de l'appli" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push -u origin nuit2/appli-p2-langue
for WF in iOS LoLKit; do
  RUN=$(gh run list --workflow "$WF" --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')
  gh run watch --exit-status "$RUN"
done
```

Attendu : CI iOS verte (toutes les planches non vides, `34-grand-texte` compris) ; CI LoLKit verte, job `strings` compris.

---

## Auto-relecture

**Couverture de la spec (§2-§3)**

| Spec | Où |
|---|---|
| §1.6 collecte : ordre (priorités 0-4, le plus récent d'abord), cadence 2 s (y compris les 2 requêtes d'une game), recul 4-8-16-32-60, arrêt après 5 échecs, budget 300 / session (énumération comprise), premier plan seulement, reprise = le disque, échecs `statsDisabled`/`noData`/`notFinished`/`http`, un fichier par game, palier B qui réécrit, `GameWinners` rejoué | A1 (`PacedTransport`, `SeasonCrawler`, `SeasonStore`) ; boucle et réveils : I1 (`seasonLoop`, `wake`) |
| §1.7 cache disque (chemins, durées, 2 000 games, versions de schéma) | A1 (`SeasonDisk`) |
| §1.8 anti-spoiler du socle | A1 (planification), I1 (`seasonMasked`), A2-A5 (chaque agrégat reçoit `masked`) |
| §2.1 navigation : Accueil par défaut, piles par onglet, `.failleDestinations`, routes, lien profond inchangé, toucher une équipe partout, 5 icônes | I1 ; taps : I2 |
| §2.2 sections de l'Accueil, états vides, sans suivi → Mondial + carte | A3 |
| §2.3 cache d'abord, calcul hors du fil principal mémoïsé, cascade, pas d'animation continue (halo ≤ 3 lignes) | A3 |
| §2.4 activité | A3 (`ActivitySection`, L7) |
| §3.1 page équipe (en-tête, périmètres, ligne d'état, bilan, forme, prochains, effectif, moyennes, champions, face-à-face, classement, squelettes, priorité 0, « Stats masquées ») | A2 |
| §3.2 calendrier complet (mois, pages `older`/`newer`) | A7 (pages via A1) |
| §3.3 duels (Détail : joueurs / équipes, barres, « Cette game », sélecteur, anti-spoiler) | A4, branché par I2 |
| §3.4 page joueur | A5 |
| §3.5 ligues suivies (suivre, ses N équipes, notifications, section Ligues), classements (table, suisse, tableau), masquage et révélation | I1 (store), A8, A6, I2 |
| §3.6 « À ne pas rater » (Accueil 1 + 2, Matchs 5, « Comment c'est calculé ») | A3, I2 |
| §3.7 onboarding (3 écrans, Passer, exemple vivant, utilisateur existant marqué fait), états vides | A9, I1 (`markOnboardedIfExistingUser`), I2 (`fullScreenCover`) |
| §3.8 catalogue fr/en + contrôle CI, VoiceOver, Dynamic Type `.sora`, contraste | P2 (`.sora` créé par I1) |
| §4 critères appli (planches non vides avec « N matchs masqués » / « Classement masqué », tests hébergés de la collecte, lien profond) | A1, A2, A5, A6, I1 |

Non couvert, volontairement : widgets pour les ligues suivies et anti-spoiler par ligue (rulings de la spec §3.5) ; photos des joueurs (aucune image de joueur téléchargée cette nuit : monogramme) ; KDA par champion sur la page joueur (`ChampionUse` ne le porte pas : games et bilan seulement) ; réutilisation d'une relecture existante pour le palier A (spec §1.3, « à implémenter en dernier » : non planifiée cette nuit).

**Anti-spoiler** : collecte — aucun job pour un match masqué (`SeasonMasking` → `CrawlPlanner`, testé : aucune URL de ses games, puis demandé après révélation) ; agrégats — `seasonMasked` passé partout (`teamSeason`, `player`, `topPlayers`, `headToHead`, `HomeFeed.activity`) ; lignes de match — `MatchLine` ne lit que `Presenter.scoreLine` (masqué : « En direct » / « Terminé · toucher pour révéler ») ; « prochain » — `Presenter.nextLine` (page équipe, ligues : règle C) ; duel d'un match masqué — ni composition ni « Cette game » (testé) ; classement — `StandingsMasking`, révélation par tournoi sans révéler de match (testé) ; « Regarder » de l'Accueil — `WatchLinks.live(masked:)` ; un match masqué se compte, jamais ses games (« N matchs masqués »).

**Sobriété réseau** : une seule porte (`PacedTransport`) pour toutes les requêtes de saison, testée (≥ 2 s, 300, recul) ; premier plan seulement (tâche de `poll`, rien dans `refreshInBackground`) ; un tour d'attente avant la première passe ; tournois terminés jamais relus (testé) ; tournois en cours 30 min ; listes de tournois 24 h ; pages du calendrier gardées pour la session ; classement à l'écran : une requête ; icônes de champions : version Data Dragon déjà gardée 24 h, images pour toujours (existant).

**Fichiers disjoints** : vérifié sur la matrice — chaque fichier existant n'a qu'un propriétaire à un moment donné (coquilles : I1 puis une seule tâche A ; `RootView` : I1 puis I2, en séquence) ; A2-A8 tournent en parallèle sans fichier commun (les noms de postes sont dans `SeasonNames.role`, d'I1, pour éviter un doublon entre A2, A4 et A5).

**API et replis** : `UIContentSizeCategory(_ dynamicTypeSize:)` (repli : `switch`) ; `navigationDestination(item:)` (iOS 17+) ; `ScrollViewReader.scrollTo` à l'apparition (bandeau) ; `TimelineView(.periodic)` (exemple vivant, figé sous « Réduire les animations ») ; `NumberFormatter.ordinal` ; `fullScreenCover` décidé une fois à l'apparition ; `Task.detached` pour les deux calculs lourds (disque, Accueil) ; palier B à 4 requêtes faute d'enrichissement dans LoLKit (et `noData` s'il n'apporte rien, pour ne pas boucler) ; 400 / réponse illisible traduits en `noData` (sinon `CrawlFailure.record` ne les garde pas et la game reviendrait sans fin) ; si un point d'entrée de LoLKit manque à la fusion, même règle en fonction privée testée.

**Cohérence avec le contrat LoLKit** : chaque symbole consommé est dans le tableau, relevé sur le vrai code (`4e37f00`) ; le code sans interface du plan y a été compilé et testé (0 avertissement, 30 tests), L7 comprise telle que l'écrit le plan LoLKit. Ce que l'appli ne redéclare pas parce que LoLKit l'a : `DuelBar` / `DuelMetric` (barres du duel), règles de la collecte (`CrawlPlanner.*`, `CrawlFailure.*`), « en cours », étape du Mondial, budget disque, tableaux (`StandingsTable.Content`), pages du calendrier (`CalendarMonth.pageNeeded`), sections de l'Accueil (`HomeFeed.build`). Risques restants : L7 n'est pas encore fusionnée (A3, A7, I2 la consomment : relire à la tête de branche) ; les tests d'ordre d'A1 suivent l'ordre réel de `CrawlPlanner` (relevé, testé) ; les étiquettes d'`ActivityKind` / `MustWatchReason` suivent le plan L7.
