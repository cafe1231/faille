import Foundation

/// Règle stricte de l'appli envers Leaguepedia, qui limite les requêtes anonymes (« ratelimited » vu le 14/10/2026) :
/// - au plus `maxAttempts` (3) requêtes par match, refusées ou non ;
/// - jamais deux requêtes à moins de `minimumGap` (10 min) l'une de l'autre, même sans refus ;
/// - après un refus (`rateLimited`), plus rien avant `retryAfterRefusal` (30 min) ;
/// - plus aucune requête une fois les sorts obtenus.
///
/// Un état par match, que l'appli garde dans son cache disque (encodé avec `JSONEncoder()` par défaut, dates en secondes
/// depuis 2001). Fonction pure : elle ne lit ni l'horloge ni le réseau, l'appli lui donne la date. L'appli ne l'interroge
/// pas pour un match masqué (anti-spoiler) et demande `canAttempt(now:)` avant chaque requête à `LeaguepediaClient`.
public struct SpellLookupPolicy: Sendable, Equatable, Codable {
    /// Résultat d'une requête, à noter avec `record(now:outcome:)`.
    public enum Outcome: Sendable, Equatable {
        /// Les sorts de la game ont été trouvés (`LeaguepediaClient.summonerSpells` a rendu un résultat).
        case success
        /// Le wiki a refusé (`LeaguepediaError.rateLimited`).
        case rateLimited
        /// Tout le reste : erreur réseau ou HTTP, erreur de l'API, ou game pas encore sur le wiki (réponse nil).
        case failure
    }

    /// Nombre maximal de requêtes par match.
    public static let maxAttempts = 3
    /// Délai après un refus du wiki avant de retenter.
    public static let retryAfterRefusal: TimeInterval = 30 * 60
    /// Écart minimal entre deux requêtes, même sans refus.
    public static let minimumGap: TimeInterval = 10 * 60

    /// Requêtes faites pour ce match (refusées comprises).
    public private(set) var attempts: Int
    /// Date de la dernière requête.
    public private(set) var lastAttempt: Date?
    /// La dernière requête a été refusée par le wiki.
    public private(set) var lastWasRateLimited: Bool
    /// Les sorts ont été obtenus : plus aucune requête pour ce match.
    public private(set) var succeeded: Bool

    public init(attempts: Int = 0, lastAttempt: Date? = nil, lastWasRateLimited: Bool = false, succeeded: Bool = false) {
        self.attempts = attempts
        self.lastAttempt = lastAttempt
        self.lastWasRateLimited = lastWasRateLimited
        self.succeeded = succeeded
    }

    private enum CodingKeys: String, CodingKey {
        case attempts, lastAttempt, lastWasRateLimited, succeeded
    }

    /// Décodage tolérant (spec §4.2) : un champ absent ou illisible prend sa valeur neutre, les autres sont gardés.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attempts = max(0, (try? container.decodeIfPresent(Int.self, forKey: .attempts)) ?? 0)
        lastAttempt = try? container.decodeIfPresent(Date.self, forKey: .lastAttempt)
        lastWasRateLimited = (try? container.decodeIfPresent(Bool.self, forKey: .lastWasRateLimited)) ?? false
        succeeded = (try? container.decodeIfPresent(Bool.self, forKey: .succeeded)) ?? false
    }

    /// Une requête à Leaguepedia est-elle permise maintenant ? Non si les sorts sont déjà obtenus, si les
    /// `maxAttempts` essais sont faits, si le dernier a été refusé il y a moins de `retryAfterRefusal`, ou si le dernier
    /// date de moins de `minimumGap` (une horloge qui a reculé compte comme « à l'instant » : rien).
    public func canAttempt(now: Date) -> Bool {
        guard !succeeded, attempts < Self.maxAttempts else { return false }
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        if lastWasRateLimited, elapsed < Self.retryAfterRefusal { return false }
        return elapsed >= Self.minimumGap
    }

    /// Note une requête faite à `now` et son résultat. Un succès est définitif.
    public mutating func record(now: Date, outcome: Outcome) {
        attempts += 1
        lastAttempt = now
        lastWasRateLimited = outcome == .rateLimited
        succeeded = succeeded || outcome == .success
    }
}
