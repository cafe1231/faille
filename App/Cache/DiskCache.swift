import Foundation

/// Cache disque des fonctionnalités (spec fonctionnalités, « Sobriété réseau ») : images et données Data Dragon
/// (`ddragon/…`), détails des games (`details/…`), relectures du flux (`replays/…`), sorts d'invocateur (`spells/…`).
/// Un dossier racine — `cache/` à côté des fichiers de Faille —, exclu de la sauvegarde iCloud : tout s'y retrouve par le
/// réseau. Chemins relatifs « a/b/c.json » ; un chemin qui tenterait d'en sortir (« .. ») est refusé. JSON en
/// `JSONEncoder()` / `JSONDecoder()` par défaut (dates en secondes depuis 2001), comme `FileStore`. Un fichier illisible
/// est simplement ignoré : la donnée sera relue sur le réseau.
struct DiskCache: Sendable {
    let root: URL

    init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    /// Chemin relatif sûr : composants non vides, sans « . » ni « .. » ; nil s'il ne reste rien ou s'il sort du dossier.
    static func safePath(_ path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        return parts.joined(separator: "/")
    }

    func url(_ path: String) -> URL? {
        Self.safePath(path).map { root.appendingPathComponent($0, isDirectory: false) }
    }

    func data(_ path: String) -> Data? {
        url(path).flatMap { try? Data(contentsOf: $0) }
    }

    func write(_ data: Data, to path: String) {
        guard let url = url(path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        data(path).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func save<T: Encodable>(_ value: T, to path: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        write(data, to: path)
    }
}
