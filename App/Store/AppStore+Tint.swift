import LoLKit
import SwiftUI

extension AppStore {
    /// Couleur Vitrail d'une équipe d'un match si elle est suivie ; nil = verre neutre (spec §9).
    func tint(for team: MatchTeam) -> Color? {
        followed(team).map { Palette.team($0.colorHex) }
    }
}
