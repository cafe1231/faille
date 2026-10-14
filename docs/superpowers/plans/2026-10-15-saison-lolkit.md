# Saison (LoLKit) — plan d'implémentation (tâches L1 à L8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** donner à LoLKit toute la logique pure du « compagnon de saison » — énumération des tournois, des matchs joués et des classements, réduction d'une game jouée en `GameSummary` versionné, vainqueur par game, agrégats d'équipe et de joueur, duels, planification et cadence de la collecte, ligues suivies et nouveaux réglages, classements et tableaux, calendrier, « À ne pas rater » et fil de l'Accueil —, testée sur les vraies fixtures réduites de `Fixtures/season/`, anti-spoiler compris, pour que l'appli (tâches A1-A9, I1-I2, plan séparé) n'ait plus qu'à lire le cache, exécuter la collecte et afficher.

**Architecture :** huit tâches en **trois vagues**. Chaque tâche travaille dans son worktree, sur sa branche `nuit2/lolkit-lN-<slug>` partie de `main`, et ne touche que les fichiers de sa ligne de la « Matrice des fichiers » ; le contrôleur fusionne côté serveur. Vague 1 : L1 ‖ L2 ‖ L5 ‖ L8 (partent de `main` actuel, aucune dépendance) ; vague 2 : L3 ‖ L4 ‖ L6 (partent de `main` **après** la fusion de la vague 1) ; vague 3 : L7 (part de `main` **après** la fusion de la vague 2). Tout est pur (Foundation seule) ; aucune requête réseau dans LoLKit hors des méthodes de `LoLClient`.

**Tech Stack :** Swift 6.2 (mode Swift 6, concurrence stricte), Foundation seule, Swift Testing, Docker `swift:6.2` via `scripts/lolkit.sh` (un volume de compilation par worktree), CI GitHub `LoLKit` (Linux + macOS, déclenchée par tout push touchant `LoLKit/**`, branches comprises), `python -I` pour réduire deux fixtures.

**Spec :** `docs/superpowers/specs/2026-10-15-faille-saison-design.md` (contraignante) : §0, §1.1 (mesures réelles, recopiées en assertions), §1.2 (énumération, jointure, saison = année civile), §1.3 (paliers A/B, frame `finished`, gold à 15 min ± 15 s), §1.4 (vainqueur par game), §1.5 (modèle de données, formules), §1.6 (collecte), §1.7 (cache), §1.8 (anti-spoiler), §2.4 (`HomeFeed.activity`), §3.2 (calendrier), §3.3 (duels), §3.5 (ligues, classements, masquage), §3.6 (`MustWatch`), §4 (découpage L1-L8) ; règles de données de `.superpowers/goal-nuit-2.md`. Ce plan ne couvre que LoLKit ; `SeasonStore`, le collecteur, le cache disque et les écrans sont au plan de l'appli.

## Global Constraints

- LoLKit n'importe que **Foundation** ; Swift 6.2, mode Swift 6 : tout type public nouveau est `Sendable` (et `Equatable` quand il est comparé dans un test) ; **aucun avertissement** de compilation (vérifier `grep -c "warning:"` = 0 dans la sortie).
- TDD : test qui échoue → `bash scripts/lolkit.sh test --filter <Suite>` (échec de compilation attendu : le type n'existe pas) → implémentation → même commande verte → `bash scripts/lolkit.sh test` complet vert avec le total attendu. Docker Desktop doit tourner (sinon lancer `C:\Program Files\Docker\Docker\Docker Desktop.exe`, ne rien installer). Les commandes se lancent depuis la racine du worktree, dans Git Bash.
- **Fixtures réelles** : celles de `LoLKit/Tests/LoLKitTests/Fixtures/season/` sont déjà au dépôt (commit `ca921f4`) et ne sont **jamais modifiées**. Deux fixtures nouvelles sont produites par un script `python -I` (L1 : `getCompletedEvents_lec3_ids.json` ; L6 : `getStandings_worlds25_reduced.json`) à partir des captures brutes du dossier de travail ; empreinte `sha256sum` attendue donnée : si elle diffère, s'arrêter et le signaler (ne pas ajuster les tests). **Aucune requête vers `lol.fandom.com`** ; si une capture brute manque, une seule requête `curl` vers `esports-api.lolesports.com` (clé publique, au plus une toutes les 2 s).
- **Décodage tolérant** (spec §4.2, §1.7) : tout champ non essentiel est optionnel ou prend une valeur neutre ; un élément illisible est ignoré, jamais tout le décodage ; un champ retiré ne fait jamais échouer (testé dans chaque tâche qui décode).
- **Versionnage** : `GameSummary.v` (schéma 1) ; un fichier d'un schéma plus récent est ignoré (`GameSummary.decodeStored`), un plus ancien relu avec ses champs manquants à nil.
- **Anti-spoiler** (spec §1.8, §3.5, §3.6) : toutes les fonctions d'agrégat prennent `masked: Set<String>` (ids de match, `SeasonMasking.maskedMatchIds`) ; un match masqué ne compte nulle part, il est compté en **matchs** (jamais en games) ; `CrawlPlanner.jobs` ne rend **jamais** de job pour un match masqué ; classements masqués par `StandingsMasking` ; « À ne pas rater » exclut F1 / C et neutralise les raisons tirées des résultats.
- **Des valeurs, jamais du texte** dans les API nouvelles (`MustWatchReason`, `ActivityKind`, `StandingsTable.Content`, `DayMarker`…) : l'appli formule (catalogue de chaînes, P2).
- **Aucun secret** : seule clé, la clé publique lolesports déjà dans `LoLClient.publicAPIKey`.
- Identifiants en anglais, commentaires en français, fins de ligne LF (`.gitattributes` : `* text=auto eol=lf`).
- **Une tâche ne touche que les fichiers de sa ligne de la matrice** : ni `Package.swift`, ni `Tests/LoLKitTests/Support/Fixture.swift` / `FakeTransport.swift` / `Builders.swift`, ni une fixture existante, ni un fichier d'une autre tâche.
- Commits : `git commit -m "<message>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`. Chaque tâche pousse **sa branche** (`git push -u origin <branche>`) et attend **une** CI `LoLKit` verte sur le SHA complet de son dernier commit touchant `LoLKit/` ; elle ne pousse jamais sur `main` (le contrôleur fusionne).

## Décisions prises par ce plan (au-delà de la spec)

- **`SeasonScope.swift` passe de L4 à L3** : `SeasonStats.team(…scope: SeasonScope…)` et `TeamSeason.scope` (L3) en ont besoin, alors que L3 ne dépend pas de L4. `SeasonScope.label` est une valeur (année « 2026 » ou slug du tournoi), pas un texte.
- **L2 modifie aussi `Models/LiveWindow.swift`** (seule tâche à le toucher) : `ParticipantMetadata.esportsPlayerId: String?` (présent dans le flux, mesuré), indispensable à `PlayerGameLine.playerId` (identité d'un joueur, §1.5). Optionnel : les anciennes captures restent lisibles.
- **`GameWinners.assign(teams:playedGameIds:summaries:)`** au lieu de `assign(match:summaries:)` : L2 ne dépend pas de L1 (`SeasonMatch`) ; l'appli l'appelle avec `match.teams` et `match.playedGameIds`. Règle 4 lue strictement : « déduit » seulement si chaque game attribuée à A a une marge de tours ≥ +3 et chaque game attribuée à B ≤ −3 (l'unicité en découle) ; sinon « inconnu » pour ces games. Vérifié : KC LEC S3 = 21 exactes, 10 déduites, 0 inconnue, toutes cohérentes. `GameWinners.apply(teams:playedGameIds:to:)` reporte les résultats dans un dictionnaire de résumés.
- **Index KC et frame `finished`** : 2 des 31 lignes de `crawl_kc_lec3_tierA_index.json` ont un dernier état `in_game` (le flux s'arrête avant `finished`). La règle §1.3 est gardée (`GameSummary.make` → nil sans `finished`, testé) ; les agrégats §1.1 (31 games, 509 kills, 85 drakes…) sont vérifiés en construisant les 31 résumés directement depuis l'index (`SeasonFixture.summary(_:)`), ce qui teste les **formules**. Dans l'appli, ces 2 games tomberaient en `notFinished` (réessai 1 h, 3 fois, puis « sans stats ») : 29 games, 475 kills.
- **`SeasonStats.team` reçoit `withoutStats: Set<String> = []`** (games en échec définitif, calculées par l'appli depuis `crawl.json`) : sans ce paramètre, `gamesWithoutStats` serait incalculable sans dépendre de L4.
- **Série en cours** : nil si elle fait moins de 2 matchs, si le match le plus récent est masqué, et elle s'arrête au premier match masqué (sinon elle mentirait). `SeasonStats.streak(_:matches:masked:)` est publique (réutilisée par `HomeFeed`).
- **Champions** : une victoire = game gagnée par l'équipe du joueur au vainqueur exact ou déduit ; `winsEstimated` dès qu'une victoire est déduite ; un vainqueur inconnu ne compte ni en victoire ni en défaite. **Nom d'un joueur** dans `PlayerSeason.name` = nom brut du flux de sa game la plus récente ; l'appli affiche le catalogue ou `PlayerName.display`. **`PlayerMetric.kills`** = kills moyens par game.
- **`GameSummary`** : part des dégâts arrondie à 4 décimales (comme la fixture attendue) ; `enriched` = un des deux du palier B fourni ; stats finales = première frame `finished` ; `durationSeconds` arrondi à la seconde (2031). Le JSON du cache a la forme du type (`result {winnerTeamId, basis}`, `enriched`), pas celle, plate, de `game_summary_115548681803406304.json`, que les tests comparent valeur par valeur.
- **Cache** : `Standings`, `CompletedMatch`, `TournamentRef` sont `Codable` dans leur forme de cache ; `RankedTeam` s'encode avec `record {wins, losses}` comme l'API (un seul décodeur). `CompletedMatch` ne garde pas les vods.
- **`Team.players`** décodé à part (`LossyArray`, illisible → nil) : un effectif cassé ne retire jamais l'équipe du catalogue ; les autres champs gardent leurs exigences d'avant.
- **Ligues suivies** : `FollowedLeague(league:)`, `FollowList.follow(league:)`, `unfollowLeague(id:)`, `setNotifyStarts(_:leagueId:)`, `league(slug:)`. `MatchReminders.plan` ajoute, pour une ligue `notifyStarts`, chaque match à venir **sans équipe suivie** (ceux-là gardent la règle `nextLine`) et **sans « TBD »**.
- **Collecte** : priorités 0-4 de §1.6 (3 = ligues suivies, tournoi en cours puis précédents ; 4 = palier B) ; dans un groupe, tournoi en cours d'abord, puis match le plus récent, puis n° de game. Recul : le n-ième échec d'affilée attend 4, 8, 16, 32 s, le 5e arrête (la valeur 60 de `backoff` reste le plafond documenté). Une réponse 204 / 404 / 400 est une **réponse** (cadence normale) ; 429, 5xx et erreur réseau reculent. Fonctions pures ajoutées : `CrawlFailure.record/reason(for:)/isFinal/allowsRetry`, `CrawlPacer.outcome(of:)`, `CrawlPlanner.seasonTournaments/currentTournament/currentStageMatchIds/evictions/maxAge/needsRefresh` (§1.2, §1.6, §1.7).
- **Tableaux** : `StandingsTable.Content` = `.table` (rankings) | `.swiss` (bilans recalculés depuis `outcome`, équipes « TBD » ignorées) | `.bracket` (slug `knockouts` à 7 matchs) | `.matches` (le reste). **Masquage d'un classement** : en plus des matchs terminés masqués, une équipe suivie en anti-spoiler classée avec un bilan non nul masque le tableau tant que ses matchs listés et révélés ne couvrent pas son bilan (un bilan résume des matchs que le tableau réduit ne liste pas).
- **« À ne pas rater »** : « Tout se joue » est une raison à part `.decider` (+40 au lieu de 30 + 30) ; ids d'équipe pris dans le tableau s'il les connaît, sinon dans le catalogue (`SeasonMatch.resolve`) ; à égalité de points, les raisons gardent l'ordre de déclaration ; un match en cours compte même commencé la veille ; L7 consomme aussi L5 (`FollowList.league(slug:)`), déjà fusionnée en vague 1.
- **Accueil** : `HomeFeed.build(_:)` assemble « À ne pas rater » (3), direct (équipes suivies, ligues suivies, internationaux, reste), bandeau (`WeekStrip`), nombre de matchs du jour, résultats (72 h, suivis d'abord, 8) et activité (6) ; « vient de finir » = fin de la dernière game en cache du match, sinon son début (aucune heure inventée) ; record de kills = maximum de toutes les games visibles, montré seulement s'il date de ≤ 7 jours. Joueurs en forme : `HomeFeed.topPlayers(…period:…)` (semaine : 7 jours, 2 games ; saison : 5 games).
- **Calendrier** : grille de semaines entières à partir de `calendar.firstWeekday` (lundi en France) ; `followed` = ids de match (calculés par `HomeFeed.followedMatchIds`) pour que L8 ne dépende pas de L5 ; `CalendarMonth.pageNeeded` dit quelle page `older` / `newer` lire.

## Matrice des fichiers

Chemins relatifs à `LoLKit/`. Tests dans `Tests/LoLKitTests/`, fixtures dans `Tests/LoLKitTests/Fixtures/season/`.

| Tâche | Vague | Branche | Crée | Modifie (seule tâche autorisée) |
|---|---|---|---|---|
| L1 API saison | 1 | `nuit2/lolkit-l1-api-saison` | `Sources/LoLKit/Season/TournamentRef.swift`, `Season/CompletedMatch.swift`, `Season/Standings.swift`, `Season/SeasonMatch.swift`, `API/LoLClient+Season.swift`, `SeasonAPITests.swift`, fixture `getCompletedEvents_lec3_ids.json` | `Sources/LoLKit/API/LoLClient.swift`, `Sources/LoLKit/Models/Team.swift` |
| L2 Game réduite | 1 | `nuit2/lolkit-l2-game-summary` | `Season/GameSummary.swift`, `Season/GameWinners.swift`, `Season/PlayerName.swift`, `GameSummaryTests.swift`, `GameWinnersTests.swift`, `Support/SeasonFixture.swift` | `Sources/LoLKit/Models/LiveWindow.swift` |
| L5 Ligues et réglages | 1 | `nuit2/lolkit-l5-ligues-reglages` | `LeagueFollowTests.swift` | `Follow/FollowList.swift`, `Follow/ScheduleQuery.swift`, `Reminders/MatchReminders.swift`, `Storage/AppSettings.swift`, `PublicInitTests.swift` |
| L8 Calendrier | 1 | `nuit2/lolkit-l8-calendrier` | `Calendar/CalendarMonth.swift`, `Calendar/WeekStrip.swift`, `CalendarTests.swift` | — |
| L3 Agrégats | 2 | `nuit2/lolkit-l3-agregats` | `Season/SeasonScope.swift`, `Season/SeasonStats.swift`, `Season/TeamSeason.swift`, `Season/PlayerSeason.swift`, `Season/SeasonMasking.swift`, `Season/Duel.swift`, `SeasonStatsTests.swift`, `DuelTests.swift`, `Support/SeasonMatches.swift` | — |
| L4 Collecte | 2 | `nuit2/lolkit-l4-collecte` | `Season/CrawlPlanner.swift`, `Season/CrawlPacer.swift`, `CrawlPlannerTests.swift` | — |
| L6 Tableaux | 2 | `nuit2/lolkit-l6-tableaux` | `Season/StandingsTable.swift`, `Season/StandingsMasking.swift`, `StandingsTableTests.swift`, fixture `getStandings_worlds25_reduced.json` | — |
| L7 Accueil pur | 3 | `nuit2/lolkit-l7-accueil` | `Home/MustWatch.swift`, `Home/HomeFeed.swift`, `MustWatchTests.swift`, `HomeFeedTests.swift` | — |

Aucun chemin n'apparaît sur deux lignes ; chaque fichier existant modifié a un seul propriétaire. Noms de types, de suites et d'aides de test sans collision (vérifié : les huit tâches fusionnées compilent sans avertissement). Les aides de test privées de fichier (`seasonJSON` en L1, `close` en L3) sont `private`.

## Dépendances

| Tâche | Dépend de | Ce qu'elle consomme | Comment, en parallèle |
|---|---|---|---|
| L1, L2, L5, L8 | — | code déjà à `HEAD` | vague 1, partent de `main` actuel |
| L3 | L1, L2 | `SeasonMatch`, `TournamentRef.year`, `Team.players`, `TeamPlayer` ; `GameSummary` et ses lignes, `GameResult`, `GameWinners.apply`, `SeasonFixture` (tests) | vague 2 : worktree créé depuis `main` **après** la fusion de L1 et L2 |
| L4 | L1, L2 | `SeasonMatch`, `TournamentRef`, `Standings`, `StandingsResponse`, `LoLClient.tournaments` ; `GameSummary`, `TeamGameLine`, `SeasonFixture.data` | vague 2, idem |
| L6 | L1 (+ L2 pour l'aide de test `SeasonFixture.data`) | `Standings`, `StandingsStage`, `StandingsSection`, `BracketMatch`, `Ranking`, `RankedTeam`, `StandingsResponse` | vague 2, idem |
| L7 | L3, L6, L8 (+ L1, L5) | `SeasonStats.streak/topPlayers`, `SeasonMasking`, `Streak`, `PlayerMetric`, `PlayerSeason` ; `StandingsTable.swissRecords`, `StandingsMasking.isMasked` ; `WeekStrip.days`, `CalendarMonth.events`, `CalendarDay` ; `SeasonMatch.resolve`, `Standings.match(id:)` / `stage(containing:)` ; `FollowList.league(slug:)` / `follow(league:)` ; tests : `SeasonFixture.kcMatches()` / `kcGames()` (L3) | vague 3 : worktree créé depuis `main` **après** la fusion de la vague 2 |

Une tâche dépendante **ne démarre jamais** sur une branche non fusionnée ni ne recopie le code d'une autre tâche : elle part de `main` une fois la vague précédente fusionnée et sa CI `LoLKit` verte sur `main`.

**Vérifié avant d'écrire ce plan** (copie de `HEAD` = `ca921f4` hors du dépôt, Docker `swift:6.2`, LoLKit identique à `ab700f5`) : `HEAD` = **320 tests dans 37 suites**. Vague 1, chaque tâche seule sur `HEAD` : L1 → 334 / 38, L2 → 332 / 39, L5 → 328 / 38, L8 → 325 / 38 ; vague 1 fusionnée : **359 tests / 42 suites**. Vague 2, chaque tâche seule sur la vague 1 : L3 → 374 / 44, L4 → 371 / 43, L6 → 364 / 43 ; vague 2 fusionnée : **391 / 46**. Vague 3 : L7 sur la vague 2 → **407 tests dans 48 suites**. Aucun avertissement. Ordre de fusion indifférent dans une vague (fichiers disjoints).

**Mise en place (contrôleur, avant chaque tâche) :**

```bash
git fetch origin && git worktree add ../faille-lN -b nuit2/lolkit-lN-<slug> origin/main
```

L'implémenteur travaille dans `../faille-lN` ; `scripts/lolkit.sh` y crée son propre volume Docker. **Fusion (contrôleur, à la fin de chaque vague)** : `gh api repos/cafe1231/faille/merges -f base=main -f head=<branche> -f commit_message="merge: <branche>"` pour chaque branche à CI verte, puis `git pull` sur `main` et `bash scripts/lolkit.sh test` → total attendu ci-dessus, puis CI `LoLKit` verte sur le SHA complet de `main`, avant de lancer la vague suivante.

---

### Task L1: API saison — tournois, matchs terminés, classements, page de calendrier, effectif

**Branche :** `nuit2/lolkit-l1-api-saison` — **Vague 1**

**Files:**
- Create: `LoLKit/Sources/LoLKit/Season/TournamentRef.swift`, `LoLKit/Sources/LoLKit/Season/CompletedMatch.swift`, `LoLKit/Sources/LoLKit/Season/Standings.swift`, `LoLKit/Sources/LoLKit/Season/SeasonMatch.swift`, `LoLKit/Sources/LoLKit/API/LoLClient+Season.swift`
- Modify: `LoLKit/Sources/LoLKit/API/LoLClient.swift` (`api` passe de `private` à interne), `LoLKit/Sources/LoLKit/Models/Team.swift` (`players`, `TeamPlayer`)
- Test: `LoLKit/Tests/LoLKitTests/SeasonAPITests.swift`
- Fixture créée : `LoLKit/Tests/LoLKitTests/Fixtures/season/getCompletedEvents_lec3_ids.json` (LEC Split 3 entier, 53 matchs, réduit aux ids). Fixtures lues (déjà au dépôt) : `getTournamentsForLeague_lec_reduced.json`, `getCompletedEvents_lec3_reduced.json`, `getStandings_lec3_reduced.json`, `getStandings_worlds26_reduced.json`, `getSchedule_lec_page1_reduced.json`, `getTeams_karmine-corp.json`.

**Interfaces:**
- Consumes (à `HEAD`) : `LoLClient.api<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T` (aujourd'hui `private`) ; `struct LossyArray<Element: Decodable>: Decodable { var elements: [Element] }` ; `JSONDecoder.lolesports()` ; `MatchTeam(id: String?, name: String, code: String, image: String?, result: Result?)`, `MatchTeam.gameWins: Int`, `MatchTeam.isPlaceholder: Bool`, `MatchTeam.isSame(as: FollowedTeam) -> Bool` ; `FollowedTeam(team: Team)` ; `Strategy.count: Int` ; `EventState` (`.unknown` pour une valeur inconnue) ; `MatchEvent` ; `Cached<Value>(value:fetchedAt:)` ; tests : `FakeTransport.on(_ fragment: String, status: Int = 200, fixture: String? = nil, body: String = "")`, `queryValue(_:_:)`, `date(_:)`, `catalogTeam(_:)`, `Fixture.Missing(name:)`, `TeamsResponse`.
- Produces :
  - `public struct TournamentRef: Codable, Sendable, Equatable, Identifiable { id, slug, startDate, endDate: String; var leagueId: String; init(id:slug:startDate:endDate:leagueId:); var year: Int?; func isActive(today: String) -> Bool }`
  - `public struct CompletedMatch: Codable, Sendable, Equatable, Identifiable { matchId: String; startTime: Date; blockName: String?; bestOf: Int; teams: [MatchTeam]; gameIds: [String]; var playedGameIds: [String] }`
  - `public struct Standings { stages: [StandingsStage]; var allMatches: [BracketMatch]; func stage(containing: String) -> StandingsStage?; func match(id: String) -> BracketMatch? }`, `StandingsStage { id, name, slug: String; sections }`, `StandingsSection { name; matches: [BracketMatch]; rankings: [Ranking] }`, `BracketMatch { id: String; state: EventState; teams: [MatchTeam] }`, `Ranking { ordinal: Int; teams: [RankedTeam] }`, `RankedTeam { id, code, name: String; image: String?; wins, losses: Int }` — tous `Codable, Sendable, Equatable`, avec `init` public.
  - `public struct SeasonMatch: Codable, Sendable, Equatable, Identifiable { id, tournamentId, leagueSlug: String; stageSlug: String?; startTime: Date; blockName: String?; bestOf: Int; teams: [MatchTeam]; playedGameIds: [String]; func involves(_ teamId: String) -> Bool; static func join(completed:standings:tournamentId:leagueSlug:catalog:) -> [SeasonMatch] }` ; `static func resolve(_ team: MatchTeam, in catalog: [Team]) -> MatchTeam` (interne).
  - `public struct SchedulePageResult: Sendable, Equatable { events: [MatchEvent]; older: String?; newer: String? }`.
  - `LoLClient.tournaments(leagueId:) async throws -> [TournamentRef]`, `completedEvents(tournamentId:) async throws -> [CompletedMatch]`, `standings(tournamentId:) async throws -> Standings`, `schedulePage(leagueIds: [String], pageToken: String?) async throws -> SchedulePageResult`.
  - `Team.players: [TeamPlayer]?`, `Team.init(…, homeLeague:, players: [TeamPlayer]? = nil)` ; `public struct TeamPlayer: Codable, Sendable, Equatable, Identifiable { id, summonerName: String; image, role: String? }`.
  - Internes : `TournamentsResponse`, `CompletedEventsResponse`, `StandingsResponse`, `SchedulePageResponse`.

- [ ] **Step 1: Produire la fixture `getCompletedEvents_lec3_ids.json`**

Source : la capture brute du 14/10/2026 (`getCompletedEvents?hl=fr-FR&tournamentId=115548681802226458`, 61 277 o) du dossier de travail ; si elle a disparu, une seule requête.

```bash
RAW=$(mktemp -d)
SRC="/c/Users/Dan/AppData/Local/Temp/claude/C--Users-Dan-Desktop-01-Dev-App-Esport-en-direct/497551d5-ffb1-472a-813a-0380440095c9/scratchpad/raw/completed_lec3.json"
if [ -f "$SRC" ]; then cp "$SRC" "$RAW/completed.json"; else
  curl -s -H "x-api-key: 0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z" -o "$RAW/completed.json" \
    "https://esports-api.lolesports.com/persisted/gw/getCompletedEvents?hl=fr-FR&tournamentId=115548681802226458"
fi
python -I - "$RAW/completed.json" LoLKit/Tests/LoLKitTests/Fixtures/season/getCompletedEvents_lec3_ids.json <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
events = json.load(open(src, encoding="utf-8"))["data"]["schedule"]["events"]
out = []
for e in events:
    m = e["match"]
    out.append({
        "startTime": e["startTime"],
        "blockName": e.get("blockName"),
        "league": {"name": e["league"]["name"]},
        "match": {
            "id": m["id"],
            "teams": [{"name": t["name"], "code": t["code"], "result": {"gameWins": t["result"]["gameWins"]}} for t in m["teams"]],
            "strategy": {"type": m["strategy"]["type"], "count": m["strategy"]["count"]},
        },
        "games": [{"id": g["id"]} for g in e.get("games", [])],
    })
with open(dst, "wb") as f:
    f.write((json.dumps({"data": {"schedule": {"events": out}}}, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
PY
sha256sum LoLKit/Tests/LoLKitTests/Fixtures/season/getCompletedEvents_lec3_ids.json
```

Expected : `3a57d35ad075291ce3dc599b80f5646aee4a728f4cd80cf6dc6dbce8fdd24351`, 38 516 octets (53 événements, 175 ids de game). Empreinte différente : s'arrêter et le signaler.

- [ ] **Step 2: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/SeasonAPITests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Fixture réelle réduite du dossier `Fixtures/season/` (capturée le 14/10/2026, spec saison §1.1).
private func seasonJSON(_ name: String) throws -> String {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/season") else {
        throw Fixture.Missing(name: "season/\(name)")
    }
    return try String(contentsOf: url, encoding: .utf8)
}

/// API de la saison (spec saison §1.1, §1.2) : tournois, matchs terminés, classements, page de calendrier, effectif.
@Suite struct SeasonAPITests {
    private static let lec = "98767991302996019"
    private static let lecSplit3 = "115548681802226458"
    private static let kc = "111692118851466302"

    @Test func tournamentsOfALeagueNewestFirstWithTheLeagueId() async throws {
        let fake = FakeTransport()
        try await fake.on("getTournamentsForLeague", body: try seasonJSON("getTournamentsForLeague_lec_reduced"))
        let tournaments = try await LoLClient(transport: fake).tournaments(leagueId: Self.lec)
        #expect(tournaments.map(\.slug) == ["lec_split_3_2026", "lec_split_2_2026", "lec_split_1_2026", "lec_summer_2025"])
        #expect(tournaments[0] == TournamentRef(id: Self.lecSplit3, slug: "lec_split_3_2026", startDate: "2026-07-23",
                                                endDate: "2026-09-20", leagueId: Self.lec))
        #expect(tournaments.allSatisfy { $0.leagueId == Self.lec })
        #expect(tournaments.map(\.year) == [2026, 2026, 2026, 2025])

        let request = try #require(await fake.requests.first)
        #expect(request.url.path == "/persisted/gw/getTournamentsForLeague")
        #expect(queryValue(request.url, "leagueId") == Self.lec)
        #expect(queryValue(request.url, "hl") == "fr-FR")
        #expect(request.headers["x-api-key"] == LoLClient.publicAPIKey)
    }

    /// Actif de la date de début à la date de fin + 2 jours (§1.2).
    @Test func aTournamentIsActiveUntilTwoDaysAfterItsEnd() {
        let split3 = TournamentRef(id: Self.lecSplit3, slug: "lec_split_3_2026", startDate: "2026-07-23",
                                   endDate: "2026-09-20", leagueId: Self.lec)
        #expect(!split3.isActive(today: "2026-07-22"))
        #expect(split3.isActive(today: "2026-07-23"))
        #expect(split3.isActive(today: "2026-09-22"))
        #expect(!split3.isActive(today: "2026-09-23"))
        // Fin de mois et d'année.
        let worlds = TournamentRef(id: "w", slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-12-30", leagueId: "")
        #expect(worlds.isActive(today: "2027-01-01"))
        #expect(!worlds.isActive(today: "2027-01-02"))
        #expect(!TournamentRef(id: "x", slug: "", startDate: "", endDate: "", leagueId: "").isActive(today: "2026-10-15"))
    }

    /// KC 1-3 G2 (Bo5, game 5 listée mais pas jouée) et KC 2-0 VIT (Bo3, game 3 pas jouée).
    @Test func completedEventsListAllGamesAndThePlayedOnes() async throws {
        let fake = FakeTransport()
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_reduced"))
        let matches = try await LoLClient(transport: fake).completedEvents(tournamentId: Self.lecSplit3)
        #expect(matches.map(\.matchId) == ["115548681803406303", "115548681803406199"])
        let final = matches[0]
        #expect(final.startTime == date("2026-09-06T15:00:00Z"))
        #expect(final.blockName == "Play-offs")
        #expect(final.bestOf == 5)
        #expect(final.teams.map(\.code) == ["KC", "G2"])
        #expect(final.teams.map(\.gameWins) == [1, 3])
        #expect(final.teams.allSatisfy { $0.id == nil })
        #expect(final.gameIds.count == 5)
        #expect(final.playedGameIds == ["115548681803406304", "115548681803406305", "115548681803406306",
                                        "115548681803406307"])
        #expect(matches[1].bestOf == 3)
        #expect(matches[1].playedGameIds == ["115548681803406200", "115548681803406201"])
        #expect(queryValue(try #require(await fake.requests.first?.url), "tournamentId") == Self.lecSplit3)
    }

    /// LEC Split 3 entier (53 matchs) : 175 games listées, 137 jouées (§1.1).
    @Test func lecSplit3Has137PlayedGamesOutOf175Listed() async throws {
        let fake = FakeTransport()
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_ids"))
        let matches = try await LoLClient(transport: fake).completedEvents(tournamentId: Self.lecSplit3)
        #expect(matches.count == 53)
        #expect(matches.reduce(0) { $0 + $1.gameIds.count } == 175)
        #expect(matches.reduce(0) { $0 + $1.playedGameIds.count } == 137)
    }

    /// Classement de la saison régulière (KC 9-0, VIT 7-2, G2 6-3) et play-offs sans classement, ids d'équipe présents.
    @Test func standingsOfTheLecSplit() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: try seasonJSON("getStandings_lec3_reduced"))
        let standings = try await LoLClient(transport: fake).standings(tournamentId: Self.lecSplit3)
        #expect(standings.stages.map(\.slug) == ["regular_season", "playoffs"])
        #expect(standings.stages[0].name == "Saison régulière")
        let rankings = standings.stages[0].sections[0].rankings
        #expect(rankings.map(\.ordinal) == [1, 2, 3])
        #expect(rankings[0].teams == [RankedTeam(id: Self.kc, code: "KC", name: "Karmine Corp",
                                                 image: "http://static.lolesports.com/teams/1704714951336_KC.png",
                                                 wins: 9, losses: 0)])
        #expect(rankings.map { "\($0.teams[0].code) \($0.teams[0].wins)-\($0.teams[0].losses)" } == ["KC 9-0", "VIT 7-2", "G2 6-3"])
        #expect(standings.stages[1].sections[0].rankings.isEmpty)
        let kcMkoi = try #require(standings.match(id: "115548681803406327"))
        #expect(kcMkoi.state == .completed)
        #expect(kcMkoi.teams.map(\.id) == [Self.kc, "103461966965149786"])
        #expect(kcMkoi.teams.map { $0.result?.outcome } == ["loss", "win"])
        #expect(standings.stage(containing: "115548681803406327")?.slug == "playoffs")
        #expect(standings.stage(containing: "inconnu") == nil)
        #expect(standings.allMatches.count == 4)
    }

    /// Mondial 2026 avant son début : trois étapes, jamais de `rankings`, équipes à venir `id "0"` / `TBD`.
    @Test func worldsStandingsHavePlaceholders() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: try seasonJSON("getStandings_worlds26_reduced"))
        let standings = try await LoLClient(transport: fake).standings(tournamentId: "115660540725177488")
        #expect(standings.stages.map(\.slug) == ["play_ins", "swiss", "knockouts"])
        #expect(standings.stages.allSatisfy { $0.sections.allSatisfy(\.rankings.isEmpty) })
        let tbd = try #require(standings.stages[1].sections[0].matches.first?.teams.first)
        #expect(tbd.id == "0")
        #expect(tbd.isPlaceholder)
        #expect(tbd.result == nil)
        #expect(standings.match(id: "115660588583171786")?.teams.map(\.code) == ["C9", "KC"])
    }

    @Test func noStandingsGivesNoStage() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: #"{"data":{"standings":[]}}"#)
        #expect(try await LoLClient(transport: fake).standings(tournamentId: "x") == Standings(stages: []))
    }

    /// Décodage tolérant : un champ retiré ne fait échouer ni l'étape, ni la section, ni l'équipe classée.
    @Test func standingsDecodeTolerantly() throws {
        let json = #"""
        {"data":{"standings":[{"stages":[
          {"id":"s1","sections":[{"matches":[{"id":"m1","teams":[{"id":"a","name":"A","code":"A","result":null}]},
                                              {"state":"completed"}]}]},
          {"id":"s2","name":"Play-offs","slug":"playoffs","sections":[{"name":"P","rankings":[{"ordinal":1,"teams":[{"id":"a"}]}]}]},
          {"name":"sans id"}
        ]}]}}
        """#
        let standings = try JSONDecoder.lolesports().decode(StandingsResponse.self, from: Data(json.utf8))
            .data.standings.elements[0]
        #expect(standings.stages.map(\.id) == ["s1", "s2"])
        #expect(standings.stages[0].name == "" && standings.stages[0].slug == "")
        #expect(standings.stages[0].sections[0].matches.map(\.id) == ["m1"])
        #expect(standings.stages[0].sections[0].matches[0].state == .unknown)
        #expect(standings.stages[0].sections[0].rankings.isEmpty)
        #expect(standings.stages[1].sections[0].matches.isEmpty)
        #expect(standings.stages[1].sections[0].rankings[0].teams == [RankedTeam(id: "a", code: "", name: "", image: nil,
                                                                                  wins: 0, losses: 0)])
    }

    @Test func completedEventsDecodeTolerantly() throws {
        let json = #"""
        {"data":{"schedule":{"events":[
          {"startTime":"2026-09-06T15:00:00Z","match":{"id":"m1"}},
          {"startTime":"2026-09-06T15:00:00Z","match":{"teams":[]}},
          {"match":{"id":"m3"}}
        ]}}}
        """#
        let events = try JSONDecoder.lolesports().decode(CompletedEventsResponse.self, from: Data(json.utf8))
            .data.schedule.events.elements.map(\.completed)
        #expect(events == [CompletedMatch(matchId: "m1", startTime: date("2026-09-06T15:00:00Z"), blockName: nil,
                                          bestOf: 1, teams: [], gameIds: [])])
    }

    /// Le cache disque (`Cached<…>`, `JSONEncoder` par défaut) se relit à l'identique.
    @Test func seasonValuesRoundTripThroughTheDiskCache() async throws {
        let fake = FakeTransport()
        try await fake.on("getStandings", body: try seasonJSON("getStandings_lec3_reduced"))
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_reduced"))
        try await fake.on("getTournamentsForLeague", body: try seasonJSON("getTournamentsForLeague_lec_reduced"))
        let client = LoLClient(transport: fake)
        let fetchedAt = date("2026-10-14T20:00:00Z")

        let standings = Cached(value: try await client.standings(tournamentId: Self.lecSplit3), fetchedAt: fetchedAt)
        #expect(try JSONDecoder().decode(Cached<Standings>.self, from: JSONEncoder().encode(standings)) == standings)
        let completed = Cached(value: try await client.completedEvents(tournamentId: Self.lecSplit3), fetchedAt: fetchedAt)
        #expect(try JSONDecoder().decode(Cached<[CompletedMatch]>.self, from: JSONEncoder().encode(completed)) == completed)
        let tournaments = Cached(value: try await client.tournaments(leagueId: Self.lec), fetchedAt: fetchedAt)
        #expect(try JSONDecoder().decode(Cached<[TournamentRef]>.self, from: JSONEncoder().encode(tournaments)) == tournaments)
    }

    /// Page `older` du calendrier LEC : jetons de pagination et matchs (sans id de game ni d'équipe).
    @Test func schedulePageCarriesThePageTokens() async throws {
        let fake = FakeTransport()
        try await fake.on("getSchedule", body: try seasonJSON("getSchedule_lec_page1_reduced"))
        let page = try await LoLClient(transport: fake)
            .schedulePage(leagueIds: [Self.lec], pageToken: "b2xkZXI6OjExNTU0ODY2ODA1OTU4OTMyMA==")
        #expect(page.older == "b2xkZXI6OjExNTU0ODQyNDMwODQxNDI0NA==")
        #expect(page.newer == "bmV3ZXI6OjExNTU0ODY2ODA1OTUyMzc1Mg==")
        #expect(page.events.map(\.id) == ["115548424308414244", "115548424308414224"])
        #expect(page.events[0].match.teams.map(\.code) == ["LR", "TH"])
        let url = try #require(await fake.requests.first?.url)
        #expect(queryValue(url, "pageToken") == "b2xkZXI6OjExNTU0ODY2ODA1OTU4OTMyMA==")
        #expect(queryValue(url, "leagueId") == Self.lec)

        // Sans jeton : la page autour d'aujourd'hui ; `pages` absent → aucun jeton.
        let empty = FakeTransport()
        try await empty.on("getSchedule", body: #"{"data":{"schedule":{"events":[]}}}"#)
        let first = try await LoLClient(transport: empty).schedulePage(leagueIds: [], pageToken: nil)
        #expect(queryValue(try #require(await empty.requests.first?.url), "pageToken") == nil)
        #expect(first == SchedulePageResult(events: [], older: nil, newer: nil))
    }

    /// Effectif de KC dans `getTeams` : 5 joueurs avec rôle ; `id` = `esportsPlayerId` du flux.
    @Test func teamsCarryTheirRoster() async throws {
        let fake = FakeTransport()
        try await fake.on("getTeams", body: try seasonJSON("getTeams_karmine-corp"))
        let kc = try #require(try await LoLClient(transport: fake).teams().first)
        let players = try #require(kc.players)
        #expect(players.count == 5)
        #expect(players[0] == TeamPlayer(id: "103495716771322725", summonerName: "Canna",
                                         image: "http://static.lolesports.com/players/1774651372836_canna.png",
                                         role: "top"))
        #expect(players.map(\.role) == ["top", "jungle", "bottom", "mid", "support"])
        #expect(kc.homeLeague?.name == "LEC")
    }

    /// Le catalogue réduit déjà au dépôt (un joueur par équipe) se lit aussi ; un effectif absent donne nil, un effectif
    /// illisible ne retire pas l'équipe.
    @Test func rosterIsOptionalAndTolerant() throws {
        #expect(try catalogTeam("KC").players?.map(\.summonerName) == ["Canna"])
        let json = #"""
        {"data":{"teams":[
          {"id":"1","slug":"a","name":"A","code":"A","status":"active","players":"oups"},
          {"id":"2","slug":"b","name":"B","code":"B","players":[{"id":"p1","summonerName":"Un"},{"summonerName":"sans id"}]},
          {"id":"3","slug":"c","name":"C","code":"C"}
        ]}}
        """#
        let teams = try JSONDecoder.lolesports().decode(TeamsResponse.self, from: Data(json.utf8)).data.teams.elements
        #expect(teams.map(\.id) == ["1", "2", "3"])
        #expect(teams[0].players == nil)
        #expect(teams[2].players == nil)
        #expect(teams[1].players == [TeamPlayer(id: "p1", summonerName: "Un", image: nil, role: nil)])
        let roundTrip = try JSONDecoder().decode(Team.self, from: JSONEncoder().encode(teams[1]))
        #expect(roundTrip == teams[1])
    }

    /// Jointure (§1.2) : ids d'équipe et étape depuis `getStandings` ; à défaut, ids du catalogue (nom, logo).
    @Test func seasonMatchesJoinCompletedEventsAndStandings() async throws {
        let fake = FakeTransport()
        try await fake.on("getCompletedEvents", body: try seasonJSON("getCompletedEvents_lec3_ids"))
        try await fake.on("getStandings", body: try seasonJSON("getStandings_lec3_reduced"))
        try await fake.on("getTeams", body: try seasonJSON("getTeams_karmine-corp"))
        let client = LoLClient(transport: fake)
        let completed = try await client.completedEvents(tournamentId: Self.lecSplit3)
        let standings = try await client.standings(tournamentId: Self.lecSplit3)
        let catalog = try await client.teams()

        let matches = SeasonMatch.join(completed: completed, standings: standings, tournamentId: Self.lecSplit3,
                                       leagueSlug: "lec", catalog: catalog)
        #expect(matches.count == 53)
        #expect(matches.map(\.id) == completed.map(\.matchId))
        #expect(matches.reduce(0) { $0 + $1.playedGameIds.count } == 137)

        // Dans les classements : ids et étape.
        let kcMkoi = try #require(matches.first { $0.id == "115548681803406327" })
        #expect(kcMkoi.stageSlug == "playoffs")
        #expect(kcMkoi.teams.map(\.id) == [Self.kc, "103461966965149786"])
        #expect(kcMkoi.involves(Self.kc))
        #expect(kcMkoi.tournamentId == Self.lecSplit3 && kcMkoi.leagueSlug == "lec")
        #expect(kcMkoi.bestOf == 5)
        let thNavi = try #require(matches.first { $0.id == "115548681803340575" })
        #expect(thNavi.stageSlug == "regular_season")

        // Hors des classements réduits : KC retrouvée dans le catalogue par son nom, G2 (absente du catalogue) sans id.
        let kcG2 = try #require(matches.first { $0.id == "115548681803406303" })
        #expect(kcG2.stageSlug == nil)
        #expect(kcG2.teams.map(\.id) == [Self.kc, nil])
        #expect(kcG2.teams.map(\.gameWins) == [1, 3])
        #expect(kcG2.playedGameIds.count == 4)
        #expect(matches.filter { $0.involves(Self.kc) }.count == 12)
    }
}
```

- [ ] **Step 3: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter SeasonAPITests`
Expected : échec de compilation (`cannot find 'TournamentRef' in scope`, `value of type 'LoLClient' has no member 'tournaments'`…).

- [ ] **Step 4: Rendre `api` interne**

Dans `LoLKit/Sources/LoLKit/API/LoLClient.swift` :

Remplacement 1/1 — remplacer exactement :

```swift
    private func api<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
```

par :

```swift
    /// Lecture d'une route de l'API (clé publique, `hl`) ; interne pour les extensions (`LoLClient+Season`).
    func api<T: Decodable>(_ endpoint: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
```

- [ ] **Step 5: Ajouter l'effectif au catalogue**

Remplacer tout le contenu de `LoLKit/Sources/LoLKit/Models/Team.swift` par :

```swift
/// Une équipe du catalogue (`getTeams`). `homeLeague.name` correspond à `League.name`.
public struct Team: Codable, Sendable, Equatable, Identifiable {
    public struct HomeLeague: Codable, Sendable, Equatable {
        public let name: String
        public let region: String?

        public init(name: String, region: String? = nil) {
            self.name = name
            self.region = region
        }
    }

    public let id: String
    public let slug: String
    public let name: String
    public let code: String
    public let image: String?
    public let status: String?
    public let homeLeague: HomeLeague?
    /// Effectif (`players[]` du catalogue, spec saison §1.5) ; nil si l'API n'en donne pas ou s'il est illisible.
    public let players: [TeamPlayer]?

    public init(id: String, slug: String, name: String, code: String, image: String?, status: String?, homeLeague: HomeLeague?,
                players: [TeamPlayer]? = nil) {
        self.id = id
        self.slug = slug
        self.name = name
        self.code = code
        self.image = image
        self.status = status
        self.homeLeague = homeLeague
        self.players = players
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, code, image, status, homeLeague, players
    }

    /// Mêmes exigences qu'avant l'effectif ; `players` absent ou illisible → nil (l'équipe reste dans le catalogue),
    /// un joueur illisible est ignoré.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        code = try container.decode(String.self, forKey: .code)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        homeLeague = try container.decodeIfPresent(HomeLeague.self, forKey: .homeLeague)
        players = (try? container.decodeIfPresent(LossyArray<TeamPlayer>.self, forKey: .players))?.elements
    }

    public var isActive: Bool { status == "active" }
}

/// Un joueur de l'effectif d'une équipe (`getTeams` : `players[]`). `id` = `esportsPlayerId` du flux livestats.
public struct TeamPlayer: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let summonerName: String
    public let image: String?
    /// `top`, `jungle`, `mid`, `bottom`, `support` (ou autre valeur de l'API, ex. `none`).
    public let role: String?

    public init(id: String, summonerName: String, image: String?, role: String?) {
        self.id = id
        self.summonerName = summonerName
        self.image = image
        self.role = role
    }

    private enum CodingKeys: String, CodingKey {
        case id, summonerName, image, role
    }

    /// `id` et `summonerName` indispensables ; photo et rôle illisibles → nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        summonerName = try container.decode(String.self, forKey: .summonerName)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        role = try? container.decodeIfPresent(String.self, forKey: .role)
    }
}

struct TeamsResponse: Decodable {
    struct Payload: Decodable {
        let teams: LossyArray<Team>
    }

    let data: Payload
}
```

- [ ] **Step 6: Écrire les modèles de la saison**

Créer `LoLKit/Sources/LoLKit/Season/TournamentRef.swift` :

```swift
import Foundation

/// Un tournoi d'une ligue (`getTournamentsForLeague`), ex. `lec_split_3_2026` du 23/07 au 20/09 (spec saison §1.2).
public struct TournamentRef: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let slug: String
    /// Dates « yyyy-MM-dd », telles que l'API les écrit.
    public let startDate: String
    public let endDate: String
    /// Ligue du tournoi : l'API ne le répète pas dans chaque tournoi, `LoLClient.tournaments(leagueId:)` le remplit.
    public var leagueId: String

    public init(id: String, slug: String, startDate: String, endDate: String, leagueId: String) {
        self.id = id
        self.slug = slug
        self.startDate = startDate
        self.endDate = endDate
        self.leagueId = leagueId
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, startDate, endDate, leagueId
    }

    /// Décodage tolérant : seul `id` est indispensable ; un champ absent ou illisible devient une chaîne vide.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = (try? container.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        startDate = (try? container.decodeIfPresent(String.self, forKey: .startDate)) ?? ""
        endDate = (try? container.decodeIfPresent(String.self, forKey: .endDate)) ?? ""
        leagueId = (try? container.decodeIfPresent(String.self, forKey: .leagueId)) ?? ""
    }

    /// Année de début : la saison est l'année civile, un tournoi à cheval compte dans l'année de son début (§1.2).
    public var year: Int? { Int(startDate.prefix(4)) }

    /// Actif si `today` (« yyyy-MM-dd ») est dans [début, fin + 2 jours] (§1.2 : relu au plus toutes les 30 min) ;
    /// terminé sinon (lu une fois, jamais relu). Faux si une date est illisible.
    public func isActive(today: String) -> Bool {
        guard Self.day(startDate) != nil, let end = Self.adding(days: 2, to: endDate) else { return false }
        return startDate <= today && today <= end
    }

    /// « yyyy-MM-dd » + `days` jours (calendrier grégorien, UTC) ; nil si la date est illisible.
    static func adding(days: Int, to string: String) -> String? {
        guard let date = day(string), let moved = utc.date(byAdding: .day, value: days, to: date) else { return nil }
        let parts = utc.dateComponents([.year, .month, .day], from: moved)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func day(_ string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

struct TournamentsResponse: Decodable {
    struct Payload: Decodable {
        let leagues: [LeagueTournaments]
    }

    struct LeagueTournaments: Decodable {
        let tournaments: LossyArray<TournamentRef>
    }

    let data: Payload
}
```

Créer `LoLKit/Sources/LoLKit/Season/CompletedMatch.swift` :

```swift
import Foundation

/// Un match terminé d'un tournoi (`getCompletedEvents?tournamentId=`), réduit à ce que la saison utilise : pas de
/// vods, pas d'id d'équipe (l'API n'en donne pas ici, `SeasonMatch.join` les retrouve). Encodé tel quel dans
/// `cache/season/completed/<tournamentId>.json` (`Cached<[CompletedMatch]>`).
public struct CompletedMatch: Codable, Sendable, Equatable, Identifiable {
    public let matchId: String
    public let startTime: Date
    public let blockName: String?
    public let bestOf: Int
    /// Équipes sans id, avec `result.gameWins`.
    public let teams: [MatchTeam]
    /// TOUTES les games listées par l'API, jouées ou non, dans l'ordre.
    public let gameIds: [String]

    public init(matchId: String, startTime: Date, blockName: String?, bestOf: Int, teams: [MatchTeam],
                gameIds: [String]) {
        self.matchId = matchId
        self.startTime = startTime
        self.blockName = blockName
        self.bestOf = bestOf
        self.teams = teams
        self.gameIds = gameIds
    }

    public var id: String { matchId }

    /// Games réellement jouées : les `Σ gameWins` premières de `gameIds` (règle vérifiée sur 280 matchs, spec §1.2).
    public var playedGameIds: [String] { Array(gameIds.prefix(teams.reduce(0) { $0 + $1.gameWins })) }
}

/// Forme de l'API : `events[] {startTime, blockName, league, match {id, teams, strategy}, games [{id, vods}]}`.
struct CompletedEventsResponse: Decodable {
    struct Payload: Decodable {
        let schedule: Schedule
    }

    struct Schedule: Decodable {
        let events: LossyArray<Event>
    }

    /// Un événement. `startTime` et `match.id` sont indispensables ; le reste a une valeur neutre.
    struct Event: Decodable {
        let completed: CompletedMatch

        private enum Keys: String, CodingKey {
            case startTime, blockName, match, games
        }

        private enum MatchKeys: String, CodingKey {
            case id, teams, strategy
        }

        private struct GameId: Decodable {
            let id: String
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let match = try container.nestedContainer(keyedBy: MatchKeys.self, forKey: .match)
            let teams = (try? match.decodeIfPresent(LossyArray<MatchTeam>.self, forKey: .teams))?.elements ?? []
            let strategy = try? match.decodeIfPresent(Strategy.self, forKey: .strategy)
            let games = (try? container.decodeIfPresent(LossyArray<GameId>.self, forKey: .games))?.elements ?? []
            completed = CompletedMatch(
                matchId: try match.decode(String.self, forKey: .id),
                startTime: try container.decode(Date.self, forKey: .startTime),
                blockName: try? container.decodeIfPresent(String.self, forKey: .blockName),
                bestOf: strategy?.count ?? 1,
                teams: teams,
                gameIds: games.map(\.id)
            )
        }
    }

    let data: Payload
}
```

Créer `LoLKit/Sources/LoLKit/Season/Standings.swift` :

```swift
import Foundation

/// Classements et tableaux d'un tournoi (`getStandings?tournamentId=`) : étapes → sections → matchs (avec ids d'équipe
/// et résultats) et classements. Encodé tel quel dans `cache/season/standings/<tournamentId>.json`.
public struct Standings: Codable, Sendable, Equatable {
    public let stages: [StandingsStage]

    public init(stages: [StandingsStage]) {
        self.stages = stages
    }

    private enum CodingKeys: String, CodingKey {
        case stages
    }

    /// Une étape illisible est ignorée ; `stages` absent → aucune étape.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stages = (try? container.decodeIfPresent(LossyArray<StandingsStage>.self, forKey: .stages))?.elements ?? []
    }

    /// Tous les matchs de toutes les étapes, dans l'ordre de l'API.
    public var allMatches: [BracketMatch] {
        stages.flatMap { $0.sections.flatMap(\.matches) }
    }

    /// Étape qui contient le match `matchId` ; nil s'il n'y figure pas.
    public func stage(containing matchId: String) -> StandingsStage? {
        stages.first { stage in stage.sections.contains { $0.matches.contains { $0.id == matchId } } }
    }

    /// Le match `matchId` ; nil s'il n'y figure pas.
    public func match(id matchId: String) -> BracketMatch? {
        allMatches.first { $0.id == matchId }
    }
}

/// Une étape : `regular_season`, `playoffs`, `play_ins`, `swiss`, `knockouts`…
public struct StandingsStage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let slug: String
    public let sections: [StandingsSection]

    public init(id: String, name: String, slug: String, sections: [StandingsSection]) {
        self.id = id
        self.name = name
        self.slug = slug
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, sections
    }

    /// Seul `id` est indispensable ; nom et slug absents → chaîne vide, sections illisibles ignorées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        slug = (try? container.decodeIfPresent(String.self, forKey: .slug)) ?? ""
        sections = (try? container.decodeIfPresent(LossyArray<StandingsSection>.self, forKey: .sections))?.elements ?? []
    }
}

public struct StandingsSection: Codable, Sendable, Equatable {
    public let name: String
    public let matches: [BracketMatch]
    /// Vide pour le Mondial (jamais de `rankings`, mesuré sur 2025 et 2026) et les play-offs.
    public let rankings: [Ranking]

    public init(name: String, matches: [BracketMatch], rankings: [Ranking]) {
        self.name = name
        self.matches = matches
        self.rankings = rankings
    }

    private enum CodingKeys: String, CodingKey {
        case name, matches, rankings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        matches = (try? container.decodeIfPresent(LossyArray<BracketMatch>.self, forKey: .matches))?.elements ?? []
        rankings = (try? container.decodeIfPresent(LossyArray<Ranking>.self, forKey: .rankings))?.elements ?? []
    }
}

/// Un match d'un tableau, avec les ids d'équipe. Équipe pas encore connue : `id "0"`, `code "TBD"`, `result` nil
/// (`MatchTeam.isPlaceholder`).
public struct BracketMatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let state: EventState
    public let teams: [MatchTeam]

    public init(id: String, state: EventState, teams: [MatchTeam]) {
        self.id = id
        self.state = state
        self.teams = teams
    }

    private enum CodingKeys: String, CodingKey {
        case id, state, teams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = (try? container.decodeIfPresent(EventState.self, forKey: .state)) ?? .unknown
        teams = (try? container.decodeIfPresent(LossyArray<MatchTeam>.self, forKey: .teams))?.elements ?? []
    }
}

/// Une place du classement (ex aequo possibles : plusieurs équipes au même `ordinal`).
public struct Ranking: Codable, Sendable, Equatable {
    public let ordinal: Int
    public let teams: [RankedTeam]

    public init(ordinal: Int, teams: [RankedTeam]) {
        self.ordinal = ordinal
        self.teams = teams
    }

    private enum CodingKeys: String, CodingKey {
        case ordinal, teams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ordinal = (try? container.decodeIfPresent(Int.self, forKey: .ordinal)) ?? 0
        teams = (try? container.decodeIfPresent(LossyArray<RankedTeam>.self, forKey: .teams))?.elements ?? []
    }
}

/// Une équipe classée et son bilan de séries (`record {wins, losses}` dans l'API, aplati ici).
public struct RankedTeam: Codable, Sendable, Equatable {
    public let id: String
    public let code: String
    public let name: String
    public let image: String?
    public let wins: Int
    public let losses: Int

    public init(id: String, code: String, name: String, image: String?, wins: Int, losses: Int) {
        self.id = id
        self.code = code
        self.name = name
        self.image = image
        self.wins = wins
        self.losses = losses
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, image, record
    }

    private struct Record: Codable {
        var wins: Int?
        var losses: Int?
    }

    /// Seul `id` est indispensable ; `record` absent → 0-0.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = (try? container.decodeIfPresent(String.self, forKey: .code)) ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        let record = try? container.decodeIfPresent(Record.self, forKey: .record)
        wins = record?.wins ?? 0
        losses = record?.losses ?? 0
    }

    /// Même forme que l'API (`record` imbriqué) : le cache se relit avec le même décodeur.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encode(Record(wins: wins, losses: losses), forKey: .record)
    }
}

struct StandingsResponse: Decodable {
    struct Payload: Decodable {
        let standings: LossyArray<Standings>
    }

    let data: Payload
}
```

Créer `LoLKit/Sources/LoLKit/Season/SeasonMatch.swift` :

```swift
import Foundation

/// Un match joué de la saison : l'événement de `getCompletedEvents` (ids des games) joint au match de même id dans
/// `getStandings` (ids d'équipe, `outcome`, étape) — spec saison §1.2. Jamais stocké : recalculé à la lecture.
public struct SeasonMatch: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let tournamentId: String
    public let leagueSlug: String
    /// Étape de `getStandings` qui contient le match (`regular_season`, `swiss`, `knockouts`…) ; nil si absent.
    public let stageSlug: String?
    public let startTime: Date
    public let blockName: String?
    public let bestOf: Int
    /// Équipes avec id quand il est connu : `SpoilerPolicy.isMasked` s'applique directement.
    public let teams: [MatchTeam]
    public let playedGameIds: [String]

    public init(id: String, tournamentId: String, leagueSlug: String, stageSlug: String?, startTime: Date,
                blockName: String?, bestOf: Int, teams: [MatchTeam], playedGameIds: [String]) {
        self.id = id
        self.tournamentId = tournamentId
        self.leagueSlug = leagueSlug
        self.stageSlug = stageSlug
        self.startTime = startTime
        self.blockName = blockName
        self.bestOf = bestOf
        self.teams = teams
        self.playedGameIds = playedGameIds
    }

    /// Vrai si l'équipe `teamId` joue ce match (par id : une équipe sans id n'est rattachée à rien).
    public func involves(_ teamId: String) -> Bool {
        teams.contains { $0.id == teamId }
    }

    /// Jointure (§1.2, « jointure par id de match ») : équipes, résultats et étape du match de même id dans
    /// `standings` ; à défaut, équipes de `getCompletedEvents` rapprochées du catalogue par `MatchTeam.isSame` (nom,
    /// logo ; jamais le code seul), une équipe active d'abord. Une équipe introuvable garde `id` nil : le match ne
    /// compte pas dans son bilan (pas de faux chiffre). Ordre : celui de `completed`.
    public static func join(completed: [CompletedMatch], standings: Standings?, tournamentId: String,
                            leagueSlug: String, catalog: [Team]) -> [SeasonMatch] {
        completed.map { match in
            let stage = standings?.stage(containing: match.matchId)
            let bracket = standings?.match(id: match.matchId)
            let teams: [MatchTeam]
            if let bracket, bracket.teams.count == match.teams.count, !bracket.teams.contains(where: \.isPlaceholder) {
                teams = bracket.teams
            } else {
                teams = match.teams.map { resolve($0, in: catalog) }
            }
            return SeasonMatch(id: match.matchId, tournamentId: tournamentId, leagueSlug: leagueSlug,
                               stageSlug: stage?.slug, startTime: match.startTime, blockName: match.blockName,
                               bestOf: match.bestOf, teams: teams, playedGameIds: match.playedGameIds)
        }
    }

    /// L'équipe avec l'id du catalogue (actives d'abord), ou telle quelle si rien ne correspond.
    static func resolve(_ team: MatchTeam, in catalog: [Team]) -> MatchTeam {
        guard team.id == nil, !team.isPlaceholder else { return team }
        let matches: (Team) -> Bool = { team.isSame(as: FollowedTeam(team: $0)) }
        guard let found = catalog.first(where: { $0.isActive && matches($0) }) ?? catalog.first(where: matches) else {
            return team
        }
        return MatchTeam(id: found.id, name: team.name, code: team.code, image: team.image, result: team.result)
    }
}
```

- [ ] **Step 7: Écrire les routes**

Créer `LoLKit/Sources/LoLKit/API/LoLClient+Season.swift` :

```swift
import Foundation

/// Une page de `getSchedule` et ses jetons de pagination (calendrier complet, spec saison §3.2) : `older` / `newer`
/// sont les `pageToken` des pages voisines ; `newer` nil = rien de plus récent.
public struct SchedulePageResult: Sendable, Equatable {
    public let events: [MatchEvent]
    public let older: String?
    public let newer: String?

    public init(events: [MatchEvent], older: String?, newer: String?) {
        self.events = events
        self.older = older
        self.newer = newer
    }
}

extension LoLClient {
    /// Tournois d'une ligue, du plus récent au plus ancien (`getTournamentsForLeague`), `leagueId` rempli.
    public func tournaments(leagueId: String) async throws -> [TournamentRef] {
        let response = try await api("getTournamentsForLeague", query: [URLQueryItem(name: "leagueId", value: leagueId)],
                                     as: TournamentsResponse.self)
        return response.data.leagues.flatMap(\.tournaments.elements).map { tournament in
            var filled = tournament
            filled.leagueId = leagueId
            return filled
        }
    }

    /// Matchs terminés d'un tournoi avec les ids de toutes leurs games (`getCompletedEvents`). Pas d'id d'équipe.
    public func completedEvents(tournamentId: String) async throws -> [CompletedMatch] {
        try await api("getCompletedEvents", query: [URLQueryItem(name: "tournamentId", value: tournamentId)],
                      as: CompletedEventsResponse.self).data.schedule.events.elements.map(\.completed)
    }

    /// Classements et tableaux d'un tournoi (`getStandings`) ; aucune étape si l'API n'en donne pas.
    public func standings(tournamentId: String) async throws -> Standings {
        try await api("getStandings", query: [URLQueryItem(name: "tournamentId", value: tournamentId)],
                      as: StandingsResponse.self).data.standings.elements.first ?? Standings(stages: [])
    }

    /// Une page du calendrier (80 matchs) : sans `pageToken`, la page autour d'aujourd'hui (comme `schedule`).
    public func schedulePage(leagueIds: [String], pageToken: String?) async throws -> SchedulePageResult {
        var query = leagueIds.isEmpty ? [] : [URLQueryItem(name: "leagueId", value: leagueIds.joined(separator: ","))]
        if let pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        let schedule = try await api("getSchedule", query: query, as: SchedulePageResponse.self).data.schedule
        return SchedulePageResult(events: schedule.events.elements, older: schedule.pages?.older,
                                  newer: schedule.pages?.newer)
    }
}

/// `getSchedule` avec `pages {older, newer}`.
struct SchedulePageResponse: Decodable {
    struct Payload: Decodable {
        let schedule: Schedule
    }

    struct Schedule: Decodable {
        let pages: Pages?
        let events: LossyArray<MatchEvent>
    }

    struct Pages: Decodable {
        let older: String?
        let newer: String?
    }

    let data: Payload
}
```

- [ ] **Step 8: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter SeasonAPITests`
Expected : `14 tests` passés, aucun `warning:`.

- [ ] **Step 9: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 334 tests in 38 suites passed`, aucun `warning:` (les appels existants `Team(id:slug:name:code:image:status:homeLeague:)` compilent toujours).

- [ ] **Step 10: Commit**

```bash
git add LoLKit/Sources/LoLKit/Season/TournamentRef.swift LoLKit/Sources/LoLKit/Season/CompletedMatch.swift LoLKit/Sources/LoLKit/Season/Standings.swift LoLKit/Sources/LoLKit/Season/SeasonMatch.swift LoLKit/Sources/LoLKit/API/LoLClient+Season.swift LoLKit/Sources/LoLKit/API/LoLClient.swift LoLKit/Sources/LoLKit/Models/Team.swift LoLKit/Tests/LoLKitTests/SeasonAPITests.swift LoLKit/Tests/LoLKitTests/Fixtures/season/getCompletedEvents_lec3_ids.json
git commit -m "feat(lolkit): API de la saison — tournois, matchs terminés (games jouées = Σ gameWins premières), classements, page de calendrier, effectif du catalogue, jointure SeasonMatch" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 11: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l1-api-saison
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` (Linux) et `test-macos` verts. Échec : `gh run view <id> --log-failed`, corriger, nouveau commit, nouveau push, nouvelle attente sur le nouveau SHA.

---

### Task L2: Game réduite — `GameSummary`, `GameWinners`, `PlayerName`

**Branche :** `nuit2/lolkit-l2-game-summary` — **Vague 1**

**Files:**
- Create: `LoLKit/Sources/LoLKit/Season/GameSummary.swift`, `LoLKit/Sources/LoLKit/Season/GameWinners.swift`, `LoLKit/Sources/LoLKit/Season/PlayerName.swift`
- Modify: `LoLKit/Sources/LoLKit/Models/LiveWindow.swift` (`ParticipantMetadata.esportsPlayerId`)
- Test: `LoLKit/Tests/LoLKitTests/GameSummaryTests.swift`, `LoLKit/Tests/LoLKitTests/GameWinnersTests.swift`, aide `LoLKit/Tests/LoLKitTests/Support/SeasonFixture.swift`
- Fixtures lues (déjà au dépôt) : `window_first_115548681803406304.json`, `window_final_115548681803406304.json`, `window_15min_115548681803406304.json`, `details_final_115548681803406304.json`, `game_summary_115548681803406304.json`, `crawl_kc_lec3_tierA_index.json` ; `window_finished.json` (ancienne capture).

**Interfaces:**
- Consumes (à `HEAD`) : `LiveWindow { esportsGameId: String; gameMetadata: GameMetadata; frames: [WindowFrame] }`, `GameMetadata { patchVersion: String?; blueTeamMetadata, redTeamMetadata: TeamMetadata }`, `TeamMetadata { esportsTeamId: String; participantMetadata: [ParticipantMetadata] }`, `ParticipantMetadata { participantId: Int; summonerName, championId, role: String? }`, `WindowFrame { rfc460Timestamp: Date; gameState: String; blueTeam, redTeam: FrameTeam }`, `FrameTeam { totalGold, inhibitors, towers, barons, totalKills: Int; dragons: [String]; participants: [FrameParticipant] }`, `FrameParticipant { participantId, totalGold, level, kills, deaths, assists, creepScore: Int }`, `GameDetails.latestFrame: DetailsFrame?`, `DetailsFrame.participants: [ParticipantDetails]`, `ParticipantDetails { participantId: Int; championDamageShare: Double?; wardsPlaced, wardsDestroyed: Int? }`, `MatchTeam`, `LossyArray` ; tests : `Fixture.data(_:)`, `Fixture.Missing`, `date(_:)`.
- Produces :
  - `public struct GameResult: Codable, Sendable, Equatable { var winnerTeamId: String?; var basis: Basis (.exact | .inferred | .unknown); static let unknown }`.
  - `public struct GameSummary: Codable, Sendable, Equatable, Identifiable { static let schemaVersion = 1; v: Int; gameId, matchId, tournamentId, leagueSlug: String; number: Int; patch: String?; startedAt, endedAt: Date; var durationSeconds: Int; var result: GameResult; blue, red: TeamGameLine; enriched: Bool; init(v:gameId:matchId:tournamentId:leagueSlug:number:patch:startedAt:endedAt:durationSeconds:result:blue:red:enriched:); func line(teamId:) -> TeamGameLine?; func opponentLine(of:) -> TeamGameLine?; func player(_:) -> (team: TeamGameLine, line: PlayerGameLine)?; static func decodeStored(_ data: Data) -> GameSummary?; static let at15Tolerance: TimeInterval = 15; static func make(first:final:at15:details:matchId:number:tournamentId:leagueSlug:) -> GameSummary? }`.
  - `public struct TeamGameLine: Codable, Sendable, Equatable { teamId: String; kills, gold, towers, inhibitors, barons: Int; dragons: [String]; gold15: Int?; players: [PlayerGameLine] }`.
  - `public struct PlayerGameLine: Codable, Sendable, Equatable { playerId, name, role, champion: String; level, kills, deaths, assists, creepScore, gold: Int; damageShare: Double?; wardsPlaced, wardsDestroyed, gold15, creepScore15: Int? }` (init : les 5 derniers par défaut nil).
  - `public enum GameWinners { static let minimumTowerMargin = 3; static func assign(teams: [MatchTeam], playedGameIds: [String], summaries: [String: GameSummary]) -> [String: GameResult]; static func apply(teams:playedGameIds:to:) -> [String: GameSummary] }`.
  - `public enum PlayerName { static func display(_ summonerName: String, teamCode: String?) -> String }`.
  - `ParticipantMetadata.esportsPlayerId: String?`.
  - Tests (interne) : `enum SeasonFixture { lecSplit3, kc, g2, game304, match303; data(_:), window(_:), details(_:), summary304(enriched:), IndexRow, kcIndex(), kcSummaries(), summary(_:), teams(of:) }`.

- [ ] **Step 1: Écrire l'aide de test et les tests qui échouent**

Créer `LoLKit/Tests/LoLKitTests/Support/SeasonFixture.swift` :

```swift
import Foundation
@testable import LoLKit

/// Fixtures réelles réduites de la saison (`Fixtures/season/`, capturées le 14/10/2026, spec saison §1.1).
enum SeasonFixture {
    static let lecSplit3 = "115548681802226458"
    static let kc = "111692118851466302"
    static let g2 = "98767991926151025"
    /// Game de référence : LEC S3, play-offs, 06/09, KC 1-3 G2, game 1 (KC bleu).
    static let game304 = "115548681803406304"
    static let match303 = "115548681803406303"

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/season") else {
            throw Fixture.Missing(name: "season/\(name)")
        }
        return try Data(contentsOf: url)
    }

    static func window(_ name: String) throws -> LiveWindow {
        try JSONDecoder.lolesports().decode(LiveWindow.self, from: data(name))
    }

    static func details(_ name: String) throws -> GameDetails {
        try JSONDecoder.lolesports().decode(GameDetails.self, from: data(name))
    }

    /// `GameSummary` de la game 304 lu depuis les vraies fenêtres (palier B si `enriched`).
    static func summary304(enriched: Bool = true) throws -> GameSummary {
        let made = GameSummary.make(
            first: try window("window_first_115548681803406304"),
            final: try window("window_final_115548681803406304"),
            at15: enriched ? try window("window_15min_115548681803406304") : nil,
            details: enriched ? try details("details_final_115548681803406304") : nil,
            matchId: match303, number: 1, tournamentId: lecSplit3, leagueSlug: "lec")
        guard let made else { throw Fixture.Missing(name: "GameSummary 304") }
        return made
    }

    /// Une ligne de `crawl_kc_lec3_tierA_index.json` : une game de KC (LEC Split 3, palier A réel), stats d'équipe finales.
    struct IndexRow: Decodable {
        struct SeriesEntry: Decodable {
            let code: String
            let wins: Int

            init(from decoder: any Decoder) throws {
                var container = try decoder.unkeyedContainer()
                code = try container.decode(String.self)
                wins = try container.decode(Int.self)
            }
        }

        struct TeamLine: Decodable {
            let totalGold: Int
            let inhibitors: Int
            let towers: Int
            let barons: Int
            let totalKills: Int
            let dragons: [String]
        }

        let match: String
        let n: Int
        let game: String
        let series: [SeriesEntry]
        let start: Date
        let end: Date
        /// `finished` (29 games) ou `in_game` (2 games dont le flux s'arrête avant la frame `finished`).
        let state: String
        let blueId: String
        let redId: String
        let blueTeam: TeamLine
        let redTeam: TeamLine
    }

    /// Les 31 games de KC, dans l'ordre chronologique.
    static func kcIndex() throws -> [IndexRow] {
        try JSONDecoder.lolesports().decode([IndexRow].self, from: data("crawl_kc_lec3_tierA_index"))
    }

    /// Les 31 games de KC en `GameSummary` (palier A, sans joueurs : l'index ne garde que les stats d'équipe),
    /// résultat inconnu.
    static func kcSummaries() throws -> [GameSummary] {
        try kcIndex().map(summary)
    }

    static func summary(_ row: IndexRow) -> GameSummary {
        func line(_ id: String, _ team: IndexRow.TeamLine) -> TeamGameLine {
            TeamGameLine(teamId: id, kills: team.totalKills, gold: team.totalGold, towers: team.towers,
                         inhibitors: team.inhibitors, barons: team.barons, dragons: team.dragons, gold15: nil, players: [])
        }
        return GameSummary(gameId: row.game, matchId: row.match, tournamentId: lecSplit3, leagueSlug: "lec",
                           number: row.n, patch: nil, startedAt: row.start, endedAt: row.end,
                           durationSeconds: Int(row.end.timeIntervalSince(row.start).rounded()), result: .unknown,
                           blue: line(row.blueId, row.blueTeam), red: line(row.redId, row.redTeam), enriched: false)
    }

    /// Les deux équipes d'un match de l'index (KC et son adversaire, ordre de la série), avec id et victoires.
    static func teams(of rows: [IndexRow]) -> [MatchTeam] {
        let first = rows[0]
        let opponent = first.blueId == kc ? first.redId : first.blueId
        return first.series.map { entry in
            MatchTeam(id: entry.code == "KC" ? kc : opponent, name: entry.code, code: entry.code, image: nil,
                      result: MatchTeam.Result(outcome: nil, gameWins: entry.wins))
        }
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/GameSummaryTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Réduction d'une game jouée (spec saison §1.3, §1.5) sur la game de référence 304 (KC 1-3 G2, game 1).
@Suite struct GameSummaryTests {
    /// Résumé attendu, calculé à part (`game_summary_115548681803406304.json`, palier B) : comparé valeur par valeur.
    private func expected() throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: SeasonFixture.data("game_summary_115548681803406304"))
            as? [String: Any])
    }

    @Test func tierAReadsTheFirstAndTheFinishedFrames() throws {
        let summary = try SeasonFixture.summary304(enriched: false)
        #expect(summary.v == GameSummary.schemaVersion)
        #expect(summary.gameId == SeasonFixture.game304)
        #expect(summary.matchId == SeasonFixture.match303)
        #expect(summary.tournamentId == SeasonFixture.lecSplit3)
        #expect(summary.leagueSlug == "lec")
        #expect(summary.number == 1)
        #expect(summary.patch == "16.17.810.4348")
        #expect(summary.startedAt == date("2026-09-06T15:17:23.939Z"))
        #expect(summary.endedAt == date("2026-09-06T15:51:14.975Z"))
        // 33:51 = dernière frame − première frame (2031,036 s).
        #expect(summary.durationSeconds == 2031)
        #expect(summary.result == .unknown)
        #expect(!summary.enriched)

        #expect(summary.blue.teamId == SeasonFixture.kc)
        #expect([summary.blue.gold, summary.blue.kills, summary.blue.towers, summary.blue.inhibitors,
                 summary.blue.barons] as [Int] == [63_457, 11, 4, 0, 0])
        #expect(summary.blue.dragons.isEmpty)
        #expect(summary.red.teamId == SeasonFixture.g2)
        #expect([summary.red.gold, summary.red.kills, summary.red.towers, summary.red.inhibitors,
                 summary.red.barons] as [Int] == [70_918, 23, 10, 2, 2])
        #expect(summary.red.dragons == ["ocean", "mountain", "cloud", "cloud", "elder"])
        // Somme des gold joueurs = gold d'équipe.
        #expect(summary.blue.players.reduce(0) { $0 + $1.gold } == 63_457)

        let canna = try #require(summary.blue.players.first)
        #expect(canna == PlayerGameLine(playerId: "103495716771322725", name: "KC Canna", role: "top", champion: "Jayce",
                                        level: 18, kills: 1, deaths: 3, assists: 5, creepScore: 304, gold: 12_846))
        #expect(summary.blue.players.map(\.role) == ["top", "jungle", "mid", "bottom", "support"])
        #expect(summary.red.players.map(\.champion) == ["KSante", "XinZhao", "Viktor", "Ezreal", "Karma"])
        #expect(summary.red.players.map { "\($0.kills)/\($0.deaths)/\($0.assists)" }
                == ["3/2/6", "7/2/6", "7/2/5", "5/3/11", "1/2/18"])
        // Palier A : rien du palier B.
        #expect(summary.blue.gold15 == nil && summary.red.gold15 == nil)
        #expect(summary.blue.players.allSatisfy { $0.damageShare == nil && $0.gold15 == nil && $0.wardsPlaced == nil })
        #expect(summary.line(teamId: SeasonFixture.g2) == summary.red)
        #expect(summary.opponentLine(of: SeasonFixture.g2) == summary.blue)
        #expect(summary.line(teamId: "autre") == nil)
        #expect(summary.player("98767975968177297")?.line.champion == "Viktor")
        #expect(summary.player("98767975968177297")?.team.teamId == SeasonFixture.g2)
    }

    /// Palier B : à 15 min, KC +228 (26 851 contre 26 623), Canna 5 197 gold / 148 CS ; part des dégâts et balises.
    @Test func tierBMatchesTheExpectedSummary() throws {
        let summary = try SeasonFixture.summary304()
        let reference = try expected()
        #expect(summary.enriched)
        #expect(summary.blue.gold15 == 26_851)
        #expect(summary.red.gold15 == 26_623)
        #expect((summary.blue.gold15 ?? 0) - (summary.red.gold15 ?? 0) == 228)
        #expect(summary.blue.players[0].gold15 == 5_197)
        #expect(summary.blue.players[0].creepScore15 == 148)
        #expect(summary.blue.players[0].damageShare == 0.2278)
        #expect(summary.blue.players[3].damageShare == 0.3387)

        #expect(summary.durationSeconds == reference["durationSeconds"] as? Int)
        #expect(summary.patch == reference["patch"] as? String)
        for side in ["blue", "red"] {
            let line = side == "blue" ? summary.blue : summary.red
            let team = try #require(reference[side] as? [String: Any])
            #expect(line.teamId == team["teamId"] as? String)
            #expect(line.gold15 == team["gold15"] as? Int)
            #expect(line.dragons == team["dragons"] as? [String])
            let players = try #require(team["players"] as? [[String: Any]])
            #expect(players.count == line.players.count)
            for (player, wanted) in zip(line.players, players) {
                #expect(player.playerId == wanted["playerId"] as? String)
                #expect(player.name == wanted["name"] as? String)
                #expect(player.champion == wanted["champion"] as? String)
                #expect([player.level, player.kills, player.deaths, player.assists, player.creepScore, player.gold]
                        == ["level", "kills", "deaths", "assists", "creepScore", "gold"].map { wanted[$0] as? Int ?? -1 })
                #expect(player.damageShare == wanted["damageShare"] as? Double)
                #expect(player.wardsPlaced == wanted["wardsPlaced"] as? Int)
                #expect(player.wardsDestroyed == wanted["wardsDestroyed"] as? Int)
                #expect(player.gold15 == wanted["gold15"] as? Int)
                #expect(player.creepScore15 == wanted["creepScore15"] as? Int)
            }
        }
    }

    /// « Jamais de chiffre inventé » : pas de frame `finished` → pas de résumé ; deux games différentes → rien.
    @Test func noSummaryWithoutTheFinishedFrame() throws {
        let first = try SeasonFixture.window("window_first_115548681803406304")
        #expect(GameSummary.make(first: first, final: first, at15: nil, details: nil, matchId: "m", number: 1,
                                 tournamentId: "t", leagueSlug: "lec") == nil)
        let other = try SeasonFixture.window("window_15min_115548681803406304")
        #expect(other.frames.allSatisfy { $0.gameState != "finished" })
        #expect(GameSummary.make(first: first, final: other, at15: nil, details: nil, matchId: "m", number: 1,
                                 tournamentId: "t", leagueSlug: "lec") == nil)
        let tlaw = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data("window_finished"))
        #expect(GameSummary.make(first: first, final: tlaw, at15: nil, details: nil, matchId: "m", number: 1,
                                 tournamentId: "t", leagueSlug: "lec") == nil)
    }

    /// Une frame à plus de 15 s de début + 900 s n'est pas « à 15 min ».
    @Test func goldAt15NeedsAFrameWithinFifteenSeconds() throws {
        let final = try SeasonFixture.window("window_final_115548681803406304")
        let summary = try #require(GameSummary.make(
            first: try SeasonFixture.window("window_first_115548681803406304"), final: final, at15: final,
            details: nil, matchId: SeasonFixture.match303, number: 1, tournamentId: SeasonFixture.lecSplit3,
            leagueSlug: "lec"))
        #expect(summary.blue.gold15 == nil)
        #expect(summary.blue.players.allSatisfy { $0.gold15 == nil && $0.creepScore15 == nil })
        #expect(summary.enriched)
    }

    /// Cache disque : `JSONEncoder` par défaut, relu à l'identique, ~3 Ko au palier B (jamais le JSON brut).
    @Test func roundTripsCompactly() throws {
        let summary = try SeasonFixture.summary304()
        let data = try JSONEncoder().encode(summary)
        #expect(data.count < 3_600)
        #expect(GameSummary.decodeStored(data) == summary)
        let tierA = try JSONEncoder().encode(try SeasonFixture.summary304(enriched: false))
        #expect(tierA.count < 2_600)
    }

    /// Schéma plus récent → ignoré ; champs retirés → relus à nil ou à une valeur neutre (jamais d'échec).
    @Test func storedSummariesDecodeTolerantly() throws {
        var object = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(try SeasonFixture.summary304())) as? [String: Any])
        object["v"] = GameSummary.schemaVersion + 1
        #expect(GameSummary.decodeStored(try JSONSerialization.data(withJSONObject: object)) == nil)

        object["v"] = nil
        object["patch"] = nil
        object["result"] = nil
        object["enriched"] = nil
        object["durationSeconds"] = nil
        var blue = try #require(object["blue"] as? [String: Any])
        var players = try #require(blue["players"] as? [[String: Any]])
        players[0]["damageShare"] = nil
        players[0]["gold15"] = nil
        players[1] = ["name": "sans id"]
        blue["players"] = players
        blue["gold15"] = nil
        object["blue"] = blue
        let summary = try #require(GameSummary.decodeStored(try JSONSerialization.data(withJSONObject: object)))
        #expect(summary.v == 1)
        #expect(summary.patch == nil)
        #expect(summary.result == .unknown)
        #expect(!summary.enriched)
        #expect(summary.durationSeconds == 2031)
        #expect(summary.blue.gold15 == nil)
        #expect(summary.blue.players.count == 4)
        #expect(summary.blue.players[0].damageShare == nil)
        #expect(summary.blue.players[0].kills == 1)
        #expect(summary.red.players.count == 5)

        let unknownBasis = #"{"winnerTeamId":"x","basis":"verified"}"#
        #expect(try JSONDecoder().decode(GameResult.self, from: Data(unknownBasis.utf8)).basis == .unknown)
        #expect(GameSummary.decodeStored(Data("{}".utf8)) == nil)
    }

    /// Le flux nomme le joueur avec le préfixe de son équipe ; `esportsPlayerId` est l'id de `getTeams`.
    @Test func participantMetadataCarriesThePlayerId() throws {
        let window = try SeasonFixture.window("window_first_115548681803406304")
        let canna = try #require(window.gameMetadata.blueTeamMetadata.participantMetadata.first)
        #expect(canna.esportsPlayerId == "103495716771322725")
        #expect(canna.summonerName == "KC Canna")
        // Une vieille capture sans `esportsPlayerId` reste lisible.
        let old = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data("window_finished"))
        #expect(old.gameMetadata.blueTeamMetadata.participantMetadata.count == 5)
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/GameWinnersTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Vainqueur par game (spec saison §1.4) et nom affiché d'un joueur (§1.5).
@Suite struct GameWinnersTests {
    private func team(_ id: String, wins: Int) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id.uppercased(), image: nil, result: MatchTeam.Result(outcome: nil, gameWins: wins))
    }

    /// Game de test : `towersA` pour l'équipe « a » (bleue), `towersB` pour « b ».
    private func game(_ id: String, _ towersA: Int, _ towersB: Int) -> GameSummary {
        func line(_ team: String, _ towers: Int) -> TeamGameLine {
            TeamGameLine(teamId: team, kills: 0, gold: 0, towers: towers, inhibitors: 0, barons: 0, dragons: [],
                         gold15: nil, players: [])
        }
        return GameSummary(gameId: id, matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
                           startedAt: date("2026-09-06T15:00:00Z"), endedAt: date("2026-09-06T15:30:00Z"),
                           durationSeconds: 1800, result: .unknown, blue: line("a", towersA), red: line("b", towersB),
                           enriched: false)
    }

    @Test func exactRules() {
        // Bo1.
        #expect(GameWinners.assign(teams: [team("a", wins: 0), team("b", wins: 1)], playedGameIds: ["g1"], summaries: [:])
                == ["g1": GameResult(winnerTeamId: "b", basis: .exact)])
        // 2-0 : tout à « a », sans résumé.
        #expect(GameWinners.assign(teams: [team("a", wins: 2), team("b", wins: 0)], playedGameIds: ["g1", "g2"],
                                   summaries: [:])
                == ["g1": GameResult(winnerTeamId: "a", basis: .exact), "g2": GameResult(winnerTeamId: "a", basis: .exact)])
        // 2-1 : la dernière game au vainqueur de la série, même sans résumé ; les autres inconnues sans résumé.
        let partial = GameWinners.assign(teams: [team("a", wins: 2), team("b", wins: 1)], playedGameIds: ["g1", "g2", "g3"],
                                         summaries: ["g1": game("g1", 9, 2)])
        #expect(partial == ["g1": .unknown, "g2": .unknown, "g3": GameResult(winnerTeamId: "a", basis: .exact)])
    }

    @Test func inferredFromTowerMargins() {
        let teams = [team("a", wins: 2), team("b", wins: 2)]
        // « b » gagne la série (dernière game g5) ; « a » doit gagner 2 games parmi g1-g4.
        let summaries = ["g1": game("g1", 9, 2), "g2": game("g2", 1, 8), "g3": game("g3", 11, 3), "g4": game("g4", 2, 9)]
        #expect(GameWinners.assign(teams: [team("a", wins: 2), team("b", wins: 3)],
                                   playedGameIds: ["g1", "g2", "g3", "g4", "g5"], summaries: summaries)
                == ["g1": GameResult(winnerTeamId: "a", basis: .inferred), "g3": GameResult(winnerTeamId: "a", basis: .inferred),
                    "g2": GameResult(winnerTeamId: "b", basis: .inferred), "g4": GameResult(winnerTeamId: "b", basis: .inferred),
                    "g5": GameResult(winnerTeamId: "b", basis: .exact)])
        // Victoires incohérentes avec les games jouées (2-2 pour 5 games) : rien.
        #expect(GameWinners.assign(teams: teams, playedGameIds: ["g1", "g2", "g3", "g4", "g5"], summaries: summaries).isEmpty)
        // Sans id d'équipe : rien.
        let noId = MatchTeam(id: nil, name: "A", code: "A", image: nil, result: MatchTeam.Result(outcome: nil, gameWins: 1))
        #expect(GameWinners.assign(teams: [noId, team("b", wins: 0)], playedGameIds: ["g1"], summaries: [:]).isEmpty)
    }

    /// Marge trop faible (< 3 tours) ou égalité à la frontière : inconnu, jamais une estimation fragile.
    @Test func closeMarginsStayUnknown() {
        let teams = [team("a", wins: 1), team("b", wins: 2)]
        let close = ["g1": game("g1", 8, 6), "g2": game("g2", 2, 9)]
        #expect(GameWinners.assign(teams: teams, playedGameIds: ["g1", "g2", "g3"], summaries: close)
                == ["g1": .unknown, "g2": .unknown, "g3": GameResult(winnerTeamId: "b", basis: .exact)])
        let tie = ["g1": game("g1", 8, 8), "g2": game("g2", 8, 8)]
        #expect(GameWinners.assign(teams: teams, playedGameIds: ["g1", "g2", "g3"], summaries: tie)["g1"] == .unknown)
    }

    /// KC, LEC Split 3 (31 games réelles) : 21 exactes, 10 déduites, 0 inconnue, toutes cohérentes avec les séries ;
    /// la game 304 (KC 1-3 G2, game 1) est à G2, « déduit ».
    @Test func kcLecSplit3() throws {
        let rows = try SeasonFixture.kcIndex()
        var summaries = Dictionary(uniqueKeysWithValues: try SeasonFixture.kcSummaries().map { ($0.gameId, $0) })
        let byMatch = Dictionary(grouping: rows, by: \.match)
        #expect(byMatch.count == 12)
        for (_, games) in byMatch {
            let ordered = games.sorted { $0.n < $1.n }
            summaries = GameWinners.apply(teams: SeasonFixture.teams(of: ordered), playedGameIds: ordered.map(\.game),
                                          to: summaries)
        }
        let results = summaries.values.map(\.result)
        #expect(results.filter { $0.basis == .exact }.count == 21)
        #expect(results.filter { $0.basis == .inferred }.count == 10)
        #expect(results.filter { $0.basis == .unknown }.isEmpty)
        #expect(summaries[SeasonFixture.game304]?.result == GameResult(winnerTeamId: SeasonFixture.g2, basis: .inferred))
        for (_, games) in byMatch {
            let teams = SeasonFixture.teams(of: games)
            for entry in teams {
                let won = games.filter { summaries[$0.game]?.result.winnerTeamId == entry.id }.count
                #expect(won == entry.gameWins)
            }
        }
    }

    @Test func playerDisplayNameDropsOnlyTheTeamCode() {
        #expect(PlayerName.display("KC Canna", teamCode: "KC") == "Canna")
        #expect(PlayerName.display("G2 Hans Sama", teamCode: "G2") == "Hans Sama")
        #expect(PlayerName.display("Hans Sama", teamCode: "G2") == "Hans Sama")
        #expect(PlayerName.display("KCB Lucky", teamCode: "KC") == "KCB Lucky")
        #expect(PlayerName.display("KC Canna", teamCode: nil) == "KC Canna")
        #expect(PlayerName.display("KC ", teamCode: "KC") == "KC ")
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

Run : `bash scripts/lolkit.sh test --filter "GameSummaryTests|GameWinnersTests"`
Expected : échec de compilation (`cannot find type 'GameSummary' in scope`…).

- [ ] **Step 3: Lire l'id du joueur dans le flux**

Dans `LoLKit/Sources/LoLKit/Models/LiveWindow.swift` :

Remplacement 1/1 — remplacer exactement :

```swift
public struct ParticipantMetadata: Codable, Sendable, Equatable {
    public let participantId: Int
```

par :

```swift
public struct ParticipantMetadata: Codable, Sendable, Equatable {
    public let participantId: Int
    /// Id du joueur, le même que `TeamPlayer.id` de `getTeams` (identité d'un joueur, spec saison §1.5) ; absent des
    /// vieilles captures.
    public let esportsPlayerId: String?
```

- [ ] **Step 4: Écrire `GameSummary`**

Créer `LoLKit/Sources/LoLKit/Season/GameSummary.swift` :

```swift
import Foundation

/// Vainqueur d'une game (spec saison §1.4) : l'API ne le donne nulle part, `GameWinners.assign` le déduit de la série.
public struct GameResult: Codable, Sendable, Equatable {
    public enum Basis: String, Codable, Sendable, Equatable {
        /// Certain : Bo1, série gagnée sans perdre de game, ou dernière game de la série.
        case exact
        /// Déduit des tours détruites : à étiqueter « estimé ».
        case inferred
        /// Inconnu : pas toutes les games en cache, ou marges trop proches.
        case unknown

        /// Valeur inconnue (version plus récente) → `.unknown`.
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Basis(rawValue: raw) ?? .unknown
        }
    }

    public var winnerTeamId: String?
    public var basis: Basis

    public init(winnerTeamId: String?, basis: Basis) {
        self.winnerTeamId = winnerTeamId
        self.basis = basis
    }

    public static let unknown = GameResult(winnerTeamId: nil, basis: .unknown)
}

/// Une game jouée, réduite à ses valeurs utiles (~2,2 Ko palier A, ~3,2 Ko palier B) et gardée pour toujours dans
/// `cache/season/games/<gameId>.json` (spec saison §1.5, §1.7). Jamais le JSON brut du flux.
public struct GameSummary: Codable, Sendable, Equatable, Identifiable {
    /// Version du schéma : un fichier d'une version plus récente est ignoré (`decodeStored`), une plus ancienne relue
    /// telle quelle (champs manquants à nil). Le même JSON servira à la synchronisation avec le serveur (phase 2).
    public static let schemaVersion = 1

    public let v: Int
    public let gameId: String
    public let matchId: String
    public let tournamentId: String
    public let leagueSlug: String
    /// N° de la game dans la série (1 = première).
    public let number: Int
    /// « 16.17.810.4348 »
    public let patch: String?
    /// Première frame du flux (début de la game).
    public let startedAt: Date
    /// Frame `finished`.
    public let endedAt: Date
    /// `endedAt − startedAt`, arrondi à la seconde.
    public var durationSeconds: Int
    /// Recalculé par `GameWinners.assign` quand toutes les games jouées de la série sont en cache.
    public var result: GameResult
    public let blue: TeamGameLine
    public let red: TeamGameLine
    /// Palier B lu (gold et CS à 15 min, part des dégâts, balises).
    public let enriched: Bool

    public init(v: Int = GameSummary.schemaVersion, gameId: String, matchId: String, tournamentId: String,
                leagueSlug: String, number: Int, patch: String?, startedAt: Date, endedAt: Date, durationSeconds: Int,
                result: GameResult, blue: TeamGameLine, red: TeamGameLine, enriched: Bool) {
        self.v = v
        self.gameId = gameId
        self.matchId = matchId
        self.tournamentId = tournamentId
        self.leagueSlug = leagueSlug
        self.number = number
        self.patch = patch
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.result = result
        self.blue = blue
        self.red = red
        self.enriched = enriched
    }

    public var id: String { gameId }

    /// Ligne de l'équipe `teamId` ; nil si elle ne joue pas cette game.
    public func line(teamId: String) -> TeamGameLine? {
        if blue.teamId == teamId { return blue }
        if red.teamId == teamId { return red }
        return nil
    }

    /// Ligne de l'adversaire de `teamId` ; nil si `teamId` ne joue pas cette game.
    public func opponentLine(of teamId: String) -> TeamGameLine? {
        if blue.teamId == teamId { return red }
        if red.teamId == teamId { return blue }
        return nil
    }

    /// Le joueur `playerId` et son équipe ; nil s'il ne joue pas cette game.
    public func player(_ playerId: String) -> (team: TeamGameLine, line: PlayerGameLine)? {
        for team in [blue, red] {
            if let line = team.players.first(where: { $0.playerId == playerId }) { return (team, line) }
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case v, gameId, matchId, tournamentId, leagueSlug, number, patch, startedAt, endedAt, durationSeconds, result
        case blue, red, enriched
    }

    /// Décodage tolérant : `gameId`, `startedAt`, `endedAt`, `blue` et `red` sont indispensables ; le reste prend une
    /// valeur neutre (`v` absent = 1, résultat inconnu, palier A).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? container.decodeIfPresent(Int.self, forKey: .v)) ?? 1
        gameId = try container.decode(String.self, forKey: .gameId)
        matchId = (try? container.decodeIfPresent(String.self, forKey: .matchId)) ?? ""
        tournamentId = (try? container.decodeIfPresent(String.self, forKey: .tournamentId)) ?? ""
        leagueSlug = (try? container.decodeIfPresent(String.self, forKey: .leagueSlug)) ?? ""
        number = (try? container.decodeIfPresent(Int.self, forKey: .number)) ?? 0
        patch = try? container.decodeIfPresent(String.self, forKey: .patch)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        durationSeconds = (try? container.decodeIfPresent(Int.self, forKey: .durationSeconds))
            ?? Int(endedAt.timeIntervalSince(startedAt).rounded())
        result = (try? container.decodeIfPresent(GameResult.self, forKey: .result)) ?? .unknown
        blue = try container.decode(TeamGameLine.self, forKey: .blue)
        red = try container.decode(TeamGameLine.self, forKey: .red)
        enriched = (try? container.decodeIfPresent(Bool.self, forKey: .enriched)) ?? false
    }

    /// Lecture d'un fichier du cache (`JSONDecoder` par défaut) : nil s'il est illisible ou d'un schéma plus récent
    /// que `schemaVersion` (ignoré, pas supprimé : une version plus récente de l'appli le relira).
    public static func decodeStored(_ data: Data) -> GameSummary? {
        guard let summary = try? JSONDecoder().decode(GameSummary.self, from: data),
              summary.v <= schemaVersion else { return nil }
        return summary
    }

    /// Écart toléré entre la frame retenue et début + 900 s pour « à 15 min » (spec §1.3 ; mesuré : 0,04 s).
    public static let at15Tolerance: TimeInterval = 15

    /// Réduit une game jouée (spec §1.3) :
    /// - `first` : `window` sans `startingTime` (sa première frame = début de la game) ;
    /// - `final` : `window` demandée après la fin, qui doit contenir une frame `finished` (sinon nil : « jamais de
    ///   chiffre inventé ») — les stats finales sont celles de la première frame `finished` ;
    /// - `at15` (palier B) : fenêtre autour de début + 900 s ; la frame la plus proche est retenue si l'écart est
    ///   ≤ 15 s, sinon gold et CS à 15 min restent nil ;
    /// - `details` (palier B) : dernière frame de `details` → part des dégâts (arrondie à 4 décimales) et balises.
    /// `enriched` = un des deux du palier B fourni. `result` = inconnu (voir `GameWinners`).
    /// - Returns: nil si `final` n'a pas de frame `finished`, si `first` n'a pas de frame ou si les deux fenêtres ne
    ///   sont pas de la même game.
    public static func make(first: LiveWindow, final: LiveWindow, at15: LiveWindow?, details: GameDetails?,
                            matchId: String, number: Int, tournamentId: String, leagueSlug: String) -> GameSummary? {
        guard first.esportsGameId == final.esportsGameId,
              let start = first.frames.map(\.rfc460Timestamp).min(),
              let end = final.frames.first(where: { $0.gameState == "finished" }) else { return nil }
        var frame15: WindowFrame?
        if let at15 {
            let target = start.addingTimeInterval(900)
            frame15 = at15.frames
                .min { abs($0.rfc460Timestamp.timeIntervalSince(target)) < abs($1.rfc460Timestamp.timeIntervalSince(target)) }
                .flatMap { abs($0.rfc460Timestamp.timeIntervalSince(target)) <= at15Tolerance ? $0 : nil }
        }
        let detailsFrame = details?.latestFrame
        func line(_ metadata: TeamMetadata, _ team: FrameTeam, _ team15: FrameTeam?) -> TeamGameLine {
            let players = metadata.participantMetadata.compactMap { meta -> PlayerGameLine? in
                guard let stats = team.participants.first(where: { $0.participantId == meta.participantId }) else {
                    return nil
                }
                let at15 = team15?.participants.first { $0.participantId == meta.participantId }
                let more = detailsFrame?.participants.first { $0.participantId == meta.participantId }
                return PlayerGameLine(
                    playerId: meta.esportsPlayerId ?? "", name: meta.summonerName ?? "", role: meta.role ?? "",
                    champion: meta.championId ?? "", level: stats.level, kills: stats.kills, deaths: stats.deaths,
                    assists: stats.assists, creepScore: stats.creepScore, gold: stats.totalGold,
                    damageShare: more?.championDamageShare.map { ($0 * 10_000).rounded() / 10_000 },
                    wardsPlaced: more?.wardsPlaced, wardsDestroyed: more?.wardsDestroyed,
                    gold15: at15?.totalGold, creepScore15: at15?.creepScore)
            }
            return TeamGameLine(teamId: metadata.esportsTeamId, kills: team.totalKills, gold: team.totalGold,
                                towers: team.towers, inhibitors: team.inhibitors, barons: team.barons,
                                dragons: team.dragons, gold15: team15?.totalGold, players: players)
        }
        let metadata = final.gameMetadata
        return GameSummary(
            gameId: final.esportsGameId, matchId: matchId, tournamentId: tournamentId, leagueSlug: leagueSlug,
            number: number, patch: metadata.patchVersion ?? first.gameMetadata.patchVersion,
            startedAt: start, endedAt: end.rfc460Timestamp,
            durationSeconds: Int(end.rfc460Timestamp.timeIntervalSince(start).rounded()),
            result: .unknown,
            blue: line(metadata.blueTeamMetadata, end.blueTeam, frame15?.blueTeam),
            red: line(metadata.redTeamMetadata, end.redTeam, frame15?.redTeam),
            enriched: at15 != nil || details != nil)
    }
}

/// Une équipe dans une game : stats finales, gold à 15 min (palier B) et ses 5 joueurs dans l'ordre du flux.
public struct TeamGameLine: Codable, Sendable, Equatable {
    public let teamId: String
    public let kills: Int
    public let gold: Int
    public let towers: Int
    public let inhibitors: Int
    public let barons: Int
    /// Types dans l'ordre (« ocean », « mountain », « cloud », « infernal », « hextech », « chemtech », « elder »).
    public let dragons: [String]
    public let gold15: Int?
    /// Ordre du flux : top, jungle, mid, bottom, support.
    public let players: [PlayerGameLine]

    public init(teamId: String, kills: Int, gold: Int, towers: Int, inhibitors: Int, barons: Int, dragons: [String],
                gold15: Int?, players: [PlayerGameLine]) {
        self.teamId = teamId
        self.kills = kills
        self.gold = gold
        self.towers = towers
        self.inhibitors = inhibitors
        self.barons = barons
        self.dragons = dragons
        self.gold15 = gold15
        self.players = players
    }

    private enum CodingKeys: String, CodingKey {
        case teamId, kills, gold, towers, inhibitors, barons, dragons, gold15, players
    }

    /// `teamId` indispensable ; compteurs absents → 0, listes absentes → vides.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamId = try container.decode(String.self, forKey: .teamId)
        kills = (try? container.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
        gold = (try? container.decodeIfPresent(Int.self, forKey: .gold)) ?? 0
        towers = (try? container.decodeIfPresent(Int.self, forKey: .towers)) ?? 0
        inhibitors = (try? container.decodeIfPresent(Int.self, forKey: .inhibitors)) ?? 0
        barons = (try? container.decodeIfPresent(Int.self, forKey: .barons)) ?? 0
        dragons = (try? container.decodeIfPresent([String].self, forKey: .dragons)) ?? []
        gold15 = try? container.decodeIfPresent(Int.self, forKey: .gold15)
        players = (try? container.decodeIfPresent(LossyArray<PlayerGameLine>.self, forKey: .players))?.elements ?? []
    }
}

/// Un joueur dans une game.
public struct PlayerGameLine: Codable, Sendable, Equatable {
    /// `esportsPlayerId` du flux = `TeamPlayer.id`.
    public let playerId: String
    /// `summonerName` brut du flux (« KC Canna ») ; affichage : `PlayerName.display` ou le catalogue.
    public let name: String
    /// « top », « jungle », « mid », « bottom », « support ».
    public let role: String
    /// Id Data Dragon (« KSante »).
    public let champion: String
    public let level: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let gold: Int
    /// Palier B : part des dégâts aux champions de l'équipe (0-1), balises posées / détruites.
    public let damageShare: Double?
    public let wardsPlaced: Int?
    public let wardsDestroyed: Int?
    /// Palier B : gold et CS à 15 min.
    public let gold15: Int?
    public let creepScore15: Int?

    public init(playerId: String, name: String, role: String, champion: String, level: Int, kills: Int, deaths: Int,
                assists: Int, creepScore: Int, gold: Int, damageShare: Double? = nil, wardsPlaced: Int? = nil,
                wardsDestroyed: Int? = nil, gold15: Int? = nil, creepScore15: Int? = nil) {
        self.playerId = playerId
        self.name = name
        self.role = role
        self.champion = champion
        self.level = level
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.gold = gold
        self.damageShare = damageShare
        self.wardsPlaced = wardsPlaced
        self.wardsDestroyed = wardsDestroyed
        self.gold15 = gold15
        self.creepScore15 = creepScore15
    }

    private enum CodingKeys: String, CodingKey {
        case playerId, name, role, champion, level, kills, deaths, assists, creepScore, gold, damageShare, wardsPlaced
        case wardsDestroyed, gold15, creepScore15
    }

    /// `playerId` indispensable ; texte absent → chaîne vide, compteur absent → 0, valeur du palier B absente → nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(String.self, forKey: .playerId)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? ""
        champion = (try? container.decodeIfPresent(String.self, forKey: .champion)) ?? ""
        level = (try? container.decodeIfPresent(Int.self, forKey: .level)) ?? 0
        kills = (try? container.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
        deaths = (try? container.decodeIfPresent(Int.self, forKey: .deaths)) ?? 0
        assists = (try? container.decodeIfPresent(Int.self, forKey: .assists)) ?? 0
        creepScore = (try? container.decodeIfPresent(Int.self, forKey: .creepScore)) ?? 0
        gold = (try? container.decodeIfPresent(Int.self, forKey: .gold)) ?? 0
        damageShare = try? container.decodeIfPresent(Double.self, forKey: .damageShare)
        wardsPlaced = try? container.decodeIfPresent(Int.self, forKey: .wardsPlaced)
        wardsDestroyed = try? container.decodeIfPresent(Int.self, forKey: .wardsDestroyed)
        gold15 = try? container.decodeIfPresent(Int.self, forKey: .gold15)
        creepScore15 = try? container.decodeIfPresent(Int.self, forKey: .creepScore15)
    }
}
```

- [ ] **Step 5: Écrire `GameWinners` et `PlayerName`**

Créer `LoLKit/Sources/LoLKit/Season/GameWinners.swift` :

```swift
import Foundation

/// Vainqueur de chaque game jouée d'une série (spec saison §1.4). L'API ne le donne nulle part : on part des victoires
/// de la série (`gameWins`, exactes) et, pour les games qu'elles ne tranchent pas, des tours détruites à la frame finale
/// (cohérent avec les scores de série sur 30 games sur 31, mesuré sur KC, LEC Split 3).
public enum GameWinners {
    /// Écart de tours minimal pour déduire un vainqueur.
    public static let minimumTowerMargin = 3

    /// Résultat de chaque game de `playedGameIds` (clé : id de game), dans cet ordre de règles :
    /// 1. Bo1 → le vainqueur du match (exact) ;
    /// 2. une équipe a gagné toutes les games → toutes à elle (exact) ;
    /// 3. la dernière game → le vainqueur de la série (exact) ;
    /// 4. les autres : l'équipe A doit en gagner `w` ; marge = tours(A) − tours(B) ; A reçoit les `w` games de plus
    ///    grande marge. **Déduit** si chaque game attribuée à A a une marge ≥ 3 et chaque game attribuée à B une
    ///    marge ≤ −3 (l'attribution est alors unique) ; sinon, ou s'il manque un résumé, **inconnu** pour ces games.
    /// Rien n'est rendu si les deux équipes n'ont pas d'id ou si les victoires ne correspondent pas aux games jouées.
    /// - Parameters:
    ///   - teams: les deux équipes du match, avec id et `result.gameWins`.
    ///   - playedGameIds: games jouées dans l'ordre (`CompletedMatch.playedGameIds`).
    ///   - summaries: résumés en cache, par id de game.
    public static func assign(teams: [MatchTeam], playedGameIds: [String],
                              summaries: [String: GameSummary]) -> [String: GameResult] {
        guard teams.count == 2, let a = teams[0].id, let b = teams[1].id, !playedGameIds.isEmpty else { return [:] }
        let winsA = teams[0].gameWins
        let winsB = teams[1].gameWins
        guard winsA + winsB == playedGameIds.count, winsA != winsB else { return [:] }
        let seriesWinner = winsA > winsB ? a : b
        var results: [String: GameResult] = [:]
        // Règles 1 et 2 (un Bo1 est une série gagnée sans perdre de game).
        if winsA == 0 || winsB == 0 {
            for game in playedGameIds { results[game] = GameResult(winnerTeamId: seriesWinner, basis: .exact) }
            return results
        }
        // Règle 3.
        let last = playedGameIds[playedGameIds.count - 1]
        results[last] = GameResult(winnerTeamId: seriesWinner, basis: .exact)
        // Règle 4.
        let rest = Array(playedGameIds.dropLast())
        let needA = winsA - (seriesWinner == a ? 1 : 0)
        let margins = rest.compactMap { game -> (game: String, margin: Int)? in
            guard let summary = summaries[game], let lineA = summary.line(teamId: a),
                  let lineB = summary.line(teamId: b) else { return nil }
            return (game, lineA.towers - lineB.towers)
        }
        guard margins.count == rest.count else {
            for game in rest { results[game] = .unknown }
            return results
        }
        let ranked = margins.enumerated().sorted { ($0.element.margin, -$0.offset) > ($1.element.margin, -$1.offset) }
            .map(\.element)
        let toA = ranked.prefix(needA)
        let toB = ranked.dropFirst(needA)
        let sure = toA.allSatisfy { $0.margin >= minimumTowerMargin } && toB.allSatisfy { $0.margin <= -minimumTowerMargin }
        for entry in toA {
            results[entry.game] = sure ? GameResult(winnerTeamId: a, basis: .inferred) : .unknown
        }
        for entry in toB {
            results[entry.game] = sure ? GameResult(winnerTeamId: b, basis: .inferred) : .unknown
        }
        return results
    }

    /// `summaries` avec le résultat de `assign` reporté dans les games de ce match (les autres inchangées).
    public static func apply(teams: [MatchTeam], playedGameIds: [String],
                             to summaries: [String: GameSummary]) -> [String: GameSummary] {
        var updated = summaries
        for (game, result) in assign(teams: teams, playedGameIds: playedGameIds, summaries: summaries) {
            updated[game]?.result = result
        }
        return updated
    }
}
```

Créer `LoLKit/Sources/LoLKit/Season/PlayerName.swift` :

```swift
/// Nom d'un joueur tel que le flux l'écrit (« KC Canna ») → nom affiché (« Canna »), spec saison §1.5.
public enum PlayerName {
    /// Retire le préfixe « CODE » s'il est exactement le code d'équipe suivi d'une espace ; sinon le nom tel quel
    /// (un pseudo à espace comme « Hans Sama » n'est jamais coupé ailleurs). Préférer `TeamPlayer.summonerName` du
    /// catalogue quand il est connu.
    public static func display(_ summonerName: String, teamCode: String?) -> String {
        guard let teamCode, !teamCode.isEmpty, summonerName.hasPrefix(teamCode + " ") else { return summonerName }
        let rest = summonerName.dropFirst(teamCode.count + 1)
        return rest.isEmpty ? summonerName : String(rest)
    }
}
```

- [ ] **Step 6: Lancer les tests pour les voir passer**

Run : `bash scripts/lolkit.sh test --filter "GameSummaryTests|GameWinnersTests"`
Expected : `12 tests` passés (7 + 5).

- [ ] **Step 7: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 332 tests in 39 suites passed`, aucun `warning:`.

- [ ] **Step 8: Commit**

```bash
git add LoLKit/Sources/LoLKit/Models/LiveWindow.swift LoLKit/Sources/LoLKit/Season/GameSummary.swift LoLKit/Sources/LoLKit/Season/GameWinners.swift LoLKit/Sources/LoLKit/Season/PlayerName.swift LoLKit/Tests/LoLKitTests/Support/SeasonFixture.swift LoLKit/Tests/LoLKitTests/GameSummaryTests.swift LoLKit/Tests/LoLKitTests/GameWinnersTests.swift
git commit -m "feat(lolkit): GameSummary versionné (paliers A et B, frame finished exigée, gold à 15 min ± 15 s), vainqueur par game (exact / déduit des tours / inconnu), nom affiché d'un joueur" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l2-game-summary
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task L3: Agrégats de saison — équipe, joueur, face-à-face, masquage, duels

**Branche :** `nuit2/lolkit-l3-agregats` — **Vague 2** (worktree depuis `main` après la fusion de la vague 1 : 359 tests)

**Files:**
- Create: `LoLKit/Sources/LoLKit/Season/SeasonScope.swift`, `LoLKit/Sources/LoLKit/Season/TeamSeason.swift`, `LoLKit/Sources/LoLKit/Season/PlayerSeason.swift`, `LoLKit/Sources/LoLKit/Season/SeasonStats.swift`, `LoLKit/Sources/LoLKit/Season/SeasonMasking.swift`, `LoLKit/Sources/LoLKit/Season/Duel.swift`
- Test: `LoLKit/Tests/LoLKitTests/SeasonStatsTests.swift`, `LoLKit/Tests/LoLKitTests/DuelTests.swift`, aide `LoLKit/Tests/LoLKitTests/Support/SeasonMatches.swift`

**Interfaces:**
- Consumes : (L1) `SeasonMatch(id:tournamentId:leagueSlug:stageSlug:startTime:blockName:bestOf:teams:playedGameIds:)`, `SeasonMatch.involves(_:)`, `TournamentRef.year: Int?`, `TournamentRef.slug`, `Team.players: [TeamPlayer]?`, `TeamPlayer { id, summonerName, image, role }`, `TeamsResponse` (tests) ; (L2) `GameSummary` (`line(teamId:)`, `opponentLine(of:)`, `player(_:)`, `result`, `durationSeconds`, `startedAt`, `matchId`, `gameId`, `blue`, `red`), `GameResult`, `TeamGameLine`, `PlayerGameLine`, `GameWinners.apply(teams:playedGameIds:to:)`, `SeasonFixture` (tests) ; (`HEAD`) `SpoilerPolicy.isMasked(_:matchId:follows:revealed:)`, `FollowList`, `FollowedTeam`.
- Produces :
  - `public struct SeasonScope: Sendable, Hashable { tournamentIds: Set<String>; label: String; static func season(_ year: Int, tournaments: [TournamentRef]) -> SeasonScope; static func tournament(_:) -> SeasonScope; func contains(_ match: SeasonMatch) -> Bool }`.
  - `Streak { kind: .wins | .losses; count }`, `FormPip { matchId; outcome: .win | .loss | .masked }`, `ChampionUse { champion; games; wins; winsEstimated }`, `TeamAverages { kills, deaths, gold, towers, dragons, barons, inhibitors, durationSeconds: Double; gold15Diff: Double?; gold15Games: Int }`, `TeamSeason` (champs de la spec §1.5), `HeadToHead { teamA, teamB; winsA, winsB; matchIds; maskedMatches }`.
  - `GameRefLine { gameId, matchId, teamId; startedAt; champion; kills, deaths, assists, creepScore, gold; won: Bool?; winEstimated: Bool; var kda }`, `PlayerSeason` (champs de la spec §1.5, `var kda`), `PlayerMetric { .kda, .kills, .csPerMin; func value(of:) -> Double }`.
  - `public enum SeasonStats { static func team(_ teamId: String, matches: [SeasonMatch], games: [String: GameSummary], scope: SeasonScope, masked: Set<String>, now: Date, withoutStats: Set<String> = []) -> TeamSeason; static func streak(_ teamId: String, matches: [SeasonMatch], masked: Set<String>) -> Streak?; static func player(_ playerId: String, games: [GameSummary], masked: Set<String>, since: Date?) -> PlayerSeason?; static func topPlayers(games: [GameSummary], masked: Set<String>, metric: PlayerMetric, since: Date?, minGames: Int, limit: Int) -> [PlayerSeason]; static func headToHead(_ a: String, _ b: String, matches: [SeasonMatch], masked: Set<String>) -> HeadToHead }`.
  - `public enum SeasonMasking { static func maskedMatchIds(_ matches: [SeasonMatch], follows: FollowList, revealed: Set<String>) -> Set<String> }`.
  - `DuelSlot { role; playerId, name, image: String? }`, `DuelMetric { .kda, .csPerMin, .goldPerMin, .damageShare, .killParticipation }`, `DuelBar { metric; left, right: Double?; leftRatio, rightRatio: Double }`, `PlayerDuel { left, right: PlayerSeason?; bars }`, `public enum Duel { static let roles; static func lineup(teamId: String, catalog: [Team], games: [GameSummary]) -> [DuelSlot]; static func players(left: String, right: String, games: [GameSummary], masked: Set<String>) -> PlayerDuel }`.
  - Tests (interne) : `SeasonFixture.kcMatches() throws -> [SeasonMatch]`, `SeasonFixture.kcGames() throws -> [String: GameSummary]`.

- [ ] **Step 1: Écrire l'aide de test et les tests qui échouent**

Créer `LoLKit/Tests/LoLKitTests/Support/SeasonMatches.swift` :

```swift
import Foundation
@testable import LoLKit

extension SeasonFixture {
    /// Les 12 matchs de KC (LEC Split 3) tirés de l'index réel, avec les ids d'équipe ; début du match = début de sa
    /// première game ; Bo3 ou Bo5 d'après le score (Bo5 = play-offs).
    static func kcMatches() throws -> [SeasonMatch] {
        let byMatch = Dictionary(grouping: try kcIndex(), by: \.match)
        return byMatch.values.map { rows in
            let ordered = rows.sorted { $0.n < $1.n }
            let sides = teams(of: ordered)
            let bestOf = 2 * (sides.map(\.gameWins).max() ?? 1) - 1
            return SeasonMatch(id: ordered[0].match, tournamentId: lecSplit3, leagueSlug: "lec",
                               stageSlug: bestOf == 5 ? "playoffs" : "regular_season", startTime: ordered[0].start,
                               blockName: nil, bestOf: bestOf, teams: sides, playedGameIds: ordered.map(\.game))
        }.sorted { $0.startTime < $1.startTime }
    }

    /// Les 31 games de KC par id, vainqueur rejoué par `GameWinners` (21 exactes, 10 déduites).
    static func kcGames() throws -> [String: GameSummary] {
        var games = Dictionary(uniqueKeysWithValues: try kcSummaries().map { ($0.gameId, $0) })
        for match in try kcMatches() {
            games = GameWinners.apply(teams: match.teams, playedGameIds: match.playedGameIds, to: games)
        }
        return games
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/SeasonStatsTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Égalité de deux réels à 1e-6 près.
private func close(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tolerance
}

/// Agrégats de saison (spec saison §1.5) sur la vraie collecte « KC, LEC Split 3 » (31 games, palier A) et la game de
/// référence 304 (palier B), anti-spoiler à la lecture (§1.8).
@Suite struct SeasonStatsTests {
    private let now = date("2026-10-14T20:00:00Z")
    private let split3 = SeasonScope(tournamentIds: [SeasonFixture.lecSplit3], label: "lec_split_3_2026")

    /// Valeurs attendues de la spec (§1.1) : séries 10-2, games 22-9, kills 509, morts 388, tours 228, barons 25,
    /// drakes 85 dont 3 elder, gold moyen 68 570, durée moyenne 35,16 min.
    @Test func kcLecSplit3MatchesTheMeasuredAggregates() throws {
        let season = SeasonStats.team(SeasonFixture.kc, matches: try SeasonFixture.kcMatches(),
                                      games: try SeasonFixture.kcGames(), scope: split3, masked: [], now: now)
        #expect(season.teamId == SeasonFixture.kc)
        #expect([season.seriesWins, season.seriesLosses, season.gameWins, season.gameLosses] as [Int] == [10, 2, 22, 9])
        #expect([season.gamesCounted, season.gamesPending, season.gamesWithoutStats, season.maskedMatches] as [Int]
                == [31, 0, 0, 0])
        let averages = try #require(season.averages)
        #expect(close(averages.kills * 31, 509))
        #expect(close(averages.deaths * 31, 388))
        #expect(close(averages.towers * 31, 228))
        #expect(close(averages.barons * 31, 25))
        #expect(close(averages.dragons * 31, 85))
        #expect(close(averages.inhibitors * 31, 34))
        #expect(close(averages.kills, 16.42, 0.005))
        #expect(close(averages.deaths, 12.52, 0.005))
        #expect(close(averages.towers, 7.35, 0.005))
        #expect(close(averages.gold, 68_570.13, 0.01))
        #expect(close(averages.durationSeconds / 60, 35.16, 0.005))
        // Palier A seulement : pas d'écart à 15 min.
        #expect(averages.gold15Diff == nil)
        #expect(averages.gold15Games == 0)
        #expect(season.dragonTypes == ["ocean": 17, "infernal": 13, "cloud": 12, "hextech": 13, "mountain": 13,
                                       "elder": 3, "chemtech": 14])
        // Deux défaites pour finir (G2 1-3, MKOI 0-3) ; forme : SHFT V, SK V, GX V, G2 D, MKOI D.
        #expect(season.streak == Streak(kind: .losses, count: 2))
        #expect(season.form.map(\.outcome) == [.win, .win, .win, .loss, .loss])
        #expect(season.form.last?.matchId == "115548681803406327")
        // L'index ne garde pas les joueurs : aucun champion.
        #expect(season.champions.isEmpty)
    }

    /// Match masqué (KC 1-3 G2) : exclu des bilans, des moyennes et de la série ; pastille neutre ; compté en matchs,
    /// jamais en games.
    @Test func maskedMatchesCountNowhere() throws {
        let matches = try SeasonFixture.kcMatches()
        let games = try SeasonFixture.kcGames()
        let season = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3,
                                      masked: [SeasonFixture.match303], now: now)
        #expect([season.seriesWins, season.seriesLosses, season.gameWins, season.gameLosses] as [Int] == [10, 1, 21, 6])
        #expect(season.gamesCounted == 27)
        #expect(season.gamesPending == 0)
        #expect(season.maskedMatches == 1)
        #expect(season.form.map(\.outcome) == [.win, .win, .win, .masked, .loss])
        // La série s'arrête au match masqué : une seule défaite connue → rien à afficher.
        #expect(season.streak == nil)
        // Le plus récent masqué : série inconnue.
        let latestMasked = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3,
                                            masked: ["115548681803406327"], now: now)
        #expect(latestMasked.streak == nil)
        #expect(SeasonStats.streak(SeasonFixture.kc, matches: matches, masked: ["115548681803406327"]) == nil)
        // Tout masqué : aucune stat, 12 matchs masqués.
        let all = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3,
                                   masked: Set(matches.map(\.id)), now: now)
        #expect(all.maskedMatches == 12)
        #expect(all.averages == nil)
        #expect(all.gamesCounted == 0 && all.gamesPending == 0)
        #expect(all.form.allSatisfy { $0.outcome == .masked })
    }

    /// Games pas encore lues → « à lire » ; échec définitif → « sans stats » ; hors périmètre ou à venir → rien.
    @Test func pendingAndWithoutStatsGames() throws {
        let matches = try SeasonFixture.kcMatches()
        var games = try SeasonFixture.kcGames()
        let removed = ["115548681803406172", "115548681803406280", "115548681803406304"]
        for id in removed { games[id] = nil }
        let season = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3, masked: [],
                                      now: now, withoutStats: ["115548681803406172", "115548681803406280"])
        #expect([season.gamesCounted, season.gamesPending, season.gamesWithoutStats] as [Int] == [28, 1, 2])
        // Bilans exacts quand même (victoires de série).
        #expect([season.gameWins, season.gameLosses] as [Int] == [22, 9])
        let other = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games,
                                     scope: SeasonScope(tournamentIds: ["autre"], label: "x"), masked: [], now: now)
        #expect(other.seriesWins == 0 && other.averages == nil && other.form.isEmpty)
        let before = SeasonStats.team(SeasonFixture.kc, matches: matches, games: games, scope: split3, masked: [],
                                      now: date("2026-07-25T00:00:00Z"))
        #expect(before.seriesWins == 1 && before.form.count == 1)
    }

    /// Écart de gold à 15 min sur les games enrichies (game 304 : KC +228) ; champions de l'équipe avec « estimé ».
    @Test func tierBGoldAt15AndChampions() throws {
        var games = try SeasonFixture.kcGames()
        var enriched = try SeasonFixture.summary304()
        enriched.result = try #require(games[SeasonFixture.game304]?.result)
        games[SeasonFixture.game304] = enriched
        let season = SeasonStats.team(SeasonFixture.kc, matches: try SeasonFixture.kcMatches(), games: games,
                                      scope: split3, masked: [], now: now)
        #expect(season.averages?.gold15Diff == 228)
        #expect(season.averages?.gold15Games == 1)
        #expect(season.champions.map(\.champion) == ["Ahri", "Bard", "Caitlyn", "Jayce", "Vi"])
        #expect(season.champions[0] == ChampionUse(champion: "Ahri", games: 1, wins: 0, winsEstimated: false))
        let g2 = SeasonStats.team(SeasonFixture.g2, matches: try SeasonFixture.kcMatches(), games: games, scope: split3,
                                  masked: [], now: now)
        #expect(g2.averages?.gold15Diff == -228)
        #expect(g2.champions.first { $0.champion == "Viktor" } == ChampionUse(champion: "Viktor", games: 1, wins: 1,
                                                                               winsEstimated: true))
    }

    /// Game 304 : Canna CS/min 8,98, participation aux kills 0,545 ; Caliste gold/min 531,2 (§1.1).
    @Test func playerSeasonOnTheReferenceGame() throws {
        var summary = try SeasonFixture.summary304()
        summary.result = GameResult(winnerTeamId: SeasonFixture.g2, basis: .inferred)
        let canna = try #require(SeasonStats.player("103495716771322725", games: [summary], masked: [], since: nil))
        #expect(canna.name == "KC Canna")
        #expect(canna.role == "top")
        #expect(canna.teamId == SeasonFixture.kc)
        #expect(canna.games == 1)
        #expect([canna.kills, canna.deaths, canna.assists] as [Int] == [1, 3, 5])
        #expect(close(canna.kda, 2))
        #expect(close(canna.csPerMin, 8.98, 0.005))
        #expect(close(canna.killParticipation, 6.0 / 11.0))
        #expect(canna.damageShare == 0.2278)
        #expect(canna.damageShareGames == 1)
        #expect(canna.champions == [ChampionUse(champion: "Jayce", games: 1, wins: 0, winsEstimated: false)])
        #expect(canna.recent.count == 1)
        #expect(canna.recent.first?.won == false)
        #expect(canna.recent.first?.winEstimated == true)
        #expect(canna.bestGame?.gameId == SeasonFixture.game304)
        let caliste = try #require(SeasonStats.player("109461265532592848", games: [summary], masked: [], since: nil))
        #expect(close(caliste.goldPerMin, 531.2, 0.05))
        // Palier A : pas de part des dégâts (« — »).
        let tierA = try SeasonFixture.summary304(enriched: false)
        #expect(SeasonStats.player("103495716771322725", games: [tierA], masked: [], since: nil)?.damageShare == nil)
        // Masqué, ou avant `since` : rien.
        #expect(SeasonStats.player("103495716771322725", games: [summary], masked: [SeasonFixture.match303],
                                   since: nil) == nil)
        #expect(SeasonStats.player("103495716771322725", games: [summary], masked: [],
                                   since: date("2026-09-07T00:00:00Z")) == nil)
        #expect(SeasonStats.player("inconnu", games: [summary], masked: [], since: nil) == nil)
    }

    /// Sommes sur plusieurs games (pas la moyenne des ratios) ; meilleure game = KDA puis kills puis la plus récente.
    @Test func playerSeasonSumsGames() throws {
        let first = try SeasonFixture.summary304()
        let canna = first.blue.players[0]
        let better = PlayerGameLine(playerId: canna.playerId, name: canna.name, role: "top", champion: "KSante", level: 18,
                                    kills: 5, deaths: 1, assists: 7, creepScore: 280, gold: 14_000, damageShare: nil)
        let second = GameSummary(
            gameId: "g2", matchId: "m2", tournamentId: SeasonFixture.lecSplit3, leagueSlug: "lec", number: 1, patch: nil,
            startedAt: date("2026-09-10T15:00:00Z"), endedAt: date("2026-09-10T15:30:00Z"), durationSeconds: 1800,
            result: GameResult(winnerTeamId: SeasonFixture.kc, basis: .exact),
            blue: TeamGameLine(teamId: SeasonFixture.kc, kills: 20, gold: 60_000, towers: 9, inhibitors: 1, barons: 1,
                               dragons: [], gold15: nil, players: [better]),
            red: TeamGameLine(teamId: "autre", kills: 4, gold: 40_000, towers: 1, inhibitors: 0, barons: 0, dragons: [],
                              gold15: nil, players: []),
            enriched: false)
        let season = try #require(SeasonStats.player(canna.playerId, games: [first, second], masked: [], since: nil))
        #expect(season.games == 2)
        #expect(close(season.kda, Double(1 + 5 + 5 + 7) / Double(3 + 1)))
        #expect(close(season.csPerMin, Double(304 + 280) / ((2031 + 1800) / 60.0)))
        #expect(close(season.killParticipation, Double(1 + 5 + 5 + 7) / Double(11 + 20)))
        #expect(season.damageShare == 0.2278 && season.damageShareGames == 1)
        #expect(season.recent.map(\.gameId) == ["g2", SeasonFixture.game304])
        #expect(season.bestGame?.gameId == "g2")
        #expect(season.bestGame?.won == true)
        #expect(season.champions.map(\.champion) == ["Jayce", "KSante"])
        // « Semaine » : depuis le 08/09, seulement la seconde game.
        #expect(SeasonStats.player(canna.playerId, games: [first, second], masked: [],
                                   since: date("2026-09-08T00:00:00Z"))?.games == 1)
    }

    @Test func topPlayersByMetric() throws {
        let game = try SeasonFixture.summary304()
        let byKda = SeasonStats.topPlayers(games: [game], masked: [], metric: .kda, since: nil, minGames: 1, limit: 3)
        #expect(byKda.map(\.name) == ["G2 Labrov", "G2 SkewMond", "G2 Caps"])
        let byKills = SeasonStats.topPlayers(games: [game], masked: [], metric: .kills, since: nil, minGames: 1, limit: 3)
        #expect(byKills.map(\.name) == ["G2 Caps", "G2 SkewMond", "G2 Hans Sama"])
        let byCs = SeasonStats.topPlayers(games: [game], masked: [], metric: .csPerMin, since: nil, minGames: 1, limit: 3)
        #expect(byCs.map(\.name) == ["KC Caliste", "G2 Hans Sama", "KC Canna"])
        #expect(SeasonStats.topPlayers(games: [game], masked: [], metric: .kda, since: nil, minGames: 2, limit: 5).isEmpty)
        #expect(SeasonStats.topPlayers(games: [game], masked: [SeasonFixture.match303], metric: .kda, since: nil,
                                       minGames: 1, limit: 5).isEmpty)
        #expect(PlayerMetric.kills.value(of: byKills[0]) == 7)
    }

    /// KC – G2 cette saison : 1-1 (G2 1-2 KC le 26/07, KC 1-3 G2 le 06/09) ; masqué → exclu et compté.
    @Test func headToHead() throws {
        let matches = try SeasonFixture.kcMatches()
        let all = SeasonStats.headToHead(SeasonFixture.kc, SeasonFixture.g2, matches: matches, masked: [])
        #expect(all == HeadToHead(teamA: SeasonFixture.kc, teamB: SeasonFixture.g2, winsA: 1, winsB: 1,
                                  matchIds: [SeasonFixture.match303, "115548681803406287"], maskedMatches: 0))
        let masked = SeasonStats.headToHead(SeasonFixture.kc, SeasonFixture.g2, matches: matches,
                                            masked: [SeasonFixture.match303])
        #expect(masked.winsA == 1 && masked.winsB == 0 && masked.maskedMatches == 1)
        #expect(masked.matchIds == ["115548681803406287"])
    }

    /// Périmètre : saison = tournois commencés dans l'année ; un tournoi seul a son slug pour label.
    @Test func scopes() {
        let tournaments = [
            TournamentRef(id: "s3", slug: "lec_split_3_2026", startDate: "2026-07-23", endDate: "2026-09-20", leagueId: "l"),
            TournamentRef(id: "s1", slug: "lec_split_1_2026", startDate: "2026-01-16", endDate: "2026-03-01", leagueId: "l"),
            TournamentRef(id: "su", slug: "lec_summer_2025", startDate: "2025-08-02", endDate: "2025-09-29", leagueId: "l"),
        ]
        #expect(SeasonScope.season(2026, tournaments: tournaments) == SeasonScope(tournamentIds: ["s3", "s1"], label: "2026"))
        #expect(SeasonScope.tournament(tournaments[0]) == SeasonScope(tournamentIds: ["s3"], label: "lec_split_3_2026"))
    }

    /// Masquage de la saison : `SpoilerPolicy` sur les équipes (avec id) de chaque match, révélations comprises.
    @Test func seasonMasking() throws {
        let matches = try SeasonFixture.kcMatches()
        var follows = FollowList(teams: [FollowedTeam(id: SeasonFixture.kc, code: "KC", name: "Karmine Corp")])
        #expect(SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: []).isEmpty)
        follows.setSpoilerFree(true, id: SeasonFixture.kc)
        #expect(SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: []).count == 12)
        #expect(SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: [SeasonFixture.match303]).count == 11)
        // Une équipe suivie en anti-spoiler qui n'est pas dans ces matchs ne masque rien.
        let other = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)])
        #expect(SeasonMasking.maskedMatchIds(matches, follows: other, revealed: []).isEmpty)
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/DuelTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Duels de joueurs (spec saison §3.3) : composition poste par poste et barres en miroir.
@Suite struct DuelTests {
    private func kcCatalog() throws -> [Team] {
        try JSONDecoder.lolesports().decode(TeamsResponse.self, from: SeasonFixture.data("getTeams_karmine-corp"))
            .data.teams.elements
    }

    /// Effectif du catalogue, dans l'ordre des postes (le catalogue liste « bottom » avant « mid »).
    @Test func lineupFollowsTheRolesOrder() throws {
        let slots = Duel.lineup(teamId: SeasonFixture.kc, catalog: try kcCatalog(), games: [])
        #expect(slots.map(\.role) == Duel.roles)
        #expect(slots.map(\.name) == ["Canna", "Yike", "kyeahoo", "Caliste", "Busio"])
        #expect(slots[0].playerId == "103495716771322725")
        #expect(slots[0].image == "http://static.lolesports.com/players/1774651372836_canna.png")
    }

    /// Deux joueurs au même poste : celui qui a le plus de games ; à égalité le premier listé.
    @Test func substituteWithMoreGamesIsChosen() throws {
        let game = try SeasonFixture.summary304()
        let roster = [TeamPlayer(id: "sub", summonerName: "Remplaçant", image: nil, role: "top"),
                      TeamPlayer(id: "103495716771322725", summonerName: "Canna", image: nil, role: "top")]
        let team = Team(id: SeasonFixture.kc, slug: "karmine-corp", name: "Karmine Corp", code: "KC", image: nil,
                        status: "active", homeLeague: nil, players: roster)
        #expect(Duel.lineup(teamId: SeasonFixture.kc, catalog: [team], games: [game])[0].name == "Canna")
        #expect(Duel.lineup(teamId: SeasonFixture.kc, catalog: [team], games: [])[0].name == "Remplaçant")
    }

    /// Sans effectif au catalogue : la composition de la game la plus récente (noms bruts du flux).
    @Test func lineupFallsBackToTheLatestGame() throws {
        let slots = Duel.lineup(teamId: SeasonFixture.g2, catalog: try kcCatalog(), games: [try SeasonFixture.summary304()])
        #expect(slots.map(\.name) == ["G2 BrokenBlade", "G2 SkewMond", "G2 Caps", "G2 Hans Sama", "G2 Labrov"])
        #expect(Duel.lineup(teamId: "inconnue", catalog: [], games: []).allSatisfy { $0.playerId == nil })
    }

    /// Canna contre BrokenBlade sur la game 304 : KDA 2,0 contre 4,5 ; part des dégâts 22,78 % contre 12,19 %.
    @Test func mirroredBars() throws {
        let game = try SeasonFixture.summary304()
        let duel = Duel.players(left: "103495716771322725", right: "99566406047571736", games: [game], masked: [])
        #expect(duel.left?.name == "KC Canna")
        #expect(duel.right?.name == "G2 BrokenBlade")
        #expect(duel.bars.map(\.metric) == DuelMetric.allCases)
        let kda = duel.bars[0]
        #expect(kda.left == 2 && kda.right == 4.5)
        #expect(abs(kda.leftRatio - 2 / 4.5) < 1e-9 && kda.rightRatio == 1)
        let damage = try #require(duel.bars.first { $0.metric == .damageShare })
        #expect(damage.left == 0.2278 && damage.right == 0.1219)
        #expect(damage.leftRatio == 1)
        let participation = try #require(duel.bars.first { $0.metric == .killParticipation })
        #expect(abs((participation.right ?? 0) - 9.0 / 23.0) < 1e-9)
    }

    /// Match masqué : aucune stat de ce match (ici la seule game) → « — » des deux côtés, barres vides.
    @Test func maskedGamesGiveNoBars() throws {
        let game = try SeasonFixture.summary304()
        let duel = Duel.players(left: "103495716771322725", right: "99566406047571736", games: [game],
                                masked: [SeasonFixture.match303])
        #expect(duel.left == nil && duel.right == nil)
        #expect(duel.bars.allSatisfy { $0.left == nil && $0.right == nil && $0.leftRatio == 0 && $0.rightRatio == 0 })
        // Palier A : part des dégâts « — », les autres barres restent.
        let tierA = Duel.players(left: "103495716771322725", right: "99566406047571736",
                                 games: [try SeasonFixture.summary304(enriched: false)], masked: [])
        let damage = try #require(tierA.bars.first { $0.metric == .damageShare })
        #expect(damage.left == nil && damage.right == nil && damage.leftRatio == 0)
        #expect(tierA.bars[0].left == 2)
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

Run : `bash scripts/lolkit.sh test --filter "SeasonStatsTests|DuelTests"`
Expected : échec de compilation (`cannot find 'SeasonStats' in scope`…).

- [ ] **Step 3: Écrire le périmètre et les types de résultat**

Créer `LoLKit/Sources/LoLKit/Season/SeasonScope.swift` :

```swift
import Foundation

/// Périmètre d'un calcul de saison (pilules « Saison 2026 », « LEC Split 3 »… de la page équipe, spec saison §3.1) :
/// un ensemble de tournois. `label` est une valeur, pas un texte : l'année (« 2026 ») ou le slug du tournoi.
public struct SeasonScope: Sendable, Hashable {
    public let tournamentIds: Set<String>
    public let label: String

    public init(tournamentIds: Set<String>, label: String) {
        self.tournamentIds = tournamentIds
        self.label = label
    }

    /// Saison = année civile (§1.2) : les tournois commencés cette année-là.
    public static func season(_ year: Int, tournaments: [TournamentRef]) -> SeasonScope {
        SeasonScope(tournamentIds: Set(tournaments.filter { $0.year == year }.map(\.id)), label: String(year))
    }

    /// Un seul tournoi ; `label` = son slug.
    public static func tournament(_ tournament: TournamentRef) -> SeasonScope {
        SeasonScope(tournamentIds: [tournament.id], label: tournament.slug)
    }

    public func contains(_ match: SeasonMatch) -> Bool {
        tournamentIds.contains(match.tournamentId)
    }
}
```

Créer `LoLKit/Sources/LoLKit/Season/TeamSeason.swift` :

```swift
import Foundation

/// Série en cours d'une équipe (séries de matchs, du plus récent ; spec saison §1.5).
public struct Streak: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case wins
        case losses
    }

    public let kind: Kind
    public let count: Int

    public init(kind: Kind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

/// Une pastille de forme : victoire, défaite, ou match masqué (pastille neutre à sa place, §1.8).
public struct FormPip: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case win
        case loss
        case masked
    }

    public let matchId: String
    public let outcome: Outcome

    public init(matchId: String, outcome: Outcome) {
        self.matchId = matchId
        self.outcome = outcome
    }
}

/// Un champion joué : nombre de games et victoires (vainqueur exact ou déduit ; une game au vainqueur inconnu n'est
/// comptée ni en victoire ni en défaite). `winsEstimated` : au moins une game au vainqueur déduit (« estimé »).
public struct ChampionUse: Sendable, Equatable {
    public let champion: String
    public let games: Int
    public let wins: Int
    public let winsEstimated: Bool

    public init(champion: String, games: Int, wins: Int, winsEstimated: Bool) {
        self.champion = champion
        self.games = games
        self.wins = wins
        self.winsEstimated = winsEstimated
    }
}

/// Moyennes par game d'une équipe (games lues seulement). Morts = kills adverses.
public struct TeamAverages: Sendable, Equatable {
    public let kills: Double
    public let deaths: Double
    public let gold: Double
    public let towers: Double
    public let dragons: Double
    public let barons: Double
    public let inhibitors: Double
    public let durationSeconds: Double
    /// Écart de gold moyen à 15 min (équipe − adversaire) sur les `gold15Games` games enrichies ; nil sans aucune.
    public let gold15Diff: Double?
    public let gold15Games: Int

    public init(kills: Double, deaths: Double, gold: Double, towers: Double, dragons: Double, barons: Double,
                inhibitors: Double, durationSeconds: Double, gold15Diff: Double?, gold15Games: Int) {
        self.kills = kills
        self.deaths = deaths
        self.gold = gold
        self.towers = towers
        self.dragons = dragons
        self.barons = barons
        self.inhibitors = inhibitors
        self.durationSeconds = durationSeconds
        self.gold15Diff = gold15Diff
        self.gold15Games = gold15Games
    }
}

/// Saison d'une équipe dans un périmètre (§1.5), calculée à la lecture, jamais stockée. Bilans depuis les victoires de
/// série (exactes) ; moyennes depuis les games lues. Matchs masqués exclus de tout, comptés dans `maskedMatches`.
public struct TeamSeason: Sendable, Equatable {
    public let teamId: String
    public let scope: SeasonScope
    public let seriesWins: Int
    public let seriesLosses: Int
    public let gameWins: Int
    public let gameLosses: Int
    /// Série en cours (≥ 2) ; nil si plus courte, ou si le match le plus récent est masqué.
    public let streak: Streak?
    /// 5 derniers matchs, du plus ancien au plus récent (le plus récent à droite).
    public let form: [FormPip]
    /// Games jouées des matchs non masqués : lues, à lire, sans stats (échec définitif de la collecte).
    public let gamesCounted: Int
    public let gamesPending: Int
    public let gamesWithoutStats: Int
    /// Matchs masqués (jamais un nombre de games : il trahirait la longueur de la série, §1.8).
    public let maskedMatches: Int
    public let averages: TeamAverages?
    /// Drakes par type sur les games lues.
    public let dragonTypes: [String: Int]
    /// 8 champions les plus joués par l'équipe, par nombre de games.
    public let champions: [ChampionUse]

    public init(teamId: String, scope: SeasonScope, seriesWins: Int, seriesLosses: Int, gameWins: Int, gameLosses: Int,
                streak: Streak?, form: [FormPip], gamesCounted: Int, gamesPending: Int, gamesWithoutStats: Int,
                maskedMatches: Int, averages: TeamAverages?, dragonTypes: [String: Int], champions: [ChampionUse]) {
        self.teamId = teamId
        self.scope = scope
        self.seriesWins = seriesWins
        self.seriesLosses = seriesLosses
        self.gameWins = gameWins
        self.gameLosses = gameLosses
        self.streak = streak
        self.form = form
        self.gamesCounted = gamesCounted
        self.gamesPending = gamesPending
        self.gamesWithoutStats = gamesWithoutStats
        self.maskedMatches = maskedMatches
        self.averages = averages
        self.dragonTypes = dragonTypes
        self.champions = champions
    }
}

/// Face-à-face de deux équipes sur les matchs donnés (séries), masqués exclus et comptés.
public struct HeadToHead: Sendable, Equatable {
    public let teamA: String
    public let teamB: String
    public let winsA: Int
    public let winsB: Int
    /// Matchs comptés, du plus récent au plus ancien.
    public let matchIds: [String]
    public let maskedMatches: Int

    public init(teamA: String, teamB: String, winsA: Int, winsB: Int, matchIds: [String], maskedMatches: Int) {
        self.teamA = teamA
        self.teamB = teamB
        self.winsA = winsA
        self.winsB = winsB
        self.matchIds = matchIds
        self.maskedMatches = maskedMatches
    }
}
```

Créer `LoLKit/Sources/LoLKit/Season/PlayerSeason.swift` :

```swift
import Foundation

/// Une game d'un joueur (5 dernières games, meilleure game de la page joueur, spec saison §3.4).
public struct GameRefLine: Sendable, Equatable {
    public let gameId: String
    public let matchId: String
    public let teamId: String
    public let startedAt: Date
    public let champion: String
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let gold: Int
    /// Victoire de son équipe ; nil si le vainqueur de la game est inconnu.
    public let won: Bool?
    /// Vainqueur déduit (« estimé »).
    public let winEstimated: Bool

    public init(gameId: String, matchId: String, teamId: String, startedAt: Date, champion: String, kills: Int,
                deaths: Int, assists: Int, creepScore: Int, gold: Int, won: Bool?, winEstimated: Bool) {
        self.gameId = gameId
        self.matchId = matchId
        self.teamId = teamId
        self.startedAt = startedAt
        self.champion = champion
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.gold = gold
        self.won = won
        self.winEstimated = winEstimated
    }

    /// (K + A) / max(1, D).
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
}

/// Saison d'un joueur (§1.5), calculée à la lecture sur les games lues de ses matchs non masqués.
public struct PlayerSeason: Sendable, Equatable {
    public let playerId: String
    /// Nom brut du flux dans sa game la plus récente (« KC Canna ») : l'appli affiche `TeamPlayer.summonerName` du
    /// catalogue, sinon `PlayerName.display(name, teamCode:)`.
    public let name: String
    public let role: String
    /// Équipe de sa game la plus récente.
    public let teamId: String
    public let games: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    /// Σ CS / Σ minutes ; Σ gold / Σ minutes ; Σ (K + A) / Σ kills de l'équipe.
    public let csPerMin: Double
    public let goldPerMin: Double
    public let killParticipation: Double
    /// Moyenne sur les `damageShareGames` games enrichies ; nil sans aucune (« — »).
    public let damageShare: Double?
    public let damageShareGames: Int
    public let champions: [ChampionUse]
    /// KDA le plus haut, puis le plus de kills, puis la plus récente.
    public let bestGame: GameRefLine?
    /// 5 dernières games, la plus récente d'abord.
    public let recent: [GameRefLine]

    public init(playerId: String, name: String, role: String, teamId: String, games: Int, kills: Int, deaths: Int,
                assists: Int, csPerMin: Double, goldPerMin: Double, killParticipation: Double, damageShare: Double?,
                damageShareGames: Int, champions: [ChampionUse], bestGame: GameRefLine?, recent: [GameRefLine]) {
        self.playerId = playerId
        self.name = name
        self.role = role
        self.teamId = teamId
        self.games = games
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.csPerMin = csPerMin
        self.goldPerMin = goldPerMin
        self.killParticipation = killParticipation
        self.damageShare = damageShare
        self.damageShareGames = damageShareGames
        self.champions = champions
        self.bestGame = bestGame
        self.recent = recent
    }

    /// (K + A) / max(1, D) sur la somme (pas la moyenne des ratios).
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
}

/// Classement des « Joueurs en forme » (Accueil, spec saison §2.2 n° 6).
public enum PlayerMetric: Sendable, Equatable, CaseIterable {
    case kda
    /// Kills moyens par game.
    case kills
    case csPerMin

    public func value(of player: PlayerSeason) -> Double {
        switch self {
        case .kda: player.kda
        case .kills: Double(player.kills) / Double(max(1, player.games))
        case .csPerMin: player.csPerMin
        }
    }
}
```

- [ ] **Step 4: Écrire les agrégats et le masquage**

Créer `LoLKit/Sources/LoLKit/Season/SeasonStats.swift` :

```swift
import Foundation

/// Agrégats de saison (spec saison §1.5, §1.8), purs et calculés à la lecture : rien n'est stocké. Toutes les fonctions
/// prennent `masked` (ids de match, `SeasonMasking.maskedMatchIds`) : un match masqué ne compte nulle part.
public enum SeasonStats {
    /// Saison de l'équipe `teamId` dans `scope`.
    /// - Parameters:
    ///   - matches: matchs joués (`SeasonMatch.join`), dans n'importe quel ordre ; seuls ceux du périmètre, joués par
    ///     l'équipe (par id) et commencés avant `now` comptent.
    ///   - games: `GameSummary` en cache par id de game (résultats déjà rejoués par `GameWinners`).
    ///   - withoutStats: games en échec définitif de collecte (`CrawlFailure` final) : « N games sans stats ».
    public static func team(_ teamId: String, matches: [SeasonMatch], games: [String: GameSummary], scope: SeasonScope,
                            masked: Set<String>, now: Date, withoutStats: Set<String> = []) -> TeamSeason {
        let played = matches
            .filter { scope.contains($0) && $0.involves(teamId) && $0.startTime <= now }
            .sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        let visible = played.filter { !masked.contains($0.id) }
        var seriesWins = 0, seriesLosses = 0, gameWins = 0, gameLosses = 0
        for match in visible {
            guard let (own, other) = score(match, teamId) else { continue }
            gameWins += own
            gameLosses += other
            if own > other { seriesWins += 1 } else if other > own { seriesLosses += 1 }
        }
        let form = played.suffix(5).map { match -> FormPip in
            if masked.contains(match.id) { return FormPip(matchId: match.id, outcome: .masked) }
            let won = score(match, teamId).map { $0.own > $0.other } ?? false
            return FormPip(matchId: match.id, outcome: won ? .win : .loss)
        }
        var counted: [GameSummary] = []
        var pending = 0, without = 0
        for match in visible {
            for gameId in match.playedGameIds {
                if let summary = games[gameId], summary.line(teamId: teamId) != nil {
                    counted.append(summary)
                } else if withoutStats.contains(gameId) {
                    without += 1
                } else {
                    pending += 1
                }
            }
        }
        var dragonTypes: [String: Int] = [:]
        for summary in counted {
            for dragon in summary.line(teamId: teamId)?.dragons ?? [] { dragonTypes[dragon, default: 0] += 1 }
        }
        let lines = counted.flatMap { summary in
            (summary.line(teamId: teamId)?.players ?? []).map { (summary: summary, teamId: teamId, line: $0) }
        }
        return TeamSeason(
            teamId: teamId, scope: scope, seriesWins: seriesWins, seriesLosses: seriesLosses, gameWins: gameWins,
            gameLosses: gameLosses, streak: streak(teamId, matches: played, masked: masked), form: Array(form),
            gamesCounted: counted.count, gamesPending: pending, gamesWithoutStats: without,
            maskedMatches: played.count - visible.count, averages: averages(teamId, counted),
            dragonTypes: dragonTypes, champions: Array(championUses(lines).prefix(8)))
    }

    /// Série en cours de l'équipe sur `matches` (séries, du plus récent) ; nil si elle fait moins de 2 matchs ou si le
    /// match le plus récent est masqué (la série « en cours » est alors inconnue). S'arrête au premier match masqué.
    public static func streak(_ teamId: String, matches: [SeasonMatch], masked: Set<String>) -> Streak? {
        let ordered = matches.filter { $0.involves(teamId) }.sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        var kind: Streak.Kind?
        var count = 0
        for match in ordered {
            guard !masked.contains(match.id), let (own, other) = score(match, teamId), own != other else { break }
            let current: Streak.Kind = own > other ? .wins : .losses
            if let kind, kind != current { break }
            kind = current
            count += 1
        }
        guard let kind, count >= 2 else { return nil }
        return Streak(kind: kind, count: count)
    }

    /// Saison d'un joueur sur les games données (toutes équipes), masquées exclues ; `since` : games commencées à
    /// partir de cette date (« Semaine »). nil s'il n'a aucune game.
    public static func player(_ playerId: String, games: [GameSummary], masked: Set<String>,
                              since: Date?) -> PlayerSeason? {
        let entries = games
            .filter { summary in !masked.contains(summary.matchId) && (since.map { summary.startedAt >= $0 } ?? true) }
            .compactMap { summary in summary.player(playerId).map { (summary: summary, team: $0.team, line: $0.line) } }
            .sorted { ($0.summary.startedAt, $0.summary.gameId) > ($1.summary.startedAt, $1.summary.gameId) }
        guard let latest = entries.first else { return nil }
        let minutes = entries.reduce(0.0) { $0 + Double($1.summary.durationSeconds) / 60 }
        let kills = entries.reduce(0) { $0 + $1.line.kills }
        let deaths = entries.reduce(0) { $0 + $1.line.deaths }
        let assists = entries.reduce(0) { $0 + $1.line.assists }
        let teamKills = entries.reduce(0) { $0 + $1.team.kills }
        let shares = entries.compactMap(\.line.damageShare)
        let refs = entries.map { entry in
            gameRef(entry.summary, teamId: entry.team.teamId, line: entry.line)
        }
        let best = refs.enumerated().max { a, b in
            (a.element.kda, a.element.kills, -a.offset) < (b.element.kda, b.element.kills, -b.offset)
        }?.element
        return PlayerSeason(
            playerId: playerId, name: latest.line.name, role: latest.line.role, teamId: latest.team.teamId,
            games: entries.count, kills: kills, deaths: deaths, assists: assists,
            csPerMin: minutes > 0 ? Double(entries.reduce(0) { $0 + $1.line.creepScore }) / minutes : 0,
            goldPerMin: minutes > 0 ? Double(entries.reduce(0) { $0 + $1.line.gold }) / minutes : 0,
            killParticipation: teamKills > 0 ? Double(kills + assists) / Double(teamKills) : 0,
            damageShare: shares.isEmpty ? nil : shares.reduce(0, +) / Double(shares.count),
            damageShareGames: shares.count,
            champions: championUses(entries.map { (summary: $0.summary, teamId: $0.team.teamId, line: $0.line) }),
            bestGame: best, recent: Array(refs.prefix(5)))
    }

    /// Joueurs en forme (§2.2 n° 6) : au moins `minGames` games (2 sur la semaine, 5 sur la saison), triés par
    /// `metric` décroissant, puis par nombre de games, puis par nom.
    public static func topPlayers(games: [GameSummary], masked: Set<String>, metric: PlayerMetric, since: Date?,
                                  minGames: Int, limit: Int) -> [PlayerSeason] {
        let ids = Set(games.flatMap { ($0.blue.players + $0.red.players).map(\.playerId) }.filter { !$0.isEmpty })
        return ids.compactMap { player($0, games: games, masked: masked, since: since) }
            .filter { $0.games >= minGames }
            .sorted { a, b in
                let (x, y) = (metric.value(of: a), metric.value(of: b))
                if x != y { return x > y }
                if a.games != b.games { return a.games > b.games }
                return (a.name, a.playerId) < (b.name, b.playerId)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Face-à-face des équipes `a` et `b` sur `matches` (séries gagnées), masqués exclus et comptés.
    public static func headToHead(_ a: String, _ b: String, matches: [SeasonMatch], masked: Set<String>) -> HeadToHead {
        let meetings = matches.filter { $0.involves(a) && $0.involves(b) }
            .sorted { ($0.startTime, $0.id) > ($1.startTime, $1.id) }
        let visible = meetings.filter { !masked.contains($0.id) }
        var winsA = 0, winsB = 0
        for match in visible {
            guard let (own, other) = score(match, a) else { continue }
            if own > other { winsA += 1 } else if other > own { winsB += 1 }
        }
        return HeadToHead(teamA: a, teamB: b, winsA: winsA, winsB: winsB, matchIds: visible.map(\.id),
                          maskedMatches: meetings.count - visible.count)
    }

    // MARK: - Détails

    /// Victoires de l'équipe et de son adversaire dans la série ; nil si l'équipe n'y joue pas.
    static func score(_ match: SeasonMatch, _ teamId: String) -> (own: Int, other: Int)? {
        guard let own = match.teams.first(where: { $0.id == teamId }) else { return nil }
        let other = match.teams.filter { $0.id != teamId }.reduce(0) { $0 + $1.gameWins }
        return (own.gameWins, other)
    }

    static func averages(_ teamId: String, _ games: [GameSummary]) -> TeamAverages? {
        guard !games.isEmpty else { return nil }
        let count = Double(games.count)
        func mean(_ value: (GameSummary) -> Int) -> Double { Double(games.reduce(0) { $0 + value($1) }) / count }
        let diffs = games.compactMap { summary -> Int? in
            guard let own = summary.line(teamId: teamId)?.gold15,
                  let other = summary.opponentLine(of: teamId)?.gold15 else { return nil }
            return own - other
        }
        return TeamAverages(
            kills: mean { $0.line(teamId: teamId)?.kills ?? 0 },
            deaths: mean { $0.opponentLine(of: teamId)?.kills ?? 0 },
            gold: mean { $0.line(teamId: teamId)?.gold ?? 0 },
            towers: mean { $0.line(teamId: teamId)?.towers ?? 0 },
            dragons: mean { $0.line(teamId: teamId)?.dragons.count ?? 0 },
            barons: mean { $0.line(teamId: teamId)?.barons ?? 0 },
            inhibitors: mean { $0.line(teamId: teamId)?.inhibitors ?? 0 },
            durationSeconds: mean(\.durationSeconds),
            gold15Diff: diffs.isEmpty ? nil : Double(diffs.reduce(0, +)) / Double(diffs.count),
            gold15Games: diffs.count)
    }

    /// Champions par nombre de games (puis par nom) ; une victoire = la game gagnée par l'équipe du joueur (vainqueur
    /// exact ou déduit ; « estimé » si au moins une victoire est déduite).
    static func championUses(_ lines: [(summary: GameSummary, teamId: String, line: PlayerGameLine)]) -> [ChampionUse] {
        var byChampion: [String: (games: Int, wins: Int, estimated: Bool)] = [:]
        for (summary, team, line) in lines where !line.champion.isEmpty {
            var entry = byChampion[line.champion] ?? (0, 0, false)
            entry.games += 1
            if summary.result.winnerTeamId == team, summary.result.basis != .unknown {
                entry.wins += 1
                if summary.result.basis == .inferred { entry.estimated = true }
            }
            byChampion[line.champion] = entry
        }
        return byChampion
            .map { ChampionUse(champion: $0.key, games: $0.value.games, wins: $0.value.wins, winsEstimated: $0.value.estimated) }
            .sorted { $0.games != $1.games ? $0.games > $1.games : $0.champion < $1.champion }
    }

    static func gameRef(_ summary: GameSummary, teamId: String, line: PlayerGameLine) -> GameRefLine {
        let known = summary.result.basis != .unknown && summary.result.winnerTeamId != nil
        return GameRefLine(gameId: summary.gameId, matchId: summary.matchId, teamId: teamId,
                           startedAt: summary.startedAt, champion: line.champion, kills: line.kills,
                           deaths: line.deaths, assists: line.assists, creepScore: line.creepScore, gold: line.gold,
                           won: known ? summary.result.winnerTeamId == teamId : nil,
                           winEstimated: summary.result.basis == .inferred)
    }
}
```

Créer `LoLKit/Sources/LoLKit/Season/SeasonMasking.swift` :

```swift
/// Anti-spoiler du socle (spec saison §1.8) : quels matchs de la saison sont masqués.
public enum SeasonMasking {
    /// Ids des matchs masqués : `SpoilerPolicy.isMasked` sur les équipes du match (avec id quand il est connu), sauf
    /// match révélé. À passer en `masked` à `SeasonStats`, `Duel`, `HomeFeed` et `CrawlPlanner` (aucune requête pour
    /// un match masqué).
    public static func maskedMatchIds(_ matches: [SeasonMatch], follows: FollowList, revealed: Set<String>) -> Set<String> {
        Set(matches.filter { SpoilerPolicy.isMasked($0.teams, matchId: $0.id, follows: follows, revealed: revealed) }
            .map(\.id))
    }
}
```

- [ ] **Step 5: Écrire les duels**

Créer `LoLKit/Sources/LoLKit/Season/Duel.swift` :

```swift
import Foundation

/// Un poste d'une composition de duel : le joueur retenu (nil si personne n'est connu à ce poste).
public struct DuelSlot: Sendable, Equatable {
    public let role: String
    public let playerId: String?
    /// Nom du catalogue (« Canna ») ou nom brut du flux si le joueur ne vient que d'une game.
    public let name: String?
    public let image: String?

    public init(role: String, playerId: String?, name: String?, image: String?) {
        self.role = role
        self.playerId = playerId
        self.name = name
        self.image = image
    }
}

/// Une stat comparée dans un duel (barres en miroir, spec saison §3.3).
public enum DuelMetric: Sendable, Equatable, CaseIterable {
    case kda
    case csPerMin
    case goldPerMin
    case damageShare
    case killParticipation

    public func value(of player: PlayerSeason) -> Double? {
        switch self {
        case .kda: player.kda
        case .csPerMin: player.csPerMin
        case .goldPerMin: player.goldPerMin
        case .damageShare: player.damageShare
        case .killParticipation: player.killParticipation
        }
    }
}

/// Une barre en miroir : valeurs (nil = « — ») et largeurs relatives (valeur / max des deux, 0 si inconnue).
public struct DuelBar: Sendable, Equatable {
    public let metric: DuelMetric
    public let left: Double?
    public let right: Double?
    public let leftRatio: Double
    public let rightRatio: Double

    public init(metric: DuelMetric, left: Double?, right: Double?, leftRatio: Double, rightRatio: Double) {
        self.metric = metric
        self.left = left
        self.right = right
        self.leftRatio = leftRatio
        self.rightRatio = rightRatio
    }
}

/// Duel de deux joueurs : leurs saisons (nil sans game lue) et les barres.
public struct PlayerDuel: Sendable, Equatable {
    public let left: PlayerSeason?
    public let right: PlayerSeason?
    public let bars: [DuelBar]

    public init(left: PlayerSeason?, right: PlayerSeason?, bars: [DuelBar]) {
        self.left = left
        self.right = right
        self.bars = bars
    }
}

/// Duels de joueurs, poste par poste (spec saison §3.3). Anti-spoiler : `games` et `masked` comme pour `SeasonStats`
/// (match masqué → seulement les stats de saison, aucune donnée de ce match ; c'est l'appli qui n'affiche pas la ligne
/// « Cette game » d'un match masqué).
public enum Duel {
    /// Postes dans l'ordre d'affichage.
    public static let roles = ["top", "jungle", "mid", "bottom", "support"]

    /// Composition d'une équipe pour un duel : l'effectif du catalogue, poste par poste ; deux joueurs au même poste →
    /// celui qui a le plus de games dans `games`, à égalité le premier listé (§1.5). Sans effectif au catalogue pour un
    /// poste : le joueur de ce poste dans la game la plus récente de l'équipe.
    /// - Parameter games: games lues, déjà privées des matchs masqués.
    public static func lineup(teamId: String, catalog: [Team], games: [GameSummary]) -> [DuelSlot] {
        let roster = catalog.first { $0.id == teamId }?.players ?? []
        var played: [String: Int] = [:]
        for summary in games {
            for line in summary.line(teamId: teamId)?.players ?? [] { played[line.playerId, default: 0] += 1 }
        }
        let latest = games.filter { $0.line(teamId: teamId) != nil }.max { $0.startedAt < $1.startedAt }
        return roles.map { role in
            let candidates = roster.filter { $0.role == role }
            if let chosen = candidates.enumerated().max(by: { a, b in
                (played[a.element.id] ?? 0, -a.offset) < (played[b.element.id] ?? 0, -b.offset)
            })?.element {
                return DuelSlot(role: role, playerId: chosen.id, name: chosen.summonerName, image: chosen.image)
            }
            if let line = latest?.line(teamId: teamId)?.players.first(where: { $0.role == role }) {
                return DuelSlot(role: role, playerId: line.playerId, name: line.name, image: nil)
            }
            return DuelSlot(role: role, playerId: nil, name: nil, image: nil)
        }
    }

    /// Duel de deux joueurs quelconques sur leurs games lues non masquées (toute la saison donnée).
    public static func players(left: String, right: String, games: [GameSummary], masked: Set<String>) -> PlayerDuel {
        let a = SeasonStats.player(left, games: games, masked: masked, since: nil)
        let b = SeasonStats.player(right, games: games, masked: masked, since: nil)
        let bars = DuelMetric.allCases.map { metric -> DuelBar in
            let x = a.flatMap { metric.value(of: $0) }
            let y = b.flatMap { metric.value(of: $0) }
            let top = max(x ?? 0, y ?? 0)
            return DuelBar(metric: metric, left: x, right: y, leftRatio: top > 0 ? (x ?? 0) / top : 0,
                           rightRatio: top > 0 ? (y ?? 0) / top : 0)
        }
        return PlayerDuel(left: a, right: b, bars: bars)
    }
}
```

- [ ] **Step 6: Lancer les tests pour les voir passer**

Run : `bash scripts/lolkit.sh test --filter "SeasonStatsTests|DuelTests"`
Expected : `15 tests` passés (10 + 5).

- [ ] **Step 7: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 374 tests in 44 suites passed` (sur `main` après la vague 1), aucun `warning:`.

- [ ] **Step 8: Commit**

```bash
git add LoLKit/Sources/LoLKit/Season/SeasonScope.swift LoLKit/Sources/LoLKit/Season/TeamSeason.swift LoLKit/Sources/LoLKit/Season/PlayerSeason.swift LoLKit/Sources/LoLKit/Season/SeasonStats.swift LoLKit/Sources/LoLKit/Season/SeasonMasking.swift LoLKit/Sources/LoLKit/Season/Duel.swift LoLKit/Tests/LoLKitTests/Support/SeasonMatches.swift LoLKit/Tests/LoLKitTests/SeasonStatsTests.swift LoLKit/Tests/LoLKitTests/DuelTests.swift
git commit -m "feat(lolkit): agrégats de saison — bilan, forme, série, moyennes, champions, joueur (KDA, CS/min, gold/min, participation, part des dégâts), joueurs en forme, face-à-face, duels poste par poste ; matchs masqués exclus et comptés" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l3-agregats
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task L4: Planification et cadence de la collecte

**Branche :** `nuit2/lolkit-l4-collecte` — **Vague 2** (worktree depuis `main` après la fusion de la vague 1)

**Files:**
- Create: `LoLKit/Sources/LoLKit/Season/CrawlPlanner.swift`, `LoLKit/Sources/LoLKit/Season/CrawlPacer.swift`
- Test: `LoLKit/Tests/LoLKitTests/CrawlPlannerTests.swift`

**Interfaces:**
- Consumes : (L1) `SeasonMatch` (`id`, `tournamentId`, `leagueSlug`, `startTime`, `teams`, `playedGameIds`), `TournamentRef` (`year`, `startDate`, `isActive(today:)`), `Standings` / `StandingsStage` / `BracketMatch.state`, `StandingsResponse` (tests), `LoLClient.tournaments(leagueId:)` (tests) ; (L2) `GameSummary` (`enriched`, `startedAt`, `blue.teamId`, `red.teamId`, `gameId`), `TeamGameLine`, `SeasonFixture.data(_:)` (tests) ; (`HEAD`) `LoLAPIError { http(status:), statsDisabled, noData }`.
- Produces :
  - `public struct CrawlJob: Sendable, Equatable { enum Tier: String { case a = "A", b = "B" }; gameId, matchId, tournamentId, leagueSlug: String; number: Int; tier: Tier; priority: Int }`.
  - `public struct CrawlWanted: Sendable, Equatable { openedTeamId: String?; followedTeamIds: [String]; worldsStageMatchIds: Set<String>; followedLeagueSlugs: [String]; currentTournamentIds: Set<String> }`.
  - `public struct CrawlFailure: Codable, Sendable, Equatable { enum Reason: String, Codable { statsDisabled, noData, notFinished, http }; var reason; var attempts: Int; var lastAttempt: Date; static let maxAttempts = 3; static let retryDelay: TimeInterval = 3600; var isFinal: Bool; func allowsRetry(now:) -> Bool; static func record(_:previous:now:) -> CrawlFailure?; static func reason(for: any Error) -> Reason }`.
  - `public enum CrawlPlanner { static func jobs(wanted:matches:have:failures:masked:now:) -> [CrawlJob]; static func seasonTournaments(_:year:) -> [TournamentRef]; static func currentTournament(_:today:) -> TournamentRef?; static func currentStageMatchIds(_ standings: Standings) -> Set<String>; static let diskLimit = 2_000; static func evictions(_:followedTeamIds:limit:) -> [String]; static let tournamentsMaxAge: TimeInterval = 86_400; static let activeTournamentMaxAge: TimeInterval = 1_800; static func maxAge(of:today:) -> TimeInterval?; static func needsRefresh(fetchedAt:now:maxAge:) -> Bool }`.
  - `public struct CrawlPacer: Sendable, Equatable { static let baseInterval: TimeInterval = 2; static let backoff: [TimeInterval] = [4, 8, 16, 32, 60]; static let maxConsecutiveFailures = 5; static let sessionRequestBudget = 300; enum Outcome { answered, retryable }; enum StopReason { budget, failures }; enum Decision { wait(TimeInterval), stop(StopReason) }; init(budget: Int = 300); var requestsMade, consecutiveFailures: Int; var canRequest: Bool; mutating func next(after: Outcome) -> Decision; static func outcome(of: (any Error)?) -> Outcome }`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/CrawlPlannerTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Collecte progressive (spec saison §1.6, §1.7) : ordre des jobs, anti-spoiler, échecs, cadence, budget, cache.
@Suite struct CrawlPlannerTests {
    private static let lec3 = "115548681802226458"
    private static let lec1 = "115548424304940735"
    private static let worlds = "115660540725177488"
    private static let lck3 = "lck3"
    private static let lck1 = "lck1"
    private let now = date("2026-10-20T12:00:00Z")

    private func team(_ id: String, wins: Int) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id, image: nil, result: MatchTeam.Result(outcome: nil, gameWins: wins))
    }

    private func match(_ id: String, _ tournament: String, _ league: String, _ start: String, _ a: String, _ b: String,
                       games: Int = 2) -> SeasonMatch {
        SeasonMatch(id: id, tournamentId: tournament, leagueSlug: league, stageSlug: nil, startTime: date(start),
                    blockName: nil, bestOf: 3, teams: [team(a, wins: 2), team(b, wins: games - 2)],
                    playedGameIds: (1...games).map { "\(id)-g\($0)" })
    }

    private var matches: [SeasonMatch] {
        [
            match("kc-g2", Self.lec3, "lec", "2026-09-06T15:00:00Z", "KC", "G2", games: 3),
            match("kc-vit", Self.lec3, "lec", "2026-07-24T17:30:00Z", "KC", "VIT"),
            match("kc-old", Self.lec1, "lec", "2026-02-01T17:00:00Z", "KC", "FNC"),
            match("kc-sk", Self.lec3, "lec", "2026-08-29T15:00:00Z", "KC", "SK"),
            match("fnc-th", Self.lec3, "lec", "2026-08-30T15:00:00Z", "FNC", "TH"),
            match("fnc-old", Self.lec1, "lec", "2026-02-02T15:00:00Z", "FNC", "TH"),
            match("t1-gen", Self.worlds, "worlds", "2026-10-18T09:00:00Z", "T1", "GEN"),
            match("hle-dk", Self.lck3, "lck", "2026-08-20T09:00:00Z", "HLE", "DK"),
            match("hle-old", Self.lck1, "lck", "2026-02-20T09:00:00Z", "HLE", "DK"),
            match("ns-bro", Self.lck3, "lck", "2026-10-25T09:00:00Z", "NS", "BRO"),
            match("g2-th", Self.lec3, "lec", "2026-08-01T15:00:00Z", "G2", "TH"),
        ]
    }

    private var wanted: CrawlWanted {
        CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC"], worldsStageMatchIds: ["t1-gen"],
                    followedLeagueSlugs: ["lck"], currentTournamentIds: [Self.lec3, Self.worlds, Self.lck3])
    }

    private func summary(_ gameId: String, _ blue: String, _ red: String, enriched: Bool = false) -> GameSummary {
        func line(_ id: String) -> TeamGameLine {
            TeamGameLine(teamId: id, kills: 0, gold: 0, towers: 0, inhibitors: 0, barons: 0, dragons: [], gold15: nil,
                         players: [])
        }
        return GameSummary(gameId: gameId, matchId: "m", tournamentId: Self.lec3, leagueSlug: "lec", number: 1,
                           patch: nil, startedAt: date("2026-09-06T15:00:00Z"), endedAt: date("2026-09-06T15:30:00Z"),
                           durationSeconds: 1800, result: .unknown, blue: line(blue), red: line(red), enriched: enriched)
    }

    /// Page ouverte (FNC, tournoi en cours) → équipes suivies (le plus récent d'abord, tournoi en cours avant les
    /// précédents) → Mondial → ligues suivies → palier B ; masqué jamais ; à venir et hors périmètre jamais.
    @Test func jobsFollowThePriorityOrder() {
        let have = ["kc-g2-g1": summary("kc-g2-g1", "KC", "G2"), "kc-g2-g2": summary("kc-g2-g2", "G2", "KC", enriched: true)]
        let jobs = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: have, failures: [:], masked: ["kc-sk"], now: now)
        #expect(jobs.map(\.gameId) == [
            "fnc-th-g1", "fnc-th-g2",
            "kc-g2-g3", "kc-vit-g1", "kc-vit-g2", "kc-old-g1", "kc-old-g2",
            "t1-gen-g1", "t1-gen-g2",
            "hle-dk-g1", "hle-dk-g2", "hle-old-g1", "hle-old-g2",
            "kc-g2-g1",
        ])
        #expect(jobs.map(\.priority) == [0, 0, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 4])
        #expect(jobs.last?.tier == .b)
        #expect(jobs.dropLast().allSatisfy { $0.tier == .a })
        #expect(jobs[2] == CrawlJob(gameId: "kc-g2-g3", matchId: "kc-g2", tournamentId: Self.lec3, leagueSlug: "lec",
                                    number: 3, tier: .a, priority: 1))
        // Jamais un match masqué, ni un match à venir (NS-BRO), ni un match que rien ne demande (G2-TH).
        #expect(!jobs.contains { $0.matchId == "kc-sk" || $0.matchId == "ns-bro" || $0.matchId == "g2-th" })
        // Une ancienne game de FNC (tournoi précédent) n'est pas demandée pour une page ouverte.
        #expect(!jobs.contains { $0.matchId == "fnc-old" })
    }

    /// Révéler le match le rend éligible au passage suivant ; suivre l'équipe ouverte la fait passer au groupe 1.
    @Test func revealingOrFollowingChangesThePlan() {
        let revealed = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: [:], failures: [:], masked: [], now: now)
        #expect(revealed.contains { $0.matchId == "kc-sk" })
        let followFnc = CrawlWanted(openedTeamId: "FNC", followedTeamIds: ["KC", "FNC"], worldsStageMatchIds: [],
                                    followedLeagueSlugs: [], currentTournamentIds: [Self.lec3])
        let jobs = CrawlPlanner.jobs(wanted: followFnc, matches: matches, have: [:], failures: [:], masked: [], now: now)
        #expect(jobs.allSatisfy { $0.priority == 1 })
        #expect(jobs.contains { $0.matchId == "fnc-old" })
    }

    /// Échecs : 404 définitif ; 204 / pas de fin → réessai après 1 h, 3 fois au plus ; `http` → toujours repris.
    @Test func failuresAreRetriedByTheRules() {
        let soon = now.addingTimeInterval(-30 * 60)
        let hourAgo = now.addingTimeInterval(-61 * 60)
        let failures: [String: CrawlFailure] = [
            "kc-vit-g1": CrawlFailure(reason: .statsDisabled, attempts: 1, lastAttempt: hourAgo),
            "kc-vit-g2": CrawlFailure(reason: .noData, attempts: 1, lastAttempt: soon),
            "kc-old-g1": CrawlFailure(reason: .notFinished, attempts: 2, lastAttempt: hourAgo),
            "kc-old-g2": CrawlFailure(reason: .noData, attempts: 3, lastAttempt: hourAgo),
            "kc-g2-g1": CrawlFailure(reason: .http, attempts: 4, lastAttempt: now),
        ]
        let ids = CrawlPlanner.jobs(wanted: wanted, matches: matches, have: [:], failures: failures, masked: [], now: now)
            .map(\.gameId)
        #expect(!ids.contains("kc-vit-g1") && !ids.contains("kc-vit-g2") && !ids.contains("kc-old-g2"))
        #expect(ids.contains("kc-old-g1") && ids.contains("kc-g2-g1"))
        #expect(failures["kc-vit-g1"]?.isFinal == true)
        #expect(failures["kc-old-g2"]?.isFinal == true)
        #expect(failures["kc-old-g1"]?.isFinal == false)
        #expect(failures["kc-g2-g1"]?.isFinal == false)
    }

    @Test func recordingFailures() {
        let first = CrawlFailure.record(.noData, previous: nil, now: now)
        #expect(first == CrawlFailure(reason: .noData, attempts: 1, lastAttempt: now))
        let second = CrawlFailure.record(.noData, previous: first, now: now.addingTimeInterval(3600))
        #expect(second?.attempts == 2)
        #expect(CrawlFailure.record(.notFinished, previous: second, now: now)?.attempts == 1)
        // Erreur HTTP : la game n'est pas en cause, l'échec précédent est gardé tel quel.
        #expect(CrawlFailure.record(.http, previous: nil, now: now) == nil)
        #expect(CrawlFailure.record(.http, previous: second, now: now) == second)
        #expect(CrawlFailure.reason(for: LoLAPIError.statsDisabled) == .statsDisabled)
        #expect(CrawlFailure.reason(for: LoLAPIError.noData) == .noData)
        #expect(CrawlFailure.reason(for: LoLAPIError.http(status: 503)) == .http)
        #expect(CrawlFailure.reason(for: URLError(.timedOut)) == .http)
    }

    /// `crawl.json` : `[gameId: CrawlFailure]`, `JSONEncoder` par défaut.
    @Test func failuresRoundTrip() throws {
        let failures = ["g1": CrawlFailure(reason: .notFinished, attempts: 2, lastAttempt: now)]
        #expect(try JSONDecoder().decode([String: CrawlFailure].self, from: JSONEncoder().encode(failures)) == failures)
    }

    /// 2 s entre deux requêtes ; recul 4, 8, 16, 32 s ; arrêt au 5e échec d'affilée ; une réponse remet à 2 s.
    @Test func pacerBacksOffAndStops() {
        var pacer = CrawlPacer()
        #expect(pacer.canRequest)
        let outcomes: [CrawlPacer.Outcome] = [.answered, .retryable, .retryable, .answered,
                                              .retryable, .retryable, .retryable, .retryable, .retryable]
        var decisions: [CrawlPacer.Decision] = []
        for outcome in outcomes { decisions.append(pacer.next(after: outcome)) }
        #expect(decisions == [.wait(2), .wait(4), .wait(8), .wait(2), .wait(4), .wait(8), .wait(16), .wait(32),
                              .stop(.failures)])
        #expect(!pacer.canRequest)
        #expect(pacer.requestsMade == 9)
        #expect(pacer.consecutiveFailures == 5)
    }

    /// 300 requêtes par session (≈ 150 games au palier A) : la 300e arrête la collecte.
    @Test func pacerStopsAtTheSessionBudget() {
        var pacer = CrawlPacer()
        #expect(CrawlPacer.sessionRequestBudget == 300)
        var decisions: [CrawlPacer.Decision] = []
        for _ in 1..<300 { decisions.append(pacer.next(after: .answered)) }
        #expect(decisions.allSatisfy { $0 == .wait(2) })
        #expect(pacer.canRequest)
        let last = pacer.next(after: .answered)
        #expect(last == .stop(.budget))
        #expect(!pacer.canRequest)
        var small = CrawlPacer(budget: 2)
        let first = small.next(after: .retryable)
        let second = small.next(after: .answered)
        #expect(first == .wait(4))
        #expect(second == .stop(.budget))
    }

    @Test func outcomeOfARequest() {
        #expect(CrawlPacer.outcome(of: nil) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.noData) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.statsDisabled) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.http(status: 400)) == .answered)
        #expect(CrawlPacer.outcome(of: LoLAPIError.http(status: 429)) == .retryable)
        #expect(CrawlPacer.outcome(of: LoLAPIError.http(status: 503)) == .retryable)
        #expect(CrawlPacer.outcome(of: URLError(.notConnectedToInternet)) == .retryable)
    }

    /// Saison 2026 de la LEC (fixture réelle) : 3 splits ; le 14/10 le split 3 est fini, il reste « le dernier commencé ».
    @Test func seasonAndCurrentTournaments() async throws {
        let fake = FakeTransport()
        try await fake.on("getTournamentsForLeague", body: String(decoding: try SeasonFixture.data(
            "getTournamentsForLeague_lec_reduced"), as: UTF8.self))
        let tournaments = try await LoLClient(transport: fake).tournaments(leagueId: "98767991302996019")
        #expect(CrawlPlanner.seasonTournaments(tournaments, year: 2026).map(\.slug)
                == ["lec_split_3_2026", "lec_split_2_2026", "lec_split_1_2026"])
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2026-10-14")?.slug == "lec_split_3_2026")
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2026-04-10")?.slug == "lec_split_2_2026")
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2026-03-15")?.slug == "lec_split_1_2026")
        #expect(CrawlPlanner.currentTournament(tournaments, today: "2020-01-01") == nil)
    }

    /// Étape en cours du Mondial : celle du premier match non terminé ; tout terminé → la dernière étape.
    @Test func currentWorldsStage() throws {
        let worlds = try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(
            "getStandings_worlds26_reduced")).data.standings.elements[0]
        #expect(CrawlPlanner.currentStageMatchIds(worlds) == ["115660588583040710", "115660588583171786"])
        let lec = try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(
            "getStandings_lec3_reduced")).data.standings.elements[0]
        #expect(CrawlPlanner.currentStageMatchIds(lec) == ["115548681803406327", "115548681803406333"])
        #expect(CrawlPlanner.currentStageMatchIds(Standings(stages: [])).isEmpty)
    }

    /// Budget disque : 2 000 games ; au-delà, les plus anciennes sans équipe suivie, jamais une game d'équipe suivie.
    @Test func diskBudgetKeepsFollowedTeams() {
        func game(_ id: String, _ start: String, _ blue: String) -> GameSummary {
            let base = summary(id, blue, "X")
            return GameSummary(gameId: id, matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
                               startedAt: date(start), endedAt: date(start).addingTimeInterval(1800),
                               durationSeconds: 1800, result: .unknown, blue: base.blue, red: base.red, enriched: false)
        }
        let games = [game("old-kc", "2026-01-01T10:00:00Z", "KC"), game("old", "2026-01-02T10:00:00Z", "G2"),
                     game("mid", "2026-03-01T10:00:00Z", "T1"), game("new", "2026-09-01T10:00:00Z", "GEN")]
        #expect(CrawlPlanner.diskLimit == 2_000)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC"], limit: 2) == ["old", "mid"])
        #expect(CrawlPlanner.evictions(games, followedTeamIds: ["KC", "G2", "T1", "GEN"], limit: 2).isEmpty)
        #expect(CrawlPlanner.evictions(games, followedTeamIds: [], limit: 4).isEmpty)
    }

    /// Tournois 24 h ; tournoi actif 30 min ; tournoi terminé jamais relu ; pas de copie → à lire.
    @Test func enumerationRefresh() {
        let active = TournamentRef(id: "w", slug: "worlds_2026", startDate: "2026-10-15", endDate: "2026-11-15", leagueId: "")
        let done = TournamentRef(id: "s3", slug: "lec_split_3_2026", startDate: "2026-07-23", endDate: "2026-09-20", leagueId: "")
        #expect(CrawlPlanner.maxAge(of: active, today: "2026-10-20") == 1_800)
        #expect(CrawlPlanner.maxAge(of: done, today: "2026-10-20") == nil)
        let fetched = date("2026-10-20T12:00:00Z")
        #expect(CrawlPlanner.needsRefresh(fetchedAt: nil, now: fetched, maxAge: nil))
        #expect(!CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(1_799), maxAge: 1_800))
        #expect(CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(1_800), maxAge: 1_800))
        #expect(!CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(1e7), maxAge: nil))
        #expect(CrawlPlanner.needsRefresh(fetchedAt: fetched, now: fetched.addingTimeInterval(-60),
                                          maxAge: CrawlPlanner.tournamentsMaxAge))
        #expect(CrawlPlanner.tournamentsMaxAge == 86_400)
    }
}
```

- [ ] **Step 2: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter CrawlPlannerTests`
Expected : échec de compilation (`cannot find 'CrawlPlanner' in scope`…).

- [ ] **Step 3: Écrire `CrawlPlanner`**

Créer `LoLKit/Sources/LoLKit/Season/CrawlPlanner.swift` :

```swift
import Foundation

/// Une game à lire par la collecte (spec saison §1.6).
public struct CrawlJob: Sendable, Equatable {
    /// Palier A : `window` sans `startingTime` + `window` après la fin (obligatoire). Palier B : `window` à 15 min +
    /// `details` (enrichissement).
    public enum Tier: String, Sendable, Equatable {
        case a = "A"
        case b = "B"
    }

    public let gameId: String
    public let matchId: String
    public let tournamentId: String
    public let leagueSlug: String
    /// N° de la game dans la série.
    public let number: Int
    public let tier: Tier
    /// Groupe de priorité, 0 = le plus urgent (voir `CrawlPlanner.jobs`).
    public let priority: Int

    public init(gameId: String, matchId: String, tournamentId: String, leagueSlug: String, number: Int, tier: Tier,
                priority: Int) {
        self.gameId = gameId
        self.matchId = matchId
        self.tournamentId = tournamentId
        self.leagueSlug = leagueSlug
        self.number = number
        self.tier = tier
        self.priority = priority
    }
}

/// Ce que la collecte doit couvrir (§1.6), rempli par l'appli.
public struct CrawlWanted: Sendable, Equatable {
    /// Équipe dont la page est ouverte (priorité 0 si elle n'est pas suivie : tournoi en cours seulement).
    public let openedTeamId: String?
    public let followedTeamIds: [String]
    /// Matchs de l'étape en cours du Mondial (`CrawlPlanner.currentStageMatchIds`).
    public let worldsStageMatchIds: Set<String>
    public let followedLeagueSlugs: [String]
    /// Tournois en cours : celui de chaque ligue concernée et l'international en cours.
    public let currentTournamentIds: Set<String>

    public init(openedTeamId: String?, followedTeamIds: [String], worldsStageMatchIds: Set<String>,
                followedLeagueSlugs: [String], currentTournamentIds: Set<String>) {
        self.openedTeamId = openedTeamId
        self.followedTeamIds = followedTeamIds
        self.worldsStageMatchIds = worldsStageMatchIds
        self.followedLeagueSlugs = followedLeagueSlugs
        self.currentTournamentIds = currentTournamentIds
    }
}

/// Échec de lecture d'une game (`cache/season/crawl.json`, seul état à mémoriser : le reste, c'est le disque).
public struct CrawlFailure: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable, Equatable {
        /// 404 : Riot ne fournit pas les stats de cette game → définitif.
        case statsDisabled
        /// 204 / vide → réessai après 1 h, 3 fois au plus.
        case noData
        /// Pas de frame `finished` → réessai après 1 h, 3 fois au plus.
        case notFinished
        /// 429, 5xx, réseau : suit le recul de `CrawlPacer`, jamais un échec de la game.
        case http
    }

    public var reason: Reason
    public var attempts: Int
    public var lastAttempt: Date

    public init(reason: Reason, attempts: Int, lastAttempt: Date) {
        self.reason = reason
        self.attempts = attempts
        self.lastAttempt = lastAttempt
    }

    /// Réessais de `noData` / `notFinished`, et délai entre deux essais.
    public static let maxAttempts = 3
    public static let retryDelay: TimeInterval = 3600

    /// Plus jamais réessayée : stats désactivées, ou 3 essais sans données / sans fin (« N games sans stats »).
    public var isFinal: Bool {
        switch reason {
        case .statsDisabled: true
        case .noData, .notFinished: attempts >= Self.maxAttempts
        case .http: false
        }
    }

    /// Peut-on retenter la game à `now` ?
    public func allowsRetry(now: Date) -> Bool {
        switch reason {
        case .http: true
        case .statsDisabled: false
        case .noData, .notFinished: !isFinal && now.timeIntervalSince(lastAttempt) >= Self.retryDelay
        }
    }

    /// Échec à enregistrer après une lecture ratée (`http` : rien, la game n'est pas en cause).
    public static func record(_ reason: Reason, previous: CrawlFailure?, now: Date) -> CrawlFailure? {
        guard reason != .http else { return previous }
        let attempts = previous?.reason == reason ? (previous?.attempts ?? 0) + 1 : 1
        return CrawlFailure(reason: reason, attempts: attempts, lastAttempt: now)
    }

    /// Raison d'une erreur de `LoLClient` : 404 → `statsDisabled`, vide → `noData`, le reste → `http`.
    public static func reason(for error: any Error) -> Reason {
        switch error as? LoLAPIError {
        case .statsDisabled: .statsDisabled
        case .noData: .noData
        default: .http
        }
    }
}

/// Planification pure de la collecte progressive (§1.6) : quelles games lire, dans quel ordre. L'appli exécute (au
/// premier plan seulement, avec `CrawlPacer`) ; l'état, c'est le disque (une game est faite si son `GameSummary`
/// existe) plus `crawl.json` pour les échecs.
public enum CrawlPlanner {
    /// Ordre des groupes : 0 page ouverte (équipe non suivie, tournoi en cours) ; 1 équipes suivies, saison entière ;
    /// 2 étape en cours du Mondial ; 3 ligues suivies, tournoi en cours puis précédents ; 4 palier B des équipes suivies
    /// (tournois en cours). Dans un groupe : tournoi en cours d'abord, puis le match le plus récent, puis le n° de game.
    /// **Jamais de job pour un match de `masked`** ; une game en échec n'est reprise que si `allowsRetry(now:)`.
    public static func jobs(wanted: CrawlWanted, matches: [SeasonMatch], have: [String: GameSummary],
                            failures: [String: CrawlFailure], masked: Set<String>, now: Date) -> [CrawlJob] {
        let followed = Set(wanted.followedTeamIds)
        let leagues = Set(wanted.followedLeagueSlugs)
        var best: [String: (job: CrawlJob, current: Bool, start: Date)] = [:]
        for match in matches where !masked.contains(match.id) && match.startTime <= now {
            let current = wanted.currentTournamentIds.contains(match.tournamentId)
            let teamIds = Set(match.teams.compactMap(\.id))
            var groups: [Int] = []
            if let opened = wanted.openedTeamId, !followed.contains(opened), teamIds.contains(opened), current {
                groups.append(0)
            }
            let involvesFollowed = !teamIds.isDisjoint(with: followed)
            if involvesFollowed { groups.append(1) }
            if wanted.worldsStageMatchIds.contains(match.id) { groups.append(2) }
            if leagues.contains(match.leagueSlug) { groups.append(3) }
            for (index, gameId) in match.playedGameIds.enumerated() {
                if let failure = failures[gameId], !failure.allowsRetry(now: now) { continue }
                let job: CrawlJob
                if let summary = have[gameId] {
                    guard !summary.enriched, involvesFollowed, current else { continue }
                    job = CrawlJob(gameId: gameId, matchId: match.id, tournamentId: match.tournamentId,
                                   leagueSlug: match.leagueSlug, number: index + 1, tier: .b, priority: 4)
                } else {
                    guard let group = groups.min() else { continue }
                    job = CrawlJob(gameId: gameId, matchId: match.id, tournamentId: match.tournamentId,
                                   leagueSlug: match.leagueSlug, number: index + 1, tier: .a, priority: group)
                }
                if let existing = best[gameId], existing.job.priority <= job.priority { continue }
                best[gameId] = (job, current, match.startTime)
            }
        }
        return best.values.sorted { a, b in
            if a.job.priority != b.job.priority { return a.job.priority < b.job.priority }
            if a.current != b.current { return a.current }
            if a.start != b.start { return a.start > b.start }
            if a.job.matchId != b.job.matchId { return a.job.matchId < b.job.matchId }
            return a.job.number < b.job.number
        }.map(\.job)
    }

    /// Tournois de la saison `year` (année civile, §1.2), du plus récent au plus ancien.
    public static func seasonTournaments(_ tournaments: [TournamentRef], year: Int) -> [TournamentRef] {
        tournaments.filter { $0.year == year }.sorted { ($0.startDate, $0.id) > ($1.startDate, $1.id) }
    }

    /// Tournoi en cours d'une ligue : l'actif (`isActive`), sinon le dernier commencé ; nil si aucun n'a commencé.
    public static func currentTournament(_ tournaments: [TournamentRef], today: String) -> TournamentRef? {
        let started = tournaments.filter { !$0.startDate.isEmpty && $0.startDate <= today }
            .sorted { ($0.startDate, $0.id) > ($1.startDate, $1.id) }
        return started.first { $0.isActive(today: today) } ?? started.first
    }

    /// Matchs de l'étape en cours du Mondial (§1.6, groupe 2) : l'étape qui contient le premier match non `completed`
    /// (dans l'ordre de l'API) ; si tout est joué, la dernière étape. Équipes encore inconnues comprises (rien à lire).
    public static func currentStageMatchIds(_ standings: Standings) -> Set<String> {
        let stage = standings.stages.first { stage in
            stage.sections.contains { $0.matches.contains { $0.state != .completed } }
        } ?? standings.stages.last
        return Set(stage?.sections.flatMap { $0.matches.map(\.id) } ?? [])
    }

    /// Budget disque (§1.7) : au-delà de `limit` games, ids à supprimer — les plus anciennes (`startedAt`) qui ne
    /// concernent aucune équipe suivie. Une game d'une équipe suivie n'est jamais supprimée (le cache peut alors
    /// dépasser la limite).
    public static let diskLimit = 2_000

    public static func evictions(_ games: [GameSummary], followedTeamIds: Set<String>,
                                 limit: Int = diskLimit) -> [String] {
        guard games.count > limit else { return [] }
        let removable = games
            .filter { !followedTeamIds.contains($0.blue.teamId) && !followedTeamIds.contains($0.red.teamId) }
            .sorted { ($0.startedAt, $0.gameId) < ($1.startedAt, $1.gameId) }
        return removable.prefix(games.count - limit).map(\.gameId)
    }

    /// Fraîcheur de l'énumération (§1.2) : tournois d'une ligue 24 h ; résultats et classements d'un tournoi actif
    /// 30 min ; d'un tournoi terminé, jamais relus (nil).
    public static let tournamentsMaxAge: TimeInterval = 86_400
    public static let activeTournamentMaxAge: TimeInterval = 1_800

    public static func maxAge(of tournament: TournamentRef, today: String) -> TimeInterval? {
        tournament.isActive(today: today) ? activeTournamentMaxAge : nil
    }

    /// À relire ? Pas de copie → oui ; `maxAge` nil → jamais ; sinon âge ≥ `maxAge` (ou horloge qui a reculé).
    public static func needsRefresh(fetchedAt: Date?, now: Date, maxAge: TimeInterval?) -> Bool {
        guard let fetchedAt else { return true }
        guard let maxAge else { return false }
        let age = now.timeIntervalSince(fetchedAt)
        return age < 0 || age >= maxAge
    }
}
```

- [ ] **Step 4: Écrire `CrawlPacer`**

Créer `LoLKit/Sources/LoLKit/Season/CrawlPacer.swift` :

```swift
import Foundation

/// Cadence de la collecte (spec saison §1.6), pure : l'appli demande `next(after:)` après chaque requête et attend le
/// délai rendu (ou s'arrête). Une requête toutes les 2 s (y compris les 2 requêtes d'une même game) ; 429, 5xx ou
/// erreur réseau → 4, 8, 16, 32 s ; 5 échecs d'affilée → arrêt jusqu'à la prochaine session ; une réponse → retour à
/// 2 s ; 300 requêtes par session au premier plan (énumération comprise) → arrêt.
public struct CrawlPacer: Sendable, Equatable {
    public static let baseInterval: TimeInterval = 2
    /// Attente après le n-ième échec d'affilée (le 5e arrête la session : la dernière valeur est le plafond si
    /// `maxConsecutiveFailures` augmente un jour).
    public static let backoff: [TimeInterval] = [4, 8, 16, 32, 60]
    public static let maxConsecutiveFailures = 5
    public static let sessionRequestBudget = 300

    /// Issue d'une requête, du point de vue de la cadence.
    public enum Outcome: Sendable, Equatable {
        /// Le serveur a répondu (200, 204, 404…) : la game a une réponse, bonne ou non.
        case answered
        /// 429, 5xx ou erreur réseau : on recule.
        case retryable
    }

    public enum StopReason: Sendable, Equatable {
        /// 300 requêtes faites dans cette session.
        case budget
        /// 5 échecs d'affilée.
        case failures
    }

    public enum Decision: Sendable, Equatable {
        /// Attendre ce délai (s) avant la requête suivante.
        case wait(TimeInterval)
        case stop(StopReason)
    }

    public let budget: Int
    public private(set) var requestsMade = 0
    public private(set) var consecutiveFailures = 0

    public init(budget: Int = CrawlPacer.sessionRequestBudget) {
        self.budget = budget
    }

    /// Reste-t-il au moins une requête dans le budget ?
    public var canRequest: Bool { requestsMade < budget && consecutiveFailures < Self.maxConsecutiveFailures }

    /// À appeler après chaque requête faite : compte la requête et rend la suite.
    public mutating func next(after outcome: Outcome) -> Decision {
        requestsMade += 1
        switch outcome {
        case .answered:
            consecutiveFailures = 0
        case .retryable:
            consecutiveFailures += 1
            if consecutiveFailures >= Self.maxConsecutiveFailures { return .stop(.failures) }
        }
        if requestsMade >= budget { return .stop(.budget) }
        if consecutiveFailures == 0 { return .wait(Self.baseInterval) }
        return .wait(Self.backoff[min(consecutiveFailures, Self.backoff.count) - 1])
    }

    /// Issue d'une requête de `LoLClient` : pas d'erreur, `noData` (204), `statsDisabled` (404) ou autre statut HTTP
    /// (400…) → `.answered` ; 429, 5xx et toute erreur non HTTP (réseau, délai dépassé) → `.retryable`.
    public static func outcome(of error: (any Error)?) -> Outcome {
        guard let error else { return .answered }
        switch error as? LoLAPIError {
        case .noData, .statsDisabled:
            return .answered
        case let .http(status):
            return status == 429 || status >= 500 ? .retryable : .answered
        case nil:
            return .retryable
        }
    }
}
```

- [ ] **Step 5: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter CrawlPlannerTests`
Expected : `12 tests` passés.

- [ ] **Step 6: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 371 tests in 43 suites passed` (sur `main` après la vague 1), aucun `warning:`.

- [ ] **Step 7: Commit**

```bash
git add LoLKit/Sources/LoLKit/Season/CrawlPlanner.swift LoLKit/Sources/LoLKit/Season/CrawlPacer.swift LoLKit/Tests/LoLKitTests/CrawlPlannerTests.swift
git commit -m "feat(lolkit): collecte progressive — jobs par priorité (page ouverte, équipes suivies, Mondial, ligues, palier B), jamais un match masqué, échecs et réessais, cadence 2 s avec recul, budget de 300 requêtes, budget disque, fraîcheur de l'énumération" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l4-collecte
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task L5: Ligues suivies et nouveaux réglages

**Branche :** `nuit2/lolkit-l5-ligues-reglages` — **Vague 1**

**Files:**
- Modify: `LoLKit/Sources/LoLKit/Follow/FollowList.swift` (`FollowedLeague`, `FollowList.leagues`), `LoLKit/Sources/LoLKit/Follow/ScheduleQuery.swift` (ligues suivies), `LoLKit/Sources/LoLKit/Reminders/MatchReminders.swift` (`notifyStarts`), `LoLKit/Sources/LoLKit/Storage/AppSettings.swift` (`onboardingDone`, `revealedStandingIds`), `LoLKit/Tests/LoLKitTests/PublicInitTests.swift`
- Test: `LoLKit/Tests/LoLKitTests/LeagueFollowTests.swift`

**Interfaces:**
- Consumes (à `HEAD`) : `FollowList { teams; init(teams:); followed(in:); involves(_:); team(id:); setSpoilerFree(_:id:) }`, `FollowedTeam`, `League(id:slug:name:region:image:priority:)`, `League.internationalSlugs`, `MatchReminders.plan(schedule:follows:revealed:now:lead:)` et ses internes `identifier(matchId:)`, `title(_:follows:lead:)`, `subtitle(_:)`, `TeamCards.build`, `Presenter.maskedLatestTeamIds`, `Presenter.nextLine` ; `AppSettings(liveActivityMode:revealedMatchIds:matchRemindersEnabled:matchReminderLead:)` ; `LossyArray` ; tests : `makeTeam(_:id:name:image:wins:)`, `date(_:)`.
- Produces :
  - `public struct FollowedLeague: Codable, Sendable, Equatable, Identifiable { let id: String; var slug, name: String; var image: String?; var notifyStarts: Bool; init(id:slug:name:image: = nil, notifyStarts: = false); init(league: League) }`.
  - `FollowList.leagues: [FollowedLeague]` (`public private(set)`), `init(teams: = [], leagues: = [])`, `containsLeague(id:)`, `league(slug:) -> FollowedLeague?`, `mutating follow(league: League)`, `unfollowLeague(id:)`, `setNotifyStarts(_:leagueId:)` ; décodage : `leagues` absent ou illisible → `[]`.
  - `ScheduleQuery.leagueIds(follows:leagues:)` inclut les ligues suivies.
  - `MatchReminders.plan` : en plus, les matchs à venir des ligues `notifyStarts` sans équipe suivie ni « TBD ».
  - `AppSettings.onboardingDone: Bool` (défaut false), `AppSettings.revealedStandingIds: Set<String>` (défaut vide), `init(…, matchReminderLead:, onboardingDone: = false, revealedStandingIds: = [])`, décodage tolérant.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/LeagueFollowTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Suivre une ligue et nouveaux réglages (spec saison §3.5, §3.7) : liste des suivis, calendrier, notifications,
/// décodage tolérant des fichiers d'avant ce lot.
@Suite struct LeagueFollowTests {
    private let lec = League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: "http://lec.png",
                             priority: 3)
    private let lck = League(id: "98767991310872058", slug: "lck", name: "LCK", region: "KOREA", image: nil, priority: 2)
    private let worlds = League(id: "98767975604431411", slug: "worlds", name: "Mondial", region: nil, image: nil,
                                priority: 1)

    @Test func followAndUnfollowALeague() {
        var list = FollowList()
        list.follow(league: lec)
        list.follow(league: lec)
        list.follow(league: lck)
        #expect(list.leagues.map(\.slug) == ["lec", "lck"])
        #expect(list.leagues[0] == FollowedLeague(id: lec.id, slug: "lec", name: "LEC", image: "http://lec.png"))
        #expect(!list.leagues[0].notifyStarts)
        #expect(list.containsLeague(id: lck.id))
        #expect(list.league(slug: "lck")?.name == "LCK")
        list.setNotifyStarts(true, leagueId: lck.id)
        #expect(list.league(slug: "lck")?.notifyStarts == true)
        list.unfollowLeague(id: lec.id)
        #expect(list.leagues.map(\.slug) == ["lck"])
        #expect(list.teams.isEmpty)
    }

    /// `follows.json` d'avant ce lot (sans `leagues`) : les équipes restent, aucune ligue. Une ligue illisible est
    /// ignorée, les autres sont gardées ; un interrupteur illisible vaut « désactivé ».
    @Test func followListDecodesTolerantly() throws {
        let old = #"{"teams":[{"id":"111692118851466302","code":"KC","name":"Karmine Corp"}]}"#
        let decoded = try JSONDecoder().decode(FollowList.self, from: Data(old.utf8))
        #expect(decoded.teams.map(\.code) == ["KC"])
        #expect(decoded.leagues.isEmpty)

        let mixed = #"""
        {"teams":[],"leagues":[{"id":"1","slug":"lec","name":"LEC","notifyStarts":"oui"},{"slug":"sans-id"},
                                {"id":"2","slug":"lck","name":"LCK","notifyStarts":true,"image":42}]}
        """#
        let leagues = try JSONDecoder().decode(FollowList.self, from: Data(mixed.utf8)).leagues
        #expect(leagues == [FollowedLeague(id: "1", slug: "lec", name: "LEC"),
                            FollowedLeague(id: "2", slug: "lck", name: "LCK", notifyStarts: true)])
        let notALeagueList = #"{"teams":[],"leagues":"lec"}"#
        #expect(try JSONDecoder().decode(FollowList.self, from: Data(notALeagueList.utf8)).leagues.isEmpty)
    }

    @Test func followListRoundTripsWithItsLeagues() throws {
        var list = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")])
        list.follow(league: lck)
        list.setNotifyStarts(true, leagueId: lck.id)
        #expect(try JSONDecoder().decode(FollowList.self, from: JSONEncoder().encode(list)) == list)
    }

    /// Le calendrier demande aussi les ligues suivies (dans l'ordre de `getLeagues`).
    @Test func scheduleQueryIncludesFollowedLeagues() {
        let leagues = [worlds, lck, lec]
        var list = FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", homeLeagueName: "LEC")])
        #expect(ScheduleQuery.leagueIds(follows: list, leagues: leagues) == [worlds.id, lec.id])
        list.follow(league: lck)
        #expect(ScheduleQuery.leagueIds(follows: list, leagues: leagues) == [worlds.id, lck.id, lec.id])
        #expect(ScheduleQuery.leagueIds(follows: FollowList(), leagues: leagues) == [worlds.id])
    }

    private func match(_ id: String, start: String, league: String = "lck", teams: [MatchTeam],
                       state: EventState = .unstarted) -> MatchEvent {
        MatchEvent(startTime: date(start), state: state, type: "match", blockName: "Semaine 3",
                   league: LeagueRef(id: nil, slug: league, name: league.uppercased(), image: nil),
                   match: MatchInfo(id: id, teams: teams, strategy: Strategy(type: "bestOf", count: 3), games: nil),
                   streams: nil)
    }

    /// Ligue suivie avec `notifyStarts` : chaque match à venir est notifié ; sans l'interrupteur, rien.
    @Test func notifyStartsRemindsEveryMatchOfTheLeague() {
        let events = [
            match("t1-gen", start: "2026-10-20T08:00:00Z", teams: [makeTeam("T1"), makeTeam("GEN")]),
            match("hle-dk", start: "2026-10-20T10:00:00Z", teams: [makeTeam("HLE"), makeTeam("DK")]),
            match("lec", start: "2026-10-20T16:00:00Z", league: "lec", teams: [makeTeam("G2"), makeTeam("FNC")]),
            match("tbd", start: "2026-10-21T08:00:00Z", teams: [makeTeam("TBD"), makeTeam("TBD")]),
            match("past", start: "2026-10-15T08:00:00Z", teams: [makeTeam("NS"), makeTeam("BRO")], state: .completed),
        ]
        var list = FollowList()
        list.follow(league: lck)
        let now = date("2026-10-19T12:00:00Z")
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900).isEmpty)
        list.setNotifyStarts(true, leagueId: lck.id)
        let reminders = MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900)
        #expect(reminders.map(\.matchId) == ["t1-gen", "hle-dk"])
        #expect(reminders[0].title == "T1 vs GEN dans 15 min")
        #expect(reminders[0].subtitle == "LCK · Semaine 3 · Bo3")
        #expect(reminders[0].fireDate == date("2026-10-20T07:45:00Z"))
        // Heure de notification passée : rien.
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: date("2026-10-20T07:50:00Z"),
                                    lead: 900).map(\.matchId) == ["hle-dk"])
    }

    /// Un match de la ligue avec une équipe suivie garde la règle des équipes (F1 + C) : jamais notifié quand
    /// `Presenter.nextLine` le cache, et une seule fois sinon.
    @Test func followedTeamsKeepTheNextLineRule() {
        let t1 = MatchTeam(id: "t1", name: "T1", code: "T1", image: nil, result: nil)
        let gen = MatchTeam(id: "gen", name: "Gen.G", code: "GEN", image: nil, result: nil)
        let last = match("t1-last", start: "2026-10-18T08:00:00Z",
                         teams: [MatchTeam(id: "t1", name: "T1", code: "T1", image: nil,
                                           result: MatchTeam.Result(outcome: "win", gameWins: 2)),
                                 makeTeam("DK", wins: 0)], state: .completed)
        let next = match("t1-gen", start: "2026-10-20T08:00:00Z", teams: [t1, gen])
        let later = match("t1-hle", start: "2026-10-22T08:00:00Z", teams: [t1, makeTeam("HLE")])
        var list = FollowList(teams: [FollowedTeam(id: "t1", code: "T1", name: "T1")])
        list.follow(league: lck)
        list.setNotifyStarts(true, leagueId: lck.id)
        let now = date("2026-10-19T12:00:00Z")
        // T1 suivie normalement : son prochain match une fois, pas le suivant (règle des équipes : le prochain seul).
        #expect(MatchReminders.plan(schedule: [last, next, later], follows: list, revealed: [], now: now, lead: 900)
                    .map(\.matchId) == ["t1-gen"])
        // T1 en anti-spoiler, dernier match masqué (F1) : rien pour T1, même par la ligue.
        list.setSpoilerFree(true, id: "t1")
        #expect(MatchReminders.plan(schedule: [last, next, later], follows: list, revealed: [], now: now, lead: 900)
                    .isEmpty)
    }

    /// Réglages d'avant ce lot : onboarding non fait, aucun classement révélé ; valeurs illisibles → par défaut.
    @Test func newSettingsDecodeTolerantly() throws {
        let defaults = AppSettings()
        #expect(!defaults.onboardingDone)
        #expect(defaults.revealedStandingIds.isEmpty)
        let old = #"{"liveActivityMode":"manual","revealedMatchIds":["m1"],"matchRemindersEnabled":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.liveActivityMode == .manual)
        #expect(decoded.matchRemindersEnabled)
        #expect(!decoded.onboardingDone)
        #expect(decoded.revealedStandingIds.isEmpty)
        let odd = #"{"onboardingDone":"oui","revealedStandingIds":"t1"}"#
        let oddDecoded = try JSONDecoder().decode(AppSettings.self, from: Data(odd.utf8))
        #expect(!oddDecoded.onboardingDone && oddDecoded.revealedStandingIds.isEmpty)

        var settings = AppSettings(onboardingDone: true, revealedStandingIds: ["115548681802226458"])
        settings.revealedStandingIds.insert("115660540725177488")
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }
}
```

Dans `LoLKit/Tests/LoLKitTests/PublicInitTests.swift` (construction depuis un autre module, sans `@testable`) :

Remplacement 1/1 — remplacer exactement :

```swift
    @Test func scoreLine() {
```

par :

```swift
    /// Ligues suivies et nouveaux réglages (spec saison §3.5, §3.7) : construits par l'appli (onboarding, Réglages).
    @Test func followedLeaguesAndSettings() {
        let league = League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 3)
        let followed = FollowedLeague(league: league)
        #expect(followed == FollowedLeague(id: "98767991302996019", slug: "lec", name: "LEC"))
        let list = FollowList(teams: [], leagues: [FollowedLeague(id: "1", slug: "lck", name: "LCK", image: nil,
                                                                  notifyStarts: true)])
        #expect(list.leagues.first?.notifyStarts == true)
        let settings = AppSettings(liveActivityMode: .manual, revealedMatchIds: [], matchRemindersEnabled: false,
                                   matchReminderLead: 900, onboardingDone: true, revealedStandingIds: ["t"])
        #expect(settings.onboardingDone && settings.revealedStandingIds == ["t"])
    }

    @Test func scoreLine() {
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

Run : `bash scripts/lolkit.sh test --filter "LeagueFollowTests|PublicInitTests"`
Expected : échec de compilation (`cannot find 'FollowedLeague' in scope`, `extra arguments 'onboardingDone'`…).

- [ ] **Step 3: Suivre une ligue**

Dans `LoLKit/Sources/LoLKit/Follow/FollowList.swift` :

Remplacement 1/1 — remplacer exactement :

```swift
/// Les équipes suivies, dans l'ordre où elles ont été suivies.
public struct FollowList: Codable, Sendable, Equatable {
    public private(set) var teams: [FollowedTeam]

    public init(teams: [FollowedTeam] = []) {
        self.teams = teams
    }

    private enum CodingKeys: String, CodingKey {
        case teams
    }

    /// Une entrée illisible est ignorée : les autres équipes suivies sont conservées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decode(LossyArray<FollowedTeam>.self, forKey: .teams).elements
    }
```

par :

```swift
/// Une ligue suivie (spec saison §3.5) : ses matchs vont dans le calendrier, l'Accueil et « À ne pas rater ».
public struct FollowedLeague: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var slug: String
    public var name: String
    public var image: String?
    /// Notifications de début de match pour tous les matchs de la ligue (désactivées par défaut).
    public var notifyStarts: Bool

    public init(id: String, slug: String, name: String, image: String? = nil, notifyStarts: Bool = false) {
        self.id = id
        self.slug = slug
        self.name = name
        self.image = image
        self.notifyStarts = notifyStarts
    }

    public init(league: League) {
        self.init(id: league.id, slug: league.slug, name: league.name, image: league.image)
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, image, notifyStarts
    }

    /// `id`, `slug` et `name` indispensables ; logo illisible → nil, interrupteur illisible → désactivé.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        notifyStarts = (try? container.decodeIfPresent(Bool.self, forKey: .notifyStarts)) ?? false
    }
}

/// Les équipes suivies, dans l'ordre où elles ont été suivies, et les ligues suivies.
public struct FollowList: Codable, Sendable, Equatable {
    public private(set) var teams: [FollowedTeam]
    /// Ligues suivies, dans l'ordre où elles ont été suivies (spec saison §3.5).
    public private(set) var leagues: [FollowedLeague]

    public init(teams: [FollowedTeam] = [], leagues: [FollowedLeague] = []) {
        self.teams = teams
        self.leagues = leagues
    }

    private enum CodingKeys: String, CodingKey {
        case teams, leagues
    }

    /// Une entrée illisible est ignorée : les autres équipes suivies sont conservées. `leagues` absent (liste
    /// enregistrée avant les ligues) ou illisible → aucune ligue.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decode(LossyArray<FollowedTeam>.self, forKey: .teams).elements
        leagues = (try? container.decodeIfPresent(LossyArray<FollowedLeague>.self, forKey: .leagues))?.elements ?? []
    }

    public func containsLeague(id: String) -> Bool {
        leagues.contains { $0.id == id }
    }

    /// Ligue suivie de ce slug (les matchs du calendrier portent `league.slug`, pas toujours l'id).
    public func league(slug: String) -> FollowedLeague? {
        leagues.first { $0.slug == slug }
    }

    public mutating func follow(league: League) {
        guard !containsLeague(id: league.id) else { return }
        leagues.append(FollowedLeague(league: league))
    }

    public mutating func unfollowLeague(id: String) {
        leagues.removeAll { $0.id == id }
    }

    public mutating func setNotifyStarts(_ on: Bool, leagueId: String) {
        guard let index = leagues.firstIndex(where: { $0.id == leagueId }) else { return }
        leagues[index].notifyStarts = on
    }
```

Remplacer tout le contenu de `LoLKit/Sources/LoLKit/Follow/ScheduleQuery.swift` par :

```swift
/// Quelles ligues demander à `getSchedule`.
public enum ScheduleQuery {
    /// Ligues d'attache des équipes suivies + ligues suivies + compétitions internationales, dans l'ordre de
    /// `getLeagues`.
    public static func leagueIds(follows: FollowList, leagues: [League]) -> [String] {
        let homeNames = Set(follows.teams.compactMap(\.homeLeagueName))
        let followedIds = Set(follows.leagues.map(\.id))
        return leagues
            .filter { League.internationalSlugs.contains($0.slug) || homeNames.contains($0.name) || followedIds.contains($0.id) }
            .map(\.id)
    }
}
```

- [ ] **Step 4: Notifier les matchs d'une ligue**

Dans `LoLKit/Sources/LoLKit/Reminders/MatchReminders.swift` :

Remplacement 1/2 — remplacer exactement :

```swift
    /// (adversaire suivi en anti-spoiler au dernier match masqué). Donc au plus un match par équipe suivie : son prochain.
```

par :

```swift
    /// (adversaire suivi en anti-spoiler au dernier match masqué). Donc au plus un match par équipe suivie : son prochain.
    /// Ligues suivies avec `notifyStarts` (spec saison §3.5) : en plus, chacun de leurs matchs à venir qui n'oppose
    /// aucune équipe suivie (ceux-là restent soumis à la règle ci-dessus) ni une équipe encore inconnue (« TBD »).
```

Remplacement 2/2 — remplacer exactement :

```swift
        return Array(reminders.sorted { ($0.fireDate, $0.matchId) < ($1.fireDate, $1.matchId) }.prefix(maxCount))
```

par :

```swift
        let notifiedSlugs = Set(follows.leagues.filter(\.notifyStarts).map(\.slug))
        for event in schedule where notifiedSlugs.contains(event.league.slug) && event.state == .unstarted
            && !planned.contains(event.id) && !follows.involves(event.match.teams)
            && !event.match.teams.contains(where: \.isPlaceholder) {
            let fireDate = event.startTime.addingTimeInterval(-lead)
            guard fireDate > now else { continue }
            planned.insert(event.id)
            reminders.append(MatchReminder(id: identifier(matchId: event.id), matchId: event.id, fireDate: fireDate,
                                           title: title(event, follows: follows, lead: lead),
                                           subtitle: subtitle(event)))
        }
        return Array(reminders.sorted { ($0.fireDate, $0.matchId) < ($1.fireDate, $1.matchId) }.prefix(maxCount))
```

- [ ] **Step 5: Ajouter les réglages**

Dans `LoLKit/Sources/LoLKit/Storage/AppSettings.swift` :

Remplacement 1/2 — remplacer exactement :

```swift
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
```

par :

```swift
    public var matchReminderLead: TimeInterval {
        didSet {
            if !MatchReminders.leadOptions.contains(matchReminderLead) {
                matchReminderLead = MatchReminders.defaultLead
            }
        }
    }
    /// Premier lancement passé (onboarding vu ou utilisateur existant, spec saison §3.7).
    public var onboardingDone: Bool
    /// Tournois dont le classement a été révélé malgré l'anti-spoiler (spec saison §3.5) : ne révèle aucun match.
    public var revealedStandingIds: Set<String>

    public init(liveActivityMode: LiveActivityMode = .automatic, revealedMatchIds: Set<String> = [],
                matchRemindersEnabled: Bool = false, matchReminderLead: TimeInterval = MatchReminders.defaultLead,
                onboardingDone: Bool = false, revealedStandingIds: Set<String> = []) {
        self.liveActivityMode = liveActivityMode
        self.revealedMatchIds = revealedMatchIds
        self.matchRemindersEnabled = matchRemindersEnabled
        self.matchReminderLead = Self.lead(matchReminderLead)
        self.onboardingDone = onboardingDone
        self.revealedStandingIds = revealedStandingIds
    }

    private enum CodingKeys: String, CodingKey {
        case liveActivityMode, revealedMatchIds, matchRemindersEnabled, matchReminderLead, onboardingDone
        case revealedStandingIds
    }
```

Remplacement 2/2 — remplacer exactement :

```swift
        matchReminderLead = Self.lead((try? container.decodeIfPresent(TimeInterval.self, forKey: .matchReminderLead))
            ?? MatchReminders.defaultLead)
    }
```

par :

```swift
        matchReminderLead = Self.lead((try? container.decodeIfPresent(TimeInterval.self, forKey: .matchReminderLead))
            ?? MatchReminders.defaultLead)
        onboardingDone = (try? container.decodeIfPresent(Bool.self, forKey: .onboardingDone)) ?? false
        revealedStandingIds = (try? container.decodeIfPresent(Set<String>.self, forKey: .revealedStandingIds)) ?? []
    }
```

- [ ] **Step 6: Lancer les tests pour les voir passer**

Run : `bash scripts/lolkit.sh test --filter "LeagueFollowTests|PublicInitTests|MatchRemindersTests|ReminderSettingsTests|StorageTests|FollowListTests"`
Expected : tout vert (`LeagueFollowTests` : 7 tests ; `PublicInitTests` : 7 tests) ; les suites existantes des notifications, des réglages et des suivis inchangées.

- [ ] **Step 7: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 328 tests in 38 suites passed`, aucun `warning:`.

- [ ] **Step 8: Commit**

```bash
git add LoLKit/Sources/LoLKit/Follow/FollowList.swift LoLKit/Sources/LoLKit/Follow/ScheduleQuery.swift LoLKit/Sources/LoLKit/Reminders/MatchReminders.swift LoLKit/Sources/LoLKit/Storage/AppSettings.swift LoLKit/Tests/LoLKitTests/LeagueFollowTests.swift LoLKit/Tests/LoLKitTests/PublicInitTests.swift
git commit -m "feat(lolkit): suivre une ligue (calendrier, notifications de début de match sans contourner nextLine), réglages onboardingDone et classements révélés, décodage tolérant" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l5-ligues-reglages
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task L6: Classements et tableaux

**Branche :** `nuit2/lolkit-l6-tableaux` — **Vague 2** (worktree depuis `main` après la fusion de la vague 1)

**Files:**
- Create: `LoLKit/Sources/LoLKit/Season/StandingsTable.swift`, `LoLKit/Sources/LoLKit/Season/StandingsMasking.swift`
- Test: `LoLKit/Tests/LoLKitTests/StandingsTableTests.swift`
- Fixture créée : `LoLKit/Tests/LoLKitTests/Fixtures/season/getStandings_worlds25_reduced.json` (Mondial 2025 terminé : play-ins 1 match, suisse 33, phase finale 7). Lues : `getStandings_lec3_reduced.json`, `getStandings_worlds26_reduced.json`.

**Interfaces:**
- Consumes : (L1) `Standings` (`stages`, `allMatches`), `StandingsStage { id, name, slug, sections }`, `StandingsSection { name, matches, rankings }`, `BracketMatch { id, state, teams }`, `Ranking { ordinal, teams }`, `RankedTeam { id, code, name, image, wins, losses }`, `StandingsResponse` (tests) ; (L2) `SeasonFixture.data(_:)` (tests) ; (`HEAD`) `SpoilerPolicy.isMasked`, `FollowList.team(id:)`, `FollowedTeam.spoilerFree`, `MatchTeam.isPlaceholder`.
- Produces :
  - `public enum StandingsTable { struct Row { ordinal; team: RankedTeam; wins; losses }; struct TeamRecord { team: MatchTeam; wins; losses }; struct RecordGroup { wins; losses; teams: [MatchTeam]; var record: String }; struct Round { kind: .quarterFinal | .semiFinal | .final; matches }; enum Content { table([Row]), swiss([RecordGroup]), bracket([Round]), matches([BracketMatch]) }; struct Stage: Identifiable { id, name, slug; content }; static func build(standings: Standings) -> [Stage]; static func swissRecords(_ matches: [BracketMatch]) -> [TeamRecord] }`.
  - `public enum StandingsMasking { static func isMasked(_ standings: Standings, tournamentId: String, follows: FollowList, revealed: Set<String>, revealedStandings: Set<String>) -> Bool }`.

- [ ] **Step 1: Produire la fixture `getStandings_worlds25_reduced.json`**

Source : capture brute du 14/10/2026 (`getStandings?hl=fr-FR&tournamentId=113475452383887518`, 21 032 o).

```bash
RAW=$(mktemp -d)
SRC="/c/Users/Dan/AppData/Local/Temp/claude/C--Users-Dan-Desktop-01-Dev-App-Esport-en-direct/497551d5-ffb1-472a-813a-0380440095c9/scratchpad/raw/standings_worlds25.json"
if [ -f "$SRC" ]; then cp "$SRC" "$RAW/standings.json"; else
  curl -s -H "x-api-key: 0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z" -o "$RAW/standings.json" \
    "https://esports-api.lolesports.com/persisted/gw/getStandings?hl=fr-FR&tournamentId=113475452383887518"
fi
python -I - "$RAW/standings.json" LoLKit/Tests/LoLKitTests/Fixtures/season/getStandings_worlds25_reduced.json <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
stages = json.load(open(src, encoding="utf-8"))["data"]["standings"][0]["stages"]
def team(t):
    return {"id": t["id"], "name": t["name"], "code": t["code"], "result": t.get("result")}
out = []
for s in stages:
    out.append({"id": s["id"], "name": s["name"], "type": s.get("type"), "slug": s["slug"],
                "sections": [{"name": x["name"],
                              "matches": [{"id": m["id"], "state": m["state"], "teams": [team(t) for t in m["teams"]]} for m in x["matches"]],
                              "rankings": x["rankings"]} for x in s["sections"]]})
with open(dst, "wb") as f:
    f.write((json.dumps({"data": {"standings": [{"stages": out}]}}, ensure_ascii=False, indent=1) + "\n").encode("utf-8"))
PY
sha256sum LoLKit/Tests/LoLKitTests/Fixtures/season/getStandings_worlds25_reduced.json
```

Expected : `793641352641586f8ac2c4a9dfa8ef43b7f0c213cc759d06e6bedb5587c94309`, 24 439 octets. Empreinte différente : s'arrêter et le signaler.

- [ ] **Step 2: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/StandingsTableTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Classements et tableaux (spec saison §3.5) sur de vraies réponses `getStandings` : LEC Split 3, Mondial 2025
/// (terminé) et Mondial 2026 (pas commencé) ; masquage anti-spoiler.
@Suite struct StandingsTableTests {
    private static let lec3 = "115548681802226458"
    private static let worlds25 = "113475452383887518"
    private static let worlds26 = "115660540725177488"
    private static let t1 = "98767991853197861"

    private func standings(_ name: String) throws -> Standings {
        try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(name))
            .data.standings.elements[0]
    }

    @Test func leagueTableAndPlayoffs() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_lec3_reduced"))
        #expect(stages.map(\.slug) == ["regular_season", "playoffs"])
        #expect(stages[0].name == "Saison régulière")
        guard case let .table(rows) = stages[0].content else {
            Issue.record("classement attendu")
            return
        }
        #expect(rows.map(\.ordinal) == [1, 2, 3])
        #expect(rows.map(\.team.code) == ["KC", "VIT", "G2"])
        #expect(rows.map(\.wins) == [9, 7, 6])
        #expect(rows.map(\.losses) == [0, 2, 3])
        guard case let .matches(playoffs) = stages[1].content else {
            Issue.record("liste de matchs attendue")
            return
        }
        #expect(playoffs.map(\.id) == ["115548681803406327", "115548681803406333"])
    }

    /// Suisse 2025 recalculé depuis `outcome` : KT et AL 3-0 … FNC et PSG 0-3 (33 matchs).
    @Test func worlds2025Swiss() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_worlds25_reduced"))
        #expect(stages.map(\.slug) == ["play_ins", "swiss", "knockouts"])
        guard case let .swiss(groups) = stages[1].content else {
            Issue.record("système suisse attendu")
            return
        }
        #expect(groups.map(\.record) == ["3-0", "3-1", "3-2", "2-3", "1-3", "0-3"])
        #expect(groups.map { $0.teams.map(\.code) } == [["AL", "KT"], ["G2", "GEN", "HLE"], ["CFO", "T1", "TES"],
                                                       ["BLG", "FLY", "MKOI"], ["100T", "TSW", "VKS"], ["FNC", "PSG"]])
        #expect(groups.flatMap(\.teams).count == 16)
        #expect(groups.flatMap(\.teams).allSatisfy { $0.id != nil && $0.result == nil })
        let records = StandingsTable.swissRecords(try standings("getStandings_worlds25_reduced").stages[1].sections[0].matches)
        #expect(records.first { $0.team.code == "KT" }.map { [$0.wins, $0.losses] } == [3, 0])
    }

    /// Phase finale 2025 : quarts [0-3], demies [4] = vainqueurs de [0] et [1] (T1 contre TES), [5], finale [6].
    @Test func worlds2025Bracket() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_worlds25_reduced"))
        guard case let .bracket(rounds) = stages[2].content else {
            Issue.record("tableau attendu")
            return
        }
        #expect(rounds.map(\.kind) == [.quarterFinal, .semiFinal, .final])
        #expect(rounds.map(\.matches.count) == [4, 2, 1])
        #expect(Set(rounds[1].matches[0].teams.map(\.code)) == ["T1", "TES"])
        #expect(Set(rounds[1].matches[1].teams.map(\.code)) == ["KT", "GEN"])
        #expect(Set(rounds[2].matches[0].teams.map(\.code)) == ["T1", "KT"])
        // Vainqueurs des quarts [0] et [1] = équipes de la demie [4].
        let winners = rounds[0].matches[0...1].compactMap { $0.teams.first { $0.result?.outcome == "win" }?.code }
        #expect(Set(winners) == Set(rounds[1].matches[0].teams.map(\.code)))
        guard case let .matches(playIns) = stages[0].content else {
            Issue.record("liste attendue")
            return
        }
        #expect(playIns.count == 1)
    }

    /// Mondial 2026 avant son début : équipes « TBD » ignorées (aucun bilan), tableau réduit → liste de matchs.
    @Test func worlds2026BeforeItStarts() throws {
        let stages = StandingsTable.build(standings: try standings("getStandings_worlds26_reduced"))
        #expect(stages.map(\.slug) == ["play_ins", "swiss", "knockouts"])
        #expect(stages[1].content == .swiss([]))
        guard case let .matches(knockouts) = stages[2].content else {
            Issue.record("liste attendue (2 matchs seulement)")
            return
        }
        #expect(knockouts.count == 2)
        let records = StandingsTable.swissRecords(try standings("getStandings_worlds26_reduced").stages[0].sections[0].matches)
        #expect(records.map(\.team.code) == ["FUR", "MVK", "C9", "KC"])
        #expect(records.allSatisfy { $0.wins == 0 && $0.losses == 0 })
        #expect(StandingsTable.build(standings: Standings(stages: [StandingsStage(id: "vide", name: "", slug: "x",
                                                                                   sections: [])])).isEmpty)
    }

    /// Masqué si une équipe suivie en anti-spoiler y a un match terminé masqué, ou un bilan que les matchs révélés
    /// ne couvrent pas ; la révélation du classement lève le masque sans révéler de match.
    @Test func maskingFollowsTheSpoilerFreeTeams() throws {
        let lec = try standings("getStandings_lec3_reduced")
        var follows = FollowList(teams: [FollowedTeam(id: "111692118851466302", code: "KC", name: "Karmine Corp")])
        #expect(!StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: [],
                                           revealedStandings: []))
        follows.setSpoilerFree(true, id: "111692118851466302")
        #expect(StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: [],
                                          revealedStandings: []))
        // Révéler son match de play-offs ne suffit pas : son bilan 9-0 résume 9 autres matchs.
        #expect(StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: ["115548681803406327"],
                                          revealedStandings: []))
        #expect(!StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: follows, revealed: [],
                                           revealedStandings: [Self.lec3]))
        // Une autre équipe en anti-spoiler (T1) ne masque pas la LEC ; le Mondial 2026 (rien de joué) n'est jamais masqué.
        let other = FollowList(teams: [FollowedTeam(id: Self.t1, code: "T1", name: "T1", spoilerFree: true)])
        #expect(!StandingsMasking.isMasked(lec, tournamentId: Self.lec3, follows: other, revealed: [], revealedStandings: []))
        #expect(!StandingsMasking.isMasked(try standings("getStandings_worlds26_reduced"), tournamentId: Self.worlds26,
                                           follows: follows, revealed: [], revealedStandings: []))
        // Mondial 2025 : T1 en anti-spoiler masque le tableau ; ses 9 matchs révélés le démasquent.
        let worlds = try standings("getStandings_worlds25_reduced")
        #expect(StandingsMasking.isMasked(worlds, tournamentId: Self.worlds25, follows: other, revealed: [],
                                          revealedStandings: []))
        let t1Matches = Set(worlds.allMatches.filter { $0.teams.contains { $0.id == Self.t1 } }.map(\.id))
        #expect(t1Matches.count == 9)
        #expect(!StandingsMasking.isMasked(worlds, tournamentId: Self.worlds25, follows: other, revealed: t1Matches,
                                           revealedStandings: []))
    }
}
```

- [ ] **Step 3: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter StandingsTableTests`
Expected : échec de compilation (`cannot find 'StandingsTable' in scope`…).

- [ ] **Step 4: Écrire `StandingsTable`**

Créer `LoLKit/Sources/LoLKit/Season/StandingsTable.swift` :

```swift
import Foundation

/// Classements et tableaux prêts à afficher (spec saison §3.5), depuis `getStandings`. Des valeurs, jamais du texte :
/// l'appli formule (« 2-1 », « Quarts de finale »…).
public enum StandingsTable {
    /// Une ligne de classement (`rankings`) ; ex aequo : même `ordinal`.
    public struct Row: Sendable, Equatable {
        public let ordinal: Int
        public let team: RankedTeam

        public init(ordinal: Int, team: RankedTeam) {
            self.ordinal = ordinal
            self.team = team
        }

        public var wins: Int { team.wins }
        public var losses: Int { team.losses }
    }

    /// Bilan d'une équipe dans un système suisse.
    public struct TeamRecord: Sendable, Equatable {
        /// L'équipe (id, nom, code, logo ; sans résultat).
        public let team: MatchTeam
        public let wins: Int
        public let losses: Int

        public init(team: MatchTeam, wins: Int, losses: Int) {
            self.team = team
            self.wins = wins
            self.losses = losses
        }
    }

    /// Équipes de même bilan dans un système suisse.
    public struct RecordGroup: Sendable, Equatable {
        public let wins: Int
        public let losses: Int
        /// Par code d'équipe.
        public let teams: [MatchTeam]

        public init(wins: Int, losses: Int, teams: [MatchTeam]) {
            self.wins = wins
            self.losses = losses
            self.teams = teams
        }

        /// « 2-1 »
        public var record: String { "\(wins)-\(losses)" }
    }

    /// Un tour d'une phase finale.
    public struct Round: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case quarterFinal
            case semiFinal
            case final
        }

        public let kind: Kind
        public let matches: [BracketMatch]

        public init(kind: Kind, matches: [BracketMatch]) {
            self.kind = kind
            self.matches = matches
        }
    }

    public enum Content: Sendable, Equatable {
        /// Classement (`rankings` non vide).
        case table([Row])
        /// Système suisse : bilans recalculés depuis `outcome` des matchs `completed`, meilleurs bilans d'abord.
        case swiss([RecordGroup])
        /// Phase finale à 7 matchs (Mondial) : [0-3] quarts, [4] = vainqueurs de [0] et [1], [5] = de [2] et [3],
        /// [6] finale (ordre vérifié sur 2025).
        case bracket([Round])
        /// Autre tableau (play-offs d'une ligue, play-ins) : les matchs dans l'ordre de l'API.
        case matches([BracketMatch])
    }

    public struct Stage: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let slug: String
        public let content: Content

        public init(id: String, name: String, slug: String, content: Content) {
            self.id = id
            self.name = name
            self.slug = slug
            self.content = content
        }
    }

    /// Une entrée par étape, dans l'ordre de l'API. Choix : `rankings` → `.table` ; slug `swiss` → `.swiss` ; slug
    /// `knockouts` à 7 matchs → `.bracket` ; sinon `.matches`. Une étape sans aucun match ni classement est omise.
    public static func build(standings: Standings) -> [Stage] {
        standings.stages.compactMap { stage in
            let rankings = stage.sections.flatMap(\.rankings)
            let matches = stage.sections.flatMap(\.matches)
            let content: Content
            if !rankings.isEmpty {
                content = .table(rankings.sorted { $0.ordinal < $1.ordinal }
                    .flatMap { ranking in ranking.teams.map { Row(ordinal: ranking.ordinal, team: $0) } })
            } else if matches.isEmpty {
                return nil
            } else if stage.slug == "swiss" {
                content = .swiss(swissGroups(matches))
            } else if stage.slug == "knockouts", matches.count == 7 {
                content = .bracket([Round(kind: .quarterFinal, matches: Array(matches[0..<4])),
                                    Round(kind: .semiFinal, matches: Array(matches[4..<6])),
                                    Round(kind: .final, matches: [matches[6]])])
            } else {
                content = .matches(matches)
            }
            return Stage(id: stage.id, name: stage.name, slug: stage.slug, content: content)
        }
    }

    /// Bilans d'un système suisse : victoires et défaites de chaque équipe connue (hors « TBD ») sur les matchs
    /// `completed` (`outcome` win / loss) ; une équipe sans match joué est à 0-0.
    public static func swissRecords(_ matches: [BracketMatch]) -> [TeamRecord] {
        var order: [String] = []
        var records: [String: (team: MatchTeam, wins: Int, losses: Int)] = [:]
        for match in matches {
            for team in match.teams where !team.isPlaceholder {
                let key = team.id ?? team.code
                if records[key] == nil {
                    order.append(key)
                    records[key] = (MatchTeam(id: team.id, name: team.name, code: team.code, image: team.image,
                                              result: nil), 0, 0)
                }
                guard match.state == .completed else { continue }
                switch team.result?.outcome {
                case "win": records[key]?.wins += 1
                case "loss": records[key]?.losses += 1
                default: break
                }
            }
        }
        return order.compactMap { records[$0] }.map { TeamRecord(team: $0.team, wins: $0.wins, losses: $0.losses) }
    }

    static func swissGroups(_ matches: [BracketMatch]) -> [RecordGroup] {
        let grouped = Dictionary(grouping: swissRecords(matches)) { "\($0.wins)-\($0.losses)" }
        return grouped.values.map { entries in
            RecordGroup(wins: entries[0].wins, losses: entries[0].losses,
                        teams: entries.map(\.team).sorted { $0.code < $1.code })
        }.sorted { $0.wins != $1.wins ? $0.wins > $1.wins : $0.losses < $1.losses }
    }
}
```

- [ ] **Step 5: Écrire `StandingsMasking`**

Créer `LoLKit/Sources/LoLKit/Season/StandingsMasking.swift` :

```swift
/// Anti-spoiler des classements et tableaux (spec saison §3.5) : un classement contient tous les résultats.
public enum StandingsMasking {
    /// Masqué si une équipe suivie en anti-spoiler y figure et qu'un de ses matchs terminés (ou en cours) de ce tournoi
    /// est masqué, sauf révélation explicite du classement (`revealedStandings` = `AppSettings.revealedStandingIds`).
    /// Une équipe classée avec un bilan non nul compte aussi : son bilan résume des matchs que le tableau ne liste pas
    /// forcément, il est masqué tant que tous ses matchs listés et terminés ne sont pas révélés et au moins aussi
    /// nombreux que son bilan. Révéler le classement ne révèle aucun match.
    public static func isMasked(_ standings: Standings, tournamentId: String, follows: FollowList, revealed: Set<String>,
                                revealedStandings: Set<String>) -> Bool {
        guard !revealedStandings.contains(tournamentId) else { return false }
        let played = standings.allMatches.filter { $0.state == .completed || $0.state == .inProgress }
        if played.contains(where: { SpoilerPolicy.isMasked($0.teams, matchId: $0.id, follows: follows, revealed: revealed) }) {
            return true
        }
        for team in standings.stages.flatMap({ $0.sections.flatMap(\.rankings) }).flatMap(\.teams)
        where team.wins + team.losses > 0 {
            guard let followed = follows.team(id: team.id), followed.spoilerFree else { continue }
            let revealedOwn = played.filter { match in
                match.teams.contains { $0.id == team.id } && revealed.contains(match.id)
            }
            if revealedOwn.count < team.wins + team.losses { return true }
        }
        return false
    }
}
```

- [ ] **Step 6: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter StandingsTableTests`
Expected : `5 tests` passés.

- [ ] **Step 7: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 364 tests in 43 suites passed` (sur `main` après la vague 1), aucun `warning:`.

- [ ] **Step 8: Commit**

```bash
git add LoLKit/Sources/LoLKit/Season/StandingsTable.swift LoLKit/Sources/LoLKit/Season/StandingsMasking.swift LoLKit/Tests/LoLKitTests/StandingsTableTests.swift LoLKit/Tests/LoLKitTests/Fixtures/season/getStandings_worlds25_reduced.json
git commit -m "feat(lolkit): classements et tableaux — classement, système suisse recalculé depuis outcome, phase finale du Mondial (quarts, demies, finale), masquage anti-spoiler et révélation du classement" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l6-tableaux
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task L7: Accueil pur — « À ne pas rater » et fil de l'Accueil

**Branche :** `nuit2/lolkit-l7-accueil` — **Vague 3** (worktree depuis `main` après la fusion de la vague 2 : 391 tests)

**Files:**
- Create: `LoLKit/Sources/LoLKit/Home/MustWatch.swift`, `LoLKit/Sources/LoLKit/Home/HomeFeed.swift`
- Test: `LoLKit/Tests/LoLKitTests/MustWatchTests.swift`, `LoLKit/Tests/LoLKitTests/HomeFeedTests.swift`

**Interfaces:**
- Consumes : (L1) `SeasonMatch` (`involves`, `startTime`, `teams`, `id`), `SeasonMatch.resolve(_:in:)` (interne), `Standings.match(id:)`, `Standings.stage(containing:)`, `StandingsStage`, `StandingsSection`, `BracketMatch`, `Ranking`, `RankedTeam`, `StandingsResponse`, `TeamsResponse` (tests) ; (L2) `GameSummary`, `GameResult`, `TeamGameLine`, `PlayerGameLine`, `SeasonFixture` (tests) ; (L3) `SeasonStats.streak(_:matches:masked:)`, `SeasonStats.topPlayers(games:masked:metric:since:minGames:limit:)`, `SeasonMasking.maskedMatchIds(_:follows:revealed:)`, `Streak.Kind`, `PlayerMetric`, `PlayerSeason`, `SeasonFixture.kcMatches()` / `kcGames()` (tests) ; (L5) `FollowList.league(slug:)`, `FollowList.follow(league:)` ; (L6) `StandingsTable.swissRecords(_:) -> [TeamRecord]`, `StandingsMasking.isMasked(_:tournamentId:follows:revealed:revealedStandings:)` ; (L8) `WeekStrip.days(today:events:calendar:followed:before:after:)`, `CalendarMonth.events(on:in:calendar:)`, `CalendarDay`, `DayMarker` ; (`HEAD`) `TeamCards.build`, `Presenter.maskedLatestTeamIds`, `SpoilerPolicy.isMasked`, `League.internationalSlugs`, `MatchEvent`.
- Produces :
  - `public enum MustWatchReason: Sendable, Hashable { followedTeam, followedLeague, international(slug:), elimination, qualification, decider, final, semiFinal, quarterFinal, playoffs, topClash, closeRanks, rematch, derby, bestOf5, bestOf3, live }`, `MustWatchScore { reason; points }`, `MustWatchPick: Identifiable { event: MatchEvent; points; reasons; var explanation: [MustWatchReason] }`.
  - `public enum MustWatch { static func rank(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>, revealedStandings: Set<String>, standings: [String: Standings], seasonMatches: [SeasonMatch], catalog: [Team], now: Date, calendar: Calendar, limit: Int) -> [MustWatchPick] }` (+ `round(blockName:)` interne).
  - `public enum ActivityKind { justFinished(matchId:), streak(teamId:kind:count:), killRecord(gameId:teamId:kills:), bigGame(gameId:playerId:kills:), fastGame(gameId:seconds:), longGame(gameId:seconds:), comeback15(gameId:teamId:deficit:) }`, `ActivityItem { kind; date }`.
  - `public enum HomeFeed { struct Input; struct Sections { mustWatch, live, week, todayCount, recentResults, activity }; enum Period { week, season }; static func build(_:) -> Sections; static func followedMatchIds(_:follows:) -> Set<String>; static func live(_:follows:) -> [MatchEvent]; static func recentResults(schedule:follows:now:) -> [MatchEvent]; static func activity(matches:games:schedule:follows:revealed:masked:now:) -> [ActivityItem]; static func topPlayers(games:masked:metric:period:now:) -> [PlayerSeason] }`.

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `LoLKit/Tests/LoLKitTests/MustWatchTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// « À ne pas rater » (spec saison §3.6) : candidats, barème, exclusions anti-spoiler, raisons tirées des résultats
/// neutralisées quand le tableau est masqué.
@Suite struct MustWatchTests {
    private static let worlds26 = "115660540725177488"
    private static let c9kc = "115660588583171786"
    private static let furMvk = "115660588583040710"
    private static let kcLast = "115548681803406327"

    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    private func catalog() throws -> [Team] {
        try JSONDecoder.lolesports().decode(TeamsResponse.self, from: Fixture.data("getTeams")).data.teams.elements
    }

    private func worlds() throws -> Standings {
        try JSONDecoder.lolesports().decode(StandingsResponse.self, from: SeasonFixture.data(
            "getStandings_worlds26_reduced")).data.standings.elements[0]
    }

    private func kcFollow(spoilerFree: Bool = false) throws -> FollowList {
        var follows = FollowList()
        follows.follow(try catalogTeam("KC"))
        if spoilerFree { follows.setSpoilerFree(true, id: SeasonFixture.kc) }
        return follows
    }

    private func rank(_ schedule: [MatchEvent], follows: FollowList, revealed: Set<String> = [],
                      revealedStandings: Set<String> = [], standings: [String: Standings],
                      seasonMatches: [SeasonMatch] = [], now: Date, limit: Int = 5) throws -> [MustWatchPick] {
        MustWatch.rank(schedule: schedule, follows: follows, revealed: revealed, revealedStandings: revealedStandings,
                       standings: standings, seasonMatches: seasonMatches, catalog: try catalog(), now: now,
                       calendar: paris, limit: limit)
    }

    /// 15/10 à midi : C9 – KC (20:00 à Paris) seul aujourd'hui → on ajoute les prochaines 24 h (FUR – MVK à 01:00) ;
    /// TBD contre TBD exclu. KC suivie : 50 + Mondial 20 + Bo5 10 = 80.
    @Test func worldsDayWithAFollowedTeam() async throws {
        let picks = try rank(try await schedule(), follows: try kcFollow(), standings: [Self.worlds26: try worlds()],
                             now: date("2026-10-15T12:00:00Z"))
        #expect(picks.map(\.event.id) == [Self.c9kc, Self.furMvk])
        #expect(picks.map(\.points) == [80, 30])
        #expect(picks[0].reasons == [MustWatchScore(reason: .followedTeam, points: 50),
                                     MustWatchScore(reason: .international(slug: "worlds"), points: 20),
                                     MustWatchScore(reason: .bestOf5, points: 10)])
        #expect(picks[0].explanation == [.followedTeam, .international(slug: "worlds")])
        // Une ligue suivie ajoute 25 à chacun de ses matchs.
        var withLeague = try kcFollow()
        withLeague.follow(league: League(id: "98767975604431411", slug: "worlds", name: "Mondial", region: nil,
                                         image: nil, priority: 1))
        let leaguePicks = try rank(try await schedule(), follows: withLeague, standings: [:],
                                   now: date("2026-10-15T12:00:00Z"))
        #expect(leaguePicks.map(\.points) == [105, 55])
        #expect(try rank(try await schedule(), follows: try kcFollow(), standings: [:],
                         now: date("2026-10-15T12:00:00Z"), limit: 1).count == 1)
    }

    /// KC en anti-spoiler, dernier match (KC – MKOI) masqué : son prochain match n'est proposé nulle part (F1) ;
    /// révéler ce dernier match le rend.
    @Test func maskedLatestTeamsAreExcluded() async throws {
        let events = try await schedule()
        let now = date("2026-10-15T12:00:00Z")
        let masked = try rank(events, follows: try kcFollow(spoilerFree: true), standings: [:], now: now)
        #expect(masked.map(\.event.id) == [Self.furMvk])
        let revealed = try rank(events, follows: try kcFollow(spoilerFree: true), revealed: [Self.kcLast],
                                standings: [:], now: now)
        #expect(revealed.map(\.event.id) == [Self.c9kc, Self.furMvk])
    }

    // MARK: - Système suisse

    private func team(_ id: String, _ outcome: String? = nil, _ wins: Int = 0) -> MatchTeam {
        MatchTeam(id: id, name: id, code: id, image: nil,
                  result: outcome.map { MatchTeam.Result(outcome: $0, gameWins: wins) })
    }

    private func event(_ id: String, _ a: String, _ b: String, start: String, league: String = "worlds",
                       bestOf: Int = 3, block: String? = nil, state: EventState = .unstarted) -> MatchEvent {
        MatchEvent(startTime: date(start), state: state, type: "match", blockName: block,
                   league: LeagueRef(id: nil, slug: league, name: league, image: nil),
                   match: MatchInfo(id: id, teams: [team(a), team(b)], strategy: Strategy(type: "bestOf", count: bestOf),
                                    games: nil),
                   streams: nil)
    }

    /// Bilans : A 2-0, B 0-2, C 1-1, D 1-1.
    private var swiss: Standings {
        let done: [BracketMatch] = [
            BracketMatch(id: "m1", state: .completed, teams: [team("A", "win", 2), team("C", "loss", 1)]),
            BracketMatch(id: "m2", state: .completed, teams: [team("A", "win", 2), team("D", "loss", 0)]),
            BracketMatch(id: "m3", state: .completed, teams: [team("C", "win", 2), team("B", "loss", 0)]),
            BracketMatch(id: "m4", state: .completed, teams: [team("D", "win", 2), team("B", "loss", 1)]),
        ]
        let next = [("a-b", "A", "B"), ("b-c", "B", "C"), ("c-d", "C", "D")].map {
            BracketMatch(id: $0.0, state: .unstarted, teams: [team($0.1), team($0.2)])
        }
        return Standings(stages: [StandingsStage(id: "s", name: "Système suisse", slug: "swiss",
                                                 sections: [StandingsSection(name: "Suisse", matches: done + next,
                                                                             rankings: [])])])
    }

    private var swissDay: [MatchEvent] {
        [event("c-d", "C", "D", start: "2026-10-20T10:00:00Z"), event("b-c", "B", "C", start: "2026-10-20T12:00:00Z"),
         event("a-b", "A", "B", start: "2026-10-20T14:00:00Z")]
    }

    /// A (2-0) contre B (0-2) : « Tout se joue » 40 ; B contre C : élimination 30 ; C contre D (1-1) : rien.
    @Test func swissStakes() throws {
        let picks = try rank(swissDay, follows: FollowList(), standings: ["w": swiss], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["a-b", "b-c", "c-d"])
        #expect(picks.map(\.points) == [65, 55, 25])
        #expect(picks[0].explanation == [.decider, .international(slug: "worlds")])
        #expect(picks[1].reasons.first == MustWatchScore(reason: .elimination, points: 30))
    }

    /// Tableau masqué (A suivie en anti-spoiler, ses matchs joués masqués) : plus aucune raison tirée des résultats,
    /// pour tous les matchs du tournoi ; révéler le classement les rend.
    @Test func maskedTableNeutralizesResultReasons() throws {
        let follows = FollowList(teams: [FollowedTeam(id: "A", code: "A", name: "A", spoilerFree: true)])
        let picks = try rank(swissDay, follows: follows, standings: ["w": swiss], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["a-b", "c-d", "b-c"])
        #expect(picks.map(\.points) == [75, 25, 25])
        #expect(!picks.flatMap(\.reasons).contains { [.decider, .elimination, .qualification].contains($0.reason) })
        let revealed = try rank(swissDay, follows: follows, revealedStandings: ["w"], standings: ["w": swiss],
                                now: date("2026-10-20T08:00:00Z"))
        #expect(revealed.map(\.points) == [115, 55, 25])
    }

    /// Phase finale à 7 matchs : [6] finale 40, [4-5] demies 30, [0-3] quarts 20 ; sinon d'après le nom du bloc.
    @Test func knockoutRounds() throws {
        let ids = (0..<7).map { "k\($0)" }
        let matches = ids.enumerated().map { index, id in
            BracketMatch(id: id, state: .unstarted, teams: [team("T\(index)a"), team("T\(index)b")])
        }
        let standings = Standings(stages: [StandingsStage(id: "k", name: "Phase finale", slug: "knockouts",
                                                          sections: [StandingsSection(name: "", matches: matches,
                                                                                      rankings: [])])])
        let day = [event("k1", "T1a", "T1b", start: "2026-10-20T10:00:00Z", bestOf: 5),
                   event("k4", "T4a", "T4b", start: "2026-10-20T12:00:00Z", bestOf: 5),
                   event("k6", "T6a", "T6b", start: "2026-10-20T14:00:00Z", bestOf: 5)]
        let picks = try rank(day, follows: FollowList(), standings: ["w": standings], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["k6", "k4", "k1"])
        #expect(picks[0].reasons.map(\.reason) == [.final, .international(slug: "worlds"), .bestOf5])
        #expect(picks[1].reasons.map(\.reason) == [.semiFinal, .international(slug: "worlds"), .bestOf5])
        // À égalité de points, l'ordre de déclaration : international avant le tour.
        #expect(picks[2].reasons.map(\.reason) == [.international(slug: "worlds"), .quarterFinal, .bestOf5])
        #expect(picks.map(\.points) == [70, 60, 50])
        #expect(MustWatch.round(blockName: "Finale")?.reason == .final)
        #expect(MustWatch.round(blockName: "Demi-finales")?.reason == .semiFinal)
        #expect(MustWatch.round(blockName: "Quarts de finale")?.reason == .quarterFinal)
        #expect(MustWatch.round(blockName: "Play-offs")?.reason == .playoffs)
        #expect(MustWatch.round(blockName: "Semaine 2") == nil)
        #expect(MustWatch.round(blockName: nil) == nil)
    }

    /// LEC : KC (1re) contre VIT (2e) = choc du haut de tableau 15 + duel serré 10 + revanche 10 (déjà joué cette
    /// saison) ; KC en anti-spoiler → tableau masqué → ces trois raisons tombent.
    @Test func tableAndRematch() throws {
        let kc = SeasonFixture.kc
        let vit = "99322214695067838"
        func ranked(_ id: String, _ code: String, _ ordinal: Int) -> Ranking {
            Ranking(ordinal: ordinal, teams: [RankedTeam(id: id, code: code, name: code, image: nil, wins: 9 - ordinal,
                                                         losses: ordinal)])
        }
        let lec = Standings(stages: [StandingsStage(
            id: "r", name: "Saison régulière", slug: "regular_season",
            sections: [StandingsSection(
                name: "", matches: [BracketMatch(id: "kc-vit", state: .unstarted,
                                                 teams: [team(kc), team(vit)]),
                                    BracketMatch(id: "g2-fnc", state: .unstarted,
                                                 teams: [team(SeasonFixture.g2), team("fnc")])],
                rankings: [ranked(kc, "KC", 1), ranked(vit, "VIT", 2), ranked(SeasonFixture.g2, "G2", 3),
                           ranked("fnc", "FNC", 7)])])])
        let day = [event("g2-fnc", SeasonFixture.g2, "fnc", start: "2026-10-20T10:00:00Z", league: "lec",
                         block: "Semaine 9"),
                   event("kc-vit", kc, vit, start: "2026-10-20T12:00:00Z", league: "lec", block: "Semaine 9")]
        let seasonMatches = try SeasonFixture.kcMatches()
        let plain = try rank(day, follows: FollowList(), standings: [SeasonFixture.lecSplit3: lec],
                             seasonMatches: seasonMatches, now: date("2026-10-20T08:00:00Z"))
        #expect(plain.map(\.event.id) == ["kc-vit", "g2-fnc"])
        #expect(plain[0].reasons.map(\.reason) == [.topClash, .closeRanks, .rematch, .bestOf3])
        #expect(plain.map(\.points) == [40, 5])
        let masked = try rank(day, follows: FollowList(teams: [FollowedTeam(id: kc, code: "KC", name: "Karmine Corp",
                                                                            spoilerFree: true)]),
                              standings: [SeasonFixture.lecSplit3: lec], seasonMatches: seasonMatches,
                              now: date("2026-10-20T08:00:00Z"))
        #expect(masked[0].reasons.map(\.reason) == [.followedTeam, .bestOf3])
    }

    /// Un match en cours compte (+15) même commencé la veille ; un match au-delà de 24 h n'est pas proposé.
    @Test func candidatesAndLive() throws {
        let day = [event("live", "X", "Y", start: "2026-10-19T21:30:00Z", state: .inProgress),
                   event("later", "Z", "W", start: "2026-10-22T10:00:00Z")]
        let picks = try rank(day, follows: FollowList(), standings: [:], now: date("2026-10-20T08:00:00Z"))
        #expect(picks.map(\.event.id) == ["live"])
        #expect(picks[0].reasons.map(\.reason) == [.international(slug: "worlds"), .live, .bestOf3])
    }
}
```

Créer `LoLKit/Tests/LoLKitTests/HomeFeedTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Onglet Accueil, logique pure (spec saison §2) : activité récente sur la vraie saison de KC, direct, résultats,
/// bandeau, joueurs en forme ; rien d'un match masqué.
@Suite struct HomeFeedTests {
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }

    private var kcFollow: FollowList {
        FollowList(teams: [FollowedTeam(id: SeasonFixture.kc, code: "KC", name: "Karmine Corp")])
    }

    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    private func activity(now: String, follows: FollowList? = nil, schedule: [MatchEvent] = [],
                          revealed: Set<String> = [], masked: Set<String>? = nil) throws -> [ActivityItem] {
        let follows = follows ?? kcFollow
        let matches = try SeasonFixture.kcMatches()
        return HomeFeed.activity(
            matches: matches, games: try SeasonFixture.kcGames(), schedule: schedule, follows: follows,
            revealed: revealed,
            masked: masked ?? SeasonMasking.maskedMatchIds(matches, follows: follows, revealed: revealed),
            now: date(now))
    }

    /// 28/07 : record de kills (KC 27, G2 – KC game 3 du 26/07) et 3 victoires d'affilée.
    @Test func killRecordAndStreak() throws {
        let items = try activity(now: "2026-07-28T12:00:00Z")
        #expect(items.map(\.kind) == [
            .killRecord(gameId: "115548681803406290", teamId: SeasonFixture.kc, kills: 27),
            .streak(teamId: SeasonFixture.kc, kind: .wins, count: 3),
        ])
        #expect(items[0].date == date("2026-07-26T20:19:09.910Z"))
    }

    /// 05/08 : la game de 48:42 contre TH (> 45 min) et 5 victoires d'affilée ; le record du 26/07 a plus de 7 jours.
    @Test func longGameAndLongerStreak() throws {
        let items = try activity(now: "2026-08-05T12:00:00Z")
        #expect(items.map(\.kind) == [
            .longGame(gameId: "115548681803406141", seconds: 2922),
            .streak(teamId: SeasonFixture.kc, kind: .wins, count: 5),
        ])
    }

    /// Match G2 – KC du 26/07 masqué : ni son record, ni la série (le match le plus récent est masqué).
    @Test func maskedMatchesProduceNothing() throws {
        let items = try activity(now: "2026-07-28T12:00:00Z", masked: ["115548681803406287"])
        #expect(items.map(\.kind) == [.killRecord(gameId: "115548681803406272", teamId: SeasonFixture.kc, kills: 24)])
        var spoilerFree = kcFollow
        spoilerFree.setSpoilerFree(true, id: SeasonFixture.kc)
        #expect(try activity(now: "2026-07-28T12:00:00Z", follows: spoilerFree).isEmpty)
    }

    /// 06/09 à 20:00 : KC 1-3 G2 fini à 18:31 (fin de sa dernière game) → « vient de finir » ; masqué → rien,
    /// révélé → de nouveau.
    @Test func justFinished() async throws {
        let events = try await schedule()
        let items = try activity(now: "2026-09-06T20:00:00Z", schedule: events)
        #expect(items.map(\.kind) == [.justFinished(matchId: SeasonFixture.match303)])
        #expect(items.first?.date == date("2026-09-06T18:31:34.815Z"))
        #expect(try activity(now: "2026-09-07T01:00:00Z", schedule: events).isEmpty)
        var spoilerFree = kcFollow
        spoilerFree.setSpoilerFree(true, id: SeasonFixture.kc)
        #expect(try activity(now: "2026-09-06T20:00:00Z", follows: spoilerFree, schedule: events).isEmpty)
        // Révélé : le match revient (et ses games aussi : record de kills de G2 dans la game 304, les autres masquées).
        #expect(try activity(now: "2026-09-06T20:00:00Z", follows: spoilerFree, schedule: events,
                             revealed: [SeasonFixture.match303]).map(\.kind)
                == [.justFinished(matchId: SeasonFixture.match303),
                    .killRecord(gameId: SeasonFixture.game304, teamId: SeasonFixture.g2, kills: 23)])
        // Ni équipe ni ligue suivie : rien.
        #expect(try activity(now: "2026-09-06T20:00:00Z", follows: FollowList(), schedule: events).isEmpty)
    }

    /// Game de 23:20 gagnée par l'équipe menée de 6 623 gold à 15 min, avec un joueur à 12 kills.
    @Test func comebackBigGameAndFastGame() throws {
        let reference = try SeasonFixture.summary304()
        let star = PlayerGameLine(playerId: "star", name: "KC Star", role: "mid", champion: "Ahri", level: 16, kills: 12,
                                  deaths: 1, assists: 4, creepScore: 200, gold: 12_000)
        let game = GameSummary(
            gameId: "g", matchId: "m", tournamentId: "t", leagueSlug: "lec", number: 1, patch: nil,
            startedAt: date("2026-10-10T15:00:00Z"), endedAt: date("2026-10-10T15:23:20Z"), durationSeconds: 1400,
            result: GameResult(winnerTeamId: SeasonFixture.kc, basis: .exact),
            blue: TeamGameLine(teamId: SeasonFixture.kc, kills: 30, gold: 60_000, towers: 9, inhibitors: 2, barons: 1,
                               dragons: [], gold15: 20_000, players: [star]),
            red: TeamGameLine(teamId: SeasonFixture.g2, kills: 10, gold: 50_000, towers: 3, inhibitors: 0, barons: 0,
                              dragons: [], gold15: reference.red.gold15, players: []),
            enriched: true)
        let items = HomeFeed.activity(matches: [], games: ["g": game], schedule: [], follows: FollowList(), revealed: [],
                                      masked: [], now: date("2026-10-10T16:00:00Z"))
        #expect(items.map(\.kind) == [
            .killRecord(gameId: "g", teamId: SeasonFixture.kc, kills: 30),
            .bigGame(gameId: "g", playerId: "star", kills: 12),
            .fastGame(gameId: "g", seconds: 1400),
            .comeback15(gameId: "g", teamId: SeasonFixture.kc, deficit: 6_623),
        ])
        // Vainqueur seulement déduit : pas de « comeback ».
        var inferred = game
        inferred.result = GameResult(winnerTeamId: SeasonFixture.kc, basis: .inferred)
        #expect(!HomeFeed.activity(matches: [], games: ["g": inferred], schedule: [], follows: FollowList(),
                                   revealed: [], masked: [], now: date("2026-10-10T16:00:00Z"))
            .contains { if case .comeback15 = $0.kind { true } else { false } })
        // Au plus 6 éléments.
        let many = (0..<8).map { index in
            GameSummary(gameId: "f\(index)", matchId: "m\(index)", tournamentId: "t", leagueSlug: "lec", number: 1,
                        patch: nil, startedAt: game.startedAt, endedAt: game.endedAt.addingTimeInterval(Double(index)),
                        durationSeconds: 1400, result: .unknown, blue: game.blue, red: game.red, enriched: false)
        }
        #expect(HomeFeed.activity(matches: [], games: Dictionary(uniqueKeysWithValues: many.map { ($0.gameId, $0) }),
                                  schedule: [], follows: FollowList(), revealed: [], masked: [],
                                  now: date("2026-10-10T16:00:00Z")).count == HomeFeed.activityLimit)
    }

    @Test func liveOrderFollowedTeamsThenLeaguesThenInternationals() {
        let other = makeEvent(id: "other", state: .inProgress, start: "2026-10-15T10:00:00Z",
                              teams: [makeTeam("A"), makeTeam("B")])
        let lck = MatchEvent(startTime: date("2026-10-15T09:00:00Z"), state: .inProgress, type: "match", blockName: nil,
                             league: LeagueRef(id: "lck", slug: "lck", name: "LCK", image: nil),
                             match: MatchInfo(id: "lck", teams: [makeTeam("T1"), makeTeam("GEN")], strategy: nil,
                                              games: nil),
                             streams: nil)
        let kc = makeEvent(id: "kc", state: .inProgress, start: "2026-10-15T11:00:00Z",
                           teams: [makeTeam("KC", id: SeasonFixture.kc), makeTeam("C9")])
        var follows = kcFollow
        follows.follow(league: League(id: "lck", slug: "lck", name: "LCK", region: nil, image: nil, priority: nil))
        #expect(HomeFeed.live([other, lck, kc], follows: follows).map(\.id) == ["kc", "lck", "other"])
        #expect(HomeFeed.followedMatchIds([other, lck, kc], follows: follows) == ["kc", "lck"])
    }

    /// Résultats des 72 dernières heures, suivis d'abord, 8 au plus.
    @Test func recentResults() {
        let now = date("2026-10-15T20:00:00Z")
        let old = makeEvent(id: "old", state: .completed, start: "2026-10-12T19:00:00Z", teams: [makeTeam("A"), makeTeam("B")])
        let recent = makeEvent(id: "recent", state: .completed, start: "2026-10-15T15:00:00Z",
                               teams: [makeTeam("A"), makeTeam("B")])
        let kc = makeEvent(id: "kc", state: .completed, start: "2026-10-13T21:00:00Z",
                           teams: [makeTeam("KC", id: SeasonFixture.kc), makeTeam("C9")])
        let upcoming = makeEvent(id: "next", state: .unstarted, start: "2026-10-16T15:00:00Z",
                                 teams: [makeTeam("A"), makeTeam("B")])
        #expect(HomeFeed.recentResults(schedule: [old, recent, kc, upcoming], follows: kcFollow, now: now).map(\.id)
                == ["kc", "recent"])
        let many = (0..<10).map {
            makeEvent(id: "r\($0)", state: .completed, start: "2026-10-15T1\($0):00:00Z", teams: [makeTeam("A"), makeTeam("B")])
        }
        #expect(HomeFeed.recentResults(schedule: many, follows: FollowList(), now: now).count == 8)
    }

    /// Joueurs en forme : semaine (2 games) ou saison (5 games).
    @Test func topPlayersByPeriod() throws {
        let game = try SeasonFixture.summary304()
        let games = [game.gameId: game]
        #expect(HomeFeed.topPlayers(games: games, masked: [], metric: .kda, period: .week,
                                    now: date("2026-09-08T00:00:00Z")).isEmpty)
        #expect(HomeFeed.topPlayers(games: games, masked: [], metric: .kda, period: .season,
                                    now: date("2026-09-08T00:00:00Z")).isEmpty)
        var second = try SeasonFixture.summary304()
        second = GameSummary(gameId: "copie", matchId: "m2", tournamentId: second.tournamentId, leagueSlug: "lec",
                             number: 2, patch: nil, startedAt: date("2026-09-07T15:00:00Z"),
                             endedAt: date("2026-09-07T15:33:51Z"), durationSeconds: 2031, result: .unknown,
                             blue: second.blue, red: second.red, enriched: true)
        let week = HomeFeed.topPlayers(games: [game.gameId: game, "copie": second], masked: [], metric: .kda,
                                       period: .week, now: date("2026-09-08T00:00:00Z"))
        #expect(week.count == 5)
        #expect(week.first?.name == "G2 Labrov")
        #expect(week.first?.games == 2)
    }

    /// Accueil complet sur le calendrier réel, le 15/10 à midi : « À ne pas rater » C9 – KC, bandeau, 1 match
    /// aujourd'hui (FUR – MVK tombe le 16 à Paris), pas de direct, pas de résultat récent.
    @Test func buildTheHome() async throws {
        let events = try await schedule()
        var follows = FollowList()
        follows.follow(try catalogTeam("KC"))
        let sections = HomeFeed.build(HomeFeed.Input(
            now: date("2026-10-15T12:00:00Z"), calendar: paris, schedule: events, live: [], follows: follows,
            revealed: [], revealedStandings: [], seasonMatches: try SeasonFixture.kcMatches(),
            games: try SeasonFixture.kcGames(), standings: [:], catalog: []))
        #expect(sections.mustWatch.first?.event.id == "115660588583171786")
        #expect(sections.mustWatch.count == 2)
        #expect(sections.live.isEmpty)
        #expect(sections.week.map(\.dayNumber) == [14, 15, 16, 17, 18, 19, 20])
        #expect(sections.week[1].marker == .followed)
        #expect(sections.todayCount == 1)
        #expect(sections.recentResults.isEmpty)
        // Rien de récent dans la saison de KC au 15/10 (dernier match le 19/09, série de 2 défaites).
        #expect(sections.activity.isEmpty)
    }
}
```

- [ ] **Step 2: Lancer les tests pour les voir échouer**

Run : `bash scripts/lolkit.sh test --filter "MustWatchTests|HomeFeedTests"`
Expected : échec de compilation (`cannot find 'MustWatch' in scope`…).

- [ ] **Step 3: Écrire `MustWatch`**

Créer `LoLKit/Sources/LoLKit/Home/MustWatch.swift` :

```swift
import Foundation

/// Une raison de regarder un match (spec saison §3.6). Une valeur : l'appli formule (« Tes équipes », « Élimination en
/// jeu »…) et l'explique dans « Comment c'est calculé ».
public enum MustWatchReason: Sendable, Equatable, Hashable {
    /// « Tes équipes » : +50 par équipe suivie (100 au plus).
    case followedTeam
    /// « Ta ligue » : +25.
    case followedLeague
    /// « Mondial », « MSI », « First Stand » (slug de la ligue) : +20.
    case international(slug: String)
    /// Suisse : une équipe à 2 défaites, +30.
    case elimination
    /// Suisse : une équipe à 2 victoires, +30.
    case qualification
    /// Suisse : les deux à la fois (« Tout se joue »), +40 au lieu de 60.
    case decider
    /// Phase finale : +40 / +30 / +20 ; play-offs d'une ligue : +20.
    case final
    case semiFinal
    case quarterFinal
    case playoffs
    /// « Choc du haut de tableau » : les deux équipes dans le top 3 du classement, +15.
    case topClash
    /// « Duel serré » : écart de rang ≤ 1, +10.
    case closeRanks
    /// « Revanche » : déjà affrontées cette saison (dernier match non masqué), +10.
    case rematch
    /// « Derby » : même ligue d'attache, à un international, +10.
    case derby
    /// Bo5 +10, Bo3 +5.
    case bestOf5
    case bestOf3
    /// « En direct » : +15.
    case live
}

/// Une raison et ses points.
public struct MustWatchScore: Sendable, Equatable {
    public let reason: MustWatchReason
    public let points: Int

    public init(reason: MustWatchReason, points: Int) {
        self.reason = reason
        self.points = points
    }
}

/// Un match proposé, ses points et ses raisons (les plus fortes d'abord).
public struct MustWatchPick: Sendable, Equatable, Identifiable {
    public let event: MatchEvent
    public let points: Int
    public let reasons: [MustWatchScore]

    public init(event: MatchEvent, points: Int, reasons: [MustWatchScore]) {
        self.event = event
        self.points = points
        self.reasons = reasons
    }

    public var id: String { event.id }

    /// Ligne d'explication : les 2 raisons qui rapportent le plus (« Tes équipes · Élimination en jeu »).
    public var explanation: [MustWatchReason] { reasons.prefix(2).map(\.reason) }
}

/// « À ne pas rater » (spec saison §3.6) : les matchs du jour classés par enjeu, score transparent en points entiers.
public enum MustWatch {
    /// Matchs proposés, par points décroissants puis heure de début.
    /// - Candidats : matchs en cours, et matchs à venir commençant aujourd'hui (jour local de `calendar`) ; moins de 3
    ///   → on ajoute ceux des prochaines 24 h. Exclus : un match d'une équipe suivie en anti-spoiler dont le dernier
    ///   match est masqué (règles F1 / C généralisées, `Presenter.maskedLatestTeamIds`), et « TBD contre TBD ».
    /// - Anti-spoiler : les raisons tirées de résultats (suisse, classement, revanche) valent 0 pour tous les matchs
    ///   d'un tournoi dont le tableau est masqué (`StandingsMasking`) : l'ordre ne trahit rien.
    /// - Parameters:
    ///   - standings: classements des tournois en cours, par id de tournoi (un match y est retrouvé par son id).
    ///   - seasonMatches: matchs joués de la saison (revanche).
    ///   - catalog: catalogue `getTeams` (ids d'équipe et ligues d'attache quand le classement ne les donne pas).
    public static func rank(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>,
                            revealedStandings: Set<String>, standings: [String: Standings], seasonMatches: [SeasonMatch],
                            catalog: [Team], now: Date, calendar: Calendar, limit: Int) -> [MustWatchPick] {
        let cards = TeamCards.build(follows: follows, schedule: schedule, live: nil, revealed: revealed)
        let maskedLatest = Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: revealed)
        let eligible = schedule.filter { event in
            guard event.state == .unstarted || event.state == .inProgress else { return false }
            if event.match.teams.allSatisfy(\.isPlaceholder) { return false }
            return !follows.followed(in: event.match.teams).contains { maskedLatest.contains($0.id) }
        }
        var candidates = eligible.filter { $0.state == .inProgress || calendar.isDate($0.startTime, inSameDayAs: now) }
        if candidates.count < 3 {
            let horizon = now.addingTimeInterval(24 * 3600)
            candidates += eligible.filter { event in
                event.state == .unstarted && event.startTime > now && event.startTime <= horizon
                    && !candidates.contains { $0.id == event.id }
            }
        }
        let maskedTables = Set(standings.filter { tournamentId, table in
            StandingsMasking.isMasked(table, tournamentId: tournamentId, follows: follows, revealed: revealed,
                                      revealedStandings: revealedStandings)
        }.keys)
        let picks = candidates.map { event in
            let reasons = score(event, follows: follows, revealed: revealed, standings: standings,
                                maskedTables: maskedTables, seasonMatches: seasonMatches, catalog: catalog)
            return MustWatchPick(event: event, points: reasons.reduce(0) { $0 + $1.points }, reasons: reasons)
        }
        return Array(picks.sorted { a, b in
            if a.points != b.points { return a.points > b.points }
            if a.event.startTime != b.event.startTime { return a.event.startTime < b.event.startTime }
            return a.event.id < b.event.id
        }.prefix(limit))
    }

    /// Raisons d'un match, les plus fortes d'abord (ordre de déclaration à égalité).
    static func score(_ event: MatchEvent, follows: FollowList, revealed: Set<String>, standings: [String: Standings],
                      maskedTables: Set<String>, seasonMatches: [SeasonMatch], catalog: [Team]) -> [MustWatchScore] {
        var reasons: [MustWatchScore] = []
        let followedCount = min(2, follows.followed(in: event.match.teams).count)
        if followedCount > 0 { reasons.append(MustWatchScore(reason: .followedTeam, points: 50 * followedCount)) }
        if follows.league(slug: event.league.slug) != nil {
            reasons.append(MustWatchScore(reason: .followedLeague, points: 25))
        }
        let international = League.internationalSlugs.contains(event.league.slug)
        if international {
            reasons.append(MustWatchScore(reason: .international(slug: event.league.slug), points: 20))
        }
        let found = standings.first { $0.value.match(id: event.id) != nil }
        let bracket = found?.value.match(id: event.id)
        // Ids d'équipe : ceux du tableau s'il les connaît, sinon le catalogue (nom, logo).
        let bracketIds = bracket?.teams.filter { !$0.isPlaceholder }.compactMap(\.id) ?? []
        let teamIds = bracketIds.count == 2
            ? bracketIds
            : event.match.teams.map { SeasonMatch.resolve($0, in: catalog) }.compactMap(\.id)
        let resultsAllowed = found.map { !maskedTables.contains($0.key) } ?? true
        if let found, let stage = found.value.stage(containing: event.id) {
            let stageMatches = stage.sections.flatMap(\.matches)
            if stage.slug == "swiss", resultsAllowed {
                let records = StandingsTable.swissRecords(stageMatches).filter { record in
                    record.team.id.map { teamIds.contains($0) } ?? false
                }
                let eliminating = records.contains { $0.losses == 2 }
                let qualifying = records.contains { $0.wins == 2 }
                switch (eliminating, qualifying) {
                case (true, true): reasons.append(MustWatchScore(reason: .decider, points: 40))
                case (true, false): reasons.append(MustWatchScore(reason: .elimination, points: 30))
                case (false, true): reasons.append(MustWatchScore(reason: .qualification, points: 30))
                case (false, false): break
                }
            }
            if stage.slug == "knockouts", stageMatches.count == 7, let index = stageMatches.firstIndex(where: { $0.id == event.id }) {
                switch index {
                case 6: reasons.append(MustWatchScore(reason: .final, points: 40))
                case 4, 5: reasons.append(MustWatchScore(reason: .semiFinal, points: 30))
                default: reasons.append(MustWatchScore(reason: .quarterFinal, points: 20))
                }
            } else if let round = round(blockName: event.blockName) {
                reasons.append(round)
            }
            let ranks = found.value.stages.flatMap { $0.sections.flatMap(\.rankings) }
            if resultsAllowed, teamIds.count == 2,
               let first = ranks.first(where: { $0.teams.contains { $0.id == teamIds[0] } })?.ordinal,
               let second = ranks.first(where: { $0.teams.contains { $0.id == teamIds[1] } })?.ordinal {
                if first <= 3 && second <= 3 { reasons.append(MustWatchScore(reason: .topClash, points: 15)) }
                if abs(first - second) <= 1 { reasons.append(MustWatchScore(reason: .closeRanks, points: 10)) }
            }
        } else if let round = round(blockName: event.blockName) {
            reasons.append(round)
        }
        if resultsAllowed, teamIds.count == 2,
           let last = seasonMatches.filter({ $0.involves(teamIds[0]) && $0.involves(teamIds[1]) && $0.id != event.id })
               .max(by: { $0.startTime < $1.startTime }),
           !SpoilerPolicy.isMasked(last.teams, matchId: last.id, follows: follows, revealed: revealed) {
            reasons.append(MustWatchScore(reason: .rematch, points: 10))
        }
        if international, teamIds.count == 2 {
            let homes = teamIds.map { id in catalog.first { $0.id == id }?.homeLeague?.name }
            if let home = homes[0], home == homes[1] { reasons.append(MustWatchScore(reason: .derby, points: 10)) }
        }
        if event.bestOf == 5 { reasons.append(MustWatchScore(reason: .bestOf5, points: 10)) }
        if event.bestOf == 3 { reasons.append(MustWatchScore(reason: .bestOf3, points: 5)) }
        if event.state == .inProgress { reasons.append(MustWatchScore(reason: .live, points: 15)) }
        return reasons.enumerated().sorted { a, b in
            a.element.points != b.element.points ? a.element.points > b.element.points : a.offset < b.offset
        }.map(\.element)
    }

    /// Tour d'après le nom du bloc (« Finale », « Demi-finales », « Quarts de finale », « Play-offs »).
    static func round(blockName: String?) -> MustWatchScore? {
        guard let name = blockName?.lowercased() else { return nil }
        if name.contains("demi") || name.contains("semi") { return MustWatchScore(reason: .semiFinal, points: 30) }
        if name.contains("quart") || name.contains("quarter") { return MustWatchScore(reason: .quarterFinal, points: 20) }
        if name.contains("finale") || name == "final" || name == "finals" { return MustWatchScore(reason: .final, points: 40) }
        if name.contains("play-off") || name.contains("playoff") { return MustWatchScore(reason: .playoffs, points: 20) }
        return nil
    }
}
```

- [ ] **Step 4: Écrire `HomeFeed`**

Créer `LoLKit/Sources/LoLKit/Home/HomeFeed.swift` :

```swift
import Foundation

/// Un élément de « Activité récente » (spec saison §2.4) : ce que les données disent vraiment, sans texte.
public enum ActivityKind: Sendable, Equatable {
    /// Match terminé il y a ≤ 6 h, d'une équipe ou ligue suivie, non masqué.
    case justFinished(matchId: String)
    /// Série en cours ≥ 3 d'une équipe suivie (séries de matchs non masqués).
    case streak(teamId: String, kind: Streak.Kind, count: Int)
    /// Plus grand total de kills d'une équipe dans les games données, si la game date de ≤ 7 jours.
    case killRecord(gameId: String, teamId: String, kills: Int)
    /// Un joueur à 10 kills ou plus dans une game de ≤ 7 jours.
    case bigGame(gameId: String, playerId: String, kills: Int)
    /// Game de moins de 25 min / de plus de 45 min, de ≤ 7 jours.
    case fastGame(gameId: String, seconds: Int)
    case longGame(gameId: String, seconds: Int)
    /// Équipe menée d'au moins 2 500 gold à 15 min (palier B) et gagnante (vainqueur exact seulement).
    case comeback15(gameId: String, teamId: String, deficit: Int)
}

public struct ActivityItem: Sendable, Equatable {
    public let kind: ActivityKind
    /// Fin de la game ou du match, début du dernier match d'une série : sert au tri (le plus récent d'abord).
    public let date: Date

    public init(kind: ActivityKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// Logique pure de l'onglet Accueil (spec saison §2) : l'appli la calcule hors du fil principal, la mémoïse et
/// l'affiche. Anti-spoiler : chaque ligne de match passe encore par `Presenter.scoreLine` côté appli ; ici, les
/// matchs masqués ne produisent ni activité ni joueurs en forme.
public enum HomeFeed {
    /// Ce que l'Accueil lit (tout vient du cache : aucune requête).
    public struct Input: Sendable {
        public let now: Date
        public let calendar: Calendar
        public let schedule: [MatchEvent]
        /// Réponse de `getLive`, nil si inconnue (repli : les matchs `inProgress` du calendrier).
        public let live: [MatchEvent]?
        public let follows: FollowList
        public let revealed: Set<String>
        public let revealedStandings: Set<String>
        public let seasonMatches: [SeasonMatch]
        public let games: [String: GameSummary]
        /// Classements des tournois en cours, par id de tournoi.
        public let standings: [String: Standings]
        public let catalog: [Team]

        public init(now: Date, calendar: Calendar, schedule: [MatchEvent], live: [MatchEvent]?, follows: FollowList,
                    revealed: Set<String>, revealedStandings: Set<String>, seasonMatches: [SeasonMatch],
                    games: [String: GameSummary], standings: [String: Standings], catalog: [Team]) {
            self.now = now
            self.calendar = calendar
            self.schedule = schedule
            self.live = live
            self.follows = follows
            self.revealed = revealed
            self.revealedStandings = revealedStandings
            self.seasonMatches = seasonMatches
            self.games = games
            self.standings = standings
            self.catalog = catalog
        }
    }

    /// Sections de l'Accueil (§2.2), dans l'ordre. Une section vide est absente côté appli.
    public struct Sections: Sendable, Equatable {
        /// 1 en grand + 2 lignes.
        public let mustWatch: [MustWatchPick]
        public let live: [MatchEvent]
        /// Bandeau : la veille, aujourd'hui, les 5 jours suivants.
        public let week: [CalendarDay]
        /// Matchs d'aujourd'hui (sous-titre « 3 matchs aujourd'hui »).
        public let todayCount: Int
        public let recentResults: [MatchEvent]
        public let activity: [ActivityItem]

        public init(mustWatch: [MustWatchPick], live: [MatchEvent], week: [CalendarDay], todayCount: Int,
                    recentResults: [MatchEvent], activity: [ActivityItem]) {
            self.mustWatch = mustWatch
            self.live = live
            self.week = week
            self.todayCount = todayCount
            self.recentResults = recentResults
            self.activity = activity
        }
    }

    /// Période des « Joueurs en forme ».
    public enum Period: Sendable, Equatable {
        /// 7 derniers jours, 2 games au moins.
        case week
        /// Toutes les games données, 5 games au moins.
        case season
    }

    public static let mustWatchCount = 3
    public static let recentResultsWindow: TimeInterval = 72 * 3600
    public static let recentResultsLimit = 8
    public static let activityLimit = 6
    public static let topPlayersLimit = 5

    public static func build(_ input: Input) -> Sections {
        let masked = SeasonMasking.maskedMatchIds(input.seasonMatches, follows: input.follows, revealed: input.revealed)
        let followed = followedMatchIds(input.schedule, follows: input.follows)
        return Sections(
            mustWatch: MustWatch.rank(schedule: input.schedule, follows: input.follows, revealed: input.revealed,
                                      revealedStandings: input.revealedStandings, standings: input.standings,
                                      seasonMatches: input.seasonMatches, catalog: input.catalog, now: input.now,
                                      calendar: input.calendar, limit: mustWatchCount),
            live: live(input.live ?? input.schedule.filter { $0.state == .inProgress }, follows: input.follows),
            week: WeekStrip.days(today: input.now, events: input.schedule, calendar: input.calendar, followed: followed),
            todayCount: CalendarMonth.events(on: input.now, in: input.schedule, calendar: input.calendar).count,
            recentResults: recentResults(schedule: input.schedule, follows: input.follows, now: input.now),
            activity: activity(matches: input.seasonMatches, games: input.games, schedule: input.schedule,
                               follows: input.follows, revealed: input.revealed, masked: masked, now: input.now))
    }

    /// Matchs d'une équipe ou d'une ligue suivie (pastilles pleines du calendrier).
    public static func followedMatchIds(_ events: [MatchEvent], follows: FollowList) -> Set<String> {
        Set(events.filter { isFollowed($0, follows) }.map(\.id))
    }

    /// En direct : équipes suivies d'abord, puis ligues suivies, puis internationaux, puis le reste ; par heure de début.
    public static func live(_ events: [MatchEvent], follows: FollowList) -> [MatchEvent] {
        func rank(_ event: MatchEvent) -> Int {
            if follows.involves(event.match.teams) { return 0 }
            if follows.league(slug: event.league.slug) != nil { return 1 }
            if League.internationalSlugs.contains(event.league.slug) { return 2 }
            return 3
        }
        return events.sorted { (rank($0), $0.startTime, $0.id) < (rank($1), $1.startTime, $1.id) }
    }

    /// Résultats des 72 dernières heures, suivis d'abord, puis du plus récent ; 8 au plus. Le score reste à
    /// `Presenter.scoreLine` (masqué → « Terminé · toucher pour révéler »).
    public static func recentResults(schedule: [MatchEvent], follows: FollowList, now: Date) -> [MatchEvent] {
        let recent = schedule.filter {
            $0.state == .completed && $0.startTime <= now && now.timeIntervalSince($0.startTime) <= recentResultsWindow
        }
        return Array(recent.sorted { a, b in
            let (x, y) = (isFollowed(a, follows), isFollowed(b, follows))
            if x != y { return x }
            return (a.startTime, a.id) > (b.startTime, b.id)
        }.prefix(recentResultsLimit))
    }

    /// Activité récente (§2.4), la plus récente d'abord, `activityLimit` au plus. Rien d'un match masqué : `masked`
    /// (`SeasonMasking.maskedMatchIds`) pour les games et les séries, `SpoilerPolicy` pour les matchs du calendrier.
    public static func activity(matches: [SeasonMatch], games: [String: GameSummary], schedule: [MatchEvent],
                                follows: FollowList, revealed: Set<String>, masked: Set<String>,
                                now: Date) -> [ActivityItem] {
        let week: TimeInterval = 7 * 86_400
        var items: [ActivityItem] = []
        let visibleGames = games.values.filter { !masked.contains($0.matchId) && $0.endedAt <= now }
        // Matchs qui viennent de finir : fin = fin de leur dernière game en cache, sinon leur début.
        for event in schedule where event.state == .completed && isFollowed(event, follows)
            && !masked.contains(event.id)
            && !SpoilerPolicy.isMasked(event.match.teams, matchId: event.id, follows: follows, revealed: revealed) {
            let end = visibleGames.filter { $0.matchId == event.id }.map(\.endedAt).max() ?? event.startTime
            guard end <= now, now.timeIntervalSince(end) <= 6 * 3600 else { continue }
            items.append(ActivityItem(kind: .justFinished(matchId: event.id), date: end))
        }
        // Séries en cours des équipes suivies.
        let played = matches.filter { $0.startTime <= now }
        for team in follows.teams {
            guard let streak = SeasonStats.streak(team.id, matches: played, masked: masked), streak.count >= 3,
                  let last = played.filter({ $0.involves(team.id) }).map(\.startTime).max() else { continue }
            items.append(ActivityItem(kind: .streak(teamId: team.id, kind: streak.kind, count: streak.count), date: last))
        }
        // Record de kills d'une équipe (sur toutes les games visibles), s'il date de ≤ 7 jours.
        let lines = visibleGames.flatMap { game in [game.blue, game.red].map { (game: game, line: $0) } }
        if let record = lines.max(by: { ($0.line.kills, $0.game.endedAt) < ($1.line.kills, $1.game.endedAt) }),
           now.timeIntervalSince(record.game.endedAt) <= week {
            items.append(ActivityItem(kind: .killRecord(gameId: record.game.gameId, teamId: record.line.teamId,
                                                        kills: record.line.kills), date: record.game.endedAt))
        }
        for game in visibleGames where now.timeIntervalSince(game.endedAt) <= week {
            for line in [game.blue, game.red] {
                for player in line.players where player.kills >= 10 {
                    items.append(ActivityItem(kind: .bigGame(gameId: game.gameId, playerId: player.playerId,
                                                             kills: player.kills), date: game.endedAt))
                }
            }
            if game.durationSeconds < 25 * 60 {
                items.append(ActivityItem(kind: .fastGame(gameId: game.gameId, seconds: game.durationSeconds),
                                          date: game.endedAt))
            } else if game.durationSeconds > 45 * 60 {
                items.append(ActivityItem(kind: .longGame(gameId: game.gameId, seconds: game.durationSeconds),
                                          date: game.endedAt))
            }
            if game.result.basis == .exact, let winner = game.result.winnerTeamId,
               let own = game.line(teamId: winner)?.gold15, let other = game.opponentLine(of: winner)?.gold15,
               other - own >= 2_500 {
                items.append(ActivityItem(kind: .comeback15(gameId: game.gameId, teamId: winner, deficit: other - own),
                                          date: game.endedAt))
            }
        }
        return Array(items.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset
        }.map(\.element).prefix(activityLimit))
    }

    /// Joueurs en forme (§2.2 n° 6) : semaine (7 jours, 2 games au moins) ou saison (5 games au moins), 5 au plus.
    public static func topPlayers(games: [String: GameSummary], masked: Set<String>, metric: PlayerMetric,
                                  period: Period, now: Date) -> [PlayerSeason] {
        let since: Date? = period == .week ? now.addingTimeInterval(-7 * 86_400) : nil
        return SeasonStats.topPlayers(games: Array(games.values), masked: masked, metric: metric, since: since,
                                      minGames: period == .week ? 2 : 5, limit: topPlayersLimit)
    }

    static func isFollowed(_ event: MatchEvent, _ follows: FollowList) -> Bool {
        follows.involves(event.match.teams) || follows.league(slug: event.league.slug) != nil
    }
}
```

- [ ] **Step 5: Lancer les tests pour les voir passer**

Run : `bash scripts/lolkit.sh test --filter "MustWatchTests|HomeFeedTests"`
Expected : `16 tests` passés (7 + 9).

- [ ] **Step 6: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 407 tests in 48 suites passed` (sur `main` après la vague 2), aucun `warning:`.

- [ ] **Step 7: Commit**

```bash
git add LoLKit/Sources/LoLKit/Home/MustWatch.swift LoLKit/Sources/LoLKit/Home/HomeFeed.swift LoLKit/Tests/LoLKitTests/MustWatchTests.swift LoLKit/Tests/LoLKitTests/HomeFeedTests.swift
git commit -m "feat(lolkit): Accueil pur — « À ne pas rater » (barème transparent, F1/C, raisons tirées des résultats neutralisées si le tableau est masqué), direct, bandeau, résultats récents, activité récente, joueurs en forme" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l7-accueil
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task L8: Calendrier pur — vue mois et bandeau

**Branche :** `nuit2/lolkit-l8-calendrier` — **Vague 1**

**Files:**
- Create: `LoLKit/Sources/LoLKit/Calendar/CalendarMonth.swift`, `LoLKit/Sources/LoLKit/Calendar/WeekStrip.swift`
- Test: `LoLKit/Tests/LoLKitTests/CalendarTests.swift` (fixture `getSchedule.json` déjà au dépôt)

**Interfaces:**
- Consumes (à `HEAD`) : `MatchEvent { id; startTime; league.slug }`, `League.internationalSlugs` ; tests : `FakeTransport`, `LoLClient.schedule(leagueIds:)`, `makeEvent(id:state:start:teams:…)`, `date(_:)`.
- Produces :
  - `public enum DayMarker: Sendable, Equatable { none, followed, international }`.
  - `public struct CalendarDay: Sendable, Equatable, Identifiable { date: Date; dayNumber: Int; isInMonth, isToday: Bool; marker: DayMarker; matchIds: [String] }`.
  - `public enum SchedulePageDirection { older, newer }`.
  - `public enum CalendarMonth { static func days(events: [MatchEvent], month: Date, calendar: Calendar, followed: Set<String>, now: Date) -> [CalendarDay]; static func events(on day: Date, in events: [MatchEvent], calendar: Calendar) -> [MatchEvent]; static func pageNeeded(for month: Date, events: [MatchEvent], calendar: Calendar) -> SchedulePageDirection? }` (+ `group`, `day` internes).
  - `public enum WeekStrip { static let daysBefore = 1, daysAfter = 5, scrollWeeks = 3; static func days(today:events:calendar:followed:before:after:) -> [CalendarDay]; static func scrollRange(today:events:calendar:followed:) -> [CalendarDay] }`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/CalendarTests.swift` :

```swift
import Foundation
import Testing
@testable import LoLKit

/// Calendrier pur (spec saison §2.2 n° 3, §3.2) : vue mois, bandeau de 7 jours, pastilles, page à lire.
@Suite struct CalendarTests {
    /// C9 vs KC, Mondial, 15/10 18:00 UTC (fixture `getSchedule`).
    private static let c9kc = "115660588583171786"
    /// FUR vs MVK, 15/10 23:00 UTC = 16/10 01:00 à Paris.
    private static let furMvk = "115660588583040710"
    private static let tbd = "115660588583171790"
    private static let kcG2 = "115548681803406303"

    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    /// Calendrier de l'appareil en France : lundi en premier, heure de Paris.
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    @Test func monthGridStartsOnTheFirstWeekday() async throws {
        let events = try await schedule()
        let now = date("2026-10-15T10:00:00Z")
        let days = CalendarMonth.days(events: events, month: date("2026-10-10T12:00:00Z"), calendar: paris,
                                      followed: [Self.c9kc], now: now)
        // Octobre 2026 : du lundi 28/09 au dimanche 01/11 (5 semaines).
        #expect(days.count == 35)
        #expect(days.first?.date == date("2026-09-27T22:00:00Z"))
        #expect(days.first?.dayNumber == 28)
        #expect(days.first?.isInMonth == false)
        #expect(days.last?.dayNumber == 1)
        #expect(days.last?.isInMonth == false)
        #expect(days.filter(\.isInMonth).count == 31)
        #expect(days.filter(\.isToday).map(\.dayNumber) == [15])

        let fifteenth = try #require(days.first { $0.isInMonth && $0.dayNumber == 15 })
        #expect(fifteenth.marker == .followed)
        #expect(fifteenth.matchIds == [Self.c9kc])
        // 23:00 UTC le 15 = 01:00 le 16 à Paris : le match passe au 16, avec celui du soir.
        let sixteenth = try #require(days.first { $0.isInMonth && $0.dayNumber == 16 })
        #expect(sixteenth.matchIds == [Self.furMvk, Self.tbd])
        #expect(sixteenth.marker == .international)
        #expect(days.filter { $0.marker != .none }.count == 2)
    }

    @Test func septemberAndAnotherFirstWeekday() async throws {
        let events = try await schedule()
        let now = date("2026-10-15T10:00:00Z")
        let september = CalendarMonth.days(events: events, month: date("2026-09-15T12:00:00Z"), calendar: paris,
                                           followed: [], now: now)
        // Du lundi 31/08 au dimanche 04/10.
        #expect(september.count == 35)
        #expect(september.first?.dayNumber == 31)
        // Une ligue non suivie et non internationale (LEC) : pas de pastille, mais le match est dans la liste du jour.
        let sixth = try #require(september.first { $0.isInMonth && $0.dayNumber == 6 })
        #expect(sixth.marker == .none)
        #expect(sixth.matchIds == [Self.kcG2])
        #expect(CalendarMonth.days(events: events, month: date("2026-09-15T12:00:00Z"), calendar: paris,
                                   followed: [Self.kcG2], now: now)
                    .first { $0.isInMonth && $0.dayNumber == 6 }?.marker == .followed)

        var sunday = paris
        sunday.firstWeekday = 1
        let october = CalendarMonth.days(events: events, month: date("2026-10-10T12:00:00Z"), calendar: sunday,
                                         followed: [], now: now)
        // Du dimanche 27/09 au samedi 31/10.
        #expect(october.count == 35)
        #expect(october.first?.dayNumber == 27)
        #expect(october.last?.dayNumber == 31)
    }

    @Test func eventsOfADayInStartOrder() async throws {
        let events = try await schedule()
        #expect(CalendarMonth.events(on: date("2026-10-16T10:00:00Z"), in: events, calendar: paris).map(\.id)
                == [Self.furMvk, Self.tbd])
        #expect(CalendarMonth.events(on: date("2026-10-17T10:00:00Z"), in: events, calendar: paris).isEmpty)
    }

    /// Mois hors du calendrier en cache (06/09 → 16/10) : page `older` ou `newer` à lire.
    @Test func pageNeededOutsideTheCachedSchedule() async throws {
        let events = try await schedule()
        #expect(CalendarMonth.pageNeeded(for: date("2026-08-15T12:00:00Z"), events: events, calendar: paris) == .older)
        #expect(CalendarMonth.pageNeeded(for: date("2026-09-15T12:00:00Z"), events: events, calendar: paris) == .older)
        #expect(CalendarMonth.pageNeeded(for: date("2026-11-15T12:00:00Z"), events: events, calendar: paris) == .newer)
        #expect(CalendarMonth.pageNeeded(for: date("2026-10-15T12:00:00Z"), events: events, calendar: paris) == .newer)
        let october = events.filter { $0.startTime >= date("2026-10-01T00:00:00Z") }
            + [makeEvent(id: "first", state: .completed, start: "2026-09-30T22:00:00Z", teams: []),
               makeEvent(id: "last", state: .unstarted, start: "2026-10-31T20:00:00Z", teams: [])]
        #expect(CalendarMonth.pageNeeded(for: date("2026-10-15T12:00:00Z"), events: october, calendar: paris) == nil)
        #expect(CalendarMonth.pageNeeded(for: date("2026-10-15T12:00:00Z"), events: [], calendar: paris) == nil)
    }

    /// Bandeau de l'Accueil : la veille, aujourd'hui, les 5 jours suivants ; défilement sur ± 3 semaines.
    @Test func weekStripAroundToday() async throws {
        let events = try await schedule()
        let today = date("2026-10-15T10:00:00Z")
        let strip = WeekStrip.days(today: today, events: events, calendar: paris, followed: [Self.c9kc])
        #expect(strip.map(\.dayNumber) == [14, 15, 16, 17, 18, 19, 20])
        #expect(strip.map(\.isToday) == [false, true, false, false, false, false, false])
        #expect(strip.map(\.marker) == [.none, .followed, .international, .none, .none, .none, .none])
        #expect(strip.allSatisfy { $0.isInMonth })
        let scroll = WeekStrip.scrollRange(today: today, events: events, calendar: paris, followed: [])
        #expect(scroll.count == 43)
        #expect(scroll.first?.date == date("2026-09-23T22:00:00Z"))
        #expect(scroll.filter(\.isToday).count == 1)
    }
}
```

- [ ] **Step 2: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter CalendarTests`
Expected : échec de compilation (`cannot find 'CalendarMonth' in scope`…).

- [ ] **Step 3: Écrire la vue mois**

Créer `LoLKit/Sources/LoLKit/Calendar/CalendarMonth.swift` :

```swift
import Foundation

/// Pastille sous un jour du calendrier (spec saison §2.2 n° 3, §3.2).
public enum DayMarker: Sendable, Equatable {
    /// Aucun match à signaler.
    case none
    /// Au moins un match d'une équipe ou d'une ligue suivie : pastille pleine.
    case followed
    /// Sinon, au moins un match international (Mondial, MSI, First Stand) : anneau.
    case international
}

/// Un jour d'une grille de calendrier.
public struct CalendarDay: Sendable, Equatable, Identifiable {
    /// Début du jour dans le fuseau du calendrier donné.
    public let date: Date
    /// Numéro du jour dans le mois (1-31).
    public let dayNumber: Int
    /// Faux pour les jours du mois précédent ou suivant qui complètent la grille.
    public let isInMonth: Bool
    public let isToday: Bool
    public let marker: DayMarker
    /// Matchs du jour, par heure de début.
    public let matchIds: [String]

    public init(date: Date, dayNumber: Int, isInMonth: Bool, isToday: Bool, marker: DayMarker, matchIds: [String]) {
        self.date = date
        self.dayNumber = dayNumber
        self.isInMonth = isInMonth
        self.isToday = isToday
        self.marker = marker
        self.matchIds = matchIds
    }

    public var id: Date { date }
}

/// Page de `getSchedule` à lire pour afficher un mois hors du calendrier en cache (§3.2).
public enum SchedulePageDirection: Sendable, Equatable {
    case older
    case newer
}

/// Vue mois du calendrier complet (§3.2) : logique pure, l'appli dessine. Jours et heures dans le fuseau et la locale
/// du `Calendar` donné (celui de l'appareil) : semaine commençant à `calendar.firstWeekday` (lundi en France).
public enum CalendarMonth {
    /// Grille du mois qui contient `month` : semaines entières (de `firstWeekday` à la veille), 4 à 6 semaines.
    /// - Parameter followed: ids des matchs d'une équipe ou d'une ligue suivie (pastille pleine).
    /// - Parameter now: pour `isToday`.
    public static func days(events: [MatchEvent], month: Date, calendar: Calendar, followed: Set<String>,
                            now: Date) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = calendar.startOfDay(for: interval.start)
        let lead = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? firstDay
        let trail = (calendar.firstWeekday + 6 - calendar.component(.weekday, from: lastDay) + 7) % 7
        let monthDays = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        guard let start = calendar.date(byAdding: .day, value: -lead, to: firstDay) else { return [] }
        let byDay = group(events, calendar: calendar)
        return (0..<(lead + monthDays + trail)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return day(date, events: byDay[date] ?? [], inMonth: calendar.isDate(date, equalTo: month, toGranularity: .month),
                       calendar: calendar, followed: followed, now: now)
        }
    }

    /// Matchs d'un jour, par heure de début (liste du jour sous la grille et sous le bandeau).
    public static func events(on day: Date, in events: [MatchEvent], calendar: Calendar) -> [MatchEvent] {
        events.filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            .sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
    }

    /// Page à lire pour couvrir le mois de `month` : `.older` s'il commence avant le jour du premier match en cache,
    /// `.newer` s'il finit après le jour du dernier, nil s'il est couvert ou si le cache est vide (rien à paginer).
    /// L'appli ne lit la page que si son jeton existe (`newer` nil = rien de plus récent) et la garde pour la session.
    public static func pageNeeded(for month: Date, events: [MatchEvent], calendar: Calendar) -> SchedulePageDirection? {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let earliest = events.map(\.startTime).min(),
              let latest = events.map(\.startTime).max() else { return nil }
        if interval.start < calendar.startOfDay(for: earliest) { return .older }
        if let dayAfterLatest = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest)),
           interval.end > dayAfterLatest { return .newer }
        return nil
    }

    static func group(_ events: [MatchEvent], calendar: Calendar) -> [Date: [MatchEvent]] {
        Dictionary(grouping: events) { calendar.startOfDay(for: $0.startTime) }
    }

    static func day(_ date: Date, events: [MatchEvent], inMonth: Bool, calendar: Calendar, followed: Set<String>,
                    now: Date) -> CalendarDay {
        let sorted = events.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        let marker: DayMarker
        if sorted.contains(where: { followed.contains($0.id) }) {
            marker = .followed
        } else if sorted.contains(where: { League.internationalSlugs.contains($0.league.slug) }) {
            marker = .international
        } else {
            marker = .none
        }
        return CalendarDay(date: date, dayNumber: calendar.component(.day, from: date), isInMonth: inMonth,
                           isToday: calendar.isDate(date, inSameDayAs: now), marker: marker, matchIds: sorted.map(\.id))
    }
}
```

- [ ] **Step 4: Écrire le bandeau**

Créer `LoLKit/Sources/LoLKit/Calendar/WeekStrip.swift` :

```swift
import Foundation

/// Bandeau de jours de l'Accueil (spec saison §2.2 n° 3) : 7 jours d'aujourd'hui − 1 à aujourd'hui + 5, défilable
/// sur ± 3 semaines dans le calendrier en cache. Mêmes pastilles que la vue mois.
public enum WeekStrip {
    /// Jours visibles par défaut : la veille, aujourd'hui et les 5 jours suivants.
    public static let daysBefore = 1
    public static let daysAfter = 5
    /// Étendue du défilement, en semaines de chaque côté d'aujourd'hui.
    public static let scrollWeeks = 3

    /// Jours de `today − before` à `today + after` (bornes comprises), avec pastilles et matchs du jour.
    /// - Parameter followed: ids des matchs d'une équipe ou d'une ligue suivie (pastille pleine).
    public static func days(today: Date, events: [MatchEvent], calendar: Calendar, followed: Set<String>,
                            before: Int = daysBefore, after: Int = daysAfter) -> [CalendarDay] {
        let start = calendar.startOfDay(for: today)
        let byDay = CalendarMonth.group(events, calendar: calendar)
        return (-before...after).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return CalendarMonth.day(date, events: byDay[date] ?? [], inMonth: true, calendar: calendar,
                                     followed: followed, now: today)
        }
    }

    /// Toute l'étendue défilable : ± `scrollWeeks` semaines autour d'aujourd'hui (43 jours).
    public static func scrollRange(today: Date, events: [MatchEvent], calendar: Calendar,
                                   followed: Set<String>) -> [CalendarDay] {
        days(today: today, events: events, calendar: calendar, followed: followed, before: scrollWeeks * 7,
             after: scrollWeeks * 7)
    }
}
```

- [ ] **Step 5: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter CalendarTests`
Expected : `5 tests` passés.

- [ ] **Step 6: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 325 tests in 38 suites passed`, aucun `warning:`.

- [ ] **Step 7: Commit**

```bash
git add LoLKit/Sources/LoLKit/Calendar/CalendarMonth.swift LoLKit/Sources/LoLKit/Calendar/WeekStrip.swift LoLKit/Tests/LoLKitTests/CalendarTests.swift
git commit -m "feat(lolkit): calendrier pur — grille du mois (premier jour de la semaine de l'appareil), pastilles suivi / international, liste du jour, page older/newer à lire, bandeau de 7 jours et défilement ± 3 semaines" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Pousser la branche et vérifier la CI (une seule attente)**

```bash
git push -u origin nuit2/lolkit-l8-calendrier
SHA=$(git log -1 --format=%H -- LoLKit)
gh run list --workflow LoLKit --commit "$SHA" --limit 1 --json databaseId,status,conclusion
gh run watch --exit-status <databaseId affiché>
```
Expected : jobs `test` et `test-macos` verts.

---

## Self-review

**Couverture de la spec (parties LoLKit) :**

| Exigence | Où |
|---|---|
| §1.1 mesures en assertions : game 304 (durée 2031 s, KC +228 à 15 min, Canna 5 197 gold / 148 CS, 63 457 = Σ gold, CS/min Canna 8,98, gold/min Caliste 531,2, participation 0,545, part des dégâts 0,2278) | L2 `GameSummaryTests`, L3 `SeasonStatsTests.playerSeasonOnTheReferenceGame` |
| §1.1 vainqueur G2 « déduit » ; KC LEC S3 : 21 exactes, 10 déduites, 0 inconnue | L2 `GameWinnersTests.kcLecSplit3` |
| §1.1 index KC : 31 games, séries 10-2, games 22-9, 509 kills, 388 morts, 228 tours, 25 barons, 85 drakes dont 3 elder, gold 68 570, durée 35,16 min | L3 `kcLecSplit3MatchesTheMeasuredAggregates` |
| §1.1 LEC S3 : 137 games jouées pour 175 listées ; KC 9-0, VIT 7-2, G2 6-3 ; Mondial : pas de `rankings`, `id "0"` / `TBD` ; pages `older` / `newer` ; effectif KC (5 joueurs, rôles) | L1 `SeasonAPITests` |
| §1.1 suisse 2025 KT 3-0 … PSG 0-3 ; tableau 2025 [4] = T1 vs TES | L6 `worlds2025Swiss`, `worlds2025Bracket` |
| §1.2 routes par tournoi, saison = année civile, games jouées = Σ gameWins premières, jointure par id de match (repli catalogue, jamais le code seul), fraîcheur 24 h / 30 min / jamais | L1 (`LoLClient+Season`, `CompletedMatch.playedGameIds`, `SeasonMatch.join`), L3 (`SeasonScope.season`), L4 (`seasonTournaments`, `currentTournament`, `maxAge`, `needsRefresh`) |
| §1.3 paliers A/B, frame `finished` exigée, gold à 15 min ± 15 s, part des dégâts et balises du palier B | L2 `GameSummary.make` (+ tests `noSummaryWithoutTheFinishedFrame`, `goldAt15NeedsAFrameWithinFifteenSeconds`) ; la réutilisation d'une relecture en cache (§1.3, « en dernier ») est côté appli (A1) |
| §1.4 vainqueur par game, « estimé » | L2 `GameWinners` ; L3 `ChampionUse.winsEstimated`, `GameRefLine.winEstimated` |
| §1.5 modèle (TournamentRef, CompletedMatch, Standings…, TeamPlayer, Team.players, SeasonMatch, GameSummary versionné, TeamGameLine, PlayerGameLine, SeasonScope, TeamSeason, TeamAverages, PlayerSeason, ChampionUse, SeasonStats, SeasonMasking, PlayerName) et formules (Σ/Σ, KDA sur la somme, morts = kills adverses, meilleure game) | L1, L2, L3 |
| §1.5 remplaçant : le plus de games, sinon le premier listé | L3 `Duel.lineup` (`substituteWithMoreGamesIsChosen`) |
| §1.6 jobs par priorité, jamais pour un match masqué, cadence 2 s, recul, 5 échecs, budget 300, échecs `statsDisabled` / `noData` / `notFinished` / `http` | L4 |
| §1.7 un fichier par game, `Cached<…>` relus à l'identique, `v` plus récent ignoré / plus ancien relu, budget 2 000 games sans jamais supprimer une game d'équipe suivie | L1 (`seasonValuesRoundTripThroughTheDiskCache`), L2 (`decodeStored`, tolérance), L4 (`evictions`, `failuresRoundTrip`) ; écriture disque : appli (A1) |
| §1.8 masqué exclu partout, compté en matchs, pastille neutre, jamais de games d'un match masqué | L3 (`maskedMatchesCountNowhere`), L7 (activité), L4 (aucun job) |
| §2.2 sections de l'Accueil, §2.4 activité (`justFinished`, `streak`, `killRecord`, `bigGame`, `fastGame`/`longGame`, `comeback15` exact seulement) | L7 `HomeFeed` |
| §3.2 vue mois, pastilles, liste du jour, page `older`/`newer` | L8 ; L1 `schedulePage` |
| §3.3 duels poste par poste, barres en miroir, match masqué → stats de saison seulement | L3 `Duel` |
| §3.5 ligues suivies (tolérant), `ScheduleQuery`, `notifyStarts` sous la règle `nextLine`, `revealedStandingIds`, `onboardingDone` ; tableaux (`table` / `swiss` / `bracket`) et masquage | L5 ; L6 |
| §3.6 « À ne pas rater » (candidats, exclusions F1 / C, barème, raisons tirées des résultats à 0 si tableau masqué, explication 2 raisons) | L7 `MustWatch` |
| Décodage tolérant (champ retiré ne fait pas échouer) | L1 (`standingsDecodeTolerantly`, `completedEventsDecodeTolerantly`, `rosterIsOptionalAndTolerant`), L2 (`storedSummariesDecodeTolerantly`), L5 (`followListDecodesTolerantly`, `newSettingsDecodeTolerantly`) |

**Anti-spoiler :** `masked` partout (L3, L4, L7) ; `SeasonMasking` = `SpoilerPolicy.isMasked` sur les équipes avec id ; `StandingsMasking` (L6) et neutralisation dans `MustWatch` (L7) ; exclusion F1 / C dans `MustWatch` par `Presenter.maskedLatestTeamIds` ; `MatchReminders` garde `nextLine` pour les équipes suivies même via une ligue (L5, `followedTeamsKeepTheNextLineRule`) ; aucun nombre de games d'un match masqué (`gamesPending` exclut les masqués, testé).

**Balayage des marqueurs :** aucun « TBD » de plan, « TODO », « à compléter » ni renvoi « comme la tâche N » ; chaque étape de code donne le code entier (fichier complet, ou remplacements exacts d'un fichier existant, ancien texte unique à `HEAD`). « TBD » n'apparaît que comme code d'équipe de l'API.

**Cohérence des types :** `SeasonMatch` (L1) → `SeasonStats`, `SeasonMasking`, `CrawlPlanner`, `MustWatch`, `HomeFeed` ; `GameSummary` / `GameResult` / `TeamGameLine` / `PlayerGameLine` (L2) → `SeasonStats`, `Duel`, `CrawlPlanner.evictions`, `HomeFeed.activity` ; `Standings` & co (L1) → `StandingsTable`, `StandingsMasking`, `CrawlPlanner.currentStageMatchIds`, `MustWatch` ; `Streak`, `PlayerMetric`, `PlayerSeason` (L3) → `HomeFeed` ; `FollowedLeague` / `FollowList.league(slug:)` (L5) → `MustWatch`, `HomeFeed` ; `CalendarDay`, `WeekStrip`, `CalendarMonth.events` (L8) → `HomeFeed.Sections.week`, `todayCount`. Signatures de la spec gardées, sauf trois écarts notés aux décisions : `GameWinners.assign(teams:playedGameIds:summaries:)`, `SeasonStats.team(…, withoutStats:)`, `CalendarMonth.days(…, followed: Set<String>, now:)`.

**Disjonction des fichiers :** vérifiée sur la matrice (un chemin par ligne, un propriétaire par fichier existant : `LoLClient.swift` et `Team.swift` → L1 ; `LiveWindow.swift` → L2 ; `FollowList.swift`, `ScheduleQuery.swift`, `MatchReminders.swift`, `AppSettings.swift`, `PublicInitTests.swift` → L5). Les aides de test partagées sont des fichiers **nouveaux** d'une seule tâche (`Support/SeasonFixture.swift` → L2, `Support/SeasonMatches.swift` → L3), consommés seulement par des vagues ultérieures. Vérifié en compilant : chaque tâche seule sur sa base, chaque vague fusionnée, les huit fusionnées (407 tests, 48 suites, aucun avertissement).
