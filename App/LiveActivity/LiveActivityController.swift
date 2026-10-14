import Foundation
import LoLKit
import Observation
import os

/// Réponse du bouton « Épingler sur l'écran verrouillé ».
enum PinOutcome: Equatable {
    case pinned
    /// 3 Live Activities sont déjà à l'écran (spec §6.4) : il faut en retirer une.
    case full
    /// Live Activities désactivées dans les réglages d'iOS (ou iPad) : le bouton explique où les réactiver (spec §10).
    case disabled
}

/// Les Live Activities de Faille (spec §6) : seul objet qui décide quoi démarrer, mettre à jour et terminer, et seul à
/// appeler ActivityKit (par `ActivityGateway`). Les décisions elles-mêmes sont dans LoLKit (`LiveActivityPlanner`,
/// `LiveActivityChoices`) ; le contenu de chaque match vient du store (`AppStore.activityContent`).
@MainActor
@Observable
final class LiveActivityController {
    /// Matchs dont la Live Activity est à l'écran (en cours, ou terminée et encore affichée).
    private(set) var shownMatchIds: Set<String> = []
    /// Live Activities autorisées par iOS (faux si l'utilisateur les a coupées, et sur iPad).
    private(set) var isEnabled: Bool
    /// Épinglés, retirés à la main, démarrés par l'appli ; enregistrés dans `live-activities.json`.
    private(set) var choices: LiveActivityChoices

    private let files: FileStore?
    /// Faux dans les tests hébergés et les aperçus : rien n'est demandé à ActivityKit (les choix restent enregistrés).
    private let usesActivityKit: Bool
    /// Un `sync` a déjà eu lieu depuis le lancement.
    @ObservationIgnored private var hasSynced = false
    /// Échecs de démarrage déjà journalisés (match et cause) : un tour de 10 s ne répète pas la même ligne.
    @ObservationIgnored private var loggedStartFailures: Set<String> = []

    private static let log = Logger(subsystem: "Faille", category: "live-activity")

    init(files: FileStore?, usesActivityKit: Bool) {
        self.files = files
        self.usesActivityKit = usesActivityKit
        choices = files?.load(LiveActivityChoices.self, from: .liveActivities) ?? LiveActivityChoices()
        isEnabled = usesActivityKit ? ActivityGateway.isEnabled : true
        if usesActivityKit {
            shownMatchIds = Set(ActivityGateway.running().filter(\.isVisible).map(\.matchId))
        }
    }

    /// Aperçus (#Preview, PNG) : ces matchs ont une Live Activity ; rien n'est lu, écrit ni demandé à ActivityKit.
    init(preview shown: Set<String>) {
        files = nil
        usesActivityKit = false
        choices = LiveActivityChoices()
        isEnabled = true
        shownMatchIds = shown
    }

    /// Une passe complète (spec §6.4) :
    /// 1. les Live Activities démarrées par l'appli et disparues depuis ont été retirées à la main : jamais recréées ;
    /// 2. chaque Live Activity en cours est mise à jour ou terminée (`LiveActivityPlanner.decision`) — ActivityKit n'est
    ///    appelé que pour ce qui a changé ;
    /// 3. si `canStart` (premier plan) et si le direct est connu : démarrage des nouvelles, dans les places libres.
    ///
    /// La première passe après le lancement ne peut pas distinguer « toutes retirées » de « liste pas encore remplie »
    /// quand l'appli a noté des Live Activities qu'elle a démarrées (`choices.started`) et qu'iOS n'en liste aucune :
    /// elle ne réconcilie pas (un faux retrait serait définitif) et ne démarre rien (elle recréerait une Live Activity
    /// que l'utilisateur vient de retirer, ou en doublon) ; la passe du tour suivant, 10 s plus tard, fait les deux.
    /// Sans rien de noté, il n'y a rien à confondre : la première passe démarre tout de suite (ouvrir Faille puis
    /// verrouiller aussitôt ne laisse pas le match sans Live Activity — l'arrière-plan ne peut pas en démarrer).
    /// - Parameter content: contenu actuel d'un match (`AppStore.activityContent`), nil s'il n'y a rien de neuf.
    func sync(live: [MatchEvent]?, follows: FollowList, mode: LiveActivityMode, canStart: Bool, now: Date,
              content: (String) -> LiveActivityContent?) async {
        guard usesActivityKit else { return }
        let enabled = ActivityGateway.isEnabled
        if enabled != isEnabled {
            isEnabled = enabled
        }
        let before = choices

        let running = ActivityGateway.running()
        let verified = Self.isListVerified(hasSynced: hasSynced, iosListsAny: !running.isEmpty,
                                           appStartedAny: !choices.started.isEmpty)
        hasSynced = true
        if verified {
            choices.reconcile(running: Set(running.filter(\.isRunning).map(\.matchId)), now: now)
        }
        let kept = choices.pruned(now: now)
        if kept != choices {
            choices = kept
        }

        for activity in running where activity.isRunning {
            let decision = LiveActivityPlanner.decision(
                attributes: activity.attributes, current: activity.state, latest: content(activity.matchId),
                isPinned: choices.isPinned(activity.matchId), mode: mode, now: now)
            switch decision {
            case .keep:
                break
            case let .update(state):
                await ActivityGateway.update(matchId: activity.matchId, state: state)
            case let .end(state, dismissAt):
                // Noté AVANT la fin : la réconciliation ne doit pas y voir un retrait à la main.
                choices.markEnded(activity.matchId)
                await ActivityGateway.end(matchId: activity.matchId, state: state, dismissAt: dismissAt)
            }
        }

        if canStart, verified, enabled, let live {
            let visible = ActivityGateway.running().filter(\.isVisible).map(\.matchId)
            let target = LiveActivityPlanner.plan(live: live, follows: follows, mode: mode, pinned: choices.pinnedIds,
                                                  dismissed: choices.dismissedIds, active: visible)
            for matchId in target where !visible.contains(matchId) {
                // Pas de démarrage sans contenu ni ids d'équipe (attributs) : journalisé, c'est un match épinglé ou
                // suivi qui n'aura pas sa Live Activity.
                guard let start = content(matchId), let attributes = start.attributes else {
                    logStartFailure(matchId, "contenu ou ids d'équipe manquants")
                    continue
                }
                // Pas de démarrage non plus pour un match déjà fini.
                guard start.state.phase != .finished else { continue }
                do {
                    try ActivityGateway.start(attributes: attributes, state: start.state)
                    choices.markStarted(matchId, now: now)
                } catch {
                    logStartFailure(matchId, String(describing: error))
                }
            }
        }

        let shown = Set(ActivityGateway.running().filter(\.isVisible).map(\.matchId))
        if shown != shownMatchIds {
            shownMatchIds = shown
        }
        if choices != before {
            save()
        }
    }

    /// La liste d'iOS est-elle assez sûre pour réconcilier et démarrer ? Oui dès qu'un `sync` a déjà eu lieu, qu'iOS
    /// liste quelque chose, ou que l'appli n'a noté aucune Live Activity démarrée (rien à réconcilier, aucun retrait à
    /// la main possible). Seul cas « non » : le lancement, quand l'appli a des Live Activities notées et qu'iOS n'en
    /// liste aucune.
    nonisolated static func isListVerified(hasSynced: Bool, iosListsAny: Bool, appStartedAny: Bool) -> Bool {
        hasSynced || iosListsAny || !appStartedAny
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : enregistré tout de suite ; la Live Activity démarre au `sync`
    /// suivant, que le store lance aussitôt. Refusé si iOS les a désactivées ou si 3 sont déjà à l'écran.
    func pin(matchId: String, now: Date = Date()) -> PinOutcome {
        guard isEnabled else { return .disabled }
        if !shownMatchIds.contains(matchId), shownMatchIds.count >= LiveActivityPlanner.maxConcurrent {
            return .full
        }
        choices.pin(matchId, now: now)
        save()
        return .pinned
    }

    /// « Retirer de l'écran verrouillé » : la Live Activity s'en va tout de suite et n'est plus recréée automatiquement.
    func remove(matchId: String, now: Date = Date()) async {
        choices.dismiss(matchId, now: now)
        save()
        if shownMatchIds.contains(matchId) {
            shownMatchIds.remove(matchId)
        }
        guard usesActivityKit else { return }
        await ActivityGateway.end(matchId: matchId, state: nil, dismissAt: nil)
    }

    private func save() {
        files?.save(choices, to: .liveActivities)
    }

    /// Pourquoi un match épinglé n'a pas démarré faute de direct : `sync` ne démarre que les matchs que le direct liste
    /// et n'a donc rien à journaliser dans ces deux cas. nil : le direct liste le match (si rien ne s'affiche, la cause
    /// est un échec déjà journalisé par `sync`, ou la première passe après le lancement, qui reporte son démarrage).
    nonisolated static func pinFailureReason(matchId: String, live: [MatchEvent]?) -> String? {
        guard let live else { return "direct inconnu" }
        return live.contains { $0.id == matchId } ? nil : "absent du direct"
    }

    /// À appeler après le `sync` qui suit un « Épingler » : si le match épinglé n'est pas à l'écran à cause du direct,
    /// l'écrit au journal (niveau error, comme les autres échecs de démarrage ; pas d'écran pour le dire).
    func reportPinWithoutActivity(matchId: String, live: [MatchEvent]?) {
        guard usesActivityKit, !shownMatchIds.contains(matchId),
              let reason = Self.pinFailureReason(matchId: matchId, live: live) else { return }
        logStartFailure(matchId, reason)
    }

    /// Un démarrage qui échoue (pas d'ids d'équipe, `Activity.request` qui lève : limite d'iOS, autorisation retirée…)
    /// est journalisé une fois par match et par cause : sans écran pour le dire, le journal est la seule trace.
    private func logStartFailure(_ matchId: String, _ reason: String) {
        guard loggedStartFailures.insert("\(matchId)|\(reason)").inserted else { return }
        Self.log.error("Live Activity de \(matchId, privacy: .public) non démarrée : \(reason, privacy: .public)")
    }
}
