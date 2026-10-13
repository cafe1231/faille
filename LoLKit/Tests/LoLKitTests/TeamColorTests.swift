import Testing
@testable import LoLKit

/// Image de test : `count` pixels de chaque couleur RGBA.
private func pixels(_ runs: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8, count: Int)]) -> [UInt8] {
    runs.flatMap { run in Array(repeating: [run.r, run.g, run.b, run.a], count: run.count).flatMap { $0 } }
}

@Suite struct TeamColorTests {
    @Test func hexRoundTrip() {
        #expect(RGB(hex: "#5B8CFF") == RGB(r: 0x5B, g: 0x8C, b: 0xFF))
        #expect(RGB(hex: "ffb454") == RGB(r: 0xFF, g: 0xB4, b: 0x54))
        #expect(RGB(r: 0x0B, g: 0x10, b: 0x20).hex == "#0B1020")
        #expect(RGB(hex: "zz") == nil)
    }

    @Test func dominantOfPlainLogo() {
        #expect(TeamColor.dominant(rgba: pixels([(27, 63, 209, 255, 100)])) == RGB(r: 27, g: 63, b: 209))
    }

    @Test func whiteAndTransparentPixelsAreIgnored() {
        let logo = pixels([(255, 255, 255, 255, 80), (0, 0, 0, 0, 200), (220, 20, 60, 255, 20)])
        #expect(TeamColor.dominant(rgba: logo) == RGB(r: 220, g: 20, b: 60))
    }

    @Test func noColourMeansAccent() {
        #expect(TeamColor.dominant(rgba: pixels([(0, 0, 0, 0, 50)])) == nil)
        #expect(TeamColor.dominant(rgba: pixels([(255, 255, 255, 255, 50), (10, 10, 10, 255, 50)])) == nil)
        #expect(TeamColor.teamColor(rgba: pixels([(255, 255, 255, 255, 50)])) == .accent)
    }

    @Test func darkColoursAreLightenedButKeepTheirHue() {
        let navy = RGB(r: 27, g: 63, b: 209)
        let readable = TeamColor.readable(navy)
        #expect(navy.luminance < TeamColor.minLuminance)
        #expect(readable.luminance >= TeamColor.minLuminance)
        #expect(readable.b > readable.r && readable.b > readable.g)
    }

    @Test func brightColoursAreUnchanged() {
        let amber = RGB(r: 255, g: 180, b: 84)
        #expect(TeamColor.readable(amber) == amber)
    }
}
