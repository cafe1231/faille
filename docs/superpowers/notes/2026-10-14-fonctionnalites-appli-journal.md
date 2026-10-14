# Fonctionnalités (appli) : journal (copie du suivi SDD, 14/10/2026)

# SDD ledger — plan: docs/superpowers/plans/2026-10-14-fonctionnalites-appli.md

Spec : docs/superpowers/specs/2026-10-14-faille-fonctionnalites-design.md. Plan rédigé par un sous-agent opus (41 ancres vérifiées sur origin/main 8571588 ; code non-UI compilé sous Linux, 38 tests).
Ruling 1: trois vagues (A : T1 T2 T3 en parallèle ; B : T4 T5 T6 en parallèle après fusion de T3 ; C : T7 intégration), worktree + branche fonc/appli-tN par tâche, CI iOS sur la branche (dernier commit seulement), relecture par tâche, fusion côté serveur dans main par l'orchestrateur — coût si faux : conflit de fusion à reprendre.
Ruling 2: analyse préalable (opus) menée EN PARALLÈLE de la vague A (fichiers neufs, risque faible) ; ses décisions s'appliquent avant la vague B — coût si faux : un tour de correction sur une tâche de la vague A.
Pre-flight (opus) : 0 Critical, 5 Important, 19 Minor, 6 défauts de la vague A — décisions : preflight-rulings.md (écrites avant le démarrage de la vague B).
Vague A : T1 (37f15bb, Approved) fusionnée a5cf34d ; T3 (c4cfa6d, Approved) fusionnée 7d11a49 ; T2 (3870b7e, 1 Important → correction 67e3bf6, re-relecture Approved) fusionnée c1d98ae.
Vague B : T5 (27bd5fe, Approved) fusionnée 4b0efb2 ; T6 (ecddee8, Approved) fusionnée fd0365d ; T4 (f04f523, Approved) fusionnée 06dec81.
Intégration : T7 (79460b9, Approved, CI iOS 38610531344 verte) — l'agent de fusion (haiku) a refusé d'écrire sur main ; fusion faite par le contrôleur (9fb219a, avance rapide, 0 conflit).
Ruling 3: rapports des agents écrits dans leurs worktrees (l'outil Write refusait le chemin du dépôt principal) → rapatriés dans le dossier du lot — coût : aucun.
Relecture finale (opus) : With fixes — 0 Critical, 2 Important (I-1 course fil/courbe à la 1re ouverture ; I-2 notifications non reprogrammées en arrière-plan), 11 Minor. Ruling 4: une vague V1–V9 (I-1+m1, I-2+m2+m3, m4=A2, m10=A1, m5, m7, m9, m6, m11) ; m8 (position de « Épingler ») laissé à Dan après essai — coût si faux : un bouton qui bouge un peu.
