import Foundation
import SwiftUI
import UIKit

/// Rend un écran dans une vraie fenêtre de l'appli hôte et l'enregistre en PNG dans `build/apercus/`
/// (publié par la CI dans l'artefact `Faille-apercus`). `ImageRenderer` ne rend ni les ScrollView, ni la barre
/// d'onglets, ni le Liquid Glass : on photographie la fenêtre avec `drawHierarchy`, comme le simulateur l'affiche.
@MainActor
enum Snapshot {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// Racine du dépôt déduite de ce fichier (Tests/FailleTests/Support/Snapshot.swift) : le simulateur écrit
    /// directement sur le disque du Mac de la CI.
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // FailleTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // racine du dépôt
        .appendingPathComponent("build/apercus", isDirectory: true)

    /// Attend (5 s au plus) que l'appli hôte ait sa scène et sa première fenêtre : les tests démarrent parfois
    /// avant que l'interface ne soit à l'écran, et une capture de scène absente serait une image vide.
    private static func hostScene() async throws -> UIWindowScene {
        let deadline = ContinuousClock.now + .seconds(5)
        while true {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let scene = scenes.first(where: { !$0.windows.isEmpty }) {
                return scene
            }
            if ContinuousClock.now >= deadline {
                throw Failure(description: "aucune scène ni fenêtre après 5 s : les tests doivent être hébergés dans l'appli")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @discardableResult
    static func write(_ view: some View, named name: String) async throws -> URL {
        let scene = try await hostScene()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = UIHostingController(rootView: AnyView(view))
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Laisse SwiftUI faire sa mise en page, lancer ses `.task` et poser le verre.
        try await Task.sleep(for: .seconds(1))
        guard window.windowScene != nil, !window.bounds.isEmpty else {
            throw Failure(description: "fenêtre sans scène ou sans taille pour \(name)")
        }
        var drawn = false
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            drawn = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard drawn else {
            throw Failure(description: "drawHierarchy a échoué pour \(name) : la fenêtre n'est pas à l'écran")
        }
        guard let png = image.pngData() else {
            throw Failure(description: "PNG vide pour \(name)")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }
}
