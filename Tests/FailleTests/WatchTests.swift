import Foundation
import LoLKit
import Testing
@testable import Faille

/// « Regarder » et « Revoir » (spec fonctionnalités §1) : quels liens l'appli montre, et jamais pour un match masqué.
struct WatchTests {
    private static let streams = [
        StreamInfo(statsStatus: "enabled", provider: "youtube", parameter: "lolesports", locale: "en-US"),
        StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR"),
        StreamInfo(statsStatus: "enabled", provider: "afreecatv", parameter: "aflol", locale: "ko-KR"),
        StreamInfo(statsStatus: "enabled", provider: "huya", parameter: "lpl", locale: "zh-CN"),
    ]

    @Test func liveMatchWatchesTheFrenchStreamAndOffersTheOthers() throws {
        let live = try #require(WatchLinks.live(Self.streams, inProgress: true, masked: false))
        #expect(live.preferred.url.absoluteString == "https://www.twitch.tv/otplol_")
        #expect(live.others.map(\.provider) == ["youtube", "afreecatv"]) // fournisseur inconnu : ignoré
    }

    /// Anti-spoiler : un match masqué n'a pas de « Regarder » (l'image du stream montre le score).
    @Test func maskedOrFinishedMatchHasNoWatchButton() {
        #expect(WatchLinks.live(Self.streams, inProgress: true, masked: true) == nil)
        #expect(WatchLinks.live(Self.streams, inProgress: false, masked: false) == nil)
        #expect(WatchLinks.live(nil, inProgress: true, masked: false) == nil)
        #expect(WatchLinks.live([StreamInfo(statsStatus: "enabled")], inProgress: true, masked: false) == nil)
    }

    @Test func replayOfAPlayedGameStartsAtTheGame() throws {
        let vods = [Vod(provider: "youtube", parameter: "abc123", locale: "en-US", startMillis: 95_000)]
        let game = GameRef(number: 2, id: "g2", state: .completed, teams: nil, vods: vods)
        let link = try #require(WatchLinks.replay(game, masked: false))
        #expect(link.url.absoluteString == "https://www.youtube.com/watch?v=abc123&t=95s")
        // Anti-spoiler : masqué, rien (le nombre de games trahirait la série) ; game pas jouée : rien.
        #expect(WatchLinks.replay(game, masked: true) == nil)
        let live = GameRef(number: 3, id: "g3", state: .inProgress, teams: nil, vods: vods)
        #expect(WatchLinks.replay(live, masked: false) == nil)
        let without = GameRef(number: 1, id: "g1", state: .completed, teams: nil)
        #expect(WatchLinks.replay(without, masked: false) == nil)
    }

    @Test func labelsNameTheLanguageAndThePlatform() throws {
        func link(_ provider: String, _ locale: String?) -> StreamLink {
            StreamLink(provider: provider, locale: locale, url: URL(string: "https://example.com")!)
        }
        #expect(WatchLinks.label(link("twitch", "fr-FR")) == "Français · Twitch")
        #expect(WatchLinks.label(link("youtube", "en-US")) == "Anglais · YouTube")
        #expect(WatchLinks.label(link("afreecatv", "ko-KR")) == "Coréen · AfreecaTV")
        #expect(WatchLinks.label(link("twitch", "xx-XX")) == "xx-XX · Twitch")
        #expect(WatchLinks.label(link("youtube", nil)) == "YouTube")
    }
}
