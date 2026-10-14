import Foundation
import LoLKit
import Observation

/// Ce que Faille garde sur disque pour les sorts d'invocateur d'un match (`spells/<matchId>.json`).
struct SpellRecord: Codable, Sendable, Equatable {
    /// Début et champions d'une game (fenêtre du flux lue sans `startingTime`) : ce qui la retrouve dans Leaguepedia.
    struct Opening: Codable, Sendable, Equatable {
        let start: Date
        /// Ids Data Dragon des 10 champions de la game.
        let champions: [String]
    }

    var policy = SpellLookupPolicy()
    var openings: [String: Opening] = [:]
    /// Sorts trouvés, par game puis par champion.
    var spells: [String: [String: [String]]] = [:]
    /// Games dont le flux n'a pas de stats (404 ou vide) : sans début ni champions, elles ne peuvent pas être retrouvées
    /// dans Leaguepedia. Elles sont laissées de côté (ni requête, ni critère de succès) et jamais redemandées.
    var skipped: Set<String> = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case policy, openings, spells, skipped
    }

    /// Décodage tolérant (spec §4.2) : un champ absent ou illisible prend sa valeur neutre, les autres sont gardés.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        policy = (try? container.decodeIfPresent(SpellLookupPolicy.self, forKey: .policy)) ?? SpellLookupPolicy()
        openings = (try? container.decodeIfPresent([String: Opening].self, forKey: .openings)) ?? [:]
        spells = (try? container.decodeIfPresent([String: [String: [String]]].self, forKey: .spells)) ?? [:]
        skipped = (try? container.decodeIfPresent(Set<String>.self, forKey: .skipped)) ?? []
    }
}

/// Sorts d'invocateur des games terminées (spec fonctionnalités §3), absents du flux de Riot : une seule requête
/// Leaguepedia par match pour toutes ses games, rapprochées par `SpellMatcher` (mêmes 10 champions, ± 3 h), sous la règle
/// stricte de `SpellSchedule` (Leaguepedia limite fortement les requêtes anonymes). Tout est gardé sur disque.
/// Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué, ni pour un match qui n'est pas terminé.
@MainActor
@Observable
final class SummonerSpellsStore {
    /// Sorts par game puis par champion (id Data Dragon du flux) : ids Data Dragon des sorts (« SummonerFlash »).
    private(set) var spells: [String: [String: [String]]] = [:]

    private let client: LoLClient?
    private let wiki: LeaguepediaClient?
    private let cache: DiskCache?
    @ObservationIgnored private var running: Set<String> = []

    /// - Parameters:
    ///   - transport: réseau (flux livestats et Leaguepedia) ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil : rien n'est gardé (et la règle repart de zéro à chaque lancement).
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        client = transport.map { LoLClient(transport: $0) }
        wiki = transport.map { LeaguepediaClient(transport: $0) }
        self.cache = cache
    }

    /// Aperçus : sorts figés, aucune requête.
    init(preview spells: [String: [String: [String]]]) {
        client = nil
        wiki = nil
        cache = nil
        self.spells = spells
    }

    /// Sorts d'un champion dans une game terminée ; nil s'ils ne sont pas (encore) connus.
    func spells(gameId: String, championId: String) -> [String]? {
        spells[gameId]?[championId]
    }

    /// Sorts des games jouées d'un match terminé. Rien si toutes sont déjà connues (ou laissées de côté). Sinon, si la règle
    /// le permet : le début et les champions de chaque game (flux, une fois par game), puis UNE requête Leaguepedia
    /// centrée sur le match, notée dans la règle (succès seulement si toutes les games sont trouvées ; un refus du wiki est
    /// noté comme tel). Les sorts trouvés sont gardés même si d'autres games manquent. Une game dont le flux n'a pas de
    /// stats (404 ou vide) est laissée de côté : hors de la requête et du critère de succès, jamais redemandée.
    /// - Parameters:
    ///   - gameIds: games jouées du match (`completed`).
    ///   - matchEnd: frame `finished` de sa dernière game, si l'appli l'a ; sinon fin estimée (`SpellSchedule`).
    func lookUp(matchId: String, gameIds: [String], matchEnd: Date?, now: Date = Date()) async {
        guard !gameIds.isEmpty, !running.contains(matchId) else { return }
        running.insert(matchId)
        defer { running.remove(matchId) }
        var record = cache?.load(SpellRecord.self, from: Self.path(matchId)) ?? SpellRecord()
        publish(record)
        guard let client, let wiki, gameIds.contains(where: { record.spells[$0] == nil && !record.skipped.contains($0) })
        else { return }
        // La règle d'abord : aucune requête (même au flux) si un essai n'est pas permis.
        let knownEarliest = matchEnd.map { $0.addingTimeInterval(SpellSchedule.delayAfterEnd) } ?? .distantPast
        guard SpellSchedule.mayAttempt(record.policy, earliest: knownEarliest, now: now) else { return }
        for gameId in gameIds where record.openings[gameId] == nil && !record.skipped.contains(gameId) {
            let opening: LiveWindow
            do {
                opening = try await client.window(gameId: gameId, startingTime: nil)
            } catch LoLAPIError.statsDisabled, LoLAPIError.noData {
                // Riot n'a pas de stats pour cette game seule (remake, stats coupées) : on la laisse de côté.
                record.skipped.insert(gameId)
                cache?.save(record, to: Self.path(matchId))
                continue
            } catch {
                // Réseau, HTTP, annulation : on s'arrête là, la suite repart de ce qui est gardé.
                return
            }
            guard let start = opening.firstFrameTime else { return }
            let metadata = opening.gameMetadata
            let champions = (metadata.blueTeamMetadata.participantMetadata
                + metadata.redTeamMetadata.participantMetadata).compactMap(\.championId)
            record.openings[gameId] = SpellRecord.Opening(start: start, champions: champions)
            cache?.save(record, to: Self.path(matchId))
        }
        let wanted = gameIds.filter { !record.skipped.contains($0) }
        let starts = wanted.compactMap { record.openings[$0]?.start }
        guard let lastStart = starts.max(), let center = SpellSchedule.center(of: starts),
              SpellSchedule.mayAttempt(record.policy,
                                       earliest: SpellSchedule.earliestAttempt(matchEnd: matchEnd, lastGameStart: lastStart),
                                       now: now) else { return }
        let outcome: SpellLookupPolicy.Outcome
        do {
            let rows = try await wiki.scoreboard(around: center)
            for gameId in wanted {
                guard let opening = record.openings[gameId],
                      let found = SpellMatcher.match(champions: opening.champions, around: opening.start, rows: rows)
                else { continue }
                record.spells[gameId] = found
            }
            outcome = wanted.allSatisfy { record.spells[$0] != nil } ? .success : .failure
        } catch LeaguepediaError.rateLimited {
            outcome = .rateLimited
        } catch {
            // Réseau, HTTP, API, ou requête annulée après son envoi : un essai compté, jamais de boucle.
            outcome = .failure
        }
        record.policy.record(now: now, outcome: outcome)
        cache?.save(record, to: Self.path(matchId))
        publish(record)
    }

    private func publish(_ record: SpellRecord) {
        for (gameId, found) in record.spells {
            spells[gameId] = found
        }
    }

    static func path(_ matchId: String) -> String {
        "spells/\(matchId).json"
    }
}
