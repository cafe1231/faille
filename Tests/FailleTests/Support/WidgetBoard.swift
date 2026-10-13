import LoLKit
import SwiftUI
import UIKit
@testable import Faille

/// Tailles approximatives des familles de widgets sur un iPhone de 6,3 pouces (écran de 402 × 874 pt).
enum WidgetSize {
    static let screen = CGSize(width: 402, height: 874)
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let rectangular = CGSize(width: 172, height: 76)
    static let circular = CGSize(width: 76, height: 76)
    static let inline = CGSize(width: 257, height: 26)
    /// Marge que iOS met autour du contenu des widgets de l'écran d'accueil.
    static let homeMargin: CGFloat = 16
}

/// Un état d'un widget sur une planche : sa légende et ce qu'il montre.
struct BoardState {
    let caption: String
    let content: WidgetContent
}

/// Un petit widget sur la planche : sa légende et l'équipe qu'il montre.
struct SmallState {
    let caption: String
    let team: WidgetTeam?
}

/// Fond d'écran sombre des planches (comme la maquette de l'écran verrouillé).
struct BoardWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.20), Color(red: 0.04, green: 0.05, blue: 0.11)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.23, green: 0.31, blue: 0.56), .clear],
                           center: UnitPoint(x: 0.2, y: 0.1), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(red: 0.12, green: 0.43, blue: 0.47), .clear],
                           center: UnitPoint(x: 0.9, y: 0.8), startRadius: 0, endRadius: 360)
        }
    }
}

/// Légende d'un état sur une planche.
struct BoardCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typo.label)
            .tracking(Typo.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.6))
    }
}

/// Planche de l'écran verrouillé (spec §7) : pour chaque état, les widgets en ligne, rectangulaire et rond, en blanc
/// sur le fond d'écran, avec le fond translucide que iOS pose sous le rectangulaire et le rond.
struct LockScreenBoard: View {
    let states: [BoardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 8) {
                    BoardCaption(text: state.caption)
                    InlineWidgetView(content: state.content)
                        .frame(width: WidgetSize.inline.width, height: WidgetSize.inline.height, alignment: .leading)
                    HStack(spacing: 12) {
                        RectangularWidgetView(content: state.content)
                            .padding(.horizontal, 10)
                            .frame(width: WidgetSize.rectangular.width, height: WidgetSize.rectangular.height)
                            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        CircularWidgetView(content: state.content)
                            .frame(width: WidgetSize.circular.width, height: WidgetSize.circular.height)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white)
        .padding(24)
        .frame(width: WidgetSize.screen.width, height: WidgetSize.screen.height, alignment: .topLeading)
        .background(BoardWallpaper())
    }
}

/// Planche de l'écran d'accueil (spec §7) : petits widgets (une équipe chacun), puis moyens, sur leur fond DA.
struct HomeScreenBoard: View {
    let smalls: [SmallState]
    let mediums: [BoardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(stride(from: 0, to: smalls.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: 16) {
                    ForEach(start..<min(start + 2, smalls.count), id: \.self) { index in
                        smallTile(smalls[index])
                    }
                }
            }
            ForEach(Array(mediums.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 4) {
                    BoardCaption(text: state.caption)
                    tile(MediumWidgetView(content: state.content), size: WidgetSize.medium, tint: nil)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
        .frame(width: WidgetSize.screen.width, height: WidgetSize.screen.height, alignment: .topLeading)
        .background(BoardWallpaper())
    }

    private func smallTile(_ state: SmallState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            BoardCaption(text: state.caption)
            tile(SmallWidgetView(team: state.team), size: WidgetSize.small,
                 tint: state.team.map { Palette.team($0.team.colorHex) })
        }
    }

    /// Un widget de l'écran d'accueil comme iOS le pose : marge, fond DA (`WidgetBackdrop`), coins arrondis.
    private func tile(_ content: some View, size: CGSize, tint: Color?) -> some View {
        content
            .padding(WidgetSize.homeMargin)
            .frame(width: size.width, height: size.height)
            .background(WidgetBackdrop(tint: tint))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Rendu des widgets par `ImageRenderer` : leurs vues sont de simples vues SwiftUI (ni ScrollView, ni verre, ni
/// matière), contrairement aux écrans de l'appli, photographiés par `Snapshot` (drawHierarchy).
@MainActor
enum WidgetRender {
    /// Écrit la planche en PNG (×3) dans `build/apercus/`, à côté des captures d'écran de `Snapshot`.
    @discardableResult
    static func write(_ view: some View, size: CGSize, named name: String) throws -> URL {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        guard let png = renderer.uiImage?.pngData() else {
            throw Snapshot.Failure(description: "ImageRenderer n'a rien rendu pour \(name)")
        }
        try FileManager.default.createDirectory(at: Snapshot.directory, withIntermediateDirectories: true)
        let url = Snapshot.directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        return url
    }

    /// Part des pixels non transparents d'une vue rendue seule, sur fond transparent : 0 si elle ne dessine rien.
    static func inkRatio(_ view: some View, size: CGSize) -> Double {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        renderer.isOpaque = false
        guard let image = renderer.cgImage else { return 0 }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        let ink = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count
        return Double(ink) / Double(width * height)
    }
}
