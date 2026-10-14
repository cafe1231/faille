import Foundation

/// Bandeau de jours de l'Accueil (spec saison §2.2 n° 3) : 7 jours d'aujourd'hui − 1 à aujourd'hui + 5, défilable
/// sur ± 3 semaines dans le calendrier en cache. Mêmes pastilles que la vue mois.
public enum WeekStrip {
    /// Jours visibles par défaut : la veille, aujourd'hui et les 5 jours suivants.
    public static let daysBefore = 1
    public static let daysAfter = 5
    /// Étendue du défilement, en semaines de chaque côté d'aujourd'hui.
    public static let scrollWeeks = 3

    /// Jours de `today − before` à `today + after` (bornes comprises), avec pastilles et matchs du jour.
    /// - Parameter followed: ids des matchs d'une équipe ou d'une ligue suivie (pastille pleine).
    public static func days(today: Date, events: [MatchEvent], calendar: Calendar, followed: Set<String>,
                            before: Int = daysBefore, after: Int = daysAfter) -> [CalendarDay] {
        let start = calendar.startOfDay(for: today)
        let byDay = CalendarMonth.group(events, calendar: calendar)
        return (-before...after).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return CalendarMonth.day(date, events: byDay[date] ?? [], inMonth: true, calendar: calendar,
                                     followed: followed, now: today)
        }
    }

    /// Toute l'étendue défilable : ± `scrollWeeks` semaines autour d'aujourd'hui (43 jours).
    public static func scrollRange(today: Date, events: [MatchEvent], calendar: Calendar,
                                   followed: Set<String>) -> [CalendarDay] {
        days(today: today, events: events, calendar: calendar, followed: followed, before: scrollWeeks * 7,
             after: scrollWeeks * 7)
    }
}
