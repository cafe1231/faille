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

    /// Fichiers de l'appli : calendrier relu à `fetchedAt`, et direct (s'il est donné) relu à `liveFetchedAt`
    /// (par défaut au même instant).
    private func input(_ schedule: [MatchEvent], fetchedAt: String, live: [MatchEvent]? = nil,
                       liveFetchedAt: String? = nil, revealed: Set<String> = []) -> WidgetInput {
        WidgetInput(
            follows: follows,
            settings: AppSettings(revealedMatchIds: revealed),
            schedule: Cached(value: SchedulePage(leagueIds: [], events: schedule), fetchedAt: date(fetchedAt)),
            live: live.map { Cached(value: $0, fetchedAt: date(liveFetchedAt ?? fetchedAt)) }
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

    // MARK: Match en retard (W1)

    /// Tant qu'une donnée fraîche existe (direct ou calendrier de moins de 10 min), un match dont l'heure prévue est
    /// passée reste « à venir », comme sur la carte de l'appli : rien ne dit qu'il a commencé.
    @Test func aLateMatchStaysUpcomingWhileTheDataIsFresh() throws {
        let fresh = input([kcG2, genFur], fetchedAt: "2026-10-15T17:58:00Z")   // calendrier seul, 5 min à 18:03
        let late = WidgetTimeline.content(at: date("2026-10-15T18:03:00Z"), input: fresh)
        #expect(late.lines.map(\.matchId) == ["kc-g2", "gen-fur"])
        let line = try #require(late.headline)
        #expect(line.status == .upcoming(date("2026-10-15T18:00:00Z")))
        #expect(late.team(id: "kc")?.next == .match(line))
        // Un direct frais qui ne le cite pas ne change rien (le calendrier, lui, peut être plus ancien).
        let withLive = input([kcG2, genFur], fetchedAt: "2026-10-15T17:00:00Z", live: [], liveFetchedAt: "2026-10-15T17:58:00Z")
        let lateWithLive = WidgetTimeline.content(at: date("2026-10-15T18:03:00Z"), input: withLive)
        #expect(lateWithLive.lines.map(\.matchId) == ["kc-g2", "gen-fur"])
        #expect(lateWithLive.team(id: "kc")?.next == .match(try #require(lateWithLive.headline)))
    }

    /// Passé `liveTrust` sans rien de fiable, le match en retard est présumé commencé : ni en direct ni à venir.
    @Test func aLateMatchIsPresumedStartedOnlyOnceNothingIsTrustworthy() {
        let input = input([kcG2, genFur], fetchedAt: "2026-10-15T17:58:00Z", live: [])
        // 600 s : la donnée fait encore foi.
        #expect(WidgetTimeline.content(at: date("2026-10-15T18:08:00Z"), input: input).lines.map(\.matchId)
                == ["kc-g2", "gen-fur"])
        // 601 s : plus rien de fiable.
        let later = WidgetTimeline.content(at: date("2026-10-15T18:08:01Z"), input: input)
        #expect(later.lines.map(\.matchId) == ["gen-fur"])
        #expect(later.team(id: "kc")?.next == .noMatch)
        // Un calendrier seul se périme de la même façon.
        let scheduleOnly = self.input([kcG2, genFur], fetchedAt: "2026-10-15T17:58:00Z")
        #expect(WidgetTimeline.content(at: date("2026-10-15T18:08:00Z"), input: scheduleOnly).lines.count == 2)
        #expect(WidgetTimeline.content(at: date("2026-10-15T18:08:01Z"), input: scheduleOnly).lines.map(\.matchId)
                == ["gen-fur"])
    }

    /// Règle F1 inchangée : T1 (anti-spoiler) dont le match en retard est présumé commencé passe à « Prochain · masqué ».
    @Test func aMaskedTeamsLateMatchBecomesHiddenOnceItIsPresumedStarted() throws {
        let t1Late = match("t1-late", .unstarted, "2026-10-15T18:00:00Z", "T1", "FLY")
        let input = input([t1Late, genFur, t1Gen], fetchedAt: "2026-10-15T17:58:00Z", live: [])
        let fresh = WidgetTimeline.content(at: date("2026-10-15T18:03:00Z"), input: input)
        let line = try #require(fresh.team(id: "t1")?.next)
        guard case let .match(shown) = line else {
            Issue.record("T1 devrait encore annoncer son match en retard : \(line)")
            return
        }
        #expect(shown.matchId == "t1-late" && shown.isMasked && shown.status == .upcoming(date("2026-10-15T18:00:00Z")))
        let stale = WidgetTimeline.content(at: date("2026-10-15T18:08:01Z"), input: input)
        #expect(stale.team(id: "t1")?.next == .hidden)
        #expect(stale.lines.map(\.matchId) == ["gen-fur"])
    }

    /// Le calendrier se trompe de camp, pas le direct : `unstarted` dans le calendrier, `inProgress` dans `getLive` (frais).
    @Test func liveDataOverridesAnUnstartedScheduleEntry() throws {
        let scheduled = match("kc-c9", .unstarted, "2026-10-15T16:00:00Z", "C9", "KC")
        let content = WidgetTimeline.content(
            at: date("2026-10-15T16:15:00Z"),
            input: input([scheduled, genFur], fetchedAt: "2026-10-15T15:30:00Z", live: [kcC9], liveFetchedAt: "2026-10-15T16:10:00Z"))
        #expect(content.lines.map(\.matchId) == ["kc-c9", "gen-fur"])
        let live = try #require(content.headline)
        #expect(live.status == .live(score: [1, 0], gameNumber: 2))
        #expect(content.team(id: "kc")?.next == .live(live))
    }

    /// Le calendrier dit « en cours » et le direct (frais) ne cite pas le match : il est fini.
    @Test func aFreshLiveThatDropsAnInProgressMatchEndsIt() {
        let content = WidgetTimeline.content(
            at: date("2026-10-15T16:15:00Z"),
            input: input([kcC9, genFur], fetchedAt: "2026-10-15T16:05:00Z", live: [], liveFetchedAt: "2026-10-15T16:12:00Z"))
        #expect(content.lines.map(\.matchId) == ["gen-fur"])
        #expect(content.team(id: "kc")?.next == .noMatch)
    }

    /// Deux équipes suivies dans le même match en direct : une seule ligne, chaque équipe le voit de son côté.
    @Test func twoFollowedTeamsInTheSameLiveMatchShareOneLine() throws {
        let kcGen = match("kc-gen", .inProgress, "2026-10-15T16:00:00Z", "GEN", "KC", wins: [0, 2])
        let content = WidgetTimeline.content(at: date("2026-10-15T16:15:00Z"),
                                             input: input([kcGen], fetchedAt: "2026-10-15T16:10:00Z", live: [kcGen]))
        #expect(content.lines.count == 1)
        let kcLine = try #require(content.headline)
        #expect(kcLine.codes == ["KC", "GEN"] && kcLine.status == .live(score: [2, 0], gameNumber: 3))   // carte de KC (suivie avant GEN)
        #expect(content.team(id: "kc")?.next == .live(kcLine))
        guard case let .live(genLine)? = content.team(id: "gen")?.next else {
            Issue.record("GEN n'est pas donnée en direct")
            return
        }
        #expect(genLine.codes == ["GEN", "KC"] && genLine.status == .live(score: [0, 2], gameNumber: 3))   // le petit widget de GEN met GEN à gauche
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

    /// Règle C : « GEN vs T1 » n'est annoncé nulle part tant que le dernier match de T1 (masqué) n'est pas révélé.
    @Test func aNextMatchAgainstASpoilerFreeTeamIsNotAnnounced() {
        let t1Last = match("t1-fly-done", .completed, "2026-10-14T17:00:00Z", "T1", "FLY", wins: [3, 1])
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([t1Last, t1Gen], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.team(id: "gen")?.next == .hidden)
        #expect(content.team(id: "t1")?.next == .hidden)
        #expect(!content.lines.contains { $0.matchId == "t1-gen" })
    }

    /// Règle C affinée (W5) : T1 est en anti-spoiler mais n'a aucun dernier match masqué, « GEN vs T1 » ne trahit rien.
    @Test func aNextMatchAgainstASpoilerFreeTeamWithNothingMaskedIsAnnounced() throws {
        let content = WidgetTimeline.content(at: date("2026-10-15T12:00:00Z"),
                                             input: input([t1Gen], fetchedAt: "2026-10-15T11:00:00Z"))
        #expect(content.lines.map(\.matchId) == ["t1-gen"])
        let line = try #require(content.headline)
        #expect(line.codes == ["T1", "GEN"] && line.isMasked)   // carte de T1 (suivie avant GEN)
        #expect(content.team(id: "t1")?.next == .match(line))
        guard case let .match(genLine)? = content.team(id: "gen")?.next else {
            Issue.record("GEN devrait annoncer son match contre T1")
            return
        }
        #expect(genLine.matchId == "t1-gen" && genLine.codes == ["GEN", "T1"])
    }

    /// Révéler le dernier match masqué de T1 lève la règle C : GEN annonce de nouveau « GEN vs T1 ».
    @Test func revealingTheSpoilerFreeTeamsLastMatchAnnouncesTheNextMatchAgain() {
        let t1Last = match("t1-fly-done", .completed, "2026-10-14T17:00:00Z", "T1", "FLY", wins: [3, 1])
        let content = WidgetTimeline.content(
            at: date("2026-10-15T12:00:00Z"),
            input: input([t1Last, t1Gen], fetchedAt: "2026-10-15T11:00:00Z", revealed: ["t1-fly-done"]))
        #expect(content.lines.map(\.matchId) == ["t1-gen"])
        guard case let .match(genLine)? = content.team(id: "gen")?.next else {
            Issue.record("GEN devrait de nouveau annoncer son match contre T1")
            return
        }
        #expect(genLine.matchId == "t1-gen" && genLine.codes == ["GEN", "T1"])
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

    /// Le calendrier et le direct ont chacun leur fin de confiance : deux entrées quand ils datent de deux instants.
    @Test func theEndsOfLiveAndScheduleTrustAreBothEntries() {
        let both = input([kcC9], fetchedAt: "2026-10-15T16:00:00Z", live: [kcC9], liveFetchedAt: "2026-10-15T16:10:00Z")
        #expect(WidgetTimeline.entryDates(now: date("2026-10-15T16:05:00Z"), input: both)
                == times(["16:05:00", "16:10:01", "16:20:01"]))
    }

    /// Sans cache du direct, la fin de confiance du calendrier est la date où le match en cours cesse d'être en direct.
    @Test func theEndOfScheduleTrustIsAnEntryAndEndsTheLiveMatch() {
        let input = input([kcC9], fetchedAt: "2026-10-15T16:10:00Z")   // calendrier seul
        let now = date("2026-10-15T16:15:00Z")
        let dates = WidgetTimeline.entryDates(now: now, input: input)
        #expect(dates == times(["16:15:00", "16:20:01"]))
        #expect(WidgetTimeline.content(at: dates[0], input: input).headline?.matchId == "kc-c9")
        #expect(WidgetTimeline.content(at: dates[1], input: input).headline == nil)
    }

    /// Les heures pleines du compte à rebours suivent `Format.countdown`, qui compte en heures jusqu'à 48 h puis en jours :
    /// un palier à 47 h, aucun à 48 h.
    @Test func hourlyStepsStopWhereTheCountdownCountsInDays() {
        let now = date("2026-10-15T12:00:00Z")
        let at47h30 = match("kc-g2", .unstarted, "2026-10-17T11:30:00Z", "KC", "G2")
        #expect(WidgetTimeline.entryDates(now: now, input: input([at47h30], fetchedAt: "2026-10-15T11:00:00Z"))
                == times(["12:00:00", "12:30:00", "13:30:00", "14:30:00", "15:30:00", "16:30:00", "17:30:00"]))
        // À 48 h 30, « 48 h » s'écrirait déjà « 2 j » : le premier palier est celui de 47 h (13:30).
        let at48h30 = match("kc-g2", .unstarted, "2026-10-17T12:30:00Z", "KC", "G2")
        #expect(WidgetTimeline.entryDates(now: now, input: input([at48h30], fetchedAt: "2026-10-15T11:00:00Z"))
                == times(["12:00:00", "13:30:00", "14:30:00", "15:30:00", "16:30:00", "17:30:00"]))
    }

    /// W9, budget de rechargement de WidgetKit : les entrées couvrent déjà 6 h et chaque début de match, et l'appli
    /// recharge les widgets à chaque écriture ; l'extension ne se recharge donc qu'une heure avant la fin des entrées.
    @Test func reloadIsOneHourBeforeTheEntriesRunOut() {
        let now = date("2026-10-15T12:00:00Z")
        #expect(WidgetTimeline.reloadDate(now: now) == date("2026-10-15T17:00:00Z"))
        #expect(WidgetTimeline.reloadDate(now: now) == now.addingTimeInterval(WidgetTimeline.horizon - 3600))
    }

    /// Le rechargement ne dépend pas des matchs : un début proche, déjà passé, d'équipes non suivies ou aucun match ne le
    /// déplace pas ; il tombe toujours avant la dernière date que les entrées peuvent couvrir (jamais de trou).
    @Test func reloadDoesNotDependOnTheMatches() {
        let now = date("2026-10-15T12:00:00Z")
        let soon = match("kc-g2", .unstarted, "2026-10-15T12:10:00Z", "KC", "G2")
        let passed = match("kc-g2", .unstarted, "2026-10-15T11:00:00Z", "KC", "G2")
        let others = makeEvent(id: "g2-fnc", state: .unstarted, start: "2026-10-15T12:05:00Z",
                               teams: [makeTeam("G2"), makeTeam("FNC")])
        for schedule in [[soon], [passed], [others], []] {
            let input = input(schedule, fetchedAt: "2026-10-15T11:30:00Z")
            let entries = WidgetTimeline.entryDates(now: now, input: input)
            #expect(entries.first == now && entries.allSatisfy { $0 >= now })   // un début déjà passé n'ajoute rien
            #expect(WidgetTimeline.reloadDate(now: now) == date("2026-10-15T17:00:00Z"))
            #expect(WidgetTimeline.reloadDate(now: now) < now.addingTimeInterval(WidgetTimeline.horizon))
        }
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
