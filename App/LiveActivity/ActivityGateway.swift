import ActivityKit
import Foundation
import LoLKit

/// Une Live Activity existante, recopiée en valeurs Sendable : les objets `Activity` ne quittent jamais `ActivityGateway`.
struct RunningActivity: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        /// Active ou « pas fraîche » : on peut encore la mettre à jour.
        case running
        /// Terminée mais encore affichée (fin de match : 1 h) : elle compte dans la limite de 3.
        case ended
        /// Retirée de l'écran.
        case gone
    }

    let matchId: String
    let attributes: LiveMatchAttributes
    let state: LiveMatchState
    let phase: Phase

    var isRunning: Bool { phase == .running }
    /// À l'écran (en cours ou terminée) : compte dans la limite de 3.
    var isVisible: Bool { phase != .gone }
}

/// Le seul code qui touche ActivityKit (spec §6.4, sans push : `pushType: nil`). Les fonctions synchrones s'exécutent
/// sur l'acteur principal ; les fonctions asynchrones sont non isolées et ne reçoivent que des valeurs Sendable : les
/// `Activity`, non Sendable, restent locales à chaque appel et ne traversent jamais d'acteur (Swift 6).
enum ActivityGateway {
    /// Live Activities autorisées par iOS (faux si l'utilisateur les a coupées, et sur iPad).
    @MainActor
    static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Les Live Activities de Faille, en cours ou terminées.
    @MainActor
    static func running() -> [RunningActivity] {
        Activity<LiveMatchAttributes>.activities.map { activity in
            RunningActivity(matchId: activity.attributes.matchId, attributes: activity.attributes,
                            state: activity.content.state, phase: phase(activity.activityState))
        }
    }

    /// Démarre une Live Activity (au premier plan seulement : iOS refuse en arrière-plan).
    @MainActor
    static func start(attributes: LiveMatchAttributes, state: LiveMatchState) throws {
        _ = try Activity<LiveMatchAttributes>.request(attributes: attributes, content: content(state), pushType: nil)
    }

    static func update(matchId: String, state: LiveMatchState) async {
        for activity in Activity<LiveMatchAttributes>.activities where activity.attributes.matchId == matchId {
            await activity.update(content(state))
        }
    }

    /// Termine la Live Activity d'un match : contenu final (nil : le dernier), retrait à `dismissAt` (nil : tout de suite).
    static func end(matchId: String, state: LiveMatchState?, dismissAt: Date?) async {
        let policy: ActivityUIDismissalPolicy
        if let dismissAt {
            policy = .after(dismissAt)
        } else {
            policy = .immediate
        }
        for activity in Activity<LiveMatchAttributes>.activities where activity.attributes.matchId == matchId {
            await activity.end(state.map { content($0) }, dismissalPolicy: policy)
        }
    }

    /// `staleDate = updatedAt + 180 s` (spec §6.4) : passé cette date, iOS affiche la Live Activity « pas fraîche ».
    private static func content(_ state: LiveMatchState) -> ActivityContent<LiveMatchState> {
        ActivityContent(state: state, staleDate: state.staleDate)
    }

    private static func phase(_ state: ActivityState) -> RunningActivity.Phase {
        switch state {
        case .active, .stale: return .running
        case .ended: return .ended
        case .dismissed: return .gone
        @unknown default: return .running
        }
    }
}
