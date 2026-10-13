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

    /// Ligne « Prochain » d'une carte, avec les équipes au dernier match masqué tirées de `cards` (toutes les cartes de
    /// l'écran ; par défaut la seule carte donnée).
    private func nextLine(for card: TeamCard, in cards: [TeamCard]? = nil, follows list: FollowList,
                          revealed: Set<String> = []) -> NextLine {
        Presenter.nextLine(for: card, follows: list, revealed: revealed,
                           maskedLatestTeamIds: Presenter.maskedLatestTeamIds(cards ?? [card], follows: list,
                                                                              revealed: revealed))
    }

    @Test func maskedLastWithNextMatchHidesTheNextLine() throws {
        let card = try t1Card(next: t1("n", .unstarted, start: "2026-10-20T10:00:00Z", vs: "GEN"),
                              last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(nextLine(for: card, follows: try follows()) == .hidden)
    }

    @Test func maskedLastWithoutNextMatchIsHiddenToo() throws {
        let card = try t1Card(last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 0))
        #expect(nextLine(for: card, follows: try follows()) == .hidden)
    }

    @Test func maskedLiveMatchHidesTheNextLine() throws {
        let card = try t1Card(live: t1("lv", .inProgress, start: "2026-10-13T10:00:00Z", wins: 1),
                              next: t1("n", .unstarted, start: "2026-10-20T10:00:00Z"),
                              last: makeEvent(id: "old", state: .completed, start: "2026-10-01T10:00:00Z",
                                              teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")]))
        #expect(nextLine(for: card, follows: try follows()) == .hidden)
    }

    @Test func liveMatchTakesPrecedenceOverLast() throws {
        // Le dernier match terminé est masqué, mais le match en direct (révélé) a la priorité : seul lui compte.
        let live = t1("lv", .inProgress, start: "2026-10-13T10:00:00Z")
        let next = t1("n", .unstarted, start: "2026-10-20T10:00:00Z")
        let card = try t1Card(live: live, next: next, last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(nextLine(for: card, follows: try follows(), revealed: ["lv"]) == .match(next))
    }

    @Test func revealedLastShowsTheNextMatch() throws {
        let next = t1("n", .unstarted, start: "2026-10-20T10:00:00Z", vs: "GEN")
        let card = try t1Card(next: next, last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(nextLine(for: card, follows: try follows(), revealed: ["l"]) == .match(next))
        // Révéler un autre match ne change rien.
        #expect(nextLine(for: card, follows: try follows(), revealed: ["autre"]) == .hidden)
    }

    @Test func revealedLastWithoutNextIsNone() throws {
        let card = try t1Card(last: t1("l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        #expect(nextLine(for: card, follows: try follows(), revealed: ["l"]) == .none)
    }

    @Test func unmaskedTeamShowsItsNextMatch() throws {
        let list = try follows()
        let kc = try #require(list.teams.first { $0.code == "KC" })
        let next = makeEvent(id: "n", state: .unstarted, start: "2026-10-20T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let last = makeEvent(id: "l", state: .completed, start: "2026-10-10T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp", wins: 3), makeTeam("C9", wins: 0)])
        #expect(nextLine(for: TeamCard(team: kc, live: nil, next: next, last: last), follows: list) == .match(next))
        #expect(nextLine(for: TeamCard(team: kc, live: nil, next: nil, last: last), follows: list) == .none)
        #expect(nextLine(for: TeamCard(team: kc, live: nil, next: nil, last: nil), follows: list) == .none)
    }

    @Test func opponentInSpoilerFreeModeMasksTheLastMatchOfAnUnmaskedTeam() throws {
        // KC n'est pas en anti-spoiler, mais son dernier match était contre T1 (anti-spoiler) : masqué, donc « Prochain » aussi.
        let list = try follows()
        let kc = try #require(list.teams.first { $0.code == "KC" })
        let last = makeEvent(id: "l", state: .completed, start: "2026-10-10T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp", wins: 0), makeTeam("T1", id: Self.t1Id, wins: 3)])
        let next = makeEvent(id: "n", state: .unstarted, start: "2026-10-20T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        #expect(nextLine(for: TeamCard(team: kc, live: nil, next: next, last: last), follows: list) == .hidden)
    }

    // MARK: Règle C affinée (W5) : symétrique, sans nouvelle fuite

    private func gen(_ list: FollowList) throws -> FollowedTeam {
        try #require(list.teams.first { $0.code == "GEN" })
    }

    private func genVsT1(_ id: String = "gen-t1") -> MatchEvent {
        makeEvent(id: id, state: .unstarted, start: "2026-10-20T10:00:00Z",
                  teams: [makeTeam("GEN", name: "Gen.G Esports"), makeTeam("T1", id: Self.t1Id)])
    }

    @Test func nextMatchAgainstASpoilerFreeTeamWithNothingMaskedIsAnnounced() throws {
        // T1 est en anti-spoiler mais n'a ni match en direct ni dernier match : rien à trahir, « GEN vs T1 » s'affiche
        // sur les deux cartes.
        let list = try follows()
        let next = genVsT1()
        let genCard = TeamCard(team: try gen(list), live: nil, next: next, last: nil)
        let t1 = TeamCard(team: try #require(list.team(id: Self.t1Id)), live: nil, next: next, last: nil)
        #expect(Presenter.maskedLatestTeamIds([genCard, t1], follows: list, revealed: []).isEmpty)
        #expect(nextLine(for: genCard, in: [genCard, t1], follows: list) == .match(next))
        #expect(nextLine(for: t1, in: [genCard, t1], follows: list) == .match(next))
        #expect(Format.cardsSubtitle([genCard, t1], follows: list, revealed: []) == "0 en direct · 2 à venir")
    }

    @Test func nextMatchAgainstASpoilerFreeTeamWithAMaskedLatestMatchIsHidden() throws {
        let list = try follows()
        let next = genVsT1()
        let genCard = TeamCard(team: try gen(list), live: nil, next: next, last: nil)
        let t1 = TeamCard(team: try #require(list.team(id: Self.t1Id)), live: nil, next: next,
                          last: t1("t1-l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        let cards = [genCard, t1]
        #expect(Presenter.maskedLatestTeamIds(cards, follows: list, revealed: []) == [Self.t1Id])
        #expect(nextLine(for: genCard, in: cards, follows: list) == .hidden)
        #expect(nextLine(for: t1, in: cards, follows: list) == .hidden)   // règle F1, inchangée
        #expect(Format.cardsSubtitle(cards, follows: list, revealed: []) == "0 en direct · 0 à venir")
    }

    @Test func aMaskedLiveMatchOfTheSpoilerFreeTeamAlsoHidesTheOtherTeamsNextMatch() throws {
        let list = try follows()
        let genCard = TeamCard(team: try gen(list), live: nil, next: genVsT1(), last: nil)
        let t1 = TeamCard(team: try #require(list.team(id: Self.t1Id)),
                          live: t1("t1-lv", .inProgress, start: "2026-10-13T10:00:00Z", wins: 1), next: nil, last: nil)
        #expect(nextLine(for: genCard, in: [genCard, t1], follows: list) == .hidden)
    }

    @Test func revealingTheSpoilerFreeTeamsLatestMatchAnnouncesTheNextMatchAgain() throws {
        let list = try follows()
        let next = genVsT1()
        let genCard = TeamCard(team: try gen(list), live: nil, next: next, last: nil)
        let t1 = TeamCard(team: try #require(list.team(id: Self.t1Id)), live: nil, next: next,
                          last: t1("t1-l", .completed, start: "2026-10-10T10:00:00Z", wins: 3))
        let cards = [genCard, t1]
        #expect(nextLine(for: genCard, in: cards, follows: list, revealed: ["t1-l"]) == .match(next))
        // Révéler le prochain match lui-même ne suffit pas à lever F1 sur la carte de T1, mais lève la règle C sur GEN.
        #expect(nextLine(for: genCard, in: cards, follows: list, revealed: ["gen-t1"]) == .match(next))
        #expect(nextLine(for: t1, in: cards, follows: list, revealed: ["gen-t1"]) == .hidden)
    }

    @Test func aSpoilerFreeTeamWithoutACardIsNeverTreatedAsMasked() throws {
        // Sans la carte de T1 dans `cards`, rien ne dit que son dernier match est masqué : on n'invente pas de masque.
        let list = try follows()
        let next = genVsT1()
        let genCard = TeamCard(team: try gen(list), live: nil, next: next, last: nil)
        #expect(nextLine(for: genCard, follows: list) == .match(next))
    }

    @Test func maskedLatestTeamIdsFollowTheSameDefinitionAsTheCardsLine() throws {
        // KC (non masquée) dont le dernier match était contre T1 : son dernier match est masqué, comme sa carte le dit.
        let list = try follows()
        let kc = try #require(list.teams.first { $0.code == "KC" })
        let last = makeEvent(id: "l", state: .completed, start: "2026-10-10T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp", wins: 0), makeTeam("T1", id: Self.t1Id, wins: 3)])
        let kcCard = TeamCard(team: kc, live: nil, next: nil, last: last)
        #expect(Presenter.maskedLatestTeamIds([kcCard], follows: list, revealed: []) == [kc.id])
        #expect(Presenter.maskedLatestTeamIds([kcCard], follows: list, revealed: ["l"]).isEmpty)
        // Le direct prime sur le dernier match (comme F1).
        let live = makeEvent(id: "lv", state: .inProgress, start: "2026-10-13T10:00:00Z",
                             teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        #expect(Presenter.maskedLatestTeamIds([TeamCard(team: kc, live: live, next: nil, last: last)],
                                              follows: list, revealed: []).isEmpty)
    }

    @Test func aCardNextToASpoilerFreeTeamKeepsItsDateOrderWhenNothingIsMasked() throws {
        // GEN – T1 (20 oct.) sans rien de masqué : GEN et T1 sont ordonnées par ce match, avant KC (21 oct.).
        var list = FollowList()
        list.follow(try catalogTeam("KC"))
        list.follow(try catalogTeam("GEN"))
        list.follow(try catalogTeam("T1"))
        list.setSpoilerFree(true, id: Self.t1Id)
        let kcNext = makeEvent(id: "kc-n", state: .unstarted, start: "2026-10-21T10:00:00Z",
                               teams: [makeTeam("KC", name: "Karmine Corp"), makeTeam("C9")])
        let cards = TeamCards.build(follows: list, schedule: [kcNext, genVsT1()], live: [], revealed: [])
        #expect(cards.map(\.team.code) == ["GEN", "T1", "KC"])
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
