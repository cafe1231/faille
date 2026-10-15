# Faille — audit « pixel perfect » (15/10/2026)

Audit en lecture seule (aucun code modifié). Sources : les 57 planches PNG de la dernière CI (`apercus-final2`, 804 × 1748 px = 402 × 874 pt à ×2 ; widgets et Live Activity à ×3), la spec §9 (DA), la spec Finitions (Motion, tokens), les maquettes `docs/maquettes/`, le code d'`origin/main` (`2ebd369`) et les registres (`.superpowers/sdd/*/final-review.md`, `progress.md`, journaux, checklist iPhone).

Mesures : en points (pt), lues sur les planches (1 pt = 2 px), à ± 1 pt. Les numéros de ligne renvoient à `origin/main`.

Gravité :
- **[V] défaut visible** : se voit au premier coup d'œil (coupé, débordé, mal aligné, faux).
- **[P] polish** : incohérence ou finition qu'un œil exercé remarque.
- **[N] nit** : détail, à faire si l'on passe par là.

Bilan : **21 [V]**, **44 [P]**, **28 [N]** (93 entrées) (sections B et C ; les entrées de la section D renvoient à B/C ou aux registres et ne sont pas recomptées).

---

## A. Conformité au système de design

| Domaine | Référence (spec §9, finitions, maquettes ×1,355) | Constat dans le code et les planches | Écarts |
|---|---|---|---|
| **Gouttière d'écran** | 16 pt (maquette 12 px) | 16 pt partout (`.padding(.horizontal, 16)`) | Onboarding 20 pt (`OnboardingView.swift:80,123`) ; feuille « Comment c'est calculé » 20 pt (`MustWatchSection.swift:72`) |
| **Espacement entre cartes** | 14 pt (maquette 10 px) | `VStack(spacing: 14)` sur tous les écrans | conforme |
| **Échelle d'espacement interne** | aucune échelle nommée (valeurs libres) | 13 valeurs utilisées : 0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 18 | pas de token `Spacing` ; 3 et 5 font doublon avec 2/4/6 |
| **Padding des cartes** | carte 16 pt, élément interne 14 pt (maquette 12/10 px) | `glassCard` : 16 (cartes Vitrail), 14 (×39), 12 (×13), 10 (×2), 4 (×3 boutons) | Les cartes d'une même colonne n'ont pas le même retrait : « À ne pas rater » (liste) 12 pt contre cartes d'équipe 16 pt → libellés à x = 28,5 / 32,5 pt sur 01 ; sections de l'Accueil 12, pages saison 14, carte « Classement masqué » 10 |
| **Rayons** | 28 pt cartes, 22 pt internes | `Radius.card` / `Radius.inner` respectés par `glassCard` | Hors échelle : 6 (sorts, `PlayerSheet.swift:245`), 12 (case du mois `MonthGrid.swift:40`, ligne suivie du classement `StandingsTables.swift:25`), 14 (jour du bandeau `WeekStripSection.swift:68`), 15 (champs de recherche `TeamsView.swift:88`, `OnboardingPages.swift:56`, `DuelPicker.swift:22`), 18 (tuiles d'onboarding `OnboardingPages.swift:83-84`) |
| **Typo : famille et graisses** | Sora 400/500/600/700 | Sora variable, axe `wght` (`Typography.swift`) | conforme |
| **Typo : échelle** | 32/700 −0,04 em ; 15 ; 12 ; 11 capitales espacées | `Typo` + `SoraStyle` (Dynamic Type plafonné AX2) | `PillButton` reste en `Typo` fixe (`Components.swift:107`) : **aucune pilule ne grandit** avec le texte ; tailles fixes 9 pt (niveau, `BuildPlayersPanel.swift:106`), 11 pt (ordre des sorts, `PlayerSheet.swift:241`) ; `.label` (11, semibold, prévu en capitales) utilisé en casse mixte dans 9 endroits (métriques du duel, « Changer », « aucune game lue », « sur N games », « 5 games », « estimé ») |
| **Couleurs** | Abysse, texte, secondaire, accent `#6fd3ff` | `Palette` respectée | Blancs à opacité en dur dispersés (0,04 / 0,05 / 0,06 / 0,07 / 0,08 / 0,09 / 0,10 / 0,14 / 0,92) hors de `Palette` ; accent utilisé pour du texte non touchable (« Notifications refusées par iOS… ») |
| **Contraste** | — | secondaire `#94a0bf` sur abysse ≈ 7,3:1 ; sur verre ≈ 5:1 | Pastille accent sur le jour choisi (fond blanc 92 %) ≈ 1,5:1 (`WeekStripSection.swift:78-80`, `MonthGrid.swift:32-34`) |
| **Verre** | `.ultraThinMaterial` + dégradé 160° + reflet + arête + ombre ; Liquid Glass réservé aux barres | `GlassCard` conforme ; barre d'onglets et « Fermer » en Liquid Glass | Contrôles segmentés et interrupteurs **système** (Réglages, notifications, joueurs du Détail) : seul élément non DA des écrans |
| **Icônes** | trait 1,8, grille 24, jamais d'emoji | jeu complet, `IconView` décoratif | 10 tailles (8, 11, 12, 13, 14, 15, 16, 18, 20, 22) sans échelle ; « Part des dégâts » porte l'icône des kills (`PlayerSheet.swift:43`) |
| **Monogrammes** | badge bordé, code 30 % de la taille | `TeamBadge` 20 → 54 pt | Monogramme de joueur (cercle, `TeamRosterCard`, page joueur) ≠ badge d'équipe (carré arrondi) : voulu ; vignette de champion de repli = carré gris 22 % (même famille que les tuiles de squelette) |
| **Zones tactiles ≥ 44 pt** | finitions §2 | œil, étoile, engrenage, flèches du mois, « Regarder » compact, « Tout le fil », zones d'équipe : 44 pt | **< 44 pt** : toutes les `PillButton` ≈ 29 pt (games, ligues, périmètres, onglets du duel, joueurs en forme), `RevealButton` ≈ 23 pt (`MatchParts.swift:218`), « Changer » 32 pt (`DuelBars.swift:121`), « Choisir mes équipes » ≈ 40 pt (`MatchesView.swift:88-89`, `HomeView.swift:132-133`), lignes `MatchLine` ≈ 38 pt |
| **Mouvement** | `Motion` : aucune durée en dur | aucune durée en dur hors `Motion.swift` | `CascadeIn` appelle `Motion.list` directement (`LiveEffects.swift:91`, gardé par `shown`) ; transition d'onboarding écrite en ligne (`OnboardingView.swift:84`) |
| **Chiffres et tirets** | « 1 – 0 » (`Format.score`) | voir B-G4 | 5 conventions : « 1 – 0 », « 1–0 », « 1-0 », « 7 – 4 », « 9-0 » ; signe moins « - » (`Format.gold`) contre « − » (`SeasonFormat.signed`) |
| **Heure de Paris** | heures locales | appli : `TimeZone.current` ; planches de l'appli rendues en **UTC** | voir B-G5 |

---

## B. Défauts par écran

Format : **[gravité]** observation (planche, mesure) → correctif proposé (fichier:ligne).

### B-G. Transverses (plusieurs écrans)

- **B-G1 [P]** Pilules : hauteur ≈ 29 pt, police fixe, capsule qui ne glisse que dans le Détail. → `PillButton` (`Components.swift:96-125`) : `.sora(selected ? .secondaryMedium : .secondary)`, `.lineLimit(1).fixedSize()`, zone tactile 44 pt (`.padding(.vertical, 7)` sur la capsule puis `.frame(minHeight: 44).contentShape(Rectangle())`), et un `Namespace` passé par tous les groupes (duel, joueurs en forme, périmètres).
- **B-G2 [P]** Défilements horizontaux rognés au retrait de la carte ou de la gouttière, au lieu de déborder jusqu'au bord : pilules de games (`MatchDetailView.swift:283`), périmètres de la page joueur (`PlayerPageView.swift:97`), ligues de l'onboarding (`OnboardingPages.swift:36`), types de drakes (« M… » coupé sur 26-bas, `TeamPageSections.swift:155`), bandeau de la semaine (8e jour coupé net à 12 pt du bord, 25, `WeekStripSection.swift:27`). → le motif déjà juste de `TeamsView.swift:126-138` / `TeamPageView.swift:159-174` : `.scrollClipDisabled()` + `.contentMargins(.horizontal, X, for: .scrollContent)` + `.padding(.horizontal, -X)`.
- **B-G3 [P]** Séparateurs « · » d'espacement inégal : « Regarder ␣·␣Français » 7 pt avant le point contre 4,5 pt ailleurs (16, 04) ; « Score masqué · ␣␣toucher » (01, 06). Cause : `HStack(spacing:)` + espaces littéraux. → un seul `Text` concaténé (`Text("Regarder") + Text(" · …").foregroundStyle(…)`) : `WatchButtons.swift:56-60, 94-98`, `MatchParts.swift:209-213`, `TeamPageSections.swift:314-317`.
- **B-G4 [P]** Tirets et signes : « 1 – 0 » (Détail, cartes), « 1-0 » (Dynamic Island minimale, `LiveActivityDisplay.swift:194`), « 1–0 » (widget en ligne), « 7–4 » (Live Activity), « 7 – 4 » (`MiniStats`, `MatchParts.swift:146`), « 9-0 » / « 3-2 » (bilans, `SeasonFormat.swift:34`, `StandingsTable.swift:48,144`) ; « -3k », « -800 » (`Format.swift:10`) contre « −750 » (`SeasonFormat.swift` `signed`) ; « +2,1 k » (onboarding, `OnboardingExampleCard.swift:54`) contre « +2,1k ». → règle unique : score « 1 – 0 » (tiret demi-cadratin, espaces fines insécables en compact), bilans V–D « 9–0 », signe moins U+2212 partout (`Format.gold`), « +2,1k ».
- **B-G5 [P]** Heure de Paris : les planches de l'appli sont rendues en UTC (25b « ven. 16 oct. · 09:00 » contre « ven. 11:00 » sur le widget du même match ; bandeau « màj 15:05 » = 15:05 UTC), donc les heures des planches ne se vérifient pas. Sur l'iPhone, `TimeZone.current` donne Paris : pas de bug utilisateur, mais `MatchLine` mélange `Format.matchDate` (24 h forcé) et `formatted(date: .omitted, time: .shortened)` (12 h si l'iPhone est réglé ainsi) (`SeasonParts.swift:212-213`). → `Format.time` partout ; `@Environment(\.timeZone)` lu par `MatchLine`, l'en-tête du Détail et le bandeau, et fixé à `Europe/Paris` dans le support des planches (comme `WidgetBoard.swift:150-156`).
- **B-G6 [P]** Lexique anti-spoiler non unifié : « masqué » (appli), « Score masqué · toucher pour révéler », « Terminé · toucher pour révéler », « Prochain · masqué » / « Match à venir · masqué », « Sans spoiler · ouvre l'appli pour révéler » (Live Activity, `LiveActivityDisplay.swift:106`), « Masqué / Anti-spoiler » (widget rectangulaire, `WidgetText.swift:142`), « sans spoiler » (ligne de « Mes équipes », `TeamRows.swift:52`). → un seul mot visible, « masqué » : « Score masqué · ouvre Faille pour révéler » (LA), « Prochain · masqué » (widget), « LCK · masqué » (ligne d'équipe).
- **B-G7 [P]** « Live Activity / Live Activities » en anglais, et les deux formes dans la même phrase : « Live Activities désactivées : Réglages › Faille › Activités en direct. » (`LiveActivityPinButton.swift:55`, aussi `:58`, `SettingsView.swift:14-16`, diagnostic). iOS en français dit « Activités en direct ». → « Activité en direct » dans toute l'interface.
- **B-G8 [P]** Postes en deux langues : « TOP / JGL / MID / BOT / SUP » (joueurs du Détail, fiche, `AppFormat.swift:49-54`) contre « Top / Jungle / Mid / ADC / Support » (duel, effectif, page joueur, `SeasonFormat.swift` `SeasonNames.role`). → une seule table (courte pour les lignes denses, mais mêmes mots : « Top, Jungle, Mid, ADC, Supp. »).
- **B-G9 [N]** Libellés de stats : « INHIBS » (`StatsPanels.swift:17`) / « Inhibiteurs » (page équipe) ; drake ancestral : « Ancien » (`TeamPageSections.swift:178`) / « ancestral » (`AppFormat.swift:41`) ; « Océan × 9 » capitalisé / « océan » ailleurs.
- **B-G10 [P]** Score et « vs » centrés dans l'espace restant, pas au centre de la carte : « vs » 5 pt à gauche sur 06 (T1 étroit, FLY large), tirets des scores qui dansent de 4-5 pt d'une ligne à l'autre (02, 25, 30). La Live Activity, elle, a des côtés de même largeur. → `ScoreRow` (`MatchParts.swift:86-114`) et `MatchLine.row` (`SeasonParts.swift:152-157`) : côtés `.frame(maxWidth: .infinity, alignment: .leading/.trailing)`, centre `.fixedSize()`.
- **B-G11 [P]** Texte d'accent non touchable : « Notifications refusées par iOS : Réglages › Faille › Notifications. » ressemble à un lien (17, 31). → bouton qui ouvre `UIApplication.openNotificationSettingsURLString`, ou couleur secondaire (`MatchRemindersSection.swift:95-97`, `LeagueFollowRow.swift:45-47`).
- **B-G12 [N]** Contraste de la pastille accent sur le jour choisi (≈ 1,5:1) → pastille `Palette.abyss` quand le jour est choisi (`WeekStripSection.swift:78-80`, `MonthGrid.swift:32-34`).

### Matchs (01, 02, 08, 33b)

- **B-M1 [V]** « À ne pas rater » : le point de l'équipe s'affiche entre l'étiquette et « Comment c'est calculé » (« ● Comment c'est calculé », 01, 08, 33b, 25), alors que partout ailleurs il est au bord droit. Cause : `SectionLabel(dot:)` met le point après son `Spacer`, puis le bouton suit. → `MustWatchSection.swift:22-29` : `SectionLabel` sans point, puis `Spacer`, le lien, et `GlowDot` en dernier (ou un paramètre `trailing` dans `SectionLabel`, `Components.swift:44-62`).
- **B-M2 [P]** Retrait de « À ne pas rater » (liste) 12 pt contre 16 pt pour les cartes d'équipe juste dessous : libellés décalés de 4 pt (01). → `MustWatchSection.swift:45-46` : 16 et `Radius.card` dans les deux styles.
- **B-M3 [P]** Titre « Mes équipes » sur l'onglet « Matchs », à côté d'un onglet « Équipes » (01, 02). → titre « Matchs », sous-titre « 2 en direct · 0 à venir » (`MatchesView.swift:25`).
- **B-M4 [N]** Rythme vertical de la carte en direct : « Regarder » (pastille 26 pt dans un cadre tactile de 44 pt, `WatchButtons.swift:53`) laisse 9 pt invisibles au-dessus et au-dessous ; écart « Regarder » → « Dernier » ≈ 27 pt contre 10 pt entre les autres lignes (01, 24). → `TeamCardView.swift:137-139` : retrait vertical négatif de 9 pt sur la pastille (la forme tactile reste de 44 pt) ou espacement de la carte réduit autour d'elle.
- **B-M5 [P]** « Choisir mes équipes » : 40 pt de haut (02). → `.frame(minHeight: 44)` (`MatchesView.swift:88-89`, même bouton `HomeView.swift:132-133`).
- **B-M6 [N]** Carte GEN : « Prochain · masqué » au-dessus de « Dernier · GEN 3 – 0 HLE » (règle C juste, mais la lecture semble contradictoire). → sous-texte « (adversaire masqué) » ou icône d'aide ; à trancher par Dan.

### Équipes (03, 03b, 31)

- **B-E1 [P]** Squelette du catalogue sans la carte « Suivre la ligue » : la liste saute d'environ 80 pt au chargement (03b → 03). → `LeagueLoadingSkeleton` (`Skeleton.swift:180-193`) : un bloc de 66 pt entre les pilules et les lignes.
- **B-E2 [P]** « Suivre la ligue » et « Suivre ses 8 équipes » côte à côte : deux verbes identiques, deux sens (31, 03). En état suivi, l'interrupteur arrive à 10 pt du bord de la carte contre 12 pt pour le texte. → « Suivre la ligue » / « + ses 8 équipes » ; interrupteur dans le même retrait (`LeagueFollowRow.swift:19-53`).
- **B-E3 [N]** Champs de recherche : rayon 15, bordure ici et pas dans l'onboarding (`TeamsView.swift:88-89`, `OnboardingPages.swift:56`). → `Radius.inner` (ou capsule) et le même composant partagé.
- **B-E4 [N]** Ligne de catalogue sans ligue (FURIA) : une ligne, centrée verticalement, sans mention ; les lignes suivies disent « sans ligue d'attache » (`TeamRows.swift:53`, `:75`). → même mention, ou rien des deux côtés.

### Détail d'un match (04, 05, 06, 15, 16, 19, 20, 20b, 21, 22, 23)

- **B-D1 [V]** Courbe de gold : l'axe des temps continue après le dernier point (≈ 20 pt vides en direct sur 04/21, ≈ 45 pt sur un match terminé 19-bas/22 : courbe arrêtée à 32', axe jusqu'à ≈ 38'). → `GoldChartCard.swift:89` : `.chartXScale(domain: 0...(points.last?.gameTime ?? 0))` (une minute de marge en direct au plus).
- **B-D2 [V]** Axe vertical : « -3k » / « -16k » avec un trait d'union, collé au « 0' » de l'axe des temps dans l'angle bas gauche (04, 19, 22). → signe « − » (B-G4) et libellés des Y à l'intérieur du tracé ou `.chartPlotStyle { $0.padding(.bottom, 4) }` (`GoldChartCard.swift:102-112`).
- **B-D3 [P]** Repères de drakes/barons à 2 pt sous la ligne d'en-tête « ÉCART DE GOLD … KC +2,1k » : la carte paraît serrée en haut (04, 19). → `VStack(spacing: 14)` ou `.chartPlotStyle { $0.padding(.top, 6) }` (`GoldChartCard.swift:21, 81`).
- **B-D4 [P]** Types de drakes : « hextech, hextech, / infernal, hextech » sur deux lignes à droite (22) : la hauteur du panneau change d'une game à l'autre. → regrouper (« 3 hextech · infernal »), `lineLimit(1)` + `minimumScaleFactor(0.8)` (`StatsPanels.swift:48-75` ; formatage dans `AppFormat.swift:39-47`).
- **B-D5 [V]** Fiche joueur : « Objet 6 692 », « Objet 3 111 » : identifiant d'objet formaté avec un séparateur de milliers (20b, 23). → `PlayerSheet.swift:142` : `String(localized: "Objet \(String(id))")`, mieux : ne montrer que l'icône de repli tant que le catalogue manque.
- **B-D6 [V]** Ordre des sorts sans icônes : la lettre est écrite deux fois (« P » dans la tuile, « P » dessous) (20b, 23). → légende seulement quand l'icône est connue (`PlayerSheet.swift:228-234`).
- **B-D7 [P]** Grille des niveaux à 9 colonnes de 24 pt : 11 niveaux → 9 + 2 orphelins (20b), aucune indication du niveau. → 6 colonnes (3 rangées pour 18 niveaux) avec le numéro en petit, ou une rangée défilante (`PlayerSheet.swift:237-248`).
- **B-D8 [P]** « Runes indisponibles » : texte nu dans une carte, sans icône, alors que les autres états vides sont des `NoteCard` (20b). → `NoteCard(icon: .off, …)` (`PlayerSheet.swift:131-135`).
- **B-D9 [P]** Équipe des joueurs : contrôle segmenté système (20). → deux `PillButton` avec capsule qui glisse (`BuildPlayersPanel.swift:60-65`).
- **B-D10 [N]** Ligne de joueur : un seul carré de sort en haut à droite pour le jungler (Châtiment), rien pour les autres : l'élément paraît égaré (20). → réserver deux emplacements (vides en pointillé) (`BuildPlayersPanel.swift:129-133`) ; badge de niveau en 9 pt fixe (`:106`).
- **B-D11 [P]** Pilules de games : 29 pt de haut, rognées au bord de la gouttière (04). → B-G1, B-G2 (`MatchDetailView.swift:279-300`).
- **B-D12 [P]** « Score masqué · toucher pour révéler » : zone tactile ≈ 23 pt (06, 01). → `.frame(maxWidth: .infinity, minHeight: 44)` (`MatchParts.swift:217-219`).
- **B-D13 [N]** Draft déséquilibrée : code + 5 tuiles = 276 pt sur 306 pt utiles, vide à droite (04). → tuiles en `.frame(maxWidth: .infinity)` (`DraftStrip.swift:20-35`).
- **B-D14 [N]** En-tête : la pastille d'état est en `fixedSize` ; avec une ligue longue (« La Ligue Française · Saison régulière · Bo3 » + « En direct · Game 2 · 18:42 ») le méta-texte se tronque à quelques caractères. → pastille sur sa propre ligne sous le méta-texte quand elle ne tient pas (`ViewThatFits`, `MatchDetailView.swift:210-219`).
- **B-D15 [N]** Le squelette des stats n'a pas la ligne des types de drakes (≈ 16 pt de moins que le vrai panneau) et ses pilules font 48 pt contre 57 / 122 pt (15 contre 04). → `Skeleton.swift:49-68, 140-147`.

### Duel (04-bas, 05, 06, 21, 22, 27, 27b, 33)

- **B-U1 [V]** Duel sans données : chaque poste affiche « aucune game lue » ×2, « Changer » ×2 et 5 métriques « — / — » : ≈ 340 pt de tirets par poste, ≈ 1 700 pt pour les 5 postes (04-bas, 06, 21, 22, 27b). → si `duel.left == nil && duel.right == nil` : carte compacte (noms, poste, « Aucune game lue pour ce duel », « Changer »), barres masquées (`DuelBars.swift:77-105`, appel `DuelSection.swift:49-53`).
- **B-U2 [V]** Poste (« ADC », « Top »…) mal aligné : centré verticalement contre la pile nom/sous-titre/« Changer » (il tombe 6 pt sous la ligne du sous-titre), et décalé horizontalement quand les noms ont des largeurs différentes (« ADC » à x ≈ 194 pt pour un centre à 201, 33). → `HStack(alignment: .firstTextBaseline)` et les deux côtés en `frame(maxWidth: .infinity)` ; ou le poste en surimpression centrée (`DuelBars.swift:78-84`) ; même correctif pour « Cette game » (`:93-101`).
- **B-U3 [V]** Match masqué : « aucune game lue » pour des joueurs dont les games existent mais sont masquées (06, 27b) ; la page d'équipe dit « Stats masquées · 3 matchs masqués ». → sous-titre « stats masquées » quand le duel n'a rien parce que tout est masqué (`DuelBars.swift:117`, l'information vient de `Duel.players` / `seasonMasked`).
- **B-U4 [P]** Onglets « Joueurs / Équipes » : pilules de 29 pt sans glissement ; « Changer » à 32 pt (`DuelSection.swift:40-41`, `DuelBars.swift:121`). → B-G1, `minHeight: 44`.

### Accueil (25, 25b, 25c, 34)

- **B-H1 [V]** « À ne pas rater » (carte) : la première ligne est agrandie de 4 % depuis son bord gauche (`scaleEffect(1.04, anchor: .leading)`) : elle déborde de ≈ 12 pt à droite, le badge C9 arrive à 2 pt du bord de la carte, et la ligne n'a plus la même largeur que les suivantes (25, 25b, 34). → `MustWatchSection.swift:33` : supprimer l'échelle ; mettre en avant la première ligne par la taille de ses textes (`.sora(.score)` pour le score, badge 30 pt) dans la mise en page.
- **B-H2 [V]** « Joueurs en forme » : la pilule « CS/min » passe à la ligne (« CS/ » / « min ») et devient un rond de 44 pt (25-bas, 25c). → `lineLimit(1).fixedSize()` dans `PillButton` (B-G1) et les deux groupes sur deux rangées, ou la métrique en menu (`HotPlayersSection.swift:21-33`).
- **B-H3 [V]** Sous-titre « 2 matchs aujourd'hui » alors que la journée en liste 3 (25, 25b, 34). `todayCount` compte le calendrier seul, la liste du jour fusionne aussi le direct. → compter la même liste (`HomeFeed.swift:122` côté LoLKit, ou `eventsByDay[today]?.count` dans `HomeView.swift:33`).
- **B-H4 [V]** Grand texte (34) : jours du bandeau tronqués (« j… », « lu… », « … »), chiffres qui débordent de la case de 44 pt ; « À NE PAS… » tronqué ; « Comment c'est calculé » et « Tout le calendrier » sur deux lignes à côté de leur étiquette. → cases à largeur `@ScaledMetric`, jour en `.narrow` au-delà de `.xxLarge` (`WeekStripSection.swift:61-68`) ; en-têtes de section en `ViewThatFits` (étiquette puis lien dessous) (`MustWatchSection.swift:22-29`, `WeekStripSection.swift:19-25`).
- **B-H5 [P]** « En direct maintenant » : deux icônes « en direct » par ligne (halo à gauche + icône devant le score) (25, 25b, 34). → garder le halo et passer à `MatchLine` une option sans icône d'état (`LiveNowSection.swift:17-22`, `SeasonParts.swift:183-191`).
- **B-H6 [P]** Pendant la collecte, si la liste a déjà des joueurs, plus aucun signe de progression ; la planche 25c est identique octet pour octet à 25-bas. → ligne « Les stats arrivent : N games lues sur M » sous la liste tant que `remaining > 0` (`HotPlayersSection.swift:34-39`) ; planche avec une liste vide (`HomeSnapshotTests.swift:50-54`).
- **B-H7 [P]** Squelette de l'Accueil : 2 cartes génériques pour 5 à 7 sections → saut d'environ 1 000 pt à l'arrivée (`HomeView.swift:43-44`). → gabarits des sections (à ne pas rater, bandeau 7 jours, 3 lignes).
- **B-H8 [N]** Séparateur seulement entre la 1re et la 2e ligne de « À ne pas rater » (25b), pas entre la 2e et la 3e. → séparateurs entre toutes les lignes, ou aucun (`MustWatchSection.swift:39-41`).
- **B-H9 [N]** Joueurs en forme : la vignette de champion de repli (« AZ » pour Chovy) se lit comme les initiales du joueur. → sur l'appareil, Data Dragon répond ; sinon icône joueur.

### Page équipe (26, 26-bas, 26b, 26c)

- **B-T1 [V]** Titre « Karmine Corp » en 32 pt sur deux lignes dans l'en-tête (26, 26c), répété dans la barre de navigation. → `lineLimit(1)` + `minimumScaleFactor(0.6)` (ou `.sora(.score)` pour les noms > 10 caractères) (`TeamPageSections.swift:17-21`) ; titre de barre vide tant que l'en-tête est visible.
- **B-T2 [V]** Moyennes : 3e rangée désalignée (« 1,8 Drakes » et « 0,8 Barons » centrés verticalement contre « −750 / Écart de gold à 15 min / sur 4 games » : 15 pt d'écart de ligne de base) (26-bas). → `Grid(alignment: .topLeading, …)` (`TeamPageSections.swift:116`).
- **B-T3 [P]** Équipe masquée : « Calculé sur 0 game · 3 matchs masqués » puis « Stats masquées · 3 matchs masqués » juste dessous (26b). → masquer `TeamSeasonStatus` quand `allMasked` (`TeamPageView.swift:146-149`).
- **B-T4 [P]** Squelette dans un autre ordre que le contenu : moyennes et champions au-dessus de « Prochains matchs » et « Effectif » dans le squelette, en dessous dans la page → deux cartes sautent de ≈ 300 pt ; une barre de 12 pt tient la place des pilules de 29 pt (26c). → même ordre et une rangée de pilules (`TeamPageSkeleton.swift:5-17`).
- **B-T5 [N]** « Classement masqué · toucher pour révéler » : retrait 10 pt, centré, alors que les cartes voisines sont alignées à gauche avec 14 pt (26-bas). → `TeamPageSections.swift:311-325`.

### Page joueur (28, 28b)

- **B-J1 [V]** Même désalignement de la 3e rangée des moyennes (« 76 % » 9 pt plus bas que « 27 % ») (28). → `PlayerPageSections.swift:13` : `.topLeading`.
- **B-J2 [V]** « Champions joués » affiche l'identifiant brut du champion (`Text(use.champion)`) : « XinZhao », « KSante », « MonkeyKing » (les planches n'ont que des noms d'un mot). → `Format.champion(use.champion)` (`PlayerPageSections.swift:46`).
- **B-J3 [P]** « estimé » répété sur chaque ligne, et résultat « V » / « D » en lettre isolée grasse (28). → « estimé » une fois dans l'en-tête de section (« bilans estimés ») ; puce « Victoire » / « Défaite » (`PlayerPageSections.swift:44-53, 87-97`).
- **B-J4 [N]** « sur 12 games » seul en tête contre « Calculé sur 17 games » sur la page équipe ; date « 5 oct. 2026 » contre « dim. 5 oct. » ailleurs (`PlayerPageView.swift:33`, `PlayerPageSections.swift:74`).

### Classements (29, 29b, 29c)

- **B-C1 [V]** Tableau : colonne centrale qui danse (« vs » à x ≈ 193 / 194 / 200 pt, scores à 203 / 200 pt selon la largeur des codes) ; un match masqué et un match à venir s'écrivent tous deux « vs » (29c). → trois colonnes (B-G10) ; match masqué : icône œil barré + « masqué » (`StandingsTables.swift:111-123`).
- **B-C2 [P]** Carte « Classement masqué » : titre centré, paragraphe aligné à gauche (29b). → `.multilineTextAlignment(.center)` (`StandingsView.swift:61`).
- **B-C3 [P]** En-tête : grand titre `ScreenHeader` dans un écran poussé (« LEC Split 3 / Classement »), alors que les pages équipe, joueur et calendrier ont un titre de barre + carte héros. → même schéma partout (`StandingsView.swift:19`).
- **B-C4 [N]** Phase finale : ni badges ni mise en avant du vainqueur (29). → `TeamBadge` 22 pt et code du vainqueur en `.headline`.
- **B-C5 [N]** Équipe « vit » en minuscules dans la planche : données d'exemple (`SeasonSamples.swift:32, 106`).

### Calendrier (30)

- **B-K1 [N]** Case choisie : rayon 12 hors échelle (`MonthGrid.swift:40`) ; pastille accent sur blanc (B-G12).

### Réglages, À propos, Notifications (07, 07b, 17)

- **B-R1 [P]** Contrôles segmentés système « Automatique / Manuelle », « 5 / 15 / 30 min » : style iOS gris au milieu du verre DA (07, 17). → pilules DA (`SettingsView.swift:16-20`, `MatchRemindersSection.swift:83-89`).
- **B-R2 [N]** Diagnostic : identifiant de match brut à 18 chiffres qui casse la ligne, « ids » (07b). → « match KC–C9 » ou identifiant abrégé, « identifiants » (`LiveActivityDiagnostic.swift:66`).

### Onboarding (32-1, 32-2, 32-3)

- **B-O1 [V]** Tuiles d'équipes : « Hanwha Life Esports », « Karmine Corp Blue » touchent les bords de la tuile (0 pt de marge) (32-2). → `.padding(.horizontal, 6)` + `lineLimit(2)` (`OnboardingPages.swift:76-79`).
- **B-O2 [V]** Pilules de ligues : la pilule blanche veut dire « ligue suivie », mais ailleurs le blanc veut dire « filtre choisi » ; ici « LEC » est blanche au-dessus de « ÉQUIPES DU MONDIAL » (32-2). → ligue suivie = verre + bordure accent + étoile pleine, jamais le blanc (`OnboardingPages.swift:36-44`).
- **B-O3 [P]** Gouttière 20 pt (16 partout ailleurs) ; pilules rognées à 20 pt du bord (32-2). → 16 pt et B-G2 (`OnboardingView.swift:80, 123`).
- **B-O4 [P]** Page 1 : ≈ 330 pt de vide entre l'exemple et les points de pagination (32-1). → contenu centré verticalement (`OnboardingView.swift:64-86`).
- **B-O5 [P]** Page 3 : rien ne dit ce que veut dire l'interrupteur allumé (32-3). → en-tête de liste « Masquer les scores » (`OnboardingPages.swift:113-126`).
- **B-O6 [N]** Tuiles en rayon 18 hors échelle ; tuile suivie en accent et non à la couleur de l'équipe (`OnboardingPages.swift:83-84`).

### Widgets, Live Activity, Dynamic Island (09-13)

- **B-W1 [V]** Dynamic Island déployée : ≈ 14 pt vides entre « Game 2 · » et « 18:42 » (13) : le chrono natif est aligné à droite dans 40 pt réservés pour « 1:02:05 ». → chrono en premier puis « · Game 2 », ou largeur réservée selon la durée connue (< 1 h : 28 pt) (`IslandViews.swift:94-96`, `LiveActivityViews.swift:84-87`).
- **B-W2 [P]** Widget moyen sans équipe : « Aucune équipe suivie » sans « Ajoute-en dans l'appli » (les autres familles l'ont) (11). → `HomeWidgetViews.swift:106-112`.
- **B-W3 [N]** Live Activity « game en pause » : icône « en direct » à côté du chrono figé (12). → icône pause quand le chrono est figé en cours de game (`LiveActivityViews.swift:117-124` ; demande de distinguer pause et fin dans `LiveActivityDisplay`).
- **B-W4 [N]** Dynamic Island compacte masquée : capsule vide entre T1 et FLY (13). → icône « en direct » au centre côté droit (`IslandViews.swift:7-30`).
- **B-W5 [N]** Widget rond « Prochain masqué » : trophée seul, alors que le direct masqué montre le code « T1 » (09). → code de l'équipe + œil barré.
- **B-W6 [N]** Widget moyen avec une seule ligne : 60 % de la hauteur vide (11). Acceptable ; éventuellement ligne « Rien d'autre cette semaine ».

---

## C. Transitions (lecture du code)

- **C1 [P] Accueil : rien n'est animé.** `content = computed` est posé sans animation (`HomeView.swift:69`) : squelette → contenu, ligne de direct qui arrive ou part, révélation dans « Résultats récents » : tout saute. La cascade ne joue jamais dans l'appli (`cascaded = true` à l'apparition, avant le premier contenu, `HomeView.swift:55` ; mineur 11 du lot saison, parqué). → `withAnimation(Motion.animation(.list, reduceMotion:)) { content = computed }`, `cascaded = true` au premier contenu publié ; `.transition(Motion.listTransition…)` sur les lignes de `LiveNowSection` et `RecentResultsSection`.
- **C2 [P] Zoom carte → Détail limité à l'onglet Matchs.** `HomeView.zoom` n'est jamais utilisé (`HomeView.swift:12`) ; `MatchLine` pousse `MatchRoute(matchId:)` sans source (`SeasonParts.swift:124`) : Accueil, calendrier, page équipe, ligues, activité ouvrent le Détail par un glissement standard. → `MatchLine(sourceID:)` (« home/live/<id> », « home/day/<id> »…) + `zoomSource` ; passer `zoom` aux sections.
- **C3 [P] Retour du zoom quand la ligne change** (direct → dernier) : la source `kc/live/m1` n'existe plus au retour, iOS retombe sur sa transition de repli (M2 du lot Finitions, parqué). → id `"\(teamId)/\(matchId)"` sur la première ligne qui montre le match (`MatchRoute.swift:21-22`, `TeamCardView.swift:94, 164, 196`).
- **C4 [P] Squelette → contenu de la page équipe** : ordre différent (B-T4) → saut de ≈ 300 pt ; pilules de périmètre qui apparaissent après la lecture (+ 43 pt).
- **C5 [V] Onboarding, retour en arrière dans le mauvais sens** : l'insertion vient toujours de la droite (`.move(edge: .trailing)`, `OnboardingView.swift:84`) : « Retour » ou glisser vers la droite fait entrer la page précédente par la droite. → mémoriser le sens (`@State var forward`) et `.move(edge: forward ? .trailing : .leading)`.
- **C6 [P] Onboarding : glissement de page en conflit avec les pilules** de ligues (`DragGesture` sur tout le `ScrollView`, `OnboardingView.swift:87` ; parqué depuis FIX1). → `TabView(.page)` avec index, ou geste limité aux mouvements horizontaux hors de la rangée de pilules (`simultaneousGesture` + garde sur l'angle).
- **C7 [P] Capsule des pilules** : ne glisse que pour les games du Détail ; duel, joueurs en forme, périmètres, ligues : fondu ou saut. → B-G1 (namespace partout ; ligues : sans glissement acceptable car défilantes).
- **C8 [P] « Tout le fil » / « Réduire le fil »** : +170 pt sans animation (`TimelineCard.swift:47`). → `withAnimation(Motion.animation(.list, reduceMotion:))`, lignes en `listTransition`.
- **C9 [P] Révélation dans les listes** (`MatchLine`, Accueil, calendrier) : le score remplace « Terminé · toucher pour révéler » en fondu par défaut, sans le flou des cartes et du Détail (`SeasonParts.swift:193-205`). → `.transition(Motion.revealTransition(reduceMotion:))` sur le texte du score.
- **C10 [N] Changement de mois** : simple fondu de la grille ; pas de glissement directionnel (`SeasonCalendarView.swift:85-91`). → `.id(month).transition(.push(from: delta > 0 ? .trailing : .leading))`, fondu sous « Réduire les animations ».
- **C11 [N] Changement d'onglet et piles** : les trois `NavigationPath` sont conservées pendant la session (bien) ; un lien profond remplace toute la pile de Matchs (`RootView.swift:93`) et le duel libre vit hors de la pile (`DuelSection.swift:70`, mineur 14 parqué) : un retour par glissement depuis un duel libre ne repasse pas par le chemin. → pousser `DuelRoute` par `NavigationLink(value:)` (destination déjà déclarée, `Routes.swift:59`).
- **C12 [N] Feuilles** : fiche joueur, « Comment c'est calculé », sélecteur du duel, couleur : `.medium/.large` ; Réglages : grande seule ; aucune n'affiche la poignée ; « Comment c'est calculé » n'a pas de bouton « Fermer ». → `.presentationDragIndicator(.visible)` partout et « Fermer » dans la feuille du barème (`MustWatchSection.swift:53-76`).
- **C13 [N] Chiffres qui défilent** : en place sur cartes, Détail, sous-titres, widgets, Live Activity ; pas sur les barres du duel quand on « Change » de joueur (`DuelBars.swift:16, 30`). → `numericChange` sur les deux valeurs.
- **C14 [N] Réduire les animations** : conforme à la règle `Motion.reduced` ; le fondu `easeInOut` fait encore glisser 0,2 s les cartes qui changent d'ordre (M1 Finitions, accepté, à juger en D.13) ; halo et lueur à 120 Hz (M4, parqué) ; chaque `SkeletonBlock` a encore son `TimelineView` (M5, reflets désormais synchronisés).

---

## D. Points parqués encore ouverts (registres) et vérifications sur l'iPhone

### D.1 À corriger (utile pour la qualité perçue)

| Origine | Point | État au `2ebd369` | Renvoi |
|---|---|---|---|
| Étape 2, T10 | Score décentré si codes de largeurs différentes ; libellés masqués incohérents (« masqué » / « Terminé », « Bientôt » / « À venir ») | ouvert | B-G10, B-G6 |
| Finitions M2 | Retour du zoom perdu quand la ligne passe de « direct » à « dernier » | ouvert | C3 |
| Finitions M4 | Halo et lueur redessinés à 120 Hz | ouvert (`phaseAnimator`, `LiveEffects.swift:6-31, 50-79`) | C14 ; `TimelineView(.animation(minimumInterval: 1/30))` |
| Finitions M5 | Un minuteur par bloc de squelette | partiel (reflets synchronisés, 1 `TimelineView` par bloc) | un minuteur par conteneur |
| Fonctionnalités m8 | « Épingler » descend quand le fil se remplit (≈ 170 pt) | ouvert, décision de Dan | `MatchDetailView.swift:168-170` : le remonter sous « Regarder », ou hauteur minimale du fil pendant le chargement |
| Saison 2 | `MatchLine` reconstruit l'ensemble masqué à chaque ligne | ouvert (`SeasonParts.swift:115`) | perf de défilement |
| Saison 6 | Slug « worlds » en dur, « En attendant, voici le Mondial », « Équipes du Mondial » | ouvert (`RootView.swift:112`, `HomeView.swift:124`, `OnboardingPages.swift:58`) | avant novembre |
| Saison 7 | Onboarding, catalogue pas encore lu : titre « Équipes du Mondial » et rien dessous | ouvert | squelette de grille + note hors ligne |
| Saison 11 | Cascade de l'Accueil jamais jouée | ouvert | C1 |
| Saison 14 | Duel libre hors de la pile pilotée par chemin | ouvert | C11 |
| Parqué FIX1 | `DragGesture` de l'onboarding contre les pilules | ouvert | C6 |
| Parqué M13 | Textes LoLKit en français dans l'interface anglaise (raisons de « À ne pas rater », notifications, widgets) | ouvert | à traiter avec B-G6 (même fichiers) |
| Étape 4 | Note « Déjà 3 Live Activities » qui reste affichée | ouvert | `LiveActivityPinButton.swift:56-58` : effacer `refused` quand `shownMatchIds` change |
| Étape 3 | Message long tronqué sur le widget en ligne ; VoiceOver lit les monogrammes ; `InlineIcon` silencieux | ouvert | widgets |
| Saison 15 | Planches PNG jugées sur la taille seulement (34-grand-texte et rendu anglais jamais regardés) | ouvert | ce document comble 34 ; ajouter une planche anglaise et une AX5 |

### D.2 Parqués, à laisser (coût > gain en polish)

Saison 1 (perf joueurs en forme), 10 (arrêt `.failures` collant), 12 (écritures disque sur le fil principal), 13 (éviction au-delà de 2 000 games) ; Finitions M1 (accepté sous réserve de D.13), M7 (tests) ; Étape 4 M2, M6, `live-activities.json` sans protection ; Étape 2 M4, M11, M13, M14, M16, M17.

### D.3 Vérifications à faire sur l'iPhone (pixel et mouvement)

1. **D.6 / C3** : ouvrir un match en direct depuis sa carte, attendre la fin, revenir : le zoom se referme-t-il sur la carte ?
2. **D.8** : pendant le flou de révélation du Détail (0,5 s), les panneaux de verre clignotent-ils gris ou noir ? (flou sur `.ultraThinMaterial`)
3. **D.13** : glissements de 0,2 s sous « Réduire les animations » acceptables ?
4. **D.15 / M4** : chaleur et batterie après 20 min sur Matchs avec deux cartes en direct non masquées.
5. **Grand texte AX2** sur Accueil (B-H4), page équipe (B-T1), Détail (pilules qui ne grandissent pas, B-G1).
6. **Dynamic Island** déployée en vrai (B-W1) : l'écart « Game 2 · … 18:42 » est-il aussi visible qu'en planche ?
7. **Épingler** (m8) : bouge-t-il pendant le remplissage du fil ?
8. **Heure** : un match à venir affiche la même heure sur l'Accueil, le Détail, le widget et la notification (B-G5).
9. **iPhone réglé en 12 h** (Réglages › Général › Date et heure) : l'Accueil passe-t-il en « 8:00 PM » alors que le Détail reste en « 20:00 » ? (B-G5)
10. **Onboarding** : glisser sur la rangée de pilules change-t-il de page (C6) ? « Retour » entre-t-il par la gauche (C5) ?

---

## E. Plan de correction, en tâches parallélisables

Chaque tâche possède ses fichiers ; deux tâches ne touchent jamais le même fichier. **E0 et E1 d'abord** (elles changent des primitives et des chaînes que les autres consomment) ; ensuite E2 à E8 en parallèle. Toutes : planches régénérées et regardées à l'œil (pas seulement leur taille).

### Vague 1 (séquentielle, courte)

**E0 — Primitives DA** · fichiers : `App/DA/Components.swift`, `App/DA/Skeleton.swift`, `App/DA/GlassCard.swift`, `Shared/DA/Palette.swift`.
- `PillButton` : `.sora`, `lineLimit(1).fixedSize()`, zone 44 pt, namespace (B-G1, B-H2 en partie, C7).
- `SectionLabel` : paramètre `trailing` (lien) avant le point (B-M1).
- Tokens : `Radius.field` (22 → champs), `Palette.fill(.subtle/.chip/.selected)` pour les blancs à opacité ; `Spacing` facultatif (A).
- Squelettes : ligne de drakes dans `StatsSkeleton`, largeurs de pilules du Détail, carte « Suivre la ligue » dans `LeagueLoadingSkeleton` (B-D15, B-E1).

**E1 — Formats et lexique LoLKit** · fichiers : `LoLKit/Sources/LoLKit/Presentation/Format.swift`, `AppFormat.swift`, `LoLKit/Sources/LoLKit/Live/LiveActivityDisplay.swift`, `LoLKit/Sources/LoLKit/Widget/WidgetText.swift`, `LoLKit/Sources/LoLKit/Home/HomeFeed.swift`, `App/Season/SeasonFormat.swift` + leurs tests.
- Signe « − », tirets unifiés, `compactScore` « 1–0 », bilans « 9–0 » (B-G4).
- Postes unifiés (B-G8), drakes regroupés et « ancestral » (B-D4, B-G9).
- Lexique « masqué » pour widget et Live Activity (B-G6).
- `todayCount` sur la même liste que la journée (B-H3).

### Vague 2 (parallèle)

**E2 — Accueil et lignes de match** · `App/Home/*.swift`, `App/DA/SeasonParts.swift`.
B-H1, B-H4, B-H5, B-H6, B-H7, B-H8, B-M2 (style liste de `MustWatchSection`), B-G10 (`MatchLine`), B-G5 (`MatchLine` : `Format.time` + fuseau d'environnement), C1, C2 (Accueil), C9, C12 (feuille du barème), B-G12 (bandeau).

**E3 — Détail** · `App/Detail/*.swift`, `App/Matches/MatchParts.swift`, `App/Timeline/*.swift`, `App/Watch/WatchButtons.swift`, `App/Builds/*.swift`.
B-D1 à B-D14, B-G3 (Regarder, révéler), B-G10 (`ScoreRow`), B-G7 (note d'épinglage), C8, m8 (position d'« Épingler », après décision de Dan).

**E4 — Duel** · `App/Duel/*.swift`.
B-U1 à B-U4, C11 (duel libre par `NavigationLink(value:)`), C13.

**E5 — Pages de saison** · `App/TeamPage/*.swift`, `App/PlayerPage/*.swift`, `App/Standings/*.swift`, `App/Calendar/*.swift`.
B-T1 à B-T5, B-J1 à B-J4, B-C1 à B-C4, B-K1, B-G2 (périmètres joueur, types de drakes), C4, C10.

**E6 — Matchs, Équipes, Ligues, Réglages** · `App/Matches/TeamCardView.swift`, `App/Matches/MatchesView.swift`, `App/Matches/MatchRoute.swift`, `App/Teams/*.swift`, `App/Leagues/*.swift`, `App/Settings/SettingsView.swift`, `App/Reminders/MatchRemindersSection.swift`, `App/LiveActivity/LiveActivityDiagnostic.swift`.
B-M3, B-M4, B-M5 (et le même bouton de l'Accueil, fourni par E2), B-E2 à B-E4, B-R1, B-R2, B-G7 (Réglages), B-G11, C3.

**E7 — Onboarding** · `App/Onboarding/*.swift`.
B-O1 à B-O6, B-G4 (exemple « +2,1k »), C5, C6, saison 7 (état vide).

**E8 — Widgets, Live Activity, planches** · `Shared/LiveActivity/*.swift`, `Shared/Widgets/*.swift`, `Tests/FailleTests/*SnapshotTests.swift`, `Tests/FailleTests/Support/*`.
B-W1 à B-W6 ; fuseau `Europe/Paris` dans les planches de l'appli (B-G5) ; planche 25c réellement « en collecte » (B-H6) ; planches anglaise et AX5 (saison 15).

Ordre de priorité si tout ne passe pas : B-H1, B-U1, B-U2, B-D1/B-D2, B-T1/B-T2/B-J1, B-H2, B-D5/B-D6, B-C1, B-W1, B-H4, puis le reste par tâche.
