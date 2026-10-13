import Foundation
import Testing
@testable import LoLKit

/// Fausse opération à rappel : ne répond jamais d'elle-même, seulement quand on l'annule.
private final class PendingCall: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<Int, any Error>) -> Void)?
    private var cancels = 0

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cancels
    }

    func start(_ completion: @escaping @Sendable (Result<Int, any Error>) -> Void) -> () -> Void {
        lock.lock()
        self.completion = completion
        lock.unlock()
        return { self.cancel() }
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

    @Test func cancellingTheTaskCancelsTheCall() async {
        let call = PendingCall()
        let task = Task { try await CancellableCall.run(call.start) }
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(call.cancelCount == 1)
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
}
