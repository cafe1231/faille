import Foundation

/// Sonde de l'étape 0 : l'appli écrit une date dans l'App Group, le widget la relit.
enum ProbeStore {
    /// Le vrai nom du groupe est lu dans le profil embarqué (Sideloadly peut le renommer).
    static var appGroup: String {
        Provisioning.read(bundleURL: Bundle.main.bundleURL)?.appGroups.first ?? "group.com.cafe1231.faille"
    }

    private static let key = "probe.lastWrite"

    static var groupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil
    }

    static func write(_ date: Date) {
        UserDefaults(suiteName: appGroup)?.set(date.timeIntervalSince1970, forKey: key)
    }

    static func read() -> Date? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }
}
