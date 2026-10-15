import LoLKit
import SwiftUI

/// Une équipe de la game telle que le fil et la courbe la montrent : code et couleur (Vitrail si suivie).
struct TimelineTeam: Equatable {
    let id: String
    let code: String
    let tint: Color
}

/// Fil des événements de la game (spec fonctionnalités §4) : du plus récent au plus ancien, temps de jeu, icône de la DA
/// (épées, drake, baron, tour, inhibiteur), équipe à sa couleur. Dix lignes, puis « Tout le fil ». N'existe que pour un
/// match non masqué.
struct TimelineCard: View {
    /// Événements dans l'ordre chronologique (`TimelineStore.events`).
    let events: [TimelineEvent]
    /// Les deux équipes, dans l'ordre d'affichage.
    let teams: [TimelineTeam]
    /// Relecture en cours : gabarit tant que rien n'est arrivé.
    var loading = false
    @State private var expanded = false

    static let collapsedCount = 10

    var body: some View {
        let recent = Array(events.reversed())
        let shown = expanded ? recent : Array(recent.prefix(Self.collapsedCount))
        VStack(alignment: .leading, spacing: 10) {
            StatLabel(icon: .swords, text: String(localized: "Fil de la game"))
                .frame(maxWidth: .infinity, alignment: .leading)
            if recent.isEmpty {
                if loading {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonBlock(height: 14)
                    }
                } else {
                    Text("Rien de marquant pour l'instant")
                        .sora(.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, event in
                row(event)
            }
            if recent.count > Self.collapsedCount {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? String(localized: "Réduire le fil") : String(localized: "Tout le fil (\(recent.count))"))
                        .sora(.secondaryMedium)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func row(_ event: TimelineEvent) -> some View {
        let team = teams.first { $0.id == event.teamId }
        let tint = team?.tint ?? Palette.secondary
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Format.clock(event.gameTime))
                .sora(.secondaryMedium)
                .foregroundStyle(Palette.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .leading)
            IconView(icon: Self.icon(event.kind), size: 14)
                .foregroundStyle(tint)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(team?.code ?? "")
                .sora(.secondaryMedium)
                .foregroundStyle(tint)
            Text(TimelineText.text(event))
                .sora(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Icône de la DA de chaque événement.
    static func icon(_ kind: TimelineEvent.Kind) -> Icon {
        switch kind {
        case .kills: return .swords
        case .dragon: return .drake
        case .baron: return .baron
        case .tower: return .tower
        case .inhibitor: return .inhib
        }
    }
}
