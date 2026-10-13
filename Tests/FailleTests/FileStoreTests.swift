import Foundation
import Testing
@testable import Faille

/// Fichiers JSON de Faille : un fichier illisible n'est jamais détruit ni écrasé (R-M2, R-T5b).
@Suite(.serialized)
struct FileStoreTests {
    private struct Sample: Codable, Equatable {
        var name: String
    }

    private func asideFiles(in directory: URL, for file: FileStore.File) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(file.rawValue + ".illisible-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func savesAndLoadsAValue() {
        let store = TemporaryFiles.store()
        store.save(Sample(name: "kc"), to: .follows)
        #expect(store.load(Sample.self, from: .follows) == Sample(name: "kc"))
        #expect(store.load(Sample.self, from: .settings) == nil) // absent : nil, rien n'est mis de côté
    }

    @Test func unreadableFileIsSetAsideWithATimestampAndNeverReplacesAnEarlierOne() throws {
        let directory = TemporaryFiles.directory()
        let store = FileStore(directory: directory)
        let first = Data("pas du json".utf8)
        try first.write(to: store.url(.follows))

        #expect(store.load(Sample.self, from: .follows) == nil)
        #expect(!exists(store.url(.follows)))
        var asides = try asideFiles(in: directory, for: .follows)
        try #require(asides.count == 1)
        #expect(try Data(contentsOf: asides[0]) == first)
        // Nom horodaté : `follows.json.illisible-yyyyMMdd-HHmmss`.
        let stamp = asides[0].lastPathComponent.dropFirst("follows.json.illisible-".count)
        #expect(stamp.count == 15 && stamp.allSatisfy { $0.isNumber || $0 == "-" })

        // Un second fichier illisible dans la même seconde ne remplace pas la première mise de côté.
        let second = Data("autre contenu illisible".utf8)
        try second.write(to: store.url(.follows))
        #expect(store.load(Sample.self, from: .follows) == nil)
        asides = try asideFiles(in: directory, for: .follows)
        #expect(asides.count == 2)
        #expect(try Set(asides.map { try Data(contentsOf: $0) }) == [first, second])
    }

    @Test func fileThatCannotBeMovedIsProtectedFromOverwriting() throws {
        let directory = TemporaryFiles.directory()
        let store = FileStore(directory: directory)
        let garbage = Data("illisible".utf8)
        try garbage.write(to: store.url(.settings))

        // Dossier en lecture seule : le fichier reste lisible (donc illisible pour le décodeur), mais pas déplaçable.
        let path = directory.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
        #expect(store.load(Sample.self, from: .settings) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(try asideFiles(in: directory, for: .settings).isEmpty)

        // Le dossier est de nouveau modifiable : sans la protection, cette écriture écraserait le fichier.
        store.save(Sample(name: "neuf"), to: .settings)
        #expect(try Data(contentsOf: store.url(.settings)) == garbage)
        // Les autres fichiers ne sont pas concernés.
        store.save(Sample(name: "ok"), to: .follows)
        #expect(store.load(Sample.self, from: .follows) == Sample(name: "ok"))
    }

    @Test func readOnlyStoreWritesAndMovesNothing() throws {
        let directory = TemporaryFiles.directory()
        let readOnly = FileStore(directory: directory, readOnly: true)
        #expect(!exists(directory)) // ne crée aucun dossier
        readOnly.save(Sample(name: "x"), to: .follows)
        readOnly.saveLogo(Data([1, 2, 3]), named: "logo-x.png")
        #expect(!exists(directory))

        // Fichier illisible : un store en lecture seule le laisse tel quel, sans le mettre de côté ni l'écraser.
        let writable = FileStore(directory: directory)
        let garbage = Data("pas du json".utf8)
        try garbage.write(to: writable.url(.follows))
        let reader = FileStore(directory: directory, readOnly: true)
        #expect(reader.load(Sample.self, from: .follows) == nil)
        reader.save(Sample(name: "x"), to: .follows)
        #expect(try Data(contentsOf: writable.url(.follows)) == garbage)
        #expect(try asideFiles(in: directory, for: .follows).isEmpty)
    }
}
