import SwiftUI
import UIKit
@testable import Faille

/// Rendu de l'icône (spec finitions §1) : PNG de 1024 × 1024 px pour le catalogue, et planche `14-icone.png`.
@MainActor
enum AppIconRender {
    static let pixels: CGFloat = 1024

    /// Une variante à 1024 × 1024 px (échelle 1) dans `build/apercus/`. Claire et teintée : opaques ; sombre : fond
    /// transparent.
    @discardableResult
    static func write(_ variant: AppIconVariant) throws -> URL {
        let renderer = ImageRenderer(content: AppIconArt(variant: variant, size: pixels))
        renderer.scale = 1
        renderer.isOpaque = variant != .dark
        guard let png = renderer.uiImage?.pngData() else {
            throw Snapshot.Failure(description: "ImageRenderer n'a rien rendu pour \(variant.fileName)")
        }
        return try save(png, named: variant.fileName)
    }

    /// La planche : 512 × 680 pt à l'échelle 2 (1024 px de large).
    @discardableResult
    static func writeBoard() throws -> URL {
        let renderer = ImageRenderer(content: AppIconBoard().environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let png = renderer.uiImage?.pngData() else {
            throw Snapshot.Failure(description: "ImageRenderer n'a rien rendu pour 14-icone")
        }
        return try save(png, named: "14-icone")
    }

    private static func save(_ png: Data, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: Snapshot.directory, withIntermediateDirectories: true)
        let url = Snapshot.directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }
}

/// Pixels d'un PNG lus en RGBA 8 bits (prémultipliés) : contrôles de l'icône.
struct Bitmap {
    struct Pixel {
        let r, g, b, a: UInt8
    }

    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(contentsOf url: URL) {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false))?.cgImage else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let index = (y * width + x) * 4
        return Pixel(r: bytes[index], g: bytes[index + 1], b: bytes[index + 2], a: bytes[index + 3])
    }
}

/// Planche de l'icône (`14-icone.png`) : les trois variantes en grand, puis l'icône aux tailles de l'écran d'accueil
/// sur fond clair et sur fond sombre, avec le masque arrondi d'iOS.
struct AppIconBoard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BoardCaption(text: "Variantes · claire, sombre, teintée")
            HStack(spacing: 16) {
                ForEach(AppIconVariant.allCases, id: \.self) { variant in
                    tile(variant, size: 140, backdrop: variant == .dark ? Color(white: 0.11) : .clear)
                }
            }
            BoardCaption(text: "Sur fond clair")
            sizes(on: Color(white: 0.93))
            BoardCaption(text: "Sur fond sombre")
            sizes(on: Color(red: 0.04, green: 0.05, blue: 0.11))
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 512, height: 680, alignment: .topLeading)
        .background(BoardWallpaper())
    }

    private func sizes(on background: Color) -> some View {
        HStack(alignment: .bottom, spacing: 20) {
            ForEach([120, 80, 60, 40] as [CGFloat], id: \.self) { size in
                tile(.standard, size: size, backdrop: .clear)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func tile(_ variant: AppIconVariant, size: CGFloat, backdrop: Color) -> some View {
        AppIconArt(variant: variant, size: size)
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}
