import Foundation

/// Une notification locale de début de match (spec fonctionnalités §2), à programmer telle quelle par l'appli.
public struct MatchReminder: Sendable, Equatable, Identifiable {
    /// Identifiant de la notification, stable pour un match : re-programmer le même match remplace l'ancienne.
    public let id: String
    public let matchId: String
    /// Heure d'envoi : début du match moins le délai choisi.
    public let fireDate: Date
    /// « KC vs C9 dans 15 min » — jamais de score ni de résultat.
    public let title: String
    /// « Mondial · Play-ins · Bo5 »
    public let subtitle: String

    public init(id: String, matchId: String, fireDate: Date, title: String, subtitle: String) {
        self.id = id
        self.matchId = matchId
        self.fireDate = fireDate
        self.title = title
        self.subtitle = subtitle
    }
}

/// Quelles notifications de début de match programmer (spec fonctionnalités §2). Fonction pure : l'appli la rappelle à
/// chaque rafraîchissement du calendrier, des équipes suivies ou des réglages, et remplace toutes ses notifications.
public enum MatchReminders {
    /// iOS garde au plus 64 notifications en attente : on en laisse 4 à l'appli.
    public static let maxCount = 60
    /// Délais proposés dans les réglages (5, 15 ou 30 min) et délai par défaut (15 min).
    public static let leadOptions: [TimeInterval] = [5 * 60, 15 * 60, 30 * 60]
    public static let defaultLead: TimeInterval = 15 * 60

    /// Identifiant stable de la notification d'un match.
    public static func identifier(matchId: String) -> String {
        "match-start-\(matchId)"
    }

    /// Notifications à programmer, les plus proches d'abord, 60 au plus. Un match n'est retenu que s'il n'a pas commencé,
    /// que sa notification tombe après `now`, et que `Presenter.nextLine` l'affiche (`.match`) sur la carte d'au moins une
    /// équipe suivie qui y joue : jamais un prochain match caché par la règle F1 (dernier match masqué) ou la règle C
    /// (adversaire suivi en anti-spoiler au dernier match masqué). Donc au plus un match par équipe suivie : son prochain.
    /// Ligues suivies avec `notifyStarts` (spec saison §3.5) : en plus, chacun de leurs matchs à venir qui n'oppose
    /// aucune équipe suivie (ceux-là restent soumis à la règle ci-dessus) ni une équipe encore inconnue (« TBD »).
    /// - Parameters:
    ///   - schedule: calendrier en cache (`getSchedule`).
    ///   - revealed: ids des matchs révélés par l'utilisateur.
    ///   - lead: délai avant le début du match, en secondes.
    public static func plan(schedule: [MatchEvent], follows: FollowList, revealed: Set<String>, now: Date,
                            lead: TimeInterval) -> [MatchReminder] {
        // `live: nil` : seul le calendrier compte ici (son match `inProgress` sert de « dernier match » à la règle F1).
        let cards = TeamCards.build(follows: follows, schedule: schedule, live: nil, revealed: revealed)
        let maskedLatest = Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: revealed)
        var planned = Set<String>()
        var reminders: [MatchReminder] = []
        for card in cards {
            guard case let .match(event) = Presenter.nextLine(for: card, follows: follows, revealed: revealed,
                                                              maskedLatestTeamIds: maskedLatest),
                  event.state == .unstarted, !planned.contains(event.id) else { continue }
            let fireDate = event.startTime.addingTimeInterval(-lead)
            guard fireDate > now else { continue }
            planned.insert(event.id)
            reminders.append(MatchReminder(id: identifier(matchId: event.id), matchId: event.id, fireDate: fireDate,
                                           title: title(event, follows: follows, lead: lead),
                                           subtitle: subtitle(event)))
        }
        let notifiedSlugs = Set(follows.leagues.filter(\.notifyStarts).map(\.slug))
        // Progression de tableau (I-1 généralisé) : pas de notification pour la suite d'un match masqué.
        let bracketHidden = BracketMasking.hiddenIds(schedule: schedule, maskedTeamIds: maskedLatest, follows: follows,
                                                     revealed: revealed)
        for event in schedule where notifiedSlugs.contains(event.league.slug) && event.state == .unstarted
            && !bracketHidden.contains(event.id) && !planned.contains(event.id) && !follows.involves(event.match.teams)
            && !event.match.teams.contains(where: \.isPlaceholder) {
            let fireDate = event.startTime.addingTimeInterval(-lead)
            guard fireDate > now else { continue }
            planned.insert(event.id)
            reminders.append(MatchReminder(id: identifier(matchId: event.id), matchId: event.id, fireDate: fireDate,
                                           title: title(event, follows: follows, lead: lead),
                                           subtitle: subtitle(event)))
        }
        return Array(reminders.sorted { ($0.fireDate, $0.matchId) < ($1.fireDate, $1.matchId) }.prefix(maxCount))
    }

    /// « KC vs C9 dans 15 min » : équipes dans l'ordre d'affichage (`displayOrder` : la plus anciennement suivie à gauche).
    static func title(_ event: MatchEvent, follows: FollowList, lead: TimeInterval) -> String {
        let codes = event.match.teams.map(\.code)
        let ordered = reorder(codes, follows.displayOrder(event.match.teams)) ?? codes
        return "\(ordered.joined(separator: " vs ")) dans \(Int((lead / 60).rounded())) min"
    }

    /// « Mondial · Play-ins · Bo5 » (sans le bloc s'il est absent).
    static func subtitle(_ event: MatchEvent) -> String {
        [event.league.name, event.blockName ?? "", "Bo\(event.bestOf)"]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
