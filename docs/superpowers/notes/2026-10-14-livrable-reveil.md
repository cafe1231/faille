# Faille — ce qui a été fait cette nuit (14/10/2026)

## 1. État des étapes

| Étape | État | Preuve |
|---|---|---|
| 2 — L'appli (Matchs, Équipes, Détail, Réglages, anti-spoiler) | **Faite et testée en CI** ; reste ton test sur l'iPhone (section A de la checklist) | [iOS 38454317932](https://github.com/cafe1231/faille/actions/runs/38454317932) ; la nouvelle IPA la remplace |
| 3 — Les widgets (écran verrouillé : en ligne, rectangulaire, rond ; accueil : petit configurable, moyen) | **Faite et testée en CI** ; relecture finale + 9 corrections (matchs en retard, widget moyen à 4 lignes, anti-spoiler renforcé) | CI [iOS 38479473851](https://github.com/cafe1231/faille/actions/runs/38479473851), [LoLKit 38479473818](https://github.com/cafe1231/faille/actions/runs/38479473818) |
| 4 — La Live Activity (écran verrouillé + Dynamic Island, auto/manuel, bouton « Épingler », arrière-plan) | **Faite et testée en CI** ; relecture finale + corrections (démarrage au lancement, diagnostic, anti-doublon) ; reste le test pendant un vrai match | CI [iOS 38498941347](https://github.com/cafe1231/faille/actions/runs/38498941347), LoLKit [38498941332](https://github.com/cafe1231/faille/actions/runs/38498941332) |
| Worlds : flux en direct | **En partie** : `lolkit live` lancé (« Aucun match en direct » cette nuit) ; une **vraie frame en pause** capturée sur KC vs MKOI (LEC, 19/09) → fixture `window_paused.json` + 2 tests ; la capture du **vrai direct** est programmée pour jeudi 15/10 à 20 h 20 (voir 6.4) | [LoLKit 38501202196](https://github.com/cafe1231/faille/actions/runs/38501202196) |

Tests automatiques : 253 tests LoLKit (Linux + macOS), 118 tests sur simulateur iOS, captures PNG de chaque écran.

## 2. Installer

IPA : `C:\Users\Dan\Downloads\faille\Faille-etape4.ipa`

1. iPhone branché en USB et déverrouillé ; iTunes et AltServer lancés.
2. **Maj + clic** sur l'icône AltServer (barre des tâches) → **Sideload .ipa…** → l'iPhone → `Faille-etape4.ipa` → ton Apple ID.
3. Réglages iOS : Actualisation en arrière-plan **activée** pour Faille ; Faille › Activités en direct **activées** ; économie d'énergie **coupée**.
4. Retire le widget « Sonde Faille » de l'accueil (il n'existe plus).

Rappel AltServer (compte gratuit) : l'appli expire au bout de 7 jours, il faut la re-signer (AltServer le fait si le PC et l'iPhone sont sur le même Wi-Fi).

## 3. Checklist de test

`docs/superpowers/notes/2026-10-14-checklist-iphone.md` : A (appli), B (widgets), C (Live Activity, pendant C9 vs KC jeudi 20 h). Réponds OK / KO + remarque par ligne ; je corrige les KO.

## 4. Captures

Envoyées avec ce message : Live Activity (tous les états), Dynamic Island, widgets écran verrouillé, widgets accueil, widget moyen, bouton « Retirer » du Détail, Réglages avec le diagnostic.

## 5. Décisions prises sans toi (« Ruling »), avec leur coût si elles sont fausses

### Étape 2 (appli)
- Travail directement sur `main` (pas de branche) — coût : `main` parfois cassé quelques minutes entre deux tâches.
- Matchs à stats désactivées : on interroge quand même le flux pour le chrono — coût : quelques requêtes 404 de plus.
- **« Prochain » masqué** : si le dernier match d'une équipe anti-spoiler est masqué, sa carte montre « Prochain · masqué », hors compteur « à venir » et hors tri — sinon une élimination se lirait sur la carte — coût : tu vois moins d'infos sur tes équipes sans spoiler.
- **Cartes en verre « matière »** (flou + teinte + bordure) au lieu du Liquid Glass d'iOS 26, gardé pour la barre d'onglets — le Liquid Glass faisait un écho du texte au-dessus des cartes — coût : revenir au Liquid Glass = un modificateur.
- Pas de logos pleine taille dans les listes ; équipes non suivies en monogramme — coût : pas de logo pour les équipes non suivies.
- Rafraîchissements : la réussite est datée au début de la tentative ; tirer-pour-rafraîchir force toujours ; une requête annulée n'est pas un échec — coût : aucun visible.
- Petites corrections avant installation (cibles tactiles 44 pt, libellés masqués « Terminé » / « À venir », noms de champions, fichiers illisibles jamais écrasés, pas de cache HTTP) — coût : aucun.

### Étape 3 (widgets)
- **Règle C** : sur la carte de GEN, « GEN vs T1 » (T1 en anti-spoiler) est caché tant que le dernier match de T1 est masqué ; affiché sinon — coût : tu peux voir un prochain match que tu aurais préféré cacher.
- **Fuite résiduelle acceptée** : un fan attentif peut encore déduire un résultat (la ligne de GEN n'est masquée que contre T1) ; variante stricte possible — **à toi de choisir** (voir 6).
- **Match en retard** : à l'heure prévue, le widget le garde comme prochain (« 0 min ») tant que l'appli a des données de moins de 10 min ; sans données fraîches, il le considère commencé — coût : quelques minutes de « 0 min ».
- **Rechargement des widgets** demandé à iOS toutes les 5 h (les entrées couvrent déjà 6 h et chaque début de match ; l'appli recharge à chaque rafraîchissement) au lieu de 30 min — coût : si tu n'ouvres pas Faille pendant 5 h, un changement de calendrier peut être manqué (heures et comptes à rebours restent justes).
- Widget moyen : 4 lignes max, puis « T1 · Prochain · masqué » pour les équipes masquées, dans l'ordre de suivi — coût : une ligne coupée sur un petit iPhone (testé à 6,1" et 6,3").
- Widget rond : « 0 min » au lieu de « maintenant » (qui ne tenait pas) — coût : cosmétique.
- Message distinct si le groupe d'apps est introuvable (« réinstalle Faille avec AltServer ») — coût : aucun.
- Extension des widgets en Swift 6 ; polices et icônes embarquées — coût : aucun.

### Étape 4 (Live Activity)
- **Pas de push** (compte gratuit) : la Live Activity se met à jour quand Faille est ouverte, au passage en arrière-plan, puis seulement quand iOS accorde un réveil (~15 min au mieux). Sinon elle passe « màj il y a X minutes » au bout de 3 min — c'est honnête, mais tu le verras souvent verrouillé.
- `updatedAt` = dernière relecture réussie (pas l'heure de la mise à jour) — coût : « pas fraîche » plus tôt qu'avec la lecture littérale de la spec.
- Démarrage à chaque tour du premier plan (pas seulement à l'ouverture) — coût : aucun.
- **Pas d'éviction** : au plus 3 Live Activities, les terminées gardent leur place 1 h — coût : avec plus de 3 matchs suivis en même temps, une équipe attend.
- Retrait à la main détecté par réconciliation (30 s de grâce) ; une Live Activity glissée n'est jamais recréée automatiquement — coût : rare recréation si glissée dans les 30 s après son démarrage.
- Fin d'un match hors des ligues suivies apprise par les détails du match — coût : une requête de plus par minute pendant 1 h au plus.
- Masquer un match sorti du direct mais pas encore « terminé » au calendrier : le score peut rester quelques minutes — coût : rare, appli ouverte à ce moment-là.
- « màj il y a 9 minutes » (texte système qui avance seul) au lieu de « 9 min » — coût : cosmétique.
- Premier démarrage après un lancement à froid : différé seulement si une Live Activity notée n'est pas encore listée par iOS — coût : rare doublon (garde anti-doublon de 30 s ajoutée).
- **Bloc « Diagnostic Live Activity »** dans Réglages › À propos (dernier échec de démarrage, dernier réveil, dernière demande de réveil) — parce que je ne peux pas lire les journaux de l'iPhone depuis Windows — coût : 4 lignes de plus dans les réglages.
- Pas de Live Activity démarrée ni de logos téléchargés en arrière-plan (budget de temps d'iOS) — coût : aucun.

## 6. Ce qui a besoin de toi

1. **Tester sur l'iPhone** (checklist), surtout pendant **C9 vs KC jeudi 15/10 à 20 h**.
2. **Anti-spoiler strict ou pas ?** Aujourd'hui, la ligne « prochain match » d'une équipe normale n'est cachée que contre une équipe anti-spoiler dont le dernier match est masqué. Variante stricte : aucune équipe n'annonce son prochain adversaire tant qu'un match anti-spoiler est masqué (plus sûr, moins d'infos).
3. **Live Activity pas fraîche** : garder « màj il y a X minutes » à la place du chrono (spec) ou montrer le chrono + un petit « màj » ? À décider après l'avoir vue en vrai.
4. **Capture du vrai direct** : une tâche planifiée unique (« Faille — capture du direct des Worlds », section « Scheduled » de l'appli Claude) se lance jeudi 15/10 à 20 h 20 : elle enregistre une fenêtre réelle de C9 vs KC comme fixture testée et la pousse. **Laisse l'appli Claude ouverte** sur le PC à ce moment-là (sinon elle se lance au prochain démarrage) ; tu peux la supprimer si tu n'en veux pas. Détails : `docs/superpowers/notes/2026-10-14-worlds-capture.md`.
5. **Plus tard** : compte développeur payant (99 €/an) pour garder l'appli plus de 7 jours et ajouter le push (Live Activity à jour même téléphone verrouillé) — phase 2.
