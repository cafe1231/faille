import UIKit

/// Vignettes de logos pour `TeamBadge` : les PNG réduits que le pipeline des équipes suivies a déjà écrits dans
/// `logos/` (128 px au plus). Décodées hors du fil principal, une seule fois, puis gardées en mémoire :
/// le `body` d'une vue ne lit jamais de fichier. Aucun téléchargement ici — une équipe sans vignette garde son monogramme.
@MainActor
final class LogoImages {
    static let shared = LogoImages()

    /// Image décodée, transportée d'un fil à l'autre : elle n'est jamais modifiée après sa création.
    private struct Decoded: @unchecked Sendable {
        let image: UIImage?
    }

    private let cache = NSCache<NSString, UIImage>()

    /// Vignette déjà en mémoire (lecture instantanée, sans disque), sinon nil.
    func cached(_ file: URL) -> UIImage? {
        cache.object(forKey: Self.key(file))
    }

    /// Vignette du fichier : mémoire d'abord, sinon lecture et décodage sur un fil d'arrière-plan. nil si illisible.
    func load(_ file: URL) async -> UIImage? {
        if let hit = cached(file) { return hit }
        let path = file.path(percentEncoded: false)
        let decoded = await Task.detached(priority: .utility) {
            Decoded(image: UIImage(contentsOfFile: path)?.preparingForDisplay())
        }.value
        guard let image = decoded.image else { return nil }
        cache.setObject(image, forKey: Self.key(file))
        return image
    }

    private static func key(_ file: URL) -> NSString {
        file.path(percentEncoded: false) as NSString
    }
}
