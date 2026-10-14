import Foundation
import LoLKit

/// Ce qui oblige à reprogrammer les notifications : le réglage et le plan de LoLKit. Il change quand le calendrier, les
/// équipes suivies, les révélations ou les réglages changent (spec fonctionnalités §2), et quand une notification passe
/// son heure. Sert d'`id` à la tâche qui reprogramme (`RootView`).
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

    /// Reprogramme les notifications de Faille (celles des autres applis ne sont jamais touchées). Appelée par l'écran
    /// (`RootView`, dès que le plan change) et par chaque rafraîchissement d'arrière-plan (`refreshInBackground`,
    /// `enterBackground`) : un réveil d'iOS n'a aucune scène. Rien tant que `follows.json` ou `settings.json` est
    /// illisible : la liste des équipes suivies serait vide, et le réglage coupé, par défaut ; on supprimerait des
    /// notifications voulues (même règle que pour les Live Activities).
    func syncReminders(center: any ReminderCenter, now: Date = Date()) async {
        guard !followsUnreadable, !settingsUnreadable else { return }
        await ReminderSync.apply(plannedReminders(now: now), enabled: settings.matchRemindersEnabled, center: center)
    }
}
