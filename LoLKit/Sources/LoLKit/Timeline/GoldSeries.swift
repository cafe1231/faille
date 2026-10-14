import Foundation

/// Un point de la courbe de l'écart de gold.
public struct GoldPoint: Sendable, Equatable {
    /// Temps de jeu en secondes depuis la première frame (même règle que `TimelineEvent.gameTime`).
    public let gameTime: TimeInterval
    /// Écart de gold total : positif quand l'équipe de référence mène.
    public let difference: Int

    public init(gameTime: TimeInterval, difference: Int) {
        self.gameTime = gameTime
        self.difference = difference
    }
}

/// Courbe de l'écart de gold (spec fonctionnalités §5), sur les mêmes frames que le fil des événements. Anti-spoiler : la
/// courbe dit qui mène, minute par minute ; l'appli n'appelle pas cette fonction (et ne demande aucune frame) pour un
/// match masqué.
public enum GoldSeries {
    /// Un point par frame, dans l'ordre chronologique (deux frames au même instant gardent leur ordre de remise). Écart =
    /// bleu − rouge, réorienté vers `teamId` : si `teamId` est l'équipe rouge de la game, rouge − bleu. `teamId` nil ou
    /// absent de la game : bleu − rouge.
    public static func points(from snapshots: [GameSnapshot], firstFrameTime: Date, orientedTo teamId: String?) -> [GoldPoint] {
        GameTimeline.chronological(snapshots).map { snapshot in
            let blueMinusRed = snapshot.blue.gold - snapshot.red.gold
            return GoldPoint(gameTime: max(0, snapshot.timestamp.timeIntervalSince(firstFrameTime)),
                             difference: teamId == snapshot.redTeamId ? -blueMinusRed : blueMinusRed)
        }
    }
}
