import LoLKit
import SwiftUI
import UIKit

/// Couleurs de la DA « Échap » (spec §9).
enum Palette {
    static let abyss = Color(rgb: RGB(r: 0x0B, g: 0x10, b: 0x20))
    static let text = Color(rgb: RGB(r: 0xE9, g: 0xEE, b: 0xFB))
    static let secondary = Color(rgb: RGB(r: 0x94, g: 0xA0, b: 0xBF))
    static let accent = Color(rgb: .accent)
    /// Nappe bleue en haut à gauche, nappe turquoise en bas à droite.
    static let blueWash = Color(red: 60 / 255, green: 140 / 255, blue: 1, opacity: 0.18)
    static let tealWash = Color(red: 0, green: 220 / 255, blue: 200 / 255, opacity: 0.14)
    /// Verre neutre (équipes non suivies, listes).
    static let glassFill = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.22)
    /// Arête lumineuse en haut des cartes.
    static let glassEdge = Color.white.opacity(0.5)
    static let chipFill = Color.white.opacity(0.10)

    /// Couleur d'une équipe suivie (`FollowedTeam.colorHex`) ; l'accent si le hex est illisible.
    static func team(_ hex: String) -> Color {
        Color(rgb: RGB(hex: hex) ?? .accent)
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

extension RGB {
    /// Couleur choisie dans le sélecteur : composantes sRGB bornées à 0…1.
    init(color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        self.init(r: byte(red), g: byte(green), b: byte(blue))
    }
}
