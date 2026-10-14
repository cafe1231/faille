import Foundation
import Observation

/// Match à ouvrir après le toucher d'une notification de début de match (spec fonctionnalités §2) : le délégué des
/// notifications le dépose, `RootView` passe sur l'onglet Matchs, pousse le Détail du match, puis le consomme.
@MainActor
@Observable
final class NotificationRouter {
    private(set) var pendingMatchId: String?

    func open(matchId: String) {
        pendingMatchId = matchId
    }

    /// Le match à ouvrir, une seule fois.
    func consume() -> String? {
        defer { pendingMatchId = nil }
        return pendingMatchId
    }
}
