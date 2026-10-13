import Foundation

/// Une valeur gardée sur disque avec la date à laquelle l'API l'a donnée (spec §4.4 : cache réseau).
/// Encodée avec `JSONEncoder()` par défaut (dates en secondes depuis 2001), relue avec `JSONDecoder()`.
public struct Cached<Value: Codable & Sendable>: Codable, Sendable {
    public var value: Value
    public var fetchedAt: Date

    public init(value: Value, fetchedAt: Date) {
        self.value = value
        self.fetchedAt = fetchedAt
    }

    /// Âge de la valeur ; négatif si l'horloge de l'appareil a reculé.
    public func age(now: Date) -> TimeInterval {
        now.timeIntervalSince(fetchedAt)
    }
}

extension Cached: Equatable where Value: Equatable {}

/// Le calendrier en cache et les ligues demandées pour l'obtenir : suivre une équipe d'une autre ligue
/// impose un nouvel appel à `getSchedule`.
public struct SchedulePage: Codable, Sendable, Equatable {
    public var leagueIds: [String]
    public var events: [MatchEvent]

    public init(leagueIds: [String], events: [MatchEvent]) {
        self.leagueIds = leagueIds
        self.events = events
    }
}
