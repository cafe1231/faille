import Foundation
import LoLKit

/// Matchs du calendrier complet (spec saison §3.2) : ceux du calendrier de l'appli, du direct et des pages `older` /
/// `newer` lues pendant la session. Pur.
enum CalendarEvents {
    /// Sans doublon : le direct fait foi, puis le calendrier, puis les pages.
    static func merged(pages: [SchedulePageResult], schedule: [MatchEvent], live: [MatchEvent]?) -> [MatchEvent] {
        var byId: [String: MatchEvent] = [:]
        for event in pages.flatMap(\.events) + schedule + (live ?? []) {
            byId[event.id] = event
        }
        return byId.values.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) }
    }

    /// Jeton de la page à lire dans ce sens : `older` de la page aux matchs les plus anciens, `newer` de celle aux matchs
    /// les plus récents ; nil si rien de plus n'existe (`newer` nil = rien de plus récent) ou si aucune page n'est lue
    /// (lire d'abord la page 0).
    static func token(_ direction: SchedulePageDirection, pages: [SchedulePageResult]) -> String? {
        switch direction {
        case .older:
            pages.min { earliest($0) < earliest($1) }?.older
        case .newer:
            pages.max { latest($0) < latest($1) }?.newer
        }
    }

    private static func earliest(_ page: SchedulePageResult) -> Date {
        page.events.map(\.startTime).min() ?? .distantFuture
    }

    private static func latest(_ page: SchedulePageResult) -> Date {
        page.events.map(\.startTime).max() ?? .distantPast
    }
}
