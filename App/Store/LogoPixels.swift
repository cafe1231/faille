import CoreGraphics
import ImageIO
import UIKit

/// Décodage d'un logo pour `TeamColor` (spec §9) : miniature, puis octets RGBA. CoreGraphics ne dessine qu'en alpha
/// prémultiplié : l'appelant passe les octets par `TeamColor.unpremultiplied` avant `TeamColor.teamColor`.
enum LogoPixels {
    /// Miniature d'au plus `maxPixel` px de côté (les logos de l'API vont jusqu'à 2000 px). nil si illisible (SVG…).
    static func thumbnail(from data: Data, maxPixel: Int = 128) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// PNG de la miniature, gardé dans le dossier des logos pour l'affichage.
    static func png(_ image: CGImage) -> Data? {
        UIImage(cgImage: image).pngData()
    }

    /// Octets RGBA 8 bits (alpha prémultiplié) de l'image redessinée en `side` px au plus de côté.
    static func rgba(_ image: CGImage, side: Int = 64) -> [UInt8]? {
        let scale = min(1, Double(side) / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}
