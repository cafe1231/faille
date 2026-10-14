import Foundation

/// Réglages de l'appli, enregistrés dans le groupe d'apps (lus aussi par les widgets et la Live Activity aux étapes 3-4).
public struct AppSettings: Codable, Sendable, Equatable {
    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    public var liveActivityMode: LiveActivityMode
    /// Matchs que l'utilisateur a choisi de révéler malgré l'anti-spoiler (spec §8).
    public var revealedMatchIds: Set<String>
    /// Notifications de début de match (spec fonctionnalités §2) : désactivées par défaut.
    public var matchRemindersEnabled: Bool
    /// Délai de ces notifications avant le début du match, en secondes : une valeur de `MatchReminders.leadOptions`
    /// (5, 15 ou 30 min) ; toute autre valeur devient `MatchReminders.defaultLead` (15 min).
    public var matchReminderLead: TimeInterval {
        didSet {
            if !MatchReminders.leadOptions.contains(matchReminderLead) {
                matchReminderLead = MatchReminders.defaultLead
            }
        }
    }

    public init(liveActivityMode: LiveActivityMode = .automatic, revealedMatchIds: Set<String> = [],
                matchRemindersEnabled: Bool = false, matchReminderLead: TimeInterval = MatchReminders.defaultLead) {
        self.liveActivityMode = liveActivityMode
        self.revealedMatchIds = revealedMatchIds
        self.matchRemindersEnabled = matchRemindersEnabled
        self.matchReminderLead = Self.lead(matchReminderLead)
    }

    private enum CodingKeys: String, CodingKey {
        case liveActivityMode, revealedMatchIds, matchRemindersEnabled, matchReminderLead
    }

    /// Décodage tolérant : champ absent ou valeur inconnue (version plus récente, ou plus ancienne sans ce champ) → valeur
    /// par défaut.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveActivityMode = (try? container.decodeIfPresent(LiveActivityMode.self, forKey: .liveActivityMode)) ?? .automatic
        revealedMatchIds = (try? container.decodeIfPresent(Set<String>.self, forKey: .revealedMatchIds)) ?? []
        matchRemindersEnabled = (try? container.decodeIfPresent(Bool.self, forKey: .matchRemindersEnabled)) ?? false
        matchReminderLead = Self.lead((try? container.decodeIfPresent(TimeInterval.self, forKey: .matchReminderLead))
            ?? MatchReminders.defaultLead)
    }

    /// Délai proposé dans les réglages, sinon le délai par défaut.
    private static func lead(_ value: TimeInterval) -> TimeInterval {
        MatchReminders.leadOptions.contains(value) ? value : MatchReminders.defaultLead
    }
}
