import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Icône de l'appli (spec finitions §1) : trois PNG de 1024 × 1024 px (claire, sombre, teintée) pour
    /// `AppIcon.appiconset`, et la planche `14-icone.png`.
    @Test func appIcon() throws {
        for variant in AppIconVariant.allCases {
            let url = try AppIconRender.write(variant)
            let bitmap = try #require(Bitmap(contentsOf: url), "PNG illisible : \(variant.fileName)")
            #expect(bitmap.width == 1024 && bitmap.height == 1024,
                    "\(variant.fileName) : \(bitmap.width) × \(bitmap.height) px")
            let corner = bitmap.pixel(x: 4, y: 4)
            // Dans la faille, un peu sous le milieu (sa partie la plus large).
            let rift = bitmap.pixel(x: 512, y: 530)
            let side = bitmap.pixel(x: 300, y: 700)
            switch variant {
            case .standard:
                #expect(corner.a == 255, "claire : opaque")
                #expect(Self.brightness(corner) < 120, "claire : coin abysse sombre")
                #expect(Self.brightness(rift) > 450, "claire : faille lumineuse")
            case .dark:
                #expect(corner.a == 0, "sombre : fond transparent")
                #expect(rift.a > 200, "sombre : faille opaque")
            case .tinted:
                #expect(corner.a == 255, "teintée : opaque")
                for pixel in [corner, rift, side] {
                    #expect(Self.isGray(pixel), "teintée : niveaux de gris")
                }
                #expect(Self.brightness(rift) > 450, "teintée : faille claire")
            }
        }
        expectNotBlank(try AppIconRender.writeBoard())
    }

    private static func brightness(_ pixel: Bitmap.Pixel) -> Int {
        Int(pixel.r) + Int(pixel.g) + Int(pixel.b)
    }

    private static func isGray(_ pixel: Bitmap.Pixel) -> Bool {
        abs(Int(pixel.r) - Int(pixel.g)) <= 2 && abs(Int(pixel.g) - Int(pixel.b)) <= 2
    }
}
