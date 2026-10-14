import Foundation
import LoLKit

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
    static func apply(_ reminders: [MatchReminder], enabled: Bool, center: any ReminderCenter) async {
        let ours = await center.pendingIdentifiers().filter { $0.hasPrefix(identifierPrefix) }
        var allowed = false
        if enabled {
            allowed = await center.authorization() == .authorized
        }
        let wanted = allowed ? reminders : []
        let wantedIds = Set(wanted.map(\.id))
        let stale = ours.filter { !wantedIds.contains($0) }
        if !stale.isEmpty {
            await center.remove(identifiers: stale)
        }
        for reminder in wanted {
            try? await center.add(reminder)
        }
    }
}
