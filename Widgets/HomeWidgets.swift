import LoLKit
import SwiftUI
import WidgetKit

/// Petit widget (spec §7) : le prochain match d'une équipe suivie, teinté à sa couleur ; l'équipe se choisit dans les
/// réglages du widget (par défaut, la première suivie).
struct TeamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FailleTeam", intent: SelectTeamIntent.self, provider: TeamProvider()) { entry in
            TeamWidgetView(entry: entry)
        }
        .configurationDisplayName("Mon équipe")
        .description("Le prochain match d'une équipe suivie, à sa couleur.")
        .supportedFamilies([.systemSmall])
    }
}

struct TeamWidgetView: View {
    let entry: TeamEntry

    var body: some View {
        let team = entry.content.team(id: entry.teamId)
        SmallWidgetView(team: team)
            .containerBackground(for: .widget) {
                WidgetBackdrop(tint: team.map { Palette.team($0.team.colorHex) })
            }
    }
}

/// Moyen widget (spec §7) : matchs en direct, puis prochains matchs de toutes les équipes suivies.
struct TeamsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FailleTeams", provider: FailleProvider()) { entry in
            MediumWidgetView(content: entry.content)
                .containerBackground(for: .widget) { WidgetBackdrop(tint: nil) }
        }
        .configurationDisplayName("Mes équipes")
        .description("Les matchs en direct, puis les prochains matchs de tes équipes.")
        .supportedFamilies([.systemMedium])
    }
}
