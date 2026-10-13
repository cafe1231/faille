import Foundation
@testable import LoLKit

/// Date de test lisible : `date("2026-10-15T18:00:00Z")`.
func date(_ iso: String) -> Date {
    LoLDate.parse(iso)!
}

/// Équipe d'un match. Sans `id`, comme dans `getSchedule`.
func makeTeam(_ code: String, id: String? = nil, name: String? = nil, image: String? = nil, wins: Int? = nil) -> MatchTeam {
    MatchTeam(id: id, name: name ?? code, code: code, image: image,
              result: wins.map { MatchTeam.Result(outcome: nil, gameWins: $0) })
}

/// Match de test (forme `getSchedule` / `getLive`).
func makeEvent(
    id: String,
    state: EventState,
    start: String = "2026-10-15T18:00:00Z",
    teams: [MatchTeam],
    bestOf: Int = 5,
    games: [GameRef]? = nil,
    statsDisabled: Bool = false
) -> MatchEvent {
    MatchEvent(
        startTime: date(start),
        state: state,
        type: "match",
        blockName: "Play-ins",
        league: LeagueRef(id: "98767975604431411", slug: "worlds", name: "Mondial", image: nil),
        match: MatchInfo(id: id, teams: teams, strategy: Strategy(type: "bestOf", count: bestOf), games: games),
        streams: [StreamInfo(statsStatus: statsDisabled ? "disabled" : "enabled")]
    )
}

/// Détails de match de test (forme `getEventDetails`). Par défaut, la finale LCS : TLAW vs LYON.
func makeDetails(
    wins: [Int],
    games: [(number: Int, id: String, state: GameRef.State)],
    bestOf: Int = 5,
    teams: [(id: String, code: String)] = [("98926509885559666", "TLAW"), ("99566405941863385", "LYON")]
) -> EventDetails {
    EventDetails(
        id: "115565004607949429",
        league: LeagueRef(id: "98767991299243165", slug: "lcs", name: "LCS", image: nil),
        match: EventDetails.Match(
            strategy: Strategy(type: nil, count: bestOf),
            teams: zip(teams, wins).map { team, win in makeTeam(team.code, id: team.id, wins: win) },
            games: games.map { GameRef(number: $0.number, id: $0.id, state: $0.state, teams: nil) }
        ),
        streams: []
    )
}

/// Équipe active du catalogue de fixtures (`getTeams`), par code.
func catalogTeam(_ code: String) throws -> Team {
    let teams = try JSONDecoder.lolesports()
        .decode(TeamsResponse.self, from: Fixture.data("getTeams")).data.teams.elements
    guard let team = teams.first(where: { $0.code == code && $0.isActive }) else {
        throw Fixture.Missing(name: "équipe \(code)")
    }
    return team
}
