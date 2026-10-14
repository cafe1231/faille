import Foundation

/// Réglage « Live Activity » (spec §5.4).
public enum LiveActivityMode: String, Codable, Sendable {
    case automatic, manual
}

/// Ce que l'appli doit faire d'une Live Activity en cours, à une mise à jour (spec §6.3, §6.4).
public enum LiveActivityUpdate: Sendable, Equatable {
    /// Rien de neuf : aucun appel à ActivityKit (la Live Activity passe « pas fraîche » d'elle-même à sa `staleDate`).
    case keep
    /// Nouveau contenu, déjà dans l'ordre des équipes de la Live Activity.
    case update(LiveMatchState)
    /// Contenu final, puis retrait de l'écran verrouillé à `dismissAt` ; nil : tout de suite.
    case end(LiveMatchState, dismissAt: Date?)
}

/// Décide quelles Live Activities démarrer, mettre à jour et terminer (spec §6.4). Fonctions pures : l'appli
/// (`LiveActivityController`) les applique avec ActivityKit.
public enum LiveActivityPlanner {
    /// Au plus 3 Live Activities à l'écran en même temps.
    public static let maxConcurrent = 3
    /// Une Live Activity de match terminé reste affichée 1 h (spec §6.3).
    public static let finishedDisplay: TimeInterval = 3600
    /// Délai demandé à iOS entre deux réveils en arrière-plan (spec §6.4) ; iOS peut accorder plus tard, ou rien.
    public static let backgroundInterval: TimeInterval = 15 * 60

    /// Matchs qui doivent avoir une Live Activity, par priorité : d'abord ceux qui en ont déjà une (`active` : en cours,
    /// ou terminée et encore affichée ; ils gardent leur place, comptent dans la limite et ne sont jamais remplacés),
    /// puis les épinglés en direct, puis, en automatique, les matchs des équipes suivies dans l'ordre de suivi, sauf
    /// ceux retirés à la main. Les nouveaux venus ne prennent que les places libres (`maxConcurrent` en tout) ; ceux qui
    /// ne sont pas dans `active` sont à démarrer.
    public static func plan(
        live: [MatchEvent],
        follows: FollowList,
        mode: LiveActivityMode,
        pinned: [String],
        dismissed: Set<String>,
        active: [String] = []
    ) -> [String] {
        let liveIds = Set(live.map(\.id))
        var result: [String] = []
        for id in active where !result.contains(id) {
            result.append(id)
        }
        let kept = result.count
        for id in pinned where liveIds.contains(id) && !result.contains(id) {
            result.append(id)
        }
        if mode == .automatic {
            let ranked = live.enumerated()
                .compactMap { position, event -> (rank: Int, position: Int, id: String)? in
                    let ranks = follows.teams.indices.filter { index in
                        event.match.teams.contains { $0.isSame(as: follows.teams[index]) }
                    }
                    return ranks.min().map { (rank: $0, position: position, id: event.id) }
                }
                .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            for candidate in ranked where !dismissed.contains(candidate.id) && !result.contains(candidate.id) {
                result.append(candidate.id)
            }
        }
        return Array(result.prefix(max(maxConcurrent, kept)))
    }

    /// Que faire de la Live Activity d'un match avec ce que l'appli vient de calculer (`latest`, nil s'il n'y a rien de
    /// neuf sur ce match). `latest` est d'abord remis dans l'ordre des équipes de la Live Activity (fixé au démarrage).
    /// - mode manuel et match pas épinglé : fin tout de suite (spec §6.4 « uniquement via le bouton du Détail ») ;
    /// - match terminé : contenu final, retrait 1 h plus tard (spec §6.3) ;
    /// - un masquage (œil) est toujours envoyé, même avec une donnée plus ancienne que celle affichée : l'anti-spoiler
    ///   (spec §8) passe avant la fraîcheur, et l'état masqué n'a ni score ni stats à faire reculer ;
    /// - sinon, une donnée plus ancienne que celle affichée ne la remplace jamais ; à relecture égale, seul un changement
    ///   d'anti-spoiler (révélation, œil) est envoyé — un contenu recalculé avec moins d'informations (stats pas encore
    ///   rechargées après un relancement) n'efface pas ce qui est affiché ;
    /// - sinon, mise à jour.
    public static func decision(
        attributes: LiveMatchAttributes,
        current: LiveMatchState,
        latest: LiveActivityContent?,
        isPinned: Bool,
        mode: LiveActivityMode,
        now: Date
    ) -> LiveActivityUpdate {
        if mode == .manual && !isPinned { return .end(current, dismissAt: nil) }
        guard let latest else { return .keep }
        let state = latest.state.aligned(from: latest.teams, to: attributes)
        if state.phase == .finished { return .end(state, dismissAt: now.addingTimeInterval(finishedDisplay)) }
        if state.spoilerFree && !current.spoilerFree { return .update(state) }
        if state.updatedAt < current.updatedAt { return .keep }
        if state.updatedAt == current.updatedAt && state.spoilerFree == current.spoilerFree { return .keep }
        return .update(state)
    }

    /// Prochain réveil en arrière-plan à demander (spec §6.4) : dans 15 min si un match d'une équipe suivie est en
    /// direct, ou si une Live Activity est à l'écran (pour la mettre à jour ou la terminer) ; sinon aucun.
    public static func nextBackgroundRefresh(now: Date, live: [MatchEvent]?, follows: FollowList,
                                             hasActivities: Bool) -> Date? {
        let followedLive = live?.contains { follows.involves($0.match.teams) } ?? false
        return followedLive || hasActivities ? now.addingTimeInterval(backgroundInterval) : nil
    }
}
