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
    }

    /// La collecte de cette session est finie (budget, échecs) : plus aucune requête jusqu'à la suivante.
    var stopReason: CrawlPacer.StopReason? {
        stopped
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        await acquire()
        defer { release() }
        if let stopped { throw CrawlStopped(reason: stopped) }
        guard sent < CrawlPacer.sessionRequestBudget else {
            stopped = .budget
            throw CrawlStopped(reason: .budget)
        }
        if let nextAllowed {
            let wait = nextAllowed.timeIntervalSince(await clock.now())
            if wait > 0 { try await clock.sleep(seconds: wait) }
        }
        try Task.checkCancellation()
        sent += 1
        sentAt.append(await clock.now())
        do {
            let response = try await base.get(url, headers: headers)
            // Même règle que `CrawlPacer.outcome(of:)` : 429 et 5xx reculent ; toute autre réponse (200, 204, 400, 404…)
            // est une réponse.
            let retryable = response.status == 429 || response.status >= 500
            await apply(pacer.next(after: retryable ? .retryable : .answered))
            return response
        } catch {
            if Self.isCancellation(error) {
                // Scène quittée : ni échec ni recul ; la prochaine requête (prochaine session) attendra le pas normal.
                nextAllowed = await clock.now().addingTimeInterval(CrawlPacer.baseInterval)
                throw error
            }
            await apply(pacer.next(after: .retryable))
            throw error
        }
    }

    private func apply(_ decision: CrawlPacer.Decision) async {
        switch decision {
        case let .wait(seconds):
            nextAllowed = await clock.now().addingTimeInterval(seconds)
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
