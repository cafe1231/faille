import LoLKit
import SwiftUI

/// Remet des valeurs d'un match (score, stats) dans l'ordre d'affichage ; nil si les tailles ne correspondent pas.
func reorder<T>(_ values: [T], _ order: [Int]) -> [T]? {
    guard values.count == order.count, order.allSatisfy({ values.indices.contains($0) }) else { return nil }
    return order.map { values[$0] }
}

/// « En direct · Game 2 · 18:42 » : le chrono tourne seul (minuteur natif), figé si la game est en pause ou finie.
/// Masqué (spec §8) : « En direct » ou « En direct vs FLY », rien d'autre.
struct LiveChipText: View {
    let state: LiveMatchState
    let opponent: String?

    var body: some View {
        if state.spoilerFree {
            Text(opponent.map { "En direct vs \($0)" } ?? "En direct")
        } else {
            HStack(spacing: 0) {
                Text(prefix)
                if state.phase == .inGame, let start = state.gameClockStart {
                    Text(" · ")
                    if let stopped = state.gameClockStoppedAt {
                        Text(Format.clock(stopped.timeIntervalSince(start)))
                    } else {
                        Text(start, style: .timer)
                    }
                }
            }
            .monospacedDigit()
        }
    }

    private var prefix: String {
        switch state.phase {
        case .inGame:
            return state.gameNumber.map { "En direct · Game \($0)" } ?? "En direct"
        case .betweenGames:
            return state.gameNumber.map { "En direct · Game \($0) bientôt" } ?? "En direct"
        case .finished:
            return "Terminé"
        case .upcoming:
            return "Bientôt"
        }
    }
}

/// « [KC] KC   1 – 0   C9 [C9] » : badges, codes, score de série au centre (« vs » sans score).
struct ScoreRow: View {
    @Environment(AppStore.self) private var store
    let teams: [MatchTeam]
    let score: [Int]?
    let tints: [Color?]
    var large = false

    var body: some View {
        HStack(spacing: 8) {
            if let left = teams.first {
                badge(left, tint: tints.first ?? nil)
                Text(left.code)
                    .font(Typo.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let score {
                Text(Format.score(score))
                    .font(large ? Typo.scoreLarge : Typo.score)
                    .monospacedDigit()
            } else {
                Text("vs")
                    .font(Typo.bodyMedium)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            if teams.count > 1 {
                Text(teams[1].code)
                    .font(Typo.headline)
                    .lineLimit(1)
                badge(teams[1], tint: tints.count > 1 ? tints[1] : nil)
            }
        }
    }

    private func badge(_ team: MatchTeam, tint: Color?) -> some View {
        TeamBadge(code: team.code, logoFile: store.logoFile(for: team.image), tint: tint,
                  size: large ? 38 : 30)
    }
}

/// Ligne de stats d'une carte (spec §5.1) : kills, écart de gold, drakes, tours ; équipe de gauche d'abord.
struct MiniStats: View {
    let stats: [TeamStats]
    let tint: Color

    var body: some View {
        if stats.count == 2 {
            let diff = stats[0].gold - stats[1].gold
            HStack(spacing: 14) {
                item(.swords, "\(stats[0].kills) – \(stats[1].kills)")
                HStack(spacing: 4) {
                    IconView(icon: .gold, size: 13)
                    Text(Format.goldDiff(diff))
                        .font(Sora.font(12, .bold))
                        .foregroundStyle(diff > 0 ? tint : Palette.secondary)
                }
                item(.drake, "\(stats[0].dragons.count) – \(stats[1].dragons.count)")
                item(.tower, "\(stats[0].towers) – \(stats[1].towers)")
            }
            .font(Typo.secondaryMedium)
            .monospacedDigit()
        }
    }

    private func item(_ icon: Icon, _ text: String) -> some View {
        HStack(spacing: 4) {
            IconView(icon: icon, size: 13)
            Text(text)
        }
    }
}

/// « Score masqué · toucher pour révéler » (spec §8) : la révélation est mémorisée pour ce match.
struct RevealButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                IconView(icon: .eyeOff, size: 13)
                Text("Score masqué · ")
                Text("toucher pour révéler")
                    .foregroundStyle(Palette.accent)
            }
            .font(Typo.secondaryMedium)
            .foregroundStyle(Palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
