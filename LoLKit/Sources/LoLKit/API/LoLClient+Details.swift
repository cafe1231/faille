import Foundation

extension LoLClient {
    /// `details` est lourd (~200 Ko par lecture) : au plus une lecture par minute, et seulement Détail ouvert sur une game
    /// en cours (une seule pour une game terminée).
    public static let detailsInterval: TimeInterval = 60

    /// Détails par joueur d'une game (`livestats/v1/details/{gameId}`) à partir de `startingTime` ; sans `startingTime`,
    /// le début de la game. Mêmes erreurs que `window` (404 : stats désactivées ; vide : pas encore de données).
    public func details(gameId: String, startingTime: Date?) async throws -> GameDetails {
        try await feed("details", gameId: gameId, startingTime: startingTime, as: GameDetails.self)
    }

    /// Derniers détails d'une game, avec le même recul que `liveWindow` (fin de fenêtre ≥ 80 s, paliers de
    /// `LiveStatsTime.delays`, délai retenu par game et partagé avec `window`). Pour une game terminée, le flux renvoie
    /// les dernières frames (vérifié le 14/10/2026 : une heure demandée après la fin donne la frame `finished`) : un seul
    /// appel suffit.
    public func details(gameId: String, now: Date) async throws -> GameDetails {
        try await steppingBack(gameId: gameId, now: now) { startingTime in
            try await details(gameId: gameId, startingTime: startingTime)
        }
    }
}
