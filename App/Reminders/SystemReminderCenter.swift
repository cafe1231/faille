import Foundation
import LoLKit
import UserNotifications

/// Notifications locales d'iOS (`UNUserNotificationCenter`, spec fonctionnalités §2) : aucune n'est envoyée par un serveur.
/// Le centre est relu à chaque appel : rien de non `Sendable` n'est gardé.
struct SystemReminderCenter: ReminderCenter {
    func authorization() async -> ReminderAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func remove(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ reminder: MatchReminder) async throws {
        try await UNUserNotificationCenter.current().add(Self.request(for: reminder))
    }

    /// Requête iOS d'une notification de début de match : titre « KC vs C9 dans 15 min », sous-titre
    /// « Mondial · Play-in · Bo5 » (LoLKit : jamais de score), son par défaut, id du match pour ouvrir son Détail au
    /// toucher ; déclenchée à l'heure dite (date du calendrier, pas un compte à rebours).
    static func request(for reminder: MatchReminder, calendar: Calendar = .current) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.subtitle = reminder.subtitle
        content.sound = .default
        content.threadIdentifier = "match-start"
        content.userInfo = ReminderPayload.userInfo(matchId: reminder.matchId)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }
}

/// Délégué des notifications (spec fonctionnalités §2) : toucher une notification de Faille ouvre le Détail du match
/// (par `NotificationRouter`) ; au premier plan, elle s'affiche quand même. Posé au lancement par `FailleApp`, avant la fin
/// du démarrage : un toucher qui lance l'appli le trouve déjà là.
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    let router: NotificationRouter

    init(router: NotificationRouter) {
        self.router = router
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let matchId = ReminderPayload.matchId(from: response.notification.request.content.userInfo)
        let target = router
        Task { @MainActor in
            if let matchId {
                target.open(matchId: matchId)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
