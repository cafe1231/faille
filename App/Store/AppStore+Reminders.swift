import Foundation
import LoLKit

/// Ce qui oblige à reprogrammer les notifications : le réglage et le plan de LoLKit. Il change quand le calendrier, les
/// équipes suivies, les révélations ou les réglages changent (spec fonctionnalités §2), et quand une notification passe
/// son heure. Sert d'`id` à la tâche de la scène qui reprogramme (`FailleApp`).
struct ReminderSignature: Equatable, Sendable {
    let enabled: Bool
    let reminders: [MatchReminder]
}

// MARK: - Notifications de début de match (fonctionnalités, Task 2)

extension AppStore {
    /// Notifications à programmer maintenant ; aucune si le réglage est coupé. La sélection (le prochain match de chaque
    /// équipe suivie que `Presenter.nextLine` montre, 60 au plus, jamais un match caché par l'anti-spoiler) et les textes
    /// (jamais de score) viennent de LoLKit (`MatchReminders.plan`).
    func plannedReminders(now: Date = Date()) -> [MatchReminder] {
        guard settings.matchRemindersEnabled else { return [] }
        return MatchReminders.plan(schedule: schedule, follows: follows, revealed: settings.revealedMatchIds, now: now,
                                   lead: settings.matchReminderLead)
    }

    var reminderSignature: ReminderSignature {
        ReminderSignature(enabled: settings.matchRemindersEnabled, reminders: plannedReminders())
    }

    /// Reprogramme les notifications de Faille (celles des autres applis ne sont jamais touchées). Rien tant que
    /// `follows.json` est illisible : la liste des équipes suivies serait vide par défaut, et on supprimerait des
    /// notifications voulues (même règle que pour les Live Activities).
    func syncReminders(center: any ReminderCenter, now: Date = Date()) async {
        guard !followsUnreadable else { return }
        await ReminderSync.apply(plannedReminders(now: now), enabled: settings.matchRemindersEnabled, center: center)
    }
}
