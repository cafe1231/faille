import Foundation
import LoLKit
import Observation

/// Détails d'une game gardés sur disque (`details/<gameId>.json`) : la dernière frame, et si la game était terminée.
struct SavedDetails: Codable, Sendable, Equatable {
    let details: GameDetails
    /// Lus après la fin de la game : définitifs, plus jamais redemandés.
    let isFinal: Bool
}

/// Détails par joueur d'une game (`livestats/v1/details`, spec fonctionnalités §3) : objets, runes, ordre des sorts, part
/// des dégâts, participation, balises. Lourd (~200 Ko par lecture) : relu toutes les 60 s (`LoLClient.detailsInterval`)
/// tant que le Détail d'une game en cours est affiché, une seule fois pour une game terminée ; la dernière frame est
/// gardée sur disque. Anti-spoiler : l'appli ne l'appelle jamais pour un match masqué.
@MainActor
@Observable
final class GameDetailsStore {
    /// Dernière frame connue de chaque game.
    private(set) var details: [String: GameDetails] = [:]
    /// Games dont Riot ne fournit pas les stats (404) : plus aucune requête.
    private(set) var unavailable: Set<String> = []

    private let client: LoLClient?
    private let cache: DiskCache?
    @ObservationIgnored private var finalGames: Set<String> = []

    /// - Parameters:
    ///   - transport: réseau ; nil (aperçus) : aucune requête.
    ///   - cache: cache disque ; nil : rien n'est gardé.
    init(transport: (any HTTPTransport)?, cache: DiskCache?) {
        client = transport.map { LoLClient(transport: $0) }
        self.cache = cache
    }

    /// Aperçus : détails figés, aucune requête.
    init(preview details: [String: GameDetails]) {
        client = nil
        cache = nil
        self.details = details
        finalGames = Set(details.keys)
    }

    /// Une lecture. Le disque d'abord (une game terminée déjà lue après sa fin n'est plus jamais demandée), puis le flux
    /// avec le recul de 80 s partagé avec `window` (`LoLClient.details(gameId:now:)`) ; seule la dernière frame est gardée.
    /// - Parameter finished: la game est terminée : ce qui sera lu est définitif.
    func refresh(gameId: String, finished: Bool, now: Date = Date()) async {
        guard !unavailable.contains(gameId) else { return }
        if !finalGames.contains(gameId), details[gameId] == nil || finished,
           let saved = cache?.load(SavedDetails.self, from: Self.path(gameId)) {
            details[gameId] = saved.details
            if saved.isFinal { finalGames.insert(gameId) }
        }
        guard let client, !finalGames.contains(gameId) else { return }
        do {
            guard let frame = try await client.details(gameId: gameId, now: now).latestFrame else { return }
            let kept = GameDetails(frames: [frame])
            details[gameId] = kept
            if finished { finalGames.insert(gameId) }
            cache?.save(SavedDetails(details: kept, isFinal: finished), to: Self.path(gameId))
        } catch LoLAPIError.statsDisabled {
            unavailable.insert(gameId)
        } catch {
            // Réseau, flux vide, annulation : on garde ce qu'on a ; nouvel essai au tour suivant.
        }
    }

    /// Tant que la tâche vit (Détail affiché) : une lecture, puis, si la game est en cours, une toutes les 60 s.
    func follow(gameId: String, finished: Bool) async {
        await refresh(gameId: gameId, finished: finished)
        guard !finished else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(LoLClient.detailsInterval))
            guard !Task.isCancelled else { return }
            await refresh(gameId: gameId, finished: false)
        }
    }

    static func path(_ gameId: String) -> String {
        "details/\(gameId).json"
    }
}
