import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// Une ligne du diagnostic : libellé + valeur (le libellé sert aussi de préfixe dans le texte copié).
private struct DiagLine: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Écran de la sonde : teste l'App Group et la Live Activity sur un vrai iPhone.
struct ProbeView: View {
    @State private var lastWrite: Date? = ProbeStore.read()
    @State private var activityStatus = "aucune"
    @State private var tick = 0
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostic") {
                    ForEach(diagnostic) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(line.value)
                                .textSelection(.enabled)
                        }
                    }
                    Button("Copier le diagnostic") { copyDiagnostic() }
                    if copied {
                        Text("copié ✓")
                            .foregroundStyle(.green)
                    }
                }
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

    /// Ce que la signature de Sideloadly a réellement produit (identifiants, profils, groupes, extension).
    private var diagnostic: [DiagLine] {
        let appInfo = Provisioning.read(bundleURL: Bundle.main.bundleURL)
        let plugInsURL = Bundle.main.builtInPlugInsURL
        let appexURL = plugInsURL?.appendingPathComponent("FailleWidgets.appex")
        let appexPresent = appexURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

        var lines: [DiagLine] = []
        lines.append(DiagLine(label: "Identifiant de l'appli", value: Bundle.main.bundleIdentifier ?? "—"))

        if let info = appInfo {
            let expiration = info.expiration.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—"
            lines.append(DiagLine(label: "Profil", value: "\(info.profileName ?? "—"), expire le \(expiration)"))
            lines.append(DiagLine(label: "Équipe (teamID)", value: info.teamID ?? "—"))
            lines.append(DiagLine(label: "application-identifier du profil", value: info.appID ?? "—"))
            lines.append(DiagLine(
                label: "Groupes d'apps du profil de l'appli",
                value: info.appGroups.isEmpty ? "aucun" : info.appGroups.joined(separator: ", ")
            ))
        } else {
            lines.append(DiagLine(label: "Profil", value: "aucun profil embarqué"))
            lines.append(DiagLine(label: "Équipe (teamID)", value: "—"))
            lines.append(DiagLine(label: "application-identifier du profil", value: "—"))
            lines.append(DiagLine(label: "Groupes d'apps du profil de l'appli", value: "aucun"))
        }

        lines.append(DiagLine(
            label: "Groupe utilisé",
            value: "\(ProbeStore.appGroup), conteneur \(ProbeStore.groupAvailable ? "OK" : "INDISPONIBLE")"
        ))

        lines.append(DiagLine(label: "Extension widget", value: appexPresent ? "présente" : "ABSENTE"))
        if let appexURL, appexPresent {
            lines.append(DiagLine(
                label: "Identifiant de l'extension",
                value: Bundle(url: appexURL)?.bundleIdentifier ?? "—"
            ))
            let groups = Provisioning.read(bundleURL: appexURL)?.appGroups
            lines.append(DiagLine(
                label: "Groupes d'apps du profil de l'extension",
                value: groups.map { $0.isEmpty ? "aucun" : $0.joined(separator: ", ") } ?? "pas de profil"
            ))
        }
        // Utile si Sideloadly a renommé ou retiré l'extension : ce qui est réellement dans PlugIns.
        let plugIns = plugInsURL.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        lines.append(DiagLine(
            label: "Contenu de PlugIns",
            value: plugIns.isEmpty ? "vide ou absent" : plugIns.sorted().joined(separator: ", ")
        ))

        lines.append(DiagLine(label: "Version iOS", value: UIDevice.current.systemVersion))
        return lines
    }

    private func copyDiagnostic() {
        UIPasteboard.general.string = diagnostic
            .map { "\($0.label) : \($0.value)" }
            .joined(separator: "\n")
        copied = true
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
