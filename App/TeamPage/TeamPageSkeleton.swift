import SwiftUI

/// Chargement de la page d'équipe (disque de la saison pas encore lu, spec finitions §10) : le gabarit de chaque bloc.
struct TeamPageSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SkeletonBlock(width: 220, height: 12)
            SeasonSkeletonCard(lines: 2, label: String(localized: "Bilan en chargement"))
            SeasonSkeletonCard(lines: 3, label: String(localized: "Moyennes en chargement"))
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(width: 40, height: 40, radius: 9)
                }
            }
            .glassCard(radius: Radius.inner, padding: 14)
            .accessibilityHidden(true)
        }
    }
}
