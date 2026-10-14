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

// MARK: - Live Activities (étape 4, Task 6)

extension AppStore {
    /// Live Activities à jour (spec §6.4) : retraits à la main reconnus, mises à jour et fins, puis démarrages si
    /// `canStart` (premier plan seulement). Sans effet dans les aperçus et les tests hébergés.
    func syncLiveActivities(canStart: Bool) async {
        await liveActivities.sync(live: live, follows: follows, mode: settings.liveActivityMode, canStart: canStart,
                                  now: Date()) { matchId in
            self.activityContent(matchId: matchId)
        }
    }

    /// Après un masquage (œil) ou une révélation (spec §8) : la Live Activity suit tout de suite, avec ce que le store
    /// sait déjà (le masquage ne doit pas attendre le réseau), puis une seconde fois avec les stats relues (celles d'un
    /// match qui vient d'être révélé).
    func refreshActivitiesAfterSpoilerChange() async {
        await syncLiveActivities(canStart: false)
        await refreshLiveStats()
        await syncLiveActivities(canStart: true)
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : enregistré tout de suite, la Live Activity démarre aussitôt.
    func pinActivity(matchId: String) -> PinOutcome {
        let outcome = liveActivities.pin(matchId: matchId)
        if outcome == .pinned {
            runWithScene { await self.syncLiveActivities(canStart: true) }
        }
        return outcome
    }

    /// « Retirer de l'écran verrouillé » : tout de suite, et plus jamais recréée automatiquement pour ce match.
    func removeActivity(matchId: String) {
        runWithScene { await self.liveActivities.remove(matchId: matchId) }
    }
}

// MARK: - Arrière-plan (étape 4, Task 7)

extension AppStore {
    /// Réveil par iOS (`BGAppRefreshTask`, spec §6.4) : le direct et les stats des matchs suivis (ni logos ni couleurs :
    /// le temps accordé est compté, environ 30 s), puis les Live Activities — sans en démarrer, iOS ne le permet pas
    /// en arrière-plan —, puis la demande du réveil suivant. Sans effet dans les aperçus et les tests.
    func refreshInBackground() async {
        await refreshDue(opening: false)
        await syncLiveActivities(canStart: false)
        scheduleBackgroundRefresh()
    }

    /// Passage en arrière-plan (spec §6.4) : une dernière mise à jour des Live Activities avec ce que l'appli sait, puis
    /// la demande du premier réveil.
    func enterBackground() async {
        await syncLiveActivities(canStart: false)
        scheduleBackgroundRefresh()
    }

    /// Dans 15 min si un match suivi est en direct ou si une Live Activity est à l'écran ; sinon, plus aucune demande.
    func scheduleBackgroundRefresh(now: Date = Date()) {
        BackgroundRefresh.schedule(at: LiveActivityPlanner.nextBackgroundRefresh(
            now: now, live: live, follows: follows, hasActivities: !liveActivities.shownMatchIds.isEmpty))
    }
}
