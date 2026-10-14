import Foundation
import LoLKit

/// Textes des tableaux (spec saison §3.5).
enum StandingsTexts {
    static func roundName(_ kind: StandingsTable.Round.Kind) -> String {
        switch kind {
        case .quarterFinal: String(localized: "Quarts de finale")
        case .semiFinal: String(localized: "Demi-finales")
        case .final: String(localized: "Finale")
        }
    }

    /// Équipe d'un tableau : son code, « À déterminer » pour l'équipe d'attente (`id "0"`, code « TBD »).
    static func teamLabel(_ team: MatchTeam) -> String {
        team.isPlaceholder || team.id == "0" ? String(localized: "À déterminer") : team.code
    }
}
