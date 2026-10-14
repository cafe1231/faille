# Fonctionnalités (LoLKit) : journal (copie du suivi SDD, 14/10/2026)


Spec : docs/superpowers/specs/2026-10-14-faille-fonctionnalites-design.md. Plan rédigé par un sous-agent opus qui a exécuté les 6 tâches dans une copie (299 tests, 0 avertissement).
Ruling 1: pas d'analyse préalable séparée — le rédacteur a exécuté chaque tâche seule et les 6 ensemble dans une copie de HEAD (anciennes ancres vérifiées par exécution) — coût si faux : un défaut d'interface attrapé à la relecture.
Ruling 2: exécution en parallèle par l'orchestrateur (Workflow), une worktree et une branche fonc/lolkit-tN par tâche, relecture par tâche, fusion côté serveur dans main par le contrôleur (fichiers disjoints, matrice du plan) — coût si faux : un conflit de fusion à résoudre à la main.
Ruling 3: Leaguepedia limite fortement les requêtes anonymes (~1 accepté / 10 min observé) — le plan appli devra mettre en cache et ne jamais réessayer en boucle.
Orchestration lancée (Workflow wf_73826200-965) : T1–T6 en parallèle, worktree + branche fonc/lolkit-tN chacune, relecture sonnet, un tour de correction + re-relecture si besoin. Fusion côté serveur par le contrôleur ensuite.
Ruling 4 (Dan, option A) : Leaguepedia gardé avec règle stricte (SpellLookupPolicy : 3 essais, 30 min après un refus, 10 min d'écart, jamais après un succès) ; plus aucune requête au wiki pendant le développement ; fixture reconstruite à partir de valeurs réelles connues (task-5-addendum.md) — coût si faux : test moins proche d'une vraie réponse complète. Workflow LoLKit arrêté (T5 bloqué par le wiki) ; T1-T4, T6 validés.
Task 5: implémentée hors réseau (9ecbfc4, 278 tests, CI 38570005293 verte ; fixture reconstruite, SpellLookupPolicy) — relecture lancée.
Task 5: complete (9ecbfc4, review Approved, CI 38570005293 verte, 278 tests). Minors → plan appli : (1) état de politique illisible = réessai immédiat possible (borné à 3) ; (2) rappel anti-spoiler à ajouter aux docs de summonerSpells/match ; (3) « game pas encore sur le wiki » compte comme un essai : l'appli fait son 1er essai ≥ 30 min après la fin de la game et espace les suivants d'au moins 1 h ; (4) total attendu après fusion des 6 : 311 tests / 36 suites.
LoLKit fonctionnalités : 6/6 tâches validées (T1 6c252a8, T2 44fc2e7, T3 5559bcf, T4 2a100e5, T5 9ecbfc4, T6 b3f29e3 après correction) — fusion dans main après la fin des finitions.
Fusion dans main (côté serveur, 27be0e5..3c41ba2) des 6 branches ; CI LoLKit 38585955249 verte sur main : 316 tests / 36 suites (Linux + macOS).
