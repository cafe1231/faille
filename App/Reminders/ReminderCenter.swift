import Foundation
import LoLKit
import os

/// Autorisation des notifications, telle que l'appli la lit.
enum ReminderAuthorization: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// Centre des notifications locales (spec fonctionnalités §2) : `SystemReminderCenter` (`UNUserNotificationCenter`) dans
/// l'appli, `InertReminderCenter` dans les aperçus et les tests hébergés, un faux dans les tests unitaires.
protocol ReminderCenter: Sendable {
    func authorization() async -> ReminderAuthorization
    /// Demande l'autorisation à iOS (alertes et sons) ; vrai si elle est accordée.
    func requestAuthorization() async -> Bool
    /// Identifiants des notifications en attente, de Faille ou non.
    func pendingIdentifiers() async -> [String]
    func remove(identifiers: [String]) async
    /// Programme une notification ; un identifiant déjà programmé est remplacé.
    func add(_ reminder: MatchReminder) async throws
}

/// Aperçus et tests hébergés : rien n'est demandé à iOS ni programmé.
struct InertReminderCenter: ReminderCenter {
    func authorization() async -> ReminderAuthorization { .notDetermined }
    func requestAuthorization() async -> Bool { false }
    func pendingIdentifiers() async -> [String] { [] }
    func remove(identifiers: [String]) async {}
    func add(_ reminder: MatchReminder) async throws {}
}

extension Logger {
    /// Journal des notifications de début de match : le journal d'iOS est la seule trace d'un refus de `add` ou de
    /// `requestAuthorization` (comme pour `live-activity` et `arrière-plan`), le code d'iOS ne tournant que sur la CI.
    static let notifications = Logger(subsystem: "Faille", category: "notifications")
}

/// Ce qu'une notification de Faille transporte : l'id du match à ouvrir quand on la touche (spec fonctionnalités §2).
enum ReminderPayload {
    static let matchIdKey = "matchId"

    static func userInfo(matchId: String) -> [String: String] {
        [matchIdKey: matchId]
    }

    /// Id du match d'une notification touchée ; nil si elle ne vient pas de Faille.
    static func matchId(from userInfo: [AnyHashable: Any]) -> String? {
        guard let id = userInfo[matchIdKey] as? String, !id.isEmpty else { return nil }
        return id
    }
}

/// Programmation des notifications de début de match : celles de Faille (préfixe `match-start-`) sont remplacées par le
/// plan de LoLKit (`MatchReminders.plan`) ; celles d'autres origines ne sont jamais touchées.
enum ReminderSync {
    static let identifierPrefix = MatchReminders.identifier(matchId: "")

    /// - Parameters:
    ///   - reminders: plan de LoLKit (au plus 60, les plus proches d'abord).
    ///   - enabled: réglage « Notifications de début de match ».
    ///
    /// Au mieux : un refus d'iOS pour une notification est journalisé et ne lève rien, la passe suivante réessaie. Une
    /// passe annulée (la tâche de la scène est relancée dès que le plan change, sans attendre la précédente) ne touche plus
    /// à rien : sa fin tardive ne doit pas défaire ce que la nouvelle passe vient de programmer ou de retirer.
    static func apply(_ reminders: [MatchReminder], enabled: Bool, center: any ReminderCenter) async {
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(identifierPrefix) }
        var allowed = false
        if enabled {
            allowed = await center.authorization() == .authorized
        }
        let wanted = allowed ? reminders : []
        let wantedIds = Set(wanted.map(\.id))
        let stale = ours.filter { !wantedIds.contains($0) }
        guard !Task.isCancelled else { return }
        if !stale.isEmpty {
            await center.remove(identifiers: stale)
        }
        for reminder in wanted {
            guard !Task.isCancelled else { return }
            do {
                try await center.add(reminder)
            } catch {
                Logger.notifications.error(
                    "Notification de \(reminder.matchId, privacy: .public) non programmée : \(String(describing: error), privacy: .public)")
            }
        }
    }
}
