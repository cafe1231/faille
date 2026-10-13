import LoLKit
import SwiftUI

/// Ligne de « Mes équipes » : badge, nom, ligue, œil (anti-spoiler), étoile (ne plus suivre).
struct FollowedTeamRow: View {
    let team: FollowedTeam
    let logoFile: URL?
    let onToggleSpoiler: () -> Void
    let onUnfollow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TeamBadge(code: team.code, logoFile: logoFile, tint: Palette.team(team.colorHex), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            // Deux cibles tactiles d'au moins 44 × 44 pt, côte à côte (le glyphe reste de 20 pt).
            HStack(spacing: 0) {
                Button(action: onToggleSpoiler) {
                    IconView(icon: team.spoilerFree ? .eyeOff : .eye, size: 20)
                        .foregroundStyle(team.spoilerFree ? Palette.text : Palette.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(team.spoilerFree ? "Afficher les scores" : "Masquer les scores")
                Button(action: onUnfollow) {
                    IconView(icon: .starFill, size: 20)
                        .foregroundStyle(Palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Ne plus suivre")
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let parts = [team.homeLeagueName, team.spoilerFree ? "sans spoiler" : nil].compactMap { $0 }
        return parts.isEmpty ? "sans ligue d'attache" : parts.joined(separator: " · ")
    }
}

/// Ligne d'une équipe du catalogue (ligue ou recherche) : badge, nom, ligue, étoile.
struct CatalogTeamRow: View {
    let team: Team
    let followed: Bool
    let logoFile: URL?
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TeamBadge(code: team.code, logoFile: logoFile, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                if let league = team.homeLeague?.name {
                    Text(league)
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onToggle) {
                IconView(icon: followed ? .starFill : .star, size: 20)
                    .foregroundStyle(followed ? Palette.accent : Palette.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(followed ? "Ne plus suivre" : "Suivre")
        }
        .padding(.vertical, 2)
    }
}
