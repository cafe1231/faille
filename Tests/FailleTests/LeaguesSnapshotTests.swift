import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Ligues (spec saison §3.5) : « Suivre la ligue » / « Suivre ses N équipes » (LEC non suivie), ligue suivie avec
    /// l'interrupteur des notifications (Mondial), section « Ligues » de l'onglet Matchs (prochain match, Classement).
    @Test func leagues() async throws {
        var data = PreviewData.withSeason
        let worlds = SampleData.leagues[0]
        data.follows = FollowList(teams: SampleData.follows.teams,
                                  leagues: [FollowedLeague(id: worlds.id, slug: worlds.slug, name: worlds.name, image: nil,
                                                           notifyStarts: true)])
        let store = AppStore(preview: data)
        let now = SampleData.date("2026-10-15T15:05:00Z")
        let view = NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LeagueFollowRow(league: SampleData.leagues[2], followed: false, notifies: false, teamCount: 2,
                                    allTeamsFollowed: false, onToggleFollow: {}, onFollowAll: {},
                                    onToggleNotifications: { _ in })
                    LeagueFollowRow(league: worlds, followed: true, notifies: true, teamCount: 11,
                                    allTeamsFollowed: false, onToggleFollow: {}, onFollowAll: {},
                                    onToggleNotifications: { _ in })
                    LeaguesSection(rows: LeaguesSection.rows(store: store, now: now))
                }
                .padding(16)
            }
            .abyssBackground()
        }
        .environment(store)
        .environment(\.seasonNow, now)
        let url = try await Snapshot.write(view, named: "31-ligues")
        expectNotBlank(url)
    }
}
