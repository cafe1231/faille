import SwiftUI

/// Destination de navigation : le Détail d'un match. `sourceID` désigne la ligne de carte touchée, d'où part le zoom
/// carte → Détail (spec finitions §6) ; nil : transition standard.
struct MatchRoute: Hashable {
    /// Ligne d'une carte qui ouvre le Détail.
    enum Row: String, CaseIterable, Sendable {
        case live, next, last
    }

    let matchId: String
    let sourceID: String?

    init(matchId: String, sourceID: String? = nil) {
        self.matchId = matchId
        self.sourceID = sourceID
    }

    /// Route d'une ligne de carte. Un même match peut être sur deux cartes (deux équipes suivies qui s'affrontent), et
    /// sur deux lignes d'une carte : la source réunit l'équipe de la carte, la ligne et le match, elle est donc unique.
    init(teamId: String, row: Row, matchId: String) {
        self.init(matchId: matchId, sourceID: "\(teamId)/\(row.rawValue)/\(matchId)")
    }
}

extension View {
    /// Source du zoom carte → Détail ; sans espace de noms (aperçus Xcode) ni identifiant : rien.
    @ViewBuilder func zoomSource(_ id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Transition de l'écran Détail : zoom depuis la ligne touchée ; sans ligne source, ou sous « Réduire les
    /// animations » (`enabled` faux), transition standard d'iOS.
    @ViewBuilder func zoomTransition(_ id: String?, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if let id, enabled {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}
