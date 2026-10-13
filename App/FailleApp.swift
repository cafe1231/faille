import SwiftUI

@main
struct FailleApp: App {
    /// Dans les tests hébergés, un store figé et inerte : le vrai ne doit ni lire le disque de l'appli ni appeler l'API.
    @State private var store = RunEnvironment.isTesting
        ? AppStore(preview: .empty)
        : AppStore(files: FileStore(directory: AppGroup.directory))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if RunEnvironment.isTesting {
                // Tests hébergés : ni interface ni réseau, les tests rendent leurs propres fenêtres.
                Color.clear
            } else {
                RootView()
                    .environment(store)
                    // Rafraîchit tant que la scène est active ; la tâche (et ses requêtes) est annulée en arrière-plan.
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        await store.poll()
                    }
            }
        }
    }
}
