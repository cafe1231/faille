import Foundation
import LoLKit
import Testing
@testable import Faille

private let fr = Locale(identifier: "fr_FR")

/// Espaces insécables de la langue (U+00A0 ou U+202F selon la version d'ICU) ramenées à une espace simple.
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

struct SeasonFormatTests {
    @Test func numbersFollowTheSpecDisplayRules() {
        #expect(SeasonFormat.decimal(3.4285, locale: fr) == "3,4")
        #expect(SeasonFormat.integer(531.2, locale: fr) == "531")
        #expect(plain(SeasonFormat.percent(0.2278, locale: fr)) == "23 %")
        #expect(SeasonFormat.percent(nil, locale: fr) == "—")
        #expect(SeasonFormat.duration(seconds: 2031.036) == "33:51")
        #expect(SeasonFormat.duration(seconds: 3723) == "1:02:03")
        #expect(SeasonFormat.signed(228, locale: fr) == "+228")
        #expect(plain(SeasonFormat.signed(-1450, locale: fr)) == "\u{2212}1 450")
        #expect(SeasonFormat.signed(nil) == "—")
        #expect(SeasonFormat.record(9, 0) == "9-0")
        #expect(SeasonFormat.kda(kills: 4, deaths: 6, assists: 4) == "4/6/4")
        #expect(SeasonNames.role("bottom") == "ADC")
        #expect(SeasonNames.role(nil) == "Remplaçant")
    }
}
