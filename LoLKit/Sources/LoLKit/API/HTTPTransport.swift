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

    /// Requête GET de l'API. Pas de cache HTTP : LoLKit a son propre cache disque, et une réponse `getLive` servie par le
    /// cache d'URLSession masquerait le mode avion (la panne ne remonterait jamais).
    static func makeRequest(_ url: URL, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        let finalRequest = Self.makeRequest(url, headers: headers)
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
