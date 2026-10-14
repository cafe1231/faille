import Foundation
import LoLKit

/// Textes de l'Accueil (spec saison §3.8 : LoLKit renvoie des valeurs, l'appli formule ; chaînes du catalogue).
enum HomeTexts {
    /// « jeudi 15 octobre · 3 matchs aujourd'hui ».
    static func subtitle(now: Date, todayCount: Int, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        style = style.weekday(.wide).day().month(.wide)
        let day = now.formatted(style)
        let count = todayCount == 0 ? String(localized: "aucun match aujourd'hui")
                                    : String(localized: "\(todayCount) matchs aujourd'hui")
        return "\(day) · \(count)"
    }

    static func reason(_ reason: MustWatchReason) -> String {
        switch reason {
        case .followedTeam: String(localized: "Tes équipes")
        case .followedLeague: String(localized: "Ta ligue")
        case let .international(slug): SeasonLabels.league(slug: slug)
        case .elimination: String(localized: "Élimination en jeu")
        case .qualification: String(localized: "Qualification en jeu")
        case .decider: String(localized: "Tout se joue")
        case .final: String(localized: "Finale")
        case .semiFinal: String(localized: "Demi-finale")
        case .quarterFinal: String(localized: "Quart de finale")
        case .playoffs: String(localized: "Play-offs")
        case .topClash: String(localized: "Choc du haut de tableau")
        case .closeRanks: String(localized: "Duel serré")
        case .rematch: String(localized: "Revanche")
        case .derby: String(localized: "Derby")
        case .bestOf5: String(localized: "Bo5")
        case .bestOf3: String(localized: "Bo3")
        case .live: String(localized: "En direct")
        }
    }

    /// Les deux raisons qui rapportent le plus (`MustWatchPick.explanation`).
    static func explanation(_ pick: MustWatchPick) -> String {
        pick.explanation.map(reason).joined(separator: " · ")
    }

    /// Barème de « Comment c'est calculé » (spec saison §3.6) : raison et points, tels que les calcule `MustWatch`.
    static let scoring: [(reason: MustWatchReason, points: String)] = [
        (.followedTeam, String(localized: "+50 par équipe, 100 au plus")), (.followedLeague, "+25"),
        (.international(slug: "worlds"), "+20"), (.elimination, "+30"), (.qualification, "+30"), (.decider, "+40"),
        (.final, "+40"), (.semiFinal, "+30"), (.quarterFinal, "+20"), (.playoffs, "+20"), (.topClash, "+15"),
        (.closeRanks, "+10"), (.rematch, "+10"), (.derby, "+10"), (.bestOf5, "+10"), (.bestOf3, "+5"), (.live, "+15"),
    ]
}
