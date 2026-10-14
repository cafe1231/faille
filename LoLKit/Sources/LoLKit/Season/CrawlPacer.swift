import Foundation

/// Cadence de la collecte (spec saison §1.6), pure : l'appli demande `next(after:)` après chaque requête et attend le
/// délai rendu (ou s'arrête). Une requête toutes les 2 s (y compris les 2 requêtes d'une même game) ; 429, 5xx ou
/// erreur réseau → 4, 8, 16, 32 s ; 5 échecs d'affilée → arrêt jusqu'à la prochaine session ; une réponse → retour à
/// 2 s ; 300 requêtes par session au premier plan (énumération comprise) → arrêt.
public struct CrawlPacer: Sendable, Equatable {
    public static let baseInterval: TimeInterval = 2
    /// Attente après le n-ième échec d'affilée (le 5e arrête la session : la dernière valeur est le plafond si
    /// `maxConsecutiveFailures` augmente un jour).
    public static let backoff: [TimeInterval] = [4, 8, 16, 32, 60]
    public static let maxConsecutiveFailures = 5
    public static let sessionRequestBudget = 300

    /// Issue d'une requête, du point de vue de la cadence.
    public enum Outcome: Sendable, Equatable {
        /// Le serveur a répondu (200, 204, 404…) : la game a une réponse, bonne ou non.
        case answered
        /// 429, 5xx ou erreur réseau : on recule.
        case retryable
    }

    public enum StopReason: Sendable, Equatable {
        /// 300 requêtes faites dans cette session.
        case budget
        /// 5 échecs d'affilée.
        case failures
    }

    public enum Decision: Sendable, Equatable {
        /// Attendre ce délai (s) avant la requête suivante.
        case wait(TimeInterval)
        case stop(StopReason)
    }

    public let budget: Int
    public private(set) var requestsMade = 0
    public private(set) var consecutiveFailures = 0

    public init(budget: Int = CrawlPacer.sessionRequestBudget) {
        self.budget = budget
    }

    /// Reste-t-il au moins une requête dans le budget ?
    public var canRequest: Bool { requestsMade < budget && consecutiveFailures < Self.maxConsecutiveFailures }

    /// À appeler après chaque requête faite : compte la requête et rend la suite.
    public mutating func next(after outcome: Outcome) -> Decision {
        requestsMade += 1
        switch outcome {
        case .answered:
            consecutiveFailures = 0
        case .retryable:
            consecutiveFailures += 1
            if consecutiveFailures >= Self.maxConsecutiveFailures { return .stop(.failures) }
        }
        if requestsMade >= budget { return .stop(.budget) }
        if consecutiveFailures == 0 { return .wait(Self.baseInterval) }
        return .wait(Self.backoff[min(consecutiveFailures, Self.backoff.count) - 1])
    }

    /// Issue d'une requête de `LoLClient` : pas d'erreur, `noData` (204), `statsDisabled` (404) ou autre statut HTTP
    /// (400…) → `.answered` ; 429, 5xx et toute erreur non HTTP (réseau, délai dépassé) → `.retryable`.
    public static func outcome(of error: (any Error)?) -> Outcome {
        guard let error else { return .answered }
        switch error as? LoLAPIError {
        case .noData, .statsDisabled:
            return .answered
        case let .http(status):
            return status == 429 || status >= 500 ? .retryable : .answered
        case nil:
            return .retryable
        }
    }
}
