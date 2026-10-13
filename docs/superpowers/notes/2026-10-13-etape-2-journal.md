# Étape 2 (la vraie appli) — journal d'exécution, décisions et points différés

Copie du journal de suivi au 13/10/2026. Décisions prises pendant l'exécution (« Ruling ») et remarques différées, à reprendre dans les étapes 3 et 4.


Spec : docs/superpowers/specs/2026-10-13-faille-design.md. Plan rédigé par un sous-agent opus (13/10), commité 2026-10-13.
Ruling 1: exécution directement sur `main` (pas de worktree) — le workflow iOS ne se déclenche que sur main, projet perso mono-développeur, push autorisé par Dan — si faux : main peut être temporairement cassé entre deux tâches.

## Pre-flight scan (délégué à un relecteur opus, rapport : preflight.md — tables croisées tâche/tâche et par tâche, API LoLKit vérifiées, valeurs de tests recalculées : tout concorde)
0 Critical, 3 Important, 17 Minor. Décisions détaillées par tâche : preflight-rulings.md.
Ruling 2: pre-flight délégué (plan de 5 400 lignes) plutôt que lu par le contrôleur — préserve le contexte de coordination — si faux : une incohérence non vue sera attrapée par les relectures de tâche.
Ruling 3 (I1): captures PNG — attente de la fenêtre (5 s), erreur si drawHierarchy échoue, PNG > 10 Ko — sinon des aperçus blancs passeraient — coût nul.
Ruling 4 (I2): chrono des matchs à stats désactivées — on interroge quand même le flux pour les games en cours (T7, T11) — spec §4.3/§6.3 — si faux : quelques requêtes 404 de plus, arrêtées après la première.
Ruling 5 (I3): rechargement du widget sonde à chaque sauvegarde des équipes suivies (T7) — sinon le test T12 n°14 serait faussement KO — coût nul.
Ruling 6 (mineurs) : M1, M2, M3, M5, M6 (reformulation), M7, M8, M9, M10, M12, M15 appliqués (voir preflight-rulings.md) ; M4, M11, M13, M14, M16, M17 acceptés/différés — si faux : petits correctifs ultérieurs.
Task 1: review — Important (plan-mandated) : si le dernier succès en cache est daté dans le futur, une tentative ratée n'est plus vue comme ratée → réessai toutes les 10 s au lieu de 60 s.
Ruling 7: on corrige — `failed = success.map { attempt > $0 || $0 > now } ?? true` + test (lastSuccess = now+3600, lastAttempt = ago(30) → rien n'est dû) — une ligne, contrat §10 — coût nul.
Ruling 8 (pour T7, issu des mineurs de T1) : la boucle de rafraîchissement date `lastSuccess` avec l'heure de DÉBUT de la tentative (sinon le live passe à ~70 s) ; un tirer-pour-rafraîchir explicite efface `lastAttempt` du type concerné avant d'appeler la politique (sinon il ne fait rien pendant 60 s après un échec).
Task 1: minor (deferred): tolérance d'horloge différente entre due (60 s) et usableLive (0) ; chemins §10 non testés (jamais réussi + tentative, ligues vides, bornes exactes) ; unreadableCacheThrows accepte n'importe quelle erreur ; désabonnement → getSchedule superflu (!= au lieu de superset)
Task 1: fix round 1/5 (1 addressed, 0 open — futur daté ⇒ échec ; commits d40c758..9af1008)
Task 1: complete (commits 8f05886..9af1008, review clean after 1 fix round, CI vert Linux+macOS, 112 tests)
Task 2: complete (commits 9af1008..57a760b, review clean, CI vert, 121 tests — le brief disait 120, erreur d'addition du plan)
Task 2: minor (deferred): branche de remplissage de zéros de hex non testée ; unpremultiplied sans test de pixel partiel ; ImageURL sensible à la casse / espaces ; revealedMatchIds rejeté en bloc si un élément est mal typé
Ruling 9: le nom de fichier d'un logo se calcule TOUJOURS sur la chaîne brute renvoyée par l'API (`team.image`), et `ImageURL.secure` ne sert qu'au téléchargement — sinon deux noms pour un même logo — ajouté aux décisions de T7.
Task 3: review — Approved, 1 Important (plan-mandated, test) : l'annulation « en vol » n'est testée que par hasard (la tâche est annulée avant de démarrer).
Ruling 10: on durcit le test (signal « démarré » dans PendingCall, attente avant cancel) — chemin réel du polling — coût : un aller-retour court.
Ruling 11 (pour T7) : une requête annulée remonte en `URLError(.cancelled)` (réseau réel) ou `CancellationError` (tests) : le store traite les deux, et `Task.isCancelled`, comme « pas un échec » (ni tentative ratée, ni bannière).
Task 3: minor (deferred): closure d'annulation non @Sendable ; exactement-une-fois reposant sur le contrat de l'appelant
Task 3: fix round 1/5 (1 addressed, 0 open — annulation en vol déterministe ; commits 9101ab5..54d6634)
Task 3: complete (commits 57a760b..54d6634, review clean after 1 fix round, CI vert, 128 tests). Note : file d'attente des runners macOS jusqu'à 15 min observée.
Task 4: complete (commits 54d6634..b3c3f04, review clean, CI vert, 137 tests)
Task 4: minor (deferred): currentGame / Format.score sans avertissement anti-spoiler dans la doc (T10/T11 doivent passer par ScoreLine/LiveMatchState) ; duplications (statsDisabled, currentGame, time/twoDigits) ; noms de champions (LeBlanc, MonkeyKing→Wukong, KSante→K'Sante) et « Dragon ancestral » à vérifier ; Format.clock sur NaN, limit négatif ; trous de tests (TBD, archivées, limite, displayOrder par nom, init(event:) masqué, 3600 s)
Task 5: complete (commits b3c3f04..42dd510, review clean, CI iOS 38424965017 vert du premier coup, aucune API de repli)
Task 5: minor (deferred): course entre deux chargements d'un même fichier corrompu → protection inutile ; doc de FileStore trop affirmative (cas E/S illisible, couvert par R-T5) ; R-M2 sans tests commités → ajoutés en T7 (R-T5b) ; try? createDirectory non journalisé ; actions CI sur tags
Task 6: complete (commits 42dd510..805ce9d, review clean, CI 38429015865 vert, 2 PNG réels ; aucune API de repli : glassEffect / Glass.regular.tint / Font(CTFont) OK ; éviter UIWindowScene.coordinateSpace (déprécié iOS 26))
Task 6: minor (deferred → R-T6 pour T7) : seuil 10 Ko trop faible (le dégradé seul pèse ~54 Ko) ; job apercus sans timeout ; icônes décoratives lues par VoiceOver ; TeamBadge décode l'image dans body ; RGB(color:) ignore l'échec de getRed ; commentaire icones.sh ; chaînes d'exemple du DASampler
Task 7: review (opus) — Important (plan-mandated, aggravé par R-T1b) : refreshNow / cycle d'ouverture ignorés si un cycle tourne déjà (garde isRefreshing avant l'application de `forcing`).
Ruling 12: on corrige — refreshNow attend le cycle en cours puis lance son cycle forcé (ou un ensemble `pendingForcing` appliqué par le cycle en cours), idem pour le cycle d'ouverture ; test avec transport lent. Mineurs inclus car peu coûteux : boucle d'attente de test bornée (#6), le pull efface aussi lastAttempt des types jamais réussis (#7), refreshLiveStats sauté si le live vient d'échouer dans ce cycle (#8), un logo en échec n'arrête plus les suivants (passer à l'équipe suivante, nouvel essai au prochain rafraîchissement des équipes) (#4). Différés : Tasks non structurées hors scène (#2), drapeau followsUnreadable effacé avant relecture (#3), test logo « non re-téléchargé » qui passe pour une autre raison (#5), exists dans FileStore (#9).
Task 7: fix round 1/5 (5 addressed, 0 open — plus aucune demande de rafraîchissement perdue, attente bornée, pull hors-ligne, stats après live réussi, logos en échec non bloquants ; commits 100ee7d..a8a0ecb)
Task 7: complete (commits 805ce9d..a8a0ecb, review clean after 1 fix round, CI vert, 30 tests hébergés)
Task 7: minor (deferred): passe des logos dans la fenêtre isRefreshing (un hôte de logos lent peut retenir le cycle N×15 s) → sortir la passe logos du cycle gardé à l'étape 3 ; pas d'assertion directe de non-chevauchement ; Tasks non structurées (toggleFollow/setSpoilerFree/reveal) survivent à la scène ; drapeau followsUnreadable ; test logo « non re-téléchargé »
Task 8: complete (commits a8a0ecb..a6ba9ce, review clean, CI 38437468710 vert, 07-reglages.png réel)
Task 8: minor → R-T8 pour T9 (Binding dérivé au lieu de @State+onAppear/onChange ; test de persistance du mode) ; AboutView non capturé
Task 9: complete (commits a6ba9ce..f94150c, review clean, CI 38439027321 vert, 35 tests, 03-equipes.png réel ; R-T8 appliqué)
Task 9: minor (deferred → passe finale) : pilules coupées à la marge (.scrollClipDisabled()) ; « écho » du verre en haut des cartes (GlassCard partagé — à juger sur l'iPhone en T12, repli .ultraThinMaterial) ; « Valider » sans changement fige la couleur ; petites cibles tactiles (bouton effacer 16 pt, œil/étoile 36 pt)
Task 10: complete (commits f94150c..e1b5220, review clean, CI 38442041184 vert, 41 tests ; anti-spoiler vérifié en profondeur)
Task 10: minor (deferred → passe finale) : reorder / lastRowText (logique pure) dans l'app au lieu de LoLKit ; tests de lastRowText reconstruisent les arguments ; libellés masqués (« masqué » vs « Terminé », « Bientôt » vs « À venir ») ; score décentré si codes de largeurs différentes
Task 11: review — Important (plan-mandated) : détails en cache jamais rechargés à l'ouverture si le match n'est plus en cours (score/état périmés après la fin du match).
Ruling 13: on corrige — recharger les détails à l'ouverture (`details == nil || cycle == 0 || (inProgress && cycle % n == 0)`), n dérivé de RefreshPolicy (60 s / 10 s), + test (détails « entre deux games » en cache, événement devenu terminé → rechargement) ; mineur peu coûteux inclus : la puce d'en-tête ne se tronque pas/ne passe pas à la ligne (lineLimit(1) + fixedSize ou méta sur sa propre ligne).
Task 11: minor (deferred) : anti-spoiler de la vue sans test comportemental (seriesScore privé) ; chargements doublés à l'ouverture / sur une pastille ; prédicat « stats désactivées » écrit 3 fois ; date absente de la puce masquée (conforme au brief)
Task 11: fix round 1/5 (2 addressed, 0 open — rechargement à l'ouverture, puce jamais coupée ; commits a35e164..1d6d69a)
Task 11: complete (commits e1b5220..1d6d69a, review clean after 1 fix round, CI 38448510796 vert, 52 tests)
Task 12: manuelle (Dan) — après la relecture finale et sa vague de corrections.
Final review (opus, 8f05886..1d6d69a) : « With fixes » — 0 Critical, 5 Important. Décisions (détail : final-fix-brief.md) :
Ruling 14 (I1): la ligne « Prochain », le compteur « à venir » et le tri des cartes ne doivent rien trahir quand le dernier match (direct ou terminé) d'une équipe est masqué → « Prochain · masqué » fixe, hors compteur et hors tri — sinon l'élimination ou la qualification se lit sur la carte pendant les Worlds — si faux : Dan voit moins d'infos sur ses équipes sans spoiler (il peut révéler).
Ruling 15 (I2): cartes et bandeau en verre « matière » (flou + teinte + bordure + arête), Liquid Glass système gardé pour la barre d'onglets — l'écho de réfraction est visible sur tous les écrans — écart à la spec §9 à amender, à valider par Dan à l'installation — si faux : revenir à glassEffect = un modificateur.
Ruling 16 (I3): plus de logos pleine taille dans les listes (LazyVStack, vignettes en cache ou monogramme, aucun téléchargement pour les équipes non suivies) — risque mémoire/données sur l'iPhone — coût : logos absents pour les équipes non suivies.
Ruling 17 (mineurs avant installation) : cibles 44 pt, libellés masqués conformes §8 (« Terminé », « À venir »), pilules jusqu'au bord, « Valider » sans changement n'écrit rien, noms de champions + « ancestral », décodage optionnel tolérant de FollowedTeam, drapeau « illisible » effacé seulement après relecture réussie, pas de cache HTTP dans LoLKit, CI sur le simulateur le plus récent.
Ruling 18 (différé) : I4 (prérequis étape 4 dans AppStore) et I5 (logique des widgets vers LoLKit, reloadAllTimelines) → plans des étapes 3-4 ; autres mineurs triés « can stay deferred » par la relecture.
Final review: fix wave (commits 1d6d69a..92e1b3c, F1–F9, CI iOS 38454317932 + LoLKit 38454317965 verts, 64 tests hébergés, 152 LoLKit)
Final review: fix wave re-review — F1…F9 ADDRESSED, aucune nouvelle anomalie bloquante. Mineurs : commentaire de lastRow obsolète ; suivis faits en mémoire pendant un fichier illisible perdus quand il redevient lisible (cas très rare) ; écart de compte de tests dans le rapport ; bandes diagonales sur les cartes matière (à vérifier sur l'iPhone) ; règle live ?? last avec calendrier périmé (à reprendre pour widgets/Live Activity).
Spec amendée : §8 (ligne « Prochain » masquée) et §9 (verre matière pour les cartes).
Plan complete: étape 2 terminée — HEAD 92e1b3c, IPA C:\Users\Dan\Downloads\faille\Faille-etape2.ipa (CI iOS 38454317932).

## Décisions par tâche (preflight-rulings.md)

# Décisions du contrôleur après l'analyse préalable (prioritaires sur le texte du plan)

Chaque implémenteur lit la section de SA tâche (et la section « Toutes les tâches »). En cas de conflit avec le brief, ces décisions l'emportent ; documenter l'application dans le rapport.

## Toutes les tâches
- R-M15 : si une tâche a dû remplacer une API iOS par une alternative (ex. `Tab(...)` → `.tabItem` + `.tag`, `glassEffect` → `.ultraThinMaterial`), le contrôleur le signale dans le dispatch des tâches suivantes : réutiliser l'alternative, ne pas réintroduire l'API qui a échoué.
- R-M9 : tout fichier de test qui utilise `.environment`, `View` ou d'autres API SwiftUI commence par `import SwiftUI`.

## Task 3
- R-M7 : l'attendu de `lolkit leagues` est « une ligne qui commence par `worlds` et se termine par `Mondial` » (le slug est complété à 28 colonnes), pas la chaîne exacte `worlds   Mondial`.

## Task 5
- R-M2 : la mise de côté d'un fichier JSON illisible ne détruit jamais rien : nom horodaté `<nom>.illisible-<yyyyMMdd-HHmmss>` (jamais de `removeItem` d'une mise de côté précédente) ; si le déplacement échoue, `FileStore` mémorise ce fichier comme « protégé » et refuse ensuite de l'écraser (save renvoie sans écrire) pendant la durée du processus ; l'extension widget (lecture seule) ne met jamais de fichier de côté (paramètre ou initialiseur dédié, au choix, documenté).

## Task 6
- R-I1 : `Snapshot.write` attend la scène/fenêtre de l'app jusqu'à 5 s (boucle courte avec `Task.sleep`), et lève une erreur si aucune fenêtre ou si `drawHierarchy(in:afterScreenUpdates:)` renvoie `false` ; les tests de capture vérifient en plus que le PNG écrit fait plus de 10 Ko (image non vide).
- R-M1 : `soraIsBundled` vérifie aussi l'axe de graisse : la largeur de "Mondial" en Sora gras 15 pt est strictement supérieure à celle en Sora regular 15 pt.
- R-M8 : `xcrun simctl list --json devices available` (drapeau avant les arguments positionnels).
- R-M10 : `StubTransport` (utilisé seulement par les tests) va dans `Tests/FailleTests/Support/StubTransport.swift` (avec `import LoLKit`), pas dans `Shared/Preview` ; adapter le `git add` et les références. Si une tâche ultérieure du plan le référence depuis `Shared/Preview`, c'est le chemin de test qui fait foi.

## Task 7
- R-I2 : pour une game EN COURS, ne pas sauter le flux `window` quand `statsDisabled` est vrai (dans `refreshLiveStats`) : on en a besoin pour le chrono (spec §4.3, §5.1). Les stats restent masquées (LoLKit les ignore déjà si `statsDisabled`), et une 404 arrête toujours les nouvelles tentatives pour cette game. Pour les games terminées, garder le saut.
- R-I3 : `AppStore.saveFollows()` appelle `WidgetCenter.shared.reloadAllTimelines()` (avec `import WidgetKit`) sauf en mode aperçu/test, pour que le widget sonde reflète tout de suite les équipes suivies.
- R-M3 : supprimer le repli « lier LoLKit à FailleTests ». Si les tests ne trouvent pas le module ou des symboles : d'abord vérifier `DEAD_CODE_STRIPPING: NO` (Debug) ; s'il s'agit d'un module introuvable, ajouter le chemin des modules du produit (`SWIFT_INCLUDE_PATHS: $(BUILT_PRODUCTS_DIR)`) au target de test ; ne jamais lier une seconde copie de LoLKit.
- R-M6 : accepté tel quel (bannière par dernier échec, nouvel essai à 60 s).

## Task 10
- R-M12 : la ligne « Dernier » masquée affiche aussi la date (`Format.matchDate(event.startTime)`), comme la spec §8 (« avec la date »).

## Task 11
- R-I2 : dans `loadSelectedGame`, pour une game en cours, interroger le flux même si `statsDisabled` (chrono), sans afficher de stats ; message « Stats live non fournies par Riot pour ce match » conservé.
- R-M5 : le score de série de l'en-tête passe par `store.scoreLine(event)` (`.score`, réordonné), jamais directement par `event.match.teams.map(\.gameWins)`.

## Task 12
- R-M6 : le point « la bannière disparaît en moins d'1 min » devient « en environ 1 min ».

## Acceptés / différés (pas d'action)
M4 (frames d'une game terminée via startingTime = maintenant − 60 s : gardé, vérifié en T12), M11 (écarts documentés : recherche sur équipes actives, pas de pastille de ligue sans équipe, pas de Sora dans l'extension avant l'étape 3, stats des cartes toutes les 60 s, captures via drawHierarchy — à signaler à Dan), M13 (perf TeamDirectory acceptable), M14 (log de LossyArray → étape 3), M16 (petites duplications → plus tard), M17 (`AppStore` vs StoreKit → renommer avant l'étape 4 si StoreKit entre en jeu).

## Task 7 (ajout après la relecture de la Task 1)
- R-T1a : la boucle de rafraîchissement enregistre `lastSuccess` avec l'heure de DÉBUT de la tentative (pas l'heure de la réponse), pour tenir la cadence de 60 s du live.
- R-T1b : un tirer-pour-rafraîchir explicite (pull-to-refresh) remet à nil `lastAttempt` des types qu'il force, avant d'appeler `RefreshPolicy.due`, pour qu'il agisse même juste après un échec.
- R-T2 : `LogoFileName.name(for:)` reçoit toujours la chaîne BRUTE de l'API (`team.image` / `MatchTeam.image`), jamais l'URL convertie en https ; `ImageURL.secure` ne sert qu'à construire l'URL de téléchargement.
- R-T3 : une requête annulée (passage en arrière-plan, sortie de l'écran Détail) remonte en `URLError(.cancelled)` avec le vrai réseau ou en `CancellationError` en test : le store les traite toutes deux (et `Task.isCancelled`) comme « pas un échec » — pas de `lastAttempt` ratée, pas de bannière « lolesports ne répond pas ».
- R-T5 (pour T7) : `FileStore.load` peut renvoyer nil pour un fichier existant mais illisible au niveau E/S (sans mise de côté) : le store ne doit jamais sauvegarder des valeurs par défaut vides par-dessus avant une vraie modification par l'utilisateur (ne sauvegarder `follows`/`settings` qu'à la suite d'une action de l'utilisateur ou d'un chargement réussi). Le widget (étape 3) ouvre `FileStore(directory:readOnly: true)`.
- R-T5b (pour T7) : ajouter dans la cible de tests de l'appli un `FileStoreTests` (dossier temporaire) : mise de côté horodatée d'un JSON illisible sans écraser une mise de côté précédente, refus d'écrire si le fichier est protégé, mode `readOnly` qui n'écrit rien et ne met rien de côté.
- R-T6 (pour T7, issu de la relecture de T6) : (a) `ApercuTests.expectNotBlank` passe à un seuil de 100 000 octets (le dégradé seul pèse ~54 Ko), et le commentaire est corrigé ; (b) le job `apercus` de `ios.yml` reçoit `timeout-minutes: 30` ; (c) `IconView` rend ses images décoratives (`.accessibilityHidden(true)`), le texte voisin porte le sens. API iOS 26 confirmées par T6 : `glassEffect`, `Glass.regular.tint`, `Font(CTFont)` fonctionnent ; ne pas utiliser `UIWindowScene.coordinateSpace` (déprécié).

## Task 9 (ajouts du contrôleur)
- R-T8 : en branchant l'engrenage sur `SettingsView`, remplacer dans `SettingsView` le `@State mode` + `.onAppear` + `.onChange` par un `Binding(get: { store.settings.liveActivityMode }, set: { store.setLiveActivityMode($0) })` (une seule source de vérité, plus de réécriture inutile) ; ajouter un test hébergé : `setLiveActivityMode(.manual)` puis un nouveau `AppStore` sur les mêmes fichiers → `.manual`.
