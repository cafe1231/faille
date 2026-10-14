import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// « Regarder » et « Revoir » (spec fonctionnalités §1) : pastille de la carte, bouton du Détail, rediffusions.
    @Test func watchBoard() async throws {
        let streams = [
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "riotgames", locale: "en-US"),
            StreamInfo(statsStatus: "enabled", provider: "twitch", parameter: "otplol_", locale: "fr-FR"),
        ]
        let live = try #require(WatchLinks.live(streams, inProgress: true, masked: false))
        let alone = try #require(WatchLinks.live([streams[1]], inProgress: true, masked: false))
        let vod = [Vod(provider: "youtube", parameter: "abc123", locale: "en-US", startMillis: 95_000)]
        let replay = try #require(WatchLinks.replay(GameRef(number: 2, id: "g2", state: .completed, teams: nil, vods: vod),
                                                    masked: false))
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Regarder", subtitle: "Stream en direct · rediffusions")
                SectionLabel(text: "Carte en direct")
                VStack(alignment: .leading, spacing: 8) {
                    Text("KC 1 – 0 C9").font(Typo.headline)
                    WatchButton(live: live, compact: true)
                }
                .foregroundStyle(Palette.text)
                .glassCard(tint: Palette.team("#5B8CFF"))
                SectionLabel(text: "Détail en direct")
                WatchButton(live: live)
                WatchButton(live: alone)
                SectionLabel(text: "Détail terminé")
                ReplayButton(gameNumber: 2, link: replay)
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "16-regarder")
        expectNotBlank(url)
    }
}
