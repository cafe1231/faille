import Foundation
import Testing
@testable import LoLKit

/// Fausse opération à rappel : ne répond jamais d'elle-même, seulement quand on l'annule.
private final class PendingCall: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Int, any Error>) -> Void)?
    private var cancels = 0
    private var started = false

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancels
    }

    /// Vrai dès que `CancellableCall.run` a lancé l'opération (signal pour les tests « en vol »).
    var isStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    func start(_ completion: @escaping @Sendable (Result<Int, any Error>) -> Void) -> () -> Void {
        lock.lock()
        self.completion = completion
        started = true
        lock.unlock()
        return { self.cancel() }
    }

    /// Termine l'opération d'elle-même (sans annulation). Sans effet si elle a déjà répondu.
    func finish(_ value: Int) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(.success(value))
    }

    private func cancel() {
        lock.lock()
        cancels += 1
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(.failure(CancellationError()))
    }
}

/// Attend (au plus ~5 s, pour ne jamais bloquer) que l'opération soit lancée.
private func waitUntilStarted(_ call: PendingCall) async -> Bool {
    for _ in 0..<5_000 {
        if call.isStarted { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
    return call.isStarted
}

/// Compte combien de fois une action est exécutée.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

@Suite struct CancellableCallTests {
    @Test func returnsTheResult() async throws {
        let value: Int = try await CancellableCall.run { completion in
            completion(.success(42))
            return {}
        }
        #expect(value == 42)
    }

    @Test func forwardsErrors() async {
        await #expect(throws: LoLAPIError.noData) {
            let _: Int = try await CancellableCall.run { completion in
                completion(.failure(LoLAPIError.noData))
                return {}
            }
        }
    }

    /// Annulation EN VOL : on attend que l'opération soit lancée avant d'annuler la tâche.
    @Test func cancellingTheTaskCancelsTheCall() async {
        let call = PendingCall()
        let task = Task { try await CancellableCall.run(call.start) }
        let started = await waitUntilStarted(call)
        #expect(started)
        #expect(call.cancelCount == 0) // rien n'a encore annulé : l'opération est bien en vol
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(call.cancelCount == 1)
    }

    /// L'opération répond d'abord ; une annulation tardive ne change pas le résultat (une seule réponse).
    @Test func lateCancellationKeepsTheFirstResult() async throws {
        let call = PendingCall()
        let task = Task { try await CancellableCall.run(call.start) }
        let started = await waitUntilStarted(call)
        #expect(started)
        call.finish(7)
        task.cancel()
        let value = try await task.value
        #expect(value == 7)
    }

    @Test func alreadyCancelledTaskCancelsAtOnce() async {
        let call = PendingCall()
        let task = Task {
            try? await Task.sleep(for: .seconds(30)) // se termine dès l'annulation
            return try await CancellableCall.run(call.start)
        }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(call.cancelCount == 1)
    }

    // `Canceller` seul : les deux ordres possibles, sans aucune course.
    @Test func cancellerRunsAnInstalledActionOnce() {
        let counter = Counter()
        let canceller = Canceller()
        canceller.install { counter.increment() }
        #expect(counter.value == 0)
        canceller.cancel()
        canceller.cancel()
        #expect(counter.value == 1)
    }

    @Test func cancellerRunsALateInstalledActionOnce() {
        let counter = Counter()
        let canceller = Canceller()
        canceller.cancel()
        #expect(counter.value == 0)
        canceller.install { counter.increment() }
        #expect(counter.value == 1)
        canceller.cancel()
        #expect(counter.value == 1)
    }
}
