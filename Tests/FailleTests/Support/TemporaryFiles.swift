import Foundation
@testable import Faille

/// Dossiers temporaires pour les tests qui touchent au disque : un dossier neuf par appel.
enum TemporaryFiles {
    static func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("faille-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func store() -> FileStore {
        FileStore(directory: directory())
    }
}
