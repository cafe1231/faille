import SwiftUI

/// Variantes de l'icône (iOS 18+) : claire (par défaut), sombre (fond transparent : iOS pose son fond sombre),
/// teintée (niveaux de gris : iOS applique la teinte choisie).
enum AppIconVariant: String, CaseIterable, Sendable {
    case standard, dark, tinted

    /// Nom du PNG, dans l'artefact `Faille-apercus` comme dans `AppIcon.appiconset`.
    var fileName: String {
        switch self {
        case .standard: return "app-icon-1024"
        case .dark: return "app-icon-1024-dark"
        case .tinted: return "app-icon-1024-tinted"
        }
    }
}

/// Icône de Faille (spec finitions §1) : fond abysse (`#0B1020` vers plus profond), une faille verticale lumineuse à
/// l'accent `#6FD3FF` avec un halo doux, rien d'autre (pas de texte). Dessinée dans un carré de `size` points : rendue
/// à 1024 × 1024 px par un test hébergé (`ImageRenderer`, échelle 1), puis copiée dans `AppIcon.appiconset`.
struct AppIconArt: View {
    let variant: AppIconVariant
    /// Côté du carré, en points (rendu à l'échelle 1 : en pixels).
    let size: CGFloat

    var body: some View {
        ZStack {
            background
            // Halo doux autour de la faille.
            Ellipse()
                .fill(RadialGradient(colors: [glow.opacity(haloOpacity), glow.opacity(haloOpacity * 0.25), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.36))
                .frame(width: size * 0.62, height: size * 0.95)
                .blur(radius: size * 0.04)
            // Lueur large, lueur serrée, puis la faille : blanche au milieu, à l'accent vers les pointes.
            RiftShape()
                .fill(glow)
                .blur(radius: size * 0.03)
            RiftShape()
                .fill(glow.opacity(0.6))
                .blur(radius: size * 0.008)
            RiftShape()
                .fill(LinearGradient(colors: [glow, Color.white, glow], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var background: some View {
        switch variant {
        case .standard:
            LinearGradient(colors: [Palette.abyss, Color(red: 4 / 255, green: 7 / 255, blue: 18 / 255)],
                           startPoint: .top, endPoint: .bottom)
        case .dark:
            Color.clear
        case .tinted:
            Color.black
        }
    }

    /// Lueur : l'accent, ou un gris clair pour la variante teintée (niveaux de gris seulement).
    private var glow: Color {
        variant == .tinted ? Color(white: 0.82) : Palette.accent
    }

    private var haloOpacity: Double {
        variant == .tinted ? 0.30 : 0.38
    }
}

/// La faille : une fente verticale en zigzag, effilée aux deux pointes, plus large au milieu (fractions du carré).
struct RiftShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Pointe du haut, bord gauche de haut en bas, pointe du bas, bord droit de bas en haut.
        let outline: [(x: CGFloat, y: CGFloat)] = [
            (0.500, 0.140),
            (0.471, 0.280), (0.500, 0.400), (0.442, 0.520), (0.496, 0.640), (0.478, 0.760),
            (0.505, 0.870),
            (0.506, 0.760), (0.556, 0.640), (0.522, 0.520), (0.560, 0.400), (0.499, 0.280),
        ]
        var path = Path()
        for (index, point) in outline.enumerated() {
            let location = CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
            if index == 0 {
                path.move(to: location)
            } else {
                path.addLine(to: location)
            }
        }
        path.closeSubpath()
        return path
    }
}
