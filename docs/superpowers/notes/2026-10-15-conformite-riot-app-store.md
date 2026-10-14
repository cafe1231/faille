# Faille — conformité Riot, données esport et App Store (note P4)

> 15/10/2026 · Lot P4 de `.superpowers/goal-nuit-2.md` · À lire avec `docs/superpowers/specs/2026-10-15-phase2-serveur-push.md`.
> **Information, pas un avis juridique.** Sources lues en ligne le 14-15/10/2026 (dates de mise à jour indiquées quand la page en donne une). Les citations sont courtes et en anglais (langue des sources) ; tout le reste est un résumé. Avant de **monétiser**, faire relire par un avocat (propriété intellectuelle / numérique).

## 0. En une phrase

Faille peut raisonnablement aller en **TestFlight** dès demain ; la **sortie publique** demande d'abord de s'enregistrer chez Riot et d'obtenir une réponse sur l'usage des flux lolesports ; la **monétisation** n'est pas prudente sans un **accord écrit**, car Riot réserve l'usage commercial des données esport en direct et du calendrier à **GRID**.

## Tableau de synthèse

| # | Sujet | Risque (gratuit) | Risque (monétisé) | Parade principale |
|---|---|---|---|---|
| 1 | Politiques développeur de Riot (enregistrement, mention) | Moyen | Élevé | Enregistrer « Faille » sur le portail développeur, mention de non-affiliation |
| 2 | Legal Jibber Jabber (IP de Riot dans une appli) | Moyen | Élevé | Pas de marque Riot, mention exigée, statut « API project » |
| 3 | Flux lolesports non officiels (`persisted/gw`, `livestats`) | **Moyen-élevé** | **Élevé — risque n° 1** | Question écrite à Riot ; dépendance isolée ; pas de redistribution par le serveur |
| 4 | Données officielles : GRID | — | Élevé (coût/accès) | Contacter GRID avant toute monétisation |
| 5 | Data Dragon, logos d'équipe, Leaguepedia | Faible-moyen | Moyen | Produit enregistré ; attribution ; monogrammes en repli |
| 6 | App Store : services tiers (5.2.2) et propriété intellectuelle (5.2.1) | Moyen | Élevé | Autorisation écrite prête « sur demande » |
| 7 | Pronos : paris, concours, jeux d'argent | Faible si gratuit sans lots | Élevé si lots/mises | Aucun argent, aucun lot, texte explicite |
| 8 | Nom « Faille », marques, fiche App Store | Faible-moyen | Moyen | Recherche INPI/EUIPO ; pas de « LoL » dans le nom ni les mots-clés |
| 9 | Confidentialité : politique, étiquettes, RGPD, suppression de compte | Faible si fait | Moyen (pub/ATT) | Politique publiée, étiquettes exactes, suppression in-app |
| 10 | Vendeur, statut de commerçant (DSA), contenu généré | Faible | Moyen | Décider individuel/organisation ; filtre/signaler/bloquer |

---

## 1. Politiques générales des développeurs Riot

**Source** : https://developer.riotgames.com/policies/general (mise à jour indiquée : 29/05/2025).

**Ce que disent les règles**
- Tout produit doit être enregistré et audité : « All products must be registered in, and audited by Riot Games through the Developer Portal. » Les nouvelles fonctions aussi.
- Données : « Products should use supported services from Riot Games for data ingestion. »
- Monétisation : il faut un statut **« Approved » ou « Acknowledged »** ; une **offre gratuite** obligatoire (« which may include advertising ») ; un contenu payant doit être **transformatif** ; modes de paiement admis : abonnements, dons / financement participatif, frais d'inscription à des tournois, monnaies non convertibles. Interdits : paris et jeux d'argent (« cannot feature betting or gambling functionality »), cryptomonnaies / blockchain, monétisation jugée abusive (« yes, we get to decide that »).
- Marques et logos Riot (kit presse) : seulement quand c'est « inevitable to serve the core value of the product » ; un produit ne doit pas ressembler de trop près à un produit Riot.
- **Mention obligatoire**, visible des joueurs (texte complet sur la page ; deux extraits) : « isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot Games », et « Riot Games, and all associated properties are trademarks or registered trademarks of Riot Games, Inc. »
- Sécurité : ne jamais mettre une clé d'API Riot dans le code distribué ; une clé de production par produit.

**Pour Faille** : Faille n'utilise aujourd'hui **aucune clé d'API Riot** ; elle lit les flux du site lolesports.com (§3), Data Dragon (§5) et Leaguepedia. Elle ne relève donc pas proprement de la case « produit API », mais la règle d'enregistrement vise « tous les produits ». Le site lolesports.com n’est pas un « supported service » documenté du portail.

**Risque** : moyen (gratuit), élevé (monétisé : il faut un statut Approved/Acknowledged, impossible sans enregistrement).

**Parade** : créer un compte sur le portail, **enregistrer « Faille »** avec une description honnête (appli compagnon gratuite, sources utilisées, aucun accès aux comptes des joueurs, anti-spoiler), demander par écrit si l'usage des flux lolesports est acceptable (§11). Ajouter la mention Riot dans Réglages › À propos, sur la fiche App Store (description) et sur le site.

## 2. « Legal Jibber Jabber » (projets de fans utilisant l'IP de Riot)

**Source** : https://www.riotgames.com/en/legal (mise à jour indiquée : août 2018 ; aussi https://riotgames.com/legal-jibber-jabber).

**Ce que disent les règles**
- Licence révocable pour des projets de fans **gratuits et non commerciaux** ; Riot peut faire arrêter un projet à tout moment.
- Sans licence écrite : interdits les projets commerciaux, financés participativement, **impliquant une entreprise ou une entité juridique**, ou payants. Trois exceptions : revenus publicitaires passifs d'un **individu** ; dons/abonnements pendant un stream ; **projets API** conformes aux conditions de l'API avec une clé Riot valide émise pour ce projet.
- **Applis** : l'IP de Riot (personnages, capacités, cartes, **icônes**, objets) ne peut pas être utilisée dans des jeux ou des applis ; un projet sur l'**App Store ou Google Play** exige **une licence écrite ou une clé d'API valide** conforme aux conditions.
- Pas de logos ni de marques Riot sans licence ; pas de **noms de domaine ou de comptes sociaux** contenant des marques Riot ; pas de marques Riot comme **mots-clés**.
- Mention à afficher : « [titre] was created under Riot Games' "Legal Jibber Jabber" policy using assets owned by Riot Games. Riot Games does not endorse or sponsor this project. »

**Pour Faille** : Faille affiche des **icônes de champions, d'objets, de runes et de sorts** (Data Dragon) : c'est exactement l'IP visée par la règle « pas dans les applis ». Sur l'App Store, la voie prévue est donc le **statut de projet API** (clé valide, produit enregistré) ou une licence écrite. « Echap Studio » comme vendeur = « entité juridique » au sens de la politique si c'est une société.

**Risque** : moyen en gratuit (Riot tolère beaucoup d'applis compagnons, mais la règle écrite est claire), élevé en monétisé.

**Parade** : (1) enregistrer le produit (§1) et obtenir une clé de production si Riot l'accorde (Faille pourrait utiliser une API officielle utile, ex. données statiques, mais ne pas inventer un usage artificiel : poser la question) ; (2) afficher les deux mentions (Legal Jibber Jabber + boilerplate du portail) ; (3) aucune marque Riot dans le nom, l'icône, le domaine, les comptes sociaux ; (4) garder en réserve un **mode sans icônes Riot** (monogrammes et textes : l'appli sait déjà le faire pour les logos) si Riot refuse.

## 3. Statut des flux lolesports (`persisted/gw`, `livestats`)

**Sources** :
- https://developer.riotgames.com/docs/lol (aucune mention de lolesports.com ni de ses flux ; esport = API de tournois seulement ; interdiction des applis « data broker » entre l'API et une société tierce).
- https://developer.riotgames.com/terms (conditions de l'API, mise à jour indiquée : 09/12/2013) : accès « only … with the API Key(s) provided to You by Riot » ; facturer l'accès aux « Game Information » (qui inclut les données d'événements compétitifs) demande l'**accord écrit préalable** de Riot ; ingénierie inverse interdite ; licence résiliable « at any time for any reason ».
- https://riotesportsdata.com/league-of-legends : les données en direct, le calendrier (« fixture ») et l'audiovisuel sont « only available for commercial purposes through GRID » ; un accès non commercial pour la communauté est « en préparation », sans date.
- Documentation communautaire : https://vickz84259.github.io/lolesports-api-docs/ (non officielle).

**Ce que ça dit** : les points d'accès `esports-api.lolesports.com/persisted/gw/*` et `feed.lolesports.com/livestats/v1/*` sont ceux du **site officiel**, non documentés pour les tiers, sans conditions publiées, avec une clé publique envoyée à chaque visiteur. Aucune autorisation explicite n'existe pour un usage par une appli tierce ; Riot réserve explicitement l'usage **commercial** des mêmes données (live + calendrier) à son partenaire exclusif **GRID**.

**Pour Faille** : c'est la base de toute l'appli (calendrier, direct, stats). En gratuit, Faille ressemble aux nombreux projets communautaires qui utilisent ces flux depuis des années ; Riot peut les couper ou les changer sans préavis (migration GraphQL évoquée dans la spec §14). En monétisé, Faille vendrait (directement ou par la pub) un service bâti sur des données dont Riot dit qu'elles ne sont commerciales **que** via GRID.

**Risque** : moyen-élevé en gratuit (coupure technique, demande de retrait à Apple via 5.2.2) ; **élevé en monétisé : c'est le risque n° 1** (demande de retrait, éventuelle réclamation).

**Parade** :
- Poser la question **par écrit** à Riot (portail développeur / Developer Relations) avant la sortie publique, en décrivant précisément les flux et les volumes (le serveur de la phase 2 **réduit** la charge : une boucle partagée à ~15 req/min au lieu d'une par téléphone).
- **Ne pas redistribuer** le flux brut par le serveur Faille (le serveur ne pousse que l'état calculé de la Live Activity et arbitre les pronos ; l'appli lit lolesports elle-même) : limite l'effet « data broker ».
- Sobriété (déjà en place : cache, 80 s, recul exponentiel, User-Agent identifiable côté serveur).
- Garder toute la dépendance dans `LoLKit/API` pour pouvoir brancher une source licenciée (GRID) sans toucher au reste.
- Aucune monétisation tant qu'il n'y a pas de réponse écrite favorable (§4).

## 4. GRID : la voie officielle des données esport

**Sources** : https://riotesportsdata.com/league-of-legends ; https://grid.gg/riot-games-and-grid-announce-exclusive-global-esports-data-partnership/ (partenariat exclusif mondial, nov. 2023) ; https://grid.gg/open-access/ ; https://grid.gg/solutions/media-publishers/.

**Ce que ça dit** : GRID est le distributeur exclusif des données esport de LoL (direct, calendrier, audiovisuel) pour l'usage commercial. Les offres sont **sur devis** (« custom-priced ») ; une offre « Media » couvre API en direct et WebSocket, et exclut les usages de paris. La page « Open Access » de GRID ne permet pas de confirmer, à la date de lecture, une offre gratuite couvrant **League of Legends** en direct pour une appli commerciale ; la donnée des équipes est distribuée **après la game** pour l'intégrité sportive. La LCK n'est disponible que pour un usage « médias » selon la page Riot.

**Pour Faille** : c'est la seule voie clairement licite pour une appli **monétisée** qui montre le direct. Coût inconnu (probablement hors de portée d'une petite appli au départ), mais une offre « créateurs / communauté » peut exister : il faut demander.

**Risque** : sans objet en gratuit ; en monétisé, risque d'**accès** (refus, prix) plutôt que juridique.

**Parade** : écrire à GRID (formulaire « Talk to Sales », sales@grid.gg ; partenariats : partners@grid.gg) avec le profil de Faille (appli compagnon de fans, iOS, audience visée, pas de paris) et demander : offre Open Access / créateurs pour LoL, conditions d'usage en appli mobile, monétisation permise, prix, délai de la donnée en direct.

## 5. Data Dragon, logos d'équipe, Leaguepedia

**Sources** : https://developer.riotgames.com/docs/lol (section Data Dragon : données et images « can be used by third-party developers » ; la politique autorise « Game-Specific static data ») ; politiques générales (§1) ; Legal Jibber Jabber (§2) ; Leaguepedia : https://lol.fandom.com (pied de page de licence, à vérifier) et conditions Fandom https://www.fandom.com/terms-of-use.

**Pour Faille**
- **Data Dragon** (icônes de champions, objets, runes, sorts) : permis pour les produits **enregistrés** dans le cadre des politiques ; c'est de l'IP de Riot dans une appli (§2) → dépend de l'enregistrement.
- **Logos d'équipe** (servis par lolesports) : ce sont des **marques des équipes** (KC, T1…), pas de Riot. Un usage d'identification dans un contexte de résultats est courant, mais Apple 5.2.1 interdit d'utiliser des marques de tiers « without permission » ; risque surtout si une équipe se plaint, ou si un logo sert de visuel marketing (captures, icône).
- **Leaguepedia** (sorts d'invocateur des games terminées) : contenu du wiki réputé sous **CC BY-SA 3.0** (à confirmer sur le pied de page de lol.fandom.com) ; conditions de Fandom pour l'API ; le wiki limite le débit (l'appli fait déjà une requête par match).

**Risque** : faible-moyen (gratuit), moyen (monétisé).

**Parade** : enregistrement Riot ; ligne d'attribution dans À propos (« Données complémentaires : Leaguepedia, CC BY-SA ») ; pas de logo d'équipe dans l'icône, le nom, ni comme élément principal des captures de la fiche (préférer les écrans avec monogrammes) ; supprimer un logo sur simple demande d'une équipe ; vérifier la licence et les conditions de l'API Leaguepedia avant la sortie publique.

## 6. App Store Review Guidelines

**Source** : https://developer.apple.com/app-store/review/guidelines/ (lue le 15/10/2026 ; la page ne donne pas de date).

| Règle | Ce qu'elle dit | Pour Faille | Risque | Parade |
|---|---|---|---|---|
| **5.2.2** Services tiers | Si l'appli utilise ou affiche le contenu d'un service tiers, il faut y être « specifically permitted » par ses conditions ; « Authorization must be provided upon request. » | Toute l'appli affiche le contenu de lolesports.com. Si Apple (ou Riot via Apple) demande l'autorisation, Faille n'a rien d'écrit aujourd'hui. | **Moyen** (gratuit) / **élevé** (monétisé) | Obtenir une trace écrite de Riot (§1-3) avant la sortie publique ; notes de relecture honnêtes. |
| **5.2.1** Propriété intellectuelle | Pas de marques ou œuvres protégées de tiers « without permission », pas de nom ou métadonnées trompeurs. | Icônes Data Dragon, logos d'équipe, mots « League of Legends » / « LoL ». | Moyen | Mention de non-affiliation, usage descriptif seulement, enregistrement Riot (§2, §5). |
| **2.3.7** Métadonnées | Nom unique ; ne pas remplir les métadonnées de « trademarked terms ». | Tentation de mettre « LoL », « Worlds », « LEC » dans le nom ou les mots-clés. | Moyen | Nom « Faille » ; sous-titre générique (« Esport en direct, sans spoiler ») ; marques seulement dans la description, de façon descriptive (« compatible avec les compétitions de League of Legends »), jamais en mots-clés (aussi interdit par Legal Jibber Jabber). |
| **4.2** Fonctionnalité minimale | Plus qu'un site web reconditionné. | Widgets, Live Activity, anti-spoiler, pronos : largement au-dessus. | Faible | — |
| **4.1** Copies | Pas d'imitation d'une autre appli. | Ne pas copier l'apparence de l'appli officielle LoL Esports ni le nom d'une appli de pronos existante. | Faible | DA Faille propre (Échap). |
| **1.2** Contenu généré | Filtre, signalement avec réponse rapide, blocage, contact publié. | Pseudos et noms de ligue (phase 2.2). | Faible si fait | Prévu dans la spec phase 2 §2.6. |
| **4.5.4** Notifications | Jamais indispensables ; pas de données sensibles ; pas de promotion sans opt-in explicite et désinscription. | Notifications de début et de résultat. | Faible | Désactivées par défaut (début) ; résultat masqué par défaut ; jamais de pub. |
| **4.8** Connexion | Une connexion tierce (Google, Facebook…) impose une option équivalente respectueuse de la vie privée. | Seulement compte anonyme + Sign in with Apple. | Nul | Ne pas ajouter d'autre fournisseur. |
| **5.1.1(i)** Politique de confidentialité | Lien obligatoire dans App Store Connect **et** dans l'appli. | Obligatoire même sans collecte. | Faible si fait | Page publiée (checklist de demain, étape 2), lien dans Réglages. |
| **5.1.1(v)** Suppression de compte | Si l'appli permet de créer un compte, elle doit permettre de le supprimer dans l'appli. | Comptes anonymes + Sign in with Apple (phase 2.2). | Faible si fait | `DELETE /v1/me`, bouton dans Réglages, révocation Sign in with Apple. |
| **5.1.2** Usage et partage, ATT | Pas de partage de données personnelles sans permission ; traçage → App Tracking Transparency. | Pas de traçage prévu. Une régie publicitaire ou un outil d'analyse tiers changerait tout (ATT, étiquettes, consentement RGPD). | Faible (sans pub) / moyen (avec pub) | Pas de SDK publicitaire ni d'analyse tiers sans relecture de ce point. |
| **3.1.1** Achats intégrés | Débloquer des fonctions ou du contenu (abonnements…) = achat intégré obligatoire ; pourboires possibles en achat intégré. | Seulement si monétisation. | — | Achat intégré d'Apple uniquement ; jamais de déblocage par code ou paiement externe. |
| **5.3** Jeux, concours | Concours sponsorisés par le développeur ; règlement dans l'appli précisant qu'Apple n'est pas impliqué ; pas d'achat intégré pour des jeux d'argent réel. | Ligues de pronos. | Faible tant que sans lots | §7. |

**Étiquettes de confidentialité et manifeste** : déclarer exactement ce qui est collecté (spec phase 2 §4) — avant le serveur : « Données non collectées » ; avec le serveur : identifiant utilisateur, contenu utilisateur (pronostics, pseudo), sans traçage. Fichier `PrivacyInfo.xcprivacy` dans l'appli et l'extension (données collectées + API à « raison requise » ; aucune trouvée dans le code au 15/10). Sources : https://developer.apple.com/app-store/app-privacy-details/ et https://developer.apple.com/documentation/bundleresources/privacy-manifest-files.

**Notes de relecture** (champ « Notes » de la soumission) : expliquer l'anti-spoiler (pourquoi des scores n'apparaissent pas), qu'il faut un match en direct pour voir la Live Activity (fournir une vidéo ou des captures), et que les données viennent des flux publics de lolesports.com avec la démarche en cours auprès de Riot. Fournir des captures sans logos d'équipe en premier plan.

## 7. Pronostics, paris et concours

**Sources** : politiques Riot (§1 : « cannot feature betting or gambling functionality ») ; Apple 5.3 (§6) ; en France, les jeux d'argent et de hasard sont encadrés par l'ANJ (https://anj.fr) et les loteries/concours par le Code de la sécurité intérieure (art. L320-1 et suivants) — *à faire confirmer par un avocat si des lots sont envisagés*.

**Pour Faille** : des pronostics **gratuits, sans mise, sans lot, sans achat pour jouer**, entre amis, ne sont ni un pari ni une loterie dans l'esprit de ces règles. Tout ajout de valeur (lots, achat de « jokers », points achetables, classement public doté) change la qualification.

**Risque** : faible tant que gratuit sans lot ; élevé avec lots ou mises.

**Parade** : texte « Pour le plaisir : aucun argent, aucun lot » sur l'écran des ligues ; aucun achat intégré lié aux pronos ; pas de cotes affichées ; pas de lien vers des sites de paris (ni publicité de paris : la monétisation par la pub devra exclure cette catégorie dans la régie).

## 8. Nom, marques, fiche App Store

**Sources** : Apple 2.3.7 et 5.2.1 (§6) ; Legal Jibber Jabber (§2) ; recherche de marques : https://data.inpi.fr et https://www.tmdn.org/tmview (EUIPO), classes de Nice 9 (logiciels) et 41 (divertissement).

**Pour Faille**
- « Faille » est un mot courant du français ; en France, « la Faille de l'invocateur » est le nom de la carte de LoL (IP de Riot) : **ne jamais l'écrire en entier** dans le nom, le sous-titre ou le visuel ; « Faille » seul est un mot générique, défendable, mais **non vérifié** comme marque disponible.
- Pas de « LoL », « League », « Worlds », « LEC », « Riot » dans le nom, l'icône, le domaine, les comptes sociaux, les mots-clés.
- **« Mon Petit Prono »** est le nom d'une appli de pronostics de football existante : ne pas l'utiliser comme nom de fonction (nom de travail : « Pronos », « Ligue de potes »).
- Mention recommandée (À propos, description de la fiche, site) :
  > « Faille n'est pas approuvée ni sponsorisée par Riot Games et ne reflète pas les opinions de Riot Games ni de quiconque officiellement impliqué dans la production ou la gestion de League of Legends. League of Legends et Riot Games sont des marques ou des marques déposées de Riot Games, Inc. Faille a été créée dans le cadre de la politique « Legal Jibber Jabber » de Riot Games en utilisant des ressources appartenant à Riot Games. Les logos des équipes appartiennent à leurs propriétaires respectifs. »
  (Version anglaise : reprendre **mot pour mot** le texte du portail développeur et celui de Legal Jibber Jabber.)

**Risque** : faible-moyen.

**Parade** : recherche INPI/EUIPO avant d'acheter le domaine et de créer la fiche ; vérifier la disponibilité du nom dans App Store Connect (un nom pris est refusé à la création) ; dépôt de marque « Faille » (INPI, ≈ 190 € pour une classe, à vérifier) seulement si l'appli décolle.

## 9. Confidentialité et RGPD

**Sources** : Apple 5.1.1 / 5.1.2 (§6) ; RGPD (règlement UE 2016/679), art. 5 (minimisation, conservation limitée), 12-22 (droits), 30 (registre) ; CNIL : https://www.cnil.fr/fr/rgpd-par-ou-commencer.

**Pour Faille** : sans serveur, aucune donnée personnelle ne quitte le téléphone. Avec le serveur : identifiants pseudonymes, jetons de push, suivis, pronostics, pseudos → données personnelles au sens du RGPD (même sans nom ni e-mail). Détail dans la spec phase 2 §4 (conservation, droits, sous-traitants, mineurs).

**Risque** : faible si la spec est suivie ; moyen avec publicité (consentement, ATT, sous-traitants hors UE).

**Parade** : politique de confidentialité en français et en anglais, versionnée (2.0 sans collecte, 2.1 avec serveur) ; export et suppression dans l'appli ; registre d'une page ; hébergement UE ; pas de SDK tiers sans revue.

## 10. Vendeur, statut DSA, programme Apple

**Sources** : https://developer.apple.com/programs/enroll/ ; https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements.

**Ce que ça dit** : en **individuel**, le **nom légal** de Dan s'affiche comme vendeur ; en **organisation**, il faut une **personne morale** avec **numéro D-U-N-S** et site web sur son domaine, et Apple **n'accepte pas les noms commerciaux** (« DBAs, fictitious business names, trade names »). Le **DSA** impose à chaque compte de déclarer s'il est « commerçant » ; un commerçant voit son **adresse, téléphone et e-mail publiés** sur les fiches UE.

**Pour Faille** : « Echap Studio » ne peut être vendeur que si c'est une société immatriculée. En gratuit sans activité commerciale, « non-commerçant » est défendable ; dès qu'il y a monétisation (ou si Echap Studio est une activité professionnelle), « commerçant ».

**Risque** : faible (mais exposition des coordonnées personnelles si mal préparé).

**Parade** : individuel demain si pas de société ; adresse et numéro professionnels (domiciliation) avant de passer commerçant ; migration vers un compte organisation avant la monétisation si une société est créée.

---

## 11. Questions à vérifier ou à poser (par Dan)

### À Riot (portail développeur / Developer Relations — par écrit, garder les réponses)
1. Une appli iOS **gratuite**, enregistrée sur le portail, peut-elle utiliser les points d'accès publics de lolesports.com (`esports-api.lolesports.com/persisted/gw` : `getSchedule`, `getLive`, `getEventDetails`, `getStandings`… et `feed.lolesports.com/livestats/v1/window|details`) avec la clé publique du site ? Quelles limites de débit ?
2. Même question si l'appli est **monétisée** (abonnement de soutien, achats intégrés, publicité) : faut-il passer par **GRID** pour le calendrier et le direct, même affichés à des fans ?
3. Un **serveur** qui lit ces flux une fois pour tous et pousse seulement un résumé (score, kills, gold, tours, drakes, barons) en notification / Live Activity est-il acceptable, ou considéré comme de la redistribution (« data broker ») ?
4. Pour une appli sans usage de l'API officielle, quel statut viser (Acknowledged / Approved) et une clé de production est-elle nécessaire pour remplir la condition « valid API key » de Legal Jibber Jabber pour l'App Store ?
5. Les **icônes Data Dragon** (champions, objets, runes, sorts) et le **nom « Faille »** posent-ils problème (« Faille de l'invocateur » étant le nom français de Summoner's Rift) ?
6. Les ligues de **pronostics gratuites sans lots** entre amis sont-elles compatibles avec l'interdiction des paris ?
7. Quel texte de mention exact Riot attend-il sur une fiche App Store (FR et EN) ?

### À GRID (sales@grid.gg / partners@grid.gg) — seulement si monétisation envisagée
8. Existe-t-il une offre « Open Access » / créateurs couvrant **League of Legends** (calendrier, résultats, direct) pour une appli mobile ? Usage commercial permis ? Prix, délai de la donnée, régions (LCK « médias seulement ») ?
9. Conditions d'affichage (attribution, logos d'équipe, stockage, durée de conservation) et interdits (paris, revente).

### À vérifier soi-même
10. Disponibilité de « Faille » : App Store Connect, INPI (classes 9 et 41), EUIPO/TMview ; domaines et comptes sociaux.
11. Licence exacte de Leaguepedia (pied de page de lol.fandom.com) et conditions de son API (Fandom).
12. Echap Studio : personne morale ou non ? D-U-N-S ? → individuel ou organisation chez Apple ; statut DSA.
13. Texte définitif de la page de confidentialité et des étiquettes App Store (d'après la spec phase 2 §4) avant chaque phase.

### À un avocat (avant toute monétisation)
14. Risque de monétiser une appli bâtie sur les flux lolesports sans accord écrit (contrefaçon, parasitisme / concurrence déloyale, droit *sui generis* des bases de données — directive 96/9/CE — sur le calendrier et les stats).
15. Statut des logos d'équipe et de l'usage des marques Riot à titre descriptif dans la fiche.
16. Pronos avec éventuels lots ou partenariats (loteries, ANJ) ; conditions générales d'utilisation et mentions légales (LCEN) ; responsabilité du contenu généré (pseudos, ligues) au regard du DSA.

---

## Sources citées

- Riot — politiques générales : https://developer.riotgames.com/policies/general
- Riot — Legal Jibber Jabber : https://www.riotgames.com/en/legal · https://riotgames.com/legal-jibber-jabber
- Riot — conditions de l'API : https://developer.riotgames.com/terms
- Riot — docs LoL (Data Dragon, tournois, « data broker ») : https://developer.riotgames.com/docs/lol
- Riot / GRID — données esport : https://riotesportsdata.com/league-of-legends
- GRID — partenariat exclusif : https://grid.gg/riot-games-and-grid-announce-exclusive-global-esports-data-partnership/
- GRID — Open Access : https://grid.gg/open-access/ · offres médias : https://grid.gg/solutions/media-publishers/
- Docs communautaires lolesports (non officielles) : https://vickz84259.github.io/lolesports-api-docs/
- Dev diary LoL Esports Data Portal : https://lolesports.com/en-US/news/dev-diary-introducing-the-new-lol-esports-data-portal
- Apple — App Review Guidelines : https://developer.apple.com/app-store/review/guidelines/
- Apple — inscription au programme : https://developer.apple.com/programs/enroll/
- Apple — DSA (commerçant) : https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements
- Apple — étiquettes de confidentialité : https://developer.apple.com/app-store/app-privacy-details/
- Apple — manifeste de confidentialité : https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- Fandom — conditions : https://www.fandom.com/terms-of-use
- INPI : https://data.inpi.fr · EUIPO TMview : https://www.tmdn.org/tmview · ANJ : https://anj.fr · CNIL : https://www.cnil.fr/fr/rgpd-par-ou-commencer
