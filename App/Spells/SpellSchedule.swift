import Foundation
import LoLKit

/// Quand interroger Leaguepedia pour les sorts d'invocateur d'un match (spec fonctionnalités §3 ; journal du lot LoLKit) :
/// la règle de LoLKit (`SpellLookupPolicy` : 3 essais, 10 min d'écart, 30 min après un refus, plus rien après un succès),
/// plus celle de l'appli — premier essai 30 min au moins après la fin du match (le wiki n'a pas la game avant ; « pas
/// encore sur le wiki » compte comme un essai), essais espacés d'une heure au moins.
enum SpellSchedule {
    static let delayAfterEnd: TimeInterval = 30 * 60
    static let gapBetweenAttempts: TimeInterval = 60 * 60
    /// Fin estimée d'un match dont la frame `finished` n'est pas connue : début de sa dernière game + 1 h 15 (une game
    /// professionnelle dépasse rarement l'heure ; l'estimation ne fait que retarder le premier essai).
    static let assumedGameLength: TimeInterval = 75 * 60

    /// Premier essai permis : 30 min après la fin du match (sa frame `finished` si on l'a, sinon l'estimation).
    static func earliestAttempt(matchEnd: Date?, lastGameStart: Date) -> Date {
        (matchEnd ?? lastGameStart.addingTimeInterval(assumedGameLength)).addingTimeInterval(delayAfterEnd)
    }

    /// Une requête est-elle permise à `now` ? Jamais avant `earliest`, jamais si `SpellLookupPolicy` la refuse, jamais
    /// moins d'une heure après la précédente.
    static func mayAttempt(_ policy: SpellLookupPolicy, earliest: Date, now: Date) -> Bool {
        guard now >= earliest, policy.canAttempt(now: now) else { return false }
        guard let last = policy.lastAttempt else { return true }
        return now.timeIntervalSince(last) >= gapBetweenAttempts
    }

    /// Centre de la requête (± 3 h, `SpellMatcher.window`) : le milieu entre le début de la première et de la dernière game
    /// du match ; une série dont les games commencent à moins de 6 h d'écart est couverte en une seule requête.
    static func center(of starts: [Date]) -> Date? {
        guard let first = starts.min(), let last = starts.max() else { return nil }
        return first.addingTimeInterval(last.timeIntervalSince(first) / 2)
    }
}
