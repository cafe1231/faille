import Foundation
import LoLKit

// MARK: - Contenu des Live Activities (étape 4, Task 3)

extension AppStore {
    /// Contenu de la Live Activity d'un match (spec §4.3, §6) : attributs (pour la démarrer) et état, anti-spoiler
    /// compris. `updatedAt` est la dernière relecture réussie de la donnée qui le nourrit : le direct, ou, pour un match
    /// sorti du direct, le calendrier — jamais l'heure de réception de la frame, qui reste l'ancre du chrono.
    /// Un match que l'API dit terminé est « terminé » même sans série gagnée (`displayed(for:)` : forfait, Bo2).
    /// - Returns: nil s'il n'y a rien de neuf sur ce match (ni dans le direct, ni terminé au calendrier, ni série gagnée
    ///   dans ses détails) : la Live Activity garde alors son contenu et passe « pas fraîche » d'elle-même.
    func activityContent(matchId: String) -> LiveActivityContent? {
        if let event = live?.first(where: { $0.id == matchId }) {
            let details = EventDetails(event: event)
            let built = self.state(details: details, statsDisabled: event.statsDisabled, updatedAt: lastSuccess[.live])
            return LiveActivityContent(details: details, state: built.displayed(for: event), follows: follows)
        }
        // Sorti du direct : le calendrier, relu aussitôt (spec §10), dit s'il est terminé ; sinon on attend.
        if let event = schedule.first(where: { $0.id == matchId }), event.state == .completed {
            let details = EventDetails(event: event)
            let built = self.state(details: details, statsDisabled: event.statsDisabled, updatedAt: lastSuccess[.schedule])
            return LiveActivityContent(details: details, state: built.displayed(for: event), follows: follows)
        }
        // Ni dans le direct, ni terminé au calendrier (compétition hors des ligues suivies, équipe plus suivie) : les
        // détails du match (relus par `refreshLiveStats` pour les Live Activities à l'écran). Fini seulement si la série
        // est gagnée.
        if let loaded = details[matchId] {
            let built = self.state(details: loaded, statsDisabled: loaded.statsDisabled, updatedAt: nil)
            if built.phase == .finished {
                return LiveActivityContent(details: loaded, state: built, follows: follows)
            }
        }
        return nil
    }
}
