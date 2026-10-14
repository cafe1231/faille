import LoLKit
import SwiftUI

/// « En direct maintenant » (spec saison §2.2) : équipes suivies d'abord, puis ligues suivies, puis internationaux ;
/// score et « Regarder » ; masqué → « En direct » seul (ni score ni « Regarder »). Le halo « en direct » respire sur les
/// 3 premières lignes seulement (aucune animation continue au-delà). Aucun match en cours : la section n'existe pas.
struct LiveNowSection: View {
    let items: [HomeLiveItem]
    let onHaptic: (Haptic) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: String(localized: "En direct maintenant"))
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        if index < 3 {
                            LiveIndicator(size: 12)
                        } else {
                            IconView(icon: .live, size: 12)
                        }
                        MatchLine(event: item.event)
                    }
                    if let watch = WatchLinks.live(item.event.streams, inProgress: true, masked: item.masked) {
                        WatchButton(live: watch, compact: true, onHaptic: onHaptic)
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }
}
