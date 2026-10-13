import ActivityKit
import Foundation

/// Live Activity de test : un compteur et l'heure de la dernière mise à jour.
struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tick: Int
        var updatedAt: Date
    }

    var title: String
}
