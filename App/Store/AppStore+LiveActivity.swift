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
    /// Rien ne bouge tant que `follows.json` est illisible : la liste des équipes suivies est alors vide par défaut, donc
    /// plus aucun œil (spec §8) — une Live Activity mise à jour ou démarrée maintenant ne serait pas masquée. Elle garde
    /// son dernier contenu (et passe « pas fraîche » d'elle-même) jusqu'à ce que la liste soit relue, à la prochaine
    /// modification de l'utilisateur (`syncFollowsBeforeChange`).
    func syncLiveActivities(canStart: Bool) async {
        guard !followsUnreadable else { return }
        await liveActivities.sync(live: live, follows: follows, mode: settings.liveActivityMode, canStart: canStart,
                                  now: Date()) { matchId in
            self.activityContent(matchId: matchId)
        }
    }

    /// Après un masquage (œil) ou une révélation (spec §8) : la Live Activity suit tout de suite, avec ce que le store
    /// sait déjà (le masquage ne doit pas attendre le réseau), puis les stats sont relues. La seconde passe
    /// (`canStart: true`) ne renvoie pas ces stats à la Live Activity : après une révélation elle rend `.keep` (même
    /// `updatedAt`, même `spoilerFree`, voir `LiveActivityPlanner.decision`). Les stats d'un match qui vient d'être révélé
    /// n'y arrivent qu'à la prochaine relecture réussie du direct (60 s au plus), qui change `updatedAt`.
    func refreshActivitiesAfterSpoilerChange() async {
        await syncLiveActivities(canStart: false)
        await refreshLiveStats()
        guard !Task.isCancelled else { return }
        await syncLiveActivities(canStart: true)
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : enregistré tout de suite, la Live Activity démarre aussitôt.
    /// Si elle ne peut pas démarrer faute de direct (inconnu, ou sans ce match), le journal le dit.
    func pinActivity(matchId: String) -> PinOutcome {
        let outcome = liveActivities.pin(matchId: matchId)
        if outcome == .pinned {
            runWithScene {
                await self.syncLiveActivities(canStart: true)
                // Une scène qui quitte le premier plan pendant la passe : on ne sait pas si elle a abouti.
                guard !Task.isCancelled else { return }
                self.liveActivities.reportPinWithoutActivity(matchId: matchId, live: self.live)
            }
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
    /// Le réveil suivant est demandé dès le début : si le temps accordé expire pendant les requêtes, la chaîne de réveils
    /// ne s'arrête pas là ; la demande de la fin, plus fraîche (le direct vient d'être relu), remplace la première.
    /// Les notifications de début de match sont reprogrammées avec le calendrier qui vient d'être relu (spec fonctionnalités
    /// §2) : sans scène, aucun écran ne le ferait (le prochain match d'une équipe, quand le précédent est terminé).
    func refreshInBackground() async {
        recordBackgroundWake()
        scheduleBackgroundRefresh()
        await refreshDue(opening: false)
        await syncLiveActivities(canStart: false)
        scheduleBackgroundRefresh()
        await syncReminders(center: reminderCenter)
    }

    /// Passage en arrière-plan (spec §6.4) : une dernière mise à jour des Live Activities et des notifications avec ce que
    /// l'appli sait, puis la demande du premier réveil.
    func enterBackground() async {
        // Un vrai passage en arrière-plan : la prochaine session de collecte repart d'un budget neuf (I-2).
        noteBackgroundPassage()
        await syncLiveActivities(canStart: false)
        await syncReminders(center: reminderCenter)
        scheduleBackgroundRefresh()
    }

    /// Dans 15 min si un match suivi est en direct ou si une Live Activity est à l'écran ; sinon, plus aucune demande.
    /// Ce qu'iOS en a dit est noté pour le diagnostic de À propos.
    func scheduleBackgroundRefresh(now: Date = Date()) {
        let outcome = BackgroundRefresh.schedule(at: LiveActivityPlanner.nextBackgroundRefresh(
            now: now, live: live, follows: follows, hasActivities: !liveActivities.shownMatchIds.isEmpty))
        recordWakeRequest(outcome, at: now)
    }

    /// Les quatre lignes du bloc « Diagnostic Live Activity » de À propos : autorisation d'iOS, dernier échec de
    /// démarrage, dernier réveil reçu, dernière demande de réveil.
    func liveActivityDiagnosticLines(now: Date = Date()) -> [LiveActivityDiagnosticText.Line] {
        LiveActivityDiagnosticText.lines(enabled: liveActivities.isEnabled, failure: liveActivities.lastStartFailure,
                                         background: backgroundDiagnostic, now: now)
    }
}
