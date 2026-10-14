import Foundation

public enum LeaguepediaError: Error, Equatable, Sendable {
    /// Réponse HTTP inattendue.
    case http(status: Int)
    /// Le wiki limite les requêtes anonymes (vu le 14/10/2026 : réponse 200 avec `error.code == "ratelimited"`, levée au
    /// bout de quelques minutes). Réessayer plus tard, jamais en boucle.
    case rateLimited
    /// Autre erreur de l'API MediaWiki (`error.code`).
    case api(code: String)
}

/// Client de Leaguepedia (`lol.fandom.com`, API Cargo, sans clé) pour les sorts d'invocateur des games terminées, absents
/// du flux de Riot (spec fonctionnalités §3). Une requête par game au plus : l'appli met la réponse en cache disque.
public struct LeaguepediaClient: Sendable {
    /// User-Agent identifiable demandé par le wiki.
    public static let userAgent = "Faille (usage personnel)"
    static let endpoint = "https://lol.fandom.com/api.php"

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Sorts d'invocateur d'une game terminée, par champion : `champions` = ids Data Dragon du flux (les 10 de la game),
    /// `start` = début de la game. Réponse : ids Data Dragon des sorts (« SummonerFlash ») par id de champion ; nil si le
    /// wiki n'a pas (encore) la game.
    public func summonerSpells(champions: [String], around start: Date) async throws -> [String: [String]]? {
        SpellMatcher.match(champions: champions, around: start, rows: try await scoreboard(around: start))
    }

    /// Lignes `ScoreboardPlayers` des games commencées à ± 3 h de `start` (une seule requête, 500 lignes au plus).
    public func scoreboard(around start: Date) async throws -> [ScoreboardRow] {
        let response = try await transport.get(Self.scoreboardURL(around: start), headers: ["User-Agent": Self.userAgent])
        guard response.status == 200 else { throw LeaguepediaError.http(status: response.status) }
        let body = try JSONDecoder().decode(CargoResponse.self, from: response.body)
        if let error = body.error {
            throw error.code == "ratelimited" ? LeaguepediaError.rateLimited : LeaguepediaError.api(code: error.code)
        }
        return (body.cargoquery ?? []).compactMap { $0.value?.title.row }
    }

    /// Requête Cargo : `ScoreboardPlayers`, champs `GameId,Link,Champion,SummonerSpells,DateTime_UTC`, games commencées
    /// entre `start - 3 h` et `start + 3 h` (heure UTC à la seconde).
    static func scoreboardURL(around start: Date) -> URL {
        let from = cargoDate(start.addingTimeInterval(-SpellMatcher.window))
        let to = cargoDate(start.addingTimeInterval(SpellMatcher.window))
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "action", value: "cargoquery"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "tables", value: "ScoreboardPlayers"),
            URLQueryItem(name: "fields", value: "GameId,Link,Champion,SummonerSpells,DateTime_UTC"),
            URLQueryItem(name: "where", value: "DateTime_UTC >= '\(from)' AND DateTime_UTC <= '\(to)'"),
            URLQueryItem(name: "limit", value: "500"),
        ]
        return components.url!
    }

    /// « 2026-10-04 17:18:26 » (UTC), le format des dates Cargo.
    static func cargoDate(_ date: Date) -> String {
        let iso = LoLDate.format(date) // 2026-10-04T17:18:26.892Z
        return String(iso.prefix(19)).replacingOccurrences(of: "T", with: " ")
    }

    /// « 2026-10-04 20:18:00 » (UTC) → date ; nil si illisible.
    static func parseCargoDate(_ string: String) -> Date? {
        LoLDate.parse(string.replacingOccurrences(of: " ", with: "T") + "Z")
    }
}

/// Réponse de `action=cargoquery` : des lignes `{"title": {...}}`, ou une erreur MediaWiki.
private struct CargoResponse: Decodable {
    struct Entry: Decodable {
        let title: Title
    }

    struct Title: Decodable {
        let gameId: String?
        let link: String?
        let champion: String?
        let summonerSpells: String?
        let dateTime: String?

        enum CodingKeys: String, CodingKey {
            case gameId = "GameId", link = "Link", champion = "Champion", summonerSpells = "SummonerSpells"
            case dateTime = "DateTime UTC"
        }

        /// Ligne utilisable : game et champion connus.
        var row: ScoreboardRow? {
            guard let gameId, !gameId.isEmpty, let champion, !champion.isEmpty else { return nil }
            let spells = (summonerSpells ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return ScoreboardRow(gameId: gameId, link: link, champion: champion, summonerSpells: spells,
                                 dateTime: dateTime.flatMap(LeaguepediaClient.parseCargoDate))
        }
    }

    struct APIError: Decodable {
        let code: String
    }

    let cargoquery: [Lenient<Entry>]?
    let error: APIError?
}

/// Ligne décodée si possible, sinon nil : une ligne illisible n'empêche pas de lire les autres.
private struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
