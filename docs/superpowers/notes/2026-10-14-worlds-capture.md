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
