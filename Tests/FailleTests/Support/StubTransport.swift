import Foundation
import LoLKit

/// Faux réseau pour les tests du store : réponses JSON minimales de l'API (deux ligues, deux équipes, un match),
/// ou 503 partout (`failing`). Logos et flux `window` : 404.
struct StubTransport: HTTPTransport {
    var failing = false

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        guard !failing else { return HTTPResponse(status: 503, body: Data()) }
        let path = url.path(percentEncoded: false)
        let body: String
        if path.hasSuffix("/getLeagues") {
            body = Self.leagues
        } else if path.hasSuffix("/getTeams") {
            body = Self.teams
        } else if path.hasSuffix("/getSchedule") {
            body = Self.schedule
        } else if path.hasSuffix("/getLive") {
            body = Self.live
        } else {
            return HTTPResponse(status: 404, body: Data())
        }
        return HTTPResponse(status: 200, body: Data(body.utf8))
    }

    static let leagues = #"{"data":{"leagues":[{"id":"98767975604431411","slug":"worlds","name":"Mondial","region":"INTERNATIONAL","priority":1},{"id":"98767991302996019","slug":"lec","name":"LEC","region":"EMEA","priority":1}]}}"#

    static let teams = #"{"data":{"teams":[{"id":"111692118851466302","slug":"karmine-corp","name":"Karmine Corp","code":"KC","image":"http://static.lolesports.com/teams/1704714951336_KC.png","status":"active","homeLeague":{"name":"LEC","region":"EMEA"}},{"id":"98767991853197861","slug":"g2-esports","name":"G2 Esports","code":"G2","image":"http://static.lolesports.com/teams/G2-FullonDark.png","status":"active","homeLeague":{"name":"LEC","region":"EMEA"}}]}}"#

    static let schedule = #"{"data":{"schedule":{"events":[{"startTime":"2026-10-20T16:00:00Z","state":"unstarted","type":"match","blockName":"Quarts de finale","league":{"name":"Mondial","slug":"worlds"},"match":{"id":"300","teams":[{"name":"Karmine Corp","code":"KC","result":{"outcome":null,"gameWins":0}},{"name":"G2 Esports","code":"G2","result":{"outcome":null,"gameWins":0}}],"strategy":{"type":"bestOf","count":5}}}]}}}"#

    static let live = #"{"data":{"schedule":{"events":[]}}}"#
}
