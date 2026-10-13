import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Accès réseau, remplaçable dans les tests.
public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
}

/// Transport réel. Utilise `dataTask` (disponible partout, y compris Linux) ; annuler la `Task` appelante
/// annule la requête (`URLError.cancelled`).
public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let finalRequest = request
        return try await CancellableCall.run { completion in
            let task = URLSession.shared.dataTask(with: finalRequest) { data, response, error in
                if let error {
                    completion(.failure(error))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion(.success(HTTPResponse(status: status, body: data ?? Data())))
            }
            task.resume()
            return { task.cancel() }
        }
    }
}
