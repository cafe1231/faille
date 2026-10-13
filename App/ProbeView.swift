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
