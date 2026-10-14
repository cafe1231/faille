# Faille — checklist de test sur l'iPhone (étapes 2, 3, 4 et finitions)

À faire avec la dernière IPA (`C:\Users\Dan\Downloads\faille\Faille-etape4.ipa`), idéalement pendant un vrai match des Worlds d'une équipe suivie (premier match : **jeudi 15/10 à 20 h, C9 vs KC**). Pour chaque ligne : OK / KO + une remarque. Les KO deviennent des corrections.

## 0. Installer (AltServer, comme pour la sonde)

1. iPhone branché en USB et déverrouillé, iTunes et AltServer lancés sur le PC.
2. **Maj + clic** sur l'icône AltServer (barre des tâches, près de l'horloge) → **Sideload .ipa…** → choisir l'iPhone → `Faille-etape4.ipa` → ton Apple ID (tu le tapes toi-même).
3. Même identifiant que la sonde : l'ancienne Faille est remplacée. Le widget « Sonde Faille » posé à l'écran d'accueil devient vide : retire-le.
4. Avant le match, dans les Réglages iOS :
   - Général › Actualisation en arrière-plan : **activée** pour Faille ;
   - Faille › Activités en direct : **activées** ;
   - mode économie d'énergie **coupé**.
5. Pendant le test, **ne ferme jamais Faille de force** (glisser vers le haut dans le sélecteur d'applis) : iOS ne réveille plus une appli fermée de force, et la Live Activity ne se mettrait plus à jour.
6. Suis tes équipes **avant** le match (une équipe suivie en cours de match garde la couleur par défaut sur sa Live Activity).

## A. L'appli (étape 2)

1. Ouverture : fond abysse sombre, police Sora (titres épais, chiffres ronds), barre d'onglets flottante en verre « Matchs » / « Équipes », aucune emoji.
2. Premier lancement (si l'appli est vierge) : onglet Matchs = « Bienvenue dans Faille », le bouton mène à Équipes.
3. Équipes : pilules de ligues (Mondial en tête) ; « Mondial » liste les équipes des Worlds ; « La Ligue Française » liste les équipes LFL.
4. Recherche « kc » : Karmine Corp en premier ; l'étoile la met dans « Mes équipes » ; en quelques secondes, logo et couleur (badge, point) remplacent le bleu clair par défaut.
5. Suivre 2-3 équipes (dont une des Worlds) : une carte teintée par équipe, avec Prochain (date et heure locales) et Dernier.
6. Appui long sur une équipe suivie → « Changer la couleur » → un vert → Valider : la carte devient verte ; « Couleur automatique » rétablit la couleur du logo.
7. Œil sur une équipe → « sans spoiler » : sa carte n'affiche plus aucun score ; ouvrir le match → « toucher pour révéler » → le score apparaît ; relancer l'appli → le match reste révélé.
8. Pendant un match en direct : carte « En direct · Game N · chrono » (le chrono avance seul), score de série, ligne kills / gold / drakes / tours qui change d'une minute à l'autre.
9. Détail du match : pilules de games, stats qui bougent toutes les ~10 s, barre de gold, drakes avec leurs types, joueurs des deux équipes ; une game terminée montre ses stats finales (ou « Stats de cette game indisponibles » : noter lequel).
10. Mode avion puis tirer pour rafraîchir : bandeau « lolesports ne répond pas · màj HH:MM », les cartes restent ; sortir du mode avion : le bandeau disparaît en moins d'une minute.
11. Tuer l'appli, la relancer en mode avion : équipes, cartes et calendrier s'affichent tout de suite (cache).
12. Engrenage → Réglages : Automatique / Manuelle conservé après relance ; À propos : « 0.1.0 (1) · LoLKit 0.1.0 » et « Groupe d'apps : group.com.cafe1231.faille.<TEAMID> ».
13. Les couleurs d'équipe arrivent toujours (elles sont maintenant calculées hors du rafraîchissement) : suivre une nouvelle équipe → sa couleur apparaît en moins d'une minute.
14. (Facultatif) iPad : mêmes écrans, contenu centré, lisible en paysage.

## B. Les widgets (étape 3)

1. Écran verrouillé → Personnaliser → ajouter « Prochain match » en ligne (au-dessus de l'heure), rectangulaire et rond : monochrome, police Sora (gras et normal bien distincts), icônes au trait ; le contenu correspond à l'onglet Matchs.
2. Le rond : compte à rebours (« 21h », « 45 min »), code de l'équipe ; la jauge avance au fil des heures ; paliers de 5 min dans la dernière heure ; « 0 min » si le match a du retard.
3. Écran d'accueil : « Mon équipe » (petit) → première équipe suivie, teintée à sa couleur, monogrammes ; Modifier le widget → **la liste des équipes apparaît** → choisir une autre équipe → il bascule.
4. « Mes équipes » (moyen) : matchs en direct d'abord, puis les prochains ; **4 lignes tiennent sans être coupées** ; points de couleur des équipes.
5. Anti-spoiler : une équipe en anti-spoiler dont le dernier match est terminé → « Prochain · masqué », jamais de score ni de numéro de game ; pendant son match, seulement « En direct ».
6. Écran verrouillé avec **uniquement** une équipe masquée suivie → « Prochain · masqué » (et pas « Aucun match prévu »).
7. Cas « GEN vs T1 » (GEN suivie normalement, T1 en anti-spoiler) : tant que le dernier match de T1 est masqué, la ligne de GEN montre « Prochain · masqué » ; une fois ce match de T1 révélé, « GEN vs T1 » s'affiche.
8. Dans le widget moyen, une équipe masquée a sa ligne « T1 · Prochain · masqué » après les lignes datées.
9. Révéler un match dans l'appli, revenir à l'accueil : les widgets montrent le score / le prochain match en quelques secondes. Suivre / ne plus suivre une équipe : idem.
10. Match en retard (fréquent aux Worlds) : à l'heure prévue, le widget le garde comme prochain (« 0 min ») tant que l'appli a des données fraîches ; il n'annonce pas le match suivant trop tôt.
11. Pendant un match, appli ouverte puis fermée : le widget en ligne affiche « KC 1–0 C9 · G2 » ; une dizaine de minutes après la fermeture, la ligne « en direct » disparaît (le widget ne prétend pas connaître le direct sans données fraîches).
12. Mode teinté d'iOS 26 (appui long sur l'accueil → Personnaliser → Teinté) : les widgets restent lisibles.
13. (Facultatif) iPad : petit et moyen widgets.

Note : les planches PNG de l'écran verrouillé sont approximatives (iOS pose sa propre plaque translucide).

## C. La Live Activity (étape 4) — pendant un match des Worlds

1. Réglages de Faille : « Automatique ». Ouvrir Faille pendant le match ; à la première Live Activity, iOS demande s'il faut l'autoriser : **Autoriser**. Ouvrir le Détail du match : attendre que le bouton affiche « Retirer de l'écran verrouillé » (quelques secondes), puis verrouiller : en-tête « MONDIAL · BO5 · GAME N », chrono, score entre les monogrammes, 5 lignes de stats, fond à la couleur de l'équipe suivie. Rien n'est coupé en bas.
2. Chrono, téléphone verrouillé : il avance seul **pendant ~3 min après la dernière mise à jour**, puis « màj il y a X minutes » le remplace (attendu : la donnée n'est plus fraîche). Noter le texte exact affiché (et, après une heure, « il y a 1 heure »).
3. Dynamic Island : compacte (monogramme + victoires de chaque côté de la caméra, **l'équipe suivie à gauche**) ; appui long → déployée (équipes, score, « Game N · chrono », 5 stats) ; minimale quand une autre appli occupe l'île (lancer un minuteur de l'Horloge).
4. Premier plan : laisser Faille ouverte 2 min puis verrouiller : score et stats à jour (moins d'une minute de retard sur l'appli).
5. Arrière-plan : verrouiller 30 min sans ouvrir Faille. Noter ce qui se passe : mises à jour toutes les ~15 min (si iOS accorde les réveils) ou « màj il y a X minutes » à la place du chrono, stats pâlies. Les deux sont normaux sans serveur de push ; noter lequel.
6. Game en pause (si ça arrive) : le chrono s'arrête.
7. Entre deux games : « entre deux games » (icône pause), score de série à jour, « La game N commence dans quelques minutes ».
8. Anti-spoiler : une équipe suivie en anti-spoiler joue → « En direct » + « Sans spoiler · ouvre l'appli pour révéler », ni score ni numéro de game ni stats, **dans aucune zone de la Dynamic Island** non plus. Révéler le match dans l'appli → la Live Activity montre le score en quelques secondes (les stats suivent à la relecture suivante, ≤ 1 min).
9. Glisser la Live Activity pour la retirer, rouvrir Faille : elle ne revient pas ; le Détail du match propose « Épingler sur l'écran verrouillé » → elle revient ; « Retirer de l'écran verrouillé » → elle s'en va.
10. Réglage « Manuelle » : les Live Activities non épinglées s'en vont ; épingler un match depuis le Détail → il s'affiche ; rien d'autre ne s'affiche tout seul. Repasser en « Automatique ».
11. Fin du match : « Victoire XX » (icône trophée), score final, « Se retire de l'écran verrouillé au bout d'une heure » ; elle disparaît environ 1 h plus tard.
12. Match d'une compétition hors des ligues suivies (si l'occasion se présente, ex. coupe régionale) : à la fin, la Live Activity passe bien « Victoire XX » au lieu de rester « màj il y a… ».
13. Match sans stats (si l'occasion se présente) : score + chrono + « Stats live non fournies par Riot pour ce match ».
14. Plus de 3 matchs suivis en direct (si l'occasion se présente) : 3 Live Activities au plus ; « Épingler » un 4e → « Déjà 3 Live Activities… ».
15. Live Activities coupées dans Réglages › Faille : le Détail affiche « Live Activities désactivées : Réglages › Faille › Activités en direct. ».
16. Nom de ligue long (si l'occasion se présente) : l'en-tête se raccourcit proprement, le statut à droite reste lisible.
17. iPad (si disponible) : pas de bouton « Épingler », l'appli et les widgets marchent.
18. Pendant le match, fermer Faille normalement puis la rouvrir (sans fermeture forcée) : il y a toujours **une seule** Live Activity pour ce match, et elle continue de se mettre à jour.
19. Après un réveil d'arrière-plan (le compteur « màj » repart de zéro), les stats et le chrono sont toujours là (s'ils disparaissent, le noter).
20. Dynamic Island déployée quand la Live Activity n'est plus fraîche : le texte « màj il y a … » est lisible.
21. Si tu as une Apple Watch : la Live Activity apparaît aussi dans la pile intelligente ; un match masqué n'y montre aucun score.

**Si quelque chose ne marche pas** (pas de Live Activity, pas de mise à jour en arrière-plan) : ouvre Faille → engrenage → Réglages → À propos → bloc **« Diagnostic Live Activity »**, et fais une capture d'écran : il dit le dernier échec de démarrage, le dernier réveil et la dernière demande de réveil.

## Une question de design pour toi (après le test)

Quand la Live Activity n'a pas été mise à jour depuis 3 min (téléphone verrouillé, iOS n'a pas réveillé l'appli), elle remplace le chrono par « màj il y a X minutes » (c'est la spec). Variante possible : garder le chrono **et** ajouter un petit « màj il y a X min ». Le chrono reste juste (il est calculé à partir du début de la game), sauf si la game s'est terminée entre-temps. À toi de choisir après l'avoir vu en vrai.

## D. Finitions (animations, retours tactiles, icône)

À faire avec `C:\Users\Dan\Downloads\faille\Faille-finitions.ipa` (installer comme au §0). Un match en direct d'une équipe suivie aide pour D.4, D.5, D.12 et D.14 ; le reste se vérifie à tout moment. Pour chaque ligne : OK / KO + une remarque (« trop lent », « trop fort », « on ne le voit pas »…) : c'est ici que se juge le style « sobre et fluide ».

1. **Icône** : sur l'écran d'accueil, l'icône Faille (fond abysse, faille verticale lumineuse cyan, halo doux, aucun texte) remplace l'icône vide ; la même dans Réglages › Faille, Spotlight et le sélecteur d'applis. Appui long sur l'accueil › Personnaliser › **Sombre** : la faille sur fond sombre ; **Teinté** : une version d'une seule teinte, lisible.
2. **Toucher** : le bloc « En direct » d'une carte, les lignes Prochain et Dernier, une pilule de ligue ou de game, l'étoile, l'œil, « Choisir mes équipes », « Épingler », « À propos » s'enfoncent légèrement et pâlissent pendant l'appui, puis reviennent sans rebond. Les zones de toucher n'ont pas rétréci (œil et étoile toujours faciles à viser).
3. **Retours haptiques**, un seul par action : suivre une équipe (succès) ; ne plus suivre (léger) ; œil (petit clic) ; Épingler (succès) ; Retirer (léger) ; toucher pour révéler (moyen) ; tirer pour rafraîchir (succès ; en mode avion : avertissement) ; Valider une couleur ou « Couleur automatique » (petit clic) ; changer de pilule de game (petit clic). **Aucun** retour pendant un match quand les stats se mettent à jour toutes les 10 s.
4. **Chiffres qui défilent** (match en direct) : sur la carte et dans le Détail, kills, gold, tours, inhibs, barons, drakes et le score de série changent en faisant défiler leurs chiffres ; le sous-titre « N en direct · N à venir » aussi. Sur une carte masquée : aucun chiffre, donc rien ne défile.
5. **« En direct »** : un halo doux respire lentement (≈ 1,6 s) derrière l'icône « en direct » de la pastille de la carte, de la pastille du Détail et de la pilule de la game en cours ; il ne clignote pas.
6. **Zoom** : toucher le bloc « En direct » d'une carte → le Détail s'ouvre en zoomant depuis ce bloc ; revenir (bouton retour, glisser depuis le bord gauche ou vers le bas) → il se referme vers le même bloc. Pareil depuis « Prochain » et « Dernier ». Si les deux équipes d'un match sont suivies (deux cartes), le zoom part de la carte touchée.
7. **Listes** : dans Équipes, suivre / ne plus suivre fait apparaître (fondu, léger grossissement) ou disparaître (fondu) la ligne dans « Mes équipes », sans saut. À l'ouverture de l'appli, les cartes de Matchs arrivent en cascade rapide, une fois ; en revenant du Détail, pas de nouvelle cascade.
8. **Révéler** : sur une carte masquée, « toucher pour révéler » → le score et les stats sortent d'un flou en fondu (≈ 0,5 s), avec un retour moyen ; pareil dans le Détail. Remettre l'œil dans Équipes → la carte redevient masquée en simple fondu. Aucun chiffre n'apparaît, même un instant, sur un match encore masqué.
9. **Détail** : la capsule blanche glisse d'une pilule de game à l'autre ; la barre de gold change de largeur en douceur ; changer d'équipe dans « Joueurs » fait un fondu des lignes.
10. **Chargement** : ouvrir un match pas encore chargé (ou, au premier lancement, l'onglet Équipes) → des formes grises arrondies au gabarit du contenu, parcourues d'un reflet lent, au lieu d'une roue ; le contenu les remplace dès qu'il arrive.
11. **Bandeau d'erreur** : mode avion puis tirer pour rafraîchir → le bandeau descend du haut en fondu ; sortir du mode avion → il remonte et disparaît.
12. **Lueur d'équipe** : une carte dont le match est en direct et non masqué a un contour qui luit doucement à la couleur de l'équipe et respire lentement (≈ 2,4 s) ; une carte masquée (équipe en anti-spoiler) n'a **aucune** lueur.
13. **Réduire les animations** (Réglages › Accessibilité › Mouvement › Réduire les animations, activé) : plus de zoom (transition standard), plus de cascade, halo et lueur fixes, squelettes sans reflet, les surfaces ne s'enfoncent plus (elles pâlissent seulement), la capsule des pilules ne glisse plus, chiffres et révélation en simple fondu ; les retours haptiques sont toujours là. Désactiver ensuite.
14. **Widgets et Live Activity** : quand le score ou une stat change, les chiffres défilent au passage (si iOS l'anime) ; rien ne bouge en continu (pas de halo, pas de pulsation).
15. **Fluidité** : pendant un match en direct, faire défiler Matchs et le Détail : aucun à-coup ; le téléphone ne chauffe pas plus qu'avant.
