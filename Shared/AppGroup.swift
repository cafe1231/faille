import Foundation
import LoLKit

/// Groupe d'apps réellement attribué à ce bundle (spec §4.4). AltServer le renomme en
/// `group.com.cafe1231.faille.<TEAMID>` : on ne suppose jamais ni le nom du groupe, ni le bundle ID.
/// Même règle dans l'appli et dans l'extension (chacune lit son propre profil embarqué).
enum AppGroup {
    /// Nom déclaré dans project.yml, dernier candidat.
    static let configured = "group.com.cafe1231.faille"

    /// Groupe retenu : le premier candidat dont le conteneur existe ; nil si aucun (l'appli marche alors seule).
    static let identifier: String? = {
        let provisioned = Provisioning.read(bundleURL: Bundle.main.bundleURL)?.appGroups ?? []
        let altStore = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let candidates = AppGroupResolver.candidates(provisioned: provisioned, altAppGroups: altStore, configured: configured)
        return AppGroupResolver.first(of: candidates) {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
    }()

    /// Dossier des fichiers de Faille : `Faille/` dans le conteneur du groupe, sinon dans Application Support de l'appli.
    static let directory: URL = {
        if let identifier, let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return container.appendingPathComponent("Faille", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Faille", isDirectory: true)
    }()
}
