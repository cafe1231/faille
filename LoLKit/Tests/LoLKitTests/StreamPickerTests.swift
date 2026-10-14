import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli doit pouvoir lire streams et rediffusions et choisir le lien.
import LoLKit

@Suite struct StreamPickerTests {
    /// Vrai `getLive` (13/10/2026, Demacia Cup) : un seul stream, AfreecaTV en coréen.
    @Test func decodesTheStreamsOfGetLive() async throws {
        let fake = FakeTransport()
        try await fake.on("getLive", fixture: "getLive")
        let event = try #require(try await LoLClient(transport: fake).live().first)
        let streams = try #require(event.streams)
        #expect(streams == [StreamInfo(statsStatus: "disabled", provider: "afreecatv", parameter: "aflol", locale: "ko-KR")])
        #expect(event.statsDisabled)

        let link = try #require(StreamPicker.preferred(streams))
        #expect(link == StreamLink(provider: "afreecatv", locale: "ko-KR",
                                   url: try #require(URL(string: "https://play.afreecatv.com/aflol"))))
        #expect(StreamPicker.others(streams).isEmpty)
    }

    /// Vrai `getEventDetails` (finale LCS terminée) : deux rediffusions YouTube par game jouée (en-US, es-MX).
    @Test func decodesTheVodsOfGetEventDetails() async throws {
        let fake = FakeTransport()
        try await fake.on("getEventDetails", fixture: "getEventDetails")
        let games = try await LoLClient(transport: fake).eventDetails(matchId: "115565004607949429").match.games
        #expect(games.map { $0.vods?.count } == [2, 2, 2, 2, 0])
        #expect(games[1].vods?.first == Vod(provider: "youtube", parameter: "8Mdtj9TMxWQ", locale: "en-US",
                                            startMillis: 2_646_000))
        #expect(games[1].vods?.last == Vod(provider: "youtube", parameter: "c_1_5yDlQZ0", locale: "es-MX",
                                           startMillis: nil))
    }

    @Test func replayLinksJumpToTheStartOfTheGame() async throws {
        let fake = FakeTransport()
        try await fake.on("getEventDetails", fixture: "getEventDetails")
        let games = try await LoLClient(transport: fake).eventDetails(matchId: "115565004607949429").match.games
        // Pas de fr-FR : l'anglais passe avant l'espagnol ; la game 1 commence au début de la vidéo (pas de `t`).
        #expect(StreamPicker.replay(games[0].vods ?? [])?.url.absoluteString
                == "https://www.youtube.com/watch?v=8Mdtj9TMxWQ")
        #expect(StreamPicker.replay(games[1].vods ?? [])?.url.absoluteString
                == "https://www.youtube.com/watch?v=8Mdtj9TMxWQ&t=2646s")
        #expect(StreamPicker.replay(games[3].vods ?? [])?.url.absoluteString
                == "https://www.youtube.com/watch?v=8Mdtj9TMxWQ&t=8632s")
        #expect(StreamPicker.replay(games[1].vods ?? [])?.locale == "en-US")
        // Game 5 non jouée : rien à revoir.
        #expect(StreamPicker.replay(games[4].vods ?? []) == nil)
    }

    @Test func replayPrefersFrenchAndIgnoresOtherProviders() {
        let vods = [
            Vod(provider: "youtube", parameter: "en", locale: "en-US", startMillis: 0),
            Vod(provider: "twitch", parameter: "123", locale: "fr-FR", startMillis: 0),
            Vod(provider: "youtube", parameter: "fr", locale: "fr-FR", startMillis: 1_500),
        ]
        #expect(StreamPicker.replay(vods)?.url.absoluteString == "https://www.youtube.com/watch?v=fr&t=1s")
        #expect(StreamPicker.replay([Vod(provider: "youtube", parameter: "es", locale: "es-MX", startMillis: nil)])?
            .url.absoluteString == "https://www.youtube.com/watch?v=es")
        #expect(StreamPicker.replay([Vod(provider: "youtube", parameter: nil, locale: "fr-FR", startMillis: 0)]) == nil)
    }

    @Test func prefersFrenchThenEnglishThenTheFirstStream() throws {
        let korean = StreamInfo(statsStatus: "enabled", provider: "afreecatv", parameter: "aflol", locale: "ko-KR")
        let english = StreamInfo(statsStatus: "enabled", provider: "youtube", parameter: "abc123", locale: "en-US")
        let french = StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR")

        #expect(StreamPicker.preferred([korean, english, french])?.url.absoluteString == "https://www.twitch.tv/otplol_")
        #expect(StreamPicker.preferred([korean, english])?.url.absoluteString
                == "https://www.youtube.com/watch?v=abc123")
        #expect(StreamPicker.preferred([korean])?.provider == "afreecatv")
        #expect(StreamPicker.preferred([]) == nil)
        // Menu de l'appui long : les autres, dans l'ordre de l'API.
        #expect(StreamPicker.others([korean, english, french]).map(\.locale) == ["ko-KR", "en-US"])
    }

    @Test func unknownProvidersAndEmptyParametersAreIgnored() {
        let huya = StreamInfo(statsStatus: "enabled", provider: "huya", parameter: "lpl", locale: "fr-FR")
        let empty = StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "", locale: "fr-FR")
        let missing = StreamInfo(statsStatus: "enabled")
        let english = StreamInfo(statsStatus: "enabled", provider: "Twitch", parameter: "riotgames", locale: "en-US")

        #expect(StreamPicker.links([huya, empty, missing, english]).map(\.url.absoluteString)
                == ["https://www.twitch.tv/riotgames"])
        #expect(StreamPicker.preferred([huya, empty, missing]) == nil)
        #expect(StreamPicker.url(provider: "huya", parameter: "lpl") == nil)
        #expect(StreamPicker.url(provider: "youtube", parameter: nil) == nil)
        // Deux entrées vers le même lien n'en font qu'une.
        #expect(StreamPicker.links([english, english]).count == 1)
    }

    @Test func oldCachedMatchesWithoutStreamFieldsStillDecode() throws {
        // Calendrier écrit sur disque par une version précédente : ni provider, ni vods.
        let json = #"{"statsStatus":"enabled"}"#
        let stream = try JSONDecoder().decode(StreamInfo.self, from: Data(json.utf8))
        #expect(stream == StreamInfo(statsStatus: "enabled"))
        let game = try JSONDecoder().decode(GameRef.self, from: Data(#"{"number":1,"id":"g1","state":"completed"}"#.utf8))
        #expect(game.vods == nil)
        // Champ d'un mauvais type : ignoré, pas d'échec.
        let odd = try JSONDecoder().decode(Vod.self, from: Data(#"{"parameter":"x","startMillis":"tard"}"#.utf8))
        #expect(odd == Vod(provider: nil, parameter: "x", locale: nil, startMillis: nil))
    }
}
