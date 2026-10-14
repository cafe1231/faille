import SwiftUI

/// Retours haptiques de Faille (spec finitions §3) : un par action de l'utilisateur, jamais sur une mise à jour des
/// données (pas à chaque relecture des stats). Ils restent sous « Réduire les animations ».
enum Haptic: Equatable, Sendable {
    case follow, unfollow
    case spoilerToggle
    case pin, unpin
    case reveal
    case refreshSucceeded, refreshFailed
    case colorPicked
    case gamePicked

    /// Nature du retour, testable sans `SensoryFeedback`.
    enum Style: Equatable, Sendable {
        case success, lightImpact, mediumImpact, selection, warning
    }

    /// Suivre, épingler, rafraîchir : succès ; ne plus suivre, retirer : impact léger ; œil, couleur, pilule :
    /// sélection ; révéler : impact moyen ; rafraîchir en échec : avertissement.
    var style: Style {
        switch self {
        case .follow, .pin, .refreshSucceeded: return .success
        case .unfollow, .unpin: return .lightImpact
        case .spoilerToggle, .colorPicked, .gamePicked: return .selection
        case .reveal: return .mediumImpact
        case .refreshFailed: return .warning
        }
    }

    var feedback: SensoryFeedback {
        switch style {
        case .success: return .success
        case .lightImpact: return .impact(weight: .light)
        case .mediumImpact: return .impact(weight: .medium)
        case .selection: return .selection
        case .warning: return .warning
        }
    }
}

/// Déclencheur de `.sensoryFeedback` : chaque `play` change la valeur observée, même pour deux retours identiques de
/// suite. À garder dans une vue qui reste à l'écran après l'action (l'écran ou la carte, pas la ligne ni le bouton qui
/// disparaissent avec elle).
struct HapticTrigger: Equatable {
    private(set) var haptic: Haptic?
    private(set) var count = 0

    mutating func play(_ haptic: Haptic) {
        self.haptic = haptic
        count += 1
    }
}

extension View {
    /// Joue le retour de chaque `trigger.play(_:)`.
    func haptics(_ trigger: HapticTrigger) -> some View {
        sensoryFeedback(trigger: trigger) { _, new in new.haptic?.feedback }
    }
}
