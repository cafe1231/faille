import Foundation
import LoLKit

// Diagnostic des Live Activities (étape 4, vague finale) : depuis Windows, on ne peut pas lire le journal d'iOS
// (`os.Logger`). Le bloc « Diagnostic Live Activity » de À propos dit à l'écran, sur l'iPhone, pourquoi une Live Activity
// n'est pas apparue ou ne se met pas à jour en arrière-plan.

/// Dernier démarrage de Live Activity qui a échoué (ou qui n'a pas pu avoir lieu).
struct StartFailure: Sendable, Equatable {
    let matchId: String
    let reason: String
    let date: Date
}

/// Dernière demande de réveil faite à iOS (`BGAppRefreshTask`) et ce qu'iOS en a dit.
struct WakeRequest: Codable, Sendable, Equatable {
    enum Outcome: Codable, Sendable, Equatable {
        /// Acceptée : réveil demandé pour cette date au plus tôt (iOS décide seul du moment, ou de ne rien accorder).
        case requested(Date)
        /// iOS a refusé la demande (cause en français).
        case refused(String)
        /// Rien à demander : aucun match suivi en direct, aucune Live Activity à l'écran.
        case nothingToWatch
    }

    /// Quand l'appli l'a faite.
    let at: Date
    let outcome: Outcome
}

/// Ce que l'appli sait de l'arrière-plan. Enregistré dans un fichier : pour un réveil, iOS relance parfois l'appli dans
/// un nouveau processus, et la mémoire de celui qui a reçu le réveil est perdue quand l'utilisateur rouvre Faille.
struct BackgroundDiagnostic: Codable, Sendable, Equatable {
    /// Dernier réveil d'arrière-plan reçu d'iOS.
    var lastWake: Date?
    var lastRequest: WakeRequest?
}

/// Les quatre lignes du bloc, en texte (« — » quand c'est inconnu), testables sans interface.
enum LiveActivityDiagnosticText {
    struct Line: Equatable, Identifiable {
        let title: String
        let value: String

        var id: String { title }
    }

    static let unknown = "—"

    /// Heure locale « 14:05 » ; « 13/10 14:05 » quand ce n'est pas le jour de `now` (le diagnostic est enregistré :
    /// un réveil d'hier ne doit pas se lire comme celui de ce matin).
    static func stamp(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = Format.time(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let parts = calendar.dateComponents([.day, .month], from: date)
        return String(format: "%d/%02d ", parts.day ?? 0, parts.month ?? 0) + time
    }

    static func lines(enabled: Bool, failure: StartFailure?, background: BackgroundDiagnostic, now: Date,
                      timeZone: TimeZone = .current) -> [Line] {
        func stamp(_ date: Date) -> String {
            Self.stamp(date, now: now, timeZone: timeZone)
        }
        let failureText = failure.map { "\(stamp($0.date)) · \($0.matchId) · \($0.reason)" } ?? unknown
        let wakeText = background.lastWake.map(stamp) ?? unknown
        let requestText = background.lastRequest.map { request -> String in
            switch request.outcome {
            case let .requested(date): return "\(stamp(request.at)) · demandé pour \(stamp(date))"
            case let .refused(reason): return "\(stamp(request.at)) · refusé : \(reason)"
            case .nothingToWatch: return "\(stamp(request.at)) · aucun match suivi en direct"
            }
        } ?? unknown
        return [
            Line(title: "Live Activities autorisées", value: enabled ? "oui" : "non"),
            Line(title: "Dernier échec de démarrage", value: failureText),
            Line(title: "Dernier réveil en arrière-plan", value: wakeText),
            Line(title: "Dernière demande de réveil", value: requestText),
        ]
    }
}
