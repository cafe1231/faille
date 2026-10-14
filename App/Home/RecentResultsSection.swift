import LoLKit
import SwiftUI

/// « Résultats récents » (spec saison §2.2) : 72 h, 8 au plus, suivis d'abord ; masqué → « Terminé · toucher pour
/// révéler » (la ligne entière révèle, `store.reveal`).
struct RecentResultsSection: View {
    let events: [MatchEvent]
    let onReveal: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: String(localized: "Résultats récents"))
            if events.isEmpty {
                Text("Pas de résultat ces 3 derniers jours").sora(.secondary).foregroundStyle(Palette.secondary)
            } else {
                ForEach(events) { event in
                    MatchLine(event: event, showsDay: true, onReveal: onReveal)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 12)
    }
}
