# Faille — spec phase 2 : serveur, push et publication

> Date : 15/10/2026 · Statut : à relire par Dan · Remplace et précise la §12 de `2026-10-13-faille-design.md`.
> Lot P3 de `.superpowers/goal-nuit-2.md`. Documents seulement : rien n'est construit ici.
> À lire avec la note de conformité `docs/superpowers/notes/2026-10-15-conformite-riot-app-store.md` (P4), qui conditionne la **publication publique** et toute **monétisation**.

## 0. Résumé en 10 lignes

1. Un seul petit serveur en Europe (VPS Hetzner), un service **Swift (Hummingbird 2) qui réutilise LoLKit tel quel** : le contrat `LiveMatchState` est le même code, pas une réécriture.
2. Il interroge lolesports **une fois pour tout le monde** (cache partagé) : `getLive` toutes les 30 s, `window` toutes les 10 s par match en direct suivi, règle des 80 s via `LoLClient.liveWindow`.
3. Il pousse les Live Activities par APNs : **push-to-start** au début du match, mises à jour par **canal de diffusion** (iOS 18+ : un envoi par match, quel que soit le nombre d'abonnés), fin 1 h après le match.
4. Deux canaux par match : **« plein »** et **« masqué »** (anti-spoiler). L'état masqué est `LiveMatchState.masked()`, déjà dans LoLKit.
5. Notifications de résultat : texte construit par la même règle anti-spoiler ; un match masqué donne « terminé » sans score, ou rien.
6. Comptes **anonymes par défaut** (identifiant + secret dans le trousseau), **Sign in with Apple facultatif** pour retrouver ses pronos sur un autre iPhone. Aucun e-mail stocké.
7. **Ligues de pronos entre amis** : code d'invitation, verrouillage au début du match **côté serveur**, classement calculé par l'appli à partir des points par match pour respecter l'anti-spoiler de chacun. Pas d'argent, pas de lots.
8. API JSON versionnée `/v1`, décrite dans `server/openapi.yaml`, testée sur la fixture dorée `live_contract.json`.
9. Coût : **≈ 10 €/mois** tout compris pour une petite audience (VPS + sauvegardes + domaine + compte Apple lissé) ; < 60 €/mois jusqu'à ~100 000 utilisateurs grâce aux canaux de diffusion.
10. Ordre de sortie : TestFlight avec les identifiants officiels **sans serveur** (semaine 1), puis push Live Activity (2.1), puis ligues de pronos (2.2), puis App Store public **après réponse de Riot** (2.3), monétisation en dernier et seulement avec un accord écrit.

---

## 1. Ce qui change par rapport à la §12 de la spec v1

| §12 (13/10) | Phase 2 (15/10) | Pourquoi |
|---|---|---|
| Cloudflare Worker + Durable Object, TypeScript | VPS + service Swift qui importe LoLKit | Le contrat de la Live Activity, l'anti-spoiler et la règle des 80 s existent déjà, testés, en Swift sur Linux (CI `lolkit.yml`, Docker `swift:6.2`). Les réécrire en TypeScript = deux vérités à maintenir. APNs exige HTTP/2 : natif en Swift (AsyncHTTPClient / APNSwift), incertain dans le runtime Workers (bibliothèques communautaires seulement). Dan prend « un serveur ». |
| `window` toutes les 15 s | 10 s | Le flux ne produit une nouvelle donnée qu'au plus toutes les 10 s (spec §4.1) ; 10 s = la donnée la plus fraîche possible, sans requête inutile. |
| Mise à jour par jeton de chaque Live Activity | **Canal de diffusion par match** (iOS 18+), jeton par activité en repli | Un envoi par match au lieu d'un par iPhone ; pas besoin que l'appli se réveille pour envoyer son jeton d'activité. |
| Dépôt privé + Xcode Cloud | Dépôt public conservé, CI GitHub Actions signée par secrets | Xcode Cloud demande un Mac pour la mise en place ; les minutes macOS de GitHub sont gratuites en dépôt public et facturées ×10 en privé. À revoir si le code serveur doit rester privé (voir §9.4). |

**Ruling : serveur Swift sur VPS plutôt que Worker — pourquoi : un seul code pour le contrat et l'anti-spoiler, APNs HTTP/2 natif, boucle de 10 s triviale — coût si faux : une semaine pour porter vers un autre hébergeur (le service est un conteneur Docker, portable tel quel sur Fly.io ou Scaleway).**

---

## 2. Architecture

```
                        ┌────────────────────────────────────────────────────────────┐
                        │ VPS Hetzner (UE, Allemagne/Finlande) · Docker Compose        │
 lolesports persisted/gw│                                                            │
 ◄──── getLive 30 s ────┤  faille-server (Swift 6, Hummingbird 2, import LoLKit)      │
 ◄──── getSchedule 5 min│   ├─ Poller      : cache partagé en mémoire + disque        │
 ◄──── getEventDetails ─┤   ├─ LiveEngine  : LiveMatchBuilder → LiveMatchState        │
 livestats/window       │   ├─ PushQueue   : file en base (Postgres) + envoi APNs      │──── HTTP/2 + JWT ───► APNs
 ◄──── 10 s / match ────┤   ├─ PronoEngine : verrouillage, points, ligues            │
                        │   └─ API /v1     : appareils, suivis, pronos, ligues        │◄─── HTTPS ──── appli Faille
                        │  postgres:17 (volume) · caddy (TLS auto, HTTP/3)            │
                        │  sauvegarde nocturne chiffrée → Storage Box / objet S3      │
                        └────────────────────────────────────────────────────────────┘
```

### 2.1 Poller (cache partagé)

- **Une seule boucle pour tous les utilisateurs** : le serveur est le seul à interroger lolesports pour le push ; le nombre d'utilisateurs ne change pas le nombre de requêtes vers Riot.
- Cadences :
  - `getLive` : 30 s (CloudFront le garde 60 s ; 30 s divise par deux le retard moyen de détection d'un début de match sans charger Riot).
  - `getSchedule` des ligues suivies par au moins un appareil + Mondial / MSI / First Stand : 5 min, pagination `pageToken` comme dans l'appli.
  - `getEventDetails` : à chaque nouveau match en direct et à chaque changement de game (ids des équipes, games, vainqueur).
  - `livestats/window/{gameId}` : **toutes les 10 s** pour chaque game en direct dont le match a au moins un abonné (appareil qui suit une des équipes ou la ligue). **Règle des 80 s** : `LoLClient.liveWindow` (90 s en arrière, recul 100/120/180/300/600 s sur 400 « ahead of broadcast », délai retenu par game). `statsStatus == disabled` fait foi : score seul.
  - `window` sans `startingTime` : une fois par game pour `gameClockStart`.
- Recul exponentiel sur 429 / 5xx (2 s → 4 → 8 … plafonné à 120 s), en-tête `User-Agent: FailleServer/1.0 (+https://<domaine>/contact)`.
- Volume attendu : un soir de Worlds avec 2 matchs en parallèle ≈ 2 × 6 req/min (`window`) + 2 req/min (`getLive`) ≈ **15 req/min**, à comparer à ~1 req/s × N téléphones aujourd'hui.
- Les réponses brutes ne sont **pas** archivées : seul l'état calculé (`LiveMatchState` par match, résultats des séries) est gardé, 30 jours (voir §7).
- L'appli **continue de lire lolesports directement** pour tout le reste (calendrier, équipes, stats de saison, Détail) : le serveur ne redistribue pas le flux brut de Riot (risque « data broker », voir P4 §3). Il ne fournit que ce qui ne peut pas venir du téléphone : le push, et la vérité partagée des ligues de pronos.

### 2.2 LiveEngine

- Pour chaque match en direct suivi : `LiveMatchBuilder.state(...)` de LoLKit produit `LiveMatchState` **plein** ; `masked()` produit la version **masquée**. Les deux sont comparés au dernier état envoyé : rien à envoyer si identiques (hors `updatedAt`).
- Attributs (`LiveMatchAttributes`) : construits **par appareil** au push-to-start (couleur des équipes suivies, `primaryTeamIndex` = l'équipe suivie depuis le plus longtemps sur CET appareil). L'état dynamique, lui, ne dépend pas de l'appareil (scores dans l'ordre de `attributes.teams` = ordre du match), d'où le canal partagé.
- Couleur d'équipe : le serveur n'a pas les pixels du logo ; l'appli envoie la couleur qu'elle a calculée (ou surchargée) avec ses suivis (`colorHex`). Repli : `#6fd3ff`.
- **`updatedAt` monotone** : un état n'est envoyé que si son `updatedAt` est plus récent que le dernier envoyé ; l'appli applique la même règle à ses mises à jour locales (§8.3). Évite qu'une relecture locale plus vieille écrase un push plus récent, et inversement.

### 2.3 Push des Live Activities (APNs)

En-têtes : `apns-push-type: liveactivity`, `apns-topic: <bundleId>.push-type.liveactivity`, JWT ES256 (clé `.p8`), `apns-priority` 5 ou 10. Charge utile `aps` : `timestamp`, `event` (`start` / `update` / `end`), `content-state` (= JSON de `LiveMatchState`, **format de la fixture dorée** : dates en secondes depuis 2001, champs nil omis), `stale-date` (= `updatedAt + 180 s`), `dismissal-date` pour `end`.

| Moment | Envoi | Cible | Priorité |
|---|---|---|---|
| Match d'une équipe suivie qui passe en direct, mode « Automatique » | `event: start` + `attributes-type: LiveMatchAttributes` + `attributes` (par appareil) + `content-state` + canal à écouter (`input-push-channel`, iOS 18) | **jeton push-to-start** de chaque appareil concerné (≤ 3 activités par appareil, ordre de suivi, comme `LiveActivityPlanner`) | 10 |
| Changement de score de série, début/fin de game, baron, inhibiteur | `event: update` | canal du match (plein ; masqué seulement si la phase masquée change) | 10 |
| Stats courantes (kills, gold, tours, drakes) | `event: update`, au plus toutes les 10 s | canal plein | 5 |
| Match terminé | `event: update` phase `finished`, puis `event: end` avec `dismissal-date = fin + 1 h` | canaux plein et masqué | 10 |

- **Info.plist** : `NSSupportsLiveActivitiesFrequentUpdates = YES` (budget de mises à jour plus large ; l'utilisateur peut le couper dans Réglages). Les mises à jour de routine en priorité 5 ménagent le budget ; Apple ne publie pas de chiffre exact : **à mesurer en TestFlight** (journal des réponses APNs + diagnostic dans l'appli).
- **Canaux de diffusion** (« broadcast push », iOS 18+) : le serveur crée deux canaux par match (`plein`, `masqué`) via l'API de gestion des canaux d'APNs, les supprime 2 h après la fin. iOS 26 minimum : tous les appareils les supportent. Repli si un appareil n'a pas de canal (activité démarrée localement avant l'enregistrement) : envoi au **jeton de l'activité** (`pushType: .token`), que l'appli transmet dès qu'elle le reçoit.
- Les détails exacts (nom de la clé `input-push-channel`, quota de canaux par appli, point d'accès de gestion) sont **à vérifier dans la documentation ActivityKit au moment de coder** ; la conception ne dépend pas d'eux (repli par jeton).
- **Environnement APNs** : les builds TestFlight et App Store utilisent **production** (`api.push.apple.com`) ; seule une build de débogage installée depuis Xcode utilise sandbox. Sans Mac, toutes les builds de Dan passent par la CI → production. L'appli envoie quand même `apnsEnvironment` à l'enregistrement.
- Réponses APNs : `410 Unregistered` / `400 BadDeviceToken` → jeton supprimé ; `429` → recul ; `403 ExpiredProviderToken` → JWT régénéré (on le régénère toutes les 40 min, jamais plus d'une fois toutes les 20 min).

### 2.4 Notifications de résultat et de début (alertes classiques)

- Réglages par appareil : début de match (déjà local aujourd'hui : on le garde local, il marche sans serveur), **résultat** (nouveau, serveur), « tu n'as pas pronostiqué » (local).
- Texte construit côté serveur par une fonction LoLKit à créer, `ResultNotification.text(match:follows:revealed:)`, qui passe par `SpoilerPolicy.isMasked` :
  - non masqué : « KC 3-1 C9 · Victoire de KC » ;
  - masqué : réglage par appareil, **« Rien »** (défaut) ou « KC vs C9 est terminé · toucher pour révéler » — jamais de score, jamais de vainqueur, ni dans le titre, ni dans le corps, ni dans `thread-id`, ni dans le résumé de notifications (pas de `summary-arg` avec équipe gagnante).
- Pas de push sur le prochain match si `Presenter.nextLine` le cache pour cet appareil (même règle que les rappels locaux).
- Lien profond : `faille://match/<id>` (le routeur des notifications existe : `App/Reminders/NotificationRouter.swift`).

### 2.5 Appareils, comptes, identité

- **Compte anonyme** créé au premier enregistrement : le serveur renvoie `accountId` (UUID) + `secret` (256 bits) ; l'appli les garde dans le **trousseau** (`kSecAttrAccessibleAfterFirstUnlock`, pour fonctionner en arrière-plan). Requêtes signées : `Authorization: Bearer <jeton court>` obtenu par `POST /v1/session` avec le secret (jeton 24 h).
- **Sign in with Apple** facultatif, proposé seulement là où ça sert (« Retrouver mes pronos et mes ligues sur un autre iPhone ») : le serveur vérifie le jeton d'identité (clés publiques d'Apple), garde **seulement** le `sub` haché (SHA-256 + sel serveur), **ne demande ni le nom ni l'e-mail**. Pas d'autre fournisseur de connexion → la règle 4.8 ne s'applique pas.
- **Suppression du compte dans l'appli** (Réglages › Mes données › Supprimer) : efface tout côté serveur immédiatement et, si Sign in with Apple a été lié, révoque le jeton auprès d'Apple (exigé par Apple lors de la suppression d'un compte lié).
- **App Attest** (DeviceCheck) : phase 2.3, pour limiter la création de comptes par des scripts avant la sortie publique. Pas nécessaire en TestFlight.

### 2.6 Ligues de pronos entre amis (« prono entre potes »)

> Nom à éviter : « Mon Petit Prono » est le nom d'une appli de football existante (voir P4 §9). Nom de travail : **« Pronos »** / « Ligue de potes ».

Règles de jeu : celles de l'idée 9 de `goal-nuit-2.md` (1 pt bon vainqueur, 3 pts score exact de la série, bonus outsider, bonus de série, badges). Le barème vit dans **LoLKit** (même code dans l'appli et le serveur) ; le serveur est l'arbitre.

- **Pronostic** : `{matchId, winnerTeamId, score: [a, b]}`. Accepté jusqu'à l'heure de début du calendrier **ou** la première apparition du match dans `getLive`, la première des deux (**horloge du serveur**, jamais celle du téléphone). Après : 409 `locked`. Le pronostic solo hors ligne reste possible : un prono fait hors ligne n'entre dans les ligues que s'il a été reçu par le serveur avant le verrouillage.
- **Ligue** : créée par un membre (nom ≤ 32 caractères, filtré), rejointe par un **code d'invitation** à 8 caractères ou un lien `https://<domaine>/l/<code>` (lien universel). ≤ 50 membres. Le créateur peut exclure, régénérer le code, supprimer la ligue. Chacun peut quitter.
- **Pseudo** par ligue (≤ 20 caractères, filtre de mots, unique dans la ligue). Contenu généré par les utilisateurs → règle 1.2 d'Apple : **filtre**, **signaler** (pseudo ou nom de ligue), **bloquer** (masquer un membre pour soi), **contact publié** dans la fiche et l'appli. Pas de messagerie : on évite tout le reste de la modération.
- **Périmètre** d'une ligue : toutes les ligues pro, ou une sélection (ex. « LEC + Worlds »). Saison = intervalle de dates.
- **Anti-spoiler et classement partagé** (le point délicat) : le classement d'une ligue trahit des résultats (« Paul a pris 3 points hier soir »). Donc :
  - le serveur renvoie les **points par membre et par match** (`GET /v1/leagues/{id}/ledger`), pas un classement tout fait ;
  - l'appli calcule le classement **sans les matchs masqués non révélés pour CET utilisateur** et affiche « Classement au <date> · 2 matchs masqués » ; toucher → révéler (la révélation est la même que partout, §8 de la spec v1) ;
  - les pronostics des autres sur un match à venir sont visibles après le verrouillage seulement (pas de copie) ; sur un match masqué, ils sont visibles mais sans les points.
  - Les notifications de ligue (« Tu passes 2e ») ne sont **pas** envoyées en phase 2 : impossibles à rendre sûres pour tous les membres.
- **Pas d'argent, pas de lots, pas de mise** : ni achat de points, ni récompense ayant une valeur. Sinon : interdits de Riot (« betting or gambling functionality »), règle 5.3 d'Apple, loi française sur les jeux d'argent et les loteries (voir P4 §7). Le texte de l'écran le dit : « Pour le plaisir : aucun argent, aucun lot. »
- **Pick'em des Worlds** (tableau suisse + phase finale) : hors phase 2.2, mêmes tables (`prediction.kind = 'bracket'`) le jour venu.

### 2.7 Modèle de données (Postgres)

```
accounts(id uuid pk, secret_hash, apple_sub_hash null, created_at, last_seen_at, locale)
devices(id uuid pk, account_id fk, apns_token null, push_to_start_token null, apns_env, app_version,
        os_version, live_activity_mode, notify_results enum('none','masked','full'), updated_at)
follows(account_id, team_id, league_id null, followed_at, spoiler_free bool, color_hex null)   -- miroir de follows.json
reveals(account_id, match_id, revealed_at)                                                       -- miroir de revealedMatchIds
activities(device_id, match_id, activity_push_token null, channel_kind enum('full','masked'), started_at, ended_at)
match_state(match_id pk, full_state jsonb, masked_state jsonb, updated_at, result jsonb null)     -- 30 jours
channels(match_id, kind, apns_channel_id, created_at, deleted_at)
predictions(account_id, match_id, winner_team_id, score_a, score_b, created_at, updated_at, locked bool, points int null)
leagues(id uuid pk, name, owner_account_id, invite_code unique, scope jsonb, season_start, season_end, created_at)
league_members(league_id, account_id, nickname, joined_at, role enum('owner','member'))
blocks(account_id, blocked_account_id) · reports(id, reporter, target_kind, target_id, reason, created_at, status)
push_log(id, kind, target, apns_status, apns_reason, sent_at)                                   -- 14 jours
```

### 2.8 API versionnée (`/v1`)

Règles : JSON en `camelCase` (pas de `snake_case`) — on garde les noms de Swift pour que les types LoLKit s'encodent tels quels ; dates en ISO 8601 **sauf** dans `content-state`, qui garde le format du contrat (secondes depuis 2001). Ajout de champ = compatible ; suppression ou changement de sens = `/v2`. `GET /v1/meta` renvoie `minAppVersion` et des drapeaux (ex. `pushLiveActivities: true`) pour couper une fonction sans publier l'appli. Décodage tolérant des deux côtés. Erreurs : `{ "error": { "code": "locked", "message": "…" } }`.

| Méthode | Chemin | Rôle |
|---|---|---|
| POST | `/v1/accounts` | Crée un compte anonyme → `{accountId, secret}` |
| POST | `/v1/session` | Secret (ou jeton Sign in with Apple) → jeton d'accès 24 h |
| PUT | `/v1/devices/{deviceId}` | Jetons APNs (appareil, push-to-start), environnement, version, réglages de notification et de Live Activity |
| PUT | `/v1/me/follows` | Liste complète des suivis (idempotent) : équipes, ligues, anti-spoiler, couleur |
| PUT | `/v1/me/reveals` | Matchs révélés (ajout seulement) |
| POST / DELETE | `/v1/devices/{deviceId}/activities/{matchId}` | Jeton d'une Live Activity démarrée localement (repli) / retrait à la main (ne plus la relancer) |
| GET | `/v1/meta` | Version minimale, drapeaux |
| PUT | `/v1/predictions/{matchId}` | Pronostic (409 `locked` après le début) |
| GET | `/v1/me/predictions?since=` | Mes pronostics et points |
| POST | `/v1/leagues` · `/v1/leagues/join` | Créer · rejoindre par code |
| GET | `/v1/leagues/{id}` · `/v1/leagues/{id}/ledger` | Membres · points par membre et par match |
| PATCH / DELETE | `/v1/leagues/{id}` · `/v1/leagues/{id}/members/{accountId}` | Renommer, code, supprimer · quitter, exclure |
| POST | `/v1/reports` · `/v1/blocks` | Signaler · bloquer |
| POST | `/v1/auth/apple` | Lier Sign in with Apple au compte |
| GET | `/v1/me/export` | Export RGPD (JSON) |
| DELETE | `/v1/me` | Supprimer le compte et toutes ses données |

- Spécification dans `server/openapi.yaml` ; tests de contrat : le serveur encode un `LiveMatchState` et le compare octet pour octet à `live_contract.json` (même fixture que les tests Swift de l'appli).
- Limites : 60 requêtes/min par compte, 10 créations de compte/h par IP (en mémoire, Caddy + middleware).

---

## 3. Technologie, hébergement, coûts

### 3.1 Trois options comparées

| | **A. VPS Hetzner + Swift (retenu)** | B. Cloudflare Workers + Durable Objects + D1 | C. Firebase (Functions + Firestore + FCM) |
|---|---|---|---|
| Langage serveur | Swift 6, **LoLKit importé** | TypeScript (contrat et anti-spoiler réécrits) | TypeScript (idem) |
| Boucle de 10 s | Tâche Swift en continu | Alarmes de Durable Object (possible) | Mal adapté (planificateur ≥ 1 min ; il faut une instance toujours allumée) |
| APNs (HTTP/2, Live Activities) | Natif (APNSwift / AsyncHTTPClient) | Incertain : le runtime n'a pas de client HTTP/2 Node, bibliothèques communautaires seulement | Via FCM (Live Activities prises en charge par l'API HTTP v1) : une couche de plus |
| Base | Postgres 17 (conteneur) | D1 (SQLite) | Firestore (NoSQL) |
| RGPD / localisation | UE (Allemagne/Finlande), un seul sous-traitant | Mondial, région UE possible pour D1 | Région UE possible ; Google sous-traitant |
| Exploitation | À la charge de Dan (mises à jour, sauvegardes) : ~1 h/mois | Quasi nulle | Faible |
| Coût petite audience (≤ 1 000) | **≈ 6-9 €/mois** | ≈ 5 $/mois | ≈ 0-25 $/mois (instance toujours allumée) |
| Coût ~100 000 utilisateurs | ≈ 30-60 €/mois | ≈ 20-50 $/mois | Imprévisible (lectures Firestore, FCM gratuit) |
| Sortie | Conteneur Docker, portable partout | Lié à Cloudflare | Lié à Google |

**Choix : A.** Raisons, par ordre d'importance : (1) une seule implémentation du contrat de la Live Activity et de l'anti-spoiler, déjà testée sur fixtures réelles ; (2) APNs HTTP/2 sans détour ; (3) boucle continue de 10 s naturelle ; (4) coût fixe et bas, données en UE ; (5) Dan voulait un serveur. Le coût d'exploitation est réel mais petit (images Docker, `unattended-upgrades`, sauvegardes automatiques).

### 3.2 Pile retenue

- **Serveur** : Hetzner Cloud, gamme ARM (CAX11 : 2 vCPU, 4 Go) ou x86 (CX22), Ubuntu 24.04 LTS, Falkenstein ou Helsinki. *Prix exacts à vérifier le jour de la commande* (ordre de grandeur 4-7 € HT/mois, +20 % pour les sauvegardes Hetzner).
- **Conteneurs** (Docker Compose) : `faille-server` (image `swift:6.2` → binaire statique sur `ubuntu:24.04` minimal), `postgres:17`, `caddy:2` (TLS Let's Encrypt automatique, reverse proxy).
- **Swift** : Hummingbird 2 (léger, SwiftNIO), PostgresNIO, APNSwift (ou client APNs maison sur AsyncHTTPClient, ~200 lignes), swift-log, swift-metrics. **LoLKit en dépendance locale** (`server/Package.swift` → `path: "../LoLKit"`).
- **Sauvegardes** : `pg_dump` chiffré (age) chaque nuit vers une Hetzner Storage Box ou un compartiment S3 UE (Scaleway / Backblaze UE), 14 jours de rétention ; **test de restauration une fois par mois** (script).
- **Dépôt** : dossier `server/` dans le même dépôt (le contrat et LoLKit sont partagés) ; workflow `server.yml` : `swift test` Linux + image Docker publiée sur GHCR + déploiement par SSH (`docker compose pull && up -d`) sur `main` uniquement, protégé par un environnement GitHub avec approbation.

### 3.3 Estimation des coûts

| Poste | Petite audience (≤ 1 000 utilisateurs) | Croissance (~100 000) |
|---|---|---|
| Compte Apple Developer | 99 $/an (≈ 8,5 €/mois lissés) | idem |
| VPS | ≈ 5-7 €/mois | 1 VPS dédié (CCX, 4 vCPU) ≈ 25-35 €/mois + 1 petit de secours |
| Sauvegardes | ≈ 1-4 €/mois | ≈ 5 €/mois |
| Domaine | ≈ 10-20 €/an (`.app` / `.fr`) | idem |
| APNs | gratuit | gratuit |
| Supervision (Healthchecks.io, Sentry / GlitchTip, ntfy) | offres gratuites | ≈ 0-26 $/mois |
| **Total** | **≈ 15 €/mois** avec le compte Apple, **≈ 7-10 €/mois** hors Apple | **≈ 50-80 €/mois** |

Pourquoi ça tient à 100 000 : les mises à jour passent par **canal** (un envoi par match et par variante, ≈ 360 envois/h par match), seuls les push-to-start et les notifications de résultat sont par appareil (≈ 1 à 3 par appareil et par match suivi). Un seul flux HTTP/2 vers APNs encaisse des milliers d'envois par seconde. La base reste petite (pronos : ~100 octets par ligne).

---

## 4. Données personnelles et RGPD

*Information, pas un avis juridique ; à faire relire si Faille est monétisée.*

- **Responsable de traitement** : Dan (ou la société Echap Studio si elle existe en tant que personne morale, voir §10 étape 0). Contact publié : `privacy@<domaine>`.
- **Minimisation** : pas d'e-mail, pas de nom, pas d'adresse IP conservée (journaux Caddy sans IP, ou IP tronquée), pas de traçage publicitaire, pas d'IDFA, pas d'outil d'analyse tiers en phase 2 (compteurs agrégés côté serveur seulement).
- **Données traitées** : identifiant de compte et d'appareil, jetons APNs, version de l'appli/iOS, équipes et ligues suivies + anti-spoiler + révélations (nécessaires au push masqué), pronostics, ligues, pseudos, signalements, `sub` Sign in with Apple haché.
- **Base légale** : exécution du service demandé (contrat) pour tout ce qui précède ; aucun consentement marketing (pas de push promotionnel ; s'il en faut un jour : opt-in explicite, règle 4.5.4).
- **Conservation** :
  | Donnée | Durée |
  |---|---|
  | Jeton d'appareil / push-to-start | jusqu'au 410 d'APNs, ou 90 jours sans contact de l'appareil |
  | Jeton de Live Activity, canaux | fin du match + 24 h |
  | `match_state` | 30 jours |
  | `push_log`, journaux applicatifs | 14 jours |
  | Pronostics, ligues, pseudos | tant que le compte existe |
  | Compte sans activité | supprimé après **24 mois** (avertissement in-app au retour à 23 mois si possible) |
  | Signalements traités | 12 mois |
  | Sauvegardes | 14 jours glissants (une suppression de compte disparaît des sauvegardes sous 14 jours ; à écrire dans la politique) |
- **Droits** : export (`GET /v1/me/export`, bouton « Exporter mes données »), suppression immédiate (`DELETE /v1/me`), rectification (pseudo modifiable). Délai de réponse par e-mail : 1 mois (RGPD art. 12).
- **Sous-traitants / destinataires** : Hetzner (hébergement, UE), Apple (APNs, Sign in with Apple), fournisseur de sauvegarde (UE). Registre des traitements tenu dans `docs/legal/registre.md` (une page).
- **Mineurs** : beaucoup de fans de LoL ont moins de 15 ans. Pas de traitement fondé sur le consentement → pas de consentement parental requis à ce titre, mais : pas de messagerie, pseudos filtrés, pas de profil public, pas de publicité ciblée. Classification d'âge App Store : répondre honnêtement au questionnaire (contenu généré limité aux pseudos et noms de ligue).
- **Sécurité** : TLS partout, secrets hachés (Argon2id pour `secret`), base non exposée (réseau Docker interne), pare-feu (22 restreint par clé, 80/443), mises à jour automatiques de sécurité, sauvegardes chiffrées.
- **Étiquettes de confidentialité App Store** (à déclarer, version serveur) : *Identifiants → Identifiant utilisateur* (fonctionnalité de l'appli, lié à l'utilisateur, pas de traçage) ; *Contenu utilisateur → Autre contenu* (pronostics, pseudo, nom de ligue) ; *Diagnostics* seulement si un outil de rapports de plantage est ajouté. Rien pour le traçage → pas d'App Tracking Transparency. **Avant le serveur** (TestFlight 2.0) : « Aucune donnée collectée » est exact (tout est local), à condition que l'appli n'envoie rien d'identifiant (les requêtes vers lolesports, Data Dragon et Leaguepedia ne transportent aucune donnée de l'utilisateur).
- **Manifeste de confidentialité** `PrivacyInfo.xcprivacy` dans l'appli et l'extension : données collectées (idem étiquettes) + API à « raison requise » (aujourd'hui aucune trouvée dans `App/`, `Shared/`, `Widgets/`, LoLKit : pas de `UserDefaults`, pas de dates de fichiers ; à revérifier à chaque lot, et pour toute bibliothèque ajoutée).

---

## 5. Exploitation

### 5.1 Supervision

- **Battement** : chaque tour du poller ping Healthchecks.io (gratuit) ; alerte si rien pendant 2 min → notification sur l'iPhone de Dan (application ntfy ou e-mail).
- **Disponibilité** externe : `GET /v1/meta` toutes les minutes (Healthchecks ou Uptime Kuma hébergé ailleurs).
- **Métriques** (`/metrics`, Prometheus, protégé) et tableau de bord minimal :
  - fraîcheur : âge de la dernière frame par match en direct (alerte > 3 min avec stats activées) ;
  - lolesports : taux d'erreurs par endpoint, nombre de 400 « ahead of broadcast », 403 (clé publique changée → **alerte immédiate** : l'appli et le serveur cassent ensemble) ;
  - APNs : envois par type, 4xx par raison, latence ; 410 purgés ;
  - base : taille, durée des sauvegardes, **date de la dernière sauvegarde réussie** (alerte > 26 h).
- **Erreurs** : Sentry (offre gratuite) ou GlitchTip auto-hébergé, sans données personnelles (identifiants hachés).
- **Mode dégradé** : si lolesports tombe, le serveur arrête d'envoyer (pas de faux état) ; la Live Activity passe d'elle-même « màj il y a X minutes » grâce à `stale-date`. Si APNs refuse tout : drapeau `pushLiveActivities: false` dans `/v1/meta` → l'appli reprend le mode local actuel.

### 5.2 Secrets

| Secret | Où | Jamais |
|---|---|---|
| Clé APNs `AuthKey_XXXX.p8` + Key ID + Team ID | Gestionnaire de mots de passe de Dan (original) ; serveur : `/etc/faille/secrets/` (root, `chmod 600`), monté en secret Docker | dépôt, `.superpowers/`, image Docker, journaux, conversation avec un agent |
| Clé API App Store Connect (`.p8`, pour la CI) | Gestionnaire + secret GitHub (base64) dans un **environnement protégé** | idem |
| Clé Sign in with Apple (`.p8`, pour révoquer à la suppression) | idem clé APNs | idem |
| Mot de passe Postgres, sel de hachage, clé de chiffrement des sauvegardes | `/etc/faille/secrets/` + gestionnaire | idem |
| Clé SSH de déploiement | secret GitHub (environnement protégé) + `authorized_keys` restreint | idem |

- Garde-fous : `.gitignore` avec `*.p8`, `*.p12`, `*.mobileprovision`, `secrets/` ; **gitleaks** en CI sur chaque push ; secrets GitHub dans un environnement `production` avec approbation manuelle (les PR de forks n'y ont pas accès).
- La clé publique lolesports (`x-api-key`) n'est pas un secret (le site l'envoie à chaque visiteur) ; elle reste une constante de `LoLKit/API`.

### 5.3 Rotation

- **APNs** : une clé d'authentification n'expire pas. Rotation annuelle ou immédiate en cas de doute : créer une 2e clé → déployer (le serveur accepte une liste de clés et signe avec la plus récente) → vérifier les envois → révoquer l'ancienne dans le portail. Le JWT, lui, est régénéré toutes les 40 min automatiquement.
- **Clé API App Store Connect** : rôle minimal (« App Manager » si suffisant pour signer/téléverser ; « Admin » seulement si la signature gérée dans le cloud l'exige), révocable sans impact sur les utilisateurs ; rotation annuelle.
- **Secret de compte compromis** : `POST /v1/session` révoque tous les jetons d'un compte au changement de secret.
- **Fuite d'un `.p8`** : révoquer dans le portail Apple (effet immédiat), créer une nouvelle clé, redéployer, noter l'incident.

### 5.4 Incidents et routine

- Runbook dans `server/RUNBOOK.md` (au moment de construire) : redémarrer, restaurer une sauvegarde, couper le push par drapeau, changer la clé lolesports.
- Routine mensuelle (≈ 1 h) : mises à jour d'images, test de restauration, lecture des métriques et des signalements.

---

## 6. Ce que l'appli doit changer

### 6.1 Identifiants et signature

- **Bundle IDs officiels** : `com.cafe1231.faille` (appli) et `com.cafe1231.faille.widgets` (extension), déjà dans `project.yml`. **Ruling : garder `com.cafe1231.faille` — pourquoi : déjà partout, invisible pour l'utilisateur, aucun code à changer — coût si faux : un bundle ID publié est définitif ; si Dan veut `com.echapstudio.faille`, il doit le décider AVANT de créer l'App ID demain (aucun autre coût aujourd'hui).**
- **App Group officiel** : `group.com.cafe1231.faille`, déclaré pour l'appli et l'extension (déjà dans `project.yml`).
- **Résolution du groupe à l'exécution** (`Shared/AppGroup.swift`, `Provisioning.swift`, `AppGroupResolver`) : **on la garde**. Avec un profil officiel, le premier candidat (profil embarqué) est `group.com.cafe1231.faille`, identique au nom configuré : le code donne le bon résultat sans changement, et il continue de servir pour une build AltServer de secours. La branche `ALTAppGroups` pourra être retirée une fois TestFlight éprouvé, **seulement** si plus aucune build AltServer n'est produite. Le message « réinstalle Faille avec AltServer » des widgets devient « réinstalle Faille » sur une build TestFlight/App Store (texte conditionné à la présence d'un profil AltServer).
- `project.yml` : configuration `Release` signée (`CODE_SIGN_STYLE: Automatic` + `DEVELOPMENT_TEAM` lu d'une variable de CI, ou `Manual` avec profils installés par la CI) ; la configuration actuelle non signée reste pour la CI de test et les aperçus. `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` : numéro de build = numéro de run CI (TestFlight refuse deux fois le même).
- **Entitlements de l'appli** : `com.apple.security.application-groups`, `aps-environment = production` (indispensable au push-to-start et aux notifications distantes), `com.apple.developer.applesignin = [Default]` (seulement en phase 2.2), `com.apple.developer.associated-domains = applinks:<domaine>` (liens d'invitation, phase 2.2). **Extension** : App Groups seulement.
- **Info.plist de l'appli** : garder `NSSupportsLiveActivities`, ajouter `NSSupportsLiveActivitiesFrequentUpdates = YES` ; `UIBackgroundModes` : garder `fetch` ; ajouter `remote-notification` **seulement** si on envoie un jour des push silencieux (ex. « calendrier changé → recharger les widgets ») — pas en phase 2.1. Ajouter `ITSAppUsesNonExemptEncryption = NO` (HTTPS standard seulement) pour éviter la question d'export à chaque build.
- **iPad** : `TARGETED_DEVICE_FAMILY: "1,2"` impose des captures iPad 13" sur la fiche App Store. Option à trancher à la publication : garder l'iPad (déjà testé en CI) ou publier iPhone seul en v1.

### 6.2 Couche `LiveUpdatesTransport`

Protocole dans `App/LiveActivity/` (iOS), choisi au démarrage :

```swift
protocol LiveUpdatesTransport: Sendable {
    /// Mode actuel : relecture locale (v1) ou push (phase 2).
    var kind: LiveUpdatesKind { get }
    /// Une Live Activity vient d'être créée localement : à quel type de push l'abonner (nil, .token, .channel(id)).
    func pushType(for match: LiveMatchAttributes) async -> PushType?
    /// Jetons reçus d'ActivityKit (push-to-start, activité) : à transmettre au serveur, ou ignorés en local.
    func didReceive(token: LiveUpdatesToken) async
    /// Faut-il encore relire localement toutes les 10 s au premier plan pour ce match ? (oui en local ; oui aussi en push,
    /// sous la règle de `updatedAt` monotone, pour rester fluide appli ouverte.)
    func shouldRefreshLocally(matchId: String) -> Bool
}
```

- `LocalRefreshTransport` = comportement actuel exact (`pushType: nil`, `BackgroundRefresh`), choisi si pas de serveur, pas d'autorisation de notifications, ou drapeau `/v1/meta` coupé.
- `PushTransport` : `Activity<LiveMatchAttributes>.pushToStartTokenUpdates` → `PUT /v1/devices` ; `pushTokenUpdates` d'une activité → `POST …/activities/{matchId}` (repli) ; activités démarrées par push détectées par `Activity.activityUpdates` pour que `LiveActivityController` les voie (anti-doublon existant : clé = `matchId`).
- `ActivityGateway.start` reçoit le `pushType` du transport au lieu de `nil` en dur ; c'est le **seul** changement dans le code qui touche ActivityKit.
- Règle commune : une mise à jour (locale ou push) n'est appliquée que si `state.updatedAt` > celui affiché.

### 6.3 Schéma local versionné et synchronisation

- Enveloppe pour les fichiers de l'utilisateur (`follows.json`, `settings.json`, `live-activities.json`, pronos) : `{ "schemaVersion": 2, "data": … }`, lue de façon tolérante (un fichier sans enveloppe = version 1, l'actuel). Les caches (`cache-*.json`) n'en ont pas besoin : jetables.
- Migrations écrites dans LoLKit (`LocalSchema.migrate(from:)`), testées sur des fichiers réels de la v1. Le comportement actuel « fichier illisible mis de côté, jamais écrasé » (`FileStore`) est conservé.
- Synchronisation : le téléphone reste la source de vérité pour les suivis et l'anti-spoiler (envoyés en entier à chaque changement, idempotent) ; le serveur est la source de vérité pour les pronostics verrouillés et les ligues (le téléphone garde une copie pour l'affichage hors ligne).

### 6.4 Nouveaux écrans / textes

- Réglages › **Notifications** : début de match (local), résultat (Rien / Terminé sans score / Score), Live Activity automatique sur l'écran verrouillé.
- Réglages › **Mes données** : exporter, supprimer le compte, lier Sign in with Apple, politique de confidentialité, mentions (« Faille n'est pas approuvé par Riot Games… », voir P4).
- **Pronos** : ligues, créer / rejoindre, signaler / bloquer.
- À propos : sources des données, version, contact.

---

## 7. Migration depuis l'appli sideloadée (AltServer)

- L'appli AltServer (`com.cafe1231.faille.TA6JYZWPU9`, groupe `group.com.cafe1231.faille.TA6JYZWPU9`) et l'appli TestFlight (`com.cafe1231.faille`) sont **deux applis différentes** sur l'iPhone : elles coexistent, et la nouvelle **ne voit pas** les fichiers de l'ancienne (conteneurs différents).
- Données à transporter : équipes suivies (+ anti-spoiler, couleurs), réglages, matchs révélés, pronostics solo. Les caches se reconstruisent seuls.
- **Plan** :
  1. Dernière build AltServer : bouton Réglages › Mes données › **« Exporter »** → fichier `faille-export.json` (enveloppe `schemaVersion`) via `ShareLink` (Fichiers / AirDrop).
  2. Build TestFlight : à l'onboarding et dans Réglages, **« Importer »** (`fileImporter`) ; aussi accepté à l'ouverture d'un fichier `.json` partagé vers Faille.
  3. Dan teste les deux côte à côte (widgets : choisir ceux de la nouvelle appli), puis supprime l'appli AltServer. Ses Live Activities en cours disparaissent avec elle.
- Pour Dan seul, re-suivre ses équipes à la main prend 2 minutes : l'export/import est surtout utile pour les pronos et pour les futurs testeurs. **Ruling : export/import par fichier plutôt que synchronisation serveur — pourquoi : marche dès la semaine 1, sans serveur ni compte — coût si faux : quelques heures, et l'import resservira de toute façon (changement d'iPhone sans compte).**
- AltServer reste un plan de secours : une build non signée continue de sortir de la CI.

---

## 8. Plan par phases (ce qui sort d'abord)

| Phase | Contenu | Dépend de | Terminé quand |
|---|---|---|---|
| **2.0 — TestFlight, sans serveur** (jours 1-3) | Compte, identifiants, CI signée + envoi TestFlight, `ITSAppUsesNonExemptEncryption`, manifeste de confidentialité, export/import, page de confidentialité « aucune donnée collectée ». Même appli qu'aujourd'hui, valable 90 jours par build, sans ré-signature tous les 7 jours. | Compte accepté | Dan installe Faille par TestFlight et y importe ses suivis |
| **2.1 — Push Live Activity** (semaine 1-2) | Serveur (poller, LiveEngine, APNs, appareils, suivis, révélations), `LiveUpdatesTransport`, push-to-start + canal + repli jeton, notifications de résultat masquées, supervision, sauvegardes. Testeurs internes (≤ 100, sans relecture Apple). | 2.0, VPS, domaine, clé APNs | Pendant un vrai match, la Live Activity démarre seule téléphone verrouillé et suit à ~10 s près (80 s derrière le direct) ; un match masqué ne montre rien |
| **2.2 — Ligues de pronos** (semaine 2-4) | Pronos serveur, ligues, codes et liens d'invitation, classement côté appli avec anti-spoiler, signaler/bloquer, Sign in with Apple facultatif, export/suppression. Testeurs externes (relecture bêta d'Apple, ~1 jour). | 2.1, lot pronos solo (idée 9) dans LoLKit | 10 amis jouent une semaine de Worlds sans spoiler ni triche au verrouillage |
| **2.3 — App Store public** | Fiche, captures, App Attest, relecture App Store. **Seulement après** les démarches Riot de la note P4 (enregistrement du produit, réponse sur les flux lolesports). | 2.2 + P4 | Faille publiée gratuitement, sans publicité |
| **2.4 — Monétisation** (éventuelle) | Abonnement « soutien » ou fonctions avancées par achat intégré, jamais de publicité dans une notification ou une Live Activity. **Seulement avec un accord écrit** (Riot et/ou GRID) — voir P4, risque n° 1. | Accord écrit, accord « Paid Apps » d'Apple, statut de commerçant DSA | — |
| Plus tard | Pick'em complet des Worlds, contrôle du Centre de contrôle (nouvelle extension, désormais possible), Apple Watch, widgets interactifs. | — | — |

---

## 9. Checklist exacte de Dan pour demain (dans l'ordre)

> Durées = temps de Dan devant l'écran ; les attentes d'Apple sont à part. Rien de tout ça n'a besoin d'un Mac.
> **Règle d'or : chaque fichier `.p8` téléchargé va dans le gestionnaire de mots de passe, jamais dans le dossier du dépôt, jamais dans une conversation.**

### Étape 0 — Décider le vendeur (15 min, avant de payer)
- [ ] **Individuel ou organisation ?** Apple : en individuel, **ton nom légal** s'affiche comme vendeur ; en organisation, le nom de la **personne morale**, qui doit avoir un numéro **D-U-N-S** (gratuit, quelques jours à quelques semaines) et un site web sur son domaine ; Apple **refuse les noms commerciaux** (« DBA », nom d'enseigne). Une entreprise individuelle (EI / micro) n'est pas une personne morale distincte → « Echap Studio » ne peut s'afficher que si c'est une société (SASU, EURL…).
- [ ] **Recommandation** : si Echap Studio n'est pas déjà une société immatriculée avec un D-U-N-S, **inscris-toi en individuel demain** (TestFlight tout de suite), et passe en organisation plus tard (migration possible par le support Apple) avant la sortie publique ou la monétisation.
- [ ] Choisis maintenant si le bundle ID reste `com.cafe1231.faille` (recommandé) — définitif une fois l'appli créée.

### Étape 1 — Inscription au programme (30 min + attente 0 à 48 h)
- [ ] Sur l'iPhone, app **Apple Developer** → Compte → S'inscrire (vérification d'identité par pièce d'identité, possible sans Mac). Apple ID avec double authentification, **nom légal exact**, adresse réelle (pas de boîte postale).
- [ ] Payer 99 $/an (prix local TTC affiché). Attendre l'e-mail « Welcome to the Apple Developer Program ».

### Étape 2 — Pendant l'attente (≈ 1 h 30)
- [ ] **Domaine** (15 min) : acheter un domaine court (ex. vérifier `faille.app`, `failleapp.fr`, `echap.studio`…), chez un registrar UE (OVH, Gandi). Pas de domaine contenant « lol », « league », « riot » (P4 §8).
- [ ] **VPS** (20 min) : compte Hetzner, projet « faille », serveur ARM ou x86 le moins cher en Allemagne/Finlande, Ubuntu 24.04, **clé SSH seulement** (pas de mot de passe), sauvegardes activées. Note l'IP ; enregistrement DNS `api.<domaine>` → IP. Je fais la suite (Docker, Caddy, pare-feu) en session.
- [ ] **Adresse de contact** (10 min) : `contact@<domaine>` et `privacy@<domaine>` (redirections e-mail du registrar).
- [ ] **Page de confidentialité** (20 min) : je fournis le texte (version 2.0 « aucune donnée collectée », version 2.1 complète d'après §4) ; publication sur GitHub Pages ou `https://<domaine>/confidentialite`. Même chose pour une page « Assistance » (obligatoire sur la fiche) avec l'adresse de contact.
- [ ] **Recherche de nom** (20 min) : « Faille » sur l'App Store, sur data.inpi.fr et TMview (EUIPO), classes 9 et 41 (P4 §8).

### Étape 3 — Après acceptation : accords et conformité (15 min)
- [ ] App Store Connect → **Business** : accepter le contrat du programme ; « Paid Apps » (banque, fiscalité) **seulement plus tard** si monétisation.
- [ ] Déclarer le **statut de commerçant DSA** (UE) : gratuit et sans activité commerciale → « non-commerçant » défendable ; dès qu'il y a monétisation → commerçant, et Apple publie **adresse, téléphone et e-mail** sur la fiche UE (prévoir une adresse et un numéro professionnels).

### Étape 4 — Identifiants et capacités (20 min) — developer.apple.com › Certificates, Identifiers & Profiles
- [ ] **App Group** : `group.com.cafe1231.faille`.
- [ ] **App ID** explicite `com.cafe1231.faille` : cocher **App Groups** (associer le groupe), **Push Notifications** ; *(phase 2.2)* **Sign in with Apple**, **Associated Domains**.
- [ ] **App ID** explicite `com.cafe1231.faille.widgets` : **App Groups** (même groupe).
- [ ] Noter le **Team ID** (10 caractères, page Membership).

### Étape 5 — Clés (15 min)
- [ ] **Clé APNs** : Keys → « + » → nom « Faille APNs » → cocher **Apple Push Notifications service (APNs)** (environnement : Sandbox & Production) → télécharger `AuthKey_<KEYID>.p8` (**téléchargeable une seule fois**) → gestionnaire de mots de passe avec le Key ID et le Team ID. Ne pas la copier dans le dépôt ni l'envoyer par chat ; on la posera ensemble sur le serveur par `scp` au moment de 2.1.
- [ ] **Clé API App Store Connect** (pour la CI) : App Store Connect → Utilisateurs et accès → Intégrations → Clés d'API de l'équipe → rôle **App Manager** (ou Admin si la signature gérée par le cloud l'exige) → télécharger le `.p8` (une seule fois), noter **Issuer ID** et **Key ID**.
- [ ] Ajouter dans GitHub (dépôt → Settings → Environments → `release`, avec approbation) les secrets : `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `APPLE_TEAM_ID`. (Je fournis la commande PowerShell pour l'encodage base64, exécutée en local par toi.)

### Étape 6 — App Store Connect : l'appli (15 min)
- [ ] Apps → « + » → Nouvelle app : plateforme iOS, nom **Faille** (s'il est pris : « Faille — esport » ou autre, sans marque Riot), langue principale **français**, bundle ID `com.cafe1231.faille`, SKU `faille-001`, accès complet.
- [ ] Renseigner l'URL de confidentialité et l'URL d'assistance (étape 2).
- [ ] **Confidentialité de l'app** (étiquettes) : pour 2.0, « Données non collectées » (§4). À mettre à jour avant 2.1.

### Étape 7 — Première build TestFlight (≈ 15 min pour toi ; la CI et moi faisons le reste)
- [ ] Je modifie `ios.yml` + `project.yml` (signature Release, numéro de build, envoi vers TestFlight) ; tu approuves le premier déploiement dans GitHub (environnement `release`).
- [ ] TestFlight → **Test interne** → groupe « Dan » → t'ajouter ; installer l'app **TestFlight** sur l'iPhone → installer Faille. Pas de relecture Apple pour les testeurs internes. Conformité de chiffrement : réglée par `ITSAppUsesNonExemptEncryption = NO`.
- [ ] Ouvrir l'ancienne appli AltServer → Exporter ; la nouvelle → Importer (§7).

### Étape 8 — Riot (30 min, pas bloquant pour TestFlight, bloquant pour la sortie publique)
- [ ] Compte sur **developer.riotgames.com** (avec ton compte Riot), lire les politiques, **enregistrer le produit « Faille »** (description honnête : appli compagnon gratuite, sources de données utilisées) et poser par écrit les questions de la note P4 §11.

**Total devant l'écran : ≈ 3 h 30**, réparties sur la journée ; le seul vrai temps mort est l'acceptation du compte.

### Ce qui est déjà prêt côté appli (au 15/10)
- Bundle IDs et App Group officiels déjà dans `project.yml` ; résolution du groupe à l'exécution compatible avec un profil officiel.
- Contrat `LiveMatchState` figé par la fixture dorée `live_contract.json`, conforme à `ActivityAttributes` (`ContentState = LiveMatchState`) : prêt à être poussé tel quel.
- Anti-spoiler en une seule fonction (`SpoilerPolicy.isMasked`, `LiveMatchState.masked()`), réutilisable par le serveur.
- Règle des 80 s (`LoLClient.liveWindow`) dans LoLKit, compilée sur Linux.
- Notifications locales et leur routeur de liens profonds.
- À faire en session (pas par Dan) : `LiveUpdatesTransport`, enveloppe `schemaVersion`, export/import, `PrivacyInfo.xcprivacy`, CI signée, dossier `server/`.

---

## 10. Risques et points ouverts

| Risque | Effet | Parade |
|---|---|---|
| Riot demande l'arrêt de l'usage des flux non officiels, ou change l'API (GraphQL) | Appli et serveur sans données | Dépendance isolée dans `LoLKit/API` ; démarche Riot avant la sortie publique ; P4. |
| Budget de mises à jour des Live Activities plus serré que prévu | Live Activity moins fraîche | Priorité 5 pour la routine, 10 pour les événements ; `NSSupportsLiveActivitiesFrequentUpdates` ; mesurer en 2.1. |
| Le flux a 80 s de retard | « Direct » décalé | Normal pour ce flux ; dit dans À propos. Ne pas promettre « temps réel ». |
| Spoiler par le classement d'une ligue ou une notification | Promesse cassée | Classement calculé dans l'appli sans les matchs masqués ; aucune notification de ligue ; résultat masqué = « Rien » par défaut. |
| Triche au verrouillage des pronos | Ligues faussées | Horloge serveur, début = calendrier ou `getLive`, le premier des deux. |
| Panne du VPS unique | Pas de push le temps de la panne | L'appli retombe sur le mode local (drapeau / délai) ; sauvegardes testées ; reconstruction en < 1 h par Docker Compose. |
| Fuite d'une clé `.p8` | Envoi de push par un tiers | Jamais dans le dépôt, gitleaks, révocation immédiate (§5.3). |
| Contenu offensant (pseudos, noms de ligue) | Rejet App Store (1.2) | Filtre, signaler, bloquer, contact publié. |
