# Faille — spec de conception v1

> Appli iOS perso pour suivre en direct les matchs LoL esport des équipes qu'on suit, jusque sur l'écran verrouillé.
> Date : 13/10/2026 · Statut : à relire par Dan · Nom de travail : **Faille** (la Faille de l'invocateur), modifiable.

## 1. Objectif et périmètre

**Ce que fait l'appli, et rien d'autre :**

1. Choisir les équipes LoL esport qu'on suit, dans toutes les ligues que l'API lolesports propose (Mondial, MSI, First Stand, LEC, LCK, LPL, LTA, LFL…).
2. Voir leurs matchs : en direct, à venir, derniers résultats.
3. Voir les stats en direct d'une game : stats d'équipe et stats des joueurs.
4. Afficher le match en direct d'une équipe suivie sur l'écran verrouillé (Live Activity + Dynamic Island).
5. Afficher le prochain match des équipes suivies en widget (écran verrouillé et écran d'accueil).
6. Masquer les scores d'une équipe au choix (mode anti-spoiler).

**Hors périmètre v1 :** notifications de début de match, historique des saisons, classements, VOD et liens de stream, comptes utilisateurs, Apple Watch, publication sur l'App Store, serveur de push (conçu en §12, construit en phase 2).

**Appareils :** iPhone (tout) et iPad (appli + widgets ; Apple n'affiche pas les Live Activities sur iPad). **iOS 26.0 minimum** (Liquid Glass natif).

## 2. Contraintes

| Contrainte | Conséquence |
|---|---|
| Développement sur Windows, pas de Mac | Logique en Swift pur testable sur Windows ; compilation iOS sur un Mac cloud (GitHub Actions) ; projet Xcode généré par XcodeGen depuis `project.yml`. |
| Compte Apple gratuit d'abord | Installation par **AltServer** (Sideloadly ne signe pas les extensions avec un compte gratuit, vérifié le 13/10), re-signature tous les 7 jours, pas de push : la Live Activity se met à jour quand l'appli tourne. |
| Compte payant plus tard (99 €/an) | Le format de données de la Live Activity est figé dès la v1 pour que le serveur de push (phase 2) s'y branche sans changer l'appli. |
| API lolesports non officielle | Usage strictement personnel, jamais publié. Toute la dépendance à l'API est isolée dans une seule couche de `LoLKit`. |
| Dépôt GitHub public | Aucun secret dans le code, jamais. Git configuré avec l'adresse `noreply` de GitHub. Passage en privé + Xcode Cloud au moment du compte payant. |

## 3. Architecture

```
App Esport en direct/            (dépôt « faille »)
├─ LoLKit/                       Swift package, aucune dépendance Apple-only
│  ├─ Sources/LoLKit/
│  │  ├─ API/                    clients HTTP lolesports + livestats, décodage tolérant
│  │  ├─ Models/                 League, Team, Match, Game, TeamStats, PlayerStats
│  │  ├─ Follow/                 équipes suivies, anti-spoiler, couleurs d'équipe
│  │  ├─ Live/                   LiveMatchState (état de la Live Activity), machine d'états d'un match
│  │  ├─ Presentation/           règle anti-spoiler unique, formats (gold, dates, chrono)
│  │  └─ Color/                  extraction de la couleur dominante d'un logo (pixels RGBA bruts)
│  ├─ Sources/lolkit-cli/        exécutable `swift run lolkit …` pour tester l'API depuis Windows
│  └─ Tests/LoLKitTests/         tests + fixtures JSON réelles
├─ App/                          appli SwiftUI (iPhone + iPad)
├─ Widgets/                      extension WidgetKit : widgets + vue de la Live Activity
├─ Shared/                       code iOS partagé App ↔ Widgets (stockage App Group, polices, DA)
├─ Resources/Fonts/              Sora 400/500/600/700 (licence OFL)
├─ project.yml                   description XcodeGen
├─ .github/workflows/            CI (voir §11)
└─ docs/                         specs, plans
```

**Règles :**
- `LoLKit` compile sur Windows, Linux et iOS. Il n'importe ni SwiftUI, ni WidgetKit, ni ActivityKit. Tout ce qui peut casser y vit et y est testé.
- `App/` et `Widgets/` sont fins : ils affichent ce que `LoLKit` leur donne.
- La conformité `ActivityAttributes` est un fichier iOS de quelques lignes dans `Shared/` qui enveloppe `LiveMatchState` de `LoLKit`.
- Aucune dépendance externe en v1.

**Identifiants :** bundle ID `com.cafe1231.faille`, extension `com.cafe1231.faille.widgets`, App Group `group.com.cafe1231.faille`.

## 4. Données

### 4.1 Sources

| Besoin | Appel | Cadence |
|---|---|---|
| Ligues | `esports-api.lolesports.com/persisted/gw/getLeagues?hl=fr-FR` | 1×/jour, cache |
| Équipes et logos | `…/getTeams?hl=fr-FR` | 1×/jour, cache |
| Calendrier, résultats | `…/getSchedule?hl=fr-FR&leagueId=a,b,c` (ligues d'attache des équipes suivies + Mondial, MSI, First Stand ; une seule page, qui couvre environ ±6 semaines) | toutes les 30 min, et à chaque ouverture |
| Matchs en cours | `…/getLive?hl=fr-FR` | 60 s (le CDN met en cache 60 s) |
| Games d'un match | `…/getEventDetails?hl=fr-FR&id=…` | à l'ouverture d'un match en direct, puis à chaque changement de game |
| Stats d'équipe **et des joueurs** en direct | `feed.lolesports.com/livestats/v1/window/{gameId}?startingTime=…` (les joueurs : `frames[].*.participants` + `gameMetadata` pour champion, rôle et pseudo) | 10 s, uniquement pour les games affichées |
| Début d'une game (pour le chrono) | `…/window/{gameId}` **sans** `startingTime` : renvoie les premières frames | une fois par game |

- L'API `persisted/gw` exige l'en-tête `x-api-key` : la clé publique que le site lolesports.com envoie à chaque visiteur. Elle vit dans une seule constante de `LoLKit/API`.
- `startingTime` est arrondi aux 10 s et décalé d'environ 1 min dans le passé (le flux livestats a ce retard sur le direct).
- `frames[].gameState` vaut `in_game`, `paused` ou `finished`.
- **Stats indisponibles** : `streams[].statsStatus == "disabled"` (vu sur `getLive`) ou une 404 sur `window`. Vérifié le 13/10 : un match aux stats désactivées peut aussi renvoyer `window` en 200 avec des frames à zéro, donc **c'est `statsStatus` qui fait foi**. Le match passe alors en **score seul**.
- Le flux `livestats/v1/details` n'est pas utilisé en v1 (`window` suffit).

### 4.2 Modèles (LoLKit)

- `League` : id, slug, nom (fr), image, priorité.
- `Team` : id, code (« KC »), nom, image, ligue d'attache.
- `Match` : id, ligue, bloc (« Play-in »), `bestOf`, horaire, état (`unstarted | inProgress | completed`), deux équipes avec victoires en série, games.
- `Game` : id, numéro, état, côté de chaque équipe.
- `TeamStats` : kills, gold total, tours, inhibiteurs, barons, dragons (liste des types).
- `PlayerStats` : rôle, champion, niveau, K/D/A, CS, gold.
- `FollowedTeam` : id d'équipe, ordre de suivi, `spoilerFree: Bool`, `colorOverride: RGB?`.

**Reconnaître une équipe suivie dans un match** : `getLive` et `getEventDetails` donnent l'id des équipes, mais **`getSchedule` ne le donne pas** (seulement nom, code, logo), et plusieurs équipes actives partagent le même code (FUR, DK, HLE…). Règle : on compare l'id quand il est présent, sinon le nom (sans tenir compte de la casse), sinon l'URL du logo. Jamais le code seul. Le nom, le code et le logo des équipes suivies sont rafraîchis chaque jour depuis `getTeams` par id (renommages de sponsor).

**Ligue d'attache** : `getTeams` donne `homeLeague.name`, qui correspond au `name` de `getLeagues` (« La Ligue Française » pour la LFL, « Mondial » pour les Worlds). Environ 40 % des équipes actives n'ont pas de ligue d'attache ; elles sont trouvables par la recherche.

Le décodage est **tolérant** : tout champ non essentiel est optionnel. Un champ inconnu ou absent dégrade l'affichage au lieu de faire échouer le décodage.

### 4.3 LiveMatchState (contrat de la Live Activity)

Le même JSON sert à l'appli (v1) et au serveur de push (phase 2). Taille cible < 1 Ko (limite Apple : 4 Ko).

- **Attributs fixes** (au démarrage, construits depuis `getEventDetails`, qui donne toujours les ids d'équipe) : `matchId`, ligue, `bestOf`, pour chaque équipe : **id**, code, nom, couleur (hex, si suivie) ; `primaryTeamIndex` = l'équipe suivie la plus anciennement suivie (fond de la Live Activity, Dynamic Island minimale). Jamais de code d'équipe à la place d'un id.
- **État dynamique** (scores et stats dans l'ordre de `attributes.teams`) :
  - `phase` : `upcoming | inGame | betweenGames | finished` (valeur inconnue lue comme `inGame`)
  - `seriesScore` : [a, b]
  - `gameNumber`
  - `gameClockStart` : date de début estimée de la game (sert au chrono qui tourne seul) ; calculée même si les stats sont désactivées
  - `gameClockStoppedAt` : rempli quand la game est en pause ou finie dans le flux ; le chrono s'arrête à cette date
  - `stats` : `TeamStats` des deux équipes, ou `nil` si indisponibles
  - `statsAvailable: Bool`
  - `spoilerFree: Bool`
  - `winnerCode` (si terminé)
  - `updatedAt`

Le chrono est affiché avec un minuteur natif d'iOS à partir de `gameClockStart` (et `gameClockStoppedAt` s'il est rempli) : il avance sans aucune mise à jour.

**Format du JSON** : `JSONEncoder` par défaut — dates en secondes depuis le 1er janvier 2001 (`deferredToDate`), champs nil omis. Une fixture dorée (`LoLKit/Tests/LoLKitTests/Fixtures/live_contract.json`) fige ce format ; le serveur de la phase 2 l'utilisera dans ses propres tests. Côté iOS : `extension LiveMatchAttributes: ActivityAttributes { typealias ContentState = LiveMatchState }`, pour que le JSON des push soit exactement celui de la fixture.

### 4.4 Stockage

- **App Group** (partagé appli ↔ extension) : équipes suivies et leurs réglages, couleurs d'équipe, calendrier en cache, dernier état connu des matchs en direct. Stockage par fichiers JSON.
  - **Le nom du groupe est lu à l'exécution, jamais écrit en dur** : les outils de signature le renomment (AltServer : `group.com.cafe1231.faille.<TEAMID>`, et les bundle IDs deviennent `com.cafe1231.faille.<TEAMID>`). Ordre : groupes du `embedded.mobileprovision` du bundle courant, puis la clé `ALTAppGroups` de l'Info.plist, puis le nom configuré ; on garde le premier dont `containerURL` n'est pas nil. Même règle dans l'appli et l'extension. Aucun code ne suppose un bundle ID fixe.
  - La liste des équipes suivies se décode de façon tolérante (champs nouveaux optionnels, entrée illisible ignorée) : une mise à jour de l'appli ne doit jamais faire perdre les équipes suivies.
- **Cache réseau** : réponses `getLeagues`, `getTeams` et `getSchedule` gardées sur disque avec leur date, et réutilisées si l'API ne répond pas.
- **Logos** : téléchargés et mis en cache par l'appli. Live Activity et widgets **n'affichent pas les logos** mais un monogramme (le code de l'équipe dans un badge à sa couleur), comme sur les maquettes. Ça évite les images dans la Live Activity et réduit la dépendance à l'App Group.

## 5. Écrans de l'appli

Deux onglets dans une barre de navigation en pilule flottante : **Matchs** et **Équipes**.

### 5.1 Matchs (version B : une carte Vitrail par équipe)

- Titre « Mes équipes », sous-titre « N en direct · N à venir ».
- Une carte en verre teintée à la couleur de l'équipe, par équipe suivie. Ordre : équipes en direct d'abord, puis par horaire du prochain match.
- Contenu d'une carte :
  - **En direct** (si c'est le cas) : puce « En direct · Game N · chrono », score de série, ligne de stats (kills, écart de gold, drakes, tours).
  - **Prochain** : adversaire, date, heure locale.
  - **Dernier** : dernier résultat.
- Tirer pour rafraîchir. Toucher un match ouvre le Détail.
- Équipe en anti-spoiler : voir §8.
- Aucune équipe suivie : message d'accueil et bouton vers l'onglet Équipes.

### 5.2 Équipes

- Champ de recherche sur toutes les équipes.
- **Mes équipes** : monogramme ou logo, nom, ligue, icône œil (anti-spoiler on/off), étoile (suivre / ne plus suivre). Appui long : « Changer la couleur » (sélecteur de couleur) et « Couleur automatique ».
- **Toutes les ligues** : pilules de ligues (ordre de priorité de l'API), puis la liste des équipes de la ligue choisie, chacune avec son étoile.
- Engrenage : **Réglages**.

### 5.3 Détail d'un match

- Retour, carte d'en-tête teintée : ligue, bloc, Bo, chrono, équipes, score de série.
- Pilules de games (G1 ✓, G2 en direct, G3…), une par game jouée ou à venir.
- **Stats d'équipe** de la game choisie : kills, gold (+ barre d'écart), tours, inhibiteurs, drakes (avec leurs types), barons.
- **Joueurs** : sélecteur d'équipe, puis 5 lignes rôle / champion / KDA / CS.
- Bouton **« Épingler sur l'écran verrouillé »** / **« Retirer de l'écran verrouillé »** (iPhone uniquement).
- Stats désactivées : score de série + message « Stats live non fournies par Riot pour ce match ».

### 5.4 Réglages

- Live Activity : **Automatique** (défaut) ou **Manuelle**.
- Lien « À propos » : source des données, version.

## 6. Live Activity

### 6.1 Contenu (écran verrouillé)

- **En-tête** : « LIGUE · Bo5 · Game N » à gauche, chrono qui tourne à droite.
- **Score** : monogramme + code de chaque équipe, score de série au centre.
- **Stats**, 5 lignes `valeur A · icône + libellé · valeur B` : kills, gold (+ écart à la couleur de l'équipe qui mène), tours, drakes, barons.
- **Fond** : dégradé de la couleur de l'équipe suivie vers l'abysse. Si les deux équipes sont suivies : celle suivie en premier.

### 6.2 Dynamic Island

- **Compacte** : monogramme + victoires de chaque côté de la caméra.
- **Minimale** : monogramme de l'équipe suivie + score.
- **Déployée** : équipes, score, « Game N · chrono », puis une ligne avec les 5 stats.

### 6.3 États

| État | Affichage |
|---|---|
| `inGame` | Tout le contenu du §6.1 |
| `betweenGames` | Score de série + « La game N commence dans quelques minutes » |
| `finished` | « Victoire XX », score final. La Live Activity se retire 1 h après la fin. |
| Stats indisponibles | Score + chrono + message |
| Pas fraîche (`staleDate` dépassée) | « màj il y a X minutes » (texte système qui avance seul, sans secondes) à la place du chrono, stats pâlies |
| Anti-spoiler | Voir §8 |

### 6.4 Démarrage et fin (v1, sans push)

- **Automatique** : à chaque tour du premier plan (10 s), une Live Activity est créée pour chaque match en direct impliquant une équipe suivie qui n'en a pas déjà une (un match qui commence pendant que l'appli est ouverte a donc aussi la sienne). Au maximum **3 en même temps** (terminées encore affichées comprises, pas d'éviction), par ordre de suivi des équipes. Une Live Activity ne peut être créée qu'au premier plan : ouvrir Faille pendant le match suffit.
- **Manuelle** : uniquement via le bouton du Détail.
- L'utilisateur peut toujours en retirer une d'un glissement. Une Live Activity retirée à la main n'est pas recréée automatiquement pour ce match.
- **Mises à jour** :
  - Au premier plan : à chaque rafraîchissement des données (10 s).
  - Au passage en arrière-plan : une dernière mise à jour.
  - En arrière-plan : à chaque `BGAppRefreshTask`, demandée toutes les 15 min tant qu'un match suivi est en direct ou qu'une Live Activity est affichée (iOS décide seul s'il l'accorde ; jamais si l'appli a été fermée de force).
  - Chaque mise à jour fixe `staleDate = updatedAt + 3 min`, où `updatedAt` est la dernière relecture réussie des données (pas l'heure de la mise à jour) : une donnée vieille est montrée « pas fraîche » tout de suite.
- **Fin** : quand le match passe à `completed` (direct, calendrier, ou détails du match pour une compétition hors des ligues suivies), état `finished`, puis fin de la Live Activity 1 h après le moment où l'appli l'apprend.

## 7. Widgets

| Widget | Emplacement | Contenu |
|---|---|---|
| En ligne | Écran verrouillé, au-dessus de l'heure | « KC 1–0 C9 · G2 » si un match est en direct, sinon « GEN vs FUR · jeu. 11:00 » |
| Rectangulaire | Écran verrouillé | « PROCHAIN », match, date et heure (ou match en direct) |
| Rond | Écran verrouillé | Compte à rebours jusqu'au prochain match (jauge) + code de l'équipe |
| Petit | Écran d'accueil | Prochain match d'une équipe, teinté à sa couleur |
| Moyen | Écran d'accueil | Matchs en direct, puis prochains matchs de toutes les équipes suivies (4 lignes) |

- Les widgets de l'écran verrouillé sont rendus en monochrome par iOS. Ils utilisent Sora et les icônes, sans les couleurs d'équipe.
- **Planning** : calculé à partir du calendrier en cache. Entrées sur 6 h : maintenant, chaque début de match à venir d'une équipe suivie, les paliers du compte à rebours et les fins de confiance des données. Rechargement demandé à iOS 5 h plus tard (horizon − 1 h) : les entrées couvrent déjà chaque début de match, l'appli recharge les widgets à chaque relecture réussie, et iOS limite le nombre de rechargements. Un match dont l'heure est passée reste « à venir » (« 0 min ») tant que des données fraîches (≤ 10 min) ne le disent pas commencé ; sans donnée fraîche, il est présumé commencé et son issue est inconnue (anti-spoiler : « Prochain · masqué »).
- L'appli appelle `WidgetCenter.reloadAllTimelines()` à chaque rafraîchissement du calendrier au premier plan.
- Le petit widget affiche par défaut la première équipe suivie ; l'équipe se choisit dans les réglages du widget (configuration `AppIntent`).

## 8. Anti-spoiler

- Réglage par équipe suivie (icône œil dans Équipes).
- **Un match est masqué si au moins une des deux équipes est en anti-spoiler.**
- Un match masqué n'affiche :
  - ni score de série, ni numéro de game, ni stats, ni vainqueur, ni résultat dans « Dernier » ;
  - que « En direct », « Terminé » ou « À venir », avec la date. Entre deux games, un match masqué reste « En direct » (sinon le nombre de pauses trahit la longueur de la série).
- **Le prochain match ne doit rien trahir non plus** : tant que le dernier match en direct ou terminé d'une équipe est masqué et non révélé, la ligne « Prochain » affiche « Prochain · masqué » (qu'un prochain match existe ou non), et l'équipe ne compte pas dans « N à venir » ni dans le tri des cartes par prochain match (`Presenter.nextLine`). Sinon une élimination ou une qualification se lirait sur la carte. De même, un prochain match contre une AUTRE équipe suivie en anti-spoiler dont le dernier match est masqué et non révélé (« GEN vs T1 » sur la carte de GEN, tant que le dernier match de T1 est masqué) est affiché « Prochain · masqué » ; si le dernier match de T1 est révélé (ou si T1 n'en a pas), « GEN vs T1 » s'affiche. Résidu connu, accepté pour l'instant : un fan attentif peut encore déduire un résultat (la carte de GEN n'est masquée que si son adversaire est T1) ; une variante stricte (aucune équipe n'annonce son prochain adversaire tant qu'un match anti-spoiler est masqué) reste possible.
- Partout, sans exception : appli, Live Activity, Dynamic Island, widgets.
- **Révéler** : dans l'appli seulement, « toucher pour révéler » sur la carte ou le Détail. La révélation est mémorisée pour ce match. Live Activity et widgets suivent cette révélation à leur prochaine mise à jour.
- La règle est une **fonction unique** de `LoLKit/Presentation` (`SpoilerPolicy.isMasked`) ; `Presenter.scoreLine` (appli, widgets) et `LiveMatchBuilder.state` (Live Activity) l'appellent eux-mêmes à partir des équipes suivies et des matchs révélés. Toutes les surfaces passent par elles.

## 9. Direction artistique (reprise d'Échap Hub)

- **Abysse** : fond `#0b1020`, nappe bleue `rgba(60,140,255,0.18)` en haut à gauche, nappe turquoise `rgba(0,220,200,0.14)` en bas à droite. Texte `#e9eefb`, secondaire `#94a0bf`, accent `#6fd3ff`.
- **Verre** : Liquid Glass natif d'iOS 26 pour la barre d'onglets et les boutons de barre d'outils ; cartes et bandeau en verre « matière » qui reproduit Échap (`.ultraThinMaterial` + dégradé de la teinte + reflet en haut + bordure lumineuse + ombre profonde). Le Liquid Glass sur les cartes réfractait le contenu juste au-dessus d'elles (écho visible, étape 2). Coins 28 pt (cartes) et 22 pt (éléments internes).
- **Sora** 400/500/600/700, embarquée dans l'appli et l'extension. Titres 32 pt, graisse 700, interlettrage -0,04 em ; corps 15 pt ; secondaire 12 pt ; étiquettes 11 pt en capitales espacées.
- **Icônes** au trait (1,8 pt, grille 24), jamais d'emoji. Jeu dédié : kills (épées), gold (pièces), tour, inhibiteur (cristal), drake (flamme), baron (hexagone), en direct (ondes), anti-spoiler (œil barré), suivre (étoile), réglages, recherche.
- **Vitrail : une teinte = une équipe suivie.** Carte teintée : dégradé à 160° de la couleur de l'équipe vers `rgba(255,255,255,0.03)`, point lumineux dans l'en-tête. Équipes non suivies : verre neutre. La nature d'une info se lit à son icône, jamais à sa couleur. « En direct » est donc une icône + du texte, pas du rouge.
- **Couleur d'équipe** :
  - Calcul : la couleur dominante saturée du logo, en ignorant les pixels transparents, quasi blancs et quasi noirs. Elle est ensuite éclaircie si besoin pour rester lisible sur `#0b1020`.
  - Où : l'algorithme est dans `LoLKit/Color` et travaille sur des pixels bruts (testable sur Windows) ; l'appli fournit les pixels du logo décodé.
  - Si le logo est illisible : `#6fd3ff`.
  - Surcharge manuelle possible (§5.2).
- Maquettes de référence : `docs/maquettes/ecrans-appli.html` et `docs/maquettes/ecran-verrouille.html`.

## 10. Gestion des erreurs

| Cas | Comportement |
|---|---|
| Réseau absent, API en 5xx | Dernières données en cache + bandeau discret « lolesports ne répond pas · màj HH:MM ». Nouvel essai au prochain cycle. |
| 403 sur `persisted/gw` (clé changée) | Même bandeau + log explicite. Corrigé en changeant la constante de clé. |
| `window` en 404 « Stats are disabled » / `statsStatus == disabled` | Match en score seul, partout. |
| JSON inattendu | Décodage tolérant ; si un objet entier est illisible, il est ignoré et logué, le reste s'affiche. |
| Live Activities désactivées par l'utilisateur dans iOS | Le bouton « Épingler » explique où les réactiver. |
| Plus de 3 matchs suivis en direct | Les 3 premières équipes suivies ont une Live Activity ; les autres restent dans l'appli. |
| App Group renommé ou indisponible | Nom résolu à l'exécution (§4.4). S'il n'y a vraiment aucun groupe : plan B, le widget lit l'API lui-même et l'équipe se choisit dans sa configuration. |
| Un match quitte `getLive` | Rafraîchir aussitôt `getSchedule` ; tant que `getLive` répond, il fait foi pour « en direct » (pas de repli sur un calendrier périmé). |

## 11. Tests

1. **`swift test` (Windows via Docker, et CI Linux)** sur `LoLKit`, avec des fixtures JSON réelles capturées le 13/10/2026 :
   - **Fixtures** : `getLeagues`, `getTeams` (réduit), `getSchedule` (LEC + Mondial, réduit), `getLive` (match aux stats désactivées), `getEventDetails` (finale LCS terminée), `window` avant la game, en jeu et en fin de game. La 404 est simulée par un faux transport.
   - **Sur Windows** : Swift tourne dans un conteneur Docker (`swift:6.2`) via `scripts/lolkit.sh`, sans installer Swift pour Windows.
   - **Lecture** : décodage de chaque fixture ; tolérance (champ retiré → pas d'échec).
   - **Calculs** : écart de gold, liste des drakes.
   - **Machine d'états** : `upcoming → inGame(N) → betweenGames → … → finished`.
   - **Anti-spoiler** : chaque champ masqué, cas « une seule des deux équipes ».
   - **Live Activity** : détection de « pas fraîche » ; ordre et limite de 3 Live Activities ; taille du JSON `LiveMatchState` < 4 Ko.
   - **Couleur** : extraction sur quelques tableaux de pixels types.
2. **`swift run lolkit live`** (Windows) : liste les matchs en direct et leurs stats depuis la vraie API.
   - `swift run lolkit schedule KC` : prochains matchs d'une équipe.
   - `swift run lolkit leagues` : liste des ligues.
3. **CI iOS (macOS)** :
   - Génération XcodeGen, puis compilation de l'appli + extension non signées, puis `.ipa` en artefact.
   - Un test d'aperçu produit des **PNG** de la Live Activity (tous les états), de la Dynamic Island et des widgets, via `ImageRenderer` sur simulateur. Ils sont publiés en artefact pour voir le rendu depuis Windows.
4. **Sur iPhone** : checklist pendant un vrai match des Worlds (démarrage auto, chrono, mise à jour au premier plan, état pas frais en arrière-plan, anti-spoiler, fin de match, widgets).

**Workflows** :
- `lolkit.yml` : Linux, `swift test`, à chaque push.
- `ios.yml` : macOS, à chaque push sur `main` et à la demande.

## 12. Phase 2 (conçue, non construite)

À faire quand le compte Apple Developer payant est pris :

- **Serveur** : un Cloudflare Worker (TypeScript) avec un Durable Object.
  - Il interroge `getLive` toutes les 60 s et `livestats/window` toutes les 15 s pour les matchs des équipes suivies par au moins un appareil.
  - Il calcule le même `LiveMatchState` (contrat §4.3, partagé via une fixture JSON commune aux tests Swift et TypeScript).
  - Il l'envoie à APNs : mise à jour par jeton de Live Activity, et **push-to-start** pour démarrer automatiquement sans ouvrir l'appli.
- **Appli** : envoie au Worker son jeton push-to-start, les jetons de chaque Live Activity et ses équipes suivies. Le mode automatique passe alors du « à l'ouverture » au « dès le début du match ».
- **Secrets** (clé APNs `.p8`, jetons Cloudflare) : uniquement dans les secrets Cloudflare et GitHub.
- **Distribution** : dépôt passé en privé, CI déplacée sur Xcode Cloud, installation par TestFlight.

## 13. Ordre de construction

| Étape | Contenu | Terminé quand |
|---|---|---|
| **0. Chaîne de bout en bout** | Appli vide + extension widget + App Group, `project.yml`, workflow iOS, `.ipa` installée avec AltServer | Le widget affiche sur l'iPhone une valeur écrite par l'appli dans l'App Group. Sinon, on bascule sur le plan B du §10 avant d'aller plus loin. |
| **1. LoLKit** | Modèles, clients API, fixtures, présentation/anti-spoiler, machine d'états, couleur, CLI | `swift test` vert sur Windows ; `lolkit live` affiche un match des Worlds |
| **2. Appli** | DA (tokens, Sora, verre), Équipes, Matchs (B), Détail, Réglages, cache | Suivre une équipe et voir ses matchs sur l'iPhone |
| **3. Widgets** | 3 widgets écran verrouillé + 2 écran d'accueil | Widgets justes sur l'iPhone, aperçus PNG en CI |
| **4. Live Activity** | Vues + Dynamic Island, états, auto/manuel, arrière-plan, pas fraîche | Checklist §11.4 passée pendant un match des Worlds |

Plans : `docs/superpowers/plans/2026-10-13-etape-0-chaine.md` et `docs/superpowers/plans/2026-10-13-lolkit.md`. Les plans des étapes 2 à 4 seront écrits après le verdict de l'étape 0 (App Group ou plan B) et une fois les interfaces de LoLKit stabilisées.

## 14. Risques et points ouverts

- **L'API lolesports change** (des indices montrent une migration vers GraphQL côté site) : toute la dépendance est dans `LoLKit/API`, et les fixtures permettent de voir tout de suite ce qui a cassé.
- **Signature avec un compte gratuit (étape 0, 13/10)** : Sideloadly 0.70.1 laisse l'extension sans profil (widget et Live Activity invisibles) ; **AltServer** signe l'appli et l'extension avec le groupe `group.com.cafe1231.faille.TA6JYZWPU9`, conteneur OK des deux côtés. Outil retenu : AltServer. Repli : Impactor, puis compte payant.
- **Compte gratuit** : appli à réinstaller tous les 7 jours, 3 applis sideloadées maximum, 10 identifiants d'app par semaine (l'appli en consomme 2).
- **Retard des stats** : environ 1 min derrière le direct, ce qui est normal pour ce flux.
- **Confirmé par Dan (13/10/2026)** :
  - iPhone sous iOS 26 : minimum iOS 26.0 retenu.
  - Nom « Faille » et identifiant `com.cafe1231.faille` retenus.

## Annexes

- Étude de marché : `reports/Applis iOS suivi esport LoL.md`. Deux applis indé proches (My Roster, Riftly), aucune ne combine sans pub, anti-spoiler sur l'écran verrouillé, tours et inhibiteurs, et widget d'écran verrouillé.
- Maquettes : voir §9.
