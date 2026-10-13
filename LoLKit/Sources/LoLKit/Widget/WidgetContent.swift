import Foundation

/// Ce que les widgets lisent dans le groupe d'apps (spec §4.4, §7) : les fichiers de l'appli, tels quels.
/// L'extension n'appelle jamais l'API : tout ce qu'elle montre vient d'ici.
public struct WidgetInput: Sendable, Equatable {
    public var follows: FollowList
    /// `settings.json` : seuls les matchs révélés (`revealedMatchIds`) comptent pour les widgets.
    public var settings: AppSettings
    /// `cache-schedule.json` ; nil tant que l'appli n'a jamais chargé le calendrier.
    public var schedule: Cached<SchedulePage>?
    /// `cache-live.json` ; sa fraîcheur est jugée à la date de chaque entrée (`RefreshPolicy.usableLive`).
    public var live: Cached<[MatchEvent]>?

    public init(follows: FollowList = FollowList(), settings: AppSettings = AppSettings(),
                schedule: Cached<SchedulePage>? = nil, live: Cached<[MatchEvent]>? = nil) {
        self.follows = follows
        self.settings = settings
        self.schedule = schedule
        self.live = live
    }
}

/// Un match tel qu'un widget a le droit de l'afficher : l'anti-spoiler (spec §8) y est déjà appliqué.
public struct WidgetLine: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        /// En direct. Score de série et numéro de game dans l'ordre d'affichage ; tous deux nil si le match est masqué.
        case live(score: [Int]?, gameNumber: Int?)
        /// À venir, avec son heure de début.
        case upcoming(Date)
    }

    public let matchId: String
    public let leagueName: String
    /// Codes des équipes dans l'ordre d'affichage : l'équipe suivie à gauche (`FollowList.displayOrder`).
    public let codes: [String]
    /// Couleur de chaque équipe, dans le même ordre ; nil pour une équipe non suivie.
    public let colorHexes: [String?]
    public let status: Status
    /// Au moins une équipe du match est en anti-spoiler et le match n'a pas été révélé.
    public let isMasked: Bool

    public init(matchId: String, leagueName: String, codes: [String], colorHexes: [String?], status: Status,
                isMasked: Bool) {
        self.matchId = matchId
        self.leagueName = leagueName
        self.codes = codes
        self.colorHexes = colorHexes
        self.status = status
        self.isMasked = isMasked
    }

    public var id: String { matchId }

    public var isLive: Bool {
        if case .live = status { return true }
        return false
    }

    /// Heure de début d'un match à venir ; nil en direct.
    public var upcomingStart: Date? {
        if case let .upcoming(start) = status { return start }
        return nil
    }
}

/// Ce que le petit widget annonce pour une équipe suivie (spec §7).
public struct WidgetTeam: Sendable, Equatable, Identifiable {
    public enum Next: Sendable, Equatable {
        /// L'équipe joue en ce moment.
        case live(WidgetLine)
        /// Son prochain match (`Presenter.nextLine` = `.match`).
        case match(WidgetLine)
        /// Rien n'est annoncé, « Prochain · masqué » (`Presenter.nextLine` = `.hidden`, spec §8) : le dernier match de
        /// l'équipe est masqué (règle F1), ou son prochain match l'oppose à une autre équipe suivie en anti-spoiler et
        /// n'est pas révélé (règle C).
        case hidden
        /// Aucun match à venir connu. (Pas `.none` : on le confondrait avec `Optional.none`.)
        case noMatch
    }

    public let team: FollowedTeam
    public let next: Next

    public init(team: FollowedTeam, next: Next) {
        self.team = team
        self.next = next
    }

    public var id: String { team.id }
}

/// Ce que montrent les widgets à une date donnée.
public struct WidgetContent: Sendable, Equatable {
    /// Date de l'entrée : les comptes à rebours partent d'elle.
    public let date: Date
    /// Une par équipe suivie, dans l'ordre de suivi.
    public let teams: [WidgetTeam]
    /// Matchs en direct (dans l'ordre des cartes de l'appli), puis prochains matchs par heure de début ; un match
    /// entre deux équipes suivies n'y est qu'une fois.
    public let lines: [WidgetLine]

    public init(date: Date, teams: [WidgetTeam], lines: [WidgetLine]) {
        self.date = date
        self.teams = teams
        self.lines = lines
    }

    /// Match des widgets de l'écran verrouillé : un match en direct d'abord, sinon le prochain.
    public var headline: WidgetLine? { lines.first }

    /// Équipe du petit widget : celle choisie dans ses réglages si elle est toujours suivie, sinon la première suivie.
    public func team(id: String?) -> WidgetTeam? {
        if let id, let chosen = teams.first(where: { $0.team.id == id }) { return chosen }
        return teams.first
    }
}
