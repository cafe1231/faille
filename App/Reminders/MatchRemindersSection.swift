import LoLKit
import SwiftUI

/// Ce que la section des notifications décide, sans vue (testé) : l'état de l'interrupteur et l'avertissement « refusées
/// par iOS » d'après l'autorisation d'iOS.
enum MatchRemindersFlow {
    struct Outcome: Equatable, Sendable {
        /// Valeur à donner au réglage ; nil : on n'y touche pas.
        let enabled: Bool?
        /// Faut-il dire que iOS refuse les notifications (et où les autoriser) ?
        let denied: Bool
    }

    /// L'utilisateur bascule l'interrupteur. Activer demande d'abord l'autorisation d'iOS (la première fois seulement) ;
    /// refusée, l'interrupteur reste coupé et l'avertissement s'affiche.
    static func toggle(to on: Bool, center: any ReminderCenter) async -> Outcome {
        guard on else { return Outcome(enabled: false, denied: false) }
        let granted: Bool
        switch await center.authorization() {
        case .authorized: granted = true
        case .denied: granted = false
        case .notDetermined: granted = await center.requestAuthorization()
        }
        return Outcome(enabled: granted, denied: !granted)
    }

    /// Au premier plan, l'autorisation d'iOS a pu changer sans l'appli (Réglages d'iOS, sauvegarde restaurée sur un autre
    /// iPhone : le réglage de Faille revient, pas l'autorisation).
    /// - Autorisée : plus d'avertissement (l'utilisateur vient peut-être de l'autoriser).
    /// - Refusée : l'avertissement s'affiche si le réglage est activé (rien ne sera programmé) ou s'il l'était déjà.
    /// - Jamais demandée alors que le réglage est activé : il n'a aucun effet, on le coupe pour que le prochain
    ///   basculement demande l'autorisation. Réglage coupé : rien ne change.
    static func reconcile(enabled: Bool, denied: Bool, authorization: ReminderAuthorization) -> Outcome {
        switch authorization {
        case .authorized:
            return Outcome(enabled: nil, denied: false)
        case .denied:
            return Outcome(enabled: nil, denied: denied || enabled)
        case .notDetermined:
            return enabled ? Outcome(enabled: false, denied: false) : Outcome(enabled: nil, denied: denied)
        }
    }
}

/// Réglage « Notifications de début de match » (spec fonctionnalités §2) : interrupteur (désactivé par défaut ; l'activer
/// demande l'autorisation d'iOS) et délai de 5, 15 ou 30 min. Une seule source de vérité : les valeurs viennent du store
/// et y retournent par `setEnabled` / `setLead`, rien n'est recopié dans la vue. Si iOS refuse, l'interrupteur reste coupé
/// et la section dit où l'autoriser (`MatchRemindersFlow`).
struct MatchRemindersSection: View {
    let enabled: Bool
    let lead: TimeInterval
    let center: any ReminderCenter
    let setEnabled: (Bool) -> Void
    let setLead: (TimeInterval) -> Void
    @State private var denied: Bool
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter denied: état initial « refusé par iOS » (aperçus) ; l'écran le vérifie lui-même à l'affichage et à
    ///   chaque retour au premier plan.
    init(enabled: Bool, lead: TimeInterval, center: any ReminderCenter, denied: Bool = false,
         setEnabled: @escaping (Bool) -> Void, setLead: @escaping (TimeInterval) -> Void) {
        self.enabled = enabled
        self.lead = lead
        self.center = center
        self.setEnabled = setEnabled
        self.setLead = setLead
        _denied = State(initialValue: denied)
    }

    /// « 15 min »
    static func leadLabel(_ lead: TimeInterval) -> String {
        "\(Int((lead / 60).rounded())) min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { enabled }, set: { on in Task { await toggle(on) } })) {
                Text("Début de match")
                    .font(Typo.body)
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.accent)
            if enabled {
                Picker("Délai", selection: Binding(get: { lead }, set: { setLead($0) })) {
                    ForEach(MatchReminders.leadOptions, id: \.self) { option in
                        Text(Self.leadLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text(explanation)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
            if denied {
                Text("Notifications refusées par iOS : Réglages › Faille › Notifications.")
                    .font(Typo.secondaryMedium)
                    .foregroundStyle(Palette.accent)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        // À l'affichage et à chaque retour au premier plan (l'utilisateur revient des Réglages d'iOS).
        .task(id: scenePhase) { await refresh() }
    }

    private var explanation: String {
        enabled
            ? "« KC vs C9 dans \(Self.leadLabel(lead)) » avant le prochain match de chaque équipe suivie. Jamais pour un match que l'anti-spoiler cache, jamais de score."
            : "Désactivées : aucune notification. Les activer demande l'autorisation d'iOS."
    }

    /// Relit l'autorisation d'iOS (`MatchRemindersFlow.reconcile`) quand la scène est au premier plan.
    private func refresh() async {
        guard scenePhase == .active else { return }
        let authorization = await center.authorization()
        apply(MatchRemindersFlow.reconcile(enabled: enabled, denied: denied, authorization: authorization))
    }

    private func toggle(_ on: Bool) async {
        let outcome = await MatchRemindersFlow.toggle(to: on, center: center)
        apply(outcome)
    }

    private func apply(_ outcome: MatchRemindersFlow.Outcome) {
        denied = outcome.denied
        if let value = outcome.enabled {
            setEnabled(value)
        }
    }
}
