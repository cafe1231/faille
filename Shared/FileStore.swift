import Foundation
import os

/// Fichiers JSON de Faille (spec §4.4) dans le dossier résolu par `AppGroup`. Partagé entre l'appli et l'extension.
/// Encodage `JSONEncoder()` / `JSONDecoder()` par défaut.
///
/// Un fichier illisible n'est jamais détruit ni écrasé : `load` le met de côté sous
/// `<nom>.illisible-<yyyyMMdd-HHmmss>` (une mise de côté précédente n'est jamais supprimée). Si le déplacement
/// échoue, le fichier est « protégé » : `save` refuse de l'écraser tant que le processus vit.
///
/// `readOnly: true` (extension widget) : ne crée aucun dossier, ne met jamais de fichier de côté et n'écrit rien.
struct FileStore: Sendable {
    enum File: String, Sendable, CaseIterable {
        case follows = "follows.json"
        case settings = "settings.json"
        case leagues = "cache-leagues.json"
        case teams = "cache-teams.json"
        case schedule = "cache-schedule.json"
        case live = "cache-live.json"
        /// Choix sur les Live Activities (épinglées, retirées à la main, démarrées) : écrit par l'appli seule.
        case liveActivities = "live-activities.json"
    }

    let directory: URL
    let readOnly: Bool

    init(directory: URL, readOnly: Bool = false) {
        self.directory = directory
        self.readOnly = readOnly
        if !readOnly {
            try? FileManager.default.createDirectory(at: logosDirectory, withIntermediateDirectories: true)
        }
    }

    var logosDirectory: URL {
        directory.appendingPathComponent("logos", isDirectory: true)
    }

    func url(_ file: File) -> URL {
        directory.appendingPathComponent(file.rawValue)
    }

    /// Valeur enregistrée, ou nil si le fichier manque ou est illisible.
    func load<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        let fileURL = self.url(file)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.log.error("\(file.rawValue, privacy: .public) illisible : \(String(describing: error), privacy: .public)")
            // Format d'une autre version ? On le met de côté pour ne pas l'écraser à la prochaine sauvegarde.
            if !readOnly { setAside(fileURL) }
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, to file: File) {
        guard !readOnly else { return }
        let fileURL = self.url(file)
        if Self.isProtected(fileURL) {
            Self.log.error("\(file.rawValue, privacy: .public) illisible et non déplaçable : écriture refusée pour ne pas l'écraser")
            return
        }
        do {
            try JSONEncoder().encode(value).write(to: fileURL, options: .atomic)
        } catch {
            Self.log.error("Écriture de \(file.rawValue, privacy: .public) impossible : \(String(describing: error), privacy: .public)")
        }
    }

    func logoURL(named name: String) -> URL {
        logosDirectory.appendingPathComponent(name)
    }

    func hasLogo(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: logoURL(named: name).path(percentEncoded: false))
    }

    func saveLogo(_ data: Data, named name: String) {
        guard !readOnly else { return }
        do {
            try data.write(to: logoURL(named: name), options: .atomic)
        } catch {
            Self.log.error("Écriture du logo \(name, privacy: .public) impossible : \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Fichier illisible

    private static let log = Logger(subsystem: "Faille", category: "fichiers")

    /// Fichiers illisibles qu'on n'a pas pu déplacer : on refuse de les écraser jusqu'à la fin du processus.
    private static let protectedPaths = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    private static func key(_ fileURL: URL) -> String {
        fileURL.standardizedFileURL.path(percentEncoded: false)
    }

    private static func isProtected(_ fileURL: URL) -> Bool {
        let path = key(fileURL)
        return protectedPaths.withLock { $0.contains(path) }
    }

    /// Déplace le fichier vers `<nom>.illisible-<horodatage>` sans jamais supprimer ni remplacer un fichier existant.
    /// Un nom déjà pris reçoit un suffixe `-1`, `-2`… ; si le déplacement échoue, le fichier devient « protégé ».
    private func setAside(_ fileURL: URL) {
        let path = Self.key(fileURL)
        let manager = FileManager.default
        let base = "\(fileURL.lastPathComponent).illisible-\(Self.timestamp(Date()))"
        let folder = fileURL.deletingLastPathComponent()
        var failure: String = "aucun nom libre"
        for attempt in 0..<100 {
            let aside = folder.appendingPathComponent(attempt == 0 ? base : "\(base)-\(attempt)")
            if manager.fileExists(atPath: aside.path(percentEncoded: false)) { continue }
            do {
                try manager.moveItem(at: fileURL, to: aside)
                _ = Self.protectedPaths.withLock { $0.remove(path) }
                Self.log.error("\(fileURL.lastPathComponent, privacy: .public) mis de côté sous \(aside.lastPathComponent, privacy: .public)")
                return
            } catch {
                failure = String(describing: error)
                break
            }
        }
        _ = Self.protectedPaths.withLock { $0.insert(path) }
        Self.log.error("\(fileURL.lastPathComponent, privacy: .public) illisible et non déplaçable (\(failure, privacy: .public)) : protégé contre l'écrasement")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
