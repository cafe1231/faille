import Foundation

/// Data Dragon (`ddragon.leagueoflegends.com`) : images et données officielles de Riot, sans clé (spec fonctionnalités §3).
/// Ce fichier ne fait que choisir la version et écrire les liens ; l'appli télécharge et met en cache disque.
public enum DataDragon {
    static let base = "https://ddragon.leagueoflegends.com"
    /// Langue des données (noms d'objets, de runes, de sorts).
    public static let language = "fr_FR"
    /// Liste des versions, la plus récente d'abord. À relire au plus une fois toutes les 24 h.
    public static let versionsURL = URL(string: "\(base)/api/versions.json")!
    public static let versionsMaxAge: TimeInterval = 24 * 3600

    /// Version Data Dragon d'un patch du flux (`gameMetadata.patchVersion`, ex. « 16.18.819.1060 ») : la plus récente
    /// qui commence par « major.minor. » (« 16.18.1 »), sinon la plus récente. Les entrées `lolpatch_*` sont ignorées.
    /// nil si la liste n'a aucune version.
    /// - Parameter versions: `api/versions.json`, dans son ordre (la plus récente d'abord).
    public static func version(forPatch patch: String?, versions: [String]) -> String? {
        let releases = versions.filter { $0.first?.isNumber == true }
        if let patch {
            let parts = patch.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty {
                // Le point final compte : « 16.1. » ne doit pas prendre « 16.18.1 ».
                let prefix = "\(parts[0]).\(parts[1])."
                if let match = releases.first(where: { $0.hasPrefix(prefix) }) { return match }
            }
        }
        return releases.first
    }

    /// Lit `api/versions.json` (un tableau de chaînes).
    public static func decodeVersions(_ data: Data) throws -> [String] {
        try JSONDecoder().decode([String].self, from: data)
    }

    // MARK: Images

    /// `cdn/<v>/img/champion/<championId>.png` (`championId` du flux, ex. « KSante »).
    public static func championImage(version: String, championId: String) -> URL {
        url("cdn/\(version)/img/champion/\(championId).png")
    }

    /// `cdn/<v>/img/item/<id>.png`
    public static func itemImage(version: String, itemId: Int) -> URL {
        url("cdn/\(version)/img/item/\(itemId).png")
    }

    /// Sort d'un champion : `cdn/<v>/img/spell/<image.full>` (ex. « KSanteQ.png »).
    public static func spellImage(version: String, file: String) -> URL {
        url("cdn/\(version)/img/spell/\(file)")
    }

    /// Passif d'un champion : `cdn/<v>/img/passive/<image.full>`.
    public static func passiveImage(version: String, file: String) -> URL {
        url("cdn/\(version)/img/passive/\(file)")
    }

    /// Sort d'invocateur : `cdn/<v>/img/spell/<id>.png` (ex. « SummonerFlash »).
    public static func summonerSpellImage(version: String, spellId: String) -> URL {
        url("cdn/\(version)/img/spell/\(spellId).png")
    }

    /// Icône de rune ou d'arbre (`icon` de `runesReforged.json`) : `cdn/img/<icon>`, sans version.
    public static func runeIcon(_ icon: String) -> URL {
        url("cdn/img/\(icon)")
    }

    // MARK: Données (fr_FR)

    public static func itemsURL(version: String) -> URL {
        url("cdn/\(version)/data/\(language)/item.json")
    }

    public static func runesURL(version: String) -> URL {
        url("cdn/\(version)/data/\(language)/runesReforged.json")
    }

    public static func summonerSpellsURL(version: String) -> URL {
        url("cdn/\(version)/data/\(language)/summoner.json")
    }

    /// Détail d'un champion (sorts et passif) : `data/fr_FR/champion/<championId>.json`.
    public static func championURL(version: String, championId: String) -> URL {
        url("cdn/\(version)/data/\(language)/champion/\(championId).json")
    }

    /// Chemin encodé pour une URL (un id venu du flux ne peut pas casser le lien) ; après encodage, `URL(string:)` réussit
    /// toujours sur cette base https.
    private static func url(_ path: String) -> URL {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return URL(string: "\(base)/\(encoded)")!
    }
}
