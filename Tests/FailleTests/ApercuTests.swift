import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Faille

/// Aperçus PNG des écrans (artefact `Faille-apercus`) : depuis Windows, on ne voit l'appli que comme ça.
/// Les tâches suivantes ajoutent leurs écrans par `extension ApercuTests` (même suite, donc rendus un par un).
@MainActor
@Suite(.serialized)
struct ApercuTests {
    @Test func soraIsBundled() {
        #expect(!UIFont.fontNames(forFamilyName: "Sora").isEmpty)
        #expect(Sora.uiFont(15, .bold).familyName == "Sora")
        // L'axe de graisse agit vraiment : « Mondial » est plus large en gras qu'en regular.
        func width(_ weight: Sora.Weight) -> CGFloat {
            ("Mondial" as NSString).size(withAttributes: [.font: Sora.uiFont(15, weight)]).width
        }
        #expect(width(.bold) > width(.regular))
    }

    @Test func iconsAreInTheCatalog() {
        #expect(Icon.allCases.count == 21)
        for icon in Icon.allCases {
            #expect(UIImage(named: icon.assetName) != nil, "icône manquante : \(icon.assetName)")
        }
    }

    @Test func designSheet() async throws {
        let url = try await Snapshot.write(DASampler(), named: "00-da")
        expectNotBlank(url)
    }
}

extension ApercuTests {
    /// Le PNG existe et n'est pas une image vide : fond dégradé + contenu pèsent bien plus de 10 Ko.
    /// À appeler après chaque `Snapshot.write` (les tests des écrans suivants le réutilisent).
    func expectNotBlank(_ url: URL, sourceLocation: SourceLocation = #_sourceLocation) {
        let path = url.path(percentEncoded: false)
        #expect(FileManager.default.fileExists(atPath: path), sourceLocation: sourceLocation)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        #expect(size > 10_000, "capture quasi vide : \(url.lastPathComponent), \(size) octets", sourceLocation: sourceLocation)
    }
}
