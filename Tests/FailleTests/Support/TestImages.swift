import Foundation
import LoLKit
import UIKit
@testable import Faille

/// Fausses icônes Data Dragon pour les tests et les aperçus : aucun réseau, aucune image de Riot dans le dépôt.
enum TestImages {
    /// PNG carré uni avec une lettre (48 pt, à l'échelle de l'écran).
    static func png(_ color: UIColor, letter: String = "", side: CGFloat = 48) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.45, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let text = letter as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attributes)
        }
    }

    /// Dépose de fausses icônes dans le cache, au chemin de leur URL Data Dragon : `DataDragonStore` les lit comme les vraies.
    static func seed(_ cache: DiskCache, _ icons: [(url: URL, color: UIColor, letter: String)]) {
        for icon in icons {
            guard let path = DataDragon.cachePath(for: icon.url) else { continue }
            cache.write(png(icon.color, letter: icon.letter), to: path)
        }
    }
}
