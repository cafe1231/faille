import Foundation
import Testing
@testable import LoLKit

/// F1 : la ligne « Prochain » d'une carte ne doit rien trahir d'un match masqué (spec §8) :
/// ni l'existence ni l'adversaire du prochain match (élimination, tableau, Swiss), ni son ordre, ni son compte.
@Suite struct NextLineTests {
    private static let t1Id = "98767991853197861"

    /// T1 en anti-spoiler ; KC et GEN suivies normalement.
    private func follows() throws -> FollowList {
        var list = FollowList()
        list.follow(try catalogTeam("T1"))
        list.follow(try catalogTeam("KC"))
        list.follow(try catalogTeam("GEN"))
        list.setSpoilerFree(true, id: Self.t1Id)
        return list
    }

    private func t1(_ id: String, _ state: EventState, start: String, wins: Int = 0, vs: String = "FLY") -> MatchEvent {
        makeEvent(id: id, state: state, start: start,
                  teams: [makeTeam("T1", id: Self.t1Id, wins: wins), makeTeam(vs, id: "opp-\(vs)", wins: 0)])
    }

    private func t1Card(live: MatchEvent? = nil, next: MatchEvent? = nil, last: MatchEvent? = nil) throws -> TeamCard {
        TeamCard(team: try #require(try follows().team(id: Self.t1Id)), live: live, next: next, last: last)
    }

    @Test func maskedLastWithNextMatchHidesTheNextLine() throws {
        let card = try t1Card(next: t1("n", .unstarted, start: "2026-10-20T10:00:00Z", vs: "GEN"),
                              last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: []) == .hidden)
    }

    @Test func maskedLastWithoutNextMatchIsHiddenToo() throws {
        let card = try t1Card(last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 0))
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: []) == .hidden)
    }

    @Test func maskedLiveMatchHidesTheNextLine() throws {
        let card = try t1Card(live: t1("lv", .inProgress, start: "2026-10-13T10:00:00Z", wins: 1),
                              next: t1("n", .unstarted, start: "2026-10-20T10:00:00Z"),
                              last: makeEvent(id: "old", state: .completed, start: "2026-10-01T10:00:00Z",
                                              teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")]))
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: []) == .hidden)
    }

    @Test func liveMatchTakesPrecedenceOverLast() throws {
        // Le dernier match terminé est masqué, mais le match en direct (révélé) a la priorité : seul lui compte.
        let live = t1("lv", .inProgress, start: "2026-10-13T10:00:00Z")
        let next = t1("n", .unstarted, start: "2026-10-20T10:00:00Z")
        let card = try t1Card(live: live, next: next, last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: ["lv"]) == .match(next))
    }

    @Test func revealedLastShowsTheNextMatch() throws {
        let next = t1("n", .unstarted, start: "2026-10-20T10:00:00Z", vs: "GEN")
        let card = try t1Card(next: next, last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: ["l"]) == .match(next))
        // Révéler un autre match ne change rien.
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: ["autre"]) == .hidden)
    }

    @Test func revealedLastWithoutNextIsNone() throws {
        let card = try t1Card(last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(Presenter.nextLine(for: card, follows: try follows(), revealed: ["l"]) == .none)
    }

    @Test func unmaskedTeamShowsItsNextMatch() throws {
        let list = try follows()
        let kc = try #require(list.teams.first { $0.code == "KC" })
        let next = makeEvent(id: "n", state: .unstarted, start: "2026-10-20T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let last = makeEvent(id: "l", state: .completed, start: "2026-10-10T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp", wins: 3), makeTeam("C9", wins: 0)])
        #expect(Presenter.nextLine(for: TeamCard(team: kc, live: nil, next: next, last: last), follows: list, revealed: [])
                == .match(next))
        #expect(Presenter.nextLine(for: TeamCard(team: kc, live: nil, next: nil, last: last), follows: list, revealed: [])
                == .none)
        #expect(Presenter.nextLine(for: TeamCard(team: kc, live: nil, next: nil, last: nil), follows: list, revealed: [])
                == .none)
    }

    @Test func opponentInSpoilerFreeModeMasksTheLastMatchOfAnUnmaskedTeam() throws {
        // KC n'est pas en anti-spoiler, mais son dernier match était contre T1 (anti-spoiler) : masqué, donc « Prochain » aussi.
        let list = try follows()
        let kc = try #require(list.teams.first { $0.code == "KC" })
        let last = makeEvent(id: "l", state: .completed, start: "2026-10-10T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp", wins: 0), makeTeam("T1", id: Self.t1Id, wins: 3)])
        let next = makeEvent(id: "n", state: .unstarted, start: "2026-10-20T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        #expect(Presenter.nextLine(for: TeamCard(team: kc, live: nil, next: next, last: last), follows: list, revealed: [])
                == .hidden)
    }

    @Test func nextMatchAgainstASpoilerFreeTeamIsHiddenOnTheOtherTeamsCard() throws {
        let list = try follows()
        let gen = try #require(list.teams.first { $0.code == "GEN" })
        let next = makeEvent(id: "gen-t1", state: .unstarted, start: "2026-10-20T10:00:00Z",
                             teams: [makeTeam("GEN", name: gen.name), makeTeam("T1", id: Self.t1Id)])
        let card = TeamCard(team: gen, live: nil, next: next, last: nil)
        #expect(Presenter.nextLine(for: card, follows: list, revealed: []) == .hidden)
        #expect(Format.cardsSubtitle([card], follows: list, revealed: []) == "0 en direct · 0 à venir")
        #expect(Presenter.nextLine(for: card, follows: list, revealed: ["gen-t1"]) == .match(next))
    }

    // MARK: Tri et compte

    @Test func maskedCardIsNotOrderedByItsNextMatch() throws {
        // T1 (masquée) a le prochain match le plus proche : sans la règle, elle passerait devant GEN et trahirait qu'elle joue encore.
        let list = try follows()
        let t1Last = t1("t1-last", .completed, start: "2026-10-10T10:00:00Z", wins: 3)
        let t1Next = t1("t1-next", .unstarted, start: "2026-10-14T10:00:00Z")
        let genNext = makeEvent(id: "gen-next", state: .unstarted, start: "2026-10-20T10:00:00Z",
                                teams: [makeTeam("GEN", name: "Gen.G Esports"), makeTeam("X")])
        let cards = TeamCards.build(follows: list, schedule: [t1Last, t1Next, genNext], live: [], revealed: [])
        // GEN a un prochain match visible : elle passe en premier ; T1 reprend sa place de suivi parmi les cartes
        // sans prochain match, devant KC puisque T1 est suivie avant KC.
        #expect(cards.map(\.team.code) == ["GEN", "T1", "KC"])
    }

    @Test func revealedCardGoesBackToBeingOrderedByItsNextMatch() throws {
        let list = try follows()
        let t1Last = t1("t1-last", .completed, start: "2026-10-10T10:00:00Z", wins: 3)
        let t1Next = t1("t1-next", .unstarted, start: "2026-10-14T10:00:00Z")
        let genNext = makeEvent(id: "gen-next", state: .unstarted, start: "2026-10-20T10:00:00Z",
                                teams: [makeTeam("GEN", name: "Gen.G Esports"), makeTeam("X")])
        let cards = TeamCards.build(follows: list, schedule: [t1Last, t1Next, genNext], live: [], revealed: ["t1-last"])
        #expect(cards.map(\.team.code) == ["T1", "GEN", "KC"])
    }

    @Test func maskedCardKeepsFollowOrderAmongCardsWithoutNextMatch() throws {
        var list = FollowList()
        list.follow(try catalogTeam("KC"))   // 0 : aucun match
        list.follow(try catalogTeam("T1"))   // 1 : masquée, avec un prochain match
        list.setSpoilerFree(true, id: Self.t1Id)
        let cards = TeamCards.build(
            follows: list,
            schedule: [t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3), t1("n", .unstarted, start: "2026-10-14T10:00:00Z")],
            live: [], revealed: [])
        #expect(cards.map(\.team.code) == ["KC", "T1"])
    }

    @Test func subtitleDoesNotCountMaskedCards() throws {
        let list = try follows()
        let maskedCard = try t1Card(next: t1("n", .unstarted, start: "2026-10-20T10:00:00Z"),
                                    last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        let kc = try #require(list.teams.first { $0.code == "KC" })
        let kcNext = makeEvent(id: "kn", state: .unstarted, start: "2026-10-21T10:00:00Z",
                               teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let cards = [maskedCard, TeamCard(team: kc, live: nil, next: kcNext, last: nil)]
        #expect(Format.cardsSubtitle(cards, follows: list, revealed: []) == "0 en direct · 1 à venir")
        #expect(Format.cardsSubtitle(cards, follows: list, revealed: ["l"]) == "0 en direct · 2 à venir")
    }
}
