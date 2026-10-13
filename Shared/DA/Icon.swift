import SwiftUI

/// Icônes au trait des maquettes (grille 24, trait 1,8), dans Resources/Assets.xcassets en rendu « template » :
/// elles prennent la couleur du texte courant. Jamais d'emoji (spec §9).
enum Icon: String, CaseIterable, Sendable {
    case swords, gold, tower, inhib, drake, baron, clock, live, eye
    case eyeOff = "eyeoff"
    case star
    case starFill = "star-fill"
    case trophy, settings, search, back, arrow, pin, check, refresh, off, pause

    var assetName: String {
        "icon-" + rawValue
    }
}

extension Image {
    init(icon: Icon) {
        self.init(icon.assetName)
    }
}

/// Une icône à la taille voulue (14 pt par défaut), teinte du texte courant. Décorative : VoiceOver ne la lit pas,
/// c'est le texte voisin (ou le `accessibilityLabel` du bouton qui la contient) qui porte le sens.
struct IconView: View {
    let icon: Icon
    var size: CGFloat = 14

    var body: some View {
        Image(icon: icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
