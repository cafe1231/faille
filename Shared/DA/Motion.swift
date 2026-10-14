import SwiftUI

/// Vocabulaire de mouvement de Faille (spec finitions, « Principes ») : ressorts et durées nommés, et ce qu'ils
/// deviennent sous « Réduire les animations ». Aucune durée en dur dans les vues : elles passent toutes par ici.
/// Dans `Shared/` : les widgets et la Live Activity utilisent `numericTransition()`.
enum Motion {
    /// Durées, en secondes.
    enum Duration {
        static let press: Double = 0.18
        static let snappy: Double = 0.3
        static let number: Double = 0.35
        static let list: Double = 0.4
        static let smooth: Double = 0.45
        static let reveal: Double = 0.5
        /// Fondu : remplaçant des mouvements sous « Réduire les animations », et masquage par l'œil.
        static let fade: Double = 0.2
        /// Un aller-retour du halo « en direct ».
        static let livePulse: Double = 1.6
        /// Un aller-retour de la lueur d'équipe.
        static let teamGlow: Double = 2.4
        /// Un passage du reflet d'un squelette de chargement.
        static let shimmer: Double = 1.6
        /// Décalage entre deux cartes de la cascade d'apparition.
        static let cascadeStep: Double = 0.04
    }

    /// Les animations nommées de la spec.
    enum Kind: CaseIterable, Sendable {
        /// Appui sur une surface touchable.
        case press
        /// Bandeau d'erreur, capsule des pilules, onglet des joueurs.
        case snappy
        /// Largeur de la barre de gold.
        case smooth
        /// Chiffres qui défilent.
        case number
        /// Cartes et lignes qui arrivent, partent ou changent d'ordre.
        case list
        /// Révélation anti-spoiler.
        case reveal
    }

    /// Ce que devient une animation sous « Réduire les animations ».
    enum Reduced: Equatable, Sendable {
        /// Réglage coupé : l'animation de la spec.
        case full
        /// Un fondu court remplace le mouvement.
        case fade
        /// Plus d'animation : le changement est immédiat.
        case instant
    }

    /// Effets continus ou spatiaux, arrêtés (ou figés) sous « Réduire les animations ».
    enum Effect: CaseIterable, Sendable {
        case livePulse, teamGlow, shimmer, cascade, zoom, pillSlide
    }

    /// Règle « Réduire les animations » (spec, Principes) : un mouvement pur (appui, largeur de la barre de gold)
    /// devient immédiat ; un changement de contenu (chiffres, listes, révélation, bandeau, pilules) devient un fondu de
    /// `Duration.fade` (0,2 s). Ce fondu est une courbe `easeInOut` posée sur la transaction : elle anime donc encore
    /// les positions quand des cartes ou des lignes changent d'ordre ou d'arrivée (elles glissent 0,2 s, sans zoom ni
    /// ressort). Comportement accepté, à juger sur l'appareil (checklist D.13).
    static func reduced(_ kind: Kind, reduceMotion: Bool) -> Reduced {
        guard reduceMotion else { return .full }
        switch kind {
        case .press, .smooth: return .instant
        case .snappy, .number, .list, .reveal: return .fade
        }
    }

    /// L'animation à poser ; nil : aucune (changement immédiat).
    static func animation(_ kind: Kind, reduceMotion: Bool) -> Animation? {
        switch reduced(kind, reduceMotion: reduceMotion) {
        case .full: return base(kind)
        case .fade: return fade
        case .instant: return nil
        }
    }

    /// Un effet continu ou spatial tourne-t-il ? Jamais sous « Réduire les animations » (halo et lueur restent, fixes).
    static func runs(_ effect: Effect, reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    // MARK: Animations de la spec (sobres : aucun rebond, sauf 8 % pour les listes)

    static var press: Animation { .spring(duration: Duration.press, bounce: 0) }
    static var snappy: Animation { .spring(duration: Duration.snappy, bounce: 0) }
    static var smooth: Animation { .smooth(duration: Duration.smooth) }
    static var number: Animation { .smooth(duration: Duration.number) }
    static var list: Animation { .spring(duration: Duration.list, bounce: 0.08) }
    static var reveal: Animation { .easeOut(duration: Duration.reveal) }
    static var fade: Animation { .easeInOut(duration: Duration.fade) }

    /// Demi-cycle (aller ou retour) du halo « en direct » : la respiration dure `Duration.livePulse` en tout.
    static var livePulseAnimation: Animation { .easeInOut(duration: Duration.livePulse / 2) }
    /// Demi-cycle (aller ou retour) de la lueur d'équipe : la respiration dure `Duration.teamGlow` en tout.
    static var teamGlowAnimation: Animation { .easeInOut(duration: Duration.teamGlow / 2) }

    private static func base(_ kind: Kind) -> Animation {
        switch kind {
        case .press: return press
        case .snappy: return snappy
        case .smooth: return smooth
        case .number: return number
        case .list: return list
        case .reveal: return reveal
        }
    }

    // MARK: Valeurs

    /// Échelle d'une surface appuyée (spec finitions §2) ; 1 sous « Réduire les animations ».
    static func pressScale(pressed: Bool, reduceMotion: Bool) -> CGFloat {
        pressed && !reduceMotion ? 0.97 : 1
    }

    /// Opacité d'une surface appuyée : légère baisse, gardée sous « Réduire les animations » (ce n'est pas un mouvement).
    static func pressOpacity(pressed: Bool) -> Double {
        pressed ? 0.85 : 1
    }

    /// Cascade d'apparition (spec finitions §7) : au plus 8 cartes décalées ; les suivantes arrivent avec la 8e.
    static let cascadeLimit = 8

    /// Retard de la carte `index` dans la cascade : 40 ms par carte.
    static func cascadeDelay(index: Int) -> Double {
        Double(min(max(index, 0), cascadeLimit - 1)) * Duration.cascadeStep
    }

    /// Distance que parcourt une carte qui arrive en cascade (points).
    static let cascadeOffset: CGFloat = 12
    /// Échelle de départ d'une carte ou d'une ligne qui arrive (spec finitions §7).
    static let insertScale: CGFloat = 0.96
    /// Rayon du flou d'où sort un score révélé (spec finitions §8).
    static let revealBlur: CGFloat = 10

    // MARK: Transitions

    /// Carte ou ligne : arrive en fondu en grandissant depuis 0,96, part en fondu ; fondu seul sous « Réduire les
    /// animations ».
    @MainActor static func listTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .scale(scale: insertScale)),
                                              removal: .opacity)
    }

    /// Bandeau d'erreur : glisse du haut en fondu ; fondu seul sous « Réduire les animations ».
    @MainActor static func bannerTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    /// Révélation (spec finitions §8) : le contenu sort d'un flou (10 → 0) en fondu ; masquage : fondu simple. Fondu
    /// seul sous « Réduire les animations ».
    @MainActor static func revealTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: BlurFade(radius: revealBlur, opacity: 0),
                                 identity: BlurFade(radius: 0, opacity: 1)),
            removal: .opacity
        )
    }
}

/// Flou et opacité : les deux états de la transition de révélation.
struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

extension EnvironmentValues {
    /// Force « Réduire les animations » ; nil : réglage du système. Les aperçus PNG le mettent à vrai : rendus figés,
    /// dans l'état final (ni cascade en cours, ni halo à mi-respiration, ni reflet de squelette).
    @Entry var reduceMotionOverride: Bool? = nil
}

/// « Réduire les animations » tel que les vues de Faille le lisent : la valeur forcée (`reduceMotionOverride`) si elle
/// existe, sinon le réglage du système (`accessibilityReduceMotion`). Les retours haptiques n'en dépendent pas.
/// S'emploie sans `private` (`@ReduceMotion var reduceMotion`) : l'initialiseur membre à membre des vues reste interne.
@propertyWrapper
struct ReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @Environment(\.reduceMotionOverride) private var override

    init() {}

    @MainActor var wrappedValue: Bool {
        override ?? system
    }
}

/// Chiffres qui défilent dans l'appli (spec finitions §4) : transition numérique animée par `Motion.number` quand
/// `value` change ; fondu sous « Réduire les animations ». À poser seulement sur une valeur affichée, donc déjà jugée
/// non masquée (un score masqué n'est jamais rendu : il ne peut pas défiler).
struct NumericChange<Value: Equatable>: ViewModifier {
    let value: Value
    @ReduceMotion var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(Motion.animation(.number, reduceMotion: reduceMotion), value: value)
    }
}

/// Chiffres qui défilent dans un widget ou la Live Activity : WidgetKit et ActivityKit animent eux-mêmes le passage
/// d'une entrée (ou d'une mise à jour) à la suivante. Aucune animation continue (spec finitions §4, Hors périmètre) :
/// ne jamais le poser sur un conteneur qui contient un chrono qui tourne.
struct NumericTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .opacity : .numericText())
    }
}

extension View {
    /// Chiffres qui défilent quand `value` change (appli).
    func numericChange<Value: Equatable>(_ value: Value) -> some View {
        modifier(NumericChange(value: value))
    }

    /// Chiffres qui défilent d'une entrée à l'autre (widgets, Live Activity).
    func numericTransition() -> some View {
        modifier(NumericTransition())
    }
}
