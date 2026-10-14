import Foundation

/// Pastille sous un jour du calendrier (spec saison §2.2 n° 3, §3.2).
public enum DayMarker: Sendable, Equatable {
    /// Aucun match à signaler.
    case none
    /// Au moins un match d'une équipe ou d'une ligue suivie : pastille pleine.
    case followed
    /// Sinon, au moins un match international (Mondial, MSI, First Stand) : anneau.
    case international
}

/// Un jour d'une grille de calendrier.
public struct CalendarDay: Sendable, Equatable, Identifiable {
    /// Début du jour dans le fuseau du calendrier donné.
    public let date: Date
    /// Numéro du jour dans le mois (1-31).
    public let dayNumber: Int
    /// Faux pour les jours du mois précédent ou suivant qui complètent la grille.
    public let isInMonth: Bool
    public let isToday: Bool
    public let marker: DayMarker
    /// Matchs du jour, par heure de début.
    public let matchIds: [String]

    public init(date: Date, dayNumber: Int, isInMonth: Bool, isToday: Bool, marker: DayMarker, matchIds: [String]) {
        self.date = date
        self.dayNumber = dayNumber
        self.isInMonth = isInMonth
        self.isToday = isToday
        self.marker = marker
        self.matchIds = matchIds
    }

    public var id: Date { date }
}

/// Page de `getSchedule` à lire pour afficher un mois hors du calendrier en cache (§3.2).
public enum SchedulePageDirection: Sendable, Equatable {
    case older
    case newer
}

/// Vue mois du calendrier complet (§3.2) : logique pure, l'appli dessine. Jours et heures dans le fuseau et la locale
/// du `Calendar` donné (celui de l'appareil) : semaine commençant à `calendar.firstWeekday` (lundi en France).
public enum CalendarMonth {
    /// Grille du mois qui contient `month` : semaines entières (de `firstWeekday` à la veille), 4 à 6 semaines.
    /// - Parameter followed: ids des matchs d'une équipe ou d'une ligue suivie (pastille pleine).
    /// - Parameter now: pour `isToday`.
    public static func days(events: [MatchEvent], month: Date, calendar: Calendar, followed: Set<String>,
                            now: Date) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = calendar.startOfDay(for: interval.start)
        let lead = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? firstDay
        let trail = (calendar.firstWeekday + 6 - calendar.component(.weekday, from: lastDay) + 7) % 7
        let monthDays = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        guard let start = calendar.date(byAdding: .day, value: -lead, to: firstDay) else { return [] }
        let byDay = group(events, calendar: calendar)
        return (0..<(lead + monthDays + trail)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return day(date, events: byDay[date] ?? [], inMonth: calendar.isDate(date, equalTo: month, toGranularity: .month),
                       calendar: calendar, followed: followed, now: now)
        }
    }

    /// Matchs d'un jour, par heure de début (liste du jour sous la grille et sous le bandeau).
    public static func events(on day: Date, in events: [MatchEvent], calendar: Calendar) -> [MatchEvent] {
        events.filter { calendar.isDate($0.startTime, inSameDayAs: day) }
            .sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
    }

    /// Page à lire pour couvrir le mois de `month` : `.older` s'il commence avant le jour du premier match en cache,
    /// `.newer` s'il finit après le jour du dernier, nil s'il est couvert ou si le cache est vide (rien à paginer).
    /// L'appli ne lit la page que si son jeton existe (`newer` nil = rien de plus récent) et la garde pour la session.
    public static func pageNeeded(for month: Date, events: [MatchEvent], calendar: Calendar) -> SchedulePageDirection? {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let earliest = events.map(\.startTime).min(),
              let latest = events.map(\.startTime).max() else { return nil }
        if interval.start < calendar.startOfDay(for: earliest) { return .older }
        if let dayAfterLatest = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest)),
           interval.end > dayAfterLatest { return .newer }
        return nil
    }

    static func group(_ events: [MatchEvent], calendar: Calendar) -> [Date: [MatchEvent]] {
        Dictionary(grouping: events) { calendar.startOfDay(for: $0.startTime) }
    }

    static func day(_ date: Date, events: [MatchEvent], inMonth: Bool, calendar: Calendar, followed: Set<String>,
                    now: Date) -> CalendarDay {
        let sorted = events.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
        let marker: DayMarker
        if sorted.contains(where: { followed.contains($0.id) }) {
            marker = .followed
        } else if sorted.contains(where: { League.internationalSlugs.contains($0.league.slug) }) {
            marker = .international
        } else {
            marker = .none
        }
        return CalendarDay(date: date, dayNumber: calendar.component(.day, from: date), isInMonth: inMonth,
                           isToday: calendar.isDate(date, inSameDayAs: now), marker: marker, matchIds: sorted.map(\.id))
    }
}
