# LoLKit (étape 1) — journal d'exécution, décisions et points différés

Copie du journal de suivi au 13/10/2026 : décisions prises pendant l'exécution (« Ruling ») et remarques mineures différées, à reprendre dans les plans des étapes 2 à 4.


Worktree: .worktrees/lolkit, branche `lolkit` (depuis 9cac237). Spec : docs/superpowers/specs/2026-10-13-faille-design.md (lue).
Autorisation de Dan (13/10) : push libre, exécution sans validation entre tâches.

## Pre-flight scan
| Tâches | Produit → consommé | Constat |
|---|---|---|
| T1 → T12 | Package.swift (lib + tests) → remplacé en T12 (+ exécutable `lolkit`) | cohérent |
| T1 → T2..T11 | `Fixture.data(_:)`, `Fixture.Missing` | OK |
| T2 → T3,T4,T5 | `JSONDecoder.lolesports()`, `LoLDate`, `LossyArray` | OK |
| T2 → T3,T6 | `League`, `Team`, `TeamsResponse` (catalogTeam) | OK |
| T3 → T4..T10 | Builders `date`, `makeTeam`, `makeEvent`, `makeDetails`, `catalogTeam` ; modèles `MatchEvent`, `EventDetails`, `GameRef`, `MatchTeam` (memberwise internes via @testable) | OK, T4 n'utilise que `date` (défini en T3, avant) |
| T4 → T5,T9 | `LiveWindow`, `GameSnapshot`, `TeamStats: Hashable` (exigé par `LiveMatchState: Hashable`) | OK |
| T5 → T12 | `LoLClient`, `LiveStatsTime`, `LoLAPIError` | OK |
| T6 → T7..T10,T12 | `FollowList`, `FollowedTeam`, `MatchTeam.isSame(as:)`, `ScheduleQuery` | OK |
| T7 → T12 | `TeamCards.build` | OK |
| T8 → T12 | `Format.gold`, `Format.matchDate` | OK |
| T9, T10, T11 | autonomes | OK |
| Chaque tâche (interne) | tests ↔ code vérifiés valeur par valeur à la planification (dates/jours de semaine, arrondis gold, ids de fixtures, ordres de tri) ; correction déjà appliquée au plan : `payloadStaysSmall` utilise `window_ingame` | OK |
| Plan ↔ rubric | aucun test vide ni duplication imposés | OK |

Ruling 1: worktree manuel `.worktrees/lolkit` ignoré via `.git/info/exclude` (pas `.gitignore`) — l'outil natif EnterWorktree est réservé aux demandes explicites de « worktree », et `.gitignore` est modifié en parallèle par l'étape 0 sur `main` — si faux : un dossier local non suivi, sans impact sur le dépôt.
Ruling 2: implémenteurs sur le modèle le moins cher (le plan contient tout le code), relecteurs sur un modèle intermédiaire — si faux : quelques tours de correction en plus, escalade prévue aux tours 4-5.
Ruling 3: la ligne de commit reste « Co-Authored-By: Claude Opus 5.5 » pour tous les commits, quel que soit le modèle de l'implémenteur — c'est la consigne d'attribution du contrôleur et du plan — si faux : trailers à corriger, sans impact fonctionnel.
Task 1: complete (commits 9cac237..65cf365, review clean)
Task 1: minor (deferred): lolkit.yml sans `permissions: contents: read` ni trigger pull_request (plan-mandated) ; pas de test dédié à Fixture.data (vérifié par le relecteur dans une copie, couvert implicitement dès T2)
Task 2: note — préoccupation « tests seulement sous Linux » : couverte plus tard par la compilation iOS de LoLKit (étape 2) ; envisager un job macOS de tests dans la vraie CI
Task 2: complete (commits 65cf365..952e648, review clean)
Task 2: minor (deferred): LossyArray skip `try?` boucle théorique si Skip lançait (brief-mandated) ; test de date faible (pas d'aller-retour fractionnel, stratégie du décodeur non testée directement) ; assertion NXB sans #require ; LossyArray non testé avec null/scalaires ; League/Team sans init public (à ajouter quand l'appli en construira) ; 2 ISO8601DateFormatter par parse
Task 3: complete (commits 952e648..af0f0da, review clean ; 1 déviation documentée : allSatisfy { $0.isPlaceholder } au lieu du key path, refusé par #expect en Swift 6.2)
Task 3: minor (deferred): indexations après #expect non bloquant (events[3], games[4]) → préférer #require ; GameRef.State .unknown, bestOf fallback 1 et statsDisabled==false non testés ; deux init tolérants quasi identiques (ok à 2) ; modèles sans init public (à ajouter pour les aperçus SwiftUI à l'étape 2) ; Builders force-unwrap / zip tronquant
Ruling 4: PlayerLine, GameSnapshot, GamePhase restent non Codable — ce sont des types dérivés, jamais décodés ni persistés ; la contrainte « modèles Codable » vise les réponses de l'API et les états persistés (FollowList, LiveMatchState) — si faux : ajouter Codable plus tard, une ligne par type.
Task 4: complete (commits af0f0da..50b22fe, review clean)
Task 4: minor (deferred): test de firstFrameTime non discriminant (fixture pregame à horodatages identiques) → ajouter un test sur window_ingame (.592 ≠ .593) ; stats(for: blue)/players(for: inconnu)/fallbacks métadonnées non testés ; fallbacks incohérents ("?" vs "") ; types sans init public (aperçus SwiftUI)
Ruling 5: `frames` reste strict (pas de LossyArray) — une fenêtre est un tout cohérent, un changement de schéma doit échouer bruyamment plutôt que produire « pas de stats » silencieusement — si faux : une fenêtre avec une frame illisible est entièrement perdue (l'appli affiche alors le dernier état connu).
Ruling 6: GamePhase inconnu → .inGame est conservé (plan + test) ; la phase « en direct » de la Live Activity se fonde sur l'état des games de l'API (EventDetails), pas seulement sur le flux — si faux : un nouvel état terminal du flux laisserait une game affichée en cours jusqu'à la mise à jour de l'API.
Task 5: complete (commits 50b22fe..feb2bd0, review clean)
Task 5: minor (deferred): force-unwrap des URL avec gameId brut (ids numériques, mais crash possible sur donnée externe) ; pas de propagation d'annulation Task → dataTask (pertinent pour le polling de l'étape 2/4) ; cachePolicy URLSession par défaut (faible confiance) ; trous de tests (200 vide, absence de startingTime, schedule [] , erreur réseau propagée)
Task 6: complete (commits feb2bd0..9abb7bf, review clean)
Task 6: minor (deferred): refresh non testé sur homeLeagueName / conservation spoilerFree+couleurs / équipes non suivies non ajoutées ; branche « logos différents » non exécutée ; ScheduleQuery sans cas liste vide / homeLeagueName nil ; aller-retour JSON sans couleurs ; compatibilité de persistance de FollowedTeam (decodeIfPresent ou version) à décider avant la persistance de l'étape 2
Task 7: complete (commits 9abb7bf..13cfc86, review clean)
Task 7: minor (deferred): tests manquants — deux matchs à venir pour une équipe (.min), égalité de date entre deux équipes suivies (même match), équipe sans prochain match suivie avant une équipe qui en a un ; indexations cards[i] sans #require
Task 8: review — Important (plan-mandated) : vainqueur arbitraire sur égalité / 0-0 / résultat nul (`teams.max { gameWins }`).
Ruling 7: on corrige — nouvelle fonction publique `Presenter.winnerCode(_ teams: [MatchTeam]) -> String?` : l'équipe dont `result.outcome == "win"` s'il y en a une, sinon l'unique équipe au plus grand `gameWins` strictement > 0, sinon nil ; utilisée par `scoreLine` et, en Task 9, par `LiveMatchBuilder` pour `winnerCode` — un mauvais vainqueur affiché avec assurance contredit le spec §6.3 (« Victoire XX ») — si faux : coût nul, la règle est plus stricte que l'ancienne.
Task 8: minor (deferred): tests masqué-terminé sans score==nil/isMasked ; à-venir masqué non testé ; pas de test de révélation négative ; bornes de Format (59/60 min, 47/48 h, 999/1000, 1050, dimanche, 00:05, passage de minuit) ; ScoreLine sans init public ; Presenter.currentGameNumber public non masqué (à rendre interne ou documenter) ; rapport : nombre de tests erroné (cosmétique)
Task 8: fix round 1/5 (1 addressed, 0 open — vainqueur fiable via Presenter.winnerCode; commits 7d1e022..2b091c8)
Task 8: complete (commits 13cfc86..2b091c8, review clean after 1 fix round)
Task 9: note — Side.id retombe sur le code si l'événement n'a pas d'id d'équipe ; en pratique les Live Activities sont créées depuis getLive (ids présents) — à garantir dans l'appli (étape 4) et à figer avant le serveur de push
Task 9: review — Important (plan-mandated) : flux « finished » avant mise à jour des victoires → sur la game décisive, phase betweenGames et gameNumber > bestOf (ex. Bo5 2-2, game 5 → « game 6 »).
Ruling 8: on corrige — si le flux dit la game finie ET qu'une équipe est à une victoire du gain de la série (`wins.max() >= needed - 1`), la phase reste `.inGame` (stats finales de la game, numéro inchangé) jusqu'à ce que l'API tranche ; sinon comportement actuel ; et en `.betweenGames`, `gameNumber` est borné à `bestOf` — on ne peut pas savoir depuis le flux qui a gagné la game, mieux vaut afficher la game qui vient de se finir que la mauvaise série — si faux : pendant ≤ 60 s après une game décisive, la Live Activity montre la game finie comme « en cours » au lieu de « terminé ».
Task 9: minor (deferred): Side.id retombe sur le code (contrat à figer avant le serveur, construire les attributs depuis getLive/EventDetails) ; ordre des équipes attributs (événement) vs état (EventDetails) non réconcilié par id → à vérifier à l'étape 4 ; bestOf par défaut 1 si strategy absente ; garde perTeam.count non testée ; test statsDisabled sans gameClockStart nil / score présent ; pas d'aller-retour JSON ni de valeurs brutes de Phase épinglées (format de Date à documenter pour le serveur) ; chrono décalé par les pauses
Task 9: fix round 1/5 (1 addressed, 0 open — game décisive : reste inGame si la série peut être finie, numéro borné au Bo; commits 084a180..3b29f05)
Task 9: complete (commits 2b091c8..3b29f05, review clean after 1 fix round)
Task 9: minor (deferred): sur une game décisive finie dans le flux, gameClockStart reste renseigné → le chrono continue jusqu'à la mise à jour de l'API (≤ 60 s) ; à traiter côté vue (étape 4) en figeant le chrono si snapshot.phase == .finished
Ruling 9: le commit e4272e4 porte « Co-Authored-By: Claude Haiku 5.5 » (modèle réel de l'implémenteur) au lieu d'Opus — on n'amende pas ; les deux formes sont acceptées, la ligne d'attribution reste présente — si faux : trailers hétérogènes dans l'historique, purement cosmétique.
Task 10: complete (commits 3b29f05..e4272e4, review clean)
Task 10: minor (deferred): ids épinglés en double non dédoublonnés ; garde de dédoublonnage auto non testée (pin d'un match suivi) ; épinglé ET retiré → épinglé gagne (non documenté, l'appli doit garder pinned/dismissed disjoints) ; calcul de rang réimplémente FollowList.involves (lisibilité)
Task 11: review — Important (plan-mandated) : teinte coupée en cases fixes de 10°, une couleur à cheval sur une frontière (surtout le rouge à 0°/360°) perd contre une couleur plus petite mais compacte (repro : 200 px rouges répartis 358°/2° vs 150 px verts → vert).
Ruling 10: on corrige — le score d'une case devient la somme circulaire de ses voisines (i-1, i, i+1 modulo 36) et la couleur rendue est la moyenne RGB sur cette fenêtre de 3 cases ; + test de non-régression (mix ci-dessus → rouge) — la couleur d'équipe est la teinte de toute l'interface (Vitrail), un logo rouge rendu vert est très visible — si faux : coût nul, la surcharge manuelle (§5.2) reste disponible.
Task 11: fix round 1/5 (1 addressed, 0 open — fenêtre circulaire de 3 cases de teinte; commits 9d7fc6c..2de838d)
Task 11: complete (commits e4272e4..2de838d, review clean after 1 fix round)
Task 11: minor (deferred): seuils alpha et noir saturé non testés isolément ; teamColor (chemin positif) non testé ; init?(hex:) accepte un signe +/- ; hue/mix internes (pas private) et variable locale qui masque la méthode ; doc à compléter (alpha prémultiplié ? fenêtre de 3 cases)
Task 12: complete (commits 2de838d..b157ca9, review clean ; branche lolkit poussée ; CI LoLKit run 38402316350 vert, 71 tests)
Task 12: minor (deferred): branche « stats » de `lolkit live` non exercée sur données réelles (aucun match avec stats le 13/10) → relancer pendant les play-ins des Worlds (15/10) ; ligne d'équipe silencieusement omise si id absent ; padding qui tronque ; erreurs sur stdout sans indice « clé changée » ; une erreur sur un match interrompt la liste
Final review (opus, 9cac237..b157ca9) : « With fixes » — 0 Critical, 6 Important. Rulings :
Ruling 11 (I1): attributs construits depuis EventDetails — `attributes(for details: EventDetails, follows:) -> LiveMatchAttributes?` (nil si une équipe n'a pas d'id), plus de repli sur le code ; ajout `primaryTeamIndex: Int?` (équipe suivie en premier, pour §6.1/§6.2) ; test d'ordre attributs = état par id — l'ordre et les ids sont figés par le contrat phase 2 — si faux : signature à rechanger à l'étape 4.
Ruling 12 (I2): contrat épinglé par une fixture dorée (encodage = comparaison, décodage = comparaison), Phase inconnue → .inGame, ajout `gameClockStoppedAt: Date?` (rempli quand le flux est paused/finished en .inGame), Date au format par défaut de JSONEncoder (secondes depuis 2001) documenté dans la spec ; le wrapper iOS sera `extension LiveMatchAttributes: ActivityAttributes { typealias ContentState = LiveMatchState }` (étape 4) — si faux : le serveur devra s'adapter au format choisi.
Ruling 13 (I3): `state(…)` prend `follows` + `revealed` et appelle `SpoilerPolicy.isMasked` lui-même ; `masked()` transforme .betweenGames en .inGame (sinon la longueur de série fuit) ; `Presenter.winnerCode` et `currentGameNumber` deviennent internes ; 3 tests (terminé masqué sans score, révélation ciblée, entre-deux masqué) ; spec §8 amendée — si faux : coût nul.
Ruling 14 (I4): `FollowedTeam` décodage tolérant (decodeIfPresent + valeurs par défaut sauf id/code/name), `FollowList` ignore les entrées illisibles ; tests héritage / entrée cassée / aller-retour avec couleurs / refresh conserve réglages — c'est la seule saisie manuelle de Dan — si faux : coût nul.
Ruling 15 (I5): inits publics memberwise (mêmes libellés et ordre que les propriétés) pour League, Team, LeagueRef, Strategy, GameRef(+Side), StreamInfo, MatchInfo, MatchEvent, EventDetails(+Match), GameSnapshot, PlayerLine, TeamCard, ScoreLine, FollowedTeam ; un test qui construit chacun — nécessaire aux aperçus et placeholders des étapes 2-3.
Ruling 16 (I6): `TeamCards.build(…, live: [MatchEvent]?)` — nil = inconnu (repli calendrier), tableau = fait foi (pas de repli) ; note étape 2 : rafraîchir getSchedule quand un id quitte getLive — si faux : un match fini peut rester « Prochain » jusqu'au rafraîchissement.
Ruling 17 (mineurs inclus dans la vague, peu coûteux) : chrono calculé même si stats désactivées (spec §6.3 « Score + chrono ») ; doc « rgba non prémultiplié » ; test firstFrameTime discriminant (window_ingame .592) ; `<= 2` → `== 2` ; job CI macOS `swift test` dans lolkit.yml + `permissions: contents: read`. Reste différé : .finished sans série gagnée (forfait/Bo2), annulation des requêtes, URL force-unwrap, planner sans `active:` (étape 4), LossyArray break/log.
Final review: fix wave (commits b157ca9..96721b3, 8 commits F1–F8, 98 tests) ; spec amendée (commit suivant) ; branche poussée
Final review: fix wave re-review — F1…F8 ADDRESSED, aucune nouvelle anomalie bloquante ; CI run 38405524163 vert (Linux + macOS, 98 tests). Mineurs restants : gameClockStoppedAt sans gameClockStart possible (la vue doit l'ignorer) ; init LiveMatchAttributes sans défaut pour primaryTeamIndex ; FollowList jette si la clé `teams` manque ; types LiveWindow sans init public (non requis).
Plan complete: prêt à fusionner dans main.
