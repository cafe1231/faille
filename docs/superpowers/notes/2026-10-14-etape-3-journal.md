# Étape 3 — Les widgets : journal (copie du suivi SDD, clôturé le 14/10/2026)

Plan : docs/superpowers/plans/2026-10-14-etape-3-widgets.md. Spec : docs/superpowers/specs/2026-10-13-faille-design.md (§7, §8 amendés). Décisions détaillées par tâche : analyse préalable (opus) et vague finale W1–W9.


Spec : docs/superpowers/specs/2026-10-13-faille-design.md. Plan rédigé par un sous-agent opus (13-14/10).
Ruling 1: exécution sur main (workflow iOS déclenché sur main ; autorisation de Dan).

## Pre-flight scan (délégué à un relecteur opus ; rapport : preflight.md — T1–T3 exécutés tels quels dans une copie : 178/178 ; noms et interfaces concordent)
1 Critical, 3 Important, 13 Minor. Décisions par tâche : preflight-rulings.md.
Ruling 2 (C1): règle du prochain match, variante C (cacher un prochain match masqué par une AUTRE équipe suivie en anti-spoiler), plutôt que la lecture littérale A qui cachait à jamais les prochains matchs de l'équipe anti-spoiler elle-même (et cassait 5 tests) — si faux : il resterait des cas où l'on voit moins que voulu.
Ruling 3 (I1): fuite résiduelle par inférence acceptée pour l'instant, consignée dans la spec §8 et signalée à Dan (variante stricte = sa décision) — coût : un fan attentif peut déduire un résultat.
Ruling 4 (I2, I3, M1, M2, M3, M5, M13) : appliqués dans les tâches concernées ; M4, M6–M12 acceptés/différés.
Task 1: complete (commits 1e1002c..01f977a, review clean, CI LoLKit 38466504280 + iOS 38466504157 verts, 157 tests LoLKit, 64 hébergés)
Task 1: minor (deferred → T4) : deux commentaires de doc obsolètes après R-C1 (AppStore.swift ~140, TeamCardView.swift ~87)
Ruling 5: relecture de T2 et implémentation de T3 en parallèle (T3 ne touche que de nouveaux fichiers de textes LoLKit) — gagne ~15 min sur la nuit — si faux : T3 s'adapte à un éventuel changement d'interface demandé par la relecture de T2.
Task 2: complete (commits 4bb5b56..c53d4a7, review clean, CI LoLKit 38468199797 vert, 173 tests ; dates et entrées recalculées à la main par le relecteur)
Task 2: minor (deferred → vague finale de l'étape 3) : test du filtre `> now` de reloadDate (début passé) ; test de l'entrée « fin de confiance du calendrier » ; cas réels (calendrier unstarted vs live inProgress, deux équipes suivies dans un même match en direct, ligne masquée absente) ; doc « comme dans l'appli » à corriger ; nombres magiques 48/12 à dériver des constantes
Task 3: complete (commits 9cc4450..3bf428f, review clean, CI LoLKit 38469461798 vert, 181 tests ; chaînes recalculées par le relecteur)
Task 3: minor (deferred → vague finale) : Format.day/matchDate dupliqués ; libellés vides répétés (faire réutiliser emptyMessage) ; docs de rectangular/small/Circular.empty à mettre à jour (R-I2, règle C) ; durcir title(_:) sur !isMasked + test score non nul masqué
Task 4: review — Important : R-M5 incomplet pour le live (le test `Task.isCancelled` précède l'affectation de liveFetched → rechargement perdu si annulation juste après un live réussi).
Ruling 6: on corrige (échanger les deux lignes dans AppStore.cycle + test si faisable), mais APRÈS la fin de T5 (même copie de travail : deux agents qui commitent/poussent en même temps sur main se gêneraient) — coût : quelques minutes de décalage.
Task 4: minor (deferred) : rechargement des widgets après refreshLiveStats/updateTeamColors (quelques secondes de retard, accepté) ; trous de tests (origine du rechargement, cycle inactif, saveFollows) ; « une fois par cycle » approximatif
Task 5: complete (commits 837d156..9c401e9, review clean, CI 38471655896 vert, planches 09/10 réelles ; aucune API de repli : ImageRenderer et Label OK)
Task 5: Important (plan-mandated, tests/preuves) → vague finale de l'étape 3 : (1) garde des planches non discriminante (le fond seul pèse ~2 Mo) → vérifier le contenu (inkRatio de la couche contenu) ; (2) maximum de 4 lignes du widget moyen jamais rendu → échantillon à 4 lignes rendu à la taille 6,3" (338×158) et ajustement si débordement.
Task 5: minor → vague finale : fuseau Paris dans les planches via @Environment(\.timeZone) (pas de NSTimeZone.default) ; widget moyen : ligne « T1 · Prochain · masqué » quand d'autres lignes existent ; minor différés : inkRatio faible, duplications de test, monogrammes lus par VoiceOver, InlineIcon silencieux
Task 4: fix round 1/5 (1 addressed, 0 open — liveFetched affecté avant le test d'annulation + test rouge puis vert ; commits 9c401e9..6ebf5c6)
Task 4: complete (commits 3bf428f..6ebf5c6, review clean after 1 fix round, CI 38473208323 vert, 74 tests hébergés)
Task 6: complete (commits 6ebf5c6..86a2b7e, review clean, CI 38474304545 vert, extension en Swift 6 sans repli, Metadata.appintents généré)
Task 6: minor (deferred) : imports inutiles (AppIntents, LoLKit) ; contrôle du contenu de Metadata.appintents faible
Task 7: manuelle (Dan) — checklist complétée par R-I3/R-M13, à livrer au réveil.

## Relecture finale (opus, 1e1002c..86a2b7e) : « With fixes » — 4 Important, 9 Minor
Ruling 7 (I1): match en retard — ne présumer « commencé » que s'il n'y a plus ni live ni calendrier fiables (W1) — pourquoi : les Worlds prennent souvent du retard, le match disparaissait des widgets alors que l'appli le montrait — coût si faux : quelques minutes de « maintenant » de trop sur un widget.
Ruling 8 (I2, I3): widget moyen — 4 lignes qui tiennent dans 158 pt, lignes « CODE · Prochain · masqué » après les lignes datées, dans l'ordre de suivi (W2) — coût si faux : une ligne coupée sur un iPhone plus petit.
Ruling 9 (I4): garde des planches discriminante par inkRatio sur fond transparent (W3) — coût si faux : une planche vide passerait inaperçue.
Ruling 10 (M5): fuseau Paris par l'environnement SwiftUI dans les planches (W4).
Ruling 11 (règle C, propriétaire) : affinage symétrique — « X vs Y » ne se cache que si le dernier match de Y est masqué et non révélé (même définition que F1) (W5) — pourquoi : sans dernier match masqué de Y, l'affiche ne trahit aucun résultat caché ; la règle stricte cachait trop — coût si faux : Dan voit un prochain match qu'il aurait préféré cacher ; signalé au réveil.
Ruling 12 (M8): masquage vérifié dans les aides de texte (W6). Ruling 13 (M9, T2/T3 minors): docs, constantes dérivées, tests manquants, imports (W7).
Ruling 14 (M10, M11): « maintenant » remplacé par l'icône en direct sur le rond ; message distinct si le groupe d'apps est introuvable (W8).
Ruling 15 (M6, budget): rechargement auto `.after(now + horizon − 1 h)` au lieu de 30 min — les entrées couvrent 6 h et chaque début de match, l'appli recharge à chaque écriture ; spec §7 amendée — coût si faux : un widget peut rester sur un calendrier vieux de 5 h si l'appli n'est pas ouverte (dates et comptes à rebours restent justes, seul un changement de calendrier serait manqué).
Différés (notés) : Format.day dupliqué, libellés vides, trous de tests T4 (étape 4 T3), doublons de tests T5, VoiceOver des monogrammes, InlineIcon silencieux, M7, M12 (mode teinté : checklist T7).
Vague finale : brief final-fix-brief.md (W1–W9), un seul sous-agent (sonnet).
Vague finale : complete (commits 86a2b7e..5c8a296 + spec 2c6f707 ; relecture ciblée : W1–W9 ADDRESSED, aucune régression ; CI LoLKit 38479473818 + iOS 38479473851 verts ; 209 tests LoLKit, 80 hébergés ; PNG 09, 10, 11-widgets-moyen).
Ruling 16: écarts acceptés de la vague — 48 dérivé de Format.countdownHoursLimit ; reloadDate(now:) ; « 0 min » sur le rond (un match en retard n'est pas connu en direct) ; ligne masquée code + « Prochain · masqué » ; planche 11-widgets-moyen ; commits groupés par couche — coût si faux : cosmétique.
Résiduels (bas, parqués) : états « groupe d'apps introuvable » sans PNG (contrôle d'encre seulement) ; message long tronqué sur le widget en ligne ; garde d'encre qui ne vérifie pas chaque texte ; AppStore.nextLine recalcule les cartes à chaque rendu (négligeable).
Étape 3 : TERMINÉE côté code. Task 7 (vérification sur l'iPhone) : checklist livrée à Dan au réveil.
