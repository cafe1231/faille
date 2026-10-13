import Foundation

extension JSONDecoder {
    /// Décodeur des réponses lolesports : dates ISO 8601 avec ou sans fractions de seconde.
    public static func lolesports() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = LoLDate.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date ISO 8601 invalide : \(string)")
        }
        return decoder
    }
}

/// Lecture et écriture des dates ISO 8601 de l'API.
public enum LoLDate {
    public static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Format attendu par `startingTime` du flux livestats : `2026-10-04T20:38:20.000Z`.
    public static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Tableau tolérant : un élément illisible est ignoré au lieu de faire échouer tout le décodage.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.elements = elements
    }

    /// Consomme un élément sans le lire, pour avancer dans le tableau.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}
