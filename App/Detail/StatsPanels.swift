import LoLKit
import SwiftUI

/// Stats d'équipe de la game choisie (spec §5.3) : kills, gold et barre d'écart, tours, inhibiteurs, drakes (types), barons.
struct TeamStatsPanel: View {
    let left: TeamStats
    let right: TeamStats
    /// Couleur de l'équipe de gauche (barre de gold).
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            row(.swords, String(localized: "Kills"), "\(left.kills)", "\(right.kills)")
            row(.gold, String(localized: "Gold"), Format.gold(left.gold), Format.gold(right.gold))
            GoldBar(left: left.gold, right: right.gold, tint: tint)
            row(.tower, String(localized: "Tours"), "\(left.towers)", "\(right.towers)")
            row(.inhib, String(localized: "Inhibiteurs"), "\(left.inhibitors)", "\(right.inhibitors)")
            dragonRow
            row(.baron, String(localized: "Barons"), "\(left.barons)", "\(right.barons)")
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func row(_ icon: Icon, _ label: String, _ a: String, _ b: String) -> some View {
        // Les chiffres défilent quand ils changent (spec finitions §4) ; le panneau n'existe que pour un match non masqué.
        HStack {
            Text(a)
                .sora(.stat)
                .numericChange(a)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: icon, text: label)
            Text(b)
                .sora(.stat)
                .numericChange(b)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(label, a, b)))
    }

    /// « Kills : 7 à 4 » : une ligne de stats lue d'un bloc.
    static func spoken(_ label: String, _ left: String, _ right: String) -> String {
        String(localized: "\(label) : \(left) à \(right)")
    }

    private var dragonRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(left.dragons.count)").sora(.stat).numericChange(left.dragons.count)
                if !left.dragons.isEmpty {
                    // Une ligne, quelle que soit la game : le panneau garde sa hauteur (audit B-D4).
                    Text(Format.dragons(left.dragons))
                        .sora(.secondary)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: .drake, text: String(localized: "Drakes"))
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(right.dragons.count)").sora(.stat).numericChange(right.dragons.count)
                if !right.dragons.isEmpty {
                    Text(Format.dragons(right.dragons))
                        .sora(.secondary)
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(String(localized: "Drakes"), "\(left.dragons.count)",
                                             "\(right.dragons.count)")))
    }
}

/// Libellé central d'une ligne de stats : icône + étiquette en capitales.
struct StatLabel: View {
    let icon: Icon
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            IconView(icon: icon, size: 13)
            Text(text)
                .sora(.label)
                .tracking(Typo.labelTracking)
                .textCase(.uppercase)
        }
        .foregroundStyle(Palette.secondary)
        .frame(minWidth: 96)
    }
}

/// Barre d'écart de gold : la part de l'équipe de gauche, à sa couleur. Sa largeur glisse vers la nouvelle part
/// (`Motion.smooth`, spec finitions §9) ; immédiate sous « Réduire les animations ».
struct GoldBar: View {
    let left: Int
    let right: Int
    let tint: Color
    @ReduceMotion var reduceMotion

    var body: some View {
        let share = CGFloat(left) / CGFloat(max(1, left + right))
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill(.track))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * share)
                    .shadow(color: tint, radius: 4)
            }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
        .animation(Motion.animation(.smooth, reduceMotion: reduceMotion), value: share)
    }
}
