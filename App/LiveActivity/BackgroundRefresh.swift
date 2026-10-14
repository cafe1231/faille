import BackgroundTasks
import Foundation
import os
import UIKit

/// Rafraîchissement en arrière-plan (spec §6.4) : `BGAppRefreshTask` environ toutes les 15 min tant qu'un match suivi
/// est en direct. iOS décide seul du moment, et peut ne rien accorder (mode économie d'énergie, actualisation en
/// arrière-plan coupée, appli peu utilisée) : la Live Activity le montre alors honnêtement (« màj il y a X minutes »).
enum BackgroundRefresh {
    /// Déclaré dans Info.plist (`BGTaskSchedulerPermittedIdentifiers`). Indépendant du bundle ID, qu'AltServer renomme.
    static let identifier = "faille.live-refresh"

    private static let log = Logger(subsystem: "Faille", category: "arrière-plan")

    /// Demande le prochain réveil au plus tôt à `date` ; nil annule la demande en attente. Rend ce qu'iOS en a dit (pour
    /// le diagnostic de À propos). Dans les tests, rien n'est demandé à iOS et la demande est réputée acceptée.
    @discardableResult
    static func schedule(at date: Date?) -> WakeRequest.Outcome {
        guard let date else {
            if !RunEnvironment.isTesting {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            }
            return .nothingToWatch
        }
        guard !RunEnvironment.isTesting else { return .requested(date) }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
            return .requested(date)
        } catch {
            // Simulateur, actualisation en arrière-plan coupée : la Live Activity passera « pas fraîche ».
            log.info("Réveil en arrière-plan non programmé : \(String(describing: error), privacy: .public)")
            return .refused(refusalReason(error))
        }
    }

    /// Cause d'un refus, en français : les trois codes de `BGTaskScheduler.Error` (domaine `BGTaskSchedulerErrorDomain`),
    /// sinon le texte de l'erreur.
    static func refusalReason(_ error: any Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == "BGTaskSchedulerErrorDomain" else { return String(describing: error) }
        switch nsError.code {
        case 1: return "indisponible (actualisation en arrière-plan coupée, ou simulateur)"
        case 2: return "trop de demandes en attente"
        case 3: return "non autorisé (identifiant ou mode d'arrière-plan manquant)"
        default: return "erreur \(nsError.code)"
        }
    }

    /// Laisse à `work` le temps de finir après le passage en arrière-plan (quelques secondes accordées par iOS).
    @MainActor
    static func finishInBackground(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let assertion = BackgroundAssertion()
        assertion.begin()
        Task {
            await work()
            assertion.end()
        }
    }
}

/// Une demande de temps d'exécution en arrière-plan (`beginBackgroundTask`), rendue au plus tard à son expiration.
@MainActor
private final class BackgroundAssertion {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Faille · Live Activities") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
