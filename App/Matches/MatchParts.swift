import LoLKit
import SwiftUI

extension LiveMatchState {
    /// État à afficher dans une pastille. Un match que l'API donne pour terminé (`getLive` ou calendrier) est « Terminé »,
    /// même si ses victoires ou ses détails n'ont pas encore rattrapé la fin de la série (spec §8 : jamais « En direct »
    /// pour un match masqué terminé).
    func displayed(for event: MatchEvent?) -> LiveMatchState {
        guard event?.state == .completed, phase != .finished else { return self }
        var copy = self
        copy.phase = .finished
        copy.gameNumber = nil
        copy.gameClockStart = nil
        copy.gameClockStoppedAt = nil
        return copy
    }
}

/// « En direct · Game 2 · 18:42 » : le chrono tourne seul (minuteur natif), figé si la game est en pause ou finie.
/// Masqué (spec §8) : « En direct », « Terminé » ou « À venir » (suivi de « vs FLY » si l'adversaire est donné), rien d'autre.
struct LiveChipText: View {
    let state: LiveMatchState
    let opponent: String?

    /// Icône de la pastille : « en direct » n'accompagne que l'état en direct.
    static func icon(for phase: LiveMatchState.Phase) -> Icon {
        switch phase {
        case .inGame, .betweenGames: return .live
        case .finished: return .check
        case .upcoming: return .clock
        }
    }

    /// Texte d'un match masqué : seulement l'état (entre deux games, un match masqué reste « En direct »).
    static func maskedText(phase: LiveMatchState.Phase, opponent: String?) -> String {
        let label = Format.maskedStatus(phase)
        return opponent.map { "\(label) vs \($0)" } ?? label
    }

    var body: some View {
        if state.spoilerFree {
            Text(Self.maskedText(phase: state.phase, opponent: opponent))
        } else {
            HStack(spacing: 0) {
                Text(Self.prefix(for: state))
                if state.phase == .inGame, let start = state.gameClockStart {
                    Text(" · ")
                    if let stopped = state.gameClockStoppedAt {
                        // Chrono figé (pause, fin de game) : ses chiffres défilent quand il change (spec finitions §4).
                        Text(Format.clock(stopped.timeIntervalSince(start)))
                            .numericChange(stopped.timeIntervalSince(start))
                    } else {
                        Text(start, style: .timer)
                    }
                }
            }
            .monospacedDigit()
        }
    }

    /// Libellé d'un match non masqué (le chrono suit pour une game en cours).
    static func prefix(for state: LiveMatchState) -> String {
        switch state.phase {
        case .inGame:
            return state.gameNumber.map { "En direct · Game \($0)" } ?? "En direct"
        case .betweenGames:
            return state.gameNumber.map { "En direct · Game \($0) bientôt" } ?? "En direct"
        case .finished:
            return "Terminé"
        case .upcoming:
            return "À venir"
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
    @ReduceMotion var reduceMotion

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
                // Score non masqué (nil quand masqué : rien ne peut défiler) ; à la révélation, il sort d'un flou
                // (spec finitions §4, §8).
                Text(Format.score(score))
                    .font(large ? Typo.scoreLarge : Typo.score)
                    .monospacedDigit()
                    .numericChange(score)
                    .transition(Motion.revealTransition(reduceMotion: reduceMotion))
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
/// Les chiffres défilent quand ils changent (spec finitions §4) ; cette ligne n'existe que pour un match non masqué.
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
                        .numericChange(diff)
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
                .numericChange(text)
        }
    }
}

/// Place de `MiniStats` tant que la première frame du match n'est pas arrivée (spec finitions §10) : quatre blocs de
/// squelette sur une ligne de la hauteur de `MiniStats` (le texte masqué porte la même police), pour que la carte garde
/// sa taille quand les stats la remplacent.
struct MiniStatsSkeleton: View {
    var body: some View {
        Text("0")
            .font(Typo.secondaryMedium)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonBlock(width: 44, height: 11)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stats en chargement")
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
        .buttonStyle(.pressable)
    }
}
