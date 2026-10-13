import Foundation
import Testing
@testable import LoLKit

@Suite struct ImageTests {
    @Test func fnvMatchesReferenceVectors() {
        #expect(LogoFileName.fnv1a64("") == 0xcbf2_9ce4_8422_2325)
        #expect(LogoFileName.fnv1a64("a") == 0xaf63_dc4c_8601_ec8c)
        #expect(LogoFileName.fnv1a64("foobar") == 0x8594_4171_f739_67e8)
    }

    @Test func logoNamesAreStableAndDistinct() {
        let kc = "http://static.lolesports.com/teams/1704714951336_KC.png"
        let name = LogoFileName.name(for: kc)
        #expect(name == LogoFileName.name(for: kc))
        #expect(name.hasPrefix("logo-") && name.hasSuffix(".png") && name.count == 25)
        #expect(name != LogoFileName.name(for: "http://static.lolesports.com/teams/G2-FullonDark.png"))
        #expect(LogoFileName.name(for: "") == "logo-cbf29ce484222325.png")
    }

    @Test func unpremultiplyRestoresChannels() {
        #expect(TeamColor.unpremultiplied([100, 50, 0, 128]) == [199, 100, 0, 128])
        #expect(TeamColor.unpremultiplied([0, 0, 0, 0, 10, 20, 30, 255]) == [0, 0, 0, 0, 10, 20, 30, 255])
        #expect(TeamColor.unpremultiplied([200, 0, 0, 100]) == [255, 0, 0, 100])
    }

    @Test func halfTransparentLogoKeepsItsColour() {
        let premultiplied = Array(repeating: [UInt8]([110, 10, 30, 128]), count: 50).flatMap { $0 }
        #expect(TeamColor.dominant(rgba: premultiplied) == RGB(r: 110, g: 10, b: 30))
        #expect(TeamColor.dominant(rgba: TeamColor.unpremultiplied(premultiplied)) == RGB(r: 219, g: 20, b: 60))
    }

    @Test func imageURLsBecomeHTTPS() {
        #expect(ImageURL.secure("http://static.lolesports.com/teams/KC.png")?.absoluteString
                == "https://static.lolesports.com/teams/KC.png")
        #expect(ImageURL.secure("https://static.lolesports.com/teams/team-tbd.png")?.absoluteString
                == "https://static.lolesports.com/teams/team-tbd.png")
        #expect(ImageURL.secure("//static.lolesports.com/a.png")?.absoluteString == "https://static.lolesports.com/a.png")
        #expect(ImageURL.secure(nil) == nil)
        #expect(ImageURL.secure("") == nil)
        #expect(ImageURL.secure("ftp://example.com/a.png") == nil)
    }
}
