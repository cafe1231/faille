# Étape 0 — Chaîne de bout en bout : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** prouver qu'une appli iOS avec extension widget, App Group et Live Activity, compilée sur un Mac cloud depuis un dépôt GitHub, s'installe sur l'iPhone de Dan avec Sideloadly et un Apple ID gratuit, et que le widget lit ce que l'appli écrit.

**Architecture :** une appli « sonde » jetable. Le projet Xcode est décrit dans `project.yml` (XcodeGen) et généré en CI. GitHub Actions (macOS) compile sans signature, signe en ad hoc avec les entitlements, empaquette une `.ipa` et la publie en artefact. Dan la télécharge et l'installe avec Sideloadly sur Windows.

**Tech Stack :** XcodeGen, SwiftUI, WidgetKit, ActivityKit, GitHub Actions (`macos-26`), Sideloadly.

**Spec :** `docs/superpowers/specs/2026-10-13-faille-design.md` (§2, §3, §13 étape 0, §10 plan B).

## Global Constraints

- iOS minimum : **26.0** ; appareils iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- Bundle ID appli : `com.cafe1231.faille` ; extension : `com.cafe1231.faille.widgets` ; App Group : `group.com.cafe1231.faille`.
- Nom affiché : **Faille**.
- Dépôt GitHub **public** `cafe1231/faille`. **Aucun secret** dans le dépôt, jamais.
- Commits signés avec `45066362+cafe1231@users.noreply.github.com` (déjà configuré en local dans ce dépôt — vérifier avec `git config user.email`). Chaque message de commit se termine par la ligne `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` (second `-m`).
- Fins de ligne LF (`.gitattributes` déjà présent).
- Le projet `.xcodeproj`, `Info.plist` et `.entitlements` sont **générés** par XcodeGen et ignorés par Git ; seul `project.yml` est versionné.
- Langue de l'interface : français.
- Le code de cette étape est **jetable** (sonde) : il sera remplacé par l'appli réelle aux étapes 2 à 4. Swift 5 language mode pour la sonde, afin d'éviter les erreurs de concurrence stricte sur ActivityKit pendant l'expérience.

---

### Task 1 : Publier le dépôt sur GitHub

**Files :** aucun fichier créé ; remote `origin` ajouté.

**Interfaces :**
- Consumes : dépôt Git local existant (branche `main`, commit de la spec).
- Produces : dépôt public `https://github.com/cafe1231/faille`, remote `origin`.

- [ ] **Step 1 : Demander la confirmation de Dan**

Publier un dépôt est une action visible publiquement. Avant de lancer la commande, demander explicitement à Dan : « Je crée le dépôt public `cafe1231/faille` et j'y pousse la spec, les plans, les maquettes et l'étude de marché. OK ? ». Ne continuer qu'après un oui.

- [ ] **Step 2 : Vérifier qu'aucun secret ni e-mail perso n'est dans l'historique**

Run :
```bash
git log --format='%ae' | sort -u
git ls-files | grep -Ei '\.(p8|p12|mobileprovision|env)$' || echo "aucun fichier sensible"
```
Expected : une seule adresse `45066362+cafe1231@users.noreply.github.com`, puis `aucun fichier sensible`.

- [ ] **Step 3 : Créer le dépôt et pousser**

Run :
```bash
gh repo create cafe1231/faille --public --source . --remote origin --push --description "Faille — suivre les matchs LoL esport en direct sur l'écran verrouillé (appli iOS perso)"
```
Expected : `✓ Created repository cafe1231/faille on GitHub` puis `✓ Pushed commits`.

- [ ] **Step 4 : Vérifier**

Run : `gh repo view cafe1231/faille --json visibility,defaultBranchRef --jq '.visibility + " " + .defaultBranchRef.name'`
Expected : `PUBLIC main`

---

### Task 2 : Appli sonde (appli + widget + Live Activity) décrite par XcodeGen

**Files :**
- Create : `project.yml`
- Create : `Shared/ProbeStore.swift`
- Create : `Shared/ProbeAttributes.swift`
- Create : `App/FailleApp.swift`
- Create : `App/ProbeView.swift`
- Create : `Widgets/FailleWidgets.swift`
- Modify : `.gitignore` (ajouter les fichiers générés par XcodeGen)

**Interfaces :**
- Consumes : rien.
- Produces : cibles Xcode `Faille` (application) et `FailleWidgets` (app-extension) ; schéma `Faille` ; entitlements générés `App/Faille.entitlements` et `Widgets/FailleWidgets.entitlements` (utilisés par la Task 3 pour la signature ad hoc) ; produit `Faille.app` contenant `PlugIns/FailleWidgets.appex`.

Cette tâche n'a pas de test automatisé possible sur Windows (pas de compilateur iOS) : sa vérification est la compilation en CI de la Task 3. Écrire les fichiers avec soin, puis passer à la Task 3 avant de commiter si on veut un seul commit vert ; sinon commiter ici et corriger en Task 3.

- [ ] **Step 1 : Écrire `project.yml`**

```yaml
name: Faille
options:
  bundleIdPrefix: com.cafe1231
  deploymentTarget:
    iOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.0"
    MARKETING_VERSION: "0.0.1"
    CURRENT_PROJECT_VERSION: "1"
    TARGETED_DEVICE_FAMILY: "1,2"
    CODE_SIGNING_ALLOWED: "NO"
    CODE_SIGNING_REQUIRED: "NO"
targets:
  Faille:
    type: application
    platform: iOS
    sources:
      - App
      - Shared
    dependencies:
      - target: FailleWidgets
    scheme: {}
    entitlements:
      path: App/Faille.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.cafe1231.faille
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Faille
        UILaunchScreen: {}
        NSSupportsLiveActivities: true
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        UISupportedInterfaceOrientations~ipad:
          - UIInterfaceOrientationPortrait
          - UIInterfaceOrientationPortraitUpsideDown
          - UIInterfaceOrientationLandscapeLeft
          - UIInterfaceOrientationLandscapeRight
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille
  FailleWidgets:
    type: app-extension
    platform: iOS
    sources:
      - Widgets
      - Shared
    entitlements:
      path: Widgets/FailleWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.cafe1231.faille
    info:
      path: Widgets/Info.plist
      properties:
        CFBundleDisplayName: Faille
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.cafe1231.faille.widgets
```

- [ ] **Step 2 : Écrire `Shared/ProbeStore.swift`** (compilé dans l'appli et l'extension)

```swift
import Foundation

/// Sonde de l'étape 0 : l'appli écrit une date dans l'App Group, le widget la relit.
enum ProbeStore {
    static let appGroup = "group.com.cafe1231.faille"
    private static let key = "probe.lastWrite"

    static var groupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    static func write(_ date: Date) {
        UserDefaults(suiteName: appGroup)?.set(date.timeIntervalSince1970, forKey: key)
    }

    static func read() -> Date? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}
```

- [ ] **Step 3 : Écrire `Shared/ProbeAttributes.swift`**

```swift
import ActivityKit
import Foundation

/// Live Activity de test : un compteur et l'heure de la dernière mise à jour.
struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tick: Int
        var updatedAt: Date
    }

    var title: String
}
```

- [ ] **Step 4 : Écrire `App/FailleApp.swift`**

```swift
import SwiftUI

@main
struct FailleApp: App {
    var body: some Scene {
        WindowGroup {
            ProbeView()
        }
    }
}
```

- [ ] **Step 5 : Écrire `App/ProbeView.swift`**

```swift
import ActivityKit
import SwiftUI
import WidgetKit

/// Écran de la sonde : teste l'App Group et la Live Activity sur un vrai iPhone.
struct ProbeView: View {
    @State private var lastWrite: Date? = ProbeStore.read()
    @State private var activityStatus = "aucune"
    @State private var tick = 0

    var body: some View {
        NavigationStack {
            List {
                Section("App Group") {
                    LabeledContent("Conteneur partagé", value: ProbeStore.groupAvailable ? "OK" : "INDISPONIBLE")
                    LabeledContent("Dernière écriture", value: lastWrite.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                    Button("Écrire l'heure pour le widget") {
                        let now = Date()
                        ProbeStore.write(now)
                        lastWrite = now
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
                Section("Live Activity") {
                    LabeledContent("Autorisées", value: ActivityAuthorizationInfo().areActivitiesEnabled ? "oui" : "non")
                    LabeledContent("État", value: activityStatus)
                    Button("Démarrer") { start() }
                    Button("Mettre à jour (+1)") { Task { await update() } }
                    Button("Arrêter", role: .destructive) { Task { await stop() } }
                }
            }
            .navigationTitle("Faille · sonde")
        }
    }

    private func start() {
        do {
            let state = ProbeAttributes.ContentState(tick: tick, updatedAt: .now)
            _ = try Activity.request(
                attributes: ProbeAttributes(title: "Sonde"),
                content: .init(state: state, staleDate: nil)
            )
            activityStatus = "démarrée"
        } catch {
            activityStatus = "erreur : \(error.localizedDescription)"
        }
    }

    private func update() async {
        tick += 1
        let state = ProbeAttributes.ContentState(tick: tick, updatedAt: .now)
        for activity in Activity<ProbeAttributes>.activities {
            await activity.update(.init(state: state, staleDate: nil))
        }
        activityStatus = "mise à jour \(tick)"
    }

    private func stop() async {
        for activity in Activity<ProbeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        activityStatus = "arrêtée"
    }
}
```

- [ ] **Step 6 : Écrire `Widgets/FailleWidgets.swift`**

```swift
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        ProbeWidget()
        ProbeLiveActivity()
    }
}

struct ProbeEntry: TimelineEntry {
    let date: Date
    let lastWrite: Date?
    let groupOK: Bool
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, lastWrite: nil, groupOK: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> ProbeEntry {
        ProbeEntry(date: .now, lastWrite: ProbeStore.read(), groupOK: ProbeStore.groupAvailable)
    }
}

struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProbeWidget", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sonde Faille")
        .description("Vérifie le partage entre l'appli et le widget.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Faille · \(entry.groupOK ? "groupe OK" : "groupe KO")")
                .font(.caption2)
            Text(entry.lastWrite.map { $0.formatted(date: .omitted, time: .shortened) } ?? "rien lu")
                .font(.headline)
        }
    }
}

struct ProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            HStack {
                Text("Sonde Faille").bold()
                Spacer()
                Text("tick \(context.state.tick)")
                Text(context.state.updatedAt, style: .time)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("tick \(context.state.tick)")
                }
            } compactLeading: {
                Text("F")
            } compactTrailing: {
                Text("\(context.state.tick)")
            } minimal: {
                Text("\(context.state.tick)")
            }
        }
    }
}
```

- [ ] **Step 7 : Ignorer les fichiers générés par XcodeGen**

Ajouter à la fin de `.gitignore` :
```gitignore

# Générés par XcodeGen depuis project.yml
App/Info.plist
App/Faille.entitlements
Widgets/Info.plist
Widgets/FailleWidgets.entitlements
```

- [ ] **Step 8 : Commit**

```bash
git add project.yml Shared App Widgets .gitignore
git commit -m "feat: appli sonde de l'étape 0 (App Group, widget, Live Activity)"
```

---

### Task 3 : Compilation iOS sur Mac cloud et `.ipa` en artefact

**Files :**
- Create : `.github/workflows/ios.yml`

**Interfaces :**
- Consumes : `project.yml`, cibles `Faille` / `FailleWidgets`, schéma `Faille`, entitlements générés (Task 2).
- Produces : artefact GitHub Actions nommé `Faille-ipa` contenant `Faille.ipa` (appli + extension signées ad hoc avec leurs entitlements).

- [ ] **Step 1 : Écrire `.github/workflows/ios.yml`**

```yaml
name: iOS

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  build:
    # Si ce label n'existe pas sur GitHub, utiliser macos-latest.
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Générer le projet Xcode
        run: |
          brew install xcodegen
          xcodegen generate

      - name: Compiler sans signature
        run: |
          xcodebuild -project Faille.xcodeproj -scheme Faille -configuration Release \
            -destination 'generic/platform=iOS' -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO build

      - name: Signer en ad hoc avec les entitlements
        # Sideloadly re-signe ensuite avec l'Apple ID de Dan ; il lit les entitlements embarqués ici.
        run: |
          APP=build/Build/Products/Release-iphoneos/Faille.app
          codesign --force --sign - --entitlements Widgets/FailleWidgets.entitlements "$APP/PlugIns/FailleWidgets.appex"
          codesign --force --sign - --entitlements App/Faille.entitlements "$APP"
          codesign -d --entitlements - "$APP"
          codesign -d --entitlements - "$APP/PlugIns/FailleWidgets.appex"

      - name: Empaqueter l'IPA
        run: |
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/Faille.app Payload/
          zip -qry Faille.ipa Payload

      - uses: actions/upload-artifact@v4
        with:
          name: Faille-ipa
          path: Faille.ipa
          retention-days: 14
```

- [ ] **Step 2 : Commit et push**

```bash
git add .github/workflows/ios.yml
git commit -m "ci: compilation iOS non signée et IPA en artefact"
git push
```

- [ ] **Step 3 : Suivre le run**

Run : `gh run watch --exit-status $(gh run list --workflow iOS --limit 1 --json databaseId --jq '.[0].databaseId')`
Expected : toutes les étapes vertes. Dans les logs de « Signer en ad hoc », les deux blocs d'entitlements contiennent `group.com.cafe1231.faille`.

Si le run échoue : lire le log (`gh run view --log-failed`), corriger `project.yml` ou le code Swift de la Task 2, commit, push, recommencer. Erreurs fréquentes :
- « Unable to find a destination » → vérifier que l'Xcode choisi a la plateforme iOS (`xcodebuild -showsdks` dans un step de debug).
- Label `macos-26` inconnu → remplacer par `macos-latest`.

- [ ] **Step 4 : Télécharger l'IPA**

Run :
```bash
mkdir -p "$HOME/Downloads/faille" && gh run download --name Faille-ipa --dir "$HOME/Downloads/faille"
ls -la "$HOME/Downloads/faille"
```
Expected : `Faille.ipa` (quelques centaines de Ko à quelques Mo).

---

### Task 4 : Installation sur l'iPhone et verdict

Cette tâche est faite **par Dan** sur son PC et son iPhone, guidé pas à pas. L'agent n'installe rien sur le PC lui-même.

**Files :**
- Create : `docs/superpowers/notes/2026-10-etape-0-verdict.md`
- Modify : `docs/superpowers/specs/2026-10-13-faille-design.md` (§14, une ligne de résultat)

**Interfaces :**
- Consumes : `Faille.ipa` (Task 3).
- Produces : verdict écrit, qui conditionne les plans des étapes 2 à 4 : **App Group OK** (architecture de la spec) ou **App Group KO** (plan B du §10 : le widget charge ses données lui-même).

- [ ] **Step 1 : Préparer le PC (Dan)**

1. Installer **Sideloadly** depuis le site officiel `https://sideloadly.io` (version Windows).
2. Si Sideloadly le demande : installer **iTunes** et **iCloud** depuis les liens fournis par Sideloadly (versions hors Microsoft Store).
3. Brancher l'iPhone en USB, le déverrouiller, accepter « Faire confiance à cet ordinateur ».

- [ ] **Step 2 : Installer l'appli (Dan)**

1. Ouvrir Sideloadly, glisser `Downloads/faille/Faille.ipa` dans la fenêtre.
2. Choisir l'iPhone, saisir l'Apple ID (Sideloadly le transmet à Apple ; l'agent ne le voit jamais).
3. Cliquer **Start**. Attendre « Done ».
4. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur → activer** (redémarrage demandé).
5. Sur l'iPhone : **Réglages → Général → VPN et gestion de l'appareil →** l'Apple ID → **Faire confiance**.

- [ ] **Step 3 : Tester l'App Group (Dan)**

1. Ouvrir **Faille**. Noter la valeur de « Conteneur partagé » (OK ou INDISPONIBLE).
2. Appuyer sur « Écrire l'heure pour le widget ».
3. Ajouter le widget **Sonde Faille** sur l'écran d'accueil (petit) et sur l'écran verrouillé (rectangulaire).
4. Le widget doit afficher « groupe OK » et l'heure écrite à l'étape 2.

- [ ] **Step 4 : Tester la Live Activity (Dan)**

1. Dans Faille, appuyer sur « Démarrer ».
2. Verrouiller l'iPhone : la carte « Sonde Faille · tick 0 » doit apparaître sur l'écran verrouillé ; la Dynamic Island affiche « F » et « 0 ».
3. Déverrouiller, appuyer sur « Mettre à jour (+1) », reverrouiller : « tick 1 ».
4. Appuyer sur « Arrêter » : la carte disparaît.

- [ ] **Step 5 : Écrire le verdict**

Créer `docs/superpowers/notes/2026-10-etape-0-verdict.md` avec les réponses réelles de Dan :

```markdown
# Étape 0 — verdict (date)

| Vérification | Résultat |
|---|---|
| Compilation CI + IPA | OK / KO (lien du run) |
| Installation Sideloadly (Apple ID gratuit) | OK / KO |
| « Conteneur partagé » dans l'appli | OK / INDISPONIBLE |
| Widget lit l'heure écrite par l'appli | oui / non |
| Live Activity : démarrage, mise à jour, arrêt | oui / non |
| Dynamic Island | oui / non |

**Décision :** architecture App Group de la spec / plan B du §10.
**Notes :** (messages d'erreur, captures, surprises)
```

Puis ajouter à la fin de la liste « Risques et points ouverts » du §14 de la spec une ligne `- **Étape 0 (date)** : <décision>, voir docs/superpowers/notes/2026-10-etape-0-verdict.md`.

- [ ] **Step 6 : Commit**

```bash
git add docs/superpowers/notes docs/superpowers/specs/2026-10-13-faille-design.md
git commit -m "docs: verdict de l'étape 0"
git push
```
