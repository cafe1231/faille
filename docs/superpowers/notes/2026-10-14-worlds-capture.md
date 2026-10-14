# Worlds — capture du flux en direct (nuit du 13 au 14/10/2026)

## `lolkit live`
`bash scripts/lolkit.sh run lolkit live` lancé le 14/10 à 02:22 UTC → « Aucun match en direct. » (`getLive` vide). Le premier match des Worlds est le 15/10 à 18:00 UTC (C9 vs KC, play-ins), suivi de FUR vs MVK à 23:00 UTC.

## Frame en pause : capturée sur une partie déjà jouée
Le flux `window` sert aussi les parties terminées (`startingTime` pendant la partie). Balayage minute par minute de 10 games récentes (finales LEC et LCK, demi-finale LEC) : une seule pause trouvée.
- KC vs MKOI, LEC play-offs, game 1 (19/09/2026, game `115548681803406328`) : fenêtre `startingTime=2026-09-19T15:15:50Z` → 9 frames `in_game` puis une frame `paused` (15:15:02.993Z, pause en tout début de partie, 2 500 gold par équipe).
- Fixture : `LoLKit/Tests/LoLKitTests/Fixtures/window_paused.json` (réponse brute de l'API).
- Tests : `LiveWindowTests.pausedFrameFromTheFeed` (décodage, phase `.paused`, ids d'équipe, 5 joueurs par côté) et `LiveContractTests.aRealPausedFrameStopsTheClock` (`LiveMatchBuilder.state` : en jeu, game 1, chrono arrêté, stats présentes). LoLKit : 253 tests verts.

## Le vrai direct des Worlds
Une tâche planifiée unique, « Faille — capture du direct des Worlds (C9 vs KC) », est programmée pour le 15/10 à 20:20 (heure de Paris) dans l'appli Claude (section « Scheduled »). Elle relance `lolkit live`, enregistre une fenêtre réelle en direct (`window_live_worlds.json`, plus `window_live_paused.json` si une pause arrive), ajoute les tests, pousse et écrit `2026-10-15-capture-worlds.md`. Elle ne tourne que si l'appli Claude est ouverte (sinon, au prochain lancement) ; tu peux la supprimer dans la barre latérale.

## Matin du 14/10 : vrai match en direct, et un bug trouvé
- 11:41 (Paris) : KT vs BFX (Demacia Cup, Bo5, game 1) en direct avec stats. `bash scripts/lolkit.sh run lolkit live` répondait **« Erreur : http(status: 400) »**.
- Cause : le flux refuse une fenêtre « en avance sur la diffusion » (`BAD_QUERY_PARAMETER`, « disallowed window with end time less than 80 sec old … ahead of broadcast »). Mesuré avec l'heure du serveur : une fin de fenêtre de moins d'environ 62 s est refusée ; l'appli demandait `maintenant − 60 s` (fin de fenêtre à 50-60 s). **Les stats en direct ne se seraient jamais chargées dans l'appli ni dans la Live Activity.** Les fixtures du 04/10 avaient été capturées sur un match dont le seuil était plus bas : le seuil dépend du match.
- Correctif (commit `e3953e6`) : `LoLClient.liveWindow(gameId:now:)` essaie 90 s, puis 120, 180, 300 et 600 s, et retient par game le premier délai accepté ; l'appli et la CLI l'utilisent ; 3 tests (recul, abandon après 600 s, pas de nouvel essai sur un autre code d'erreur) ; spec §4.1 amendée. Après correction, `lolkit live` affiche : « KT 8 kills · 54,3k gold · 3 tours · 0 inhibs · 0 barons · drakes [mountain] / BFX 19 kills · 64,7k gold · 8 tours · 2 inhibs · 1 barons · drakes [hextech, cloud, cloud, cloud] ».
- Capture : 4 fenêtres réelles de 09:41 à 09:44 UTC (fin de la game 1, pas de pause pendant la capture). Fixture `window_live.json` + tests `liveWindowFromTheFeed` et `aRealLiveFrameGivesEachTeamItsOwnStats` (BFX côté bleu alors que l'API liste KT en premier : stats rattachées par id). LoLKit : 258 tests.
- La tâche planifiée de jeudi 20:20 a été corrigée (heure du serveur, `startingTime` avec recul) pour capturer en plus une fenêtre des Worlds.
