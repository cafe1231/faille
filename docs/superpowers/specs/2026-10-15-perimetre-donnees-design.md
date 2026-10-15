# Faille — périmètre des données : la saison en cours, la précédente, les tournois en cours (conception)

Date : 15/10/2026. Statut : **contraignant pour le plan du lot qualité** (gel des fonctionnalités : on garde ce qui existe, on borne les données).
Décision de Dan (citée telle quelle) : « uniquement le contenu des équipes des tournois en cours et de la saison en cours, pas avant ; par exemple pour les Worlds et la Demacia Cup il faut leurs données complètes, mais de cette saison et de celle d'avant, pas plus ».
Références : `2026-10-15-faille-saison-design.md` (socle saison, ce document **remplace** ses rulings §1.2 « saison = année civile » pour le filtrage, §1.6 ordre de collecte, §1.7 budget disque ; tout le reste est inchangé), `2026-10-13-faille-design.md` §8 anti-spoiler (inchangé, contraignant).

Chaque décision : **Ruling: … — pourquoi — coût si faux**. Les valeurs en `code` sont **mesurées** (59 requêtes réelles du 15/10/2026, 10:30-10:47 heure de Paris, une toutes les 2,1 s, aucune vers `lol.fandom.com`) et servent d'assertions.

---

## 0. En une minute

- Une seule règle pure dans LoLKit, **`SeasonWindow`** : saison = année civile du **début** du tournoi ; sont dans le périmètre la saison en cours (2026), la précédente (2025), les tournois annoncés de la saison suivante, et un tournoi **en cours** plus ancien (garde-fou : commencé il y a ≤ 400 jours). **Rien de 2024 ni avant** : ni requête, ni cache, ni écran.
- Le périmètre est un **plafond**, pas une cible : la collecte ne lit toujours que ce qu'elle veut (équipes et ligues suivies, page ouverte, compétitions complètes). Les compétitions dont Dan veut les **données complètes** (toutes les équipes) : Mondial, MSI, First Stand, **Demacia Cup**.
- Le filtre s'applique en **quatre couches** : énumération (aucune requête hors fenêtre), `SeasonStore` (rien hors fenêtre n'entre ni ne sort : point d'étranglement de tous les écrans), disque (purge au lancement, migration une fois par fenêtre), écrans (choix de la saison affichée).
- Mesuré : la Demacia Cup **n'a que 2026** dans l'API (ligue créée en 2026) ; les stats `window` des games de 2025 (et même 2024) répondent toujours (`200`, `finished`) ; KC = `113` games en 2026 + `108` en 2025 ; tout l'international 2025-2026 = `377` games (`772` requêtes, ≈ 2,6 sessions).

---

## 1. Mesures réelles (15/10/2026, à recopier dans les tests)

Fixtures capturées hors du dépôt : `C:\Users\Dan\AppData\Local\Temp\claude\C--Users-Dan-Desktop-01-Dev-App-Esport-en-direct\497551d5-ffb1-472a-813a-0380440095c9\scratchpad\fixtures\perimetre\` (réponses brutes dans `…\scratchpad\perimetre\`). La tâche W1 copie dans `LoLKit/Tests/LoLKitTests/Fixtures/season/perimetre/` : les 7 `getTournamentsForLeague_<slug>.json` (complets, 142 o à 3,9 Ko), `completed_kc_g2_2024_2026_reduced.json` (48 Ko : par tournoi, nombre de matchs et de games jouées, et les seuls matchs de KC et G2 avec `playedGameIds`), `getStandings_demacia_cup_2026.json`. Ne **pas** copier `completed_index_2024_2026.json` (302 Ko, sert au calcul des volumes). Si le dossier a disparu : recapturer avec les mêmes routes, 1 requête / 2 s.

### 1.1 `getLeagues` (12 220 o, 51 ligues)

- **Demacia Cup** : `demacia_cup`, id `117126995932274206`, nom `DCGI`, région `INTERNATIONAL`. Les autres ligues `INTERNATIONAL` : `worlds`, `msi`, `first_stand`, `wsci`, `ewc_lol`, `tft_esports`, `wqs`, `asian_games`.
- **EMEA Masters** `emea_masters` `100695891328981122` ; LFL `105266103462388553` ; LPL `98767991314006698` ; LCS `98767991299243165` ; LTA North `lta_n` `113470291645289904` ; LTA South `lta_s` `113475181634818701` ; LTA Cross `lta_cross` `113475149040947852`.

### 1.2 `getTournamentsForLeague` (tous `200`, du plus récent au plus ancien)

| Ligue | Taille | Tournois | Dans la fenêtre au 15/10/2026 (2025-2026) | Hors fenêtre |
|---|---|---|---|---|
| `worlds` | 1 107 o | 11 | `worlds_2026` `115660540725177488` 2026-10-15 → 2026-11-15 (**en cours**, commencé aujourd'hui) ; `worlds_2025` `113475452383887518` 2025-10-14 → 2025-11-09 | 9 (`worlds_2024` `112966669920590211` 2024-09-24 → 2024-11-02 … `worlds_2011`) |
| `msi` | 792 o | 8 | `msi_2026` `115570934354631452` 06-27 → 07-12 ; `msi_2025` `113470835034591734` 06-26 → 07-13 | 6 |
| `first_stand` | 244 o | 2 | `first_stand_2026` `115570858980956868` 03-16 → 03-23 ; `first_stand_2025` `113470740394381750` 03-10 → 03-16 | 0 |
| `demacia_cup` | 142 o | **1** | `demacia_cup_2026` `117133773242499009` 2026-10-02 → 2026-10-17 (**en cours**, en direct à 08:34 UTC) | 0 — **pas de 2025 dans l'API** |
| `lec` | 3 527 o | 34 | `lec_split_3_2026` `115548681802226458`, `lec_split_2_2026` `115548668058343983`, `lec_split_1_2026` `115548424304940735`, `lec_summer_2025` `113487526512660769` 08-02 → 09-29, `lec_spring_2025` `113487400974323999` 03-29 → 06-08, `lec_winter_2025` `113475994398658012` 01-18 → 03-02 | 28, dont `eu_lcs_summer_2013` `109349946712116171` **2013-06-14 → 2022-08-26** (date de fin aberrante) |
| `lck` | 3 872 o | 37 | `lck_split_3_2026` `115548147890329817`, `lck_split_2_2026` `115548128960088078`, `lck_split_1_2026` `115548106590082745`, `lck_split_3_2025` `113503357263583149`, `lck_split_2_2025` `113503260417890076`, `lck_cup_2025` `113480665704729522` | 31, dont `champions_winter_2014` `109440320603801592` **2013-11-15 → 2014-01-25** (à cheval sur le Nouvel An) |
| `emea_masters` | 2 589 o | 22 | 7 : `emea_masters_summer_2026` `117171782811211421` 09-20 → 10-23 (**en cours**), `_barrage_2026`, `_spring_2026`, `_winter_2026`, `_summer_2025` (2025-09-23 → 2025-11-03), `_spring_2025`, `_winter_2025` | 15 |
| `lcs` | 3 104 o | 30 | 3 (splits 2026 seulement : **pas de LCS en 2025**) | 27 |
| `lta_n` / `lta_s` / `lta_cross` | 352 / 352 / 256 o | 3 / 3 / 2 | tous 2025 (la LCS et le CBLOL de 2025 s'appelaient LTA North / South) | 0 |
| `lfl` / `lpl` / `lcp` | 1 452 / 2 105 / 652 o | 14 / 20 / 6 | 6 / 6 / 6 | 8 / 14 / 0 |
| `wsci` / `ewc_lol` / `kespa_cup` / `asian_games` | 135-142 o | 1 chacun (2026) | terminés en 2026 | — |

Constats : chaque ligue liste **tout son historique** (jusqu'à 2011) ; filtrer sur la seule année de début suffit pour toutes les ligues mesurées ; deux dates aberrantes ou à cheval existent réellement (`eu_lcs_summer_2013`, `champions_winter_2014`) et servent de cas limites.

### 1.3 `getCompletedEvents` (matchs, games jouées = Σ `gameWins`, octets)

| Tournoi | Octets | Matchs | Games jouées / listées |
|---|---|---|---|
| `worlds_2026` | 35 | 0 | 0 / 0 (`play_ins` : 6 matchs `unstarted`) |
| `worlds_2025` | 62 947 | 41 | **84** / 99 |
| `worlds_2024` (hors fenêtre) | 52 370 | 50 | 106 / 124 |
| `demacia_cup_2026` | 18 011 | 25 | **62** / 73 (en cours : le chiffre bougera) |
| `msi_2026` / `msi_2025` | 40 937 / 47 208 | 20 / 19 | 71 / 80 |
| `first_stand_2026` / `_2025` | 24 666 / 20 418 | 13 / 13 | 45 / 35 |
| LEC 2026 (S1, S2, S3) | 65 879 / 62 496 / 61 277 | 80 / 53 / 53 | 105 / 141 / 137 |
| LEC 2025 (winter, spring, summer) | 45 714 / 65 721 / 39 612 | 59 / 54 / 30 | 84 / 139 / 85 |
| LCK 2026 (S1, S2, S3) | 34 205 / 74 076 / 44 169 | 40 / 95 / 53 | 125 / 224 / 154 |
| LCK 2025 (cup, S2, S3) | 36 753 / 77 938 / 63 137 | 38 / 96 / 75 | 109 / 240 / 206 |
| `emea_masters_summer_2026` | 65 600 | 100 | 180 / 220 |
| `wsci_2026` | 31 187 | 53 | 74 / 81 |
| `lta_n` 2025 (S1, S2, S3) | 7 881 / 35 265 / 17 870 | 12 / 52 / 22 | 26 / 95 / 68 (C9 : 6 / 32 / 21) |
| `lcs_split_3_2026` | 29 265 | 38 | 103 (C9 : 32) |

Par équipe (games jouées, codes du flux) : **KC 2026 = 113** (LEC S1 31, S2 42, S3 31, MSI 9) ; **KC 2025 = 108** (winter 25, spring 41, summer 23, First Stand 19). G2 2026 = 120, 2025 = 103, 2024 = 8 (Mondial 2024, exclu). T1 2026 = 130, 2025 = 162, 2024 = 17 (exclu).

Bilans (séries puis games, depuis `gameWins`) : **KC 2026 `33-13`, `72-41`** ; **KC 2025 `26-14`, `64-44`** ; G2 2026 `33-15`, `79-41` ; G2 2025 `28-14`, `62-41`. Face-à-face KC-G2 : 2026 **`2-6`**, 2025 **`3-2`**, fenêtre 2025-2026 **`5-8` sur 13 matchs** (premier : `lec_winter_2025` 2025-01-18 KC 1-0 ; dernier : `lec_split_3_2026` 2026-09-06 KC 1-3).

### 1.4 `getStandings`

- `demacia_cup_2026` (14 599 o) : étapes `swiss` (15 matchs `completed`, 30 équipes avec id), `round_4` (3, **3 classés**), `round_5` (2), `playoffs` (7 : 5 `completed`, 2 `unstarted`). → étape en cours = `playoffs`.
- `worlds_2026` (16 255 o) : `play_ins` 6, `swiss` 33, `knockouts` 7, tous `unstarted` ; 4 équipes avec id (play-ins).
- `lec_winter_2025` (31 699 o) : `regular_season` 45 matchs, 10 classés, 90 ids d'équipe ; `playoffs` 14. **Les tournois de 2025 ont leurs ids d'équipe** : la jointure `SeasonMatch.join` marche telle quelle.

### 1.5 Flux `window` des games anciennes (palier A, 2 requêtes)

| Game | 1re fenêtre | Fenêtre finale (`startingTime` = maintenant − 90 s) |
|---|---|---|
| Mondial 2025, finale g1 `113475871524050784` | `200`, 16 787 o, 1re frame 2025-11-09T07:32:19.493Z | `200`, 18 558 o, `finished` 2025-11-09T08:08:33.922Z, kills 11-25 |
| LEC winter 2025, sem. 1 `113476054450558828` | `200`, 16 800 o | `200`, 18 511 o, `finished`, kills 3-11 |
| First Stand 2025, finale g1 `113470740396478960` | `200`, 16 802 o | `200`, 18 535 o, `finished`, kills 17-22 |
| Mondial 2024, finale g1 `112966669924194882` (hors fenêtre) | `200`, 16 777 o | `200`, 18 368 o, `finished` |

→ Une game de 2025 coûte comme une game de 2026 (≈ **35,3 Ko**, 2 requêtes). Le flux ne limite pas l'historique : **c'est à Faille de le borner**.

---

## 2. La règle : `SeasonWindow` (LoLKit, pure)

### 2.1 Interprétation retenue

Ruling: **saison = année civile de `startDate` du tournoi** (règle existante conservée) ; **fenêtre = saison en cours N et saison précédente N − 1**, plus les tournois de saisons futures (annoncés, sans rien à lire avant leur début) — pourquoi : c'est la lecture littérale de « cette saison et celle d'avant, pas plus », elle ne demande aucune table par ligue, et l'API n'a pas d'autre notion de saison — coût si faux : un tournoi à cheval sur deux années compte dans l'année de son début (ex. une KeSPA Cup de décembre 2026 reste « saison 2026 » en janvier 2027 ; c'est voulu).

Ruling: **la fenêtre est un plafond, pas une cible** — ce qui est dans le périmètre *peut* être énuméré, lu, gardé, montré ; ce qui est dehors ne l'est **jamais**. Ce que la collecte lit vraiment reste piloté par `CrawlWanted` (équipes et ligues suivies, page ouverte, compétitions complètes) — pourquoi : « tous les tournois en cours de toutes les ligues » ferait 51 ligues à énumérer et des milliers de games ; Dan veut borner, pas étendre — coût si faux : un tournoi en cours d'une ligue non suivie (ex. EMEA Masters) n'a de données que si on suit la ligue ou si on ouvre une équipe dont c'est la ligue d'attache.

Ruling: **« données complètes » (toutes les équipes, pas seulement les suivies) pour les compétitions `SeasonWindow.completeLeagueSlugs = ["worlds", "msi", "first_stand", "demacia_cup"]`**, dans la fenêtre — pourquoi : Dan cite le Mondial et la Demacia Cup ; MSI et First Stand sont les autres internationaux que l'appli suit déjà (`League.internationalSlugs`) — coût si faux : ≈ 772 requêtes de collecte au total pour tout l'international 2025-2026 (2,6 sessions), en dernière priorité (§3.2).

Ruling: **`League.internationalSlugs` n'est pas modifié** (la Demacia Cup n'entre ni dans le calendrier par défaut, ni dans les +20 de « À ne pas rater », ni dans `BracketMasking`) — pourquoi : gel des fonctionnalités ; ces trois usages sont des comportements d'écran, pas du périmètre de données — coût si faux : la Demacia Cup n'apparaît au calendrier que si l'on suit la ligue (pilule « Demacia Cup » de l'écran Équipes) ; ses données de saison (pages d'équipe, classement) existent, elles.

Ruling: **ligues renommées : la saison précédente d'une ligue passe par ses prédécesseurs** `SeasonWindow.predecessors = ["lcs": ["lta_n", "lta_cross"], "cblol-brazil": ["lta_s", "lta_cross"]]`, pour la saison N − 1 seulement — pourquoi : mesuré, la LCS n'a aucun tournoi en 2025 ; sans cela, C9 (au Mondial ce soir contre KC) n'aurait pas de « Saison 2025 » — coût si faux : une table de 2 lignes à tenir à la main au prochain renommage.

### 2.2 Signature

Fichier `LoLKit/Sources/LoLKit/Season/SeasonWindow.swift` :

```swift
/// Périmètre des données (spec périmètre §2) : saison en cours N, saison précédente N − 1, tournois en cours. Pur.
public struct SeasonWindow: Sendable, Hashable {
    /// Jour de référence « yyyy-MM-dd », en UTC (comme les dates des tournois et `SeasonPlanning.day`).
    public let today: String
    public let currentSeason: Int                     // 2026
    public var previousSeason: Int { currentSeason - 1 }
    /// « 2025-01-01 » : premier jour du périmètre (date des games et du calendrier).
    public var startDay: String
    public var startDate: Date                         // 2025-01-01T00:00:00Z

    public init?(today: String)                        // nil si illisible
    public init(now: Date)                             // jour UTC de `now`

    public static let completeLeagueSlugs: Set<String> = ["worlds", "msi", "first_stand", "demacia_cup"]
    public static let predecessors: [String: [String]] = ["lcs": ["lta_n", "lta_cross"], "cblol-brazil": ["lta_s", "lta_cross"]]
    /// Garde-fou de l'exception « en cours » : commencé il y a au plus 400 jours.
    public static let liveOverrideMaxAgeDays = 400

    public enum Placement: Sendable, Equatable {
        case current        // saison N
        case previous       // saison N − 1
        case upcoming       // saison > N (annoncé ; rien à lire avant son début)
        case liveOverride   // plus ancien que N − 1 mais en cours (`isActive`), commencé il y a ≤ 400 jours
        case outside        // tout le reste, y compris dates illisibles
    }

    /// Saison d'un tournoi : année de `startDate`, sinon année de `endDate`, sinon nil.
    public static func season(of tournament: TournamentRef) -> Int?
    public func placement(of tournament: TournamentRef) -> Placement
    public func contains(_ tournament: TournamentRef) -> Bool          // placement != .outside
    /// Tournois du périmètre, du plus récent au plus ancien (`startDate`, puis id).
    public func tournaments(_ all: [TournamentRef]) -> [TournamentRef]
    /// Une date (début de game, de match du calendrier) est-elle dans le périmètre ? ≥ `startDate`.
    public func contains(date: Date) -> Bool
    /// Premier mois montrable par le calendrier : 1er janvier de N − 1 dans le fuseau de `calendar`.
    public func firstMonth(calendar: Calendar) -> Date
    /// Saison « de référence » d'un écran : N s'il y a des données en N, sinon N − 1 s'il y en a, sinon N.
    public func referenceSeason(seasonsWithData: Set<Int>) -> Int
    /// Pilules d'une équipe (§4.1) : « Saison N », ses tournois de N, « Saison N − 1 », ses tournois de N − 1 ;
    /// une saison sans tournoi joué n'a pas de pilule. Les tournois `liveOverride` vont avec la saison N.
    public func scopes(played: [TournamentRef]) -> [SeasonScope]
    /// Purge (§3.3) : ids de games hors périmètre. Tournoi connu → `!contains` ; inconnu → `startedAt < startDate`.
    public func outsideGameIds(_ games: [GameSummary], tournaments: [String: TournamentRef]) -> [String]
    /// Purge : ids de tournoi (fichiers `completed/`, `standings/`) hors périmètre. Connu → `!contains` ;
    /// inconnu → hors si le dernier match connu (`lastMatchStart`) est avant `startDate` ; inconnu sans date → gardé.
    public func outsideTournamentIds(_ ids: Set<String>, tournaments: [String: TournamentRef],
                                     lastMatchStart: [String: Date]) -> Set<String>
}
```

`SeasonScope` gagne deux champs (init avec valeurs par défaut, `PublicInitTests` mis à jour) :

```swift
public struct SeasonScope: Sendable, Hashable {
    public let tournamentIds: Set<String>
    public let label: String          // inchangé : « 2026 » ou le slug
    public let season: Int?           // nouveau : saison du périmètre (année, ou saison du tournoi)
    public let isLive: Bool           // nouveau : tournoi en cours aujourd'hui (pilule « · en cours »)
    public init(tournamentIds: Set<String>, label: String, season: Int? = nil, isLive: Bool = false)
}
```
`SeasonScope.season(_:tournaments:)` et `.tournament(_:)` restent (remplissent les nouveaux champs) ; `CrawlPlanner.seasonTournaments(_:year:)` reste pour compatibilité mais n'est plus appelé par l'appli.

### 2.3 Cas limites (tous testés, §6)

| Cas | Règle | Exemple réel ou synthétique → résultat attendu |
|---|---|---|
| Tournoi de N | `.current` | `lec_split_3_2026` le 15/10/2026 → `.current` |
| Tournoi de N − 1 | `.previous` | `worlds_2025` → `.previous` |
| Tournoi de N − 2 et avant | `.outside` | `worlds_2024` → `.outside` ; LEC : 28 sur 34 |
| À cheval sur le Nouvel An | saison = année du **début** | `champions_winter_2014` (2013-11-15 → 2014-01-25) → saison 2013 → `.outside` ; synthétique `{2026-12-20 → 2027-01-10}` le 2027-01-05 → `.previous` (et `isActive`), le 2028-01-02 → `.outside` |
| Pas de `startDate` | saison = année de `endDate` | synthétique `{"" → 2026-11-01}` → `.current` ; `{"" → 2024-05-01}` → `.outside` |
| Ni début ni fin (ou illisibles) | `.outside` (jamais énuméré) | synthétique `{"" → ""}` → `.outside` |
| Tournoi plus ancien **en cours** | `.liveOverride` si `isActive(today)` et `startDate ≥ today − 400 j` | synthétique `{2024-12-28 → 2026-01-05}` le 2026-01-03 → `.liveOverride` |
| Date de fin aberrante | le garde-fou de 400 jours l'exclut | `eu_lcs_summer_2013` réel (fin 2022) → `.outside` ; synthétique même tournoi avec fin `2026-12-31` le 15/10/2026 → `isActive` vrai **mais** `.outside` |
| Saison future annoncée | `.upcoming` (dans le périmètre ; non lu tant que non commencé : règle existante `startDate ≤ today`) | synthétique `lec_split_1_2027 {2027-01-16 → …}` le 2026-12-20 → `.upcoming` |
| Bascule d'année | jour **UTC** | `SeasonWindow(now: 2026-12-31T23:30:00Z).currentSeason == 2026` (00:30 à Paris : 2026 encore 30 min, accepté) ; `2027-01-01T00:00:00Z` → 2027, `startDay == "2026-01-01"` |
| Game sans tournoi connu | date de début de la game | `startedAt` 2024-11-02T14:35:43.676Z → hors ; 2025-01-18T17:09:12.350Z → gardée |

Ruling: **l'exception « en cours » a un garde-fou de 400 jours** — pourquoi : mesuré, l'API contient des dates de fin aberrantes (`eu_lcs_summer_2013` finit en 2022) ; sans garde-fou, une erreur de ce genre ferait rentrer 2013 — coût si faux : un vrai tournoi de plus de 13 mois commencé avant N − 1 et encore en cours serait ignoré (aucun n'existe).

---

## 3. Où la règle s'applique

### 3.1 Énumération (`App/Season/SeasonPlanning.swift`, `SeasonCrawler.swift`)

- `SeasonPlanning.startedTournaments` : `window.tournaments(…)` + `startDate ≤ today` remplace `CrawlPlanner.seasonTournaments(year:)`. **Aucune requête `getCompletedEvents` / `getStandings` pour un tournoi `.outside`.** `getTournamentsForLeague` reste 1 requête par ligue et par 24 h (c'est l'index ; il faut le lire pour filtrer).
- `SeasonPlanning.leagueIds` ajoute : les ligues `completeLeagueSlugs` (donc `demacia_cup`, id lu dans `getLeagues` par slug, jamais en dur) ; les prédécesseurs (`predecessors`) des ligues énumérées, **dont seuls les tournois `.previous` sont lus**.
- `SeasonStore.loadStandings(tournamentId:)` et `schedulePage` : refusent un tournoi hors fenêtre / ne demandent pas de page `older` dont tout le mois cible est avant `firstMonth` (§3.4).
- `SeasonContext` gagne `window: SeasonWindow` (construit une fois par tour depuis `now`).

### 3.2 Collecte (`CrawlPlanner`, LoLKit)

`CrawlWanted` gagne :
```swift
public let allowedTournamentIds: Set<String>        // tournois .current/.previous/.upcoming/.liveOverride énumérés
public let previousSeasonTournamentIds: Set<String> // .previous
public let completeTournamentIds: Set<String>       // tournois des completeLeagueSlugs dans la fenêtre
public let liveCompleteStageMatchIds: Set<String>   // remplace worldsStageMatchIds : étape en cours de CHAQUE
                                                    // tournoi complet en cours (Mondial 2026, Demacia Cup 2026)
```
Ruling: **aucun job pour un match dont le tournoi n'est pas dans `allowedTournamentIds`** (filtre en tête de `jobs`, avant même le masquage) — pourquoi : défense en profondeur, testable (« zéro URL de game de `worlds_2024` ») — coût si faux : aucun.

Ruling: **ordre de priorité étendu, les groupes 0-4 gardent leur numéro** (les tests existants restent vrais) :

| Groupe | Contenu | Palier |
|---|---|---|
| 0 | page d'équipe ouverte (non suivie) : tournoi en cours | A |
| 1 | équipes suivies, **saison N** (et tournois `.liveOverride`) | A |
| 2 | étape en cours de chaque **tournoi complet en cours** (Mondial 2026 : `play_ins` ; Demacia Cup 2026 : `playoffs`) | A |
| 3 | ligues suivies, saison N (tournoi en cours d'abord) | A |
| 4 | palier B des équipes suivies (tournois en cours) | B |
| **5** | reste des tournois complets en cours (étapes déjà jouées) | A |
| **6** | équipes suivies, **saison N − 1** | A |
| **7** | tournois complets terminés de la fenêtre (MSI, First Stand, Mondial 2025…), saison N d'abord, puis le plus récent | A |
| **8** | ligues suivies, saison N − 1 | A |

Pourquoi : la saison en cours et le direct d'abord, l'historique ensuite, budget de 300 requêtes par session inchangé — coût si faux : la « Saison 2025 » d'une équipe suivie se remplit à partir de la 2e session (KC : 108 games = 216 requêtes).

Budget disque (remplace §1.7 de la spec saison) : `CrawlPlanner.evictions(_:followedTeamIds:allowedTournamentIds:previousSeasonTournamentIds:limit:)`, `diskLimit = 4_000` (≈ 9 Mo palier A). Ordre : (1) **toujours** les games hors fenêtre, quelles que soient les équipes ; (2) au-delà de la limite, saison N − 1 des équipes non suivies, la plus ancienne d'abord ; (3) puis saison N des équipes non suivies. Une game d'équipe suivie **dans la fenêtre** n'est jamais supprimée. Ruling — pourquoi : la fenêtre borne déjà le volume (scénario LEC + LCK suivies : 2 126 games, au-dessus de l'ancien plafond de 2 000) — coût si faux : 4 000 × 2,2 Ko ≈ 8,8 Mo au pire.

### 3.3 Cache disque : purge et migration

Ruling: **la purge du dossier `season/` tourne à chaque lecture du disque (lancement), la purge des caches du Détail une fois par fenêtre** — pourquoi : la première est gratuite (tout est déjà décodé en mémoire), la seconde lit des fichiers lourds (`details/` ≈ 200 Ko) ; la fenêtre change une fois par an (1er janvier UTC) — coût si faux : au 1er janvier, les fichiers du Détail de N − 2 survivent jusqu'au lancement suivant.

Déroulé dans `SeasonDisk.load()` (hors du fil principal, avant `publish`) :
1. Lire tout comme aujourd'hui (games, `tournaments/`, `completed/`, `standings/`, `crawl.json`).
2. `tournaments/<leagueId>.json` : en mémoire, filtré par `window.tournaments` ; le fichier est **réécrit filtré** s'il contenait des tournois hors fenêtre (rien d'avant N − 1 n'est gardé, même comme index).
3. `window.outsideTournamentIds` sur les clés de `completed/` et `standings/` (avec `lastMatchStart` = début du dernier match de `completed/`) → suppression des deux fichiers de chaque id.
4. `window.outsideGameIds` → suppression de `games/<id>.json`.
5. `crawl.json` : on retire les échecs des games qu'aucun match restant ne référence ; réécrit si changé.
6. Marqueur `season/window.json` = `{"v": 1, "startDay": "2025-01-01"}`. **Absent ou `startDay` différent** → purge des caches du Détail : `replays/<gameId>.json` (champ `firstFrame`), `details/<gameId>.json` (`details.frames[0].rfc460Timestamp`), `spells/<matchId>.json` (plus récent `openings[*].start`) : supprimé si la date lue est avant `startDate` ; **date illisible ou absente → gardé**. Puis écriture du marqueur (après la purge, jamais avant).

Garanties (« supprimer l'ancien cache sans risque, une fois ») : la liste des fichiers à supprimer vient **uniquement** des fonctions pures testées de `SeasonWindow` ; suppressions via `DiskCache.url` (chemins sûrs, sous `cache/`) ; **jamais** `FileStore` (suivis, réglages, `revealedMatchIds`, Live Activities) ; un fichier illisible n'est jamais supprimé par la purge ; un schéma `GameSummary` plus récent (`newerGameIds`) n'est jamais supprimé ; le marqueur n'est écrit qu'à la fin, donc une purge interrompue est refaite au lancement suivant (idempotente). Aujourd'hui, l'appli n'a rien écrit avant 2026 dans `season/` : la première exécution ne supprime normalement que d'éventuels fichiers du Détail ouverts depuis le calendrier sur un mois de 2024 (§3.4).

### 3.4 `SeasonStore` : point d'étranglement des écrans

Ruling: **`SeasonStore` n'expose que la fenêtre** : `tournaments`, `standings`, `matches`, `games` ne contiennent jamais rien de `.outside` — filtré à `publish` (disque), à `record(tournaments:)` (liste filtrée avant mémoire et disque), à `record(completed:)` / `record(standings:)` (refus si le tournoi n'est pas dans la fenêtre), à `rejoin` (un match dont le tournoi est inconnu ou hors fenêtre n'entre pas dans `matches`), à `record(_ game:)` (refus si son tournoi est hors fenêtre) — pourquoi : tous les écrans (page équipe, joueur, duels, Accueil, classements, onboarding) lisent `store.season.*` ; un seul filtre les borne tous, y compris un écran oublié — coût si faux : aucun ; un écran ne peut plus montrer 2024 même par erreur.

`SeasonStore` gagne `window: SeasonWindow` (recalculé quand le jour change : clé de mémoïsation `day` déjà présente) et :
```swift
func scopes(forTeam teamId: String, now: Date) -> [SeasonScope]       // window.scopes(played:)
func referenceSeason(forTeams ids: [String]) -> Int                    // saisons où ces équipes ont un match
func games(inSeason season: Int) -> [GameSummary]                      // par tournoi, jamais par date
func matches(inSeason season: Int) -> [SeasonMatch]
```
Ruling: **appartenance à une saison = par tournoi, jamais par la date de la game** — pourquoi : une game de janvier d'un tournoi commencé en décembre appartient à la saison du tournoi (cohérent avec les pilules et les classements) — coût si faux : aucun ; la date ne sert qu'au calendrier et aux fichiers sans tournoi connu.

### 3.5 Écrans

| Écran | Avant | Après |
|---|---|---|
| **Page équipe** — pilules (`App/TeamPage/TeamPageView.swift`) | « Saison 2026 » + tournois de 2026 | « Saison 2026 », tournois de 2026 (« Mondial · en cours », « LEC Split 3 »…), « Saison 2025 », tournois de 2025 (« LEC Summer 2025 », « Mondial 2025 »…). Pilule par défaut = **saison de référence** (`referenceSeason`) : « Saison 2026 » toute l'année, « Saison 2025 » début janvier tant que l'équipe n'a pas joué en 2026… en 2027 |
| Page équipe — face-à-face | `headToHead` sur tous les matchs connus (2026) | sur **toute la fenêtre**, titre « Face-à-face 2025-2026 » (KC-G2 : « KC 5 – 8 G2 », 13 matchs) |
| Page équipe — classement, prochains matchs, effectif | tournoi en cours | inchangé (le tournoi en cours est dans la fenêtre par construction) |
| **Page joueur** (`App/PlayerPage/PlayerPageView.swift`) | pilules de son équipe ; sans pilule : **toutes** les games | mêmes pilules que la page équipe ; sans pilule : la saison de référence (jamais « tout ») |
| **Duels** joueurs (`DuelSection`, `DuelView`) | `Duel.players` sur toutes les games | games de la **saison de référence des deux équipes** ; ligne « Stats de la saison 2026 » sous le titre |
| Duel d'équipes (`TeamDuelCard`) | « Cette saison : KC 2 – 6 G2 » sur tous les matchs | bilans et moyennes : saison de référence ; face-à-face : fenêtre, « 2025-2026 : KC 5 – 8 G2 » |
| Sélecteur de duel | joueurs du catalogue + games en cache | inchangé (le cache est déjà borné) |
| **Classements** (`StandingsView`) | tout tournoi demandé | un tournoi hors fenêtre n'est jamais lu ; écran « Classement trop ancien · Faille garde les saisons 2025 et 2026 » (garde, inatteignable par les liens existants) |
| **Calendrier** (`SeasonCalendarView`, `CalendarEvents`) | pages `older` sans limite (jusqu'en 2013) | mois minimal = `firstMonth` (janvier 2025) : flèche « mois précédent » désactivée, pied « Faille ne remonte pas avant janvier 2025 » ; `CalendarEvents.merged` écarte les matchs avant `startDate` ; pas de page `older` quand le mois voulu est avant `firstMonth` |
| **Accueil** — joueurs en forme | « Semaine / Saison » sur toutes les games | « Semaine » inchangé (7 jours) ; « Saison » → **« Saison 2026 »** = saison de référence des games lues |
| Accueil — activité récente | séries et record de kills sur tout le cache | séries (`.streak`) et record de kills (`.killRecord`) sur la saison de référence ; le reste (≤ 7 jours, ≤ 6 h) inchangé |
| Accueil — « À ne pas rater » | revanche = matchs connus | revanche = matchs de la saison de référence (comportement « cette saison » conservé) |
| Accueil — direct, bandeau, résultats récents | calendrier courant | inchangé (dates récentes) |
| **Onboarding** (`RootView` `OnboardingHost`) | Mondial « en cours » (`currentTournamentId`) | inchangé dans le code : `currentTournamentId` lit les tournois filtrés → `worlds_2026`, sinon `worlds_2025` (test hébergé) |
| **Ligues** (lien « Classement ») | tournoi en cours | inchangé (dans la fenêtre par construction) |
| **Réglages > À propos** | source des données | + ligne « Données : tournois en cours, saisons 2026 et 2025 » |

Ruling: **une seule « saison de référence » pour tout ce qui dit « saison » sans année explicite** (pilule par défaut, duels, joueurs en forme, activité, revanche) : N s'il y a des données en N, sinon N − 1 — pourquoi : en janvier, avant le premier match de N, les écrans resteraient vides ; l'année est toujours écrite (« Saison 2026 »), donc rien n'est ambigu — coût si faux : en janvier, « Saison 2026 » s'affiche alors que l'année est 2027 (c'est exact : c'est la dernière saison jouée).

Ruling: **le face-à-face couvre toute la fenêtre (deux saisons)** — pourquoi : c'est l'historique que Dan demandait (« face-à-face historique ») et la seule stat que deux saisons rendent plus juste (KC-G2 : 8 matchs en 2026 seul, 13 sur la fenêtre) — coût si faux : un titre « 2025-2026 » de plus à lire.

### 3.6 Textes (`SeasonLabels`, catalogue fr/en)

| Clé (fr) | en | Où |
|---|---|---|
| « Saison \(year) » (existant) | “\(year) season” | pilules, joueurs en forme |
| « \(tournoi) · en cours » | “\(tournament) · live” | pilule d'un tournoi `isLive` |
| « \(tournoi) \(année) » (tournoi de N − 1 : l'année reste) | “\(tournament) \(year)” | « Mondial 2025 », « LEC Summer 2025 » — un tournoi de N garde son nom court (« Mondial », « LEC Split 3 ») |
| « Demacia Cup » | “Demacia Cup” | `SeasonLabels.league(slug: "demacia_cup")` et `tournament(slug:)` (deux mots, comme `first_stand` ; sans cela le slug donnerait « DEMACIA Cup ») |
| « Face-à-face \(N−1)-\(N) » | “Head-to-head \(N−1)–\(N)” | page équipe |
| « \(N−1)-\(N) : \(a) \(x) – \(y) \(b) » | “\(N−1)–\(N): …” | duel d'équipes (remplace « Cette saison : … ») |
| « Stats de la saison \(year) » | “\(year) season stats” | duels de joueurs |
| « Faille ne remonte pas avant janvier \(N−1) » | “Faille doesn't go back before January \(N−1)” | calendrier |
| « Classement trop ancien · Faille garde les saisons \(N−1) et \(N) » | “Standings too old · Faille keeps the \(N−1) and \(N) seasons” | classements |
| « Données : tournois en cours, saisons \(N) et \(N−1) » | “Data: live tournaments, \(N) and \(N−1) seasons” | À propos |

Les années viennent toujours de `SeasonWindow` (jamais « 2025 » en dur).

---

## 4. Volumes mesurés (palier A ≈ 35,3 Ko / game, 2 requêtes ; 2,05 s / requête ; 300 requêtes / session)

| Périmètre | Games | Requêtes (games + énumération) | Données | Durée | Sessions | Disque |
|---|---|---|---|---|---|---|
| Ancien périmètre, KC suivie (2026 seul) | 113 | 226 + ≈ 12 | ≈ 3,9 Mo | ≈ 8 min | 0,8 | ≈ 0,25 Mo |
| Mondial 2025 + 2026 + Demacia Cup 2026 (aujourd'hui) | 146 | 292 + 8 = **300** | ≈ 5,0 Mo | ≈ 10 min | 1,0 | ≈ 0,31 Mo |
| Tous les « complets » 2025-2026 (Mondial, MSI, First Stand, Demacia Cup) — aucun suivi | **377** | 754 + 18 = **772** | ≈ 13,0 Mo | ≈ 26 min | 2,6 | ≈ 0,81 Mo |
| KC 2025-2026 (LEC + internationaux) | **221** (113 + 108) | 442 + 13 = 455 | ≈ 7,6 Mo | ≈ 16 min | 1,5 | ≈ 0,47 Mo |
| **KC suivie + complets** (configuration probable de Dan) | **570** | 1 140 + 31 = **1 171** | ≈ 19,6 Mo | ≈ 40 min | **3,9** | ≈ 1,2 Mo |
| + LEC suivie (ligue entière 2025-2026) | 1 068 | 2 136 + 31 = 2 167 | ≈ 36,8 Mo | ≈ 74 min | 7,2 | ≈ 2,3 Mo |
| + LCK suivie | 2 126 | 4 252 + 44 = 4 296 | ≈ 73,3 Mo | ≈ 147 min | 14,3 | ≈ 4,6 Mo |
| Exclu par la fenêtre, exemple : Mondial 2024 | 106 | 212 évitées | 3,7 Mo évités | | | |

Énumération : 1 requête par ligue et par 24 h (142 o à 3,9 Ko) ; 2 requêtes par tournoi de la fenêtre déjà commencé, une fois pour un tournoi terminé (`getCompletedEvents` 8-78 Ko + `getStandings` 15-32 Ko). Tournois de la fenêtre par ligue : Mondial 2, MSI 2, First Stand 2, Demacia Cup 1, LEC 6, LCK 6, EMEA Masters 7, LFL 6, LPL 6, LCP 6, LCS 3 + prédécesseurs 2025 (LTA North 3, LTA Cross 2). Les 19 `getCompletedEvents` 2025-2026 (internationaux + LEC + LCK) pèsent **885 199 o** au total.

Lecture : la configuration « KC + complets » se remplit en ≈ 4 sessions au premier plan ; l'ordre de §3.2 donne la saison 2026 de KC et l'étape en cours du Mondial dès la 1re session (113 + étape ≈ 250 requêtes).

---

## 5. Hors périmètre de ce lot

- Pas de nouvelle source (Leaguepedia interdit ; la Demacia Cup 2025 **n'existe pas** dans l'API : on ne la reconstruit pas).
- Pas d'énumération des 51 ligues pour trouver « tous les tournois en cours » (plafond, pas cible : §2.1).
- `League.internationalSlugs`, widgets, Live Activity, notifications : inchangés (leurs données sont déjà du direct ou du calendrier courant).
- `AppSettings.revealedMatchIds` : non purgé (ids sans contenu, nécessaires à l'anti-spoiler).

---

## 6. Tests d'acceptation (valeurs exactes)

### 6.1 LoLKit (`SeasonWindowTests.swift`, `CrawlPlannerTests.swift`, `SeasonStatsTests.swift`), fixtures `Fixtures/season/perimetre/`

1. `SeasonWindow(today: "2026-10-15")` : `currentSeason == 2026`, `previousSeason == 2025`, `startDay == "2025-01-01"`.
2. `getTournamentsForLeague_worlds.json` : `tournaments(…)` = `[worlds_2026, worlds_2025]` (ids `115660540725177488`, `113475452383887518`, dans cet ordre) ; `worlds_2026` `.current`, `worlds_2025` `.previous`, les 9 autres `.outside`.
3. `_lec.json` : 6 dans la fenêtre (les 6 ids de §1.2, du plus récent au plus ancien), 28 `.outside` ; `eu_lcs_summer_2013` `.outside`.
4. `_lck.json` : 6 dans la fenêtre, 31 dehors ; `champions_winter_2014` `.outside`, `season(of:) == 2013`.
5. `_emea_masters.json` : 7 dans la fenêtre ; `emea_masters_summer_2026` `.current` et `isActive(today: "2026-10-15") == true`.
6. `_demacia_cup.json` : 1 tournoi, `.current`, actif ; `_msi.json` et `_first_stand.json` : 2 chacun.
7. `SeasonWindow(today: "2027-01-05")` : `worlds_2025` `.outside`, `worlds_2026` `.previous`, `lec_split_1_2026` `.previous`, `startDay == "2026-01-01"`.
8. Cas synthétiques du tableau §2.3 (sans début, sans dates, à cheval, `liveOverride` le 2026-01-03, garde-fou de 400 jours sur `eu_lcs_summer_2013` à fin `2026-12-31`, `.upcoming`, bascule UTC à 23:30 / 00:00).
9. `referenceSeason` : `[2026, 2025] → 2026`, `[2025] → 2025`, `[] → 2026`.
10. `scopes(played:)` avec les 4 tournois de KC en 2026 (LEC S1-S3, MSI) et 4 en 2025 (LEC winter/spring/summer, First Stand) : 10 périmètres, dans l'ordre « 2026 », `lec_split_3_2026`, `msi_2026`, `lec_split_2_2026`, `lec_split_1_2026`, « 2025 », `lec_summer_2025`, `lec_spring_2025`, `first_stand_2025`, `lec_winter_2025` ; `season` = 2026 ×5 puis 2025 ×5 ; aucun `isLive`. Avec `worlds_2026` ajouté le 2026-10-15 : 11 périmètres, `worlds_2026` en 2e position, `isLive == true`.
11. `outsideGameIds` : la game `115548681803406304` (fixture existante, `lec_split_3_2026`) gardée ; sa copie avec `tournamentId` `112966669920590211` (`worlds_2024`) → hors ; copie au tournoi inconnu et `startedAt` 2024-11-02T14:35:43.676Z → hors ; inconnu et 2025-01-18T17:09:12.350Z → gardée.
12. `outsideTournamentIds` : `{112966669920590211, 113475452383887518, "inconnu-ancien", "inconnu-sans-date"}` avec `lastMatchStart["inconnu-ancien"] = 2024-11-02T14:00:00Z` → `{112966669920590211, "inconnu-ancien"}`.
13. `SeasonStats.team("KC", …)` sur `completed_kc_g2_2024_2026_reduced.json` (matchs construits avec `MatchTeam.id` = code) : saison 2026 → séries **33-13**, games **72-41** ; saison 2025 → **26-14**, **64-44** ; G2 2026 → 33-15 / 79-41 ; G2 2025 → 28-14 / 62-41.
14. `headToHead("KC", "G2")` : sur 2026 **2-6**, sur 2025 **3-2**, sur la fenêtre **5-8**, `matchIds.count == 13`, premier (le plus récent) du 2026-09-06.
15. `CrawlPlanner.jobs` (KC suivie, rien en cache, aucun masque, `previousSeasonTournamentIds` = les 4 tournois 2025 de KC) : **221** jobs palier A ; les **113** premiers en priorité 1, les **108** suivants en priorité 6 ; aucun job pour un match de `worlds_2024` même s'il est fourni (`allowedTournamentIds` ne le contient pas) ; avec `liveCompleteStageMatchIds` = matchs de l'étape `playoffs` de `getStandings_demacia_cup_2026.json`, leurs games en priorité 2.
16. `evictions` : 3 games hors fenêtre d'une équipe **suivie** → supprimées même sous la limite ; au-delà de `limit`, les games N − 1 non suivies partent avant celles de N.
17. `PublicInitTests` : `SeasonWindow(today:)`, `SeasonScope(…season:isLive:)`, `CrawlWanted(…)` construits depuis l'extérieur du module.

### 6.2 Appli (tests hébergés `Tests/FailleTests`, faux transport)

18. **Purge et migration** : `DiskCache` temporaire avec `season/games/{115548681803406304, 112966669924194882}.json` (la 2e au tournoi `worlds_2024`), `season/completed/112966669920590211.json`, `season/standings/112966669920590211.json`, `season/tournaments/98767975604431411.json` (les 11 tournois du Mondial), `replays/112966669924194882.json` (`firstFrame` 2024-11-02), `replays/115548681803406304.json`, un `replays/illisible.json` ; pas de marqueur → après `loadFromDisk` : les 4 fichiers de 2024 supprimés, `illisible.json` gardé, `tournaments/98767975604431411.json` réécrit avec **2** tournois, marqueur `{"v":1,"startDay":"2025-01-01"}` écrit ; second chargement : aucun fichier de `replays/` relu (espion de lecture).
19. **Collecte** : faux transport servant les fixtures de §1 ; une passe complète pour KC suivie → aucune URL contenant `112966669920590211` ni un id de game de `worlds_2024` ; `getTournamentsForLeague` demandé une fois par ligue ; `getCompletedEvents` demandé pour `demacia_cup_2026` (ligue complète, non suivie) ; ≥ 2 s entre deux requêtes, arrêt à 300.
20. **Store** : `record(completed:)` pour `worlds_2024` → ignoré (`matches` inchangé) ; `scopes(forTeam:)` de KC = 10 pilules (test 10) ; `currentTournamentId(leagueId: worlds)` = `115660540725177488` au 2026-10-15.
21. **Calendrier** : `SeasonCalendarView` modèle — mois précédent impossible depuis janvier 2025 (fuseau Europe/Paris, `firstMonth` = 2025-01-01T00:00+01:00) ; `CalendarEvents.merged` écarte un match du 2024-12-31T23:00Z.
22. Planches PNG : page équipe KC avec les pilules « Saison 2026 … Saison 2025 … » et « Mondial · en cours » ; duel d'équipes « 2025-2026 : KC 5 – 8 G2 » ; calendrier en janvier 2025 (flèche désactivée, pied de page). `scripts/strings-check.py` vert (chaînes de §3.6 avec leur `en`).

---

## 7. Découpage pour l'exécution

Principes inchangés : un fichier existant n'est modifié que par **une** tâche ; LoLKit en TDD (`bash scripts/lolkit.sh test`) ; l'appli par tests hébergés + planches ; CI verte avant fusion.

| Id | Tâche | Crée | Modifie | Dépend de | Taille |
|---|---|---|---|---|---|
| **W1** | `SeasonWindow` + périmètres | `Season/SeasonWindow.swift`, `Tests/SeasonWindowTests.swift`, `Fixtures/season/perimetre/*` (§1) | `Season/SeasonScope.swift` (`season`, `isLive`), `Tests/SeasonStatsTests.swift` (tests 13-14), `Tests/PublicInitTests.swift` | — | M |
| **W2** | Collecte et budget disque | — | `Season/CrawlPlanner.swift` (`CrawlWanted` étendu, groupes 5-8, `allowedTournamentIds`, `evictions`, `diskLimit = 4_000`), `Tests/CrawlPlannerTests.swift` | W1 (type seulement) | M |
| **A1** | Store, énumération, purge | `App/Season/SeasonPurge.swift` (sondes `replays/`, `details/`, `spells/`, marqueur), tests hébergés 18-20 | `App/Season/SeasonStore.swift`, `SeasonDisk.swift`, `SeasonPlanning.swift`, `SeasonCrawler.swift`, `App/Store/AppStore+Season.swift` (`seasonContext.window`, `currentTournamentId` filtré) | W1, W2 | L |
| **A2** | Pages équipe, joueur, duels | planches PNG | `App/Season/SeasonLabels.swift` (« · en cours », année des tournois N − 1, Demacia Cup, fenêtre), `App/TeamPage/TeamPageView.swift`, `TeamPageSections.swift`, `App/PlayerPage/PlayerPageView.swift`, `App/Duel/DuelSection.swift`, `DuelView.swift`, `DuelBars.swift` | A1 | M |
| **A3** | Accueil, calendrier, classements, À propos | test hébergé 21, planche calendrier | `App/Home/HomeStore.swift` (entrées filtrées par saison de référence), `HotPlayersSection.swift` (« Saison 2026 »), `App/Calendar/SeasonCalendarView.swift`, `CalendarModel.swift`, `App/Standings/StandingsView.swift`, `App/Settings/SettingsView.swift` | A1 | M |
| **I** | Chaînes et intégration | — | `Resources/Localizable.xcstrings` (toutes les chaînes de §3.6, fr + en), `docs/superpowers/notes/2026-10-14-checklist-iphone.md` (section G : périmètre) | A2, A3 | S |

**Vagues** : 1. W1 → W2 (W2 peut démarrer dès que la signature de `SeasonWindow` est poussée). 2. A1. 3. A2 ‖ A3 (fichiers disjoints ; `SeasonLabels.swift` à A2 seul, A3 l'appelle sans le modifier). 4. I, CI verte, IPA, relecture ciblée « rien d'avant 2025 » (grep des appels à `store.season.games` / `.matches` hors `SeasonStore` : chacun doit passer par une saison ou par la fenêtre).

Critères de fin : tests 1-17 verts en local ; 18-22 verts en CI iOS ; aucune occurrence de `2025`, `2024` en dur dans `App/` ni `LoLKit/Sources/` (hors commentaires et fixtures) ; le lien profond des notifications et les tests anti-spoiler existants inchangés et verts.

---

## 8. Rulings (récapitulatif, avec le coût si faux)

1. Saison = année du début du tournoi ; fenêtre = N et N − 1 (+ saisons futures annoncées) — coût : un tournoi à cheval compte dans l'année de son début.
2. La fenêtre est un plafond, la collecte reste pilotée par les suivis — coût : un tournoi en cours d'une ligue non suivie n'a de données qu'en la suivant.
3. Données complètes pour Mondial, MSI, First Stand, Demacia Cup ; `League.internationalSlugs` inchangé — coût : ≈ 772 requêtes d'historique international en fond, en dernière priorité ; Demacia Cup absente du calendrier sans suivi.
4. Exception « en cours » avec garde-fou de 400 jours — coût : un tournoi de plus de 13 mois serait ignoré (aucun n'existe).
5. Prédécesseurs LCS → LTA North / Cross, CBLOL → LTA South / Cross pour N − 1 — coût : une table à tenir à la main.
6. `SeasonStore` n'expose que la fenêtre ; appartenance à une saison par tournoi — coût : aucun.
7. Purge du dossier saison à chaque lancement, des caches du Détail une fois par fenêtre (marqueur `season/window.json`), jamais un fichier illisible ni `FileStore` — coût : au 1er janvier, les caches du Détail de N − 2 survivent jusqu'au lancement suivant.
8. Une « saison de référence » (N si données, sinon N − 1) partout où l'on dit « saison » ; face-à-face sur la fenêtre « 2025-2026 » ; groupes de collecte 5-8 après les 0-4 existants ; plafond disque 4 000 games — coût : la « Saison 2025 » d'une équipe suivie se remplit à partir de la 2e session.
