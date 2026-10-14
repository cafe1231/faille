import Foundation
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Octobre 2026 (spec saison §3.2) : pastilles des jours de matchs suivis, liste du 15 (KC – C9, T1 – FLY masqué :
    /// « En direct » sans score).
    @Test func calendarMonth() async throws {
        let view = NavigationStack { SeasonCalendarView() }
            .environment(AppStore(preview: .withSeason))
            .environment(\.seasonNow, SampleData.date("2026-10-15T15:05:00Z"))
        let url = try await Snapshot.write(view, named: "30-calendrier")
        expectNotBlank(url)
    }
}
