import Foundation
import LoLKit
import Testing
@testable import Faille

/// Ligne « Dernier » des cartes (spec §5.1, §8) : le résultat n'apparaît jamais tant que le match est masqué.
@MainActor
struct MatchCardTextTests {
    private func completed(_ id: String, _ a: (code: String, wins: Int), _ b: (code: String, wins: Int)) -> MatchEvent {
        // Forme `getSchedule` : pas d'id, l'équipe suivie se reconnaît à son nom.
        let names = ["T1": "T1", "GEN": "Gen.G", "HLE": "Hanwha Life Esports"]
        func side(_ team: (code: String, wins: Int)) -> MatchTeam {
            MatchTeam(id: nil, name: names[team.code] ?? team.code, code: team.code, image: nil,
                      result: MatchTeam.Result(outcome: team.wins >= 3 ? "win" : "loss", gameWins: team.wins))
        }
        return MatchEvent(startTime: SampleData.date("2026-10-11T09:00:00Z"), state: .completed, type: "match",
                          blockName: "Play-in", league: SampleData.worlds,
                          match: MatchInfo(id: id, teams: [side(a), side(b)],
                                           strategy: Strategy(type: "bestOf", count: 5), games: nil),
                          streams: nil)
    }

    /// Store d'aperçu où T1 (anti-spoiler) et GEN (non masquée) ont chacun un match terminé.
    private func store(with events: [MatchEvent]) -> AppStore {
        AppStore(preview: PreviewData(follows: SampleData.follows, schedule: events, live: []))
    }

    @Test func maskedLastRowShowsDateButNoResult() throws {
        let event = completed("m-t1-gen-done", ("T1", 3), ("GEN", 1))
        let store = store(with: [event])
        let card = try #require(store.cards.first { $0.team.code == "T1" })
        #expect(card.last?.id == event.id)
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        // Ni le score de série (« 3 – 1 ») ni son tiret : le seul chiffre permis est celui de « T1 ».
        let text = Format.lastRow(line, order: order, date: "DATE")
        #expect(text == "Dernier · T1 vs GEN · Terminé · DATE")
        #expect(!text.contains("3") && !text.contains("–"))
    }

    /// Spec §8 : un match masqué n'affiche que « En direct », « Terminé » ou « À venir » (jamais « masqué » en guise d'état).
    @Test func maskedMatchesOnlyShowTheirStatus() {
        #expect(LiveChipText.maskedText(phase: .inGame, opponent: nil) == "En direct")
        #expect(LiveChipText.maskedText(phase: .inGame, opponent: "FLY") == "En direct vs FLY")
        // Entre deux games, un match masqué reste « En direct » (sinon le nombre de pauses trahit la longueur de la série).
        #expect(LiveChipText.maskedText(phase: .betweenGames, opponent: "FLY") == "En direct vs FLY")
        #expect(LiveChipText.maskedText(phase: .finished, opponent: nil) == "Terminé")
        #expect(LiveChipText.maskedText(phase: .finished, opponent: "FLY") == "Terminé vs FLY")
        #expect(LiveChipText.maskedText(phase: .upcoming, opponent: nil) == "À venir")
    }

    @Test func liveIconOnlyAccompaniesTheLiveState() {
        #expect(LiveChipText.icon(for: .inGame) == .live)
        #expect(LiveChipText.icon(for: .betweenGames) == .live)
        #expect(LiveChipText.icon(for: .finished) == .check)
        #expect(LiveChipText.icon(for: .upcoming) == .clock)
    }

    @Test func unmaskedUpcomingIsWrittenAVenir() {
        let upcoming = LiveMatchState(phase: .upcoming, seriesScore: [0, 0], gameNumber: 1, gameClockStart: nil,
                                      gameClockStoppedAt: nil, stats: nil, statsAvailable: true, spoilerFree: false,
                                      winnerCode: nil, updatedAt: SampleData.date("2026-10-15T15:05:00Z"))
        #expect(LiveChipText.prefix(for: upcoming) == "À venir")
        var finished = upcoming
        finished.phase = .finished
        #expect(LiveChipText.prefix(for: finished) == "Terminé")
    }

    /// `getLive` (ou le calendrier) donne le match pour terminé alors que les victoires ne l'ont pas encore rattrapé :
    /// masqué, il s'affiche « Terminé » et non « En direct ».
    @Test func maskedMatchTheAPICallsCompletedIsShownFinished() {
        let store = AppStore(preview: .standard)
        let live = SampleData.t1Live   // T1 est en anti-spoiler : masqué
        let masked = store.liveState(for: live)
        #expect(masked.spoilerFree && masked.phase == .inGame)
        #expect(masked.displayed(for: live).phase == .inGame)   // l'API le dit en cours : rien ne change

        let completed = MatchEvent(startTime: live.startTime, state: .completed, type: live.type, blockName: live.blockName,
                                   league: live.league, match: live.match, streams: live.streams)
        let shown = masked.displayed(for: completed)
        #expect(shown.phase == .finished)
        #expect(shown.spoilerFree && shown.seriesScore == nil && shown.gameNumber == nil)
        #expect(LiveChipText.maskedText(phase: shown.phase, opponent: "FLY") == "Terminé vs FLY")
    }

    @Test func revealedLastRowShowsTheScore() throws {
        let event = completed("m-t1-gen-done", ("T1", 3), ("GEN", 1))
        let store = store(with: [event])
        store.reveal(matchId: event.id)
        let card = try #require(store.cards.first { $0.team.code == "T1" })
        let text = Format.lastRow(store.scoreLine(event), order: store.follows.displayOrder(event.match.teams, preferring: card.team),
                                  date: "DATE")
        #expect(text == "Dernier · T1 3 – 1 GEN")
    }

    @Test func lastRowPutsTheCardTeamOnTheLeft() throws {
        // GEN (non masquée) est à droite dans l'API : sa carte la remet à gauche, score compris.
        let event = completed("m-hle-gen-done", ("HLE", 0), ("GEN", 3))
        let store = store(with: [event])
        let card = try #require(store.cards.first { $0.team.code == "GEN" })
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        #expect(order == [1, 0])
        #expect(Format.lastRow(store.scoreLine(event), order: order, date: "DATE") == "Dernier · GEN 3 – 0 HLE")
    }
}

/// Ligne « Prochain » des cartes (F1, spec §8) : l'existence ou l'adversaire du prochain match d'une équipe dont le
/// dernier match est masqué ne doit rien trahir (ni dans la carte, ni dans l'ordre des cartes, ni dans le compte).
@MainActor
struct NextRowPrivacyTests {
    private func upcoming(_ id: String, start: String, _ a: (code: String, name: String), _ b: (code: String, name: String)) -> MatchEvent {
        func side(_ team: (code: String, name: String)) -> MatchTeam {
            MatchTeam(id: nil, name: team.name, code: team.code, image: nil, result: MatchTeam.Result(outcome: nil, gameWins: 0))
        }
        return MatchEvent(startTime: SampleData.date(start), state: .unstarted, type: "match", blockName: "Play-in",
                          league: SampleData.worlds,
                          match: MatchInfo(id: id, teams: [side(a), side(b)], strategy: Strategy(type: "bestOf", count: 5), games: nil),
                          streams: nil)
    }

    private func finished(_ id: String, start: String) -> MatchEvent {
        func side(_ code: String, _ name: String, _ wins: Int) -> MatchTeam {
            MatchTeam(id: nil, name: name, code: code, image: nil,
                      result: MatchTeam.Result(outcome: wins == 3 ? "win" : "loss", gameWins: wins))
        }
        return MatchEvent(startTime: SampleData.date(start), state: .completed, type: "match", blockName: "Play-in",
                          league: SampleData.worlds,
                          match: MatchInfo(id: id, teams: [side("T1", "T1", 3), side("HLE", "Hanwha Life Esports", 1)],
                                           strategy: Strategy(type: "bestOf", count: 5), games: nil),
                          streams: nil)
    }

    /// KC (aucun match), T1 (anti-spoiler : dernier match terminé + un prochain match très proche), GEN (prochain match plus tard).
    private func store() -> AppStore {
        let schedule = [
            finished("t1-done", start: "2026-10-11T09:00:00Z"),
            upcoming("t1-next", start: "2026-10-14T09:00:00Z", ("T1", "T1"), ("FLY", "FlyQuest")),
            upcoming("gen-next", start: "2026-10-16T09:00:00Z", ("GEN", "Gen.G"), ("FUR", "FURIA")),
        ]
        return AppStore(preview: PreviewData(follows: SampleData.follows, schedule: schedule, live: []))
    }

    @Test func maskedCardShowsAFixedNextLineAndIsNotCounted() throws {
        let store = store()
        let t1 = try #require(store.cards.first { $0.team.code == "T1" })
        #expect(t1.next?.id == "t1-next")                         // la donnée existe...
        #expect(store.nextLine(for: t1) == .hidden)               // ...mais la carte n'a pas le droit de l'annoncer
        let gen = try #require(store.cards.first { $0.team.code == "GEN" })
        let genNext = try #require(gen.next)
        #expect(store.nextLine(for: gen) == .match(genNext))
        #expect(store.cardsSubtitle(store.cards) == "0 en direct · 1 à venir")
    }

    @Test func maskedCardKeepsItsFollowPositionInsteadOfItsNextMatchDate() {
        // Sans la règle : T1 (14 oct.) passerait avant GEN (16 oct.). Avec : GEN d'abord, puis KC et T1 dans l'ordre de suivi.
        #expect(store().cards.map(\.team.code) == ["GEN", "KC", "T1"])
    }

    @Test func revealingTheLastMatchBringsTheNextLineBack() throws {
        let store = store()
        store.reveal(matchId: "t1-done")
        #expect(store.cards.map(\.team.code) == ["T1", "GEN", "KC"])
        let t1 = try #require(store.cards.first { $0.team.code == "T1" })
        let t1Next = try #require(t1.next)
        #expect(store.nextLine(for: t1) == .match(t1Next))
        #expect(store.cardsSubtitle(store.cards) == "0 en direct · 2 à venir")
    }
}
