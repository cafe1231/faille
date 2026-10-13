import Foundation

/// Lit le profil de provisionnement (`embedded.mobileprovision`) d'un bundle.
/// Le fichier est un CMS signé qui contient un plist XML en clair : on en extrait les octets
/// de `<?xml` à `</plist>` puis on les parse.
enum Provisioning {
    struct Info {
        var appGroups: [String]
        var appID: String?
        var teamID: String?
        var profileName: String?
        var expiration: Date?
    }

    static func read(bundleURL: URL) -> Info? {
        let url = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards),
              start.lowerBound < end.upperBound else { return nil }

        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil),
              let root = plist as? [String: Any] else { return nil }

        let entitlements = root["Entitlements"] as? [String: Any] ?? [:]
        return Info(
            appGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            appID: entitlements["application-identifier"] as? String,
            teamID: entitlements["com.apple.developer.team-identifier"] as? String,
            profileName: root["Name"] as? String,
            expiration: root["ExpirationDate"] as? Date
        )
    }
}
