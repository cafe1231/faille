# Fonctionnalités (LoLKit) — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** donner à LoLKit toute la logique pure du lot « Fonctionnalités » — choix du stream et des rediffusions, sélection et texte des notifications de début de match, Data Dragon (version, liens d'images, catalogues fr_FR), flux `livestats/v1/details`, sorts d'invocateur des games terminées par Leaguepedia, fil des événements et courbe de l'écart de gold —, testée sur de vraies réponses réduites, pour que l'appli n'ait plus qu'à afficher.

**Architecture :** six tâches **indépendantes et disjointes en fichiers**, exécutées en parallèle (un worktree et une branche chacune), fusionnées ensuite dans `main` par le contrôleur. Chaque tâche crée ses propres fichiers sources (`Media/`, `Reminders/`, `Leaguepedia/`, `Timeline/`, `API/LoLClient+Details.swift`, `Models/GameDetails.swift`), ses tests et ses fixtures ; les deux seuls fichiers existants modifiés ont chacun **une seule** tâche propriétaire (`Models/MatchEvent.swift` → T1, `API/LoLClient.swift` → T4). Aucune tâche ne dépend d'une autre : chacune ne consomme que du code déjà présent à `HEAD` (75ff688).

**Tech Stack :** Swift 6.2 (mode Swift 6, concurrence stricte), Foundation seule, Swift Testing, Docker `swift:6.2` via `scripts/lolkit.sh` (un volume de compilation par worktree), CI GitHub `LoLKit` (Linux + macOS, déclenchée par tout push touchant `LoLKit/**`, branches comprises), `curl` + `python -I` pour capturer et réduire les fixtures.

**Spec :** `docs/superpowers/specs/2026-10-14-faille-fonctionnalites-design.md` (principes, §1 « Regarder » / « Revoir », §2 notifications, §3 draft et builds, §4 fil des événements, §5 courbe de gold, Vérification) et ses notes `docs/superpowers/notes/2026-10-14-idees.md` ; spec principale `docs/superpowers/specs/2026-10-13-faille-design.md` §4 (données ; règle des 80 s : une fenêtre dont la fin a moins de 80 s est refusée, `LiveStatsTime.delays`) et §8 (anti-spoiler ; `Presenter.nextLine`, règles F1 et C). Ce plan ne couvre que **LoLKit** ; l'appli (boutons, notifications iOS, caches disque des images et des réponses, écrans) fera l'objet d'un plan séparé qui consomme les « Produces » ci-dessous.

## Global Constraints

- LoLKit n'importe que **Foundation** (ni SwiftUI, ni UserNotifications, ni WidgetKit) ; Swift 6.2, mode Swift 6 : tout type public nouveau est `Sendable` ; **aucun avertissement** de compilation.
- TDD : test qui échoue → `bash scripts/lolkit.sh test --filter <Suite>` → implémentation → même commande verte → `bash scripts/lolkit.sh test` complet vert. Docker Desktop doit tourner. Les commandes se lancent depuis la racine du worktree, dans Git Bash.
- Fixtures **réelles et réduites** : chaque fixture nouvelle se capture avec la commande `curl` donnée et se réduit avec le script `python -I` donné ; les réponses brutes vont dans un dossier vide créé par `mktemp -d` (jamais dans le dépôt) ; le script est passé sur l'entrée standard, les chemins en arguments. Chaque fixture a une empreinte `sha256sum` attendue : si elle diffère, s'arrêter et le signaler (ne pas ajuster les tests).
- Décodage **tolérant** (spec §4.2) : tout champ non essentiel est optionnel ou prend une valeur neutre ; un élément illisible est ignoré, jamais tout le décodage.
- **Aucun secret** : seule clé, la clé publique lolesports déjà dans `LoLClient.publicAPIKey` ; livestats, Data Dragon et Leaguepedia sans clé ; Leaguepedia reçoit l'en-tête `User-Agent: Faille (usage personnel)`.
- **Aucun bundle ID ni nom de groupe en dur** : l'identifiant d'une notification est `match-start-<matchId>`, indépendant de l'appli.
- **Anti-spoiler** (spec fonctionnalités, principes ; spec §8) : la seule décision d'affichage prise dans LoLKit est `MatchReminders.plan`, qui passe par `Presenter.nextLine` (F1 + C). Les autres fonctions sont pures et ne lisent rien d'elles-mêmes : l'appli ne les appelle pas (et ne fait aucune requête) pour un match masqué — leur documentation le rappelle.
- Identifiants en anglais, commentaires et textes en français, fins de ligne LF (`.gitattributes` : `* text=auto eol=lf`).
- **Une tâche ne touche que les fichiers de sa ligne de la « Matrice des fichiers »** : ni `Package.swift`, ni `Tests/LoLKitTests/Support/*`, ni les fixtures existantes, ni un fichier source d'une autre tâche.
- Commits : `git commit -m "<message>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"` (adresse noreply déjà configurée). Chaque tâche pousse **sa branche** (`git push -u origin <branche>`) et vérifie la CI `LoLKit` sur cette branche ; elle ne pousse jamais sur `main` (le contrôleur fusionne).

## Décisions prises par ce plan (au-delà de la spec)

- **Notifications : au plus une par équipe suivie.** `Presenter.nextLine` ne montre que le *prochain* match d'une carte ; la règle « seulement si `nextLine` le montre » retient donc au plus un match par équipe suivie (son prochain), la limite de 60 restant une garde. C'est aussi le plus sûr : le match d'après n'est programmé qu'au rafraîchissement suivant, quand F1 a pu masquer la ligne. `TeamCards.build(… live: nil …)` : seul le calendrier compte (son match `inProgress` sert de « dernier match » à F1). Notification dont l'heure est déjà passée (`début − délai ≤ now`) : aucune (pas de « dans 15 min » faux). Titre dans l'ordre `FollowList.displayOrder` : « KC vs C9 dans 15 min » même si l'API écrit « C9 vs KC ». Sous-titre : nom de ligue · `blockName` tel que l'API l'écrit (« Play-ins ») · « BoN », sans le bloc s'il est absent. Délais proposés `MatchReminders.leadOptions` = 5, 15, 30 min, défaut 15 min ; les réglages eux-mêmes (activé, délai) sont ajoutés à `AppSettings` par le plan de l'appli, pas ici.
- **Streams :** langue comparée exactement (`fr-FR`, puis `en-US`), fournisseur sans tenir compte de la casse, liens en double retirés ; `StreamPicker.others` donne le menu de l'appui long. AfreecaTV garde le lien de la spec `https://play.afreecatv.com/<parameter>` (vérifié le 14/10/2026 : redirection 301 vers `play.sooplive.com`). Rediffusions : YouTube seulement, `&t=<startMillis / 1000>s` (division entière) si > 0. Le 14/10/2026 un seul match était en direct (Demacia Cup, un stream AfreecaTV coréen) : aucune capture multi-langue n'existe ; le décodage est testé sur les vraies fixtures `getLive.json` et `getEventDetails.json` (déjà au dépôt), la préférence de langue sur des `StreamInfo` construits à la forme réelle. `StreamInfo` et le nouveau `Vod` se décodent champ par champ (un champ illisible devient nil).
- **Data Dragon :** « la plus récente » = l'ordre de `versions.json` (la plus récente d'abord) ; le préfixe comparé finit par un point (« 16.1. » ne prend pas « 16.18.1 ») ; les entrées `lolpatch_*` sont ignorées. Les liens sont non optionnels (chemin encodé : un id inattendu du flux ne casse rien). `ItemCatalog.inventory` met la balise à part grâce au tag Data Dragon « Trinket ». Les fragments de stats de `perks` (5001…5011) n'existent pas dans `runesReforged.json` : l'appli n'affiche que la rune principale (`perks[0]`) et l'arbre secondaire. `ChampionSpells.spell(forAbility:)` associe Q/W/E/R par position dans `spells`.
- **`details` :** `details(gameId:now:)` réutilise `LiveStatsTime.delays` et **partage la mémoire de délai** de `window` (même flux, même seuil : vérifié le 14/10/2026, `details` répond le même 400 « ahead of broadcast »). Pour une game terminée, une heure demandée après la fin renvoie les dernières frames (vérifié) : un seul appel `details(gameId:now:)` suffit. `LoLClient.detailsInterval = 60` (spec : 60 s au plus). `details` n'a pas de `gameMetadata` : champion, pseudo et côté se joignent par `participantId` (1-5 bleu, 6-10 rouge) à `LiveWindow.gameMetadata`, côté appli.
- **Leaguepedia :** la requête ne filtre que par dates (± 3 h autour du début de la game, 500 lignes), pas par champion (les noms du wiki ne sont pas les ids Data Dragon) ; `around` = première frame de la game (`LiveWindow.firstFrameTime` sans `startingTime`). Les sorts sont rendus en ids Data Dragon (`SummonerFlash`…) par une table de 10 noms anglais (« Ignite » → `SummonerDot`, « Cleanse » → `SummonerBoost`, « Ghost » → `SummonerHaste`…) ; un nom inconnu est omis. Normalisation des champions : minuscules, lettres et chiffres ASCII seulement, puis 3 alias (`wukong` → `monkeyking`, `renataglasc` → `renata`, `nunuwillump` → `nunu` : les seuls ids Data Dragon différents du nom, vérifié sur `champion.json` 16.17.1 et 16.20.1). Plusieurs games candidates : la plus proche dans le temps ; champion en double dans la demande : rien. **Limite de débit constatée le 14/10/2026** : le wiki répond `200 {"error":{"code":"ratelimited"}}` pendant plusieurs minutes (environ une requête Cargo anonyme acceptée toutes les 10 min) → `LeaguepediaError.rateLimited` ; l'appli ne doit jamais réessayer en boucle (à reprendre dans son plan).
- **Fil et courbe :** temps de jeu = horodatage de la frame − première frame de la game (même règle que le chrono, pauses comprises). La première frame donnée sert de référence (rien n'est inventé avant elle, cas de l'ouverture tardive). Ordre : chronologique (l'appli inverse), pour chaque pas l'équipe bleue puis la rouge, et kills, drakes, barons, tours, inhibiteurs ; une baisse n'est jamais un événement. Joueurs d'un kill : par position (ordre de `participantId`), seulement si la somme de leurs hausses vaut exactement la hausse de l'équipe ; sinon « +N kills » sans nom. **Pas de hérauts ni de larves** : le flux `window` ne les donne pas. `LiveWindow.snapshots()` (une `GameSnapshot` par frame) est ajouté pour rejouer une relecture mise en cache. La courbe : bleu − rouge, réorientée (rouge − bleu) si l'équipe de référence est rouge. Le calendrier de la relecture (une fenêtre par minute pleine depuis le début, comme la capture de `window_replay.json`) est laissé au plan de l'appli.

## Matrice des fichiers

Chemins relatifs à `LoLKit/`. Fichiers de test dans `Tests/LoLKitTests/`, fixtures dans `Tests/LoLKitTests/Fixtures/`.

| Tâche | Branche | Crée | Modifie (seule tâche autorisée) |
|---|---|---|---|
| T1 Streams et rediffusions | `fonc/lolkit-t1-streams` | `Sources/LoLKit/Media/StreamPicker.swift`, `StreamPickerTests.swift` | `Sources/LoLKit/Models/MatchEvent.swift` |
| T2 Notifications de début de match | `fonc/lolkit-t2-rappels` | `Sources/LoLKit/Reminders/MatchReminders.swift`, `MatchRemindersTests.swift` | — |
| T3 Data Dragon | `fonc/lolkit-t3-data-dragon` | `Sources/LoLKit/Media/DataDragon.swift`, `Sources/LoLKit/Media/DataDragonCatalogs.swift`, `DataDragonTests.swift`, `ddragon_versions.json`, `ddragon_item.json`, `ddragon_runesReforged.json`, `ddragon_summoner.json`, `ddragon_champion_KSante.json` | — |
| T4 Flux `details` | `fonc/lolkit-t4-details` | `Sources/LoLKit/API/LoLClient+Details.swift`, `Sources/LoLKit/Models/GameDetails.swift`, `GameDetailsTests.swift`, `details_ingame.json` | `Sources/LoLKit/API/LoLClient.swift` |
| T5 Leaguepedia | `fonc/lolkit-t5-leaguepedia` | `Sources/LoLKit/Leaguepedia/ChampionKey.swift`, `Sources/LoLKit/Leaguepedia/SpellMatcher.swift`, `Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift`, `LeaguepediaTests.swift`, `leaguepedia_scoreboard.json`, `leaguepedia_ratelimited.json` | — |
| T6 Fil des événements et courbe de gold | `fonc/lolkit-t6-fil-gold` | `Sources/LoLKit/Timeline/LiveWindow+Snapshots.swift`, `Sources/LoLKit/Timeline/GameTimeline.swift`, `Sources/LoLKit/Timeline/GoldSeries.swift`, `GameTimelineTests.swift`, `window_replay.json` | — |

Aucun fichier n'apparaît sur deux lignes. Noms de types et de suites sans collision (vérifié : les six tâches fusionnées compilent sans avertissement). Les helpers privés de fichier (`Tolerant`, `Lenient`, `CargoResponse`) sont `private` et ne se croisent pas.

## Dépendances

- **T1 :** aucune.
- **T2 :** aucune (n'utilise pas les champs ajoutés par T1).
- **T3 :** aucune.
- **T4 :** aucune.
- **T5 :** aucune (ne dépend pas des catalogues de T3 : il rend des ids Data Dragon que l'appli cherche dans `SummonerCatalog`).
- **T6 :** aucune.

**Vérifié avant d'écrire ce plan** (copie de `HEAD` hors du dépôt, Docker `swift:6.2`) : chaque tâche seule sur `HEAD` passe (`HEAD` = 258 tests dans 29 suites ; T1 → 265, T2 → 266, T3 → 266, T4 → 263, T5 → 266, T6 → 263) ; les six fusionnées : **299 tests dans 35 suites**, sans avertissement. Ordre de fusion indifférent ; après la dernière fusion, le contrôleur lance `bash scripts/lolkit.sh test` sur `main` et attend `Test run with 299 tests in 35 suites passed`.

**Mise en place (contrôleur, avant chaque tâche) :** `git worktree add ../faille-<tN> -b <branche> main`, puis l'implémenteur travaille dans ce dossier. `scripts/lolkit.sh` y crée son propre volume Docker.

---

### Task 1: Streams et rediffusions (`StreamPicker`, `streams[]`, `vods[]`)

**Branche :** `fonc/lolkit-t1-streams`

**Files:**
- Modify: `LoLKit/Sources/LoLKit/Models/MatchEvent.swift:91-110` (fin de `GameRef` et `StreamInfo`) — **T1 est la seule tâche qui touche ce fichier.**
- Create: `LoLKit/Sources/LoLKit/Media/StreamPicker.swift`
- Test: `LoLKit/Tests/LoLKitTests/StreamPickerTests.swift`
- Fixtures : aucune nouvelle (vraies fixtures déjà au dépôt : `getLive.json` — un stream `afreecatv` / `aflol` / `ko-KR` ; `getEventDetails.json` — `games[].vods[]` YouTube `en-US` et `es-MX`).

**Interfaces:**
- Consumes (à `HEAD`) : `LoLClient(transport:)`, `LoLClient.live() async throws -> [MatchEvent]`, `LoLClient.eventDetails(matchId: String) async throws -> EventDetails`, `MatchEvent.streams: [StreamInfo]?`, `MatchEvent.statsDisabled: Bool`, `EventDetails.match.games: [GameRef]` ; tests : `FakeTransport.on(_:status:fixture:body:)`, `Fixture.data(_:)`.
- Produces :
  - `StreamInfo` gagne `provider: String?`, `parameter: String?`, `locale: String?` ; `init(statsStatus: String?, provider: String? = nil, parameter: String? = nil, locale: String? = nil)` (les appels existants `StreamInfo(statsStatus:)` restent valides).
  - `public struct Vod: Codable, Sendable, Equatable { provider: String?; parameter: String?; locale: String?; startMillis: Int? }` ; `init(provider:parameter:locale:startMillis:)`.
  - `GameRef.vods: [Vod]?` ; `GameRef.init(number:id:state:teams:vods: [Vod]? = nil)`.
  - `public struct StreamLink: Sendable, Equatable { provider: String; locale: String?; url: URL }`.
  - `public enum StreamPicker` : `preferredLocales: [String]` (`["fr-FR", "en-US"]`), `url(provider: String?, parameter: String?) -> URL?`, `links(_ streams: [StreamInfo]) -> [StreamLink]`, `preferred(_ streams: [StreamInfo]) -> StreamLink?`, `others(_ streams: [StreamInfo]) -> [StreamLink]`, `replay(_ vods: [Vod]) -> StreamLink?`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/StreamPickerTests.swift` :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli doit pouvoir lire streams et rediffusions et choisir le lien.
import LoLKit

@Suite struct StreamPickerTests {
    /// Vrai `getLive` (13/10/2026, Demacia Cup) : un seul stream, AfreecaTV en coréen.
    @Test func decodesTheStreamsOfGetLive() async throws {
        let fake = FakeTransport()
        try await fake.on("getLive", fixture: "getLive")
        let event = try #require(try await LoLClient(transport: fake).live().first)
        let streams = try #require(event.streams)
        #expect(streams == [StreamInfo(statsStatus: "disabled", provider: "afreecatv", parameter: "aflol", locale: "ko-KR")])
        #expect(event.statsDisabled)

        let link = try #require(StreamPicker.preferred(streams))
        #expect(link == StreamLink(provider: "afreecatv", locale: "ko-KR",
                                   url: try #require(URL(string: "https://play.afreecatv.com/aflol"))))
        #expect(StreamPicker.others(streams).isEmpty)
    }

    /// Vrai `getEventDetails` (finale LCS terminée) : deux rediffusions YouTube par game jouée (en-US, es-MX).
    @Test func decodesTheVodsOfGetEventDetails() async throws {
        let fake = FakeTransport()
        try await fake.on("getEventDetails", fixture: "getEventDetails")
        let games = try await LoLClient(transport: fake).eventDetails(matchId: "115565004607949429").match.games
        #expect(games.map { $0.vods?.count } == [2, 2, 2, 2, 0])
        #expect(games[1].vods?.first == Vod(provider: "youtube", parameter: "8Mdtj9TMxWQ", locale: "en-US",
                                            startMillis: 2_646_000))
        #expect(games[1].vods?.last == Vod(provider: "youtube", parameter: "c_1_5yDlQZ0", locale: "es-MX",
                                           startMillis: nil))
    }

    @Test func replayLinksJumpToTheStartOfTheGame() async throws {
        let fake = FakeTransport()
        try await fake.on("getEventDetails", fixture: "getEventDetails")
        let games = try await LoLClient(transport: fake).eventDetails(matchId: "115565004607949429").match.games
        // Pas de fr-FR : l'anglais passe avant l'espagnol ; la game 1 commence au début de la vidéo (pas de `t`).
        #expect(StreamPicker.replay(games[0].vods ?? [])?.url.absoluteString
                == "https://www.youtube.com/watch?v=8Mdtj9TMxWQ")
        #expect(StreamPicker.replay(games[1].vods ?? [])?.url.absoluteString
                == "https://www.youtube.com/watch?v=8Mdtj9TMxWQ&t=2646s")
        #expect(StreamPicker.replay(games[3].vods ?? [])?.url.absoluteString
                == "https://www.youtube.com/watch?v=8Mdtj9TMxWQ&t=8632s")
        #expect(StreamPicker.replay(games[1].vods ?? [])?.locale == "en-US")
        // Game 5 non jouée : rien à revoir.
        #expect(StreamPicker.replay(games[4].vods ?? []) == nil)
    }

    @Test func replayPrefersFrenchAndIgnoresOtherProviders() {
        let vods = [
            Vod(provider: "youtube", parameter: "en", locale: "en-US", startMillis: 0),
            Vod(provider: "twitch", parameter: "123", locale: "fr-FR", startMillis: 0),
            Vod(provider: "youtube", parameter: "fr", locale: "fr-FR", startMillis: 1_500),
        ]
        #expect(StreamPicker.replay(vods)?.url.absoluteString == "https://www.youtube.com/watch?v=fr&t=1s")
        #expect(StreamPicker.replay([Vod(provider: "youtube", parameter: "es", locale: "es-MX", startMillis: nil)])?
            .url.absoluteString == "https://www.youtube.com/watch?v=es")
        #expect(StreamPicker.replay([Vod(provider: "youtube", parameter: nil, locale: "fr-FR", startMillis: 0)]) == nil)
    }

    @Test func prefersFrenchThenEnglishThenTheFirstStream() throws {
        let korean = StreamInfo(statsStatus: "enabled", provider: "afreecatv", parameter: "aflol", locale: "ko-KR")
        let english = StreamInfo(statsStatus: "enabled", provider: "youtube", parameter: "abc123", locale: "en-US")
        let french = StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR")

        #expect(StreamPicker.preferred([korean, english, french])?.url.absoluteString == "https://www.twitch.tv/otplol_")
        #expect(StreamPicker.preferred([korean, english])?.url.absoluteString
                == "https://www.youtube.com/watch?v=abc123")
        #expect(StreamPicker.preferred([korean])?.provider == "afreecatv")
        #expect(StreamPicker.preferred([]) == nil)
        // Menu de l'appui long : les autres, dans l'ordre de l'API.
        #expect(StreamPicker.others([korean, english, french]).map(\.locale) == ["ko-KR", "en-US"])
    }

    @Test func unknownProvidersAndEmptyParametersAreIgnored() {
        let huya = StreamInfo(statsStatus: "enabled", provider: "huya", parameter: "lpl", locale: "fr-FR")
        let empty = StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "", locale: "fr-FR")
        let missing = StreamInfo(statsStatus: "enabled")
        let english = StreamInfo(statsStatus: "enabled", provider: "Twitch", parameter: "riotgames", locale: "en-US")

        #expect(StreamPicker.links([huya, empty, missing, english]).map(\.url.absoluteString)
                == ["https://www.twitch.tv/riotgames"])
        #expect(StreamPicker.preferred([huya, empty, missing]) == nil)
        #expect(StreamPicker.url(provider: "huya", parameter: "lpl") == nil)
        #expect(StreamPicker.url(provider: "youtube", parameter: nil) == nil)
        // Deux entrées vers le même lien n'en font qu'une.
        #expect(StreamPicker.links([english, english]).count == 1)
    }

    @Test func oldCachedMatchesWithoutStreamFieldsStillDecode() throws {
        // Calendrier écrit sur disque par une version précédente : ni provider, ni vods.
        let json = #"{"statsStatus":"enabled"}"#
        let stream = try JSONDecoder().decode(StreamInfo.self, from: Data(json.utf8))
        #expect(stream == StreamInfo(statsStatus: "enabled"))
        let game = try JSONDecoder().decode(GameRef.self, from: Data(#"{"number":1,"id":"g1","state":"completed"}"#.utf8))
        #expect(game.vods == nil)
        // Champ d'un mauvais type : ignoré, pas d'échec.
        let odd = try JSONDecoder().decode(Vod.self, from: Data(#"{"parameter":"x","startMillis":"tard"}"#.utf8))
        #expect(odd == Vod(provider: nil, parameter: "x", locale: nil, startMillis: nil))
    }
}
```

- [ ] **Step 2: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter StreamPickerTests`
Expected : FAIL à la compilation (`cannot find 'StreamPicker' in scope`, `cannot find 'Vod' in scope`, arguments en trop pour `StreamInfo(statsStatus:)`).

- [ ] **Step 3: Décoder `streams[]` et `vods[]`**

Dans `LoLKit/Sources/LoLKit/Models/MatchEvent.swift`, remplacer les lignes 91-110 (de `    public let number: Int` jusqu'à l'accolade qui ferme `StreamInfo`) par :

```swift
    public let number: Int
    public let id: String
    public let state: State
    public let teams: [Side]?
    /// Rediffusions de la game (`getEventDetails` d'un match terminé) ; vide ou absent sinon.
    public let vods: [Vod]?

    public init(number: Int, id: String, state: State, teams: [Side]?, vods: [Vod]? = nil) {
        self.number = number
        self.id = id
        self.state = state
        self.teams = teams
        self.vods = vods
    }
}

/// Rediffusion d'une game (`games[].vods[]` de `getEventDetails`) : une vidéo par langue.
public struct Vod: Codable, Sendable, Equatable {
    /// `youtube` (le seul vu le 14/10/2026).
    public let provider: String?
    /// Identifiant de la vidéo chez le fournisseur (YouTube : `v=`).
    public let parameter: String?
    /// Langue, ex. `en-US`.
    public let locale: String?
    /// Début de la game dans la vidéo, en millisecondes (souvent 0 ou absent : la vidéo commence avec la game).
    public let startMillis: Int?

    public init(provider: String?, parameter: String?, locale: String?, startMillis: Int?) {
        self.provider = provider
        self.parameter = parameter
        self.locale = locale
        self.startMillis = startMillis
    }

    private enum CodingKeys: String, CodingKey {
        case provider, parameter, locale, startMillis
    }

    /// Décodage tolérant : un champ illisible devient nil, la game et le match restent lisibles.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try? container.decodeIfPresent(String.self, forKey: .provider)
        parameter = try? container.decodeIfPresent(String.self, forKey: .parameter)
        locale = try? container.decodeIfPresent(String.self, forKey: .locale)
        startMillis = try? container.decodeIfPresent(Int.self, forKey: .startMillis)
    }
}

/// Un stream d'un match (`getLive`, `getEventDetails`) : fournisseur (`twitch`, `youtube`, `afreecatv`…), identifiant
/// chez ce fournisseur (`parameter`), langue (`locale`, ex. `fr-FR`) et état des stats live.
public struct StreamInfo: Codable, Sendable, Equatable {
    public let statsStatus: String?
    public let provider: String?
    public let parameter: String?
    public let locale: String?

    public init(statsStatus: String?, provider: String? = nil, parameter: String? = nil, locale: String? = nil) {
        self.statsStatus = statsStatus
        self.provider = provider
        self.parameter = parameter
        self.locale = locale
    }

    private enum CodingKeys: String, CodingKey {
        case statsStatus, provider, parameter, locale
    }

    /// Décodage tolérant : un champ illisible devient nil, le match reste lisible.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statsStatus = try? container.decodeIfPresent(String.self, forKey: .statsStatus)
        provider = try? container.decodeIfPresent(String.self, forKey: .provider)
        parameter = try? container.decodeIfPresent(String.self, forKey: .parameter)
        locale = try? container.decodeIfPresent(String.self, forKey: .locale)
    }
}
```

(L'encodage reste synthétisé : le calendrier mis en cache garde les nouveaux champs ; un cache plus ancien se relit sans eux.)

- [ ] **Step 4: Écrire `StreamPicker`**

Créer `LoLKit/Sources/LoLKit/Media/StreamPicker.swift` :

```swift
import Foundation

/// Un lien « Regarder » (stream en direct) ou « Revoir » (rediffusion d'une game), à ouvrir avec `openURL`.
public struct StreamLink: Sendable, Equatable {
    /// Fournisseur en minuscules : `twitch`, `youtube` ou `afreecatv`.
    public let provider: String
    /// Langue du stream, ex. `fr-FR` (nil si l'API ne la donne pas).
    public let locale: String?
    public let url: URL

    public init(provider: String, locale: String?, url: URL) {
        self.provider = provider
        self.locale = locale
        self.url = url
    }
}

/// Choix du stream et des rediffusions (spec fonctionnalités §1). Ne connaît que les fournisseurs dont on sait écrire le
/// lien ; un autre fournisseur est ignoré. Anti-spoiler : l'appli n'appelle ces fonctions que pour un match non masqué.
public enum StreamPicker {
    /// Langues préférées, dans l'ordre ; sinon, le premier stream utilisable.
    public static let preferredLocales = ["fr-FR", "en-US"]

    /// Lien d'un stream chez son fournisseur : Twitch `https://www.twitch.tv/<parameter>`, YouTube
    /// `https://www.youtube.com/watch?v=<parameter>`, AfreecaTV `https://play.afreecatv.com/<parameter>`.
    /// nil pour un fournisseur inconnu ou un identifiant vide.
    public static func url(provider: String?, parameter: String?) -> URL? {
        guard let parameter, !parameter.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        switch provider?.lowercased() {
        case "twitch":
            components.host = "www.twitch.tv"
            components.path = "/" + parameter
        case "youtube":
            components.host = "www.youtube.com"
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: parameter)]
        case "afreecatv":
            components.host = "play.afreecatv.com"
            components.path = "/" + parameter
        default:
            return nil
        }
        return components.url
    }

    /// Streams utilisables (fournisseur connu), dans l'ordre de l'API, sans doublon de lien.
    public static func links(_ streams: [StreamInfo]) -> [StreamLink] {
        var seen = Set<URL>()
        return streams.compactMap { stream -> StreamLink? in
            guard let provider = stream.provider?.lowercased(),
                  let url = url(provider: provider, parameter: stream.parameter),
                  seen.insert(url).inserted else { return nil }
            return StreamLink(provider: provider, locale: stream.locale, url: url)
        }
    }

    /// Stream du bouton « Regarder » : `fr-FR`, sinon `en-US`, sinon le premier utilisable ; nil s'il n'y en a aucun.
    public static func preferred(_ streams: [StreamInfo]) -> StreamLink? {
        pick(links(streams))
    }

    /// Les autres streams (menu de l'appui long : langue + plateforme), dans l'ordre de l'API, sans le préféré.
    public static func others(_ streams: [StreamInfo]) -> [StreamLink] {
        let all = links(streams)
        guard let chosen = pick(all) else { return [] }
        return all.filter { $0 != chosen }
    }

    /// « Revoir la game N » : la rediffusion YouTube dans la langue préférée (même ordre que les streams), avec
    /// `&t=<startMillis / 1000>s` si la game commence plus loin dans la vidéo. nil si la game n'a pas de rediffusion.
    public static func replay(_ vods: [Vod]) -> StreamLink? {
        let links = vods.compactMap { vod -> StreamLink? in
            guard vod.provider?.lowercased() == "youtube",
                  let base = url(provider: "youtube", parameter: vod.parameter),
                  var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            let seconds = (vod.startMillis ?? 0) / 1000
            if seconds > 0 {
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: "\(seconds)s")]
            }
            guard let url = components.url else { return nil }
            return StreamLink(provider: "youtube", locale: vod.locale, url: url)
        }
        return pick(links)
    }

    /// Premier lien dans une langue préférée (dans l'ordre de `preferredLocales`), sinon le premier.
    static func pick(_ links: [StreamLink]) -> StreamLink? {
        for locale in preferredLocales {
            if let link = links.first(where: { $0.locale == locale }) { return link }
        }
        return links.first
    }
}
```

- [ ] **Step 5: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter StreamPickerTests`
Expected : PASS — `Test run with 7 tests in 1 suite passed`.

- [ ] **Step 6: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 265 tests in 30 suites passed`, aucun `warning:` (les appels existants `StreamInfo(statsStatus:)` et `GameRef(number:id:state:teams:)` compilent toujours).

- [ ] **Step 7: Commit**

```bash
git add LoLKit/Sources/LoLKit/Models/MatchEvent.swift LoLKit/Sources/LoLKit/Media/StreamPicker.swift LoLKit/Tests/LoLKitTests/StreamPickerTests.swift
git commit -m "feat(lolkit): streams et rediffusions — StreamPicker (fr-FR, en-US, premier), liens Twitch/YouTube/AfreecaTV, « Revoir » avec &t=" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Pousser la branche et vérifier la CI**

```bash
git push -u origin fonc/lolkit-t1-streams
gh run list --workflow LoLKit --branch fonc/lolkit-t1-streams --limit 1
gh run watch --exit-status <id de la ligne affichée>
```
Expected : les jobs `test` (Linux) et `test-macos` verts. Échec : `gh run view <id> --log-failed`, corriger, nouveau commit, nouveau push.

---

### Task 2: Notifications de début de match (`MatchReminders.plan`)

**Branche :** `fonc/lolkit-t2-rappels`

**Files:**
- Create: `LoLKit/Sources/LoLKit/Reminders/MatchReminders.swift`
- Test: `LoLKit/Tests/LoLKitTests/MatchRemindersTests.swift`
- Fixtures : aucune nouvelle (vraies fixtures déjà au dépôt : `getSchedule.json` — C9 vs KC, Mondial, Play-ins, Bo5, 15/10/2026 18:00 UTC, id `115660588583171786` ; dernier match de KC : KC 0 – 3 MKOI, id `115548681803406327` ; `getTeams.json` pour `catalogTeam`).

**Interfaces:**
- Consumes (à `HEAD`) : `TeamCards.build(follows: FollowList, schedule: [MatchEvent], live: [MatchEvent]?, revealed: Set<String>) -> [TeamCard]`, `Presenter.maskedLatestTeamIds(_ cards: [TeamCard], follows: FollowList, revealed: Set<String>) -> Set<String>`, `Presenter.nextLine(for: TeamCard, follows: FollowList, revealed: Set<String>, maskedLatestTeamIds: Set<String>) -> NextLine` (`.hidden`, `.none`, `.match(MatchEvent)`), `FollowList.displayOrder(_ teams: [MatchTeam], preferring: FollowedTeam? = nil) -> [Int]`, `reorder<T>(_ values: [T], _ order: [Int]) -> [T]?`, `MatchEvent.bestOf`, `.blockName`, `.league.name`, `.startTime`, `.state` ; tests : `catalogTeam(_:) throws -> Team`, `makeEvent(id:state:start:teams:bestOf:games:statsDisabled:)`, `date(_:)`, `LoLClient.schedule(leagueIds:)`, `FakeTransport`.
- Produces :
  - `public struct MatchReminder: Sendable, Equatable, Identifiable { id: String; matchId: String; fireDate: Date; title: String; subtitle: String }` ; `init(id:matchId:fireDate:title:subtitle:)`.
  - `public enum MatchReminders` : `maxCount = 60`, `leadOptions: [TimeInterval] = [300, 900, 1800]`, `defaultLead: TimeInterval = 900`, `identifier(matchId: String) -> String` (`"match-start-<id>"`), `plan(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>, now: Date, lead: TimeInterval) -> [MatchReminder]`.

- [ ] **Step 1: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/MatchRemindersTests.swift` :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli programme les notifications avec la seule API publique.
import LoLKit

/// Notifications de début de match (spec fonctionnalités §2) : seulement ce que `Presenter.nextLine` montre (F1 + C).
@Suite struct MatchRemindersTests {
    private static let kcId = "111692118851466302"
    private static let c9Id = "98767991877340524"
    /// C9 vs KC, Mondial, Play-ins, Bo5, 15/10/2026 18:00 UTC (fixture `getSchedule`).
    private static let worldsMatch = "115660588583171786"
    /// Dernier match de KC dans la fixture : KC 0 – 3 MKOI, terminé le 19/09.
    private static let kcLast = "115548681803406327"

    /// Vrai calendrier (fixture `getSchedule` : LEC + Mondial), lu par le client public.
    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    private func follows(_ codes: [String], spoilerFree: Set<String> = []) throws -> FollowList {
        var list = FollowList()
        for code in codes {
            let team = try catalogTeam(code)
            list.follow(team)
            if spoilerFree.contains(code) { list.setSpoilerFree(true, id: team.id) }
        }
        return list
    }

    @Test func remindsTheNextMatchOfAFollowedTeam() async throws {
        let reminders = MatchReminders.plan(schedule: try await schedule(), follows: try follows(["KC"]), revealed: [],
                                            now: date("2026-10-15T12:00:00Z"), lead: MatchReminders.defaultLead)
        #expect(reminders == [MatchReminder(id: "match-start-115660588583171786", matchId: Self.worldsMatch,
                                            fireDate: date("2026-10-15T17:45:00Z"), title: "KC vs C9 dans 15 min",
                                            subtitle: "Mondial · Play-ins · Bo5")])
        #expect(MatchReminders.identifier(matchId: Self.worldsMatch) == reminders.first?.id)
    }

    @Test func leadSetsTheTimeAndTheText() async throws {
        let events = try await schedule()
        let list = try follows(["KC"])
        let now = date("2026-10-15T12:00:00Z")
        #expect(MatchReminders.leadOptions == [300, 900, 1800])
        let five = try #require(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 300).first)
        #expect(five.fireDate == date("2026-10-15T17:55:00Z"))
        #expect(five.title == "KC vs C9 dans 5 min")
        let thirty = try #require(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 1800).first)
        #expect(thirty.fireDate == date("2026-10-15T17:30:00Z"))
        #expect(thirty.title == "KC vs C9 dans 30 min")
    }

    @Test func nothingOnceTheFireDateHasPassed() async throws {
        let events = try await schedule()
        let list = try follows(["KC"])
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [],
                                    now: date("2026-10-15T17:45:00Z"), lead: 900).isEmpty)
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [],
                                    now: date("2026-10-15T17:44:59Z"), lead: 900).count == 1)
    }

    /// Règle F1 : KC en anti-spoiler, son dernier match (KC – MKOI) masqué → pas de notification de son prochain match.
    @Test func maskedLastMatchHidesTheReminder() async throws {
        let events = try await schedule()
        let list = try follows(["KC"], spoilerFree: ["KC"])
        let now = date("2026-10-15T12:00:00Z")
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900).isEmpty)
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: ["autre"], now: now, lead: 900).isEmpty)
        // Révéler le dernier match de KC rend la notification.
        let revealed = MatchReminders.plan(schedule: events, follows: list, revealed: [Self.kcLast], now: now, lead: 900)
        #expect(revealed.map(\.matchId) == [Self.worldsMatch])
    }

    /// Règle C : KC suivie normalement, son prochain adversaire C9 suivi en anti-spoiler avec un dernier match masqué
    /// → « KC vs C9 » trahirait que C9 joue encore : pas de notification, ni pour KC ni pour C9.
    @Test func followedOpponentWithAMaskedLastMatchHidesTheReminder() async throws {
        let c9Last = MatchEvent(
            startTime: date("2026-10-10T18:00:00Z"), state: .completed, type: "match", blockName: "Play-ins",
            league: LeagueRef(id: "98767975604431411", slug: "worlds", name: "Mondial", image: nil),
            match: MatchInfo(id: "c9-last",
                             teams: [MatchTeam(id: nil, name: "Cloud9 Kia", code: "C9", image: nil,
                                               result: MatchTeam.Result(outcome: "win", gameWins: 3)),
                                     MatchTeam(id: nil, name: "FlyQuest", code: "FLY", image: nil,
                                               result: MatchTeam.Result(outcome: "loss", gameWins: 1))],
                             strategy: Strategy(type: "bestOf", count: 5), games: nil),
            streams: nil)
        let events = try await schedule() + [c9Last]
        let list = try follows(["KC", "C9"], spoilerFree: ["C9"])
        let now = date("2026-10-15T12:00:00Z")
        #expect(MatchReminders.plan(schedule: events, follows: list, revealed: [], now: now, lead: 900).isEmpty)
        let revealed = MatchReminders.plan(schedule: events, follows: list, revealed: ["c9-last"], now: now, lead: 900)
        #expect(revealed.map(\.title) == ["KC vs C9 dans 15 min"])
    }

    @Test func oneReminderPerMatchWhenBothTeamsAreFollowed() async throws {
        // C9 suivie en premier : elle passe à gauche.
        let reminders = MatchReminders.plan(schedule: try await schedule(), follows: try follows(["C9", "KC"]),
                                            revealed: [], now: date("2026-10-15T12:00:00Z"), lead: 900)
        #expect(reminders.map(\.title) == ["C9 vs KC dans 15 min"])
    }

    @Test func onlyTheNextMatchOfEachTeam() throws {
        let kc = MatchTeam(id: nil, name: "Karmine Corp", code: "KC", image: nil, result: nil)
        let g2 = MatchTeam(id: nil, name: "G2 Esports", code: "G2", image: nil, result: nil)
        let events = [
            makeEvent(id: "later", state: .unstarted, start: "2026-10-21T16:00:00Z", teams: [g2, kc]),
            makeEvent(id: "sooner", state: .unstarted, start: "2026-10-20T16:00:00Z", teams: [kc, g2]),
        ]
        let reminders = MatchReminders.plan(schedule: events, follows: try follows(["KC"]), revealed: [],
                                            now: date("2026-10-15T12:00:00Z"), lead: 900)
        #expect(reminders.map(\.matchId) == ["sooner"])
    }

    @Test func atMostSixtyNearestFirst() {
        let teams = (0..<65).map { FollowedTeam(id: "t\($0)", code: "T\($0)", name: "Team \($0)") }
        let base = date("2026-10-20T00:00:00Z")
        let events = (0..<65).reversed().map { index in
            MatchEvent(startTime: base.addingTimeInterval(Double(index) * 3600), state: .unstarted, type: "match",
                       blockName: nil,
                       league: LeagueRef(id: "1", slug: "lec", name: "LEC", image: nil),
                       match: MatchInfo(id: "m\(index)",
                                        teams: [MatchTeam(id: "t\(index)", name: "Team \(index)", code: "T\(index)",
                                                          image: nil, result: nil),
                                                MatchTeam(id: "o\(index)", name: "Other \(index)", code: "O\(index)",
                                                          image: nil, result: nil)],
                                        strategy: Strategy(type: "bestOf", count: 3), games: nil),
                       streams: nil)
        }
        let reminders = MatchReminders.plan(schedule: events, follows: FollowList(teams: teams), revealed: [],
                                            now: date("2026-10-15T12:00:00Z"), lead: 900)
        #expect(reminders.count == MatchReminders.maxCount)
        #expect(reminders.map(\.matchId) == (0..<60).map { "m\($0)" })
        // Sans bloc : « LEC · Bo3 ».
        #expect(reminders.first?.subtitle == "LEC · Bo3")
        #expect(reminders.first?.title == "T0 vs O0 dans 15 min")
    }
}
```

- [ ] **Step 2: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter MatchRemindersTests`
Expected : FAIL à la compilation (`cannot find 'MatchReminders' in scope`, `cannot find 'MatchReminder' in scope`).

- [ ] **Step 3: Écrire `MatchReminders`**

Créer `LoLKit/Sources/LoLKit/Reminders/MatchReminders.swift` :

```swift
import Foundation

/// Une notification locale de début de match (spec fonctionnalités §2), à programmer telle quelle par l'appli.
public struct MatchReminder: Sendable, Equatable, Identifiable {
    /// Identifiant de la notification, stable pour un match : re-programmer le même match remplace l'ancienne.
    public let id: String
    public let matchId: String
    /// Heure d'envoi : début du match moins le délai choisi.
    public let fireDate: Date
    /// « KC vs C9 dans 15 min » — jamais de score ni de résultat.
    public let title: String
    /// « Mondial · Play-ins · Bo5 »
    public let subtitle: String

    public init(id: String, matchId: String, fireDate: Date, title: String, subtitle: String) {
        self.id = id
        self.matchId = matchId
        self.fireDate = fireDate
        self.title = title
        self.subtitle = subtitle
    }
}

/// Quelles notifications de début de match programmer (spec fonctionnalités §2). Fonction pure : l'appli la rappelle à
/// chaque rafraîchissement du calendrier, des équipes suivies ou des réglages, et remplace toutes ses notifications.
public enum MatchReminders {
    /// iOS garde au plus 64 notifications en attente : on en laisse 4 à l'appli.
    public static let maxCount = 60
    /// Délais proposés dans les réglages (5, 15 ou 30 min) et délai par défaut (15 min).
    public static let leadOptions: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60]
    public static let defaultLead: TimeInterval = 15 * 60

    /// Identifiant stable de la notification d'un match.
    public static func identifier(matchId: String) -> String {
        "match-start-\(matchId)"
    }

    /// Notifications à programmer, les plus proches d'abord, 60 au plus. Un match n'est retenu que s'il n'a pas commencé,
    /// que sa notification tombe après `now`, et que `Presenter.nextLine` l'affiche (`.match`) sur la carte d'au moins une
    /// équipe suivie qui y joue : jamais un prochain match caché par la règle F1 (dernier match masqué) ou la règle C
    /// (adversaire suivi en anti-spoiler au dernier match masqué). Donc au plus un match par équipe suivie : son prochain.
    /// - Parameters:
    ///   - schedule: calendrier en cache (`getSchedule`).
    ///   - revealed: ids des matchs révélés par l'utilisateur.
    ///   - lead: délai avant le début du match, en secondes.
    public static func plan(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>, now: Date,
                            lead: TimeInterval) -> [MatchReminder] {
        // `live: nil` : seul le calendrier compte ici (son match `inProgress` sert de « dernier match » à la règle F1).
        let cards = TeamCards.build(follows: follows, schedule: schedule, live: nil, revealed: revealed)
        let maskedLatest = Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: revealed)
        var planned = Set<String>()
        var reminders: [MatchReminder] = []
        for card in cards {
            guard case let .match(event) = Presenter.nextLine(for: card, follows: follows, revealed: revealed,
                                                              maskedLatestTeamIds: maskedLatest),
                  event.state == .unstarted, !planned.contains(event.id) else { continue }
            let fireDate = event.startTime.addingTimeInterval(-lead)
            guard fireDate > now else { continue }
            planned.insert(event.id)
            reminders.append(MatchReminder(id: identifier(matchId: event.id), matchId: event.id, fireDate: fireDate,
                                           title: title(event, follows: follows, lead: lead),
                                           subtitle: subtitle(event)))
        }
        return Array(reminders.sorted { ($0.fireDate, $0.matchId) < ($1.fireDate, $1.matchId) }.prefix(maxCount))
    }

    /// « KC vs C9 dans 15 min » : équipes dans l'ordre d'affichage (`displayOrder` : la plus anciennement suivie à gauche).
    static func title(_ event: MatchEvent, follows: FollowList, lead: TimeInterval) -> String {
        let codes = event.match.teams.map(\.code)
        let ordered = reorder(codes, follows.displayOrder(event.match.teams)) ?? codes
        return "\(ordered.joined(separator: " vs ")) dans \(Int((lead / 60).rounded())) min"
    }

    /// « Mondial · Play-ins · Bo5 » (sans le bloc s'il est absent).
    static func subtitle(_ event: MatchEvent) -> String {
        [event.league.name, event.blockName ?? "", "Bo\(event.bestOf)"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
```

- [ ] **Step 4: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter MatchRemindersTests`
Expected : PASS — `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 5: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 266 tests in 30 suites passed`, aucun `warning:`.

- [ ] **Step 6: Commit**

```bash
git add LoLKit/Sources/LoLKit/Reminders/MatchReminders.swift LoLKit/Tests/LoLKitTests/MatchRemindersTests.swift
git commit -m "feat(lolkit): notifications de début de match — MatchReminders.plan (Presenter.nextLine F1 + C, 60 au plus, identifiant stable)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Pousser la branche et vérifier la CI**

```bash
git push -u origin fonc/lolkit-t2-rappels
gh run list --workflow LoLKit --branch fonc/lolkit-t2-rappels --limit 1
gh run watch --exit-status <id de la ligne affichée>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task 3: Data Dragon (version, liens d'images, catalogues fr_FR)

**Branche :** `fonc/lolkit-t3-data-dragon`

**Files:**
- Create: `LoLKit/Sources/LoLKit/Media/DataDragon.swift`
- Create: `LoLKit/Sources/LoLKit/Media/DataDragonCatalogs.swift`
- Test: `LoLKit/Tests/LoLKitTests/DataDragonTests.swift`
- Fixtures (créées) : `ddragon_versions.json`, `ddragon_item.json`, `ddragon_runesReforged.json`, `ddragon_summoner.json`, `ddragon_champion_KSante.json` (version 16.17.1, celle du patch 16.17.815.3183 des fixtures `window_*` de la finale LCS).

**Interfaces:**
- Consumes : Foundation seule ; tests : `Fixture.data(_:)`.
- Produces :
  - `public enum DataDragon` : `language = "fr_FR"`, `versionsURL: URL` (`https://ddragon.leagueoflegends.com/api/versions.json`), `versionsMaxAge: TimeInterval = 86_400`, `version(forPatch: String?, versions: [String]) -> String?`, `decodeVersions(_ data: Data) throws -> [String]`, `championImage(version: String, championId: String) -> URL`, `itemImage(version: String, itemId: Int) -> URL`, `spellImage(version: String, file: String) -> URL`, `passiveImage(version: String, file: String) -> URL`, `summonerSpellImage(version: String, spellId: String) -> URL`, `runeIcon(_ icon: String) -> URL`, `itemsURL(version:) -> URL`, `runesURL(version:) -> URL`, `summonerSpellsURL(version:) -> URL`, `championURL(version: String, championId: String) -> URL`.
  - `public struct ItemCatalog` (`init(json: Data) throws`, `version: String?`, `items: [Int: Item]`, `item(_ id: Int) -> Item?`, `inventory(_ ids: [Int]) -> Inventory`) avec `Item { id: Int; name: String; image: String; isTrinket: Bool }` et `Inventory { items: [Int]; trinket: Int? }`.
  - `public struct RuneCatalog` (`init(json:) throws`, `styles: [Int: Entry]`, `runes: [Int: Entry]`, `style(_:) -> Entry?`, `rune(_:) -> Entry?`) avec `Entry { id: Int; key: String; name: String; icon: String }`.
  - `public struct SummonerCatalog` (`init(json:) throws`, `spells: [String: Spell]`, `spell(_ id: String) -> Spell?`) avec `Spell { id: String; name: String; image: String }`.
  - `public struct ChampionSpells` (`init(json:) throws`, `championId: String`, `name: String`, `spells: [Ability]` (Q, W, E, R), `passive: Ability?`, `spell(forAbility: String) -> Ability?`) avec `Ability { name: String; image: String }`.

- [ ] **Step 1: Capturer et réduire les fixtures**

Depuis la racine du worktree (Git Bash) :

```bash
RAW="$(mktemp -d)"; command -v cygpath >/dev/null && RAW="$(cygpath -m "$RAW")"
curl -sf -o "$RAW/versions.json" https://ddragon.leagueoflegends.com/api/versions.json
B=https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR
curl -sf -o "$RAW/item.json" "$B/item.json"
curl -sf -o "$RAW/runesReforged.json" "$B/runesReforged.json"
curl -sf -o "$RAW/summoner.json" "$B/summoner.json"
curl -sf -o "$RAW/champion_KSante.json" "$B/champion/KSante.json"
python -I - "$RAW" LoLKit/Tests/LoLKitTests/Fixtures <<'EOF'
# Réduit les fichiers Data Dragon bruts (16.17.1, fr_FR) aux entrées dont les tests ont besoin.
import json, sys
raw, out = sys.argv[1], sys.argv[2]

def load(name):
    with open(f"{raw}/{name}", encoding="utf-8") as f:
        return json.load(f)

def dump(name, value):
    with open(f"{out}/{name}", "w", encoding="utf-8", newline="\n") as f:
        json.dump(value, f, ensure_ascii=False, indent=1)
        f.write("\n")

versions = load("versions.json")
start = versions.index("16.20.1")
kept = [v for v in versions[start:] if v.startswith("16.")] + ["15.24.1", versions[-1]]
dump("ddragon_versions.json", kept)

items = load("item.json")
wanted = ["1001", "1036", "1054", "2031", "2055", "3071", "3340", "3364", "6692"]
dump("ddragon_item.json", {
    "type": items["type"], "version": items["version"],
    "data": {i: {k: items["data"][i][k] for k in ["name", "plaintext", "image", "gold", "tags"]} for i in wanted},
})

runes = load("runesReforged.json")
dump("ddragon_runesReforged.json", [
    {"id": s["id"], "key": s["key"], "icon": s["icon"], "name": s["name"],
     "slots": [{"runes": [{k: r[k] for k in ["id", "key", "icon", "name"]} for r in slot["runes"]]} for slot in s["slots"]]}
    for s in runes if s["id"] in (8400, 8300)
])

summoner = load("summoner.json")
spells = ["SummonerBarrier", "SummonerBoost", "SummonerDot", "SummonerExhaust", "SummonerFlash", "SummonerHaste",
          "SummonerHeal", "SummonerSmite", "SummonerTeleport"]
dump("ddragon_summoner.json", {
    "type": summoner["type"], "version": summoner["version"],
    "data": {s: {k: summoner["data"][s][k] for k in ["id", "name", "key", "image"]} for s in spells},
})

champion = load("champion_KSante.json")
ksante = champion["data"]["KSante"]
dump("ddragon_champion_KSante.json", {
    "type": champion["type"], "version": champion["version"],
    "data": {"KSante": {
        "id": ksante["id"], "key": ksante["key"], "name": ksante["name"], "image": ksante["image"],
        "spells": [{k: s[k] for k in ["id", "name", "image"]} for s in ksante["spells"]],
        "passive": {k: ksante["passive"][k] for k in ["name", "image"]},
    }},
})
EOF
rm -rf "$RAW"
(cd LoLKit/Tests/LoLKitTests/Fixtures && sha256sum ddragon_*.json)
```

Expected (empreintes exactes ; la version 16.17.1 de Data Dragon ne change plus, et la liste des versions est coupée à partir de « 16.20.1 », donc les versions publiées plus tard n'y entrent pas) :

```
acb7ebbbaa9e3efe0a1d97859426128b78d34a2c42885af9976ba444b86fec93 *ddragon_champion_KSante.json
5bc24a6e9fc715c69f79ff0cda6b320126deb35aea41d5b99801cccf3d5a28b1 *ddragon_item.json
939d700d57f28c5813af06277f63074a75ac82a604d7b4413672644137552f57 *ddragon_runesReforged.json
7c5042d2b51c49cb36d543047cd459fcdfeb49053d37cf0d1da2eabfcc49ef70 *ddragon_summoner.json
71c77b50de50465e93cd1e8581600a3c0c0333e73761423f29af21e53ea47354 *ddragon_versions.json
```

Contenu exact de `ddragon_versions.json` (22 entrées, une par ligne avec `indent=1`) : `["16.20.1","16.19.1","16.18.1","16.17.1","16.16.1","16.15.1","16.14.1","16.13.1","16.12.1","16.11.1","16.10.1","16.9.1","16.8.1","16.7.1","16.6.1","16.5.1","16.4.1","16.3.1","16.2.1","16.1.1","15.24.1","lolpatch_3.7"]`.

- [ ] **Step 2: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/DataDragonTests.swift` :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli choisit la version, écrit les liens et lit les catalogues.
import LoLKit

/// Data Dragon (spec fonctionnalités §3), sur de vrais fichiers réduits (version 16.17.1, fr_FR, capturés le 14/10/2026).
@Suite struct DataDragonTests {
    private func versions() throws -> [String] {
        try DataDragon.decodeVersions(Fixture.data("ddragon_versions"))
    }

    @Test func versionOfThePatchOfTheFeed() throws {
        let list = try versions()
        #expect(list.count == 22)
        #expect(list.first == "16.20.1")
        // Patchs réels des fixtures window_* : 16.17 (finale LCS), 16.18 (Demacia Cup).
        #expect(DataDragon.version(forPatch: "16.17.815.3183", versions: list) == "16.17.1")
        #expect(DataDragon.version(forPatch: "16.18.819.1060", versions: list) == "16.18.1")
        // « 16.1. » ne prend pas « 16.18.1 » ni « 16.19.1 ».
        #expect(DataDragon.version(forPatch: "16.1.540.1", versions: list) == "16.1.1")
        #expect(DataDragon.version(forPatch: "15.24.700.1", versions: list) == "15.24.1")
    }

    @Test func unknownPatchFallsBackToTheMostRecent() throws {
        let list = try versions()
        #expect(DataDragon.version(forPatch: "16.21.900.1", versions: list) == "16.20.1")
        #expect(DataDragon.version(forPatch: nil, versions: list) == "16.20.1")
        #expect(DataDragon.version(forPatch: "", versions: list) == "16.20.1")
        #expect(DataDragon.version(forPatch: "16", versions: list) == "16.20.1")
        // Les entrées « lolpatch_* » ne sont jamais des versions.
        #expect(DataDragon.version(forPatch: "16.17.1", versions: ["lolpatch_3.7"]) == nil)
        #expect(DataDragon.version(forPatch: "16.17.1", versions: []) == nil)
    }

    @Test func imageAndDataLinks() {
        #expect(DataDragon.versionsURL.absoluteString == "https://ddragon.leagueoflegends.com/api/versions.json")
        #expect(DataDragon.versionsMaxAge == 86_400)
        #expect(DataDragon.championImage(version: "16.17.1", championId: "KSante").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/champion/KSante.png")
        #expect(DataDragon.itemImage(version: "16.17.1", itemId: 3364).absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/item/3364.png")
        #expect(DataDragon.spellImage(version: "16.17.1", file: "KSanteQ.png").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/spell/KSanteQ.png")
        #expect(DataDragon.passiveImage(version: "16.17.1", file: "Icons_KSante_P.png").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/passive/Icons_KSante_P.png")
        #expect(DataDragon.summonerSpellImage(version: "16.17.1", spellId: "SummonerFlash").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/spell/SummonerFlash.png")
        #expect(DataDragon.runeIcon("perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/img/perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png")
        #expect(DataDragon.itemsURL(version: "16.17.1").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/item.json")
        #expect(DataDragon.runesURL(version: "16.17.1").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/runesReforged.json")
        #expect(DataDragon.summonerSpellsURL(version: "16.17.1").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/summoner.json")
        #expect(DataDragon.championURL(version: "16.17.1", championId: "KSante").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/data/fr_FR/champion/KSante.json")
        // Un id inattendu du flux est encodé, le lien reste valide.
        #expect(DataDragon.championImage(version: "16.17.1", championId: "Nouveau Champion").absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.17.1/img/champion/Nouveau%20Champion.png")
    }

    @Test func itemCatalog() throws {
        let catalog = try ItemCatalog(json: Fixture.data("ddragon_item"))
        #expect(catalog.version == "16.17.1")
        #expect(catalog.items.count == 9)
        #expect(catalog.item(6692) == ItemCatalog.Item(id: 6692, name: "Éclipse", image: "6692.png", isTrinket: false))
        #expect(catalog.item(3364) == ItemCatalog.Item(id: 3364, name: "Brouilleur oraculaire", image: "3364.png",
                                                       isTrinket: true))
        #expect(catalog.item(3340)?.isTrinket == true)
        #expect(catalog.item(2055)?.name == "Balise de contrôle")
        #expect(catalog.item(2055)?.isTrinket == false)
        #expect(catalog.item(9999) == nil)
        // Objets réels du joueur 1 (TLAW Morgan) dans la fixture details_ingame : la balise passe à part.
        #expect(catalog.inventory([1054, 2031, 6692, 1001, 3364, 3071, 1036])
                == ItemCatalog.Inventory(items: [1054, 2031, 6692, 1001, 3071, 1036], trinket: 3364))
        #expect(catalog.inventory([1054, 4242]) == ItemCatalog.Inventory(items: [1054, 4242], trinket: nil))
    }

    @Test func runeCatalog() throws {
        let catalog = try RuneCatalog(json: Fixture.data("ddragon_runesReforged"))
        #expect(catalog.styles.count == 2)
        #expect(catalog.runes.count == 24)
        #expect(catalog.style(8400) == RuneCatalog.Entry(id: 8400, key: "Resolve", name: "Volonté",
                                                         icon: "perk-images/Styles/7204_Resolve.png"))
        #expect(catalog.style(8300)?.icon == "perk-images/Styles/7203_Whimsy.png")
        #expect(catalog.rune(8437) == RuneCatalog.Entry(
            id: 8437, key: "GraspOfTheUndying", name: "Poigne de l'immortel",
            icon: "perk-images/Styles/Resolve/GraspOfTheUndying/GraspOfTheUndying.png"))
        #expect(catalog.rune(8345)?.name == "Livraison de biscuits")
        // Fragments de stats (5008…) : absents de runesReforged.json.
        #expect(catalog.rune(5008) == nil)
    }

    @Test func summonerCatalog() throws {
        let catalog = try SummonerCatalog(json: Fixture.data("ddragon_summoner"))
        #expect(catalog.spells.count == 9)
        #expect(catalog.spell("SummonerFlash") == SummonerCatalog.Spell(id: "SummonerFlash", name: "Saut éclair",
                                                                       image: "SummonerFlash.png"))
        #expect(catalog.spell("SummonerDot")?.name == "Embrasement")
        #expect(catalog.spell("SummonerBoost")?.name == "Purge")
        #expect(catalog.spell("SummonerTeleport")?.name == "Téléportation")
        #expect(catalog.spell("Flash") == nil)
    }

    @Test func championSpells() throws {
        let ksante = try ChampionSpells(json: Fixture.data("ddragon_champion_KSante"))
        #expect(ksante.championId == "KSante")
        #expect(ksante.name == "K'Santé")
        #expect(ksante.spells.map(\.image) == ["KSanteQ.png", "KSanteW.png", "KSanteE.png", "KSanteR.png"])
        #expect(ksante.spell(forAbility: "Q") == ChampionSpells.Ability(name: "Coups de ntofo", image: "KSanteQ.png"))
        #expect(ksante.spell(forAbility: "r")?.name == "Grand jeu")
        #expect(ksante.spell(forAbility: "P") == nil)
        #expect(ksante.passive == ChampionSpells.Ability(name: "Instinct intrépide", image: "Icons_KSante_P.png"))
    }

    @Test func toleratesUnreadableEntries() throws {
        let items = #"{"version":"16.17.1","data":{"1001":{"name":"Bottes","image":{"full":"1001.png"},"tags":["Boots"]},"1002":{"name":7},"abc":{"name":"x","image":{"full":"x.png"}}}}"#
        let catalog = try ItemCatalog(json: Data(items.utf8))
        #expect(catalog.items.keys.sorted() == [1001])
        let summoners = #"{"data":{"SummonerFlash":{"id":"SummonerFlash","name":"Saut éclair","image":{"full":"SummonerFlash.png"}},"Bad":{}}}"#
        #expect(try SummonerCatalog(json: Data(summoners.utf8)).spells.count == 1)
        #expect(throws: (any Error).self) { try ChampionSpells(json: Data(#"{"data":{}}"#.utf8)) }
    }
}
```

- [ ] **Step 3: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter DataDragonTests`
Expected : FAIL à la compilation (`cannot find 'DataDragon' in scope`, `cannot find 'ItemCatalog' in scope`…).

- [ ] **Step 4: Écrire `DataDragon` (version et liens)**

Créer `LoLKit/Sources/LoLKit/Media/DataDragon.swift` :

```swift
import Foundation

/// Data Dragon (`ddragon.leagueoflegends.com`) : images et données officielles de Riot, sans clé (spec fonctionnalités §3).
/// Ce fichier ne fait que choisir la version et écrire les liens ; l'appli télécharge et met en cache disque.
public enum DataDragon {
    static let base = "https://ddragon.leagueoflegends.com"
    /// Langue des données (noms d'objets, de runes, de sorts).
    public static let language = "fr_FR"
    /// Liste des versions, la plus récente d'abord. À relire au plus une fois toutes les 24 h.
    public static let versionsURL = URL(string: "\(base)/api/versions.json")!
    public static let versionsMaxAge: TimeInterval = 24 * 3600

    /// Version Data Dragon d'un patch du flux (`gameMetadata.patchVersion`, ex. « 16.18.819.1060 ») : la plus récente
    /// qui commence par « major.minor. » (« 16.18.1 »), sinon la plus récente. Les entrées `lolpatch_*` sont ignorées.
    /// nil si la liste n'a aucune version.
    /// - Parameter versions: `api/versions.json`, dans son ordre (la plus récente d'abord).
    public static func version(forPatch patch: String?, versions: [String]) -> String? {
        let releases = versions.filter { $0.first?.isNumber == true }
        if let patch {
            let parts = patch.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty {
                // Le point final compte : « 16.1. » ne doit pas prendre « 16.18.1 ».
                let prefix = "\(parts[0]).\(parts[1])."
                if let match = releases.first(where: { $0.hasPrefix(prefix) }) { return match }
            }
        }
        return releases.first
    }

    /// Lit `api/versions.json` (un tableau de chaînes).
    public static func decodeVersions(_ data: Data) throws -> [String] {
        try JSONDecoder().decode([String].self, from: data)
    }

    // MARK: Images

    /// `cdn/<v>/img/champion/<championId>.png` (`championId` du flux, ex. « KSante »).
    public static func championImage(version: String, championId: String) -> URL {
        url("cdn/\(version)/img/champion/\(championId).png")
    }

    /// `cdn/<v>/img/item/<id>.png`
    public static func itemImage(version: String, itemId: Int) -> URL {
        url("cdn/\(version)/img/item/\(itemId).png")
    }

    /// Sort d'un champion : `cdn/<v>/img/spell/<image.full>` (ex. « KSanteQ.png »).
    public static func spellImage(version: String, file: String) -> URL {
        url("cdn/\(version)/img/spell/\(file)")
    }

    /// Passif d'un champion : `cdn/<v>/img/passive/<image.full>`.
    public static func passiveImage(version: String, file: String) -> URL {
        url("cdn/\(version)/img/passive/\(file)")
    }

    /// Sort d'invocateur : `cdn/<v>/img/spell/<id>.png` (ex. « SummonerFlash »).
    public static func summonerSpellImage(version: String, spellId: String) -> URL {
        url("cdn/\(version)/img/spell/\(spellId).png")
    }

    /// Icône de rune ou d'arbre (`icon` de `runesReforged.json`) : `cdn/img/<icon>`, sans version.
    public static func runeIcon(_ icon: String) -> URL {
        url("cdn/img/\(icon)")
    }

    // MARK: Données (fr_FR)

    public static func itemsURL(version: String) -> URL {
        url("cdn/\(version)/data/\(language)/item.json")
    }

    public static func runesURL(version: String) -> URL {
        url("cdn/\(version)/data/\(language)/runesReforged.json")
    }

    public static func summonerSpellsURL(version: String) -> URL {
        url("cdn/\(version)/data/\(language)/summoner.json")
    }

    /// Détail d'un champion (sorts et passif) : `data/fr_FR/champion/<championId>.json`.
    public static func championURL(version: String, championId: String) -> URL {
        url("cdn/\(version)/data/\(language)/champion/\(championId).json")
    }

    /// Chemin encodé pour une URL (un id venu du flux ne peut pas casser le lien) ; après encodage, `URL(string:)` réussit
    /// toujours sur cette base https.
    private static func url(_ path: String) -> URL {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(base)/\(encoded)")!
    }
}
```

- [ ] **Step 5: Écrire les catalogues**

Créer `LoLKit/Sources/LoLKit/Media/DataDragonCatalogs.swift` :

```swift
import Foundation

/// Objets (`data/fr_FR/item.json`) : nom, image et balise par id.
public struct ItemCatalog: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let id: Int
        public let name: String
        /// Fichier d'image (`image.full`, ex. « 1054.png ») ; l'URL vient de `DataDragon.itemImage`.
        public let image: String
        /// Balise (tag Data Dragon « Trinket ») : affichée à part, après les 6 objets.
        public let isTrinket: Bool

        public init(id: Int, name: String, image: String, isTrinket: Bool) {
            self.id = id
            self.name = name
            self.image = image
            self.isTrinket = isTrinket
        }
    }

    /// Les objets d'un joueur, balise à part (ligne « 6 objets + balise » du Détail).
    public struct Inventory: Sendable, Equatable {
        /// Objets dans l'ordre du flux, sans la balise.
        public let items: [Int]
        public let trinket: Int?

        public init(items: [Int], trinket: Int?) {
            self.items = items
            self.trinket = trinket
        }
    }

    public let version: String?
    public let items: [Int: Item]

    public init(version: String?, items: [Int: Item]) {
        self.version = version
        self.items = items
    }

    /// Lit `item.json`. Un objet illisible est ignoré (décodage tolérant).
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        var items: [Int: Item] = [:]
        for (key, entry) in file.data {
            guard let id = Int(key), let raw = entry.value else { continue }
            items[id] = Item(id: id, name: raw.name, image: raw.image.full, isTrinket: raw.tags?.contains("Trinket") ?? false)
        }
        self.init(version: file.version, items: items)
    }

    public func item(_ id: Int) -> Item? { items[id] }

    /// Sépare la balise des autres objets ; un id inconnu du catalogue reste un objet.
    public func inventory(_ ids: [Int]) -> Inventory {
        let trinket = ids.first { items[$0]?.isTrinket == true }
        return Inventory(items: ids.filter { $0 != trinket }, trinket: trinket)
    }

    private struct File: Decodable {
        let version: String?
        let data: [String: Tolerant<Raw>]
    }

    private struct Raw: Decodable {
        struct Image: Decodable { let full: String }
        let name: String
        let image: Image
        let tags: [String]?
    }
}

/// Runes et arbres (`data/fr_FR/runesReforged.json`) : nom et icône par id.
public struct RuneCatalog: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let id: Int
        public let key: String
        public let name: String
        /// Chemin d'icône (ex. « perk-images/Styles/7204_Resolve.png ») ; l'URL vient de `DataDragon.runeIcon`.
        public let icon: String

        public init(id: Int, key: String, name: String, icon: String) {
            self.id = id
            self.key = key
            self.name = name
            self.icon = icon
        }
    }

    /// Arbres (`styleId`, `subStyleId` de `perkMetadata`).
    public let styles: [Int: Entry]
    /// Runes (`perks` de `perkMetadata` ; la première est la rune principale).
    public let runes: [Int: Entry]

    public init(styles: [Int: Entry], runes: [Int: Entry]) {
        self.styles = styles
        self.runes = runes
    }

    /// Lit `runesReforged.json`. Un arbre illisible est ignoré.
    public init(json: Data) throws {
        let styles = try JSONDecoder().decode([Tolerant<Style>].self, from: json).compactMap(\.value)
        var styleEntries: [Int: Entry] = [:]
        var runeEntries: [Int: Entry] = [:]
        for style in styles {
            styleEntries[style.id] = Entry(id: style.id, key: style.key, name: style.name, icon: style.icon)
            for rune in style.slots.flatMap(\.runes) {
                runeEntries[rune.id] = Entry(id: rune.id, key: rune.key, name: rune.name, icon: rune.icon)
            }
        }
        self.init(styles: styleEntries, runes: runeEntries)
    }

    public func style(_ id: Int) -> Entry? { styles[id] }

    public func rune(_ id: Int) -> Entry? { runes[id] }

    private struct Style: Decodable {
        struct Slot: Decodable { let runes: [Rune] }
        struct Rune: Decodable {
            let id: Int
            let key: String
            let icon: String
            let name: String
        }

        let id: Int
        let key: String
        let icon: String
        let name: String
        let slots: [Slot]
    }
}

/// Sorts d'invocateur (`data/fr_FR/summoner.json`) : nom et image par id Data Dragon (« SummonerFlash »).
public struct SummonerCatalog: Sendable, Equatable {
    public struct Spell: Sendable, Equatable {
        /// Id Data Dragon, ex. « SummonerFlash » ; l'URL vient de `DataDragon.summonerSpellImage`.
        public let id: String
        public let name: String
        public let image: String

        public init(id: String, name: String, image: String) {
            self.id = id
            self.name = name
            self.image = image
        }
    }

    public let spells: [String: Spell]

    public init(spells: [String: Spell]) {
        self.spells = spells
    }

    /// Lit `summoner.json`. Un sort illisible est ignoré.
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        var spells: [String: Spell] = [:]
        for (key, entry) in file.data {
            guard let raw = entry.value else { continue }
            spells[key] = Spell(id: raw.id, name: raw.name, image: raw.image.full)
        }
        self.init(spells: spells)
    }

    public func spell(_ id: String) -> Spell? { spells[id] }

    private struct File: Decodable {
        let data: [String: Tolerant<Raw>]
    }

    private struct Raw: Decodable {
        struct Image: Decodable { let full: String }
        let id: String
        let name: String
        let image: Image
    }
}

/// Sorts d'un champion (`data/fr_FR/champion/<id>.json`) : Q, W, E, R et passif, pour l'ordre de montée.
public struct ChampionSpells: Sendable, Equatable {
    public struct Ability: Sendable, Equatable {
        public let name: String
        /// Fichier d'image (`image.full`) ; URL : `DataDragon.spellImage` (sorts) ou `DataDragon.passiveImage` (passif).
        public let image: String

        public init(name: String, image: String) {
            self.name = name
            self.image = image
        }
    }

    public let championId: String
    public let name: String
    /// Q, W, E, R, dans cet ordre.
    public let spells: [Ability]
    public let passive: Ability?

    public init(championId: String, name: String, spells: [Ability], passive: Ability?) {
        self.championId = championId
        self.name = name
        self.spells = spells
        self.passive = passive
    }

    /// Lit `champion/<id>.json` (un seul champion dans `data`).
    public init(json: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: json)
        guard let champion = file.data.values.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Aucun champion dans le fichier"))
        }
        self.init(championId: champion.id, name: champion.name,
                  spells: champion.spells.map { Ability(name: $0.name, image: $0.image.full) },
                  passive: champion.passive.map { Ability(name: $0.name, image: $0.image.full) })
    }

    /// Sort d'une lettre de l'ordre de montée (`abilities` du flux `details` : « Q », « W », « E » ou « R ») ; nil sinon.
    public func spell(forAbility letter: String) -> Ability? {
        guard let index = ["Q", "W", "E", "R"].firstIndex(of: letter.uppercased()), spells.indices.contains(index) else {
            return nil
        }
        return spells[index]
    }

    private struct File: Decodable {
        let data: [String: Raw]
    }

    private struct Raw: Decodable {
        struct Image: Decodable { let full: String }
        struct Spell: Decodable {
            let name: String
            let image: Image
        }

        let id: String
        let name: String
        let spells: [Spell]
        let passive: Spell?
    }
}

/// Valeur décodée si possible, sinon nil : un élément illisible n'empêche pas de lire les autres.
private struct Tolerant<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
```

- [ ] **Step 6: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter DataDragonTests`
Expected : PASS — `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 7: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 266 tests in 30 suites passed`, aucun `warning:`.

- [ ] **Step 8: Commit**

```bash
git add LoLKit/Sources/LoLKit/Media/DataDragon.swift LoLKit/Sources/LoLKit/Media/DataDragonCatalogs.swift LoLKit/Tests/LoLKitTests/DataDragonTests.swift LoLKit/Tests/LoLKitTests/Fixtures/ddragon_versions.json LoLKit/Tests/LoLKitTests/Fixtures/ddragon_item.json LoLKit/Tests/LoLKitTests/Fixtures/ddragon_runesReforged.json LoLKit/Tests/LoLKitTests/Fixtures/ddragon_summoner.json LoLKit/Tests/LoLKitTests/Fixtures/ddragon_champion_KSante.json
git commit -m "feat(lolkit): Data Dragon — version du patch, liens d'images, catalogues objets, runes, sorts d'invocateur et sorts de champion (fr_FR)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Pousser la branche et vérifier la CI**

```bash
git push -u origin fonc/lolkit-t3-data-dragon
gh run list --workflow LoLKit --branch fonc/lolkit-t3-data-dragon --limit 1
gh run watch --exit-status <id de la ligne affichée>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task 4: Flux `details` (objets, runes, sorts, part des dégâts) avec le recul partagé

**Branche :** `fonc/lolkit-t4-details`

**Files:**
- Modify: `LoLKit/Sources/LoLKit/API/LoLClient.swift:49-84` (`window` et `liveWindow`), `:95-96` (doc de `LiveStatsTime`), `:107` (doc de `memory`) — **T4 est la seule tâche qui touche ce fichier.**
- Create: `LoLKit/Sources/LoLKit/API/LoLClient+Details.swift`
- Create: `LoLKit/Sources/LoLKit/Models/GameDetails.swift`
- Test: `LoLKit/Tests/LoLKitTests/GameDetailsTests.swift`
- Fixture (créée) : `details_ingame.json` — vraie réponse `details` de la game 1 de la finale LCS (TLAW – LYON, game `115565004607949430`, même instant que `window_ingame.json`), réduite à sa première et sa dernière frame.

**Interfaces:**
- Consumes (à `HEAD`) : `LiveStatsTime.delays: [TimeInterval]`, `LiveStatsTime.startingTime(now: Date, delay: TimeInterval) -> Date`, `LiveStatsTime.memory` (`DelayMemory.delayIndex(for: String) -> Int`, `remember(_ index: Int, for: String)`), `LoLDate.format(_:)`, `JSONDecoder.lolesports()`, `LoLAPIError` (`.http(status:)`, `.statsDisabled`, `.noData`), `HTTPTransport.get(_:headers:)` ; tests : `FakeTransport`, `queryValue(_:_:)`, `date(_:)`, fixture `window_ingame.json`.
- Produces :
  - `LoLClient.details(gameId: String, startingTime: Date?) async throws -> GameDetails`, `LoLClient.details(gameId: String, now: Date) async throws -> GameDetails`, `LoLClient.detailsInterval: TimeInterval = 60`.
  - `public struct GameDetails: Codable, Sendable, Equatable { frames: [DetailsFrame] }` + `latestFrame: DetailsFrame?`, `latest(participantId: Int) -> ParticipantDetails?`.
  - `public struct DetailsFrame { rfc460Timestamp: Date; participants: [ParticipantDetails] }`.
  - `public struct PerkMetadata { styleId: Int; subStyleId: Int; perks: [Int] }` + `keystone: Int?`.
  - `public struct ParticipantDetails { participantId, level, kills, deaths, assists, creepScore, totalGoldEarned: Int; killParticipation: Double?; championDamageShare: Double?; wardsPlaced: Int?; wardsDestroyed: Int?; items: [Int]; perkMetadata: PerkMetadata?; abilities: [String] }` (init public avec tous les champs dans cet ordre).
  - Interne au module : `LoLClient.feed(_:gameId:startingTime:as:)`, `LoLClient.steppingBack(gameId:now:_:)` (pour T4 seulement).
  - `window(gameId:startingTime:)` et `liveWindow(gameId:now:)` gardent leur signature et leur comportement (`LoLClientTests` inchangés et verts).

- [ ] **Step 1: Refactoriser `LoLClient.swift` sans changer son comportement**

Dans `LoLKit/Sources/LoLKit/API/LoLClient.swift`, remplacer les lignes 49-84 (de `    /// Frames de stats d'une game. Sans `startingTime`…` jusqu'à l'accolade qui ferme `liveWindow`) par :

```swift
    /// Frames de stats d'une game. Sans `startingTime`, le flux renvoie le début de la game.
    public func window(gameId: String, startingTime: Date?) async throws -> LiveWindow {
        try await feed("window", gameId: gameId, startingTime: startingTime, as: LiveWindow.self)
    }

    /// Dernières frames d'une game en cours. Le flux refuse (400 « ahead of broadcast ») une fenêtre dont la fin a moins
    /// de 80 s (mesuré le 14/10/2026 à 0,5 s près sur 78 requêtes) : on recule par paliers (`steppingBack`).
    public func liveWindow(gameId: String, now: Date) async throws -> LiveWindow {
        try await steppingBack(gameId: gameId, now: now) { startingTime in
            try await window(gameId: gameId, startingTime: startingTime)
        }
    }

    /// Lecture d'une route du flux livestats (`window`, `details`), sans clé : 200 vide ou 204 = pas encore de données,
    /// 404 = stats désactivées par Riot pour cette game.
    func feed<T: Decodable & Sendable>(_ route: String, gameId: String, startingTime: Date?,
                                       as type: T.Type) async throws -> T {
        var components = URLComponents(string: "\(Self.feedBase)/\(route)/\(gameId)")!
        if let startingTime {
            components.queryItems = [URLQueryItem(name: "startingTime", value: LoLDate.format(startingTime))]
        }
        let response = try await transport.get(components.url!, headers: [:])
        switch response.status {
        case 200 where !response.body.isEmpty:
            return try JSONDecoder.lolesports().decode(T.self, from: response.body)
        case 200, 204:
            throw LoLAPIError.noData
        case 404:
            throw LoLAPIError.statsDisabled
        default:
            throw LoLAPIError.http(status: response.status)
        }
    }

    /// Recul commun à `liveWindow` et `details(gameId:now:)` : essaie `read` avec les délais de `LiveStatsTime.delays`, à
    /// partir du dernier délai accepté pour cette game, passe au suivant sur un 400, et retient le premier accepté. Les
    /// deux routes partagent cette mémoire (même flux, même seuil de 80 s).
    func steppingBack<T: Sendable>(gameId: String, now: Date,
                                   _ read: (Date) async throws -> T) async throws -> T {
        let first = await LiveStatsTime.memory.delayIndex(for: gameId)
        for index in first..<LiveStatsTime.delays.count {
            do {
                let value = try await read(LiveStatsTime.startingTime(now: now, delay: LiveStatsTime.delays[index]))
                await LiveStatsTime.memory.remember(index, for: gameId)
                return value
            } catch LoLAPIError.http(status: 400) {
                continue
            }
        }
        throw LoLAPIError.http(status: 400)
    }
```

Puis remplacer les lignes 95-96 :

```swift
/// Heure à demander au flux livestats : un délai dans le passé, arrondi aux 10 s inférieures. Le flux refuse une fenêtre
/// trop récente (en avance sur la diffusion) : `LoLClient.liveWindow` essaie ces délais dans l'ordre.
```

par :

```swift
/// Heure à demander au flux livestats : un délai dans le passé, arrondi aux 10 s inférieures. Le flux refuse une fenêtre
/// trop récente (en avance sur la diffusion) : `LoLClient.liveWindow` et `LoLClient.details(gameId:now:)` essaient ces
/// délais dans l'ordre.
```

et la ligne 107 (`    /// Délai accepté par game, gardé pour la durée du processus (le seuil ne change pas pendant un match).`) par :

```swift
    /// Délai accepté par game, gardé pour la durée du processus (le seuil ne change pas pendant un match) ; partagé par
    /// `window` et `details`.
```

Run : `bash scripts/lolkit.sh test --filter LoLClientTests`
Expected : PASS — `Test run with 11 tests in 1 suite passed` (comportement de `window` et `liveWindow` inchangé).

- [ ] **Step 2: Capturer et réduire la fixture**

```bash
RAW="$(mktemp -d)"; command -v cygpath >/dev/null && RAW="$(cygpath -m "$RAW")"
curl -sf -o "$RAW/details.json" "https://feed.lolesports.com/livestats/v1/details/115565004607949430?startingTime=2026-10-04T20:38:20.000Z"
python -I - "$RAW/details.json" LoLKit/Tests/LoLKitTests/Fixtures/details_ingame.json <<'EOF'
# Garde la première et la dernière frame d'une réponse livestats/v1/details (les 10 joueurs, tous leurs champs).
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as f:
    details = json.load(f)
trimmed = {"frames": [details["frames"][0], details["frames"][-1]]}
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    json.dump(trimmed, f, ensure_ascii=False, indent=1)
    f.write("\n")
EOF
rm -rf "$RAW"
sha256sum LoLKit/Tests/LoLKitTests/Fixtures/details_ingame.json
```

Expected : `5249571876da08f851a7235e21c6d0140e4ff04400e2ebfec5abcde5eda7277d` (19 410 octets ; la réponse brute fait 37 frames, de `2026-10-04T20:38:20.473Z` à `2026-10-04T20:38:29.593Z` ; le flux sert les games passées à l'identique, vérifié deux fois le 14/10/2026).

- [ ] **Step 3: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/GameDetailsTests.swift` :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli lit `details` avec la seule API publique.
import LoLKit

/// Flux `livestats/v1/details` (spec fonctionnalités §3). Fixture : vraie réponse de la game 1 de la finale LCS
/// (TLAW – LYON, 04/10/2026), `startingTime=2026-10-04T20:38:20.000Z`, réduite à sa première et sa dernière frame.
@Suite struct GameDetailsTests {
    private static let gameId = "115565004607949430"

    /// Réponse réelle du flux `details` (14/10/2026, Demacia Cup) quand la fenêtre demandée est trop récente.
    private let aheadOfBroadcast = #"{"httpStatus":400,"errorCode":"BAD_QUERY_PARAMETER","message":"disallowed window with end time less than 80 sec old (was 21.34 sec old). requested window: [2026-10-14T11:28:50Z, 2026-10-14T11:29:00Z]) ahead of broadcast. current time: 2026-10-14T11:29:21.337178735Z","implementationDetails":"filtered"}"#

    @Test func decodesTheRealDetails() async throws {
        let fake = FakeTransport()
        try await fake.on("details/\(Self.gameId)", fixture: "details_ingame")
        let details = try await LoLClient(transport: fake).details(gameId: Self.gameId,
                                                                   startingTime: date("2026-10-04T20:38:20Z"))
        let request = try #require(await fake.requests.first)
        #expect(request.url.host == "feed.lolesports.com")
        #expect(request.url.path == "/livestats/v1/details/115565004607949430")
        #expect(queryValue(request.url, "startingTime") == "2026-10-04T20:38:20.000Z")
        #expect(request.headers["x-api-key"] == nil)

        #expect(details.frames.count == 2)
        #expect(details.latestFrame?.rfc460Timestamp == date("2026-10-04T20:38:29.593Z"))
        #expect(details.latestFrame?.participants.map(\.participantId) == Array(1...10))
        #expect(details.frames.first?.participants.first?.totalGoldEarned == 7502)

        // Joueur 1 (TLAW Morgan, Ambessa, haut).
        let morgan = try #require(details.latest(participantId: 1))
        #expect(morgan.level == 14)
        #expect(morgan.kills == 0)
        #expect(morgan.deaths == 1)
        #expect(morgan.assists == 0)
        #expect(morgan.creepScore == 204)
        #expect(morgan.totalGoldEarned == 7520)
        #expect(morgan.killParticipation == 0)
        #expect(abs((morgan.championDamageShare ?? 0) - 0.2743) < 0.0001)
        #expect(morgan.wardsPlaced == 7)
        #expect(morgan.wardsDestroyed == 0)
        #expect(morgan.items == [1054, 2031, 6692, 1001, 3364, 3071, 1036])
        #expect(morgan.perkMetadata == PerkMetadata(styleId: 8400, subStyleId: 8300,
                                                    perks: [8437, 8401, 8444, 8451, 8345, 8347, 5008, 5011]))
        #expect(morgan.perkMetadata?.keystone == 8437)
        #expect(morgan.abilities.joined() == "QWEQQRQEQEREEW")

        // Joueur 2 (TLAW Josedeodo, Lee Sin) : mêmes valeurs que sa ligne dans window_ingame (12, 3/1/3, 169 CS, 8359).
        let josedeodo = try #require(details.latest(participantId: 2))
        #expect(josedeodo.level == 12)
        #expect(josedeodo.kills == 3)
        #expect(josedeodo.deaths == 1)
        #expect(josedeodo.assists == 3)
        #expect(josedeodo.creepScore == 169)
        #expect(josedeodo.totalGoldEarned == 8359)
        #expect(abs((josedeodo.killParticipation ?? 0) - 0.8571) < 0.0001)
        #expect(josedeodo.wardsDestroyed == 8)
        #expect(details.latest(participantId: 99) == nil)
        #expect(LoLClient.detailsInterval == 60)
    }

    @Test func stepsBackLikeTheWindow() async throws {
        let fake = FakeTransport()
        try await fake.on("startingTime=2026-10-13T11:59:00", status: 400, body: aheadOfBroadcast)
        try await fake.on("details/step-back-details", fixture: "details_ingame")
        let client = LoLClient(transport: fake)

        let details = try await client.details(gameId: "step-back-details", now: date("2026-10-13T12:00:37Z"))
        #expect(details.frames.count == 2)
        let urls = await fake.requests.map(\.url)
        #expect(urls.compactMap { queryValue($0, "startingTime") } == ["2026-10-13T11:59:00.000Z", "2026-10-13T11:58:50.000Z"])

        // Le délai accepté (100 s) est retenu : la lecture suivante ne refait pas l'essai refusé.
        _ = try await client.details(gameId: "step-back-details", now: date("2026-10-13T12:00:57Z"))
        #expect(await fake.requests.count == 3)
        #expect(queryValue(try #require(await fake.requests.last?.url), "startingTime") == "2026-10-13T11:59:10.000Z")
    }

    @Test func windowAndDetailsShareTheAcceptedDelay() async throws {
        let fake = FakeTransport()
        try await fake.on("startingTime=2026-10-13T11:59:00", status: 400, body: aheadOfBroadcast)
        try await fake.on("window/shared-delay", fixture: "window_ingame")
        try await fake.on("details/shared-delay", fixture: "details_ingame")
        let client = LoLClient(transport: fake)

        _ = try await client.liveWindow(gameId: "shared-delay", now: date("2026-10-13T12:00:37Z"))
        _ = try await client.details(gameId: "shared-delay", now: date("2026-10-13T12:00:57Z"))
        let last = try #require(await fake.requests.last?.url)
        #expect(last.path == "/livestats/v1/details/shared-delay")
        // Une seule requête `details`, directement au délai retenu par `window` (100 s).
        #expect(await fake.requests.filter { $0.url.path.contains("/details/") }.count == 1)
        #expect(queryValue(last, "startingTime") == "2026-10-13T11:59:10.000Z")
    }

    @Test func detailsErrors() async throws {
        let fake = FakeTransport()
        try await fake.on("details/404", status: 404, body: "Stats are disabled for game 404")
        try await fake.on("details/204", status: 204)
        try await fake.on("details/always-ahead", status: 400, body: aheadOfBroadcast)
        let client = LoLClient(transport: fake)

        await #expect(throws: LoLAPIError.statsDisabled) { try await client.details(gameId: "404", startingTime: nil) }
        await #expect(throws: LoLAPIError.noData) { try await client.details(gameId: "204", startingTime: nil) }
        await #expect(throws: LoLAPIError.statsDisabled) {
            try await client.details(gameId: "404", now: date("2026-10-13T12:00:37Z"))
        }
        let before = await fake.requests.count
        await #expect(throws: LoLAPIError.http(status: 400)) {
            try await client.details(gameId: "always-ahead", now: date("2026-10-13T12:00:37Z"))
        }
        #expect(await fake.requests.count - before == LiveStatsTime.delays.count)
    }

    @Test func toleratesMissingFields() throws {
        let json = #"{"frames":[{"rfc460Timestamp":"2026-10-04T20:38:29.593Z","participants":[{"participantId":3,"items":"?"}]}]}"#
        let details = try JSONDecoder.lolesports().decode(GameDetails.self, from: Data(json.utf8))
        let player = try #require(details.latest(participantId: 3))
        #expect(player.items.isEmpty)
        #expect(player.abilities.isEmpty)
        #expect(player.perkMetadata == nil)
        #expect(player.level == 0)
        #expect(player.championDamageShare == nil)
    }
}
```

- [ ] **Step 4: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter GameDetailsTests`
Expected : FAIL à la compilation (`value of type 'LoLClient' has no member 'details'`, `cannot find 'GameDetails' in scope`, `cannot find 'PerkMetadata' in scope`).

- [ ] **Step 5: Écrire les modèles**

Créer `LoLKit/Sources/LoLKit/Models/GameDetails.swift` :

```swift
import Foundation

/// Réponse de `livestats/v1/details/{gameId}` : environ 10 s de frames, chacune avec le détail des 10 joueurs (objets,
/// runes, ordre de montée des sorts, part des dégâts…). Pas de `gameMetadata` ici : champion, pseudo et côté se lisent
/// dans `LiveWindow.gameMetadata` par `participantId` (1-5 bleu, 6-10 rouge). Lourd : l'appli ne le lit qu'avec le Détail
/// ouvert, au plus toutes les 60 s, jamais pour un match masqué (spec fonctionnalités §3).
public struct GameDetails: Codable, Sendable, Equatable {
    public let frames: [DetailsFrame]

    public init(frames: [DetailsFrame]) {
        self.frames = frames
    }

    /// Dernière frame : l'état le plus récent.
    public var latestFrame: DetailsFrame? { frames.last }

    /// Détail du joueur `participantId` à la dernière frame ; nil s'il n'y figure pas.
    public func latest(participantId: Int) -> ParticipantDetails? {
        latestFrame?.participants.first { $0.participantId == participantId }
    }
}

public struct DetailsFrame: Codable, Sendable, Equatable {
    public let rfc460Timestamp: Date
    public let participants: [ParticipantDetails]

    public init(rfc460Timestamp: Date, participants: [ParticipantDetails]) {
        self.rfc460Timestamp = rfc460Timestamp
        self.participants = participants
    }
}

/// Runes d'un joueur : arbre principal (`styleId`), arbre secondaire (`subStyleId`) et runes choisies (`perks`, la première
/// est la rune principale ; les dernières sont des fragments de stats, absents de `runesReforged.json`).
public struct PerkMetadata: Codable, Sendable, Equatable {
    public let styleId: Int
    public let subStyleId: Int
    public let perks: [Int]

    public init(styleId: Int, subStyleId: Int, perks: [Int]) {
        self.styleId = styleId
        self.subStyleId = subStyleId
        self.perks = perks
    }

    /// Rune principale (clé de voûte).
    public var keystone: Int? { perks.first }
}

/// Un joueur dans une frame de `details`.
public struct ParticipantDetails: Codable, Sendable, Equatable {
    public let participantId: Int
    public let level: Int
    public let kills: Int
    public let deaths: Int
    public let assists: Int
    public let creepScore: Int
    public let totalGoldEarned: Int
    /// Participation aux kills de l'équipe, de 0 à 1.
    public let killParticipation: Double?
    /// Part des dégâts aux champions de l'équipe, de 0 à 1.
    public let championDamageShare: Double?
    public let wardsPlaced: Int?
    public let wardsDestroyed: Int?
    /// Ids d'objets dans l'ordre du flux, balise comprise (`ItemCatalog.inventory` la met à part).
    public let items: [Int]
    public let perkMetadata: PerkMetadata?
    /// Ordre de montée des sorts : « Q », « W », « E », « R ».
    public let abilities: [String]

    public init(participantId: Int, level: Int, kills: Int, deaths: Int, assists: Int, creepScore: Int,
                totalGoldEarned: Int, killParticipation: Double?, championDamageShare: Double?, wardsPlaced: Int?,
                wardsDestroyed: Int?, items: [Int], perkMetadata: PerkMetadata?, abilities: [String]) {
        self.participantId = participantId
        self.level = level
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.totalGoldEarned = totalGoldEarned
        self.killParticipation = killParticipation
        self.championDamageShare = championDamageShare
        self.wardsPlaced = wardsPlaced
        self.wardsDestroyed = wardsDestroyed
        self.items = items
        self.perkMetadata = perkMetadata
        self.abilities = abilities
    }

    private enum CodingKeys: String, CodingKey {
        case participantId, level, kills, deaths, assists, creepScore, totalGoldEarned, killParticipation
        case championDamageShare, wardsPlaced, wardsDestroyed, items, perkMetadata, abilities
    }

    /// Décodage tolérant : seul `participantId` est indispensable ; un champ absent ou illisible prend une valeur neutre.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        participantId = try container.decode(Int.self, forKey: .participantId)
        level = (try? container.decodeIfPresent(Int.self, forKey: .level)) ?? 0
        kills = (try? container.decodeIfPresent(Int.self, forKey: .kills)) ?? 0
        deaths = (try? container.decodeIfPresent(Int.self, forKey: .deaths)) ?? 0
        assists = (try? container.decodeIfPresent(Int.self, forKey: .assists)) ?? 0
        creepScore = (try? container.decodeIfPresent(Int.self, forKey: .creepScore)) ?? 0
        totalGoldEarned = (try? container.decodeIfPresent(Int.self, forKey: .totalGoldEarned)) ?? 0
        killParticipation = try? container.decodeIfPresent(Double.self, forKey: .killParticipation)
        championDamageShare = try? container.decodeIfPresent(Double.self, forKey: .championDamageShare)
        wardsPlaced = try? container.decodeIfPresent(Int.self, forKey: .wardsPlaced)
        wardsDestroyed = try? container.decodeIfPresent(Int.self, forKey: .wardsDestroyed)
        items = (try? container.decodeIfPresent([Int].self, forKey: .items)) ?? []
        perkMetadata = try? container.decodeIfPresent(PerkMetadata.self, forKey: .perkMetadata)
        abilities = (try? container.decodeIfPresent([String].self, forKey: .abilities)) ?? []
    }
}
```

- [ ] **Step 6: Écrire `details`**

Créer `LoLKit/Sources/LoLKit/API/LoLClient+Details.swift` :

```swift
import Foundation

extension LoLClient {
    /// `details` est lourd (~200 Ko par lecture) : au plus une lecture par minute, et seulement Détail ouvert sur une game
    /// en cours (une seule pour une game terminée).
    public static let detailsInterval: TimeInterval = 60

    /// Détails par joueur d'une game (`livestats/v1/details/{gameId}`) à partir de `startingTime` ; sans `startingTime`,
    /// le début de la game. Mêmes erreurs que `window` (404 : stats désactivées ; vide : pas encore de données).
    public func details(gameId: String, startingTime: Date?) async throws -> GameDetails {
        try await feed("details", gameId: gameId, startingTime: startingTime, as: GameDetails.self)
    }

    /// Derniers détails d'une game, avec le même recul que `liveWindow` (fin de fenêtre ≥ 80 s, paliers de
    /// `LiveStatsTime.delays`, délai retenu par game et partagé avec `window`). Pour une game terminée, le flux renvoie
    /// les dernières frames (vérifié le 14/10/2026 : une heure demandée après la fin donne la frame `finished`) : un seul
    /// appel suffit.
    public func details(gameId: String, now: Date) async throws -> GameDetails {
        try await steppingBack(gameId: gameId, now: now) { startingTime in
            try await details(gameId: gameId, startingTime: startingTime)
        }
    }
}
```

- [ ] **Step 7: Lancer les tests pour les voir passer**

Run : `bash scripts/lolkit.sh test --filter "GameDetailsTests|LoLClientTests"`
Expected : PASS — `Test run with 16 tests in 2 suites passed`.

- [ ] **Step 8: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 263 tests in 30 suites passed`, aucun `warning:`.

- [ ] **Step 9: Commit**

```bash
git add LoLKit/Sources/LoLKit/API/LoLClient.swift LoLKit/Sources/LoLKit/API/LoLClient+Details.swift LoLKit/Sources/LoLKit/Models/GameDetails.swift LoLKit/Tests/LoLKitTests/GameDetailsTests.swift LoLKit/Tests/LoLKitTests/Fixtures/details_ingame.json
git commit -m "feat(lolkit): flux details (objets, runes, ordre des sorts, part des dégâts) avec le recul de 80 s partagé avec window" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10: Pousser la branche et vérifier la CI**

```bash
git push -u origin fonc/lolkit-t4-details
gh run list --workflow LoLKit --branch fonc/lolkit-t4-details --limit 1
gh run watch --exit-status <id de la ligne affichée>
```
Expected : jobs `test` et `test-macos` verts.

---

### Task 5: Sorts d'invocateur des games terminées (Leaguepedia)

**Branche :** `fonc/lolkit-t5-leaguepedia`

**Files:**
- Create: `LoLKit/Sources/LoLKit/Leaguepedia/ChampionKey.swift`
- Create: `LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift`
- Create: `LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift`
- Test: `LoLKit/Tests/LoLKitTests/LeaguepediaTests.swift`
- Fixtures (créées) : `leaguepedia_scoreboard.json` (vraie réponse Cargo pour `around` = début de la game 1 de la finale LCS, réduite à trois games), `leaguepedia_ratelimited.json` (vraie réponse « ratelimited » du 14/10/2026).

**Interfaces:**
- Consumes (à `HEAD`) : `HTTPTransport.get(_:headers:)`, `URLSessionTransport()`, `LoLDate.format(_:)`, `LoLDate.parse(_:)` ; tests : `FakeTransport`, `queryValue(_:_:)`, `date(_:)`, `Fixture.data(_:)`, `JSONDecoder.lolesports()`, `LiveWindow.gameMetadata.{blue,red}TeamMetadata.participantMetadata[].championId`, fixture `window_ingame.json`.
- Produces :
  - `public enum LeaguepediaError: Error, Equatable, Sendable { case http(status: Int), rateLimited, api(code: String) }`.
  - `public struct LeaguepediaClient: Sendable` : `userAgent = "Faille (usage personnel)"`, `init(transport: any HTTPTransport = URLSessionTransport())`, `summonerSpells(champions: [String], around start: Date) async throws -> [String: [String]]?` (ids Data Dragon des sorts par id de champion ; nil si la game n'est pas sur le wiki), `scoreboard(around start: Date) async throws -> [ScoreboardRow]`.
  - `public struct ScoreboardRow: Sendable, Equatable { gameId: String; link: String?; champion: String; summonerSpells: [String]; dateTime: Date? }` ; `init(gameId:link:champion:summonerSpells:dateTime:)`.
  - `public enum SpellMatcher` : `window: TimeInterval = 10_800`, `dataDragonSpellId(_ name: String) -> String?`, `match(champions: [String], around: Date, rows: [ScoreboardRow]) -> [String: [String]]?`.
  - `public enum ChampionKey` : `normalized(_ name: String) -> String`.

- [ ] **Step 1: Capturer et réduire les fixtures**

```bash
RAW="$(mktemp -d)"; command -v cygpath >/dev/null && RAW="$(cygpath -m "$RAW")"
curl -s -A "Faille (usage personnel)" -o "$RAW/scoreboard.json" "https://lol.fandom.com/api.php?action=cargoquery&format=json&tables=ScoreboardPlayers&fields=GameId,Link,Champion,SummonerSpells,DateTime_UTC&where=DateTime_UTC%20%3E%3D%20'2026-10-04%2017:18:26'%20AND%20DateTime_UTC%20%3C%3D%20'2026-10-04%2023:18:26'&limit=500"
head -c 120 "$RAW/scoreboard.json"; echo
```

Cette URL est exactement celle que construit `LeaguepediaClient.scoreboardURL(around: 2026-10-04T20:18:26.892Z)`. Si la réponse commence par `{"error":{"code":"ratelimited"` (limite anonyme du wiki, constatée le 14/10/2026 : environ une requête Cargo acceptée toutes les 10 min), attendre 10 minutes et relancer **la seule** commande `curl` (jamais en boucle serrée). La bonne réponse commence par `{"cargoquery":[{"title":{"GameId":"EMEA Masters/2026 Season/Summer Main Event_Knockout Matches_1_3"` et compte 130 lignes. Puis :

```bash
python -I - "$RAW/scoreboard.json" LoLKit/Tests/LoLKitTests/Fixtures/leaguepedia_scoreboard.json <<'EOF'
# Garde, d'une réponse Cargo ScoreboardPlayers, les lignes de trois games : la game 1 de la finale LCS (celle des
# fixtures window_*), la game 2 (mêmes équipes, autres champions) et une game d'EMEA Masters du même créneau.
import json, sys
src, dst = sys.argv[1], sys.argv[2]
games = [
    "LCS/2026 Season/Summer Playoffs_Finals_1_1",
    "LCS/2026 Season/Summer Playoffs_Finals_1_2",
    "EMEA Masters/2026 Season/Summer Main Event_Knockout Matches_1_3",
]
with open(src, encoding="utf-8") as f:
    rows = json.load(f)["cargoquery"]
kept = []
for row in rows:
    if row["title"]["GameId"] in games:
        row["title"].pop("Team", None)
        kept.append(row)
# Ordre stable, quel que soit l'ordre rendu par le wiki : game, puis joueur.
kept.sort(key=lambda row: (row["title"]["GameId"], row["title"]["Link"]))
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    json.dump({"cargoquery": kept}, f, ensure_ascii=False, indent=1)
    f.write("\n")
EOF
rm -rf "$RAW"
cat > LoLKit/Tests/LoLKitTests/Fixtures/leaguepedia_ratelimited.json <<'EOF'
{"error":{"code":"ratelimited","info":"You've exceeded your rate limit. Please wait some time and try again.","*":"See https://lol.fandom.com/api.php for API usage. Subscribe to the mediawiki-api-announce mailing list at &lt;https://lists.wikimedia.org/postorius/lists/mediawiki-api-announce.lists.wikimedia.org/&gt; for notice of API deprecations and breaking changes."}}
EOF
(cd LoLKit/Tests/LoLKitTests/Fixtures && sha256sum leaguepedia_*.json)
```

Expected :

```
c7724a3e6646c61a9df81ae1058460748bbeef7f184a98e265900ae09a7c81e7 *leaguepedia_ratelimited.json
22bd235b46b56d1a64fcf67a4b9eeb74ccd9fa192ac9cd1c2d62649800c73ead *leaguepedia_scoreboard.json
```

(`leaguepedia_scoreboard.json` : 30 lignes, 7 929 octets. La game 1 de la finale LCS y figure avec `DateTime UTC` = « 2026-10-04 20:18:00 » et les champions « Ambessa », « Lee Sin », « Orianna », « Kalista », « Renata Glasc », « K'Sante », « Trundle », « Syndra », « Yunara », « Lulu ». Si le wiki a corrigé une ligne depuis le 14/10/2026 et que l'empreinte diffère, s'arrêter et le signaler.)

- [ ] **Step 2: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/LeaguepediaTests.swift` :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli interroge Leaguepedia et rapproche les games avec la seule API publique.
import LoLKit

/// Sorts d'invocateur des games terminées (spec fonctionnalités §3). Fixture : vraie réponse Cargo du 14/10/2026 pour
/// `around` = début de la game 1 de la finale LCS (TLAW – LYON, 04/10/2026 20:18:26 UTC), réduite à trois games.
@Suite struct LeaguepediaTests {
    /// Début de la game 1 de la finale LCS : première frame de `window_pregame`.
    private static let lcsStart = date("2026-10-04T20:18:26.892Z")
    private static let lcsGame = "LCS/2026 Season/Summer Playoffs_Finals_1_1"

    /// Les 10 champions de la game, tels que le flux les donne (`window_ingame`, ids Data Dragon).
    private func lcsChampions() throws -> [String] {
        let window = try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data("window_ingame"))
        let metadata = window.gameMetadata.blueTeamMetadata.participantMetadata
            + window.gameMetadata.redTeamMetadata.participantMetadata
        return metadata.compactMap(\.championId)
    }

    private func rows() async throws -> [ScoreboardRow] {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_scoreboard")
        return try await LeaguepediaClient(transport: fake).scoreboard(around: Self.lcsStart)
    }

    @Test func queriesTheScoreboardAroundTheGameStart() async throws {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_scoreboard")
        let rows = try await LeaguepediaClient(transport: fake).scoreboard(around: Self.lcsStart)

        let request = try #require(await fake.requests.first)
        #expect(request.url.host == "lol.fandom.com")
        #expect(request.url.path == "/api.php")
        #expect(queryValue(request.url, "action") == "cargoquery")
        #expect(queryValue(request.url, "format") == "json")
        #expect(queryValue(request.url, "tables") == "ScoreboardPlayers")
        #expect(queryValue(request.url, "fields") == "GameId,Link,Champion,SummonerSpells,DateTime_UTC")
        #expect(queryValue(request.url, "where")
                == "DateTime_UTC >= '2026-10-04 17:18:26' AND DateTime_UTC <= '2026-10-04 23:18:26'")
        #expect(queryValue(request.url, "limit") == "500")
        #expect(request.headers["User-Agent"] == "Faille (usage personnel)")
        #expect(request.headers["x-api-key"] == nil)

        #expect(rows.count == 30)
        #expect(rows.first == ScoreboardRow(gameId: "EMEA Masters/2026 Season/Summer Main Event_Knockout Matches_1_3",
                                            link: "Carlsen", champion: "Jayce", summonerSpells: ["Ignite", "Flash"],
                                            dateTime: date("2026-10-04T17:23:00Z")))
        #expect(rows.filter { $0.gameId == Self.lcsGame }.count == 10)
    }

    @Test func summonerSpellsOfTheLCSFinalGameOne() async throws {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_scoreboard")
        let spells = try await LeaguepediaClient(transport: fake)
            .summonerSpells(champions: try lcsChampions(), around: Self.lcsStart)
        // « Renata Glasc », « K'Sante », « Lee Sin » du wiki retrouvent « Renata », « KSante », « LeeSin » du flux.
        #expect(spells == [
            "Ambessa": ["SummonerTeleport", "SummonerFlash"],
            "LeeSin": ["SummonerFlash", "SummonerSmite"],
            "Orianna": ["SummonerTeleport", "SummonerFlash"],
            "Kalista": ["SummonerFlash", "SummonerBarrier"],
            "Renata": ["SummonerFlash", "SummonerHeal"],
            "KSante": ["SummonerFlash", "SummonerTeleport"],
            "Trundle": ["SummonerSmite", "SummonerFlash"],
            "Syndra": ["SummonerTeleport", "SummonerFlash"],
            "Yunara": ["SummonerExhaust", "SummonerFlash"],
            "Lulu": ["SummonerHeal", "SummonerFlash"],
        ])
    }

    @Test func otherGameOfTheSameSlot() async throws {
        // EMEA Masters, même créneau : « Dr. Mundo », « Jarvan IV » et « Ignite » (SummonerDot).
        let champions = ["Jayce", "DrMundo", "Thresh", "Karthus", "Orianna", "JarvanIV", "Locke", "LeeSin", "Jinx", "Camille"]
        let spells = SpellMatcher.match(champions: champions, around: date("2026-10-04T17:23:30Z"), rows: try await rows())
        #expect(spells?["Jayce"] == ["SummonerDot", "SummonerFlash"])
        #expect(spells?["DrMundo"] == ["SummonerFlash", "SummonerTeleport"])
        #expect(spells?["JarvanIV"] == ["SummonerSmite", "SummonerFlash"])
        #expect(spells?.count == 10)
    }

    @Test func noMatchOutsideThreeHoursOrWithOtherChampions() async throws {
        let rows = try await rows()
        let champions = try lcsChampions()
        // `DateTime UTC` de la game : 20:18:00 ; ± 3 h comprises.
        #expect(SpellMatcher.match(champions: champions, around: date("2026-10-04T23:18:00Z"), rows: rows) != nil)
        #expect(SpellMatcher.match(champions: champions, around: date("2026-10-04T23:18:01Z"), rows: rows) == nil)
        #expect(SpellMatcher.match(champions: champions, around: date("2026-10-04T17:18:00Z"), rows: rows) != nil)
        // Un champion différent (Ezreal au lieu de Kalista) : pas la même game.
        let other = champions.map { $0 == "Kalista" ? "Ezreal" : $0 }
        #expect(SpellMatcher.match(champions: other, around: Self.lcsStart, rows: rows) == nil)
        // Neuf champions seulement, ou un doublon : rien.
        #expect(SpellMatcher.match(champions: Array(champions.dropLast()), around: Self.lcsStart, rows: rows) == nil)
        #expect(SpellMatcher.match(champions: champions + ["Lulu"], around: Self.lcsStart, rows: rows) == nil)
        #expect(SpellMatcher.match(champions: champions, around: Self.lcsStart, rows: []) == nil)
    }

    @Test func closestGameWinsWhenTheSameDraftIsPlayedTwice() {
        let draft = ["A", "B"]
        let rows = ["early": "2026-10-04T18:00:00Z", "late": "2026-10-04T20:30:00Z"].flatMap { id, start in
            draft.map { ScoreboardRow(gameId: id, link: nil, champion: $0, summonerSpells: [id == "late" ? "Heal" : "Ghost"],
                                      dateTime: date(start)) }
        }
        #expect(SpellMatcher.match(champions: draft, around: date("2026-10-04T20:00:00Z"), rows: rows)
                == ["A": ["SummonerHeal"], "B": ["SummonerHeal"]])
    }

    @Test func rateLimitAndHTTPErrors() async throws {
        let fake = FakeTransport()
        try await fake.on("lol.fandom.com", fixture: "leaguepedia_ratelimited")
        await #expect(throws: LeaguepediaError.rateLimited) {
            try await LeaguepediaClient(transport: fake).summonerSpells(champions: ["Lulu"], around: Self.lcsStart)
        }
        let down = FakeTransport()
        try await down.on("lol.fandom.com", status: 503, body: "Service Unavailable")
        await #expect(throws: LeaguepediaError.http(status: 503)) {
            try await LeaguepediaClient(transport: down).scoreboard(around: Self.lcsStart)
        }
        let other = FakeTransport()
        try await other.on("lol.fandom.com", body: #"{"error":{"code":"badquery","info":"..."}}"#)
        await #expect(throws: LeaguepediaError.api(code: "badquery")) {
            try await LeaguepediaClient(transport: other).scoreboard(around: Self.lcsStart)
        }
    }

    @Test func championNamesAreComparedLikeDataDragonIds() {
        #expect(ChampionKey.normalized("LeBlanc") == ChampionKey.normalized("Leblanc"))
        #expect(ChampionKey.normalized("Wukong") == ChampionKey.normalized("MonkeyKing"))
        #expect(ChampionKey.normalized("K'Sante") == ChampionKey.normalized("KSante"))
        #expect(ChampionKey.normalized("Renata Glasc") == ChampionKey.normalized("Renata"))
        #expect(ChampionKey.normalized("Nunu & Willump") == ChampionKey.normalized("Nunu"))
        #expect(ChampionKey.normalized("Dr. Mundo") == "drmundo")
        #expect(ChampionKey.normalized("Kai'Sa") == "kaisa")
        #expect(ChampionKey.normalized("Jarvan IV") == "jarvaniv")
        #expect(ChampionKey.normalized("Lee Sin") != ChampionKey.normalized("Lee"))
    }

    @Test func summonerSpellNamesBecomeDataDragonIds() {
        #expect(SpellMatcher.dataDragonSpellId("Flash") == "SummonerFlash")
        #expect(SpellMatcher.dataDragonSpellId("Ignite") == "SummonerDot")
        #expect(SpellMatcher.dataDragonSpellId("Cleanse") == "SummonerBoost")
        #expect(SpellMatcher.dataDragonSpellId("Ghost") == "SummonerHaste")
        #expect(SpellMatcher.dataDragonSpellId(" Teleport") == "SummonerTeleport")
        #expect(SpellMatcher.dataDragonSpellId("Mark") == nil)
    }
}
```

- [ ] **Step 3: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter LeaguepediaTests`
Expected : FAIL à la compilation (`cannot find 'LeaguepediaClient' in scope`, `cannot find 'ScoreboardRow' in scope`, `cannot find 'SpellMatcher' in scope`, `cannot find 'ChampionKey' in scope`).

- [ ] **Step 4: Écrire la normalisation des noms**

Créer `LoLKit/Sources/LoLKit/Leaguepedia/ChampionKey.swift` :

```swift
/// Clé de comparaison d'un nom de champion, commune aux noms de Leaguepedia (« Lee Sin », « K'Sante », « Renata Glasc »,
/// « Wukong ») et aux ids Data Dragon du flux (« LeeSin », « KSante », « Renata », « MonkeyKing »).
public enum ChampionKey {
    /// Les trois champions dont l'id Data Dragon n'est pas le nom (vérifié sur `champion.json` 16.17.1 et 16.20.1).
    static let aliases = ["wukong": "monkeyking", "renataglasc": "renata", "nunuwillump": "nunu"]

    /// Minuscules, lettres et chiffres ASCII seulement (sans espace, apostrophe, point ni « & »), puis alias :
    /// « LeBlanc » et « Leblanc » → « leblanc » ; « Wukong » → « monkeyking » ; « Dr. Mundo » → « drmundo ».
    public static func normalized(_ name: String) -> String {
        let compact = String(name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
        return aliases[compact] ?? compact
    }
}
```

- [ ] **Step 5: Écrire le rapprochement**

Créer `LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift` :

```swift
import Foundation

/// Une ligne de `ScoreboardPlayers` (Leaguepedia) : un joueur d'une game terminée.
public struct ScoreboardRow: Sendable, Equatable {
    /// Identifiant de la game chez Leaguepedia (ex. « LCS/2026 Season/Summer Playoffs_Finals_1_1 »).
    public let gameId: String
    /// Page du joueur (ex. « Josedeodo »).
    public let link: String?
    /// Nom Leaguepedia du champion (ex. « Lee Sin »).
    public let champion: String
    /// Noms anglais des sorts d'invocateur, dans l'ordre du wiki (ex. « Flash », « Smite »).
    public let summonerSpells: [String]
    /// Début de la game (`DateTime_UTC`, à la minute).
    public let dateTime: Date?

    public init(gameId: String, link: String?, champion: String, summonerSpells: [String], dateTime: Date?) {
        self.gameId = gameId
        self.link = link
        self.champion = champion
        self.summonerSpells = summonerSpells
        self.dateTime = dateTime
    }
}

/// Retrouve une game du flux dans Leaguepedia (spec fonctionnalités §3) : même ensemble de 10 champions, début à ± 3 h.
public enum SpellMatcher {
    /// Écart maximal entre le début de la game (flux) et `DateTime_UTC` (wiki).
    public static let window: TimeInterval = 3 * 3600

    /// Noms Leaguepedia → ids Data Dragon des sorts d'invocateur de la Faille.
    static let spellIds = [
        "Barrier": "SummonerBarrier", "Cleanse": "SummonerBoost", "Exhaust": "SummonerExhaust",
        "Flash": "SummonerFlash", "Ghost": "SummonerHaste", "Heal": "SummonerHeal", "Ignite": "SummonerDot",
        "Smite": "SummonerSmite", "Teleport": "SummonerTeleport", "Clarity": "SummonerMana",
    ]

    /// Id Data Dragon d'un sort nommé par Leaguepedia (« Ignite » → « SummonerDot ») ; nil si inconnu (pas d'image inventée).
    public static func dataDragonSpellId(_ name: String) -> String? {
        spellIds[name.trimmingCharacters(in: .whitespaces)]
    }

    /// Sorts d'invocateur de la game dont les champions sont exactement `champions` (comparés par `ChampionKey`) et dont le
    /// début est à `window` au plus de `around` ; la plus proche dans le temps s'il y en a plusieurs. nil si aucune (le
    /// wiki n'a pas encore la game) ou si `champions` contient un doublon.
    /// - Parameters:
    ///   - champions: ids Data Dragon du flux (`participantMetadata[].championId`), les 10 de la game.
    ///   - around: début de la game (`LiveWindow.firstFrameTime` de la fenêtre lue sans `startingTime`).
    /// - Returns: ids Data Dragon des sorts (« SummonerFlash ») par id de champion tel que donné dans `champions`.
    public static func match(champions: [String], around: Date, rows: [ScoreboardRow]) -> [String: [String]]? {
        var wanted: [String: String] = [:]
        for champion in champions { wanted[ChampionKey.normalized(champion)] = champion }
        guard !wanted.isEmpty, wanted.count == champions.count else { return nil }

        let candidates = Dictionary(grouping: rows, by: \.gameId).compactMap { gameId, players
            -> (gameId: String, distance: TimeInterval, players: [ScoreboardRow])? in
            guard let start = players.compactMap(\.dateTime).first else { return nil }
            let distance = abs(start.timeIntervalSince(around))
            let keys = players.map { ChampionKey.normalized($0.champion) }
            guard distance <= window, keys.count == wanted.count, Set(keys) == Set(wanted.keys) else { return nil }
            return (gameId, distance, players)
        }
        guard let best = candidates.min(by: { ($0.distance, $0.gameId) < ($1.distance, $1.gameId) }) else { return nil }

        var spells: [String: [String]] = [:]
        for player in best.players {
            guard let champion = wanted[ChampionKey.normalized(player.champion)] else { continue }
            spells[champion] = player.summonerSpells.compactMap(dataDragonSpellId)
        }
        return spells
    }
}
```

- [ ] **Step 6: Écrire le client**

Créer `LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift` :

```swift
import Foundation

public enum LeaguepediaError: Error, Equatable, Sendable {
    /// Réponse HTTP inattendue.
    case http(status: Int)
    /// Le wiki limite les requêtes anonymes (vu le 14/10/2026 : réponse 200 avec `error.code == "ratelimited"`, levée au
    /// bout de quelques minutes). Réessayer plus tard, jamais en boucle.
    case rateLimited
    /// Autre erreur de l'API MediaWiki (`error.code`).
    case api(code: String)
}

/// Client de Leaguepedia (`lol.fandom.com`, API Cargo, sans clé) pour les sorts d'invocateur des games terminées, absents
/// du flux de Riot (spec fonctionnalités §3). Une requête par game au plus : l'appli met la réponse en cache disque.
public struct LeaguepediaClient: Sendable {
    /// User-Agent identifiable demandé par le wiki.
    public static let userAgent = "Faille (usage personnel)"
    static let endpoint = "https://lol.fandom.com/api.php"

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Sorts d'invocateur d'une game terminée, par champion : `champions` = ids Data Dragon du flux (les 10 de la game),
    /// `start` = début de la game. Réponse : ids Data Dragon des sorts (« SummonerFlash ») par id de champion ; nil si le
    /// wiki n'a pas (encore) la game.
    public func summonerSpells(champions: [String], around start: Date) async throws -> [String: [String]]? {
        SpellMatcher.match(champions: champions, around: start, rows: try await scoreboard(around: start))
    }

    /// Lignes `ScoreboardPlayers` des games commencées à ± 3 h de `start` (une seule requête, 500 lignes au plus).
    public func scoreboard(around start: Date) async throws -> [ScoreboardRow] {
        let response = try await transport.get(Self.scoreboardURL(around: start), headers: ["User-Agent": Self.userAgent])
        guard response.status == 200 else { throw LeaguepediaError.http(status: response.status) }
        let body = try JSONDecoder().decode(CargoResponse.self, from: response.body)
        if let error = body.error {
            throw error.code == "ratelimited" ? LeaguepediaError.rateLimited : LeaguepediaError.api(code: error.code)
        }
        return (body.cargoquery ?? []).compactMap { $0.value?.title.row }
    }

    /// Requête Cargo : `ScoreboardPlayers`, champs `GameId,Link,Champion,SummonerSpells,DateTime_UTC`, games commencées
    /// entre `start - 3 h` et `start + 3 h` (heure UTC à la seconde).
    static func scoreboardURL(around start: Date) -> URL {
        let from = cargoDate(start.addingTimeInterval(-SpellMatcher.window))
        let to = cargoDate(start.addingTimeInterval(SpellMatcher.window))
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "cargoquery"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "tables", value: "ScoreboardPlayers"),
            URLQueryItem(name: "fields", value: "GameId,Link,Champion,SummonerSpells,DateTime_UTC"),
            URLQueryItem(name: "where", value: "DateTime_UTC >= '\(from)' AND DateTime_UTC <= '\(to)'"),
            URLQueryItem(name: "limit", value: "500"),
        ]
        return components.url!
    }

    /// « 2026-10-04 17:18:26 » (UTC), le format des dates Cargo.
    static func cargoDate(_ date: Date) -> String {
        let iso = LoLDate.format(date) // 2026-10-04T17:18:26.892Z
        return String(iso.prefix(19)).replacingOccurrences(of: "T", with: " ")
    }

    /// « 2026-10-04 20:18:00 » (UTC) → date ; nil si illisible.
    static func parseCargoDate(_ string: String) -> Date? {
        LoLDate.parse(string.replacingOccurrences(of: " ", with: "T") + "Z")
    }
}

/// Réponse de `action=cargoquery` : des lignes `{"title": {...}}`, ou une erreur MediaWiki.
private struct CargoResponse: Decodable {
    struct Entry: Decodable {
        let title: Title
    }

    struct Title: Decodable {
        let gameId: String?
        let link: String?
        let champion: String?
        let summonerSpells: String?
        let dateTime: String?

        enum CodingKeys: String, CodingKey {
            case gameId = "GameId", link = "Link", champion = "Champion", summonerSpells = "SummonerSpells"
            case dateTime = "DateTime UTC"
        }

        /// Ligne utilisable : game et champion connus.
        var row: ScoreboardRow? {
            guard let gameId, !gameId.isEmpty, let champion, !champion.isEmpty else { return nil }
            let spells = (summonerSpells ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return ScoreboardRow(gameId: gameId, link: link, champion: champion, summonerSpells: spells,
                                 dateTime: dateTime.flatMap(LeaguepediaClient.parseCargoDate))
        }
    }

    struct APIError: Decodable {
        let code: String
    }

    let cargoquery: [Lenient<Entry>]?
    let error: APIError?
}

/// Ligne décodée si possible, sinon nil : une ligne illisible n'empêche pas de lire les autres.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
```

- [ ] **Step 7: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter LeaguepediaTests`
Expected : PASS — `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 8: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 266 tests in 30 suites passed`, aucun `warning:`.

- [ ] **Step 9: Commit**

```bash
git add LoLKit/Sources/LoLKit/Leaguepedia/ChampionKey.swift LoLKit/Sources/LoLKit/Leaguepedia/SpellMatcher.swift LoLKit/Sources/LoLKit/Leaguepedia/LeaguepediaClient.swift LoLKit/Tests/LoLKitTests/LeaguepediaTests.swift LoLKit/Tests/LoLKitTests/Fixtures/leaguepedia_scoreboard.json LoLKit/Tests/LoLKitTests/Fixtures/leaguepedia_ratelimited.json
git commit -m "feat(lolkit): sorts d'invocateur des games terminées via Leaguepedia (Cargo, ± 3 h, mêmes champions, noms normalisés)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10: Pousser la branche et vérifier la CI**

```bash
git push -u origin fonc/lolkit-t5-leaguepedia
gh run list --workflow LoLKit --branch fonc/lolkit-t5-leaguepedia --limit 1
gh run watch --exit-status <id de la ligne affichée>
```
Expected : jobs `test` et `test-macos` verts (aucun test ne touche le réseau : tout passe par `FakeTransport`).

---

### Task 6: Fil des événements et courbe de l'écart de gold

**Branche :** `fonc/lolkit-t6-fil-gold`

**Files:**
- Create: `LoLKit/Sources/LoLKit/Timeline/LiveWindow+Snapshots.swift`
- Create: `LoLKit/Sources/LoLKit/Timeline/GameTimeline.swift`
- Create: `LoLKit/Sources/LoLKit/Timeline/GoldSeries.swift`
- Test: `LoLKit/Tests/LoLKitTests/GameTimelineTests.swift`
- Fixture (créée) : `window_replay.json` — vraie relecture à pas de 60 s de la game 1 de la finale LCS (TLAW bleu – LYON rouge, game `115565004607949430`) : la dernière frame de chacune des 36 fenêtres `startingTime` = 20:19:00, 20:20:00 … 20:54:00 (04/10/2026), sous la forme d'une fenêtre livestats.

**Interfaces:**
- Consumes (à `HEAD`) : `GameSnapshot` (init public, `timestamp`, `blueTeamId`, `redTeamId`, `blue`, `red`, `bluePlayers`, `redPlayers`), `TeamStats` (`kills`, `gold`, `towers`, `inhibitors`, `barons`, `dragons`) et son init interne `TeamStats(_ team: FrameTeam)`, `PlayerLine` (`name`, `kills`) et `PlayerLine.lines(_:metadata:)` (interne), `GamePhase(apiValue:)` (interne), `LiveWindow` (`esportsGameId`, `gameMetadata`, `frames`, `latestSnapshot()`, `firstFrameTime`) ; tests : `Format.clock(_:)`, `Fixture.data(_:)`, `date(_:)`, fixture `window_pregame.json` (première frame 2026-10-04T20:18:26.892Z).
- Produces :
  - `LiveWindow.snapshots() -> [GameSnapshot]` (une par frame ; la dernière égale `latestSnapshot()`).
  - `public struct TimelineEvent: Sendable, Equatable { gameTime: TimeInterval; teamId: String; kind: Kind; count: Int; players: [String] }` avec `enum Kind { kills, dragon(String), baron, tower, inhibitor }` ; `init(gameTime:teamId:kind:count:players: [String] = [])`.
  - `public enum GameTimeline` : `events(from snapshots: [GameSnapshot], firstFrameTime: Date) -> [TimelineEvent]`.
  - `public struct GoldPoint: Sendable, Equatable { gameTime: TimeInterval; difference: Int }` ; `public enum GoldSeries` : `points(from snapshots: [GameSnapshot], firstFrameTime: Date, orientedTo teamId: String?) -> [GoldPoint]`.

- [ ] **Step 1: Capturer la relecture**

```bash
RAW="$(mktemp -d)"; command -v cygpath >/dev/null && RAW="$(cygpath -m "$RAW")"
for m in $(seq -w 19 54); do
  curl -sf -o "$RAW/w_$m.json" "https://feed.lolesports.com/livestats/v1/window/115565004607949430?startingTime=2026-10-04T20:$m:00.000Z" || echo "ECHEC $m"
done
python -I - "$RAW"/w_*.json LoLKit/Tests/LoLKitTests/Fixtures/window_replay.json <<'EOF'
# Assemble une relecture à pas de 60 s : la dernière frame de chaque fenêtre, dans l'ordre, sous la forme d'une fenêtre
# livestats (gameMetadata de la première réponse).
import json, sys
paths, dst = sys.argv[1:-1], sys.argv[-1]
windows = []
for path in paths:
    with open(path, encoding="utf-8") as f:
        windows.append(json.load(f))
first = windows[0]
replay = {
    "esportsGameId": first["esportsGameId"],
    "esportsMatchId": first["esportsMatchId"],
    "gameMetadata": first["gameMetadata"],
    "frames": [w["frames"][-1] for w in windows],
}
with open(dst, "w", encoding="utf-8", newline="\n") as f:
    json.dump(replay, f, ensure_ascii=False)
    f.write("\n")
EOF
rm -rf "$RAW"
sha256sum LoLKit/Tests/LoLKitTests/Fixtures/window_replay.json
```

Expected : aucune ligne `ECHEC`, puis `b01fb148d74f628d4991e671938b9681f1efdce46586b01bcd333cf46eaf8269` (69 282 octets, 36 frames, de `2026-10-04T20:19:09.466Z` à la frame `finished` `2026-10-04T20:53:40.101Z` ; le flux sert les games passées à l'identique, vérifié le 14/10/2026 par une deuxième capture).

- [ ] **Step 2: Écrire le test qui échoue**

Créer `LoLKit/Tests/LoLKitTests/GameTimelineTests.swift` (suite `GameTimelineTests` : le filtre `TimelineTests` attraperait aussi `WidgetTimelineTests`) :

```swift
import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli construit le fil et la courbe avec la seule API publique.
import LoLKit

/// Fil des événements (spec fonctionnalités §4) et courbe de l'écart de gold (§5). Fixture `window_replay` : vraie
/// relecture à pas de 60 s de la game 1 de la finale LCS (TLAW bleu – LYON rouge, 04/10/2026), une frame par pas
/// (dernière frame de chaque fenêtre `startingTime` = 20:19:00, 20:20:00 … 20:54:00), capturée le 14/10/2026.
@Suite struct GameTimelineTests {
    private static let tlaw = "98926509885559666"
    private static let lyon = "99566405941863385"

    private func window(_ name: String) throws -> LiveWindow {
        try JSONDecoder.lolesports().decode(LiveWindow.self, from: Fixture.data(name))
    }

    /// Début de la game : première frame de la fenêtre lue sans `startingTime` (20:18:26.892).
    private func gameStart() throws -> Date {
        try #require(try window("window_pregame").firstFrameTime)
    }

    private func line(_ event: TimelineEvent) -> String {
        let code = event.teamId == Self.tlaw ? "TLAW" : "LYON"
        let what: String
        switch event.kind {
        case .kills: what = "+\(event.count) kills" + (event.players.isEmpty ? "" : " (\(event.players.joined(separator: ", ")))")
        case let .dragon(type): what = "drake \(type)"
        case .baron: what = "+\(event.count) baron"
        case .tower: what = "+\(event.count) tours"
        case .inhibitor: what = "+\(event.count) inhib"
        }
        return "\(Format.clock(event.gameTime)) \(code) \(what)"
    }

    @Test func replaySnapshots() throws {
        let replay = try window("window_replay")
        let snapshots = replay.snapshots()
        #expect(snapshots.count == 36)
        #expect(snapshots.first?.timestamp == date("2026-10-04T20:19:09.466Z"))
        #expect(snapshots.last == replay.latestSnapshot())
        #expect(snapshots.last?.phase == .finished)
        #expect(snapshots.last?.blue == TeamStats(kills: 14, gold: 67995, towers: 8, inhibitors: 1, barons: 1,
                                                  dragons: ["chemtech", "ocean", "cloud", "cloud"]))
        #expect(snapshots[13].redPlayers.map(\.name) == ["LYON Dhokla", "LYON Inspired", "LYON Saint", "LYON Berserker",
                                                         "LYON Isles"])
    }

    @Test func timelineOfTheWholeGame() throws {
        let events = GameTimeline.events(from: try window("window_replay").snapshots(), firstFrameTime: try gameStart())
        #expect(events.map(line) == [
            "2:42 LYON +1 kills (LYON Saint)",
            "4:42 TLAW +1 kills (TLAW Josedeodo)",
            "6:42 TLAW +2 kills (TLAW Josedeodo, TLAW Yeon)",
            "6:42 TLAW drake chemtech",
            "9:42 TLAW +1 kills (TLAW Yeon)",
            "12:42 TLAW +1 kills (TLAW CoreJJ)",
            "12:42 TLAW drake ocean",
            "13:42 TLAW +2 kills (TLAW Josedeodo, TLAW CoreJJ)",
            "13:42 LYON +4 kills (LYON Inspired, LYON Saint, LYON Berserker)",
            "15:42 LYON +1 kills (LYON Inspired)",
            "17:42 TLAW +1 tours",
            "18:42 TLAW +2 tours",
            "18:42 LYON drake cloud",
            "22:42 TLAW +2 kills (TLAW Josedeodo, TLAW Quid)",
            "22:42 LYON +2 kills (LYON Dhokla, LYON Saint)",
            "23:43 LYON drake cloud",
            "23:43 LYON +1 tours",
            "24:43 LYON +1 kills (LYON Saint)",
            "27:42 TLAW +1 tours",
            "29:42 TLAW drake cloud",
            "30:43 LYON +1 kills (LYON Saint)",
            "30:43 LYON +2 tours",
            "32:42 TLAW +1 baron",
            "34:42 TLAW +5 kills (TLAW Morgan, TLAW Josedeodo, TLAW Quid, TLAW Yeon)",
            "34:42 TLAW drake cloud",
            "35:13 TLAW +4 tours",
            "35:13 TLAW +1 inhib",
        ])
    }

    @Test func firstFrameIsOnlyAReference() throws {
        // Ouverture tardive : la première frame lue (30:43) a déjà 9 kills bleus ; rien n'est inventé avant elle.
        let late = Array(try window("window_replay").snapshots()[30...])
        let events = GameTimeline.events(from: late, firstFrameTime: try gameStart())
        #expect(events.map(line) == [
            "32:42 TLAW +1 baron",
            "34:42 TLAW +5 kills (TLAW Morgan, TLAW Josedeodo, TLAW Quid, TLAW Yeon)",
            "34:42 TLAW drake cloud",
            "35:13 TLAW +4 tours",
            "35:13 TLAW +1 inhib",
        ])
        // L'ordre de remise n'importe pas ; une seule frame ne donne rien.
        #expect(GameTimeline.events(from: late.reversed(), firstFrameTime: try gameStart()) == events)
        #expect(GameTimeline.events(from: [late[0]], firstFrameTime: try gameStart()).isEmpty)
        #expect(GameTimeline.events(from: [], firstFrameTime: try gameStart()).isEmpty)
    }

    @Test func unattributableKillsHaveNoNames() {
        let start = date("2026-10-04T20:18:26Z")
        func player(_ name: String, kills: Int) -> PlayerLine {
            PlayerLine(role: "mid", champion: "Ahri", name: name, level: 6, kills: kills, deaths: 0, assists: 0,
                       creepScore: 50, gold: 3000)
        }
        func snap(_ at: String, kills: Int, towers: Int, players: [PlayerLine]) -> GameSnapshot {
            GameSnapshot(gameId: "g", phase: .inGame, timestamp: date(at), blueTeamId: "blue", redTeamId: "red",
                         blue: TeamStats(kills: kills, towers: towers), red: TeamStats(), bluePlayers: players,
                         redPlayers: [])
        }
        let before = snap("2026-10-04T20:28:26Z", kills: 3, towers: 3, players: [player("A", kills: 1), player("B", kills: 2)])
        // L'équipe gagne 2 kills mais un seul joueur en gagne 1 : « +2 kills » sans nom ; une tour en moins : rien.
        let after = snap("2026-10-04T20:28:36Z", kills: 5, towers: 2, players: [player("A", kills: 2), player("B", kills: 2)])
        let events = GameTimeline.events(from: [before, after], firstFrameTime: start)
        #expect(events == [TimelineEvent(gameTime: 610, teamId: "blue", kind: .kills, count: 2, players: [])])
    }

    @Test func goldCurveOfTheWholeGame() throws {
        let snapshots = try window("window_replay").snapshots()
        let points = GoldSeries.points(from: snapshots, firstFrameTime: try gameStart(), orientedTo: Self.tlaw)
        let expected: [(String, Int)] = [
            ("0:42", 0), ("1:42", 79), ("2:42", -619), ("3:43", -599), ("4:42", -90), ("5:42", -416), ("6:42", 744),
            ("7:42", 618), ("8:42", 799), ("9:42", 1705), ("10:42", 1437), ("11:42", 1750), ("12:42", 2852),
            ("13:42", 620), ("14:42", 862), ("15:42", 200), ("16:42", 200), ("17:42", 494), ("18:42", 1370),
            ("19:42", 1570), ("20:42", 1786), ("21:43", 1801), ("22:42", 1502), ("23:43", 1100), ("24:43", 484),
            ("25:42", 448), ("26:42", 790), ("27:42", 1242), ("28:42", 1162), ("29:42", 1437), ("30:43", 70),
            ("31:42", 329), ("32:42", 1122), ("33:42", 1810), ("34:42", 5674), ("35:13", 7663),
        ]
        #expect(points.map { Format.clock($0.gameTime) } == expected.map(\.0))
        #expect(points.map(\.difference) == expected.map(\.1))

        // Réorientée vers LYON (côté rouge) : l'écart change de signe ; sans équipe ou équipe inconnue : bleu − rouge.
        let lyon = GoldSeries.points(from: snapshots, firstFrameTime: try gameStart(), orientedTo: Self.lyon)
        #expect(lyon.map(\.difference) == expected.map { -$0.1 })
        #expect(GoldSeries.points(from: snapshots, firstFrameTime: try gameStart(), orientedTo: nil) == points)
        #expect(GoldSeries.points(from: snapshots.reversed(), firstFrameTime: try gameStart(), orientedTo: "autre") == points)
    }
}
```

- [ ] **Step 3: Lancer le test pour le voir échouer**

Run : `bash scripts/lolkit.sh test --filter GameTimelineTests`
Expected : FAIL à la compilation (`value of type 'LiveWindow' has no member 'snapshots'`, `cannot find 'GameTimeline' in scope`, `cannot find 'GoldSeries' in scope`, `cannot find type 'TimelineEvent' in scope`).

- [ ] **Step 4: Écrire `LiveWindow.snapshots()`**

Créer `LoLKit/Sources/LoLKit/Timeline/LiveWindow+Snapshots.swift` :

```swift
extension LiveWindow {
    /// Un `GameSnapshot` par frame, dans l'ordre du flux (le dernier est `latestSnapshot()`). Sert à rejouer une relecture
    /// mise en cache (une frame par pas de 60 s) dans `GameTimeline` et `GoldSeries`.
    public func snapshots() -> [GameSnapshot] {
        let blueMeta = gameMetadata.blueTeamMetadata
        let redMeta = gameMetadata.redTeamMetadata
        return frames.map { frame in
            GameSnapshot(
                gameId: esportsGameId,
                phase: GamePhase(apiValue: frame.gameState),
                timestamp: frame.rfc460Timestamp,
                blueTeamId: blueMeta.esportsTeamId,
                redTeamId: redMeta.esportsTeamId,
                blue: TeamStats(frame.blueTeam),
                red: TeamStats(frame.redTeam),
                bluePlayers: PlayerLine.lines(frame.blueTeam.participants, metadata: blueMeta.participantMetadata),
                redPlayers: PlayerLine.lines(frame.redTeam.participants, metadata: redMeta.participantMetadata)
            )
        }
    }
}
```

- [ ] **Step 5: Écrire `GameTimeline`**

Créer `LoLKit/Sources/LoLKit/Timeline/GameTimeline.swift` :

```swift
import Foundation

/// Un événement du fil de la game (spec fonctionnalités §4), déduit de deux frames successives.
public struct TimelineEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case kills
        /// Drake tué, avec son type (`infernal`, `ocean`, `cloud`, `mountain`, `hextech`, `chemtech`, `elder`).
        case dragon(String)
        case baron
        case tower
        case inhibitor
    }

    /// Temps de jeu de la frame où l'événement apparaît, en secondes depuis la première frame (même règle que le chrono :
    /// pauses comprises). L'événement a eu lieu entre la frame précédente et celle-ci.
    public let gameTime: TimeInterval
    /// Équipe qui a marqué (id lolesports).
    public let teamId: String
    public let kind: Kind
    /// Nombre gagné entre les deux frames (« +2 kills ») ; 1 pour un drake (un événement par drake).
    public let count: Int
    /// Pour les kills : pseudos des joueurs dont les kills ont augmenté, dans l'ordre du flux, seulement si la somme de
    /// leurs hausses vaut exactement `count` ; sinon vide (« +2 kills » sans nom : pas d'attribution inventée).
    public let players: [String]

    public init(gameTime: TimeInterval, teamId: String, kind: Kind, count: Int, players: [String] = []) {
        self.gameTime = gameTime
        self.teamId = teamId
        self.kind = kind
        self.count = count
        self.players = players
    }
}

/// Fil des événements d'une game : différences entre frames successives (spec fonctionnalités §4). La première frame sert
/// de référence (rien n'est inventé avant elle). Pas de hérauts ni de larves : le flux `window` ne les donne pas.
public enum GameTimeline {
    /// Événements dans l'ordre chronologique (l'appli les affiche du plus récent au plus ancien). Pour chaque pas : équipe
    /// bleue puis rouge ; kills, drakes, barons, tours, inhibiteurs. Une baisse (frame incohérente) n'est jamais un
    /// événement.
    /// - Parameters:
    ///   - snapshots: frames d'une même game (direct : une par lecture de 10 s ; relecture : une par pas de 60 s), triées
    ///     ici par horodatage.
    ///   - firstFrameTime: première frame de la game (fenêtre lue sans `startingTime`) : le 0:00 du temps de jeu.
    public static func events(from snapshots: [GameSnapshot], firstFrameTime: Date) -> [TimelineEvent] {
        let ordered = snapshots.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count > 1 else { return [] }
        var events: [TimelineEvent] = []
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            let gameTime = max(0, current.timestamp.timeIntervalSince(firstFrameTime))
            events += changes(team: current.blueTeamId, before: previous.blue, after: current.blue,
                              playersBefore: previous.bluePlayers, playersAfter: current.bluePlayers, at: gameTime)
            events += changes(team: current.redTeamId, before: previous.red, after: current.red,
                              playersBefore: previous.redPlayers, playersAfter: current.redPlayers, at: gameTime)
        }
        return events
    }

    static func changes(team: String, before: TeamStats, after: TeamStats, playersBefore: [PlayerLine],
                        playersAfter: [PlayerLine], at gameTime: TimeInterval) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let kills = after.kills - before.kills
        if kills > 0 {
            events.append(TimelineEvent(gameTime: gameTime, teamId: team, kind: .kills, count: kills,
                                        players: killers(before: playersBefore, after: playersAfter, teamKills: kills)))
        }
        if after.dragons.count > before.dragons.count {
            for type in after.dragons.dropFirst(before.dragons.count) {
                events.append(TimelineEvent(gameTime: gameTime, teamId: team, kind: .dragon(type), count: 1))
            }
        }
        let counted: [(TimelineEvent.Kind, Int)] = [
            (.baron, after.barons - before.barons),
            (.tower, after.towers - before.towers),
            (.inhibitor, after.inhibitors - before.inhibitors),
        ]
        for (kind, gained) in counted where gained > 0 {
            events.append(TimelineEvent(gameTime: gameTime, teamId: team, kind: kind, count: gained))
        }
        return events
    }

    /// Joueurs dont les kills ont augmenté, si la somme de leurs hausses explique exactement les kills de l'équipe. Les
    /// joueurs se suivent par position (le flux les donne toujours dans l'ordre de `participantId`) ; un pseudo absent ou
    /// différent d'une frame à l'autre : pas d'attribution.
    static func killers(before: [PlayerLine], after: [PlayerLine], teamKills: Int) -> [String] {
        guard before.count == after.count else { return [] }
        var names: [String] = []
        var total = 0
        for (previous, player) in zip(before, after) where player.kills > previous.kills {
            guard !player.name.isEmpty, player.name == previous.name else { return [] }
            names.append(player.name)
            total += player.kills - previous.kills
        }
        return total == teamKills ? names : []
    }
}
```

- [ ] **Step 6: Écrire `GoldSeries`**

Créer `LoLKit/Sources/LoLKit/Timeline/GoldSeries.swift` :

```swift
import Foundation

/// Un point de la courbe de l'écart de gold.
public struct GoldPoint: Sendable, Equatable {
    /// Temps de jeu en secondes depuis la première frame (même règle que `TimelineEvent.gameTime`).
    public let gameTime: TimeInterval
    /// Écart de gold total : positif quand l'équipe de référence mène.
    public let difference: Int

    public init(gameTime: TimeInterval, difference: Int) {
        self.gameTime = gameTime
        self.difference = difference
    }
}

/// Courbe de l'écart de gold (spec fonctionnalités §5), sur les mêmes frames que le fil des événements.
public enum GoldSeries {
    /// Un point par frame, dans l'ordre chronologique. Écart = bleu − rouge, réorienté vers `teamId` : si `teamId` est
    /// l'équipe rouge de la game, rouge − bleu. `teamId` nil ou absent de la game : bleu − rouge.
    public static func points(from snapshots: [GameSnapshot], firstFrameTime: Date, orientedTo teamId: String?) -> [GoldPoint] {
        snapshots.sorted { $0.timestamp < $1.timestamp }.map { snapshot in
            let blueMinusRed = snapshot.blue.gold - snapshot.red.gold
            return GoldPoint(gameTime: max(0, snapshot.timestamp.timeIntervalSince(firstFrameTime)),
                             difference: teamId == snapshot.redTeamId ? -blueMinusRed : blueMinusRed)
        }
    }
}
```

- [ ] **Step 7: Lancer le test pour le voir passer**

Run : `bash scripts/lolkit.sh test --filter GameTimelineTests`
Expected : PASS — `Test run with 5 tests in 1 suite passed`.

- [ ] **Step 8: Lancer toute la suite**

Run : `bash scripts/lolkit.sh test`
Expected : `Test run with 263 tests in 30 suites passed`, aucun `warning:`.

- [ ] **Step 9: Commit**

```bash
git add LoLKit/Sources/LoLKit/Timeline/LiveWindow+Snapshots.swift LoLKit/Sources/LoLKit/Timeline/GameTimeline.swift LoLKit/Sources/LoLKit/Timeline/GoldSeries.swift LoLKit/Tests/LoLKitTests/GameTimelineTests.swift LoLKit/Tests/LoLKitTests/Fixtures/window_replay.json
git commit -m "feat(lolkit): fil des événements (kills, drakes, barons, tours, inhibs) et courbe de l'écart de gold depuis les frames" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 10: Pousser la branche et vérifier la CI**

```bash
git push -u origin fonc/lolkit-t6-fil-gold
gh run list --workflow LoLKit --branch fonc/lolkit-t6-fil-gold --limit 1
gh run watch --exit-status <id de la ligne affichée>
```
Expected : jobs `test` et `test-macos` verts.

---

## Self-review

**Couverture de la spec (parties LoLKit) :**

| Exigence | Où |
|---|---|
| Principes : logique pure dans LoLKit, fixtures réelles (window, details, versions réduit, runesReforged / item / summoner réduits, réponse Leaguepedia réelle, getLive avec streams, getEventDetails avec vods) | T1-T6 ; fixtures nouvelles T3, T4, T5, T6 ; `getLive.json` (streams) et `getEventDetails.json` (vods) déjà au dépôt, utilisées par T1 |
| Principes : aucune clé secrète ; User-Agent « Faille (usage personnel) » | Global Constraints ; T5 (`LeaguepediaClient.userAgent`, testé) |
| Principes : sobriété réseau (`details` lourd à 60 s au plus) | T4 (`LoLClient.detailsInterval`, un seul appel pour une game terminée) ; caches disque : plan de l'appli |
| §1 `streams[]` (provider, parameter, locale) ; fr-FR → en-US → premier ; liens Twitch / YouTube / AfreecaTV ; autre fournisseur ignoré ; menu des autres streams | T1 (`StreamInfo`, `StreamPicker.preferred`, `.others`, `.url`) |
| §1 `games[].vods[]` (parameter, locale, startMillis) ; « Revoir la game N » ; `&t=<startMillis/1000>s` si > 0 | T1 (`Vod`, `GameRef.vods`, `StreamPicker.replay`) |
| §2 sélection : `unstarted`, équipe suivie, futur, `Presenter.nextLine` `.match` (F1 + C), 60 au plus, les plus proches d'abord, identifiant stable | T2 (`MatchReminders.plan`, `identifier`, tests F1, C, limite, ordre, heure passée) |
| §2 texte « KC vs C9 dans 15 min » / « Mondial · Play-in · Bo5 », jamais de score ; délais 5 / 15 / 30, défaut 15 | T2 (`title`, `subtitle`, `leadOptions`, `defaultLead`) |
| §3 version Data Dragon (patch → `major.minor`, sinon la plus récente), cache 24 h | T3 (`DataDragon.version`, `versionsMaxAge`) |
| §3 champions `img/champion/<id>.png` | T3 (`championImage`) |
| §3 `details` avec la même règle de `startingTime` (recul ≥ 80 s, paliers) | T4 (`details(gameId:now:)`, `steppingBack` partagé, `LiveStatsTime.delays`) |
| §3 objets (ids → images, noms fr_FR), runes (`perks[0]` + arbre secondaire, icônes `cdn/img/<icon>`), sorts du champion (`abilities` + `spells[].image.full`, passif) | T4 (`ParticipantDetails.items`, `.perkMetadata`, `.abilities`) ; T3 (`ItemCatalog`, `RuneCatalog`, `runeIcon`, `ChampionSpells`, `spellImage`, `passiveImage`) |
| §3 bonus : part des dégâts, participation aux kills, balises posées / détruites, niveau, CS | T4 (`championDamageShare`, `killParticipation`, `wardsPlaced`, `wardsDestroyed`, `level`, `creepScore`, `totalGoldEarned`) |
| §3 sorts d'invocateur des games terminées : Leaguepedia `ScoreboardPlayers`, ensemble des champions + ± 3 h, noms → `summoner.json` ; rien si le wiki n'a pas la game | T5 (`LeaguepediaClient.summonerSpells`, `SpellMatcher.match`, `ChampionKey`, `dataDragonSpellId`) ; T3 (`SummonerCatalog`, `summonerSpellImage`) |
| §4 fil : kills par équipe (joueurs quand déductible, sinon « +N kills »), drakes avec type, barons, tours, inhibs, temps de jeu ; hérauts « si présents » | T6 (`GameTimeline.events`) ; hérauts absents du flux → non produits (décision) |
| §4 relecture d'une game terminée à pas de 60 s, mise en cache | T6 (`LiveWindow.snapshots()` pour rejouer le cache ; fixture capturée exactement ainsi) ; requêtes et cache : plan de l'appli |
| §5 courbe (temps de jeu, écart bleu − rouge réorienté vers l'équipe suivie), mêmes frames que le fil | T6 (`GoldSeries.points(… orientedTo:)`) |

**Anti-spoiler :** seule T2 décide d'un affichage, et uniquement par `Presenter.nextLine` (tests F1, C, révélation, autre match révélé sans effet). Aucun texte de LoLKit ne porte un score ou un résultat (le titre n'a que les codes et le délai). Les autres API sont pures et documentées « l'appli ne les appelle pas pour un match masqué » (StreamPicker, GameDetails, Leaguepedia) ; aucune ne déclenche de requête d'elle-même.

**Disjonction des fichiers :** chaque chemin de la matrice n'apparaît qu'une fois ; `MatchEvent.swift` (T1) et `LoLClient.swift` (T4) ont un seul propriétaire ; aucune tâche ne modifie `Package.swift`, `Support/*` ni une fixture existante ; les helpers privés de fichier ont des noms distincts (`Tolerant` en T3, `Lenient` / `CargoResponse` en T5). Vérifié : chaque tâche seule sur `HEAD` et les six fusionnées compilent et passent (299 tests).

**Cohérence des types :** `StreamInfo(statsStatus:provider:parameter:locale:)`, `Vod(provider:parameter:locale:startMillis:)`, `GameRef(…, vods:)` (T1) ; `MatchReminder(id:matchId:fireDate:title:subtitle:)`, `MatchReminders.plan(schedule:follows:revealed:now:lead:)` (T2, signature de la spec) ; `DataDragon.version(forPatch:versions:)` (signature de la spec), `ItemCatalog.inventory(_:) -> ItemCatalog.Inventory` (T3) ; `LoLClient.details(gameId:now:)` / `details(gameId:startingTime:)` → `GameDetails` → `DetailsFrame` → `ParticipantDetails` → `PerkMetadata` (T4) ; `LeaguepediaClient.summonerSpells(champions:around:) -> [String: [String]]?` dont les valeurs sont des ids que `SummonerCatalog.spell(_:)` (T3) connaît (`SummonerFlash`, `SummonerDot`…) (T5) ; `GameTimeline.events(from:firstFrameTime:) -> [TimelineEvent]`, `GoldSeries.points(from:firstFrameTime:orientedTo:) -> [GoldPoint]` (T6, signatures de la spec). Les ids de champion du flux (`championId`, ex. « KSante ») servent à la fois à `DataDragon.championImage`, `DataDragon.championURL` et `SpellMatcher.match` ; les ids d'objets de `ParticipantDetails.items` sont les clés de `ItemCatalog.items`.

**Balayage des marqueurs :** aucun « TBD », « TODO », « à compléter » ni renvoi « comme la tâche N » ; chaque étape de code donne le code entier.
