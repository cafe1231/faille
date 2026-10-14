import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Faille

/// Vocabulaire de mouvement, « Réduire les animations », toucher et retours haptiques (spec finitions : Principes,
/// §2, §3, §7, Vérification).
@MainActor
struct MotionTests {
    @Test func everyAnimationRunsWhenReduceMotionIsOff() {
        for kind in Motion.Kind.allCases {
            #expect(Motion.reduced(kind, reduceMotion: false) == .full)
            #expect(Motion.animation(kind, reduceMotion: false) != nil)
        }
        for effect in Motion.Effect.allCases {
            #expect(Motion.runs(effect, reduceMotion: false))
        }
    }

    /// Spec, Principes : sous « Réduire les animations », un mouvement pur devient immédiat (nil), un changement de
    /// contenu devient un fondu ; zoom, cascade, pulsation, lueur, reflet et glissement s'arrêtent.
    @Test func reduceMotionReplacesMovesWithAFadeOrNothing() {
        #expect(Motion.reduced(.press, reduceMotion: true) == .instant)
        #expect(Motion.reduced(.smooth, reduceMotion: true) == .instant)
        #expect(Motion.animation(.press, reduceMotion: true) == nil)
        #expect(Motion.animation(.smooth, reduceMotion: true) == nil)
        for kind in [Motion.Kind.snappy, .number, .list, .reveal] {
            #expect(Motion.reduced(kind, reduceMotion: true) == .fade)
            #expect(Motion.animation(kind, reduceMotion: true) != nil)
        }
        for effect in Motion.Effect.allCases {
            #expect(!Motion.runs(effect, reduceMotion: true))
        }
    }

    /// Les durées nommées de la spec (≈ 0,18 / 0,3 / 0,45 / 0,5 s ; halo 1,6 s ; lueur 2,4 s ; cascade 40 ms).
    @Test func namedDurationsFollowTheSpec() {
        #expect(Motion.Duration.press == 0.18)
        #expect(Motion.Duration.snappy == 0.3)
        #expect(Motion.Duration.smooth == 0.45)
        #expect(Motion.Duration.reveal == 0.5)
        #expect(Motion.Duration.livePulse == 1.6)
        #expect(Motion.Duration.teamGlow == 2.4)
        #expect(Motion.Duration.cascadeStep == 0.04)
        #expect(Motion.revealBlur == 10)
        #expect(Motion.insertScale == 0.96)
    }

    /// Le halo et la lueur respirent en aller-retour : chaque courbe dure la moitié de la durée nommée.
    @Test func breathingCurvesAreHalfACycle() {
        #expect(Motion.livePulseAnimation == .easeInOut(duration: Motion.Duration.livePulse / 2))
        #expect(Motion.teamGlowAnimation == .easeInOut(duration: Motion.Duration.teamGlow / 2))
    }

    @Test func aPressedSurfaceShrinksOnlyWhenMotionIsAllowed() {
        #expect(Motion.pressScale(pressed: true, reduceMotion: false) == 0.97)
        #expect(Motion.pressScale(pressed: true, reduceMotion: true) == 1)
        #expect(Motion.pressScale(pressed: false, reduceMotion: false) == 1)
        #expect(Motion.pressOpacity(pressed: true) < 1)
        #expect(Motion.pressOpacity(pressed: false) == 1)
    }

    /// Spec finitions §7 : ≈ 40 ms par carte, 8 cartes au plus.
    @Test func theCascadeIsFortyMillisecondsPerCardForEightCardsAtMost() {
        #expect(Motion.cascadeLimit == 8)
        #expect(Motion.cascadeDelay(index: 0) == 0)
        #expect(abs(Motion.cascadeDelay(index: 3) - 0.12) < 1e-9)
        #expect(abs(Motion.cascadeDelay(index: 7) - 0.28) < 1e-9)
        #expect(Motion.cascadeDelay(index: 30) == Motion.cascadeDelay(index: 7))
        #expect(Motion.cascadeDelay(index: -1) == 0)
    }

    /// Spec finitions §2 : zone tactile inchangée — même taille mesurée qu'avec `.plain`, au moins 44 × 44 pt.
    @Test func pressableStyleKeepsTheHitArea() {
        let pressable = Self.fittingSize(Button(action: {}) { HitTarget() }.buttonStyle(.pressable))
        let plain = Self.fittingSize(Button(action: {}) { HitTarget() }.buttonStyle(.plain))
        #expect(pressable == plain)
        #expect(pressable.width >= 44 && pressable.height >= 44)
    }

    /// `@ReduceMotion` : la valeur forcée d'abord (aperçus PNG), sinon le réglage du système (coupé sur le simulateur
    /// de la CI).
    @Test func reduceMotionReadsTheOverrideThenTheSystem() {
        #expect(MotionProbe.read(override: true) == true)
        #expect(MotionProbe.read(override: false) == false)
        #expect(MotionProbe.read(override: nil) == false)
    }

    /// Spec finitions §3 : la nature de chaque retour.
    @Test func eachActionHasItsHaptic() {
        #expect(Haptic.follow.style == .success)
        #expect(Haptic.unfollow.style == .lightImpact)
        #expect(Haptic.spoilerToggle.style == .selection)
        #expect(Haptic.pin.style == .success)
        #expect(Haptic.unpin.style == .lightImpact)
        #expect(Haptic.reveal.style == .mediumImpact)
        #expect(Haptic.refreshSucceeded.style == .success)
        #expect(Haptic.refreshFailed.style == .warning)
        #expect(Haptic.colorPicked.style == .selection)
        #expect(Haptic.gamePicked.style == .selection)
        #expect(Haptic.watch.style == .lightImpact)
        #expect(Haptic.playerPicked.style == .selection)
    }

    /// Deux révélations de suite jouent deux retours : la valeur observée par `.sensoryFeedback` change à chaque fois.
    @Test func twoIdenticalHapticsInARowStillChangeTheTrigger() {
        var trigger = HapticTrigger()
        let start = trigger
        trigger.play(.reveal)
        let first = trigger
        trigger.play(.reveal)
        #expect(first != start)
        #expect(trigger != first)
        #expect(trigger.haptic == .reveal)
        #expect(trigger.count == 2)
    }

    private static func fittingSize(_ view: some View) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 400, height: 400))
    }
}

/// Cible tactile type de l'appli (œil, étoile) : glyphe de 20 pt dans un cadre de 44 × 44 pt.
private struct HitTarget: View {
    var body: some View {
        IconView(icon: .star, size: 20)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Lit `@ReduceMotion` pendant un rendu (`ImageRenderer` évalue `body`).
private struct MotionProbe: View {
    final class Box {
        var value: Bool?

        func record(_ value: Bool) {
            self.value = value
        }
    }

    let box: Box
    @ReduceMotion var reduceMotion

    var body: some View {
        let _ = box.record(reduceMotion)
        Color.clear.frame(width: 1, height: 1)
    }

    static func read(override: Bool?) -> Bool? {
        let box = Box()
        let renderer = ImageRenderer(content: MotionProbe(box: box).environment(\.reduceMotionOverride, override))
        _ = renderer.cgImage
        return box.value
    }
}
