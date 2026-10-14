import Foundation
import LoLKit

extension DataDragon {
    /// Liste des versions gardée sur disque (24 h, `DataDragon.versionsMaxAge`).
    static let versionsCachePath = "ddragon/versions.json"

    /// Chemin dans le cache d'une URL Data Dragon : « ddragon/ » + le chemin après « /cdn/ »
    /// (« …/cdn/16.18.1/img/champion/KSante.png » → « ddragon/16.18.1/img/champion/KSante.png » ; icônes de runes sans
    /// version : « ddragon/img/perk-images/… » ; données : « ddragon/16.18.1/data/fr_FR/item.json »). nil pour un autre
    /// hôte ou un autre chemin.
    static func cachePath(for url: URL) -> String? {
        guard url.host() == "ddragon.leagueoflegends.com" else { return nil }
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix("/cdn/") else { return nil }
        return DiskCache.safePath("ddragon/" + path.dropFirst("/cdn/".count))
    }
}
