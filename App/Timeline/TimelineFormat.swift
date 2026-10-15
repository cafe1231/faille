import Foundation
import LoLKit

/// Textes du fil des événements (spec fonctionnalités §4). Les joueurs ne sont nommés que si LoLKit a pu les déduire ;
/// sinon « +2 kills » : jamais d'attribution inventée.
enum TimelineText {
    /// « Kill · KC Mid », « 2 kills · KC Mid, KC Bot », « +2 kills », « Drake infernal », « Baron », « 2 tours »,
    /// « Inhibiteur ».
    static func text(_ event: TimelineEvent) -> String {
        switch event.kind {
        case .kills:
            guard !event.players.isEmpty else {
                return event.count == 1 ? String(localized: "+\(event.count) kill")
                                        : String(localized: "+\(event.count) kills")
            }
            let count = event.count == 1 ? String(localized: "Kill") : String(localized: "\(event.count) kills")
            return "\(count) · \(event.players.joined(separator: ", "))"
        case let .dragon(type):
            return String(localized: "Drake \(Format.dragons([type]))")
        case .baron:
            return event.count == 1 ? String(localized: "Baron") : String(localized: "\(event.count) barons")
        case .tower:
            return event.count == 1 ? String(localized: "Tour") : String(localized: "\(event.count) tours")
        case .inhibitor:
            return event.count == 1 ? String(localized: "Inhibiteur") : String(localized: "\(event.count) inhibiteurs")
        }
    }

    /// Repères de la courbe de gold : drakes et barons seulement.
    static func isMarker(_ event: TimelineEvent) -> Bool {
        switch event.kind {
        case .dragon, .baron: return true
        case .kills, .tower, .inhibitor: return false
        }
    }
}

/// Données de la courbe de l'écart de gold (spec fonctionnalités §5).
enum GoldChartData {
    /// La courbe, avec un point ajouté à chaque passage par zéro : l'aire au-dessus de zéro (équipe de gauche en tête) et
    /// celle en dessous (l'autre équipe) se rejoignent exactement sur l'axe.
    static func withZeroCrossings(_ points: [GoldPoint]) -> [GoldPoint] {
        guard var previous = points.first else { return [] }
        var result = [previous]
        for point in points.dropFirst() {
            if (previous.difference < 0 && point.difference > 0) || (previous.difference > 0 && point.difference < 0) {
                let ratio = Double(previous.difference) / Double(previous.difference - point.difference)
                let time = previous.gameTime + (point.gameTime - previous.gameTime) * ratio
                result.append(GoldPoint(gameTime: time, difference: 0))
            }
            result.append(point)
            previous = point
        }
        return result
    }

    /// Borne de l'axe vertical, symétrique : le plus grand écart (en valeur absolue) arrondi au millier supérieur,
    /// 1 000 au moins.
    static func axisLimit(_ points: [GoldPoint]) -> Int {
        let peak = points.map { abs($0.difference) }.max() ?? 0
        return max(1000, (peak + 999) / 1000 * 1000)
    }
}
