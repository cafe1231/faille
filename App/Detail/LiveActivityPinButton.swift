import LoLKit
import SwiftUI

/// « Épingler sur l'écran verrouillé » / « Retirer de l'écran verrouillé » (spec §5.3, §6.4). Explique pourquoi rien
/// ne s'affiche quand iOS a désactivé les Live Activities (spec §10) ou quand 3 sont déjà à l'écran.
struct LiveActivityPinButton: View {
    @Environment(AppStore.self) private var store
    let matchId: String
    @State private var refused: PinOutcome?
    /// Retour haptique de l'action (spec finitions §3), joué par l'écran Détail : ce bouton peut disparaître juste après
    /// « Retirer » (match terminé). Épinglé : succès ; retiré : impact léger ; refusé : rien.
    var onHaptic: (Haptic) -> Void = { _ in }

    var body: some View {
        let controller = store.liveActivities
        let shown = controller.shownMatchIds.contains(matchId)
        VStack(spacing: 6) {
            Button {
                if shown {
                    refused = nil
                    store.removeActivity(matchId: matchId)
                    onHaptic(.unpin)
                } else {
                    let outcome = store.pinActivity(matchId: matchId)
                    refused = outcome == .pinned ? nil : outcome
                    if outcome == .pinned {
                        onHaptic(.pin)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    IconView(icon: .pin, size: 15)
                    Text(shown ? "Retirer de l'écran verrouillé" : "Épingler sur l'écran verrouillé")
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(controller.isEnabled ? Palette.text : Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                // Dans le libellé : le bouton entier (verre compris) s'enfonce au toucher, comme « À propos ».
                .glassCard(radius: Radius.inner, padding: 4)
            }
            .buttonStyle(.pressable)
            if let note = note(enabled: controller.isEnabled) {
                Text(note)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func note(enabled: Bool) -> String? {
        if !enabled || refused == .disabled {
            return "Live Activities désactivées : Réglages › Faille › Activités en direct."
        }
        if refused == .full {
            return "Déjà 3 Live Activities sur l'écran verrouillé : retires-en une d'abord."
        }
        return nil
    }
}
