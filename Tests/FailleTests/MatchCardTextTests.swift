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
        // La date est remplacée par un repère sans chiffre : tout chiffre dans le texte serait un score qui fuit.
        let text = lastRowText(line, order: order, date: "DATE")
        #expect(text == "Dernier · T1 vs GEN · DATE · masqué")
        #expect(text.allSatisfy { !$0.isNumber })
    }

    @Test func revealedLastRowShowsTheScore() throws {
        let event = completed("m-t1-gen-done", ("T1", 3), ("GEN", 1))
        let store = store(with: [event])
        store.reveal(matchId: event.id)
        let card = try #require(store.cards.first { $0.team.code == "T1" })
        let text = lastRowText(store.scoreLine(event), order: store.follows.displayOrder(event.match.teams, preferring: card.team),
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
        #expect(lastRowText(store.scoreLine(event), order: order, date: "DATE") == "Dernier · GEN 3 – 0 HLE")
    }
}
