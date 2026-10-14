import SwiftUI
import UIKit

/// Styles de texte Sora qui suivent la taille du texte de l'appareil (spec saison §3.8, Dynamic Type) : la taille de
/// `Typo` est mise à l'échelle par `UIFontMetrics` du style iOS correspondant (titres ↔ `.largeTitle`, corps ↔ `.body`,
/// secondaire ↔ `.footnote`, étiquettes ↔ `.caption2`), plafonnée à `.accessibility2` (au-delà, les cartes débordent).
/// Nouveaux écrans : `.sora(.body)` plutôt que `.font(Typo.body)` ; les tracking (`Typo.titleTracking`,
/// `Typo.labelTracking`) restent posés à part. Widgets et Live Activity gardent `Typo` (tailles fixes).
enum SoraStyle: CaseIterable, Sendable {
    case title, scoreLarge, score, headline, body, bodyMedium, stat, secondary, secondaryMedium, label, chip

    /// Taille de `Typo` à la taille de texte par défaut (`.large`).
    var size: CGFloat {
        switch self {
        case .title: 32
        case .scoreLarge: 28
        case .score: 22
        case .headline, .body, .bodyMedium, .stat: 15
        case .secondary, .secondaryMedium: 12
        case .label: 11
        case .chip: 11.5
        }
    }

    var weight: Sora.Weight {
        switch self {
        case .title, .scoreLarge, .score, .stat: .bold
        case .headline, .label, .chip: .semibold
        case .bodyMedium, .secondaryMedium: .medium
        case .body, .secondary: .regular
        }
    }

    var textStyle: UIFont.TextStyle {
        switch self {
        case .title, .scoreLarge, .score: .largeTitle
        case .headline, .body, .bodyMedium, .stat: .body
        case .secondary, .secondaryMedium: .footnote
        case .label, .chip: .caption2
        }
    }

    /// Au-delà, le texte ne grandit plus.
    static let largestSize: DynamicTypeSize = .accessibility2

    func pointSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let capped = min(dynamicTypeSize, Self.largestSize)
        let traits = UITraitCollection(preferredContentSizeCategory: Self.category(capped))
        return UIFontMetrics(forTextStyle: textStyle).scaledValue(for: size, compatibleWith: traits)
    }

    /// Correspondance explicite (même ordre que `DynamicTypeSize`) : aucune dépendance à un initialiseur de pont.
    private static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

private struct SoraFont: ViewModifier {
    let style: SoraStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(Sora.font(style.pointSize(for: dynamicTypeSize), style.weight))
    }
}

extension View {
    /// Police Sora du style, à la taille de texte de l'appareil (plafonnée).
    func sora(_ style: SoraStyle) -> some View {
        modifier(SoraFont(style: style))
    }
}
