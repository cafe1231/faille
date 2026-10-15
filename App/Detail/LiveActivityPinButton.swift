import LoLKit
import SwiftUI

/// « Épingler sur l'écran verrouillé » / « Retirer de l'écran verrouillé » (spec §5.3, §6.4). Explique pourquoi rien
/// ne s'affiche quand iOS a désactivé les Activités en direct (spec §10) ou quand 3 sont déjà à l'écran.
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
                    Text(shown ? String(localized: "Retirer de l'écran verrouillé") : String(localized: "Épingler sur l'écran verrouillé"))
                }
                .sora(.bodyMedium)
                .foregroundStyle(controller.isEnabled ? Palette.text : Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                // Dans le libellé : le bouton entier (verre compris) s'enfonce au toucher, comme « À propos ».
                .glassCard(radius: Radius.inner, padding: 4)
            }
            .buttonStyle(.pressable)
            if let note = Self.note(enabled: controller.isEnabled, refused: refused) {
                Text(note)
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        // « Déjà 3 … » ne reste pas affiché quand une Activité en direct quitte l'écran ou qu'une autre arrive (audit D.1,
        // étape 4) : le refus portait sur l'état d'alors.
        .onChange(of: controller.shownMatchIds) {
            refused = nil
        }
    }

    /// Note sous le bouton : Activités en direct coupées dans iOS, ou écran verrouillé plein ; nil sinon. « Activités en
    /// direct », le nom d'iOS en français, partout (audit B-G7).
    static func note(enabled: Bool, refused: PinOutcome?) -> String? {
        if !enabled || refused == .disabled {
            return String(localized: "Activités en direct désactivées : Réglages › Faille › Activités en direct.")
        }
        if refused == .full {
            return String(localized: "Déjà 3 Activités en direct sur l'écran verrouillé : retires-en une d'abord.")
        }
        return nil
    }
}
