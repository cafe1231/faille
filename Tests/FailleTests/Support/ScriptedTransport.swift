import Foundation
import LoLKit

/// Faux réseau dont le comportement change en cours de test et qui garde la liste des requêtes reçues.
/// Par défaut il répond comme `StubTransport` ; `extra` peut fournir d'autres réponses (un logo, par exemple).
actor ScriptedTransport: HTTPTransport {
    enum Mode: Sendable {
        /// Réponses de `StubTransport` (ou de `extra`).
        case ok
        /// 503 partout.
        case failing
        /// Requête annulée comme le fait le vrai réseau : `URLError(.cancelled)`.
        case urlCancelled
        /// Requête annulée comme dans les tests : `CancellationError`.
        case swiftCancelled
    }

    private(set) var requests: [URL] = []
    private var mode: Mode
    private let delay: Duration
    private let extra: @Sendable (URL) -> HTTPResponse?

    init(mode: Mode = .ok, delay: Duration = .zero, extra: @escaping @Sendable (URL) -> HTTPResponse? = { _ in nil }) {
        self.mode = mode
        self.delay = delay
        self.extra = extra
    }

    func setMode(_ newMode: Mode) {
        mode = newMode
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append(url)
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        switch mode {
        case .urlCancelled:
            throw URLError(.cancelled)
        case .swiftCancelled:
            throw CancellationError()
        case .failing:
            return HTTPResponse(status: 503, body: Data())
        case .ok:
            if let response = extra(url) {
                return response
            }
            return try await StubTransport().get(url, headers: headers)
        }
    }
}
