# Faille — finitions (animations, retours tactiles, icône) : conception

Date : 14/10/2026. Demande de Dan : « améliorer la qualité de l'appli pour les transitions, les boutons, les effets ». Style choisi : **A — sobre et fluide, façon Apple**, avec quelques touches de lueur à la couleur de l'équipe. Ce lot passe avant les 5 fonctionnalités (stream, notifications, draft, fil des événements, courbe de gold).

Spec de référence : `docs/superpowers/specs/2026-10-13-faille-design.md` (DA §9, anti-spoiler §8 : contraignants). Aucune donnée ni règle métier ne change ; LoLKit ne change pas (sauf besoin de test pur).

## Principes
- **Un seul vocabulaire de mouvement** : `App/DA/Motion.swift` (ou `Shared/DA/` si les widgets / la Live Activity en ont besoin) donne les ressorts et durées nommés : `press` (≈0,18 s), `snappy` (≈0,3 s), `smooth` (≈0,45 s), `number` (chiffres), `list` (listes), `reveal` (≈0,5 s). Aucune durée en dur dans les vues.
- **« Réduire les animations »** (`@Environment(\.accessibilityReduceMotion)`) : mouvements, zooms, cascades, pulsations et scintillements remplacés par un simple fondu (ou rien) ; les retours haptiques restent.
- **Sobre** : pas de particules, pas de rebond exagéré, pas d'effet qui retarde l'information. Une animation ne doit jamais masquer ni retarder un changement de données (le chiffre final est toujours affiché).
- **Anti-spoiler** : aucune animation ne trahit un match masqué (ex. pas de « chiffres qui défilent » sur un score masqué, pas de lueur « victoire » sur une carte masquée) : les effets s'appliquent aux valeurs déjà décidées par `Presenter` / `SpoilerPolicy`.
- **Liquid Glass système** (barre d'onglets, boutons de barre d'outils) : inchangé, il a ses propres effets.

## Contenu
1. **Icône de l'appli** (aujourd'hui vide : `ASSETCATALOG_COMPILER_APPICON_NAME: ""`). Dessin : fond abysse (`#0B1020` vers plus profond), une **faille** verticale lumineuse couleur accent `#6FD3FF` avec un halo doux, rien d'autre (pas de texte). Variantes iOS 18+ : sombre (fond transparent) et teintée (niveaux de gris). Produite par une vue SwiftUI `AppIconArt` rendue à 1024 × 1024 px (`ImageRenderer`, échelle 1) dans un test hébergé → PNG de l'artefact → ajoutés à `Resources/Assets.xcassets/AppIcon.appiconset` (format une taille) ; `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` pour l'appli (l'extension n'a pas d'icône). Aperçu `14-icone.png` sur fond clair et sombre.
2. **Toucher** : `PressableStyle` (ButtonStyle) — échelle 0,97, légère baisse d'opacité, ressort `press` ; remplace `.buttonStyle(.plain)` sur toutes les surfaces touchables (cartes, lignes, pilules, boutons en verre). Zone tactile inchangée (≥ 44 pt).
3. **Retours haptiques** (`.sensoryFeedback`) : suivre (succès) / ne plus suivre (impact léger), œil anti-spoiler (sélection), épingler (succès) / retirer (impact léger), révéler (impact moyen), tirer pour rafraîchir terminé (succès si OK, avertissement si échec), couleur choisie (sélection), pilule de game (sélection). Jamais en boucle (pas à chaque mise à jour de stats).
4. **Chiffres qui défilent** : `.contentTransition(.numericText())` + `Motion.number` sur le score de série, kills, gold, tours, inhibs, barons, drakes, chrono figé, compteur « N à venir » — cartes, Détail, widgets (WidgetKit anime les changements d'entrée) et Live Activity (ActivityKit anime les mises à jour). Uniquement sur les valeurs non masquées.
5. **Point « en direct » qui pulse** : halo doux qui respire (≈1,6 s, opacité + échelle) derrière l'icône « en direct » des cartes, du Détail et des pilules ; statique si « Réduire les animations ». Pas de pulsation dans les widgets / la Live Activity (iOS ne les anime pas en continu).
6. **Transition zoom carte → Détail** : `matchedTransitionSource` sur la ligne touchée + `navigationTransition(.zoom(sourceID:in:))` sur l'écran Détail (iOS 18+). Un même match peut apparaître dans deux cartes : l'identifiant de source inclut la carte (équipe) et la ligne. Repli : transition standard si l'identifiant manque.
7. **Listes animées** : cartes et lignes d'équipes avec insertion (fondu + échelle 0,96) et suppression (fondu) animées (`Motion.list`) quand on suit / ne suit plus, change l'ordre, ou quand les données arrivent ; apparition en cascade à la première apparition de l'écran (décalage ≈ 40 ms par carte, 8 cartes au plus), une seule fois par apparition.
8. **Révélation anti-spoiler** : « toucher pour révéler » → le score masqué sort d'un flou (rayon ≈ 10 → 0) avec un fondu (`Motion.reveal`) + haptique ; le masquage (œil) fait l'inverse, en fondu simple.
9. **Pilules de games** : la capsule de sélection glisse d'une pilule à l'autre (`matchedGeometryEffect`) ; **barre de gold** dont la largeur s'anime (`Motion.smooth`) ; changement d'onglet de joueurs animé.
10. **Chargement** : `SkeletonBlock` (formes arrondies au gabarit du contenu, reflet qui balaie lentement) à la place des `ProgressView` (Détail, catalogue des équipes) ; statique si « Réduire les animations ».
11. **Bandeau d'erreur** : entrée et sortie en glissant du haut + fondu (`Motion.snappy`).
12. **Lueur d'équipe** (touche DA) : une carte dont un match est **en direct et non masqué** a une lueur douce à la couleur de l'équipe sur son contour, qui respire lentement (≈2,4 s, faible amplitude) ; statique si « Réduire les animations ». Rien sur une carte masquée.

## Vérification
- Les animations ne se voient pas sur les PNG : les planches existantes doivent rester identiques (aucune régression de mise en page, `expectNotBlank`, contrôles d'encre) ; l'icône a son aperçu `14-icone.png` (1024 px, > 100 000 octets).
- Tests hébergés : `Motion` renvoie `nil` / un fondu quand « Réduire les animations » est actif ; l'identifiant de source du zoom est unique par carte et par ligne ; `PressableStyle` ne change pas la zone tactile (taille mesurée).
- Le jugement final se fait sur l'iPhone de Dan (checklist « Finitions » ajoutée à `docs/superpowers/notes/2026-10-14-checklist-iphone.md`).

## Hors périmètre
Effets « gaming » (particules, flash au kill), sons, animations continues dans les widgets ou la Live Activity, refonte de la mise en page, nouvelles données.
