import LoLKit
import SwiftUI

/// Une équipe de la draft : code, couleur (Vitrail si suivie) et ses cinq champions (ids Data Dragon).
struct DraftTeam: Equatable {
    let code: String
    let tint: Color?
    let champions: [String]
}

/// Draft de la game (spec fonctionnalités §3), en haut des stats du Détail : les cinq champions de chaque équipe, dans
/// l'ordre d'affichage des équipes, en icônes Data Dragon (vignettes de repli tant que la version n'est pas connue).
/// Aucune requête de plus : les champions viennent du flux `window` déjà lu.
struct DraftStrip: View {
    let teams: [DraftTeam]
    let version: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                HStack(spacing: 8) {
                    Text(team.code)
                        .font(Typo.label)
                        .tracking(Typo.labelTracking)
                        .foregroundStyle(team.tint ?? Palette.secondary)
                        .lineLimit(1)
                        .frame(width: 36, alignment: .leading)
                    ForEach(Array(team.champions.enumerated()), id: \.offset) { _, champion in
                        DDragonIcon(url: version.map { DataDragon.championImage(version: $0, championId: champion) },
                                    size: 40, fallback: DDragonIcon.initials(champion))
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(team.code) : \(team.champions.map(Format.champion).joined(separator: ", "))")
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
