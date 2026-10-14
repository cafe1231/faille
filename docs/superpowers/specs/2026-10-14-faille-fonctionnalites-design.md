# Faille — lot « fonctionnalités » : conception

Date : 14/10/2026. Validé par Dan (« fais les 5 », puis « ajoute des icônes pour les spells, les items, les champions », puis les sorts d'invocateur des games terminées). À exécuter **après** le lot « Finitions » (`2026-10-14-faille-finitions-design.md`), dont il réutilise le vocabulaire de mouvement (`Motion`), `PressableStyle` et les retours haptiques. Spec de référence : `2026-10-13-faille-design.md` (anti-spoiler §8 et DA §9 contraignants). Notes de recherche : `docs/superpowers/notes/2026-10-14-idees.md`.

## Principes
- Toute logique pure (choix du stream, sélection des notifications, rapprochements, fil des événements, séries de gold, version Data Dragon, normalisation des noms) va dans **LoLKit**, testée par fixtures réelles (Docker). L'appli ne fait qu'afficher.
- **Anti-spoiler d'abord** : un match masqué n'affiche ni stream « en direct » avec score, ni VOD (le nombre de games trahit la série), ni draft, ni objets, ni fil, ni courbe, ni sorts d'invocateur, ni notification qui trahirait un résultat ; tout cela n'apparaît qu'une fois le match révélé. Les notifications suivent `Presenter.nextLine` (F1 + règle C).
- **Sobriété réseau** : images en cache disque (comme les logos), aucune requête pour un match masqué, `details` (lourd) à 60 s au plus et seulement Détail ouvert.
- Sources externes : l'API lolesports et le flux livestats (déjà utilisés), **Data Dragon** (`ddragon.leagueoflegends.com`, images officielles de Riot, sans clé), **Leaguepedia** (`lol.fandom.com/api.php`, API Cargo, sans clé, User-Agent identifiable « Faille (usage personnel) »). Aucune clé secrète.

## 1. « Regarder » et « Revoir »
- **En direct** : `getLive` → `streams[]` (`provider` twitch / youtube / afreecatv…, `parameter`, `locale`). Choix (LoLKit `StreamPicker`) : `fr-FR`, sinon `en-US`, sinon le premier ; liens : Twitch `https://www.twitch.tv/<parameter>`, YouTube `https://www.youtube.com/watch?v=<parameter>`, AfreecaTV `https://play.afreecatv.com/<parameter>` ; autre fournisseur → ignoré. Bouton « Regarder » (icône) sur la carte en direct et dans le Détail ; appui long → menu des autres streams (langue + plateforme). Ouverture par `openURL` (l'app Twitch / YouTube prend le relais si installée).
- **Terminé** : `getEventDetails` → `games[].vods[]` (YouTube `parameter`, `locale`, `startMillis`) → « Revoir la game N » dans le Détail (même préférence de langue ; lien avec `&t=<startMillis/1000>s` si > 0). Masqué → absent.

## 2. Notifications de début de match
- Notifications **locales** (`UNUserNotificationCenter`), programmées depuis le calendrier en cache à chaque rafraîchissement du calendrier, des équipes suivies ou des réglages ; aucune n'est envoyée par un serveur.
- Réglage « Notifications de début de match » (désactivé par défaut ; l'activer demande l'autorisation iOS) et délai (5, 15 ou 30 min, défaut 15).
- Sélection (LoLKit `MatchReminders.plan(schedule:follows:revealed:now:lead:)`) : matchs `unstarted` d'une équipe suivie, début dans le futur, **seulement si `Presenter.nextLine` les montre** (`.match`) pour au moins une équipe suivie concernée — jamais un prochain match caché par F1 / règle C ; 60 au plus (limite iOS 64), les plus proches d'abord ; identifiant stable par match (re-programmer remplace).
- Texte : « KC vs C9 dans 15 min » / sous-titre « Mondial · Play-in · Bo5 » ; jamais de score ni de résultat. Toucher la notification ouvre le Détail du match.

## 3. Draft et builds (icônes)
- **Version Data Dragon** (LoLKit `DataDragon.version(forPatch:versions:)`) : `api/versions.json`, la plus récente qui commence par `major.minor` de `gameMetadata.patchVersion` (ex. « 16.18.819.1060 » → « 16.18.1 »), sinon la plus récente. Mise en cache 24 h.
- **Champions** (pas de requête de plus : `window.gameMetadata.*.participantMetadata[].championId`) → `cdn/<v>/img/champion/<championId>.png`.
- **Objets, runes, sorts du champion** : `livestats/v1/details/{gameId}?startingTime=<même règle que window : recul ≥ 80 s, paliers>` → `participants[]` : `items` (ids) → `cdn/<v>/img/item/<id>.png` (noms : `data/fr_FR/item.json`) ; `perkMetadata` (`styleId`, `subStyleId`, `perks`) → rune principale (`perks[0]`) + arbre secondaire, icônes de `data/fr_FR/runesReforged.json` (`https://ddragon.leagueoflegends.com/cdn/img/<icon>`) ; `abilities` (ordre de montée Q/W/E/R) → icônes `data/fr_FR/champion/<id>.json` → `spells[].image.full` (`cdn/<v>/img/spell/<file>`) + `passive`. Bonus affichés : part des dégâts (barre), participation aux kills, balises posées / détruites.
- **Sorts d'invocateur** (absents du flux Riot) : **games terminées seulement**, par Leaguepedia `ScoreboardPlayers` (`Champion`, `SummonerSpells`, `Link`, `DateTime_UTC`) ; rapprochement (LoLKit) par **ensemble des champions de la game** + date (± 3 h autour du début de la game) ; noms → images `data/fr_FR/summoner.json` (`SummonerFlash`, …). Une requête par game au plus, cache disque ; rien si le wiki n'a pas encore la game.
- Fréquence : `details` toutes les 60 s Détail ouvert sur une game en cours, une fois pour une game terminée. Données JSON en cache disque ; images en cache disque (dossier `ddragon/<v>/…`), décodées hors du `body`.
- Écran : section « Joueurs » du Détail : ligne par joueur = icône du champion (+ niveau), pseudo, KDA, CS, gold, rangée d'objets (6 + balise), rune principale + arbre secondaire ; appui → fiche joueur (ordre des sorts, part des dégâts, stats, sorts d'invocateur si game terminée). Draft (les 5 champions de chaque équipe) en haut du Détail.

## 4. Fil des événements de la game
- LoLKit `GameTimeline.events(from: [GameSnapshot], firstFrameTime:)` : différences entre frames successives → kills (par équipe, avec joueurs quand déductible), drakes (type), barons, hérauts si présents, tours, inhibiteurs ; horodatés au temps de jeu (« 18:42 »). Pas d'événement inventé : un écart non attribuable devient « +2 kills ».
- En direct : chaque frame lue (10 s) alimente le fil ; game terminée ou ouverture tardive : relecture du flux à pas de 60 s à la demande (≈ 35 requêtes), mise en cache disque.
- Affichage dans le Détail : liste chronologique inversée, icônes de la DA (épées, drake, baron, tour, inhib), couleur de l'équipe.

## 5. Courbe de l'écart de gold
- LoLKit `GoldSeries.points(from: [GameSnapshot], firstFrameTime:)` → (temps de jeu, écart bleu − rouge réorienté vers l'équipe suivie) ; mêmes frames que le fil.
- Swift Charts (`Chart` + `AreaMark` / `LineMark`), couleur de l'équipe en tête au-dessus de zéro, l'autre en dessous ; repères des barons / drakes du fil. En direct : se prolonge à chaque frame.

## Vérification
- LoLKit : tests sur fixtures réelles (window, details, versions.json réduit, runesReforged / item / summoner réduits, réponse Leaguepedia réelle, getLive avec streams, getEventDetails avec vods).
- Appli : aperçus PNG du Détail enrichi (en direct, terminé, masqué), de la carte avec « Regarder », des réglages de notifications ; tests hébergés (anti-spoiler : rien de tout cela pour un match masqué ; notifications : sélection et texte).
- Checklist iPhone « Fonctionnalités » ajoutée à `docs/superpowers/notes/2026-10-14-checklist-iphone.md`.

## Hors périmètre
Sorts d'invocateur en direct (aucune source), notifications de résultat (phase 2, serveur de push), statistiques historiques de joueurs, classement / tableau des Worlds (idée suivante).
