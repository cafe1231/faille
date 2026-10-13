import CoreText
import SwiftUI
import UIKit

/// Sora, police variable embarquée (Resources/Fonts/Sora-Variable.ttf, famille « Sora », axe `wght` 100–800).
/// La graisse est posée sur l'axe de variation : `.fontWeight` n'est pas fiable sur une police variable embarquée.
enum Sora {
    enum Weight: CGFloat, Sendable {
        case regular = 400, medium = 500, semibold = 600, bold = 700

        var system: UIFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    /// Balise OpenType `wght` lue comme un entier 32 bits (clé du dictionnaire de variations de CoreText).
    private static let weightAxis = 0x7767_6874

    static func uiFont(_ size: CGFloat, _ weight: Weight) -> UIFont {
        let variation = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let attributes: [UIFontDescriptor.AttributeName: Any] = [
            .family: "Sora",
            variation: [weightAxis: weight.rawValue],
        ]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
        // Police absente (fichier non embarqué) : police système plutôt qu'une police de repli quelconque.
        return font.familyName == "Sora" ? font : .systemFont(ofSize: size, weight: weight.system)
    }

    static func font(_ size: CGFloat, _ weight: Weight) -> Font {
        Font(uiFont(size, weight) as CTFont)
    }
}

/// Échelle typographique (spec §9 ; tailles des maquettes ×1,355 pour passer de 290 px à 393 pt).
enum Typo {
    /// Titre d'écran, avec `.tracking(Typo.titleTracking)`.
    static let title = Sora.font(32, .bold)
    static let titleTracking: CGFloat = -1.28 // −0,04 em
    static let scoreLarge = Sora.font(28, .bold)
    static let score = Sora.font(22, .bold)
    static let headline = Sora.font(15, .semibold)
    static let body = Sora.font(15, .regular)
    static let bodyMedium = Sora.font(15, .medium)
    static let stat = Sora.font(15, .bold)
    static let secondary = Sora.font(12, .regular)
    static let secondaryMedium = Sora.font(12, .medium)
    /// Étiquette en capitales, avec `.tracking(Typo.labelTracking)` et `.textCase(.uppercase)`.
    static let label = Sora.font(11, .semibold)
    static let labelTracking: CGFloat = 0.88 // 0,08 em
    static let chip = Sora.font(11.5, .semibold)
}
