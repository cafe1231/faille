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

    @Test func mediumWidgetRows() {
        #expect(WidgetText.row(live, now: now, timeZone: paris)
                == WidgetText.Row(title: "KC 1 – 0 C9", trailing: "Game 2", isLive: true, isMasked: false))
        #expect(WidgetText.row(maskedLive, now: now, timeZone: paris)
                == WidgetText.Row(title: "T1 vs FLY", trailing: "En direct", isLive: true, isMasked: true))
        #expect(WidgetText.row(upcoming, now: now, timeZone: paris)
                == WidgetText.Row(title: "GEN vs FUR", trailing: "jeu. 11:00", isLive: false, isMasked: false))
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
