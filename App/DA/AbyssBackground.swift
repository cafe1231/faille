import SwiftUI

/// Fond « Abysse » (spec §9) : #0b1020, nappe bleue en haut à gauche, nappe turquoise en bas à droite.
struct AbyssBackground: View {
    var body: some View {
        ZStack {
            Palette.abyss
            LinearGradient(colors: [Palette.blueWash, .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.5, y: 0.45))
            LinearGradient(colors: [Palette.tealWash, .clear], startPoint: .bottomTrailing, endPoint: UnitPoint(x: 0.5, y: 0.55))
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Pose le fond Abysse derrière un écran entier.
    func abyssBackground() -> some View {
        background { AbyssBackground() }
    }
}
