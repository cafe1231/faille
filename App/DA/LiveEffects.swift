import SwiftUI

/// Icône « en direct » et son halo doux qui respire (spec finitions §5 : ≈ 1,6 s, opacité + échelle), dans les
/// pastilles des cartes et du Détail et dans la pilule de la game en cours. Halo fixe sous « Réduire les animations ».
/// Le halo est un fond : il ne change ni la taille ni la place de l'icône. Jamais dans les widgets ni la Live Activity.
struct LiveIndicator: View {
    var size: CGFloat = 12
    @ReduceMotion var reduceMotion

    var body: some View {
        IconView(icon: .live, size: size)
            .background {
                if Motion.runs(.livePulse, reduceMotion: reduceMotion) {
                    Circle()
                        .fill(Palette.accent)
                        .phaseAnimator([false, true]) { halo, expanded in
                            halo
                                .scaleEffect(expanded ? 1.7 : 1.05)
                                .opacity(expanded ? 0.04 : 0.30)
                        } animation: { _ in
                            Motion.livePulseAnimation
                        }
                } else {
                    Circle()
                        .fill(Palette.accent)
                        .scaleEffect(1.3)
                        .opacity(0.18)
                }
            }
    }
}

/// Icône d'une pastille d'état : « en direct » avec son halo, sinon l'icône seule (terminé, à venir).
struct ChipIcon: View {
    let icon: Icon
    var size: CGFloat = 12

    var body: some View {
        if icon == .live {
            LiveIndicator(size: size)
        } else {
            IconView(icon: icon, size: size)
        }
    }
}

/// Lueur d'équipe (spec finitions §12) : contour doux à la couleur de l'équipe, qui respire lentement (≈ 2,4 s, faible
/// amplitude) ; fixe sous « Réduire les animations ». `active` vient de `TeamCardView.glows(_:)` : jamais sur une carte
/// dont le match en direct est masqué.
struct TeamGlow: ViewModifier {
    let color: Color
    let active: Bool
    var radius: CGFloat = Radius.card
    @ReduceMotion var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                if Motion.runs(.teamGlow, reduceMotion: reduceMotion) {
                    glow
                        .phaseAnimator([false, true]) { view, bright in
                            view.opacity(bright ? 0.95 : 0.65)
                        } animation: { _ in
                            Motion.teamGlowAnimation
                        }
                } else {
                    glow.opacity(0.8)
                }
            }
        }
    }

    private var glow: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color.opacity(0.55), lineWidth: 1.2)
            .shadow(color: color.opacity(0.55), radius: 9)
            .allowsHitTesting(false)
    }
}

/// Apparition en cascade (spec finitions §7) : la carte `index` arrive en fondu en montant de 12 pt, 40 ms après la
/// précédente (8 cartes au plus). `shown` passe à vrai une fois ; il est vrai d'emblée sous « Réduire les animations ».
struct CascadeIn: ViewModifier {
    let index: Int
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : Motion.cascadeOffset)
            .animation(Motion.list.delay(Motion.cascadeDelay(index: index)), value: shown)
    }
}

extension View {
    /// Lueur d'équipe sur le contour d'une carte.
    func teamGlow(_ color: Color, active: Bool) -> some View {
        modifier(TeamGlow(color: color, active: active))
    }

    /// Place de la carte dans la cascade d'apparition.
    func cascadeIn(index: Int, shown: Bool) -> some View {
        modifier(CascadeIn(index: index, shown: shown))
    }
}
