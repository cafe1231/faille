import Foundation
@testable import LoLKit

/// Faux réseau : renvoie la réponse de la première route dont le fragment apparaît dans l'URL.
actor FakeTransport: HTTPTransport {
    private var routes: [(fragment: String, response: HTTPResponse)] = []
    private(set) var requests: [(url: URL, headers: [String: String])] = []

    func on(_ fragment: String, status: Int = 200, fixture: String? = nil, body: String = "") throws {
        let data = try fixture.map { try Fixture.data($0) } ?? Data(body.utf8)
        routes.append((fragment, HTTPResponse(status: status, body: data)))
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        requests.append((url, headers))
        return routes.first { url.absoluteString.contains($0.fragment) }?.response
            ?? HTTPResponse(status: 599, body: Data())
    }
}

/// Valeur d'un paramètre de requête d'une URL.
func queryValue(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}
