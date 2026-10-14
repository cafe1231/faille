import Foundation
import LoLKit

/// Horloge de la collecte de saison (spec saison §1.6) : l'heure et les attentes entre deux requêtes. L'appli prend celle du
/// système ; les tests une horloge virtuelle, qui avance d'un coup (aucune vraie attente).
protocol CrawlClock: Sendable {
    func now() async -> Date
    func sleep(seconds: TimeInterval) async throws
}

struct SystemCrawlClock: CrawlClock {
    func now() async -> Date {
        Date()
    }

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Fin de la collecte de la session : budget de requêtes épuisé, ou trop d'échecs d'affilée (spec saison §1.6).
struct CrawlStopped: Error, Equatable, Sendable {
    let reason: CrawlPacer.StopReason
}

/// Transport de la collecte de saison : TOUTES ses requêtes (énumération, paliers A et B, classement ou page de calendrier
/// ouverts à la demande) passent par lui, une à la fois et dans l'ordre d'arrivée, au rythme de `CrawlPacer` : 2 s entre
/// deux requêtes, recul de 4, 8, 16, 32 puis 60 s après un 429, un 5xx ou une erreur réseau, arrêt après 5 échecs
/// d'affilée ou 300 requêtes dans la session. Le rythme vaut aussi pour les reculs internes de `LoLClient.liveWindow` (un
/// 400 « en avance sur la diffusion ») : c'est le transport, pas l'appelant, qui attend. L'attente se compte depuis la
/// RÉPONSE de la requête précédente : deux débuts de requête sont toujours séparés d'au moins 2 s.
actor PacedTransport: HTTPTransport {
    private let base: any HTTPTransport
    private let clock: any CrawlClock
    private var pacer = CrawlPacer()
    private var nextAllowed: Date?
    private var stopped: CrawlPacer.StopReason?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Requêtes envoyées dans la session.
    private(set) var sent = 0
    /// Heure (de l'horloge) du départ de chaque requête de la session : tests de cadence.
    private(set) var sentAt: [Date] = []
    /// Requêtes à la demande (classement, page de calendrier) envoyées APRÈS l'épuisement du budget de la collecte : petite
    /// réserve à part (`onDemandBudget`), comptée et cadencée comme les autres.
    private(set) var reserveSent = 0
    /// Réserve par session pour les écrans, une fois le budget de la collecte épuisé.
    static let onDemandBudget = 20
    /// Numéro de session : une réponse arrivée après `beginSession()` ne touche ni le rythme ni l'arrêt de la nouvelle.
    private var generation = 0

    init(base: any HTTPTransport, clock: any CrawlClock) {
        self.base = base
        self.clock = clock
    }

    /// Nouvelle session au premier plan : budget, recul et arrêt remis à zéro.
    func beginSession() {
        pacer = CrawlPacer()
        nextAllowed = nil
        stopped = nil
        sent = 0
        sentAt = []
        reserveSent = 0
        generation += 1
    }

    /// La collecte de cette session est finie (budget, échecs) : plus aucune requête jusqu'à la suivante.
    var stopReason: CrawlPacer.StopReason? {
        stopped
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send(url, headers: headers, onDemand: false)
    }

    /// Requête d'un écran (classement, page de calendrier) : même porte et même cadence ; l'arrêt `.budget` de la
    /// collecte ne la bloque pas, dans la limite de la réserve `onDemandBudget`. Un arrêt `.failures` la bloque.
    func getOnDemand(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send(url, headers: headers, onDemand: true)
    }

    private func send(_ url: URL, headers: [String: String], onDemand: Bool) async throws -> HTTPResponse {
        await acquire()
        defer { release() }
        var useReserve = false
        if let stopped {
            guard onDemand, stopped == .budget else { throw CrawlStopped(reason: stopped) }
            useReserve = true
        } else if sent >= CrawlPacer.sessionRequestBudget {
            guard onDemand else {
                stopped = .budget
                throw CrawlStopped(reason: .budget)
            }
            useReserve = true
        }
        if useReserve, reserveSent >= Self.onDemandBudget { throw CrawlStopped(reason: .budget) }
        if let nextAllowed {
            let wait = nextAllowed.timeIntervalSince(await clock.now())
            if wait > 0 { try await clock.sleep(seconds: wait) }
        }
        try Task.checkCancellation()
        let session = generation
        if useReserve { reserveSent += 1 } else { sent += 1 }
        sentAt.append(await clock.now())
        do {
            let response = try await base.get(url, headers: headers)
            // Même règle que `CrawlPacer.outcome(of:)` : 429 et 5xx reculent ; toute autre réponse (200, 204, 400, 404…)
            // est une réponse.
            let retryable = response.status == 429 || response.status >= 500
            if session == generation { await apply(pacer.next(after: retryable ? .retryable : .answered), session: session) }
            return response
        } catch {
            if Self.isCancellation(error) {
                // Scène quittée : ni échec ni recul ; la prochaine requête (prochaine session) attendra le pas normal.
                let resume = await clock.now().addingTimeInterval(CrawlPacer.baseInterval)
                if session == generation { nextAllowed = resume }
                throw error
            }
            if session == generation { await apply(pacer.next(after: .retryable), session: session) }
            throw error
        }
    }

    /// Applique une décision du rythme, sauf si la session a changé pendant la requête (`beginSession`).
    private func apply(_ decision: CrawlPacer.Decision, session: Int) async {
        let now = await clock.now()
        guard session == generation else { return }
        switch decision {
        case let .wait(seconds):
            nextAllowed = now.addingTimeInterval(seconds)
        case let .stop(reason):
            stopped = reason
        }
    }

    /// Une requête à la fois : les appelants suivants attendent leur tour, dans l'ordre.
    private func acquire() async {
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    static func isCancellation(_ error: any Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// Transport des écrans (classement ouvert, page de calendrier) : même `PacedTransport`, mais par la réserve à la demande
/// (`getOnDemand`) qui survit à l'arrêt `.budget` de la collecte.
struct OnDemandTransport: HTTPTransport {
    let paced: PacedTransport

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await paced.getOnDemand(url, headers: headers)
    }
}
