import LoLKit
import SwiftUI

/// Réglage « Notifications de début de match » (spec fonctionnalités §2) : interrupteur (désactivé par défaut ; l'activer
/// demande l'autorisation d'iOS) et délai de 5, 15 ou 30 min. Une seule source de vérité : les valeurs viennent du store
/// et y retournent par `setEnabled` / `setLead`, rien n'est recopié dans la vue. Si iOS refuse, l'interrupteur reste coupé
/// et la section dit où l'autoriser.
struct MatchRemindersSection: View {
    let enabled: Bool
    let lead: TimeInterval
    let center: any ReminderCenter
    let setEnabled: (Bool) -> Void
    let setLead: (TimeInterval) -> Void
    @State private var denied: Bool

    /// - Parameter denied: état initial « refusé par iOS » (aperçus) ; l'écran le vérifie lui-même à l'affichage.
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
        .task {
            if enabled, await center.authorization() == .denied {
                denied = true
            }
        }
    }

    private var explanation: String {
        enabled
            ? "« KC vs C9 dans \(Self.leadLabel(lead)) » avant le prochain match de chaque équipe suivie. Jamais pour un match que l'anti-spoiler cache, jamais de score."
            : "Désactivées : aucune notification. Les activer demande l'autorisation d'iOS."
    }

    /// Activer : autorisation d'iOS d'abord (demandée la première fois) ; refusée, l'interrupteur reste coupé.
    private func toggle(_ on: Bool) async {
        guard on else {
            denied = false
            setEnabled(false)
            return
        }
        var granted = false
        switch await center.authorization() {
        case .authorized: granted = true
        case .denied: granted = false
        case .notDetermined: granted = await center.requestAuthorization()
        }
        denied = !granted
        setEnabled(granted)
    }
}
