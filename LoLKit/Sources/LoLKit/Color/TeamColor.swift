/// Couleur 8 bits par canal.
public struct RGB: Codable, Sendable, Equatable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    /// Accent de la DA (`#6FD3FF`), couleur par défaut d'une équipe.
    public static let accent = RGB(r: 0x6F, g: 0xD3, b: 0xFF)

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF))
    }

    public var hex: String {
        func pair(_ value: UInt8) -> String {
            let digits = String(value, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }
        return "#" + pair(r) + pair(g) + pair(b)
    }

    /// Luminosité perçue, de 0 (noir) à 1 (blanc).
    public var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
    }
}

/// Couleur d'une équipe à partir de son logo (spec §9).
public enum TeamColor {
    /// Luminosité minimale pour rester lisible sur le fond abysse `#0b1020`.
    public static let minLuminance = 0.5

    /// Couleur dominante saturée d'un logo. `rgba` : 4 octets par pixel.
    /// Ignore les pixels transparents, quasi gris, quasi blancs et quasi noirs.
    public static func dominant(rgba: [UInt8]) -> RGB? {
        var weights = [Double](repeating: 0, count: 36)
        var sums = [(r: Double, g: Double, b: Double, count: Double)](repeating: (0, 0, 0, 0), count: 36)
        var index = 0
        while index + 3 < rgba.count {
            let r = Double(rgba[index]), g = Double(rgba[index + 1]), b = Double(rgba[index + 2])
            let alpha = rgba[index + 3]
            index += 4
            guard alpha >= 128 else { continue }
            let maxChannel = max(r, g, b)
            let minChannel = min(r, g, b)
            let value = maxChannel / 255
            let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel
            guard saturation >= 0.25, value >= 0.2 else { continue }
            let bin = min(35, Int(hue(r, g, b, maxChannel: maxChannel, minChannel: minChannel) / 10))
            weights[bin] += saturation * value
            sums[bin].r += r
            sums[bin].g += g
            sums[bin].b += b
            sums[bin].count += 1
        }
        guard let best = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[best] > 0 else { return nil }
        let sum = sums[best]
        return RGB(r: UInt8((sum.r / sum.count).rounded()),
                   g: UInt8((sum.g / sum.count).rounded()),
                   b: UInt8((sum.b / sum.count).rounded()))
    }

    /// Éclaircit (mélange avec du blanc) jusqu'à atteindre `minLuminance`.
    public static func readable(_ color: RGB) -> RGB {
        var amount = 0.0
        var result = color
        while result.luminance < minLuminance && amount < 1 {
            amount += 0.05
            result = mix(color, with: RGB(r: 255, g: 255, b: 255), amount: amount)
        }
        return result
    }

    /// Couleur finale d'une équipe, ou l'accent si le logo n'a pas de couleur exploitable.
    public static func teamColor(rgba: [UInt8]) -> RGB {
        dominant(rgba: rgba).map(readable) ?? .accent
    }

    static func hue(_ r: Double, _ g: Double, _ b: Double, maxChannel: Double, minChannel: Double) -> Double {
        let delta = maxChannel - minChannel
        guard delta > 0 else { return 0 }
        var hue: Double
        if maxChannel == r {
            hue = (g - b) / delta
        } else if maxChannel == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue *= 60
        return hue < 0 ? hue + 360 : hue
    }

    static func mix(_ a: RGB, with b: RGB, amount: Double) -> RGB {
        func channel(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8((Double(x) + (Double(y) - Double(x)) * min(amount, 1)).rounded())
        }
        return RGB(r: channel(a.r, b.r), g: channel(a.g, b.g), b: channel(a.b, b.b))
    }
}
