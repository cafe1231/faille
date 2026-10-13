extension TeamColor {
    /// CoreGraphics ne dessine qu'en RGBA à alpha prémultiplié : on redivise chaque canal par l'alpha pour retrouver
    /// la vraie couleur (un pixel à moitié transparent paraîtrait sinon deux fois plus sombre, voire « quasi noir »).
    /// Entrée et sortie : 4 octets par pixel. Alpha 0 et 255 : pixel inchangé.
    public static func unpremultiplied(_ rgba: [UInt8]) -> [UInt8] {
        var result = rgba
        var index = 0
        while index + 3 < result.count {
            let alpha = Int(result[index + 3])
            if alpha > 0 && alpha < 255 {
                for channel in index..<(index + 3) {
                    result[channel] = UInt8(min(255, (Int(result[channel]) * 255 + alpha / 2) / alpha))
                }
            }
            index += 4
        }
        return result
    }
}
