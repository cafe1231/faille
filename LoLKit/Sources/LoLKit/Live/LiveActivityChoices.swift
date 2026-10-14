import Foundation

/// Choix de l'utilisateur sur les Live Activities (spec §6.4), enregistrés par l'appli dans `live-activities.json` :
/// - `pinned` : matchs épinglés depuis le Détail (prioritaires, gardés en mode manuel) ;
/// - `dismissed` : matchs dont la Live Activity a été retirée à la main — jamais recréée automatiquement ;
/// - `started` : matchs dont l'appli a démarré la Live Activity et qu'elle n'a pas terminée elle-même. Une Live Activity
///   de cette liste qui n'est plus en cours a été retirée par l'utilisateur (ou par iOS) pendant que l'appli dormait.
/// Épinglés et retirés restent disjoints : chaque opération enlève l'id de l'autre liste. Chaque marque est datée et
/// oubliée au bout de 24 h (un match ne dure jamais aussi longtemps).
public struct LiveActivityChoices: Codable, Sendable, Equatable {
    public static let retention: TimeInterval = 24 * 3600
    /// Délai après le démarrage pendant lequel une Live Activity absente de la liste « en cours » est encore neuve :
    /// iOS peut ne pas la lister tout de suite, elle n'est pas pour autant retirée à la main (`reconcile`), et l'appli
    /// ne la redémarre pas non plus (`recentlyStarted`).
    public static let reconcileGrace: TimeInterval = 30

    public private(set) var pinned: [String: Date]
    public private(set) var dismissed: [String: Date]
    public private(set) var started: [String: Date]

    public init(pinned: [String: Date] = [:], dismissed: [String: Date] = [:], started: [String: Date] = [:]) {
        self.pinned = pinned
        self.dismissed = dismissed
        self.started = started
    }

    private enum CodingKeys: String, CodingKey {
        case pinned, dismissed, started
    }

    /// Décodage tolérant : une liste absente ou illisible est vide, les autres sont gardées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinned = (try? container.decodeIfPresent([String: Date].self, forKey: .pinned)) ?? [:]
        dismissed = (try? container.decodeIfPresent([String: Date].self, forKey: .dismissed)) ?? [:]
        started = (try? container.decodeIfPresent([String: Date].self, forKey: .started)) ?? [:]
    }

    /// Épinglés, du plus ancien au plus récent (priorité de `LiveActivityPlanner.plan`).
    public var pinnedIds: [String] {
        pinned.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
    }

    public var dismissedIds: Set<String> {
        Set(dismissed.keys)
    }

    public func isPinned(_ matchId: String) -> Bool {
        pinned[matchId] != nil
    }

    /// « Épingler sur l'écran verrouillé » : prioritaire, et n'est plus « retiré ». Un match déjà épinglé garde sa place.
    public mutating func pin(_ matchId: String, now: Date) {
        dismissed[matchId] = nil
        if pinned[matchId] == nil {
            pinned[matchId] = now
        }
    }

    /// « Retirer de l'écran verrouillé », ou glissement sur l'écran verrouillé : plus épinglé, jamais recréé
    /// automatiquement.
    public mutating func dismiss(_ matchId: String, now: Date) {
        pinned[matchId] = nil
        started[matchId] = nil
        dismissed[matchId] = now
    }

    /// L'appli vient de démarrer la Live Activity de ce match.
    public mutating func markStarted(_ matchId: String, now: Date) {
        started[matchId] = now
    }

    /// L'appli termine elle-même cette Live Activity (match fini, mode manuel) : ce n'est pas un retrait à la main.
    public mutating func markEnded(_ matchId: String) {
        started[matchId] = nil
    }

    /// L'appli a démarré la Live Activity de ce match il y a au plus `reconcileGrace` (30 s) : si iOS ne la liste pas
    /// encore, elle existe quand même, et l'appli n'en démarre pas une seconde (doublon). C'est exactement le
    /// complément de `reconcile` : à 30 s pile, elle n'est ni retirée à la main ni à redémarrer.
    public func recentlyStarted(_ matchId: String, now: Date) -> Bool {
        guard let startedAt = started[matchId] else { return false }
        return now.timeIntervalSince(startedAt) <= Self.reconcileGrace
    }

    /// Les Live Activities démarrées par l'appli depuis plus de 30 s (`reconcileGrace`) qui ne sont plus en cours
    /// (`running`) sans qu'elle les ait terminées ont été retirées à la main (ou par iOS) : elles passent dans
    /// `dismissed`. Une entrée plus récente absente de `running` reste dans `started` (iOS peut tarder à la lister).
    public mutating func reconcile(running: Set<String>, now: Date) {
        let vanished = started.filter { matchId, startedAt in
            !running.contains(matchId) && now.timeIntervalSince(startedAt) > Self.reconcileGrace
        }
        for matchId in vanished.keys {
            dismiss(matchId, now: now)
        }
    }

    /// Sans les marques de plus de 24 h.
    public func pruned(now: Date) -> LiveActivityChoices {
        func fresh(_ marks: [String: Date]) -> [String: Date] {
            marks.filter { now.timeIntervalSince($0.value) <= Self.retention }
        }
        return LiveActivityChoices(pinned: fresh(pinned), dismissed: fresh(dismissed), started: fresh(started))
    }
}
