import SwiftUI

/// Rayons de la DA : 28 pt pour les cartes, 22 pt pour les éléments internes et les champs de saisie (spec §9).
/// Les capsules (pilules, pastilles) n'ont pas de rayon : `Capsule()`.
enum Radius {
    static let card: CGFloat = 28
    static let inner: CGFloat = 22
    /// Champ de saisie (recherche) : le rayon des éléments internes, au lieu des 15 pt libres d'avant (audit B-E3).
    static let field: CGFloat = inner
}

/// Carte en verre « matière » (comme Échap) : `.ultraThinMaterial` + dégradé Vitrail à 160° (couleur d'équipe → blanc 3 %)
/// + reflet blanc en haut + arête lumineuse + ombre profonde. `tint` = couleur de l'équipe suivie ; nil = verre neutre.
/// Pas de `glassEffect` ici : sa réfraction des bords répète le texte voisin en « écho » le long du haut des cartes.
/// Le Liquid Glass du système reste réservé aux barres (onglets, barre d'outils).
struct GlassCard: ViewModifier {
    var tint: Color?
    var radius: CGFloat
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(
                        LinearGradient(
                            colors: [tint?.opacity(0.24) ?? Palette.glassFill, Color.white.opacity(0.03)],
                            // ≈ linear-gradient(160deg, …) des maquettes
                            startPoint: UnitPoint(x: 0.33, y: 0),
                            endPoint: UnitPoint(x: 0.67, y: 1)
                        )
                    )
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.35)
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [Palette.glassEdge, Palette.glassBorder.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.35), radius: 15, x: 0, y: 14)
    }
}

extension View {
    func glassCard(tint: Color? = nil, radius: CGFloat = Radius.card, padding: CGFloat = 16) -> some View {
        modifier(GlassCard(tint: tint, radius: radius, padding: padding))
    }
}
