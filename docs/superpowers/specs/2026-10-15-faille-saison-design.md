# Faille — « compagnon de saison » : conception (socle, Accueil, équipes, joueurs, ligues, classements)

Date : 14-15/10/2026 (nuit n° 2). Statut : **contraignant pour les plans** (brainstorming en autonomie, voir `.superpowers/goal-nuit-2.md`).
Références contraignantes : `2026-10-13-faille-design.md` (§4 données, §8 anti-spoiler, §9 DA), `2026-10-14-faille-finitions-design.md` (Motion, Réduire les animations, PressableStyle, haptique, squelettes), `2026-10-14-faille-fonctionnalites-design.md` (Data Dragon, `details`, sobriété réseau).
Hors de ce document : lot 2 (indicateur de domination, moments forts par frames, MVP, pronos, carte de partage, rattrapage), lot 3, P3/P4.

Chaque décision est notée **Ruling: … — pourquoi — coût si faux**. Les valeurs entre guillemets ou en `code` sont **mesurées** (requêtes réelles du 14/10/2026 vers 21:30-22:00, heure de Paris, au plus une requête toutes les 2,05 s, aucune vers `lol.fandom.com`) et peuvent servir d'assertions.

---

## 0. En une minute

- Les stats de saison viennent de **2 requêtes par game jouée** : `window/{gameId}` sans `startingTime` (première frame → début de la game) et `window/{gameId}?startingTime=<maintenant − 90 s, arrondi aux 10 s>` (le flux renvoie alors les 10 dernières frames, la dernière `finished`). Optionnellement 2 de plus (gold à 15 min, part des dégâts).
- Les games se trouvent par **tournoi** : `getTournamentsForLeague` → `getCompletedEvents?tournamentId=` (ids des games) + `getStandings?tournamentId=` (ids des équipes, résultats, classement). `getSchedule` ne sert qu'au calendrier (pas d'id de game ni d'équipe).
- Chaque game est réduite à un `GameSummary` (~2,2 Ko, versionné), **gardé pour toujours** dans `cache/season/games/<gameId>.json`. Tout le reste (bilans, moyennes, joueurs en forme, duels, « à ne pas rater ») est **calculé à la lecture**, jamais stocké, dans LoLKit.
- L'anti-spoiler s'applique **à la lecture** (un match masqué est exclu de tout calcul et compté « N matchs masqués ») **et à la collecte** (aucune requête pour un match masqué).
- Nouvel onglet **Accueil** en premier ; **Matchs** et **Équipes** restent ; le lien profond des notifications continue d'ouvrir le Détail dans Matchs.

---

## 1. Socle : les statistiques de saison (LoLKit)

### 1.1 Mesures réelles (à recopier telles quelles dans les tests)

Fixtures réduites capturées dans le dossier de travail (pas dans le dépôt) :
`C:\Users\Dan\AppData\Local\Temp\claude\C--Users-Dan-Desktop-01-Dev-App-Esport-en-direct\497551d5-ffb1-472a-813a-0380440095c9\scratchpad\fixtures\`
Les tâches LoLKit les copient dans `LoLKit/Tests/LoLKitTests/Fixtures/season/` (mêmes noms). Si le dossier a disparu, les recapturer avec les URL ci-dessous (même réduction : premières/dernières frames, 2-3 éléments par liste) en respectant 1 requête / 2 s.

| Fichier (fixtures/) | Source | Ce qu'il contient |
|---|---|---|
| `getTournamentsForLeague_lec_reduced.json` | `getTournamentsForLeague?hl=fr-FR&leagueId=98767991302996019` | 4 premiers tournois LEC |
| `getCompletedEvents_lec3_reduced.json` | `getCompletedEvents?hl=fr-FR&tournamentId=115548681802226458` | KC 1-3 G2 (Bo5) + un Bo3 de KC |
| `getStandings_lec3_reduced.json` | `getStandings?hl=fr-FR&tournamentId=115548681802226458` | saison régulière (3 classés, 2 matchs) + play-offs (2 matchs) |
| `getStandings_worlds26_reduced.json` | `getStandings?hl=fr-FR&tournamentId=115660540725177488` | Play-ins, Système suisse, Phase finale (2 matchs chacun) |
| `getTeams_karmine-corp.json` | `getTeams?hl=fr-FR&id=karmine-corp` | KC + 5 joueurs avec rôle |
| `getSchedule_lec_page1_reduced.json` | `getSchedule?…&leagueId=98767991302996019&pageToken=b2xkZXI6OjExNTU0ODY2ODA1OTU4OTMyMA==` | `pages.older`/`pages.newer` + 2 matchs |
| `window_first_115548681803406304.json` | `window/115548681803406304` | 1re frame |
| `window_final_115548681803406304.json` | `window/115548681803406304?startingTime=2026-09-06T23:59:50.000Z` | 2 dernières frames (`finished`) |
| `window_15min_115548681803406304.json` | `…?startingTime=2026-09-06T15:32:20.000Z` | la frame la plus proche de début + 900 s |
| `details_final_115548681803406304.json` | `details/115548681803406304?startingTime=2026-09-06T23:59:50.000Z` | dernière frame de `details` |
| `game_summary_115548681803406304.json` | calculé | `GameSummary` attendu (palier B) |
| `crawl_kc_lec3_tierA_index.json` | 62 requêtes | une ligne par game de KC (LEC Split 3) : ids, début/fin, stats d'équipe finales |

**Endpoints (tous en 200 sauf mention)**

| Requête | Taille | Constats |
|---|---|---|
| `getLeagues` | 12 220 o | 51 ligues ; LEC `98767991302996019`, LCK `98767991310872058`, Mondial `98767975604431411`, MSI `98767991325878492`, First Stand `113464388705111224`, LFL `105266103462388553` |
| `getTournamentsForLeague` LEC / LCK / Mondial / MSI / First Stand | 3 527 / 3 872 / 1 107 / 792 / 244 o | `data.leagues[0].tournaments[] {id, slug, startDate "yyyy-MM-dd", endDate}`, du plus récent au plus ancien. LEC 2026 : `lec_split_1_2026` `115548424304940735` (16/01-01/03), `lec_split_2_2026` `115548668058343983` (27/03-07/06), `lec_split_3_2026` `115548681802226458` (23/07-20/09). `worlds_2026` `115660540725177488` (15/10-15/11), `msi_2026` `115570934354631452`, `first_stand_2026` `115570858980956868`. |
| `getCompletedEvents` LEC Split 3 | 61 277 o | 53 matchs ; `events[] {startTime, blockName, league{name}, match{id, type, teams[{name, code, image, result{gameWins}}], strategy}, games[{id, vods[{parameter}]}]}`. **Pas d'id d'équipe, pas d'état de game.** `games[]` liste aussi les games non jouées : 175 ids pour **137 games jouées**. Règle exacte vérifiée sur les 53 matchs : games jouées = les `Σ gameWins` **premières** de `games[]` (les vods ne sont présentes que sur celles-là). |
| `getCompletedEvents` LEC S1 / S2, LCK S3, Mondial 2025 | 65 879 / 62 496 / 44 169 / 62 947 o | 80 matchs·105 games / 53·141 / 53·154 / 41·84 (suisse 52, quarts 16, demies 7, finale 5, play-ins 4) |
| `getCompletedEvents` Mondial 2026 | 35 o | `{"data":{"schedule":{"events":[]}}}` (rien de joué au 14/10) |
| `getStandings` LEC S3 | 28 963 o | `standings[0].stages[] {id, name, type:null, slug, sections[{name, matches[], rankings[]}]}` ; `regular_season` : 45 matchs, 10 classés (`ordinal`, `teams[{id, slug, name, code, image, record{wins, losses}}]`, 1er KC 9-0, 2e VIT 7-2, 3e G2 6-3) ; `playoffs` : 8 matchs, 0 classé. Match : `{id, state, previousMatchIds, flags, teams[{id, slug, name, code, image, result{outcome, gameWins}}]}` (**ids d'équipe présents**). |
| `getStandings` Mondial 2026 / 2025 | 16 255 / 21 032 o | étapes `play_ins`, `swiss`, `knockouts` ; **jamais de `rankings`**, `previousMatchIds` toujours vide (même 2025 terminé). Phase finale : 7 matchs dans l'ordre du tableau (vérifié 2025 : [0]-[3] quarts, [4] = vainqueurs de [0] et [1], [5] = vainqueurs de [2] et [3], [6] finale). Suisse 2025 : 33 matchs (20 Bo1, 13 Bo3), bilans recalculés depuis `outcome` : KT 3-0, AL 3-0 … FNC 0-3, PSG 0-3. Équipe à venir : `id "0"`, `code "TBD"`, `result null`. |
| `getSchedule` LEC, page 0 / page `older` | 48 567 / 48 657 o | 80 matchs par page ; page 0 : 20/04 → 20/09, `pages {older: "b2xk…MzIw", newer: null}` ; page 1 : 25/01 → 20/04. 5 ligues (LEC, LCK, Mondial, MSI, FS) : 43 646 o, 80 matchs du 21/08 au 03/11 (40 Mondial à venir, 23 LEC, 17 LCK). Pas d'id de game ni d'équipe ; équipes avec `record`. |
| `getTeams?id=karmine-corp` | 1 252 o | `players[] {id, summonerName, firstName, lastName, image, role}` : Canna `103495716771322725` top, Yike `105537190986692036` jungle, kyeahoo `108205130709313212` mid, Caliste `109461265532592848` bottom, Busio `106625308523122120` support |
| `getTeams` (catalogue complet) | 1 550 686 o | 1 586 équipes, 963 avec `players` : **l'effectif est déjà dans le catalogue que l'appli télécharge chaque jour** |
| `getEventDetails` KC-G2 | 8 304 o | contient `tournament {id}` ; game 5 `state "unneeded"` ; pas de vainqueur par game |
| `window/{id}` sans `startingTime` | 16 794 o | 10 frames, 1re `2026-09-06T15:17:23.939Z` |
| `window/{id}?startingTime=` après la fin (même 5 semaines après : `2026-10-14T00:00:00.000Z`) | 18 435 o | 10 dernières frames, dernière `2026-09-06T15:51:14.975Z` `finished` |
| `window/{id}?startingTime=` à début + 900 s | 71 490 o | 42 frames (frames denses en milieu de game) |
| `details/{id}?startingTime=` après la fin | 59 832 o | 10 frames ; joueur : `killParticipation`, `championDamageShare`, `wardsPlaced`, `wardsDestroyed` + stats de combat |
| `window` d'une game `unneeded` | 204, 0 o | → `LoLAPIError.noData` |
| `startingTime` non multiple de 10 s | 400 | `"startingTime must be evenly divisible by 10 seconds"` |

**Game de référence `115548681803406304`** (LEC S3, play-offs, 06/09, KC 1-3 G2, game 1 ; KC bleu `111692118851466302`, G2 rouge `98767991926151025`, patch `16.17.810.4348`) :
- durée `2031.036 s` (33:51) = dernière frame − première frame ;
- dernière frame — bleu : gold 63 457, kills 11, tours 4, inhibs 0, barons 0, drakes `[]` ; rouge : gold 70 918, kills 23, tours 10, inhibs 2, barons 2, drakes `["ocean","mountain","cloud","cloud","elder"]` ;
- joueurs (K/D/A, CS, gold, niveau, part des dégâts) : Canna Jayce 1/3/5 304 12 846 18 0,2278 · Yike Vi 4/6/4 219 13 112 16 0,1329 · kyeahoo Ahri 1/5/7 259 11 056 15 0,2130 · Caliste Caitlyn 4/4/3 362 17 982 17 0,3387 · Busio Bard 1/5/7 38 8 461 12 0,0876 · BrokenBlade KSante 3/2/6 263 13 643 19 0,1219 · SkewMond XinZhao 7/2/6 244 15 461 17 0,1398 · Caps Viktor 7/2/5 299 14 911 18 0,2882 · Hans Sama Ezreal 5/3/11 322 16 221 18 0,3625 · Labrov Karma 1/2/18 37 10 682 15 0,0877 ;
- CS/min Canna = 304 / 33,851 = **8,98** ; gold/min Caliste = **531,2** ; participation aux kills Canna = (1+5)/11 = **0,545** (identique au `killParticipation` de `details` : 0,5454…) ;
- `summonerName` du flux = « KC Canna » (préfixe du code d'équipe) ; `esportsPlayerId` du flux = `id` de `getTeams` ;
- à 15 min (frame `15:32:23.899Z`, soit +899,96 s) : gold bleu 26 851, rouge 26 623 (**KC +228**) ; Canna gold 5 197 / CS 148 ;
- somme des gold joueurs = gold d'équipe (63 457).

**Collecte réelle « KC, LEC Split 3 » (palier A)** : 31 games, **62 requêtes, toutes 200, 1 094 485 octets, 2 min 40 s** à 2,05 s d'écart. Durées : min 26,2 min, médiane 35,1, max 48,7, moyenne 35,16. Agrégats attendus (KC) : séries 10-2, games 22-9, kills 509 (16,42/game), morts 388 (12,52), tours 228 (7,35), barons 25 (0,81), drakes 85 (2,74, dont 3 elder), gold moyen 68 570, côté bleu 21/31.

**Vainqueur d'une game** : l'API ne le donne nulle part (ni `getEventDetails`, ni `getCompletedEvents`, ni `window`). Sur les 31 games : « plus de tours détruites = vainqueur » est cohérent avec les scores de série sur 30 games, 1 égalité (8-8, KC-SK game 2, résolue car 2-0).

### 1.2 Énumérer les matchs et les games

Ruling: **unité de collecte = le tournoi** (`getCompletedEvents` + `getStandings` par `tournamentId`) — pourquoi : ce sont les seules routes qui donnent les ids des games (la première) et les ids d'équipe + résultats (la seconde) en une requête chacune ; `getSchedule` n'a ni l'un ni l'autre et pagine par 80 — coût si faux : une ligue dont `getCompletedEvents` serait vide ou incomplet n'aurait pas de stats (repli possible : `getEventDetails` par match, 1 requête de plus par match).

Ruling: **saison = année civile** : les tournois dont `startDate` est dans l'année en cours (2026), de la ligue d'attache de l'équipe et des compétitions internationales (`worlds`, `msi`, `first_stand`) où l'équipe figure dans `getStandings` — pourquoi : « saison 2026 » est ce que les fans disent, et les splits 1-3 + internationaux couvrent tout — coût si faux : un tournoi à cheval sur deux années compte dans l'année de son début (accepté).

Ruling: **une game jouée = les `Σ gameWins` premières de `games[]`** (règle vérifiée sur 53 + 41 + 53 + 80 + 53 matchs) ; `state "unneeded"` n'existe que dans `getEventDetails` — coût si faux : une game manquante ou de trop dans un match à l'ordre inattendu ; garde-fou : un `window` en 204 sur une game « jouée » la marque `noData` (§1.6).

Ruling: **jointure par id de match** : `SeasonMatch` = l'événement de `getCompletedEvents` + les ids d'équipe et `outcome` du match de même id dans `getStandings` (+ l'étape `stage.slug` qui le contient) ; à défaut (match absent des classements), équipes rapprochées du catalogue par `MatchTeam.isSame` (nom, logo ; jamais le code seul) — coût si faux : un match sans id d'équipe n'est pas rattaché à l'équipe (il manque au bilan, pas de faux chiffre).

Rafraîchissement de l'énumération :
- `getTournamentsForLeague` : 24 h par ligue.
- `getCompletedEvents` / `getStandings` d'un tournoi **actif** (aujourd'hui dans [`startDate`, `endDate` + 2 j]) : au plus toutes les 30 min, et seulement quand la collecte tourne ou qu'un écran qui en dépend est ouvert.
- tournoi **terminé** : lu une fois, **jamais relu**. Ruling — pourquoi : un tournoi fini ne change plus — coût si faux : une correction tardive de Riot n'est jamais vue (vider le cache dans Réglages > À propos la reprend).

`getSchedule` paginé (calendrier seulement, §3.2) : `pageToken` = `pages.older` / `pages.newer` ; 80 matchs par page ; `newer: null` = rien de plus récent.

### 1.3 Lire une game jouée : paliers A et B

| Palier | Requêtes | Taille mesurée | Donne |
|---|---|---|---|
| **A** (obligatoire) | `window(gameId, startingTime: nil)` puis `window(gameId, startingTime: LiveStatsTime.startingTime(now:))` (= `LoLClient.liveWindow` existant, recul compris) | 16,8 + 18,4 Ko ≈ **35,2 Ko** | début, fin, durée, patch, ids équipes/joueurs, rôles, champions, K/D/A, CS, gold, niveau, tours, inhibs, barons, drakes, participation aux kills (calculée) |
| **B** (enrichissement) | `window(gameId, startingTime: floor10(début + 900 s))` puis `details(gameId, now:)` | 71,5 + 59,8 Ko ≈ **131 Ko** | gold et CS à 15 min (équipe et joueurs), part des dégâts, balises posées/détruites |

Ruling: **la frame `finished` est exigée** pour accepter le palier A — pourquoi : « jamais de chiffre inventé », une game sans fin lue n'a pas de stats finales sûres — coût si faux : une game dont le flux s'arrête avant `finished` n'est jamais comptée (comptée « N games sans stats »).

Ruling: **gold à 15 min = la frame de la fenêtre dont l'horodatage est le plus proche de début + 900 s, acceptée si l'écart est ≤ 15 s** (mesuré : 0,04 s) — coût si faux : une valeur à ±15 s, affichée « à 15 min ».

Ruling: **le palier B n'est demandé que pour les games des équipes suivies dans le tournoi en cours et l'international en cours**, après tout le palier A — pourquoi : il coûte 3,7× le palier A en octets — coût si faux : pas de gold@15 ni de part des dégâts pour les ligues suivies et les équipes ouvertes au passage (« — »).

Ruling: **réutiliser une relecture existante** : si `cache/replays/<gameId>.json` (TimelineStore) est complet, son `firstFrame` remplace la 1re requête du palier A et sa frame la plus proche de +900 s celle du palier B (pas de 60 s : accepté si écart ≤ 35 s) — coût si faux : aucun (c'est une économie optionnelle ; l'implémenter en dernier).

### 1.4 Vainqueur par game

`GameWinners.assign(match:summaries:) -> [String: GameResult]` (pur, LoLKit) :
1. Bo1 → vainqueur du match (**exact**).
2. Une équipe a gagné toutes les games de la série (2-0, 3-0) → toutes à elle (**exact**).
3. La dernière game jouée → vainqueur de la série (**exact**).
4. Reste : il faut attribuer `w` games à l'équipe A parmi les `n` restantes ; marge = tours(A) − tours(B) à la frame finale ; on donne à A les `w` games de plus grande marge. **Déduit** si l'attribution est unique (pas d'égalité de marge à la frontière) et si toutes les marges retenues valent au moins 3 tours en valeur absolue ; sinon **inconnu**.

`GameResult { winnerTeamId: String?, basis: .exact | .inferred | .unknown }`. Sur KC LEC S3 : 21 games exactes, 10 déduites, 0 inconnue ; toutes cohérentes avec les séries.

Ruling: **un vainqueur déduit s'affiche avec l'étiquette « estimé »** (listes de games, meilleure game, taux de victoire par champion) ; les bilans « games V-D » viennent toujours des `gameWins` de série (exacts) — pourquoi : règle « une estimation est étiquetée » — coût si faux : 10 games sur 31 portent une étiquette discrète.

### 1.5 Modèle de données (LoLKit, dossier `Sources/LoLKit/Season/`)

```swift
// Énumération (API)
public struct TournamentRef: Codable, Sendable, Equatable, Identifiable {
    public let id, slug: String; public let startDate, endDate: String   // "yyyy-MM-dd"
    public var leagueId: String                                             // rempli par le client
    public func isActive(today: String) -> Bool                             // today ∈ [start, end + 2 j]
}
public struct CompletedMatch: Codable, Sendable, Equatable {               // un événement de getCompletedEvents
    public let matchId: String; public let startTime: Date; public let blockName: String?
    public let bestOf: Int; public let teams: [MatchTeam]                   // sans id
    public let gameIds: [String]                                            // TOUTES les games listées
    public var playedGameIds: [String] { Array(gameIds.prefix(teams.reduce(0) { $0 + $1.gameWins })) }
}
public struct Standings: Codable, Sendable, Equatable { public let stages: [StandingsStage] }
public struct StandingsStage: Codable, Sendable, Equatable { public let id, name, slug: String; public let sections: [StandingsSection] }
public struct StandingsSection: Codable, Sendable, Equatable { public let name: String; public let matches: [BracketMatch]; public let rankings: [Ranking] }
public struct BracketMatch: Codable, Sendable, Equatable { public let id: String; public let state: EventState; public let teams: [MatchTeam] }  // avec id ; "0"/TBD = placeholder
public struct Ranking: Codable, Sendable, Equatable { public let ordinal: Int; public let teams: [RankedTeam] }
public struct RankedTeam: Codable, Sendable, Equatable { public let id, code, name: String; public let image: String?; public let wins, losses: Int }
public struct TeamPlayer: Codable, Sendable, Equatable, Identifiable { public let id, summonerName: String; public let image: String?; public let role: String? }
// Team gagne `public let players: [TeamPlayer]?` (décodage tolérant ; absent → nil).

public struct SeasonMatch: Codable, Sendable, Equatable, Identifiable {     // jointure §1.2
    public let id: String; public let tournamentId: String; public let leagueSlug: String
    public let stageSlug: String?; public let startTime: Date; public let blockName: String?
    public let bestOf: Int; public let teams: [MatchTeam]                   // avec id si connu → SpoilerPolicy direct
    public let playedGameIds: [String]
    public static func join(completed: [CompletedMatch], standings: Standings?, tournamentId: String,
                            leagueSlug: String, catalog: [Team]) -> [SeasonMatch]
}

// Une game jouée, réduite (~2,2 Ko palier A, ~3,2 Ko palier B, JSON compact mesuré)
public struct GameSummary: Codable, Sendable, Equatable, Identifiable {
    public static let schemaVersion = 1
    public let v: Int                    // version du schéma (sync serveur future : même JSON)
    public let gameId, matchId, tournamentId, leagueSlug: String
    public let number: Int               // n° de la game dans la série
    public let patch: String?            // "16.17.810.4348"
    public let startedAt, endedAt: Date  // 1re frame, frame finished
    public var durationSeconds: Int      // endedAt − startedAt, arrondi
    public var result: GameResult        // §1.4, recalculé quand la série est complète
    public let blue, red: TeamGameLine
    public let enriched: Bool            // palier B lu
    public var id: String { gameId }
    public func line(teamId: String) -> TeamGameLine?
    public static func make(first: LiveWindow, final: LiveWindow, at15: LiveWindow?, details: GameDetails?,
                            matchId: String, number: Int, tournamentId: String, leagueSlug: String) -> GameSummary?  // nil si pas `finished`
}
public struct TeamGameLine: Codable, Sendable, Equatable {
    public let teamId: String; public let kills, gold, towers, inhibitors, barons: Int
    public let dragons: [String]; public let gold15: Int?; public let players: [PlayerGameLine]   // ordre du flux (top→support)
}
public struct PlayerGameLine: Codable, Sendable, Equatable {
    public let playerId: String          // esportsPlayerId
    public let name: String              // summonerName brut du flux ("KC Canna")
    public let role, champion: String    // "top"… / championId Data Dragon
    public let level, kills, deaths, assists, creepScore, gold: Int
    public let damageShare: Double?; public let wardsPlaced, wardsDestroyed: Int?   // palier B
    public let gold15, creepScore15: Int?                                            // palier B
}
```

« ~60 valeurs utiles » = les 10 joueurs × 6 valeurs (K, D, A, CS, gold, champion), plus ~20 valeurs d'équipe et d'identité ; jamais le JSON brut.

Agrégats (jamais stockés, calculés à la lecture) :

```swift
public struct SeasonScope: Sendable, Hashable { public let tournamentIds: Set<String>; public let label: String }
public struct TeamSeason: Sendable, Equatable {
    public let teamId: String; public let scope: SeasonScope
    public let seriesWins, seriesLosses, gameWins, gameLosses: Int          // depuis gameWins de série (exact)
    public let streak: Streak?                                               // séries, du plus récent ; ≥ 2 pour s'afficher
    public let form: [FormPip]                                               // 5 derniers matchs : .win/.loss/.masked
    public let gamesCounted, gamesPending, gamesWithoutStats, maskedMatches: Int
    public let averages: TeamAverages?                                       // nil si gamesCounted == 0
    public let dragonTypes: [String: Int]; public let champions: [ChampionUse]   // top 8, par nombre de games
}
public struct TeamAverages: Sendable, Equatable {
    public let kills, deaths, gold, towers, dragons, barons, inhibitors: Double
    public let durationSeconds: Double; public let gold15Diff: Double?; public let gold15Games: Int
}
public struct PlayerSeason: Sendable, Equatable {
    public let playerId, name, role: String; public let teamId: String       // équipe de la game la plus récente
    public let games, kills, deaths, assists: Int
    public var kda: Double { Double(kills + assists) / Double(max(1, deaths)) }
    public let csPerMin, goldPerMin, killParticipation: Double               // moyennes pondérées par la durée / par game
    public let damageShare: Double?; public let damageShareGames: Int
    public let champions: [ChampionUse]; public let bestGame: GameRefLine?; public let recent: [GameRefLine]  // 5
}
public struct ChampionUse: Sendable, Equatable { public let champion: String; public let games: Int; public let wins: Int; public let winsEstimated: Bool }
public enum SeasonStats {
    public static func team(_ teamId: String, matches: [SeasonMatch], games: [String: GameSummary], scope: SeasonScope,
                            masked: Set<String>, now: Date) -> TeamSeason
    public static func player(_ playerId: String, games: [GameSummary], masked: Set<String>, since: Date?) -> PlayerSeason?
    public static func topPlayers(games: [GameSummary], masked: Set<String>, metric: PlayerMetric, since: Date?,
                                  minGames: Int, limit: Int) -> [PlayerSeason]
    public static func headToHead(_ a: String, _ b: String, matches: [SeasonMatch], masked: Set<String>) -> HeadToHead
}
public enum SeasonMasking {   // pur, appelle SpoilerPolicy.isMasked sur SeasonMatch.teams
    public static func maskedMatchIds(_ matches: [SeasonMatch], follows: FollowList, revealed: Set<String>) -> Set<String>
}
public enum PlayerName { public static func display(_ summonerName: String, teamCode: String?) -> String }  // "KC Canna" → "Canna"
```

Formules (tests sur `crawl_kc_lec3_tierA_index.json`) : CS/min = Σ CS / Σ minutes ; gold/min = Σ gold / Σ minutes ; KDA = (K + A) / max(1, D) sur la somme (pas la moyenne des ratios) ; participation aux kills = Σ (K + A) / Σ kills de l'équipe ; part des dégâts = moyenne des games enrichies ; meilleure game = KDA de la game la plus haut, puis kills, puis la plus récente ; morts d'équipe = kills adverses. Affichage : KDA 1 décimale, CS/min 1 décimale, gold/min entier, parts en % entier, durée « 35:10 ».

Ruling: **identité d'un joueur = `esportsPlayerId`** ; nom affiché = `TeamPlayer.summonerName` du catalogue si connu, sinon `PlayerName.display` (retire le préfixe « CODE ») — coût si faux : un joueur au pseudo à espace (« Hans Sama ») mal coupé sans catalogue → la règle ne retire que le préfixe égal au code d'équipe.

Ruling: **l'effectif vient du catalogue `getTeams` déjà téléchargé chaque jour** (`Team.players` ajouté) ; un sous-remplaçant (deux joueurs au même rôle) : on retient pour un duel celui qui a le plus de games dans la saison, à égalité le premier listé — coût si faux : `cache-teams.json` grossit (~+0,6 Mo estimé ; le catalogue brut fait 1,55 Mo).

### 1.6 Collecte progressive (pur dans LoLKit, exécution dans l'appli)

```swift
public struct CrawlJob: Sendable, Equatable { public let gameId, matchId, tournamentId, leagueSlug: String; public let number: Int; public let tier: Tier; public let priority: Int }
public enum CrawlPlanner {
    public static func jobs(wanted: CrawlWanted, matches: [SeasonMatch], have: [String: GameSummary],
                            failures: [String: CrawlFailure], masked: Set<String>, now: Date) -> [CrawlJob]
}
public struct CrawlWanted: Sendable { public let openedTeamId: String?; public let followedTeamIds: [String]
    public let worldsStageMatchIds: Set<String>; public let followedLeagueSlugs: [String]; public let currentTournamentIds: Set<String> }
public struct CrawlFailure: Codable, Sendable, Equatable { public enum Reason: String, Codable { case statsDisabled, noData, notFinished, http }
    public var reason: Reason; public var attempts: Int; public var lastAttempt: Date }
public struct CrawlPacer: Sendable {   // pur
    public static let baseInterval: TimeInterval = 2
    public static let backoff: [TimeInterval] = [4, 8, 16, 32, 60]
    public static let sessionRequestBudget = 300
    public mutating func next(after outcome: Outcome) -> Decision   // .wait(seconds) | .stop(reason)
}
```

Ordre de priorité (le plus récent d'abord dans chaque groupe) :
0. équipe dont la page est ouverte (si non suivie) : tournoi en cours, palier A ;
1. équipes suivies : saison entière, palier A ;
2. phase en cours du Mondial (matchs de l'étape de `getStandings` qui contient le premier match non `completed` ; si tout est joué, la dernière étape) : palier A ;
3. ligues suivies : tournoi en cours, puis les précédents de l'année : palier A ;
4. palier B des équipes suivies (tournoi en cours + international en cours).

Règles :
- **Jamais de job pour un match masqué** (`masked` = `SeasonMasking.maskedMatchIds`) ; révéler le match le rend éligible au passage suivant.
- Cadence : 1 requête toutes les **2 s** (y compris les 2 requêtes d'une même game) ; 429 ou 5xx ou erreur réseau → attente 4, 8, 16, 32 puis 60 s ; 5 échecs d'affilée → arrêt jusqu'à la prochaine session. 200 → retour à 2 s.
- **Budget : 300 requêtes par session au premier plan** (≈ 150 games palier A, ≈ 10 min, ≈ 5,3 Mo) ; l'énumération (tournois, résultats, classements) compte dans le budget.
- Au premier plan seulement (la collecte s'arrête avec la scène, comme `poll`) ; jamais pendant un réveil d'arrière-plan.
- Reprise : l'état, c'est le disque (une game est faite si son `GameSummary` existe) ; rien d'autre à mémoriser que les échecs.
- Échecs : `statsDisabled` (404) → définitif ; `noData` (204) et `notFinished` → réessai après 1 h, 3 fois au plus, puis définitif (« N games sans stats ») ; `http` → suit le recul, pas compté comme échec de game.
- Le palier A d'une game s'écrit en un seul fichier quand ses 2 requêtes ont réussi (pas d'état intermédiaire) ; le palier B réécrit le même fichier (`enriched = true`).
- `GameWinners.assign` est rejoué pour le match dès que toutes ses games jouées sont en cache (sinon `result.basis = .unknown`).

### 1.7 Cache disque

Sous `cache/season/` (le `DiskCache` existant, exclu de la sauvegarde iCloud) :

| Chemin | Contenu | Durée |
|---|---|---|
| `season/games/<gameId>.json` | `GameSummary` (JSONEncoder par défaut) | **pour toujours** |
| `season/tournaments/<leagueId>.json` | `Cached<[TournamentRef]>` | 24 h |
| `season/completed/<tournamentId>.json` | `Cached<[CompletedMatch]>` (réduit, pas les vods) | 30 min si actif, pour toujours sinon |
| `season/standings/<tournamentId>.json` | `Cached<Standings>` | idem |
| `season/crawl.json` | `[gameId: CrawlFailure]` | — |

Budget disque : **2 000 games au plus** (≈ 4,5 Mo palier A, ≈ 6,3 Mo palier B). Au-delà, on supprime les games les plus anciennes (`startedAt`) **qui ne concernent aucune équipe suivie** ; une game d'une équipe suivie n'est jamais supprimée. Une game jouée n'est jamais invalidée. `v` > `schemaVersion` connu → fichier ignoré (pas supprimé) ; `v` plus ancien → relu tel quel, champs manquants à nil.

Ruling: **un fichier par game plutôt qu'un index unique** — pourquoi : écriture atomique par game, reprise triviale, aucun fichier géant à réécrire — coût si faux : lecture de ~400 petits fichiers au lancement (faite hors du fil principal, une fois).

### 1.8 Anti-spoiler du socle

- Masquage **à la lecture** : toutes les fonctions de `SeasonStats` prennent `masked: Set<String>` (ids de match) ; un match masqué ne compte ni dans les bilans, ni dans les moyennes, ni dans la forme (il y apparaît comme une pastille neutre « masqué » à sa place chronologique : son existence est déjà publique dans le calendrier), ni dans les joueurs en forme, ni dans le face-à-face ; `maskedMatches` le compte → libellé « N matchs masqués ».
- Activer l'œil sur une équipe après coup : les `GameSummary` restent sur disque, ils sont exclus au calcul suivant.
- **Jamais de nombre de games d'un match masqué** (il trahit la longueur de la série) : on compte des matchs masqués, pas des games ; `gamesPending` exclut les matchs masqués.
- Prochains matchs, adversaire suivant, face-à-face « contre le prochain adversaire » : toujours via `Presenter.nextLine` (F1 + règle C).

---

## 2. Onglet « Accueil »

### 2.1 Navigation

- `AppTab` : `.home` (nouveau, **par défaut**), `.matches`, `.teams`. Icônes : nouvelles `Icon.home`, `Icon.calendar`, `Icon.standings`, `Icon.versus`, `Icon.player` (trait 1,8 pt, grille 24, comme les autres).
- Chaque onglet a son `NavigationStack(path: NavigationPath)` et un modificateur commun `.failleDestinations(zoom:)` qui déclare `MatchRoute` (Détail, inchangé), `TeamRoute(teamId)`, `PlayerRoute(playerId)`, `StandingsRoute(tournamentId)`, `CalendarRoute`, `DuelRoute(left: DuelSide, right: DuelSide)`.
- Ruling: **le lien profond des notifications reste sur l'onglet Matchs** (`RootView.openPendingMatch` passe `matchesPath = NavigationPath([MatchRoute(matchId:)])`) — pourquoi : comportement et tests existants inchangés — coût si faux : l'utilisateur quitte l'Accueil en touchant une notification (attendu).
- « Toucher une équipe partout » : logo/nom d'équipe des cartes, du Détail, des lignes de l'onglet Équipes (le toucher de ligne ouvre la page ; étoile et œil restent des boutons) → `TeamRoute`.

### 2.2 Sections (dans cet ordre)

| # | Section | Source | Contenu | Vide / chargement |
|---|---|---|---|---|
| 0 | En-tête | — | « Accueil », sous-titre « mardi 15 octobre · 3 matchs aujourd'hui » | — |
| 1 | **À ne pas rater** (carte d'en-tête, verre teinté de l'équipe du 1er match si suivie) | `MustWatch.rank` (§3.6) | 1er match en grand + 2 lignes ; ligne d'explication (« Tes équipes · Élimination en jeu ») | rien à proposer → section absente |
| 2 | **En direct maintenant** | `store.live` (repli calendrier, règle existante) | matchs en cours de l'ensemble du calendrier chargé : équipes suivies d'abord, puis ligues suivies, puis internationaux ; score de série + « Regarder » ; **masqué → « En direct » seul, sans score ni Regarder** | section absente |
| 3 | **Calendrier** | `store.schedule` | bandeau de 7 jours défilant (aujourd'hui −1 → +5, défilement ±3 semaines dans la page en cache), pastille sous un jour = un match d'équipe ou de ligue suivie (pleine) ou international (anneau) ; toucher un jour → la liste du jour ; « Tout le calendrier » → `CalendarRoute` | « Aucun match ce jour-là » |
| 4 | **Résultats récents** | `store.schedule` (`completed`, 72 h) | 8 au plus, suivis d'abord ; score si non masqué ; masqué → « Terminé · toucher pour révéler » (`store.reveal`) | « Pas de résultat ces 3 derniers jours » |
| 5 | **Activité récente** | `HomeFeed.activity` (§2.4) | 6 éléments au plus | squelette 2 lignes pendant la lecture du disque ; vide → section absente |
| 6 | **Joueurs en forme** | `SeasonStats.topPlayers` | pilules « Semaine / Saison » × « KDA / Kills / CS/min » ; 5 joueurs : icône du champion le plus joué, pseudo, équipe, valeur ; toucher → `PlayerRoute` ; minimum 2 games (semaine) / 5 (saison) | « Les stats arrivent : 12 games lues sur 40 » pendant la collecte ; rien lu → section absente |

Ruling: **sans équipe suivie, l'Accueil montre quand même le Mondial** (direct, calendrier, à ne pas rater, joueurs en forme de la phase en cours) avec une carte « Suis tes équipes pour un accueil sur mesure » en tête — pourquoi : un inconnu doit voir de la valeur en 10 s — coût si faux : quelques requêtes de collecte du Mondial pour quelqu'un qui ne s'y intéresse pas (≤ 104 requêtes pour toute la phase suisse 2025).

### 2.3 Performance et anti-spoiler

- **Cache d'abord** : tout ce qui s'affiche vient de `AppStore` (déjà chargé depuis le disque au lancement) et de `SeasonStore` (les `GameSummary` sont lus hors du fil principal au lancement ; < 1 s pour 2 000 fichiers). Aucune requête n'est attendue pour afficher l'écran ; la boucle existante (`poll`) et la collecte rafraîchissent en tâche de fond.
- Les sections calculées (`HomeFeed.build`) le sont hors du fil principal, mémoïsées par (nombre de games, signature des suivis, révélations, jour), publiées en une fois.
- Animations : cascade d'apparition (≤ 8 éléments, une fois), `Motion`, `PressableStyle`, haptique « révéler » ; **aucune animation continue** dans les listes (pas de pulsation sur les lignes du calendrier ni des résultats ; la pulsation « en direct » existante seulement dans la section 2, 3 lignes au plus).
- Anti-spoiler : chaque ligne de match passe par `Presenter.scoreLine` ; « prochain match » d'une équipe par `Presenter.nextLine` ; activité et joueurs en forme reçoivent `masked`.

### 2.4 Activité récente (LoLKit `HomeFeed.activity`, ce que les données disent vraiment)

Types (enum sans texte ; l'appli formule) :
- `.justFinished(matchId)` : match terminé il y a ≤ 6 h, impliquant une équipe ou ligue suivie, **non masqué** (masqué : pas d'élément) ;
- `.streak(teamId, wins|losses, count)` : série en cours ≥ 3 (séries de matchs, non masqués) ;
- `.killRecord(gameId, teamId, kills)` : plus grand total de kills d'une équipe dans le périmètre de la saison, si la game date de ≤ 7 jours ;
- `.bigGame(gameId, playerId, kills)` : un joueur ≥ 10 kills dans une game de ≤ 7 jours ;
- `.fastGame(gameId, seconds)` / `.longGame` : game < 25 min / > 45 min de ≤ 7 jours ;
- `.comeback15(gameId, teamId, deficit)` : équipe menée d'au moins 2 500 gold à 15 min (palier B) et gagnante, vainqueur **exact** seulement.

Ruling: **ace, baron décisif, gros retournement en cours de game : reportés au lot 2** (ils exigent la suite des frames, `GameTimeline`) ; l'énumération est ouverte pour les ajouter — coût si faux : une activité moins spectaculaire cette nuit.

---

## 3. Autres écrans

### 3.1 Page équipe (`TeamRoute`)

- En-tête : logo, nom, ligue, couleur (Vitrail si suivie, sinon verre neutre), étoile et œil (si suivie).
- Pilules de périmètre : « Saison 2026 » (défaut) puis un par tournoi de l'année où l'équipe a joué (« LEC Split 3 », « Mondial »).
- Ligne d'état : « Calculé sur 24 games · 7 à lire · 2 matchs masqués » (chiffres de `TeamSeason`).
- **Bilan** : séries V-D, games V-D, série en cours (« 4 victoires d'affilée »).
- **Forme** : 5 pastilles (V / D / masqué), la plus récente à droite.
- **Prochains matchs** : 3 au plus, via `Presenter.nextLine` (`.hidden` → une ligne « Prochain · masqué » et rien d'autre) ; toucher → Détail.
- **Effectif** : joueurs du catalogue (rôle, photo si `image`), toucher → `PlayerRoute`.
- **Stats moyennes par game** : kills, morts, gold, durée, drakes (+ répartition des types en icônes), barons, tours, inhibiteurs, « écart de gold à 15 min » (« sur N games », « — » si N = 0).
- **Champions les plus joués** : 8 icônes Data Dragon avec le nombre de games.
- **Face-à-face contre le prochain adversaire** (si `nextLine` le montre) : `headToHead` de la saison + lien vers le duel d'équipes.
- **Classement** : sa ligne dans `getStandings` du tournoi en cours (rang, V-D) → `StandingsRoute` ; masquée selon §3.5.
- Chargement : squelettes au gabarit de chaque bloc ; équipe non suivie : la collecte priorité 0 (§1.6) démarre à l'ouverture et s'arrête à la fermeture.
- Anti-spoiler : équipe en anti-spoiler → tout est calculé sans ses matchs masqués ; si **tous** ses matchs de la saison sont masqués : « Stats masquées · 12 matchs masqués ». Ruling: **pas de bouton « révéler la saison »** — pourquoi : la révélation reste par match (§8) ; la page dit seulement combien de matchs sont masqués — coût si faux : un fan doit révéler match par match (les résultats récents de l'Accueil le permettent).

### 3.2 Calendrier complet (`CalendarRoute`)

Vue mois (grille lundi-dimanche, locale de l'appareil), pastilles comme le bandeau, liste du jour sous la grille. Mois couverts par le calendrier en cache ; passer à un mois hors couverture lit une page `older`/`newer` de `getSchedule` (mêmes ligues que le calendrier de l'appli, 1 requête ≈ 48 Ko), gardée en mémoire pour la session. Masqué : « Terminé » / « En direct » sans score. Logique pure : `CalendarMonth.days(events:month:calendar:followed:)` (LoLKit).

### 3.3 Duel de joueurs et duel d'équipes

- **Dans le Détail** (match à venir ou joué) : section « Duel » sous les stats, onglets « Joueurs » / « Équipes ».
- Joueurs, poste par poste (top, jungle, mid, bottom, support) : à gauche l'équipe A, à droite B ; joueurs = composition de la game affichée si elle est jouée et non masquée, sinon l'effectif du catalogue (règle du remplaçant, §1.5). Barres en miroir (largeur = valeur / max des deux) : KDA, CS/min, gold/min, part des dégâts (« — » sans game enrichie), participation aux kills ; 3 champions favoris (icônes) ; pour une game jouée **et non masquée**, une ligne « Cette game » (champion, K/D/A, CS, gold).
- Choix libre : « Changer » sur chaque côté → sélecteur (recherche parmi les joueurs des `GameSummary` en cache et des effectifs du catalogue) → `DuelRoute`.
- Équipes : `TeamSeason` côte à côte (bilan, moyennes) + face-à-face de la saison (« Cette saison : KC 2 – 1 G2 », liste des matchs ; masqués exclus et comptés).
- Anti-spoiler : match masqué (à venir, en cours ou terminé) → **uniquement** les stats de saison (matchs masqués exclus) ; aucune ligne « Cette game », pas de composition lue dans ce match.
- Logique : `Duel.players(left:right:games:masked:)`, `Duel.lineup(teamId:catalog:games:)` (LoLKit).

### 3.4 Page joueur (`PlayerRoute`)

En-tête (photo du catalogue si présente, pseudo, rôle, équipe → `TeamRoute`), pilules de périmètre (comme la page équipe), « sur N games », moyennes (K/D/A, KDA, CS/min, gold/min, participation aux kills, part des dégâts « sur N games enrichies » ou « — »), champions joués (icône, games, V-D avec « estimé » si besoin, KDA), meilleure game (lien vers le Détail du match, jamais un match masqué), 5 dernières games (champion, K/D/A, résultat si non masqué). Squelettes.

### 3.5 Suivre une ligue ; classements et tableaux

- `FollowList` gagne `leagues: [FollowedLeague]` (`id`, `slug`, `name`, `image`, `notifyStarts: Bool = false`), décodage tolérant (absent → `[]`).
- Effets d'une ligue suivie : `ScheduleQuery.leagueIds` l'inclut ; matchs dans l'Accueil, le calendrier, « à ne pas rater » ; collecte priorité 3 ; notifications de début de match si `notifyStarts` (`MatchReminders.plan` les ajoute avec la même règle `nextLine` pour les équipes suivies concernées).
- Ruling: **pas d'anti-spoiler par ligue cette nuit** — pourquoi : `SpoilerPolicy.isMasked` ne reçoit pas la ligue et toutes les surfaces (widgets, Live Activity) en dépendent — coût si faux : un fan de LCK qui veut tout masquer doit mettre l'œil sur chaque équipe.
- Ruling: **widgets inchangés pour les ligues suivies** (reporté) — pourquoi : garde-fou de non-régression des widgets — coût si faux : écart avec l'objectif, noté au livrable.
- Écran Équipes : dans la section « Toutes les ligues », sous les pilules : « Suivre la ligue » (étoile) et « Suivre ses N équipes ». Onglet Matchs : section « Ligues » après les cartes (une ligne par ligue suivie : prochain match, lien Classement).
- **Classements** (`StandingsRoute(tournamentId)`, depuis la page équipe, la ligne de ligue et l'Accueil) : `StandingsTable.build(standings:)` (LoLKit) donne pour chaque étape : `.table([Row(ordinal, team, wins, losses)])` (rankings), `.swiss([RecordGroup(record "2-1", teams)])` (bilans recalculés depuis `outcome` des matchs `completed`), `.bracket(rounds)` (Phase finale : ordre [0-3] quarts, [4] = V[0] vs V[1], [5] = V[2] vs V[3], [6] finale ; autres tableaux : liste ordonnée des matchs). Couleur d'équipe suivie sur sa ligne.
- Masquage : un tableau est masqué si une équipe suivie en anti-spoiler y figure **et** qu'un de ses matchs terminés de ce tournoi est masqué ; affichage « Classement masqué · toucher pour révéler » ; la révélation est mémorisée (`AppSettings.revealedStandingIds: Set<String>`, tolérant) et **ne révèle aucun match** (les cartes restent masquées). Ruling — pourquoi : un classement contient tous les résultats — coût si faux : un tap de plus pour qui veut voir le classement.

### 3.6 « À ne pas rater » (LoLKit `MustWatch.rank`)

Candidats : matchs `unstarted` ou `inProgress` du calendrier commençant aujourd'hui (jour local) ; moins de 3 → on étend aux prochaines 24 h. **Exclus** : tout match d'une équipe suivie en anti-spoiler dont le dernier match est masqué (`maskedLatestTeamIds`), ou opposant une équipe à une telle équipe (règles F1/C généralisées à tous ses matchs à venir) ; matchs TBD contre TBD.

Score (points entiers, affichables dans « Comment c'est calculé ») :

| Raison (`MustWatchReason`) | Points | Condition |
|---|---|---|
| `.followedTeam` « Tes équipes » | +50 par équipe suivie (max 100) | |
| `.followedLeague` « Ta ligue » | +25 | ligue suivie |
| `.international` « Mondial » / « MSI » / « First Stand » | +20 | `League.internationalSlugs` |
| `.elimination` « Élimination en jeu » | +30 | suisse : une équipe à 2 défaites |
| `.qualification` « Qualification en jeu » | +30 | suisse : une équipe à 2 victoires (cumul max +40 « Tout se joue ») |
| `.final` / `.semiFinal` / `.quarterFinal` / `.playoffs` | +40 / +30 / +20 / +20 | étape `knockouts` (index) ou `blockName` (« Finale », « Demi-finales », « Quarts de finale », « Play-offs ») |
| `.topClash` « Choc du haut de tableau » | +15 | les deux équipes dans le top 3 des `rankings` |
| `.closeRanks` « Duel serré » | +10 | écart de rang ≤ 1 |
| `.rematch` « Revanche » | +10 | déjà affrontées cette saison (dernier match non masqué) |
| `.derby` « Derby » | +10 | même ligue d'attache, à un international |
| `.bestOf5` / `.bestOf3` | +10 / +5 | |
| `.live` « En direct » | +15 | `inProgress` |

Tri : points décroissants, puis heure de début. Explication : les 2 raisons qui rapportent le plus (« Tes équipes · Élimination en jeu »). **Anti-spoiler** : les raisons tirées de résultats (suisse, classement, revanche) ne sont calculées que si le tableau du tournoi n'est pas masqué (§3.5) ; sinon ces points valent 0 pour tous les matchs du tournoi (l'ordre ne trahit rien). Affichage : 1 + 2 dans l'Accueil, 5 au plus en tête de Matchs (Lot 1.5) ; lien « Comment c'est calculé » (tableau ci-dessus).

### 3.7 Onboarding (P1)

- Montré au premier lancement si `AppSettings.onboardingDone == false` **et** aucune équipe suivie ; un utilisateur existant (suivis non vides au lancement) est marqué fait sans le voir. Champ tolérant (absent → `false`).
- 3 écrans, « Passer » partout, pagination par points, `Motion` + Réduire les animations :
  1. « Ton compagnon de saison LoL esport » : un **exemple vivant** — une carte Vitrail d'aperçu (`SampleData`) dont le score et le chrono avancent (statique si Réduire les animations), étiquetée « Exemple ».
  2. « Choisis tes équipes ou une ligue » : équipes du Mondial 2026 (catalogue + classements) en grille de logos, pilules de ligues, recherche ; étoile = suivre tout de suite.
  3. « Pas de spoiler si tu veux » : une phrase (« L'œil cache les scores d'une équipe jusqu'à ce que tu choisisses de les voir »), interrupteur par équipe choisie ; « C'est parti » → Accueil.
- États vides soignés de chaque écran (tableau §2.2, page équipe sans stats « Les stats de cette équipe arrivent », classement absent « Pas encore de classement pour ce tournoi »).

### 3.8 Accessibilité et langue (P2)

- **Catalogue** `Resources/Localizable.xcstrings` (langue source **fr**, traduction **en** complète), `project.yml` : `options.developmentLanguage: fr` ; Info.plist : `CFBundleDevelopmentRegion: fr`, `CFBundleLocalizations: [fr, en]`.
- Ruling: **catalogue tenu à la main + contrôle en CI** (`scripts/strings-check.py`, job Linux de `lolkit.yml` : chaque littéral `Text("…")`, `Label("…")`, `String(localized: "…")` de `App/` et `Shared/` doit avoir une entrée `en`) — pourquoi : sans Mac, Xcode ne remplit pas le catalogue tout seul — coût si faux : une chaîne oubliée reste en français pour un anglophone.
- Ruling: **les nouvelles API de LoLKit renvoient des valeurs (enums), jamais du texte** (`MustWatchReason`, `ActivityItem`, `StandingsTable`) ; les textes existants de LoLKit (`Format`, `AppFormat`, `WidgetText`) restent en français cette nuit — coût si faux : quelques sous-titres et widgets en français pour un anglophone (noté au livrable, tâche suivante).
- Données en `hl=fr-FR` inchangées (la correspondance ligue d'attache ↔ `getLeagues` repose sur les noms) ; l'appli affiche le nom d'une ligue internationale par son slug (`worlds` → « Mondial » / « Worlds »).
- VoiceOver : libellés sur toutes les icônes seules (kills, tours, drakes…), scores lus « Karmine Corp 2, G2 1 », masqué lu « Score masqué », pastilles de forme lues « Victoire / Défaite / Masqué », barres de duel lues « KDA : Canna 3,4, BrokenBlade 4,1 ».
- Dynamic Type : modificateur `.sora(_ style: SoraStyle)` dans `Shared/DA/Typography.swift`, qui lit `@Environment(\.dynamicTypeSize)` et met à l'échelle avec `UIFontMetrics(forTextStyle:)` (titre ↔ `.largeTitle`, corps ↔ `.body`, secondaire ↔ `.footnote`, étiquette ↔ `.caption2`), plafond `.accessibility2` ; nouveaux écrans en `.sora`, anciens écrans migrés pour les textes principaux ; widgets et Live Activity inchangés (`Typo` fixe).
- Contraste : texte secondaire `#94a0bf` sur `#0b1020` (7,2:1 calculé) conservé ; aucun texte sous 4,5:1.

---

## 4. Découpage pour l'exécution parallèle

Principes : chaque tâche **crée** ses fichiers ; un fichier existant n'est modifié que par **une** tâche (colonne « modifie ») ; les fichiers partagés de l'appli (`RootView`, `AppStore`, `MatchDetailView`, `TeamsView`, `MatchesView`, `TeamRows`, `TeamCardView`, `SampleData`, `Icon`, `project.yml`) ne sont touchés que par les tâches d'intégration I1/I2/I3. Tests LoLKit en TDD (`bash scripts/lolkit.sh test`) sur les fixtures de §1.1 ; tests hébergés + planches PNG pour l'appli.

| Id | Tâche | Crée | Modifie | Dépend de | Taille |
|---|---|---|---|---|---|
| **L1** | API saison : tournois, résultats, classements, page de calendrier, effectif | `Season/TournamentRef.swift`, `Season/CompletedMatch.swift`, `Season/Standings.swift`, `Season/SeasonMatch.swift`, `API/LoLClient+Season.swift` (`tournaments(leagueId:)`, `completedEvents(tournamentId:)`, `standings(tournamentId:)`, `schedulePage(leagueIds:pageToken:) -> SchedulePageResult`), tests + fixtures `season/` | `API/LoLClient.swift` (`api` passe `internal`), `Models/Team.swift` (`players`) | — | M (~450 l.) |
| **L2** | `GameSummary`, `GameWinners`, `PlayerName` | `Season/GameSummary.swift`, `Season/GameWinners.swift`, `Season/PlayerName.swift`, tests (game 304, index KC) | — | — (types existants) | M |
| **L5** | Ligues suivies et réglages | tests | `Follow/FollowList.swift` (`leagues`), `Follow/ScheduleQuery.swift`, `Reminders/MatchReminders.swift` (`notifyStarts`), `Storage/AppSettings.swift` (`onboardingDone`, `revealedStandingIds`), `PublicInitTests` | — | M |
| **L8** | Calendrier pur | `Calendar/CalendarMonth.swift`, `Calendar/WeekStrip.swift`, tests | — | — | S |
| **L3** | Agrégats | `Season/SeasonStats.swift`, `Season/TeamSeason.swift`, `Season/PlayerSeason.swift`, `Season/SeasonMasking.swift`, `Season/Duel.swift`, tests (agrégats KC §1.1) | — | L1 (`SeasonMatch`), L2 | L |
| **L4** | Planification de la collecte | `Season/CrawlPlanner.swift`, `Season/CrawlPacer.swift`, `Season/SeasonScope.swift`, tests | — | L1, L2 | M |
| **L6** | Tableaux | `Season/StandingsTable.swift`, `Season/StandingsMasking.swift`, tests (suisse 2025, tableau 2025 en fixture réduite) | — | L1 | M |
| **L7** | Accueil pur | `Home/MustWatch.swift`, `Home/HomeFeed.swift` (sections, activité), tests | — | L3, L6, L8 | L |
| **A1** | `SeasonStore` + collecteur | `App/Season/SeasonStore.swift` (@Observable, lecture disque hors fil principal, agrégats mémoïsés), `App/Season/SeasonCrawler.swift` (exécute `CrawlPlanner`/`CrawlPacer`), `App/Season/SeasonSamples.swift`, tests hébergés (faux transport : ordre, cadence, budget, masqué jamais demandé, reprise) | — | L1, L2, L4 | L |
| **I1** | Intégration 1 | — | `RootView.swift` (onglet Accueil, `NavigationPath`, `.failleDestinations`, lien profond), `AppStore.swift` (`season: SeasonStore`, suivre une ligue, `revealStandings`, `onboardingDone`, crawl lié à `poll`), `Shared/Preview/SampleData.swift` (`PreviewData.season`), `Shared/DA/Icon.swift` + assets (5 icônes), `App/Matches/MatchRoute.swift` (routes) ; crée `App/Navigation/Routes.swift`, `App/Home/HomeView.swift` (coquille vide) | A1, L5 | M |
| **A2** | Page équipe | `App/TeamPage/*.swift`, planche PNG, tests | — | I1, L3, L6 | L |
| **A3** | Accueil | `App/Home/*Section.swift` (remplit la coquille), planches PNG (avec et sans suivis, masqué) | `App/Home/HomeView.swift` (créé par I1, possédé par A3 ensuite) | I1, L7 | L |
| **A4** | Duels | `App/Duel/*.swift` (section du Détail en vue autonome `DuelSection`, `DuelView`, sélecteur) | — | I1, L3 | M |
| **A5** | Page joueur | `App/PlayerPage/*.swift` | — | I1, L3 | M |
| **A6** | Classements | `App/Standings/*.swift` | — | I1, L6 | M |
| **A7** | Calendrier complet | `App/Calendar/*.swift` | — | I1, L8 | S |
| **A8** | Ligues (UI) | `App/Leagues/*.swift` (`LeagueFollowRow`, `LeaguesSection`) | — | I1, L5 | S |
| **A9** | Onboarding | `App/Onboarding/*.swift`, planche PNG | — | L5 (champ), I1 (branchement) | M |
| **I2** | Intégration 2 | — | `MatchDetailView.swift` (insère `DuelSection`, taps équipe), `TeamsView.swift` / `TeamRows.swift` (taps → page équipe, ligues), `MatchesView.swift` (« À ne pas rater » + Ligues), `TeamCardView.swift` (tap logo), `RootView.swift` (onboarding en `fullScreenCover`) | A2-A9 | M |
| **P2** | Accessibilité et langue | `Resources/Localizable.xcstrings`, `scripts/strings-check.py`, modificateur `.sora` | `Shared/DA/Typography.swift`, `project.yml`, `.github/workflows/lolkit.yml`, libellés VoiceOver des écrans (après I2, seule tâche à toucher tout l'App/) | I2 | L |

**Vagues** (au plus 2 lots à la fois, ordre de coupe de l'objectif) :
1. L1 ‖ L2 ‖ L5 ‖ L8 (LoLKit, fichiers disjoints).
2. L3 ‖ L4 ‖ L6 (LoLKit) ; A9 peut démarrer (champ `onboardingDone` livré par L5).
3. A1 ‖ L7, puis I1 (fusion, CI verte, IPA intermédiaire).
4. A2 (page équipe, prioritaire) ‖ A3 (Accueil) ‖ A4 (duels) ‖ A5 (joueur) ; puis A6 ‖ A7 ‖ A8.
5. I2 (fusion, IPA), puis P2, relecture finale.

Coupe (si le temps manque, dans cet ordre on garde) : L1-L4 + A1 + I1 → A2 → A3 (+L7, L8) → A4 → A5 → A9 → A8 (+L5 déjà là) → A6 (+L6) → A7 → P2.

Critères de fin par tâche LoLKit : les valeurs de §1.1 en assertions (game 304 : durée 2031 s, CS/min Canna 8,98, KC +228 à 15 min, vainqueur G2 « déduit » ; index KC : 31 games, 22-9, 509 kills, 85 drakes ; LEC S3 : 137 games jouées pour 175 listées ; suisse 2025 : KT 3-0 … PSG 0-3 ; tableau 2025 : [4] = T1 vs TES) ; décodage tolérant (champ retiré → pas d'échec). Critères appli : planches PNG non vides (anti-spoiler visible : « N matchs masqués », « Classement masqué »), tests hébergés de la collecte (aucune URL de game d'un match masqué ; ≥ 2 s entre deux requêtes ; arrêt à 300), lien profond des notifications inchangé (test existant vert).

---

## 5. Volumes mesurés et projetés

| Périmètre | Games jouées | Requêtes palier A | Octets palier A | Durée à 2 s/req |
|---|---|---|---|---|
| KC, LEC Split 3 (mesuré) | 31 | **62** | **1 094 485** | **2 min 40 s** |
| KC, LEC 2026 (S1 31 + S2 42 + S3 31) | 104 | 208 | ≈ 3,7 Mo | ≈ 7 min |
| LEC Split 3 (ligue) | 137 | 274 | ≈ 4,8 Mo | ≈ 9 min 20 s |
| LEC 2026 (ligue) | 383 | 766 | ≈ 13,5 Mo | ≈ 26 min (3 sessions) |
| LCK Split 3 | 154 | 308 | ≈ 5,4 Mo | ≈ 10 min 30 s |
| Mondial 2025 complet / phase suisse | 84 / 52 | 168 / 104 | ≈ 3,0 / 1,8 Mo | ≈ 5 min 40 s / 3 min 30 s |
| Palier B, KC LEC S3 | 31 | +62 | ≈ +4,1 Mo | +2 min 10 s |

Énumération : par ligue 1 requête (`getTournamentsForLeague`, 0,2-3,9 Ko) ; par tournoi 2 requêtes (`getCompletedEvents` 44-66 Ko + `getStandings` 16-29 Ko). Cache disque : ~2,2 Ko par game (palier A), ~3,2 Ko (palier B) ; LEC 2026 entière ≈ 0,9 Mo.
