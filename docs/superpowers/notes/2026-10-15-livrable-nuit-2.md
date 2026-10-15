# Faille — la nuit n° 2 (14 → 15/10/2026)

## 1. Ce qui a été fait

Faille devient le **compagnon de saison** : on l'ouvre sur un accueil qui dit quoi regarder, on touche une équipe ou un joueur pour voir sa saison, on compare, on suit une ligue entière.

| Fonctionnalité | État |
|---|---|
| **Socle de saison** : statistiques de chaque équipe et de chaque joueur, calculées à partir des games jouées (KDA, CS/min, gold/min, drakes, barons, tours, durée, champions joués, part des dégâts, vainqueur de chaque game), gardées sur disque, collecte lente et sans rafale | fait et testé |
| **Onglet Accueil** (premier onglet) : matchs en direct, bandeau de la semaine, résultats récents, activité récente (séries, moments forts), joueurs en forme, « à ne pas rater » | fait et testé |
| **Calendrier complet** (vue mois, équipes et ligues suivies) | fait et testé |
| **Page équipe** : bilan de saison, forme sur 5 matchs, effectif, stats moyennes par game, champions les plus joués, prochains matchs, face-à-face | fait et testé |
| **Page joueur** : champions, KDA, CS/min, gold/min, part des dégâts, meilleure game | fait et testé |
| **Duels** de joueurs (poste contre poste, ou deux joueurs au choix) et d'équipes, avant ou après un match | fait et testé |
| **Suivre une ligue entière**, avec notifications de début de match | fait et testé |
| **Classements et tableaux** (système suisse, phase finale) | fait et testé |
| **« À ne pas rater »** : les matchs du jour classés par enjeu, avec la raison | fait et testé |
| **Onboarding** du premier lancement (3 écrans, exemple fictif) | fait et testé |
| **Accessibilité et anglais** : VoiceOver, grand texte, catalogue français et anglais (327 chaînes) | fait et testé |
| **Spec Phase 2** (serveur, push, ligues de pronos entre amis) et **note de conformité Riot / App Store** | fait (documents) |
| **Pronostics, indicateur de domination, moments forts, MVP, carte de partage, mode rattrapage, extras iOS** | **pas fait** : l'ordre de coupe du fichier de la nuit les mettait après tout le reste ; ils sont dans `docs/superpowers/notes/2026-10-14-idees.md` et la spec |

Anti-spoiler : appliqué sur tous les nouveaux chemins (accueil, calendrier, pages équipe et joueur, duels, classements, ligues, notifications). La relecture finale a trouvé deux fuites (la progression d'un tableau trahissait une élimination ; suivre une équipe pendant l'onboarding pouvait démarrer une Live Activity avant la page anti-spoiler) : **corrigées**.

CI verte : iOS [38663963372](https://github.com/cafe1231/faille/actions/runs/38663963372), Strings [38663963339](https://github.com/cafe1231/faille/actions/runs/38663963339), LoLKit [38662897499](https://github.com/cafe1231/faille/actions/runs/38662897499) (413 tests).

## 2. L'IPA

`C:\Users\Dan\Downloads\faille\Faille.ipa` (CI verte sur `main`).
1. iPhone branché en USB, déverrouillé, iTunes et AltServer lancés.
2. **Maj + clic** sur l'icône AltServer → **Sideload .ipa…** → ton iPhone → `Faille.ipa` → ton Apple ID.
3. Si l'icône reste vide, redémarre l'iPhone ; ne désinstalle pas l'appli (tu perdrais tes réglages).

Au premier lancement, l'onboarding s'ouvre (tu peux le passer). La collecte des stats de saison prend plusieurs minutes (« N games lues » avance sur l'Accueil) : laisse l'appli ouverte au premier plan.

## 3. Checklist

`docs/superpowers/notes/2026-10-14-checklist-iphone.md`, **section F** (nouveautés de la nuit). Les points les plus utiles à regarder en premier : l'Accueil au premier lancement, un match masqué (rien ne doit trahir le résultat dans le bandeau, le calendrier ou la page équipe), la collecte (chaleur, batterie), et le lien profond d'une notification.

## 4. Décisions prises pendant la nuit (« Ruling »), avec leur coût si elles sont fausses

- **Stats de saison calculées à partir des frames de fin de game** (1 requête de début + 1 de fin par game) plutôt que d'une source tierce : seule voie gratuite et officielle-ish. Coût si faux : certaines stats (gold à 15 min, part des dégâts) coûtent 2 requêtes de plus ; le volume reste ~1 Mo par équipe et par split.
- **Le vainqueur d'une game n'est pas fourni par l'API** : exact pour un Bo1, un balayage ou la dernière game ; sinon déduit des tours détruites, sous contrainte du score de série, et **étiqueté « estimé »**. Coût si faux : un vainqueur estimé peut être faux (10 games sur 31 de KC au LEC Split 3).
- **Collecte limitée** : équipes et ligues suivies plus la phase en cours du Mondial ; 1 requête toutes les 2 s, 300 par session, réserve de 20 pour les écrans ouverts ; arrêt après 5 échecs d'affilée. Coût si faux : certaines stats d'une ligue non suivie n'apparaissent pas tant qu'on ne la suit pas.
- **Plafond de 2 000 games en cache** (une game d'équipe suivie n'est jamais supprimée). Coût si faux : des games d'une ligue lointaine sont relues plus tard.
- **Aucune requête vers Leaguepedia pendant le développement** (le wiki nous limitait) : l'appli garde sa règle stricte (une requête par match, ≥ 30 min après la fin, 3 essais). Coût si faux : les sorts d'invocateur des games terminées peuvent mettre du temps à apparaître.
- **Masquer au niveau de la compétition** : un match d'une ligue internationale postérieur à un match masqué est lui aussi masqué (sinon une demi-finale trahit l'élimination). Coût si faux : on voit moins de matchs du tableau tant qu'un match d'une équipe en anti-spoiler n'est pas révélé.
- **Révéler un classement ne révèle aucun match** : les scores de séries restent « vs » dans le tableau. Coût si faux : rien à regretter, ce n'est que prudent.
- **Pas de pick'em complet des Worlds ni de pronostics cette nuit**, coupés par l'ordre de priorité. Coût si faux : la fonctionnalité qui te tentait le plus arrive plus tard.
- **Nom « Mon Petit Prono » à ne pas reprendre** (appli de foot existante) : il faudra un autre nom. 
- **Trailers de commit mixtes** (Opus 5.5 et Sonnet 5.5 selon l'agent) acceptés, jamais réécrits. Coût : cosmétique.

## 5. Points ouverts qui ont besoin de Dan

1. **Tester sur l'iPhone** la section F de la checklist, surtout : Accueil au premier lancement, anti-spoiler, chaleur et batterie pendant la collecte.
2. **Jeudi 20 h, C9 vs KC** : la Live Activity en vrai, plus les nouvelles pages en direct. **Laisse le PC allumé avec Claude ouvert** : la surveillance des Worlds et la tâche planifiée « capture du direct » tournent.
3. **Tes décisions** : anti-spoiler strict ou non ; Live Activity « pas fraîche » (garder « màj il y a X minutes » ou chrono + petit « màj ») ; position du bouton « Épingler ».
4. **Demain, compte développeur et serveur** : lis la spec `docs/superpowers/specs/2026-10-15-phase2-serveur-push.md` et sa checklist (environ 3 h 30). **Avant de payer** : décider compte **individuel** (ton nom légal affiché comme vendeur) ou société (numéro D-U-N-S requis pour « Echap Studio »).
5. **Monétisation** : Riot réserve l'usage commercial du direct et du calendrier à GRID. Pas de pub ni d'achat intégré sans accord écrit de Riot ou de GRID. Lis `docs/superpowers/notes/2026-10-15-conformite-riot-app-store.md` (questions à poser à Riot et à GRID, point juridique à faire valider).
6. **GRID** : si tu as une réponse du formulaire d'accès ouvert, transfère-la-moi.
7. **Au plus tard le 21/10** : refaire un Sideload (l'appli expire au bout de 7 jours avec un compte gratuit), ou activer la synchro Wi-Fi d'iTunes.

## 6. Idées suivantes

Pronostics (barème, badges, carte à partager) et pick'em des Worlds ; indicateur de domination en direct ; moments forts et MVP ; carte de partage ; mode rattrapage des VOD ; widgets interactifs et raccourcis Siri ; repli hors saison du Mondial (le slug « worlds » est encore en dur : à corriger avant novembre) ; purge du cache d'images ; ligues entre amis avec le serveur (phase 2).
