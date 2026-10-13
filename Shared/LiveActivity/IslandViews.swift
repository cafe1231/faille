import LoLKit
import SwiftUI

// MARK: - Dynamic Island (spec §6.2, maquette ①)

/// Compacte : un côté de la caméra — monogramme et victoires ; masqué : le monogramme seul.
struct IslandCompactView: View {
    let display: LiveActivityDisplay
    /// 0 : à gauche de la caméra ; 1 : à droite.
    let side: Int

    var body: some View {
        let team = display.teams.indices.contains(side) ? display.teams[side] : nil
        let wins = display.score.flatMap { $0.indices.contains(side) ? $0[side] : nil }
        HStack(spacing: 5) {
            if side == 1, let wins {
                Text("\(wins)")
            }
            if let team {
                MonogramBadge(code: team.code, tint: team.colorHex.map(Palette.team), size: 20)
            }
            if side == 0, let wins {
                Text("\(wins)")
            }
        }
        .font(Sora.font(14, .bold))
        .monospacedDigit()
        .foregroundStyle(Color.white)
    }
}

/// Minimale : code de l'équipe suivie et score ; masqué : son monogramme seul.
struct IslandMinimalView: View {
    let display: LiveActivityDisplay

    var body: some View {
        if let team = display.teams.first {
            if let score = display.compactScore {
                VStack(spacing: 0) {
                    Text(team.code)
                        .font(Sora.font(8, .bold))
                        .foregroundStyle(team.colorHex.map(Palette.team) ?? Color.white)
                    Text(score)
                        .font(Sora.font(11, .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                MonogramBadge(code: team.code, tint: team.colorHex.map(Palette.team), size: 22)
            }
        }
    }
}

/// Déployée, à gauche et à droite : monogramme et code d'une équipe.
struct IslandTeamView: View {
    let side: LiveActivityDisplay.Side?

    var body: some View {
        if let side {
            VStack(spacing: 3) {
                MonogramBadge(code: side.code, tint: side.colorHex.map(Palette.team), size: 30)
                Text(side.code)
                    .font(Sora.font(11, .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color.white)
            }
        }
    }
}

/// Déployée, au centre : score (« vs » si masqué) et « Game 2 · 18:42 », ou l'état.
struct IslandCenterView: View {
    let display: LiveActivityDisplay

    var body: some View {
        VStack(spacing: 4) {
            if let score = display.score, score.count == 2 {
                Text(Format.score(score))
                    .font(Sora.font(26, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            } else {
                Text("vs")
                    .font(Sora.font(15, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            LiveActivityStatusView(status: display.status, prefix: display.gameNumber.map { "Game \($0) · " })
                .font(Sora.font(10, .semibold))
        }
    }
}

/// Déployée, en bas : les 5 stats sur une ligne (« 7–4 », « +2,1k »…), ou le message.
struct IslandBottomView: View {
    let display: LiveActivityDisplay

    var body: some View {
        if display.rows.isEmpty {
            if let message = display.message {
                LiveActivityMessageView(message: message)
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(display.rows.enumerated()), id: \.element.stat) { index, row in
                    if index > 0 {
                        Spacer(minLength: 4)
                    }
                    HStack(spacing: 3) {
                        IconView(icon: row.stat.icon, size: 11)
                            .foregroundStyle(Palette.secondary)
                        Text(row.compact)
                            .foregroundStyle(color(of: row))
                    }
                }
            }
            .font(Sora.font(11, .semibold))
            .monospacedDigit()
            .opacity(display.faded ? 0.55 : 1)
        }
    }

    /// L'écart de gold à la couleur de l'équipe qui mène (si elle est suivie), le reste en blanc.
    private func color(of row: LiveActivityDisplay.Row) -> Color {
        guard let leader = row.leader, display.teams.indices.contains(leader) else { return Color.white }
        return display.teams[leader].colorHex.map(Palette.team) ?? Color.white
    }
}
