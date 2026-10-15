# Vague de corrections finale (W1-W9) - rapport

Statut : termine, CI verte. Commits `dfc8a9b..ba7fb0a` sur main (un commit par point, plus un correctif W3/W4).

- W1 dfc8a9b : `BracketMasking.hiddenIds` (LoLKit, pur, teste) ; appliqué dans `MatchReminders.plan`, `HomeFeed.build`/`recentResults(hiddenIds:)`, `AppStore.withoutMaskedUpcoming`/`isUpcomingMasked`/`bracketHiddenIds`, `LeagueRows(bracketHiddenIds:)`. Seuil = dernier match masque non revele d'une equipe de `maskedLatestTeamIds` dans la meme ligue internationale.
- W2 ba929c6 : `setLeagueNotifications` allume `matchRemindersEnabled`, demande l'autorisation via `requestReminderAuthorization()` (meme `MatchRemindersFlow`), refus = interrupteur a faux + note (`leagueNotificationsDenied`) ; phrase des Reglages mise a jour.
- W3 b3d90eb : `isOnboarding` (`beginOnboarding`/`completeOnboarding`) : ni wake ni Live Activity pendant l'onboarding, lances a la fin.
- W4 8f74cef : wake a l'arrivee des ligues et au retour de l'API ; `seasonWait` = 1 tick tant que ligues vides/echec.
- W5 a124e67, W6 4a5da01, W7 1f3400d, W8 22a756d, W9 9665258.
- ba7fb0a : correctif trouve par la CI : le wake de W4 ne doit pas se declencher pendant l'onboarding.

CI (dernier commit ba7fb0a) : iOS 38663963372 vert, Strings 38663963339 vert. LoLKit 38662897499 vert (sur 9665258, qui contient le dernier changement LoLKit dfc8a9b ; aucun run LoLKit sur ba7fb0a car rien dans LoLKit/). Premier run iOS 38662897283 en echec (test W3 vs W4), corrige.
IPA : C:\Users\Dan\Downloads\faille\Faille.ipa (6 156 394 octets).

Deviations : `withoutMaskedUpcoming` retire aussi les matchs termines de la suite du tableau (pas seulement unstarted/inProgress) ; calendrier : la raison `.budget` s'affiche des que la page est encore manquante et que le chargement est fini (la reserve epuisee n'est pas exposee a la vue) ; fr plural ajoute aussi pour « %lld games », « sur %lld games enrichies », « Stats masquees · N matchs masques » et victoires/defaites d'affilee.
Concerns : `isUpcomingMasked` recalcule `bracketHiddenIds` par ligne (limite aux ligues internationales, non-termines) ; apercus PNG non regardes.

## Fuites résiduelles de W1 (masquage de tableau) — correctifs

- Calendrier / page d'équipe / MatchLine : la suite du tableau se juge sur l'ensemble fusionné (pages + calendrier + direct) via `AppStore.bracketHiddenIds(over:)` ; `MatchLine` reçoit les ids du calendrier. LoLKit : `BracketMasking.visible` (testé : absent des pastilles et des jours, révélé = restauré).
- Équipes suivies : `TeamCard.nextBracketMasked` posé par `TeamCards.build` ; `Presenter.nextLine` rend `.hidden` (« Prochain · masqué »), ce qui couvre aussi la première boucle de `MatchReminders.plan`, le widget et la page équipe. Tests ajoutés.
- Live Activities : `syncLiveActivities` retire du direct (et du contenu) les matchs cachés ; révélé, tout revient.
- `leagueNotificationsDenied` : revert aussi si la scène est annulée pendant l'invite et que iOS refuse ; la note s'efface à l'apparition de l'onglet Équipes si l'autorisation est accordée.
- Test existant NextLineTests ajusté (GEN en ligue nationale) ; exemples widgets : matchs à venir en ligue nationale.
- CI : iOS 38666388876 vert, Strings vert, LoLKit 38665620291 vert (SHA 063c4ec). IPA copiée dans Downloads/faille.

## Dernière fuite de la progression du tableau (live / last)
- `TeamCards.build` pose `liveBracketMasked` / `lastBracketMasked` (ids dans `BracketMasking.hiddenIds`, ligue internationale, non révélés). `Presenter.scoreLine(bracketMasked:)` masque le score comme un match anti-spoiler ; `latestIsMasked` rend la ligne « Prochain » et `maskedLatestTeamIds` cohérentes (F1/C). Carte Matchs : « En direct » sans score + « toucher pour révéler » ; « Dernier · … · Terminé ». Widgets : `makeLine` honore les drapeaux.
- Ligues : seuil `bracketHiddenIds(over: [])` (calendrier + direct).
- Limite connue : l'écran Détail d'un tel match passe par `store.scoreLine` sans drapeau (non traité).

## Détail d'un match caché par BracketMasking
- `AppStore.isDetailMasked` / `isBracketHidden(matchId:)` : le Détail traite un match de `bracketHiddenIds` non révélé comme un match en anti-spoiler (même chemin `masked`, une seule décision par rendu via `bracketHidden` de la vue).
- Clés de tâches (`featureGame`), `loadSelectedGame`, `spellGames`, bouton d'épingle Live Activity, Regarder/Replay, Duel : tous sur le drapeau combiné ; aucune requête de stats.
- Test hébergé : `aBracketHiddenMatchIsMaskedInTheDetailUntilRevealed` (HomeTests). Aucun changement LoLKit ni chaîne.
