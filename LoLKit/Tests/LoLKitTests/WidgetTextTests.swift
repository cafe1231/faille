import Foundation
import Testing
@testable import LoLKit

/// Textes des widgets (spec §7) ; un match masqué ne montre jamais ni score ni numéro de game (spec §8).
@Suite struct WidgetTextTests {
    /// Mardi 13 octobre 2026, 14:00 à Paris.
    private let now = date("2026-10-13T12:00:00Z")
    private let paris = TimeZone(secondsFromGMT: 2 * 3600)!
    private let kc = FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")

    private func line(_ codes: [String], _ status: WidgetLine.Status, masked: Bool = false) -> WidgetLine {
        WidgetLine(matchId: codes.joined(separator: "-"), leagueName: "Mondial", codes: codes, colorHexes: [nil, nil],
                   status: status, isMasked: masked)
    }

    private func content(_ lines: [WidgetLine], teams: [FollowedTeam]? = nil) -> WidgetContent {
        WidgetContent(date: now, teams: (teams ?? [kc]).map { WidgetTeam(team: $0, next: .noMatch) }, lines: lines)
    }

    private var live: WidgetLine { line(["KC", "C9"], .live(score: [1, 0], gameNumber: 2)) }
    private var maskedLive: WidgetLine { line(["T1", "FLY"], .live(score: nil, gameNumber: nil), masked: true) }
    /// Jeudi 15 octobre, 11:00 à Paris.
    private var upcoming: WidgetLine { line(["GEN", "FUR"], .upcoming(date("2026-10-15T09:00:00Z"))) }

    @Test func shortDatesInFrench() {
        #expect(Format.day(date("2026-10-16T09:00:00Z"), timeZone: paris) == "ven. 16 oct.")
        #expect(Format.shortDate(date("2026-10-13T20:00:00Z"), now: now, timeZone: paris) == "mar. 22:00")
        #expect(Format.shortDate(date("2026-10-15T09:00:00Z"), now: now, timeZone: paris) == "jeu. 11:00")
        #expect(Format.shortDate(date("2026-10-19T12:00:00Z"), now: now, timeZone: paris) == "lun. 14:00")
        #expect(Format.shortDate(date("2026-10-20T12:00:00Z"), now: now, timeZone: paris) == "mar. 20 oct.")
    }

    @Test func inlineWidget() {
        #expect(WidgetText.inline(content([live]), timeZone: paris) == "KC 1–0 C9 · G2")
        #expect(WidgetText.inline(content([maskedLive]), timeZone: paris) == "T1 vs FLY · En direct")
        #expect(WidgetText.inline(content([upcoming]), timeZone: paris) == "GEN vs FUR · jeu. 11:00")
        #expect(WidgetText.inline(content([]), timeZone: paris) == "Aucun match prévu")
        #expect(WidgetText.inline(content([], teams: []), timeZone: paris) == "Aucune équipe suivie")
    }

    @Test func rectangularWidget() {
        #expect(WidgetText.rectangular(content([live]), timeZone: paris)
                == WidgetText.Rectangular(label: "En direct", title: "KC 1 – 0 C9", detail: "Mondial · Game 2",
                                          isLive: true, isMasked: false))
        #expect(WidgetText.rectangular(content([maskedLive]), timeZone: paris)
                == WidgetText.Rectangular(label: "En direct", title: "T1 vs FLY", detail: "Mondial",
                                          isLive: true, isMasked: true))
        #expect(WidgetText.rectangular(content([upcoming]), timeZone: paris)
                == WidgetText.Rectangular(label: "Prochain", title: "GEN vs FUR", detail: "jeu. 15 oct. · 11:00",
                                          isLive: false, isMasked: false))
        #expect(WidgetText.rectangular(content([]), timeZone: paris)
                == WidgetText.Rectangular(label: "Prochain", title: "Aucun match prévu",
                                          detail: "Ouvre Faille pour actualiser", isLive: false, isMasked: false))
        #expect(WidgetText.rectangular(content([], teams: []), timeZone: paris)
                == WidgetText.Rectangular(label: "Faille", title: "Aucune équipe suivie",
                                          detail: "Ajoute-en dans l'appli", isLive: false, isMasked: false))
    }

    @Test func circularWidget() {
        let soon = line(["GEN", "FUR"], .upcoming(date("2026-10-14T09:00:00Z")))
        #expect(WidgetText.circular(content([soon])) == .countdown(text: "21h", code: "GEN", progress: 0.125))
        let far = line(["GEN", "FUR"], .upcoming(date("2026-10-16T12:00:00Z")))
        #expect(WidgetText.circular(content([far])) == .countdown(text: "3 j", code: "GEN", progress: 0))
        #expect(WidgetText.circular(content([live])) == .live(code: "KC"))
        #expect(WidgetText.circular(content([maskedLive])) == .live(code: "T1"))
        #expect(WidgetText.circular(content([])) == .empty)
    }

    /// W8 : à zéro, « maintenant » ne tient pas dans 50 pt ; le widget rond écrit « 0 min » (match en retard compris).
    @Test func aCountdownAtZeroIsWrittenZeroMinutes() {
        for start in ["2026-10-13T12:00:00Z", "2026-10-13T11:57:00Z"] {   // maintenant, puis 3 min de retard
            let started = line(["GEN", "FUR"], .upcoming(date(start)))
            #expect(WidgetText.circular(content([started])) == .countdown(text: "0 min", code: "GEN", progress: 1), "\(start)")
        }
        // Moins d'une minute avant : « 0 min » aussi, jauge presque pleine.
        let imminent = line(["GEN", "FUR"], .upcoming(date("2026-10-13T12:00:45Z")))
        guard case let .countdown(text, _, progress) = WidgetText.circular(content([imminent])) else {
            Issue.record("compte à rebours attendu")
            return
        }
        #expect(text == "0 min" && progress > 0.99 && progress < 1)
        let oneMinute = line(["GEN", "FUR"], .upcoming(date("2026-10-13T12:01:00Z")))
        #expect(WidgetText.circular(content([oneMinute])) == .countdown(text: "1 min", code: "GEN", progress: 1 - 60.0 / 86400))
    }

    /// W8 : sans groupe d'apps, les widgets le disent au lieu de « Aucune équipe suivie » (rien n'a pu être lu).
    @Test func aMissingAppGroupIsSaidInsteadOfNoFollowedTeam() {
        let missing = WidgetContent(date: now, teams: [], lines: [], appGroupMissing: true)
        let message = "Groupe d'apps introuvable — réinstalle Faille avec AltServer"
        #expect(WidgetText.emptyMessage(missing) == message)
        #expect(WidgetText.inline(missing, timeZone: paris) == message)
        #expect(WidgetText.rectangular(missing, timeZone: paris)
                == WidgetText.Rectangular(label: "Faille", title: "Groupe d'apps introuvable",
                                          detail: "Réinstalle Faille avec AltServer", isLive: false, isMasked: false))
        #expect(WidgetText.small(nil, appGroupMissing: true, timeZone: paris)
                == WidgetText.Small(label: "Faille", title: "Groupe d'apps introuvable", day: nil, time: nil,
                                    note: "Réinstalle Faille avec AltServer", isLive: false, isMasked: false))
        #expect(WidgetText.circular(missing) == .empty)
        // Sans le drapeau, le texte ne change pas.
        #expect(WidgetText.emptyMessage(content([], teams: [])) == "Aucune équipe suivie")
        #expect(WidgetText.small(nil, timeZone: paris).title == "Aucune équipe suivie")
    }

    @Test func mediumWidgetRows() {
        #expect(WidgetText.row(live, now: now, timeZone: paris)
                == WidgetText.Row(title: "KC 1 – 0 C9", trailing: "Game 2", isLive: true, isMasked: false))
        #expect(WidgetText.row(maskedLive, now: now, timeZone: paris)
                == WidgetText.Row(title: "T1 vs FLY", trailing: "En direct", isLive: true, isMasked: true))
        #expect(WidgetText.row(upcoming, now: now, timeZone: paris)
                == WidgetText.Row(title: "GEN vs FUR", trailing: "jeu. 11:00", isLive: false, isMasked: false))
    }

    // MARK: Lignes du moyen widget (W2)

    private let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true, autoColorHex: "#FF5C7A")
    private let gen = FollowedTeam(id: "gen", code: "GEN", name: "Gen.G", spoilerFree: true, autoColorHex: "#FFB454")

    private func datedLine(_ id: String, _ codes: [String], hour: Int) -> WidgetLine {
        WidgetLine(matchId: id, leagueName: "Mondial", codes: codes, colorHexes: [nil, nil],
                   status: .upcoming(date("2026-10-15T\(hour):00:00Z")), isMasked: false)
    }

    private func medium(lines: [WidgetLine], hidden: [FollowedTeam], others: [FollowedTeam] = []) -> WidgetContent {
        WidgetContent(date: now,
                      teams: (others.map { WidgetTeam(team: $0, next: .noMatch) } + hidden.map { WidgetTeam(team: $0, next: .hidden) }),
                      lines: lines)
    }

    @Test func mediumRowsListTheDatedLinesThenTheHiddenTeams() {
        let a = datedLine("a", ["KC", "C9"], hour: 10)
        let b = datedLine("b", ["GEN", "FUR"], hour: 11)
        let rows = WidgetText.mediumRows(medium(lines: [live, a, b], hidden: [t1, gen]), timeZone: paris)
        #expect(rows.map(\.text.title) == ["KC 1 – 0 C9", "KC vs C9", "GEN vs FUR", "T1"])
        #expect(rows.last?.text == WidgetText.Row(title: "T1", trailing: "Prochain · masqué", isLive: false, isMasked: true))
        #expect(rows.last?.colorHexes == ["#FF5C7A"])
        #expect(rows.map(\.isHiddenNext) == [false, false, false, true])
        #expect(rows.count == WidgetText.mediumRowLimit)
    }

    @Test func mediumRowsFillTheLimitWithDatedLinesFirstThenHiddenTeamsInFollowOrder() {
        let dated = (1...5).map { datedLine("m\($0)", ["KC", "C9"], hour: 10 + $0) }
        // Quatre lignes datées ou plus : aucune ligne masquée, la limite est atteinte avec les seules lignes datées.
        #expect(WidgetText.mediumRows(medium(lines: dated, hidden: [t1]), timeZone: paris).map(\.id)
                == ["m1", "m2", "m3", "m4"])
        // Trois lignes datées : une seule place pour les équipes masquées, la première dans l'ordre de suivi.
        let three = WidgetText.mediumRows(medium(lines: Array(dated.prefix(3)), hidden: [t1, gen]), timeZone: paris)
        #expect(three.map(\.id) == ["m1", "m2", "m3", "hidden-t1"])
        // Deux lignes datées : les deux équipes masquées, dans l'ordre de suivi (jamais selon la date d'un match caché).
        let two = WidgetText.mediumRows(medium(lines: Array(dated.prefix(2)), hidden: [gen, t1]), timeZone: paris)
        #expect(two.map(\.id) == ["m1", "m2", "hidden-gen", "hidden-t1"])
    }

    @Test func mediumRowsHaveOneRowPerHiddenTeamWhenNothingIsDated() {
        let rows = WidgetText.mediumRows(medium(lines: [], hidden: [t1], others: [kc]), timeZone: paris)
        #expect(rows.map(\.text.title) == ["T1"])
        // Aucune équipe masquée, aucune ligne : rien (la vue écrit alors `emptyMessage`).
        #expect(WidgetText.mediumRows(medium(lines: [], hidden: [], others: [kc]), timeZone: paris).isEmpty)
        #expect(WidgetText.mediumRows(WidgetContent(date: now, teams: [], lines: []), timeZone: paris).isEmpty)
    }

    @Test func aLiveTeamNeverGetsAHiddenRowToo() {
        // T1 est en direct (masqué) : sa ligne est déjà dans `lines`, pas de ligne « Prochain · masqué » en plus.
        let content = WidgetContent(date: now, teams: [WidgetTeam(team: t1, next: .live(maskedLive))], lines: [maskedLive])
        #expect(WidgetText.mediumRows(content, timeZone: paris).map(\.id) == ["T1-FLY"])
    }

    @Test func datedRowsKeepTheColorsOfTheFollowedTeams() {
        let colored = WidgetLine(matchId: "c", leagueName: "Mondial", codes: ["KC", "FLY"], colorHexes: ["#5B8CFF", nil],
                                 status: .upcoming(date("2026-10-15T10:00:00Z")), isMasked: false)
        let rows = WidgetText.mediumRows(medium(lines: [colored], hidden: []), timeZone: paris)
        #expect(rows.first?.colorHexes == ["#5B8CFF"])
        #expect(rows.first?.text == WidgetText.row(colored, now: now, timeZone: paris))
    }

    @Test func smallWidget() {
        let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)
        #expect(WidgetText.small(WidgetTeam(team: kc, next: .match(upcoming)), timeZone: paris)
                == WidgetText.Small(label: "Prochain", title: "GEN vs FUR", day: "jeu. 15 oct.", time: "11:00",
                                    note: nil, isLive: false, isMasked: false))
        #expect(WidgetText.small(WidgetTeam(team: kc, next: .live(live)), timeZone: paris)
                == WidgetText.Small(label: "En direct", title: "KC 1 – 0 C9", day: nil, time: nil,
                                    note: "Mondial · Game 2", isLive: true, isMasked: false))
        #expect(WidgetText.small(WidgetTeam(team: t1, next: .live(maskedLive)), timeZone: paris)
                == WidgetText.Small(label: "En direct", title: "T1 vs FLY", day: nil, time: nil,
                                    note: "Mondial", isLive: true, isMasked: true))
        #expect(WidgetText.small(WidgetTeam(team: t1, next: .hidden), timeZone: paris)
                == WidgetText.Small(label: "Prochain", title: "T1", day: nil, time: nil,
                                    note: "masqué", isLive: false, isMasked: true))
        #expect(WidgetText.small(WidgetTeam(team: kc, next: .noMatch), timeZone: paris)
                == WidgetText.Small(label: "Prochain", title: "KC", day: nil, time: nil,
                                    note: "Aucun match prévu", isLive: false, isMasked: false))
        #expect(WidgetText.small(nil, timeZone: paris)
                == WidgetText.Small(label: "Faille", title: "Aucune équipe suivie", day: nil, time: nil,
                                    note: "Ajoute-en dans l'appli", isLive: false, isMasked: false))
    }

    /// R-I2 (spec §8) : sans match à montrer, une équipe en anti-spoiler dont le prochain match est masqué ne se lit
    /// jamais « Aucun match prévu » (on y verrait une équipe éliminée).
    @Test func aHiddenTeamIsNotReportedAsHavingNoMatch() {
        let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)
        let both = WidgetContent(date: now, teams: [WidgetTeam(team: kc, next: .noMatch),
                                                    WidgetTeam(team: t1, next: .hidden)], lines: [])
        #expect(WidgetText.emptyMessage(both) == "Prochain · masqué")
        #expect(WidgetText.inline(both, timeZone: paris) == "Prochain · masqué")
        #expect(WidgetText.rectangular(both, timeZone: paris)
                == WidgetText.Rectangular(label: "Prochain", title: "Masqué", detail: "Anti-spoiler",
                                          isLive: false, isMasked: true))
        let onlyKC = WidgetContent(date: now, teams: [WidgetTeam(team: kc, next: .noMatch)], lines: [])
        #expect(WidgetText.emptyMessage(onlyKC) == "Aucun match prévu")
    }

    /// W6 : les aides écrivent elles-mêmes sans score ni game une ligne masquée, même si on leur en donne un
    /// (défense en profondeur : `WidgetTimeline` ne construit jamais une telle ligne).
    @Test func maskedLinesNeverWriteTheirScoreEvenWhenTheyCarryOne() {
        let t1 = FollowedTeam(id: "t1", code: "T1", name: "T1", spoilerFree: true)
        let leaky = line(["T1", "FLY"], .live(score: [2, 1], gameNumber: 4), masked: true)
        #expect(WidgetText.inline(content([leaky]), timeZone: paris) == "T1 vs FLY · En direct")
        #expect(WidgetText.rectangular(content([leaky]), timeZone: paris)
                == WidgetText.Rectangular(label: "En direct", title: "T1 vs FLY", detail: "Mondial",
                                          isLive: true, isMasked: true))
        #expect(WidgetText.row(leaky, now: now, timeZone: paris)
                == WidgetText.Row(title: "T1 vs FLY", trailing: "En direct", isLive: true, isMasked: true))
        #expect(WidgetText.small(WidgetTeam(team: t1, next: .live(leaky)), timeZone: paris)
                == WidgetText.Small(label: "En direct", title: "T1 vs FLY", day: nil, time: nil, note: "Mondial",
                                    isLive: true, isMasked: true))
        #expect(WidgetText.circular(content([leaky])) == .live(code: "T1"))
        // La même ligne non masquée écrit bien son score : seul `isMasked` coupe.
        let open = line(["T1", "FLY"], .live(score: [2, 1], gameNumber: 4))
        #expect(WidgetText.inline(content([open]), timeZone: paris) == "T1 2–1 FLY · G4")
        #expect(WidgetText.row(open, now: now, timeZone: paris).trailing == "Game 4")
    }

    @Test func maskedTextsNeverCarryAScoreOrAGame() {
        let texts = [
            WidgetText.inline(content([maskedLive]), timeZone: paris),
            WidgetText.rectangular(content([maskedLive]), timeZone: paris).title,
            WidgetText.rectangular(content([maskedLive]), timeZone: paris).detail,
            WidgetText.row(maskedLive, now: now, timeZone: paris).trailing,
            WidgetText.small(WidgetTeam(team: kc, next: .live(maskedLive)), timeZone: paris).note ?? "",
        ]
        for text in texts {
            #expect(!text.contains("–") && !text.contains("Game") && !text.contains(" · G"), "\(text)")
        }
    }
}
