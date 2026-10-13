import SwiftUI
import UIKit

/// Fond des widgets de l'écran d'accueil (spec §9, maquette ③) : l'abysse et ses deux nappes, ou, pour une équipe,
/// un dégradé à 160° de sa couleur vers l'abysse. Posé par `containerBackground(for: .widget)` dans l'extension.
struct WidgetBackdrop: View {
    var tint: Color?

    var body: some View {
        ZStack {
            Palette.abyss
            if let tint {
                LinearGradient(colors: [tint.opacity(0.30), Palette.abyss.opacity(0.95)],
                               startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
            } else {
                LinearGradient(colors: [Palette.blueWash, .clear], startPoint: .topLeading,
                               endPoint: UnitPoint(x: 0.5, y: 0.45))
                LinearGradient(colors: [Palette.tealWash, .clear], startPoint: .bottomTrailing,
                               endPoint: UnitPoint(x: 0.5, y: 0.55))
            }
        }
    }
}

/// Monogramme d'une équipe (spec §4.4 : pas de logo dans les widgets) : son code dans un badge bordé de sa couleur ;
/// verre neutre pour une équipe non suivie.
struct MonogramBadge: View {
    let code: String
    var tint: Color? = nil
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
        Text(code)
            .font(Sora.font(size * 0.32, .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .foregroundStyle(tint ?? Palette.text)
            .frame(width: size, height: size)
            .background(shape.fill(Palette.chipFill))
            .overlay(shape.strokeBorder(tint ?? Palette.glassBorder, lineWidth: 1))
    }
}

/// Icône du widget en ligne, redessinée à la taille du texte : sur l'écran verrouillé, iOS affiche l'image d'un widget
/// en ligne à sa taille propre (les cadres y sont ignorés). Rendue en « template » : iOS la colore comme le texte.
@MainActor
enum InlineIcon {
    static func image(_ icon: Icon, size: CGFloat = 14) -> Image {
        guard let source = UIImage(named: icon.assetName) else { return Image(icon: icon) }
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            source.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return Image(uiImage: drawn.withRenderingMode(.alwaysTemplate))
    }
}
