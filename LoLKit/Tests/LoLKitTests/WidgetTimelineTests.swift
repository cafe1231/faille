import Foundation
import Testing
@testable import LoLKit

/// Planning des widgets (spec §7) : quelles entrées, à quelles dates, et jamais de spoiler (spec §8).
@Suite struct WidgetTimelineTests {
    /// KC et GEN suivies ; T1 suivie en anti-spoiler. Forme `getSchedule` : sans id, les équipes se reconnaissent à leur nom.
    private let follows = FollowList(teams: [
        FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", autoColorHex: "#5B8CFF"),
        FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true, autoColorHex: "#FF5C7A"),
        FollowedTeam(id: "gen", code: "GEN", name: "Gen.G", autoColorHex: "#FFB454"),
    ])

    private func match(_ id: String, _ state: EventState, _ start: String, _ a: String, _ b: String,
                       wins: [Int] = [0, 0]) -> MatchEvent {
        let names = ["KC": "Karmine Corp", "T1": "T1", "GEN": "Gen.G"]
        return makeEvent(id: id, state: state, start: start,
                         teams: [makeTeam(a, name: names[a], wins: wins[0]), makeTeam(b, name: names[b], wins: wins[1])])
    }

    /// Fichiers de l'appli : calendrier (et direct, s'il est donné) relus à `fetchedAt`.
    private func input(_ schedule: [MatchEvent], fetchedAt: String, live: [MatchEvent]? = nil,
                       revealed: Set<String> = []) -> WidgetInput {
        WidgetInput(
            follows: follows,
            settings: AppSettings(revealedMatchIds: revealed),
            schedule: Cached(value: SchedulePage(leagueIds: [], events: schedule), fetchedAt: date(fetchedAt)),
            live: live.map { Cached(value: $0, fetchedAt: date(fetchedAt)) }
        )
    }

    /// Heures du 15 octobre 2026 (UTC) : `times(["12:00:00"])`.
    private func times(_ values: [String]) -> [Date] {
        values.map { date("2026-10-15T\($0)Z") }
    }

    private var kcG2: MatchEvent { match("kc-g2", .unstarted, "2026-10-15T18:00:00Z", "KC", "G2") }
    private var genFur: MatchEvent { match("gen-fur", .unstarted, "2026-10-16T09:00:00Z", "GEN", "FUR") }
    /// En cours, C9 à gauche dans l'API : KC mène 1 – 0, game 2.
    private var kcC9: MatchEvent { match("kc-c9", .inProgress, "2026-10-15T16:00:00Z", "C9", "KC", wins: [0, 1]) }
    /// En cours et masqué (T1 en anti-spoiler).
    private var t1Fly: MatchEvent { match("t1-fly", .inProgress, "2026-10-15T17:00:00Z", "T1", "FLY", wins: [1, 0]) }
    private var t1Gen: MatchEvent { match("t1-gen", .unstarted, "2026-10-17T12:00:00Z", "T1", "GEN") }

    // MARK: Contenu à une date

    @Test func upcomingMatchesAreListedByStartTime() throws {
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([genFur, kcG2], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.map(\.matchId) == ["kc-g2", "gen-fur"])
        let first = try #require(content.headline)
        #expect(first.status == .upcoming(date("2026-10-15T18:00:00Z")))
        #expect(first.codes == ["KC", "G2"])
        #expect(first.colorHexes == ["#5B8CFF", nil])
        #expect(!first.isMasked)
        #expect(content.team(id: "gen")?.next == .match(content.lines[1]))
        #expect(content.team(id: "t1")?.next == .noMatch)
    }

    @Test func liveMatchComesFirstWithItsScoreInDisplayOrder() throws {
        let content = WidgetTimeline.content(at: date("2026-10-15T16:15:00Z"),
                                             input: input([kcC9, genFur], fetchedAt: "2026-10-15T16:10:00Z", live: [kcC9]))
        #expect(content.lines.map(\.matchId) == ["kc-c9", "gen-fur"])
        let live = try #require(content.headline)
        #expect(live.status == .live(score: [1, 0], gameNumber: 2))
        #expect(live.codes == ["KC", "C9"])
        #expect(content.team(id: "kc")?.next == .live(live))
    }

    @Test func maskedLiveMatchShowsNeitherScoreNorGameAndHidesTheNextMatch() throws {
        let content = WidgetTimeline.content(
            at: date("2026-10-15T17:05:00Z"),
            input: input([t1Fly, genFur, t1Gen], fetchedAt: "2026-10-15T17:00:00Z", live: [t1Fly]))
        let masked = try #require(content.headline)
        #expect(masked.matchId == "t1-fly")
        #expect(masked.status == .live(score: nil, gameNumber: nil))
        #expect(masked.isMasked)
        #expect(content.team(id: "t1")?.next == .live(masked))
        // « T1 vs GEN » n'est annoncé nulle part : le match en direct de T1 est masqué.
        #expect(content.lines.map(\.matchId) == ["t1-fly", "gen-fur"])
    }

    @Test func aMatchWhoseStartHasPassedIsNoLongerUpcoming() {
        let content = WidgetTimeline.content(at: date("2026-10-15T18:00:00Z"),
                                             input: input([kcG2, genFur], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.map(\.matchId) == ["gen-fur"])
        #expect(content.team(id: "kc")?.next == .noMatch)
    }

    @Test func liveDataOlderThanTenMinutesIsNotTrusted() {
        let input = input([kcC9, genFur], fetchedAt: "2026-10-15T16:10:00Z", live: [kcC9])
        #expect(WidgetTimeline.content(at: date("2026-10-15T16:20:00Z"), input: input).headline?.matchId == "kc-c9")
        let later = WidgetTimeline.content(at: date("2026-10-15T16:20:01Z"), input: input)
        #expect(later.lines.map(\.matchId) == ["gen-fur"])
        #expect(later.team(id: "kc")?.next == .noMatch)
    }

    @Test func aFreshScheduleStandsInForAMissingLive() {
        let input = input([kcC9, genFur], fetchedAt: "2026-10-15T16:10:00Z")   // pas de cache du direct
        #expect(WidgetTimeline.content(at: date("2026-10-15T16:15:00Z"), input: input).headline?.status
                == .live(score: [1, 0], gameNumber: 2))
        #expect(WidgetTimeline.content(at: date("2026-10-15T16:25:00Z"), input: input).headline?.matchId == "gen-fur")
    }

    /// Le calendrier date du match T1 – FLY (masqué) ; le lendemain, rien ne dit qu'il est fini : la ligne « Prochain »
    /// de T1 reste masquée (règle F1), et « T1 vs GEN » n'est pas annoncé.
    @Test func aMaskedMatchPresumedOverKeepsTheNextLineHidden() {
        let content = WidgetTimeline.content(at: date("2026-10-16T05:00:00Z"),
                                             input: input([t1Fly, genFur, t1Gen], fetchedAt: "2026-10-15T17:05:00Z"))
        #expect(content.team(id: "t1")?.next == .hidden)
        #expect(content.lines.map(\.matchId) == ["gen-fur"])
    }

    @Test func revealingTheMaskedMatchBringsTheNextMatchBack() throws {
        let content = WidgetTimeline.content(
            at: date("2026-10-16T05:00:00Z"),
            input: input([t1Fly, genFur, t1Gen], fetchedAt: "2026-10-15T17:05:00Z", revealed: ["t1-fly"]))
        #expect(content.lines.map(\.matchId) == ["gen-fur", "t1-gen"])
        let next = try #require(content.lines.last)
        #expect(next.codes == ["T1", "GEN"])
        #expect(next.isMasked)   // T1 reste en anti-spoiler : à venir, rien à cacher
        #expect(content.team(id: "t1")?.next == .match(next))
    }

    @Test func aMatchBetweenTwoFollowedTeamsIsListedOnce() throws {
        let kcGen = match("kc-gen", .unstarted, "2026-10-15T18:00:00Z", "GEN", "KC")
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([kcGen], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.count == 1)
        let line = try #require(content.headline)
        #expect(line.codes == ["KC", "GEN"])                 // carte de KC (suivie avant GEN)
        #expect(line.colorHexes == ["#5B8CFF", "#FFB454"])
        guard case let .match(genLine)? = content.team(id: "gen")?.next else {
            Issue.record("GEN n'annonce pas son prochain match")
            return
        }
        #expect(genLine.codes == ["GEN", "KC"])              // le petit widget de GEN met GEN à gauche
    }

    /// Décision du contrôleur : « GEN vs T1 » n'est annoncé nulle part tant que ce match n'est pas révélé.
    @Test func aNextMatchAgainstASpoilerFreeTeamIsNotAnnounced() {
        let t1Last = match("t1-fly-done", .completed, "2026-10-14T17:00:00Z", "T1", "FLY", wins: [3, 1])
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([t1Last, t1Gen], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.team(id: "gen")?.next == .hidden)
        #expect(content.team(id: "t1")?.next == .hidden)
        #expect(!content.lines.contains { $0.matchId == "t1-gen" })
    }

    @Test func smallWidgetDefaultsToTheFirstFollowedTeam() {
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.teams.map(\.team.id) == ["kc", "t1", "gen"])
        #expect(content.team(id: nil)?.team.id == "kc")
        #expect(content.team(id: "gen")?.team.id == "gen")
        #expect(content.team(id: "plus-suivie")?.team.id == "kc")
        #expect(WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"), input: WidgetInput()).team(id: nil) == nil)
    }

    // MARK: Dates des entrées et rechargement

    @Test func entriesAtTheStartAndAtEachCountdownStep() {
        let kc = match("kc-g2", .unstarted, "2026-10-15T14:00:00Z", "KC", "G2")
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T12:00:00Z"),
                                              input: input([kc], fetchedAt: "2026-10-15T11:30:00Z"))
        #expect(dates == times(["12:00:00", "13:00:00", "13:05:00", "13:10:00", "13:15:00", "13:20:00", "13:25:00",
                                "13:30:00", "13:35:00", "13:40:00", "13:45:00", "13:50:00", "13:55:00", "14:00:00"]))
    }

    @Test func aFarMatchOnlyAddsItsHourlyStepsWithinTheHorizon() {
        // GEN vs FUR est 21 h plus tard : seules ses heures pleines tombent dans les 6 h couvertes.
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T12:00:00Z"),
                                              input: input([genFur], fetchedAt: "2026-10-15T11:30:00Z"))
        #expect(dates == times(["12:00:00", "13:00:00", "14:00:00", "15:00:00", "16:00:00", "17:00:00", "18:00:00"]))
    }

    @Test func theEndOfLiveTrustIsAnEntry() {
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T16:15:00Z"),
                                              input: input([kcC9], fetchedAt: "2026-10-15T16:10:00Z", live: [kcC9]))
        #expect(dates == times(["16:15:00", "16:20:01"]))
    }

    @Test func reloadAtTheNextStartOrWithinThirtyMinutes() {
        let now = date("2026-10-15T12:00:00Z")
        let later = match("kc-g2", .unstarted, "2026-10-15T14:00:00Z", "KC", "G2")
        let soon = match("kc-g2", .unstarted, "2026-10-15T12:10:00Z", "KC", "G2")
        let others = makeEvent(id: "g2-fnc", state: .unstarted, start: "2026-10-15T12:05:00Z",
                               teams: [makeTeam("G2"), makeTeam("FNC")])
        #expect(WidgetTimeline.reloadDate(now: now, input: input([later], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:30:00Z"))
        #expect(WidgetTimeline.reloadDate(now: now, input: input([soon], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:10:00Z"))
        #expect(WidgetTimeline.reloadDate(now: now, input: input([], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:30:00Z"))
        // Un match d'équipes non suivies ne compte pas.
        #expect(WidgetTimeline.reloadDate(now: now, input: input([others], fetchedAt: "2026-10-15T11:00:00Z"))
                == date("2026-10-15T12:30:00Z"))
    }

    // MARK: Anti-spoiler sur tout le planning

    @Test func noEntryEverShowsAMaskedScoreOrTheNextMatchOfAMaskedTeam() {
        let input = input([t1Fly, genFur, t1Gen, kcC9], fetchedAt: "2026-10-15T17:00:00Z", live: [t1Fly, kcC9])
        let dates = WidgetTimeline.entryDates(now: date("2026-10-15T17:05:00Z"), input: input)
        #expect(dates.count > 2)
        for entry in dates {
            let content = WidgetTimeline.content(at: entry, input: input)
            for line in content.lines where line.isMasked {
                if case let .live(score, game) = line.status {
                    #expect(score == nil && game == nil)
                }
            }
            switch content.team(id: "t1")?.next {
            case let .live(line)?:
                #expect(line.isMasked && line.status == .live(score: nil, gameNumber: nil))
            case .hidden?:
                break
            default:
                Issue.record("T1 annonce autre chose que « En direct » masqué ou « Prochain · masqué » à \(entry)")
            }
        }
    }
}
