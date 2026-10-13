import Foundation

/// Le processus héberge-t-il des tests ? Alors l'appli reste inerte : pas d'interface, pas de réseau, pas de widget.
/// Évalué une seule fois, au premier usage (au lancement de l'appli).
enum RunEnvironment {
    static let isTesting: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}
