import Foundation
import LoLKit
import Testing
@testable import Faille

private func event(_ id: String, _ start: String, state: EventState = .completed, teams: [String] = []) -> MatchEvent {
    MatchEvent(startTime: SampleData.date(start), state: state, type: "match", blockName: nil, league: SampleData.worlds,
               match: MatchInfo(id: id,
                                teams: teams.map { MatchTeam(id: $0, name: $0, code: $0, image: nil, result: nil) },
                                strategy: nil, games: nil),
               streams: nil)
}

/// Calendrier complet (spec saison §3.2) : matchs sans doublon, jeton de la page à lire.
struct CalendarEventsTests {
    private func page(_ events: [MatchEvent], older: String?, newer: String?) -> SchedulePageResult {
        SchedulePageResult(events: events, older: older, newer: newer)
    }

    @Test func liveWinsOverTheScheduleAndPagesAddOlderMatches() {
        let merged = CalendarEvents.merged(pages: [page([event("m-old", "2026-09-01T12:00:00Z"), SampleData.kcLive],
                                                        older: "o", newer: nil)],
                                           schedule: SampleData.schedule, live: SampleData.live)
        #expect(merged.first?.id == "m-old")
        #expect(merged.filter { $0.id == SampleData.kcMatchId }.count == 1)
        #expect(Set(merged.map(\.id)).count == merged.count)
    }

    @Test func tokensComeFromTheFarthestPageInEachDirection() {
        let pages = [page(SampleData.schedule, older: "o1", newer: nil),
                     page([event("e", "2026-08-01T12:00:00Z")], older: "o2", newer: "n2")]
        #expect(CalendarEvents.token(.older, pages: pages) == "o2")
        #expect(CalendarEvents.token(.newer, pages: pages) == nil)
        #expect(CalendarEvents.token(.older, pages: []) == nil)
    }
}

/// Anti-spoiler I-1 sur un `AppStore` d'aperçu (M15 : suite sérialisée).
@MainActor
@Suite(.serialized)
struct CalendarStoreTests {
    @Test func aMaskedUpcomingMatchLeavesNoMarkerInTheCalendar() {
        var data = PreviewData.withSeason
        data.schedule.append(event("m-t1-hle-soon", "2026-10-20T18:00:00Z", state: .unstarted, teams: ["t1", "hle"]))
        let store = AppStore(preview: data)
        #expect(store.maskedLatestTeamIds.contains("t1"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        calendar.firstWeekday = 2
        let events = store.withoutMaskedUpcoming(
            CalendarEvents.merged(pages: [], schedule: store.schedule, live: store.live))
        #expect(!events.contains { $0.id == "m-t1-hle-soon" })
        let days = CalendarMonth.days(events: events, month: SampleData.date("2026-10-15T12:00:00Z"),
                                      calendar: calendar,
                                      followed: HomeFeed.followedMatchIds(events, follows: store.follows),
                                      now: SampleData.date("2026-10-15T15:05:00Z"))
        #expect(!days.flatMap(\.matchIds).contains("m-t1-hle-soon"))
    }
}
