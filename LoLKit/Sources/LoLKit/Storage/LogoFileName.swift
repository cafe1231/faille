/// Nom de fichier stable d'un logo, tiré de son URL : un logo qui change d'URL change de fichier,
/// ce qui déclenche le recalcul de la couleur de l'équipe.
public enum LogoFileName {
    public static func name(for url: String) -> String {
        "logo-" + hex(fnv1a64(url)) + ".png"
    }

    /// FNV-1a 64 bits : stable d'un lancement à l'autre, contrairement à `hashValue`.
    public static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
