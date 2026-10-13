# Étape 0 — verdict (13/10/2026)

iPhone de Dan sous iOS 27.0, Apple ID gratuit, PC Windows sans Mac.

| Vérification | Résultat |
|---|---|
| Compilation CI + IPA | OK — run 38395994959 (sonde v1), run 38399905354 (sonde v2), vertes du premier coup sur `macos-26` / Xcode 26.6 |
| Installation Sideloadly 0.70.1 (Apple ID gratuit) | appli OK, mais **extension installée sans profil** et **aucun groupe d'apps**, avec ou sans « Use automatic bundle ID » |
| Installation **AltServer** (Apple ID gratuit) | **OK** — appli et extension signées, chacune avec son profil |
| Identifiants réels après AltServer | appli `com.cafe1231.faille.TA6JYZWPU9`, extension `com.cafe1231.faille.TA6JYZWPU9.widgets`, groupe `group.com.cafe1231.faille.TA6JYZWPU9` |
| « Conteneur partagé » dans l'appli | OK (groupe lu dans `embedded.mobileprovision`) |
| Widget lit l'heure écrite par l'appli | oui |
| Live Activity : démarrage, mise à jour, arrêt | oui |
| Dynamic Island | oui |

**Décision :** architecture App Group de la spec, avec installation par **AltServer**.

**Conséquences pour les étapes suivantes :**
- Le nom du groupe d'apps est **résolu à l'exécution** (profil embarqué, puis `ALTAppGroups`, puis nom configuré ; le premier dont `containerURL` n'est pas nil), dans l'appli et dans l'extension. Aucun bundle ID n'est supposé fixe.
- Sideloadly n'est plus utilisé. Repli si AltServer casse : Impactor, puis compte Apple Developer payant.
- Avec un compte gratuit : 10 identifiants d'app par semaine (l'appli en consomme 2 à chaque nouvel identifiant), profils valables 7 jours.
