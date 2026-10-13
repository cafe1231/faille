import ActivityKit
import LoLKit

/// Conformité ActivityKit du contrat de la Live Activity (spec §4.3) : l'état d'une Live Activity est exactement
/// `LiveMatchState`, pour que le JSON des push de la phase 2 soit celui de la fixture `live_contract.json`.
/// Compilée dans l'appli (qui démarre et met à jour) et dans l'extension (qui affiche).
extension LiveMatchAttributes: @retroactive ActivityAttributes {
    public typealias ContentState = LiveMatchState
}
