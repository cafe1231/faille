import Foundation
import LoLKit
import Testing
import UIKit
@testable import Faille

/// Du logo téléchargé à la couleur de l'équipe (spec §9) : https pour le réseau, nom de fichier tiré de la chaîne
/// brute de l'API, couleur dominante saturée.
@MainActor
@Suite(.serialized)
struct LogoPipelineTests {
    private static func redSquarePNG() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
        }
        return image.pngData() ?? Data()
    }

    @Test func logoIsDownloadedOverHttpsKeptUnderTheRawName() async throws {
        let raw = "http://static.lolesports.com/teams/test-logo.png"
        let secure = "https://static.lolesports.com/teams/test-logo.png"
        let png = Self.redSquarePNG()
        #expect(png.count > 100)

        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", image: raw, homeLeagueName: "LEC"),
        ]), to: .follows)
        let transport = ScriptedTransport(extra: { url in
            url.absoluteString == secure ? HTTPResponse(status: 200, body: png) : nil
        })
        let store = AppStore(transport: transport, files: files)
        await store.refreshDue(opening: true)
        await store.updateColorsIfNeeded()   // la passe des couleurs vit hors du cycle (étape 4)

        // Téléchargé en https (l'http est refusé par ATS) ; nommé d'après la chaîne brute de l'API (R-T2).
        let requested = await transport.requests.map(\.absoluteString)
        #expect(requested.contains(secure))
        #expect(!requested.contains(raw))
        let name = LogoFileName.name(for: raw)
        #expect(files.hasLogo(named: name))
        #expect(store.logoFile(for: raw) == files.logoURL(named: name))
        #expect(store.logoFile(for: secure) == nil)
        #expect(store.logoFile(for: nil) == nil)

        // Couleur tirée du logo (rouge), enregistrée avec la liste.
        let hex = try #require(store.follows.teams.first?.autoColorHex)
        let color = try #require(RGB(hex: hex))
        #expect(color.r > color.g && color.r > color.b)
        #expect(files.load(FollowList.self, from: .follows)?.teams.first?.autoColorHex == hex)

        // Le logo est déjà là : le cycle suivant ne le retélécharge pas.
        await store.refreshDue(opening: false)
        await store.updateColorsIfNeeded()
        #expect(await transport.requests.map(\.absoluteString).filter { $0 == secure }.count == 1)
    }

    @Test func missingLogoFallsBackToTheAccentColor() async throws {
        let raw = "http://static.lolesports.com/teams/absent.png"
        let files = TemporaryFiles.store()
        files.save(FollowList(teams: [
            FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", image: raw, homeLeagueName: "LEC"),
        ]), to: .follows)
        let store = AppStore(transport: ScriptedTransport(), files: files) // 404 sur les logos
        await store.refreshDue(opening: true)
        await store.updateColorsIfNeeded()
        #expect(store.follows.teams.first?.autoColorHex == RGB.accent.hex)
        #expect(store.logoFile(for: raw) == nil)
    }

    /// Les badges n'ouvrent plus de fichier dans `body` : la vignette est décodée hors du fil principal, puis gardée en mémoire.
    @Test func thumbnailIsDecodedOnceThenServedFromMemory() async throws {
        let files = TemporaryFiles.store()
        files.saveLogo(Self.redSquarePNG(), named: "logo-test.png")
        let file = files.logoURL(named: "logo-test.png")

        #expect(LogoImages.shared.cached(file) == nil)
        let loaded = try #require(await LogoImages.shared.load(file))
        #expect(loaded.size.width > 0 && loaded.size.height > 0)
        #expect(LogoImages.shared.cached(file) === loaded)
        #expect(await LogoImages.shared.load(file) === loaded)

        // Pas de vignette (équipe non suivie) : rien à décoder, le badge reste sur son monogramme.
        let missing = files.logoURL(named: "absent.png")
        #expect(await LogoImages.shared.load(missing) == nil)
        #expect(LogoImages.shared.cached(missing) == nil)
    }
}
