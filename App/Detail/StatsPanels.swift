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
            row(.swords, "Kills", "\(left.kills)", "\(right.kills)")
            row(.gold, "Gold", Format.gold(left.gold), Format.gold(right.gold))
            GoldBar(left: left.gold, right: right.gold, tint: tint)
            row(.tower, "Tours", "\(left.towers)", "\(right.towers)")
            row(.inhib, "Inhibs", "\(left.inhibitors)", "\(right.inhibitors)")
            dragonRow
            row(.baron, "Barons", "\(left.barons)", "\(right.barons)")
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func row(_ icon: Icon, _ label: String, _ a: String, _ b: String) -> some View {
        // Les chiffres défilent quand ils changent (spec finitions §4) ; le panneau n'existe que pour un match non masqué.
        HStack {
            Text(a)
                .font(Typo.stat)
                .numericChange(a)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: icon, text: label)
            Text(b)
                .font(Typo.stat)
                .numericChange(b)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
    }

    private var dragonRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(left.dragons.count)").font(Typo.stat).numericChange(left.dragons.count)
                if !left.dragons.isEmpty {
                    Text(Format.dragons(left.dragons))
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            StatLabel(icon: .drake, text: "Drakes")
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(right.dragons.count)").font(Typo.stat).numericChange(right.dragons.count)
                if !right.dragons.isEmpty {
                    Text(Format.dragons(right.dragons))
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .monospacedDigit()
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
                .font(Typo.label)
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
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * share)
                    .shadow(color: tint, radius: 4)
            }
        }
        .frame(height: 5)
        .animation(Motion.animation(.smooth, reduceMotion: reduceMotion), value: share)
    }
}

/// Joueurs de la game (spec §5.3) : sélecteur d'équipe, puis rôle, champion, KDA, CS.
struct PlayersPanel: View {
    let teams: [MatchTeam]
    let snapshot: GameSnapshot
    @Binding var selection: Int

    var body: some View {
        let index = teams.indices.contains(selection) ? selection : 0
        let players = teams.indices.contains(index) ? (teams[index].id.flatMap { snapshot.players(for: $0) } ?? []) : []
        VStack(alignment: .leading, spacing: 8) {
            Picker("Équipe", selection: $selection) {
                ForEach(teams.indices, id: \.self) { position in
                    Text(teams[position].code).tag(position)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("").frame(width: 38, alignment: .leading)
                Text("Champion").frame(maxWidth: .infinity, alignment: .leading)
                Text("KDA").frame(width: 64, alignment: .leading)
                Text("CS").frame(width: 40, alignment: .trailing)
            }
            .font(Typo.label)
            .tracking(Typo.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.secondary)
            // Changement d'équipe animé (spec finitions §9) : les lignes de l'autre équipe arrivent en fondu (l'animation
            // vient de la liaison `selection`). Même espacement que le panneau : la mise en page ne change pas.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                    HStack {
                        Text(Format.role(player.role))
                            .foregroundStyle(Palette.secondary)
                            .frame(width: 38, alignment: .leading)
                        Text(Format.champion(player.champion))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.kda(player)).frame(width: 64, alignment: .leading)
                        Text("\(player.creepScore)").frame(width: 40, alignment: .trailing)
                    }
                    .font(Typo.secondaryMedium)
                    .monospacedDigit()
                }
                if players.isEmpty {
                    Text("Joueurs indisponibles")
                        .font(Typo.secondary)
                        .foregroundStyle(Palette.secondary)
                }
            }
            .id(index)
            .transition(.opacity)
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
