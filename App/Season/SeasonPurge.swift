import Foundation
import LoLKit

/// Purge des caches du Détail hors périmètre (spec périmètre §3.3), une fois par fenêtre : `replays/<gameId>.json`
/// (`firstFrame`), `details/<gameId>.json` (`details.frames[0].rfc460Timestamp`), `spells/<matchId>.json` (plus récent
/// `openings[*].start`) ; supprimé si la date lue est avant `window.startDate`, **gardé** si elle est illisible ou absente.
/// Le marqueur `season/window.json` n'est écrit qu'après la purge : une purge interrompue est refaite (idempotente).
/// Jamais `FileStore` (suivis, réglages, révélations, Live Activities) : seulement des chemins de `DiskCache`.
struct SeasonPurge: Sendable {
    static let markerPath = "season/window.json"

    struct Marker: Codable, Equatable, Sendable {
        let v: Int
        let startDay: String
    }

    let cache: DiskCache

    /// Purge si le marqueur manque ou date d'une autre fenêtre ; rend le nombre de fichiers du Détail lus (0 sinon).
    func run(window: SeasonWindow) -> Int {
        let marker = Marker(v: 1, startDay: window.startDay)
        guard cache.load(Marker.self, from: Self.markerPath) != marker else { return 0 }
        var read = 0
        let probes: [(folder: String, date: @Sendable (Data) -> Date?)] = [
            ("replays", Self.replayDate), ("details", Self.detailsDate), ("spells", Self.spellsDate),
        ]
        for probe in probes {
            for url in files(in: probe.folder) {
                read += 1
                guard let data = try? Data(contentsOf: url), let date = probe.date(data) else { continue }
                if !window.contains(date: date) { try? FileManager.default.removeItem(at: url) }
            }
        }
        cache.save(marker, to: Self.markerPath)
        return read
    }

    private struct ReplayProbe: Decodable { let firstFrame: Date }
    private struct DetailsProbe: Decodable {
        struct Frame: Decodable { let rfc460Timestamp: Date }
        struct Details: Decodable { let frames: [Frame] }
        let details: Details
    }
    private struct SpellsProbe: Decodable {
        struct Opening: Decodable { let start: Date }
        let openings: [String: Opening]
    }

    /// Dates encodées par `JSONEncoder()` par défaut (secondes depuis 2001), comme `DiskCache.save`.
    static func replayDate(_ data: Data) -> Date? {
        (try? JSONDecoder().decode(ReplayProbe.self, from: data))?.firstFrame
    }

    static func detailsDate(_ data: Data) -> Date? {
        (try? JSONDecoder().decode(DetailsProbe.self, from: data))?.details.frames.first?.rfc460Timestamp
    }

    static func spellsDate(_ data: Data) -> Date? {
        (try? JSONDecoder().decode(SpellsProbe.self, from: data))?.openings.values.map(\.start).max()
    }

    private func files(in folder: String) -> [URL] {
        guard let url = cache.url(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))
        else { return [] }
        return names.filter { $0.hasSuffix(".json") }.map { url.appendingPathComponent($0) }
    }
}
