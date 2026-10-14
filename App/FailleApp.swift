import SwiftUI
import UserNotifications

/// Le store unique de l'appli : la scène, le passage en arrière-plan et la tâche d'arrière-plan d'iOS (qui peut réveiller
/// l'appli sans aucune scène au premier plan) partagent le même.
@MainActor
enum AppRuntime {
    /// Dans les tests hébergés, un store figé et inerte : le vrai ne doit ni lire le disque de l'appli ni appeler l'API.
    static let store: AppStore = RunEnvironment.isTesting
        ? AppStore(preview: .empty)
        : AppStore(files: FileStore(directory: AppGroup.directory))
    /// Notification de début de match touchée → Détail du match (spec fonctionnalités §2).
    static let notificationRouter = NotificationRouter()
    /// Délégué de `UNUserNotificationCenter`, retenu ici : le centre ne garde qu'une référence faible.
    static let notificationDelegate = ReminderNotificationDelegate(router: notificationRouter)

    static func refreshInBackground() async {
        await store.refreshInBackground()
    }
}

@main
struct FailleApp: App {
    @State private var store = AppRuntime.store
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Avant la fin du lancement : une notification touchée qui lance l'appli doit trouver son délégué.
        if !RunEnvironment.isTesting {
            UNUserNotificationCenter.current().delegate = AppRuntime.notificationDelegate
        }
    }

    var body: some Scene {
        WindowGroup {
            if RunEnvironment.isTesting {
                // Tests hébergés : ni interface ni réseau, les tests rendent leurs propres fenêtres.
                Color.clear
            } else {
                RootView(router: AppRuntime.notificationRouter)
                    .environment(store)
                    // Rafraîchit tant que la scène est active ; la tâche (et ses requêtes) est annulée en arrière-plan.
                    .task(id: scenePhase) {
                        guard scenePhase == .active else { return }
                        await store.poll()
                    }
                    // Passage en arrière-plan (spec §6.4) : dernière mise à jour des Live Activities, puis demande du
                    // premier réveil si un match suivi est en direct.
                    .onChange(of: scenePhase) { _, phase in
                        guard phase == .background else { return }
                        BackgroundRefresh.finishInBackground {
                            await AppRuntime.store.enterBackground()
                        }
                    }
            }
        }
        // Réveil par iOS environ toutes les 15 min tant qu'un match suivi est en direct (spec §6.4), si l'actualisation
        // en arrière-plan n'est pas coupée.
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await AppRuntime.refreshInBackground()
        }
    }
}
