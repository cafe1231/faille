import LoLKit
import SwiftUI

/// « Changer la couleur » (appui long sur une équipe suivie, spec §5.2) : sélecteur, aperçu Vitrail, ou retour à l'automatique.
struct TeamColorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let team: FollowedTeam
    /// Couleur validée ou remise en automatique : l'onglet Équipes joue le retour « sélection » (spec finitions §3) ; la
    /// feuille se ferme aussitôt, le retour est donc joué par l'écran qui reste.
    let onPicked: () -> Void
    @State private var color: Color

    init(team: FollowedTeam, onPicked: @escaping () -> Void = {}) {
        self.team = team
        self.onPicked = onPicked
        _color = State(initialValue: Palette.team(team.colorHex))
    }

    /// Couleur à enregistrer en choix manuel : nil si la couleur choisie est celle déjà affichée (comparée à la couleur
    /// de départ après le même aller-retour par le sélecteur, pour qu'une dérive d'arrondi ne compte pas comme un changement).
    static func hexToSave(team: FollowedTeam, picked: Color) -> String? {
        let shown = RGB(color: Palette.team(team.colorHex)).hex
        let chosen = RGB(color: picked).hex
        return chosen == shown ? nil : chosen
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: team.name, dot: color)
                    HStack(spacing: 10) {
                        TeamBadge(code: team.code, tint: color, size: 34)
                        Text(team.code).font(Typo.score)
                    }
                }
                .foregroundStyle(Palette.text)
                .glassCard(tint: color)
                ColorPicker("Couleur de l'équipe", selection: $color, supportsOpacity: false)
                    .font(Typo.body)
                    .foregroundStyle(Palette.text)
                    .glassCard(radius: Radius.inner, padding: 14)
                Button("Couleur automatique (tirée du logo)") {
                    store.setColorOverride(nil, id: team.id)
                    onPicked()
                    dismiss()
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.accent)
                Spacer()
            }
            .padding(16)
            .abyssBackground()
            .navigationTitle("Couleur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") {
                        // Aucun changement : rien n'est écrit (une couleur automatique ne devient pas un choix manuel).
                        if let hex = Self.hexToSave(team: team, picked: color) {
                            store.setColorOverride(hex, id: team.id)
                            onPicked()
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
