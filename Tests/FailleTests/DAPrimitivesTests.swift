import SwiftUI
import Testing
import UIKit
@testable import Faille

/// Primitives de la DA du lot qualité (E0) : blancs à opacité nommés, rayon des champs, zone tactile des pilules,
/// reflet des squelettes partagé.
@MainActor
struct DAPrimitivesTests {
    @Test func whiteFillsAreNamedAndOrdered() {
        #expect(Palette.Fill.allCases.count == 6)
        let opacities = Palette.Fill.allCases.map(\.opacity)
        // Chaque rôle a une opacité propre, entre 0 et 1.
        #expect(Set(opacities).count == opacities.count)
        #expect(opacities.allSatisfy { $0 > 0 && $0 < 1 })
        // Le rôle « choisi » est le plus opaque ; « subtle » le plus discret.
        #expect(opacities.max() == Palette.Fill.selected.opacity)
        #expect(opacities.min() == Palette.Fill.subtle.opacity)
    }

    @Test func legacyFillsKeepTheirLook() {
        #expect(Palette.Fill.subtle.opacity == 0.05)
        #expect(Palette.Fill.chip.opacity == 0.10)
        #expect(Palette.Fill.selected.opacity == 0.92)
    }

    @Test func fieldRadiusIsTheInnerRadius() {
        #expect(Radius.field == Radius.inner)
        #expect(Radius.field == 22)
    }

    @Test func pillsHaveAFortyFourPointTouchArea() {
        #expect(PillButton<EmptyView>.touchHeight >= 44)
    }

    @Test func shimmerProgressStaysInUnitRangeAndRepeats() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        for step in 0..<20 {
            let date = start.addingTimeInterval(Double(step) * 0.37)
            let progress = ShimmerClock.progress(at: date)
            #expect(progress >= 0 && progress < 1)
        }
        let period = Motion.Duration.shimmer
        let later = start.addingTimeInterval(period * 3)
        #expect(abs(ShimmerClock.progress(at: start) - ShimmerClock.progress(at: later)) < 0.0001
            || abs(abs(ShimmerClock.progress(at: start) - ShimmerClock.progress(at: later)) - 1) < 0.0001)
    }

    /// Les deux formes de `SectionLabel` (avec et sans lien) se construisent et se mesurent.
    @Test func sectionLabelAcceptsATrailingLink() {
        let plain = UIHostingController(rootView: SectionLabel(text: "Duel").frame(width: 300))
        let linked = UIHostingController(rootView: SectionLabel(text: "À ne pas rater", dot: .red) {
            Text("Comment c'est calculé")
        }.frame(width: 300))
        #expect(plain.sizeThatFits(in: CGSize(width: 300, height: 200)).height > 0)
        #expect(linked.sizeThatFits(in: CGSize(width: 300, height: 200)).height > 0)
    }
}
