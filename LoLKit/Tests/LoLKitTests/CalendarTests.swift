import Foundation
import Testing
@testable import LoLKit

/// Calendrier pur (spec saison §2.2 n° 3, §3.2) : vue mois, bandeau de 7 jours, pastilles, page à lire.
@Suite struct CalendarTests {
    /// C9 vs KC, Mondial, 15/10 18:00 UTC (fixture `getSchedule`).
    private static let c9kc = "115660588583171786"
    /// FUR vs MVK, 15/10 23:00 UTC = 16/10 01:00 à Paris.
    private static let furMvk = "115660588583040710"
    private static let tbd = "115660588583171790"
    private static let kcG2 = "115548681803406303"

    private func schedule() async throws -> [MatchEvent] {
        let fake = FakeTransport()
        try await fake.on("getSchedule", fixture: "getSchedule")
        return try await LoLClient(transport: fake).schedule(leagueIds: [])
    }

    /// Calendrier de l'appareil en France : lundi en premier, heure de Paris.
    private var paris: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.firstWeekday = 2
        return calendar
    }

    @Test func monthGridStartsOnTheFirstWeekday() async throws {
        let events = try await schedule()
        let now = date("2026-10-15T10:00:00Z")
        let days = CalendarMonth.days(events: events, month: date("2026-10-10T12:00:00Z"), calendar: paris,
                                      followed: [Self.c9kc], now: now)
        // Octobre 2026 : du lundi 28/09 au dimanche 01/11 (5 semaines).
        #expect(days.count == 35)
        #expect(days.first?.date == date("2026-09-27T22:00:00Z"))
        #expect(days.first?.dayNumber == 28)
        #expect(days.first?.isInMonth == false)
        #expect(days.last?.dayNumber == 1)
        #expect(days.last?.isInMonth == false)
        #expect(days.filter(\.isInMonth).count == 31)
        #expect(days.filter(\.isToday).map(\.dayNumber) == [15])

        let fifteenth = try #require(days.first { $0.isInMonth && $0.dayNumber == 15 })
        #expect(fifteenth.marker == .followed)
        #expect(fifteenth.matchIds == [Self.c9kc])
        // 23:00 UTC le 15 = 01:00 le 16 à Paris : le match passe au 16, avec celui du soir.
        let sixteenth = try #require(days.first { $0.isInMonth && $0.dayNumber == 16 })
        #expect(sixteenth.matchIds == [Self.furMvk, Self.tbd])
        #expect(sixteenth.marker == .international)
        #expect(days.filter { $0.marker != .none }.count == 2)
    }

    @Test func septemberAndAnotherFirstWeekday() async throws {
        let events = try await schedule()
        let now = date("2026-10-15T10:00:00Z")
        let september = CalendarMonth.days(events: events, month: date("2026-09-15T12:00:00Z"), calendar: paris,
                                           followed: [], now: now)
        // Du lundi 31/08 au dimanche 04/10.
        #expect(september.count == 35)
        #expect(september.first?.dayNumber == 31)
        // Une ligue non suivie et non internationale (LEC) : pas de pastille, mais le match est dans la liste du jour.
        let sixth = try #require(september.first { $0.isInMonth && $0.dayNumber == 6 })
        #expect(sixth.marker == .none)
        #expect(sixth.matchIds == [Self.kcG2])
        #expect(CalendarMonth.days(events: events, month: date("2026-09-15T12:00:00Z"), calendar: paris,
                                   followed: [Self.kcG2], now: now)
                    .first { $0.isInMonth && $0.dayNumber == 6 }?.marker == .followed)

        var sunday = paris
        sunday.firstWeekday = 1
        let october = CalendarMonth.days(events: events, month: date("2026-10-10T12:00:00Z"), calendar: sunday,
                                         followed: [], now: now)
        // Du dimanche 27/09 au samedi 31/10.
        #expect(october.count == 35)
        #expect(october.first?.dayNumber == 27)
        #expect(october.last?.dayNumber == 31)
    }

    @Test func eventsOfADayInStartOrder() async throws {
        let events = try await schedule()
        #expect(CalendarMonth.events(on: date("2026-10-16T10:00:00Z"), in: events, calendar: paris).map(\.id)
                == [Self.furMvk, Self.tbd])
        #expect(CalendarMonth.events(on: date("2026-10-17T10:00:00Z"), in: events, calendar: paris).isEmpty)
    }

    /// Mois hors du calendrier en cache (06/09 → 16/10) : page `older` ou `newer` à lire.
    @Test func pageNeededOutsideTheCachedSchedule() async throws {
        let events = try await schedule()
        #expect(CalendarMonth.pageNeeded(for: date("2026-08-15T12:00:00Z"), events: events, calendar: paris) == .older)
        #expect(CalendarMonth.pageNeeded(for: date("2026-09-15T12:00:00Z"), events: events, calendar: paris) == .older)
        #expect(CalendarMonth.pageNeeded(for: date("2026-11-15T12:00:00Z"), events: events, calendar: paris) == .newer)
        #expect(CalendarMonth.pageNeeded(for: date("2026-10-15T12:00:00Z"), events: events, calendar: paris) == .newer)
        let october = events.filter { $0.startTime >= date("2026-10-01T00:00:00Z") }
            + [makeEvent(id: "first", state: .completed, start: "2026-09-30T22:00:00Z", teams: []),
               makeEvent(id: "last", state: .unstarted, start: "2026-10-31T20:00:00Z", teams: [])]
        #expect(CalendarMonth.pageNeeded(for: date("2026-10-15T12:00:00Z"), events: october, calendar: paris) == nil)
        #expect(CalendarMonth.pageNeeded(for: date("2026-10-15T12:00:00Z"), events: [], calendar: paris) == nil)
    }

    /// Bandeau de l'Accueil : la veille, aujourd'hui, les 5 jours suivants ; défilement sur ± 3 semaines.
    @Test func weekStripAroundToday() async throws {
        let events = try await schedule()
        let today = date("2026-10-15T10:00:00Z")
        let strip = WeekStrip.days(today: today, events: events, calendar: paris, followed: [Self.c9kc])
        #expect(strip.map(\.dayNumber) == [14, 15, 16, 17, 18, 19, 20])
        #expect(strip.map(\.isToday) == [false, true, false, false, false, false, false])
        #expect(strip.map(\.marker) == [.none, .followed, .international, .none, .none, .none, .none])
        #expect(strip.allSatisfy { $0.isInMonth })
        let scroll = WeekStrip.scrollRange(today: today, events: events, calendar: paris, followed: [])
        #expect(scroll.count == 43)
        #expect(scroll.first?.date == date("2026-09-23T22:00:00Z"))
        #expect(scroll.filter(\.isToday).count == 1)
    }
}
