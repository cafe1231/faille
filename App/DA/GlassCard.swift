import SwiftUI

/// Rayons de la DA : 28 pt pour les cartes, 22 pt pour les éléments internes (spec §9).
enum Radius {
    static let card: CGFloat = 28
    static let inner: CGFloat = 22
}

/// Carte en verre : Liquid Glass d'iOS 26 (`glassEffect`) + dégradé Vitrail à 160° (couleur d'équipe → blanc 3 %)
/// + arête lumineuse en haut + ombre profonde. `tint` = couleur de l'équipe suivie ; nil = verre neutre.
/// API iOS 26 utilisée : `View.glassEffect(_ glass: Glass, in shape: some Shape)` et `Glass.regular.tint(_:)`.
/// Si le SDK refuse ces noms, remplacer la ligne `.glassEffect(…)` par `.background(.ultraThinMaterial, in: shape)`.
struct GlassCard: ViewModifier {
    var tint: Color?
    var radius: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint?.opacity(0.24) ?? Palette.glassFill, Color.white.opacity(0.03)],
                    // ≈ linear-gradient(160deg, …) des maquettes
                    startPoint: UnitPoint(x: 0.33, y: 0),
                    endPoint: UnitPoint(x: 0.67, y: 1)
                ),
                in: shape
            )
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.10)) } ?? .regular, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Palette.glassEdge, Palette.glassBorder.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 15, x: 0, y: 14)
    }
}

extension View {
    func glassCard(tint: Color? = nil, radius: CGFloat = Radius.card, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(tint: tint, radius: radius, padding: padding))
    }
}
