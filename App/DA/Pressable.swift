import SwiftUI

/// Toucher (spec finitions §2) : la surface s'enfonce (échelle 0,97) et pâlit un peu pendant l'appui, avec le ressort
/// `Motion.press` ; sous « Réduire les animations », elle pâlit seulement. Remplace le style `plain` : comme lui,
/// il ne colore pas le libellé. La zone tactile ne change pas : `scaleEffect` n'agit que sur le rendu, ni sur la mise
/// en page ni sur la forme de toucher (`contentShape` du libellé).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

/// Le libellé appuyé ; une vue à part pour lire « Réduire les animations ».
private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    @ReduceMotion var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(Motion.pressScale(pressed: configuration.isPressed, reduceMotion: reduceMotion))
            .opacity(Motion.pressOpacity(pressed: configuration.isPressed))
            .animation(Motion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    /// `.buttonStyle(.pressable)` : cartes, lignes, pilules, boutons en verre.
    static var pressable: PressableStyle { PressableStyle() }
}
