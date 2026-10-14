import LoLKit
import SwiftUI

/// Sous les pilules de « Toutes les ligues » (spec saison §3.5) : « Suivre la ligue » (étoile), « Suivre ses N
/// équipes », et pour une ligue suivie l'interrupteur des notifications de début de ses matchs (désactivées par défaut).
struct LeagueFollowRow: View {
    let league: League
    let followed: Bool
    let notifies: Bool
    let teamCount: Int
    let allTeamsFollowed: Bool
    let onToggleFollow: () -> Void
    let onFollowAll: () -> Void
    let onToggleNotifications: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onToggleFollow) {
                    HStack(spacing: 6) {
                        IconView(icon: followed ? .starFill : .star, size: 18)
                            .foregroundStyle(followed ? Palette.accent : Palette.secondary)
                        (followed ? Text("Ligue suivie") : Text("Suivre la ligue")).sora(.bodyMedium)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(followed ? Text("Ne plus suivre \(league.name)") : Text("Suivre \(league.name)"))
                Spacer()
                if teamCount > 0, !allTeamsFollowed {
                    Button(action: onFollowAll) {
                        Text("Suivre ses \(teamCount) équipes").sora(.secondaryMedium).foregroundStyle(Palette.accent)
                            .frame(minHeight: 44)
                    }
                }
            }
            if followed {
                Toggle(isOn: Binding(get: { notifies }, set: onToggleNotifications)) {
                    Text("Prévenir au début de ses matchs").sora(.secondary)
                }
                .tint(Palette.accent)
            }
        }
        .buttonStyle(.pressable)
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 12)
    }
}
