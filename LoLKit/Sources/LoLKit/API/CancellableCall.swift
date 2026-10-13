import Foundation

/// Relie l'annulation d'une `Task` Swift à une opération à rappel (comme `URLSessionDataTask`).
/// Sans ce lien, annuler la boucle de rafraîchissement laisse la requête aller jusqu'à son délai (15 s).
public enum CancellableCall {
    /// - Parameter start: lance l'opération, qui appellera `completion` une seule fois, et renvoie de quoi l'annuler.
    ///   L'annulation doit elle aussi aboutir à un appel de `completion` (en erreur).
    public static func run<T: Sendable>(
        _ start: (_ completion: @escaping @Sendable (Result<T, any Error>) -> Void) -> () -> Void
    ) async throws -> T {
        let canceller = Canceller()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                let cancel = start { result in continuation.resume(with: result) }
                canceller.install(cancel)
            }
        } onCancel: {
            canceller.cancel()
        }
    }
}

/// Garde l'action d'annulation. Si l'annulation arrive avant l'installation (tâche déjà annulée),
/// l'action est exécutée dès qu'elle est installée. Elle ne s'exécute jamais deux fois.
final class Canceller: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (() -> Void)?

    func install(_ action: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            action()
        } else {
            self.action = action
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let action = self.action
        self.action = nil
        lock.unlock()
        action?()
    }
}
