import LoLKit
import SwiftUI

/// Présentation de « À ne pas rater » : carte d'en-tête de l'Accueil (1 en grand + 2 lignes), ou liste en tête de Matchs.
enum MustWatchStyle {
    case card, list
}

/// « À ne pas rater » (spec saison §3.6) : matchs du jour classés par enjeu, avec la ligne d'explication et « Comment
/// c'est calculé ». Le classement (et ses exclusions anti-spoiler) vient de LoLKit ; les lignes passent par `MatchLine`.
/// Rien à proposer : la section n'existe pas.
struct MustWatchSection: View {
    @Environment(AppStore.self) private var store
    let picks: [MustWatchPick]
    var style: MustWatchStyle = .card
    @State private var showsScoring = false

    var body: some View {
        if let first = picks.first {
            let tint = first.event.match.teams.compactMap { store.tint(for: $0) }.first
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(text: String(localized: "À ne pas rater"), dot: tint)
                    Button { showsScoring = true } label: {
                        Text("Comment c'est calculé").sora(.label).foregroundStyle(Palette.accent)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }
                ForEach(Array(picks.enumerated()), id: \.element.event.id) { index, pick in
                    VStack(alignment: .leading, spacing: 2) {
                        MatchLine(event: pick.event, showsDay: true)
                            .scaleEffect(style == .card && index == 0 ? 1.04 : 1, anchor: .leading)
                        Text(HomeTexts.explanation(pick))
                            .sora(.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    if index == 0, style == .card, picks.count > 1 {
                        Divider().overlay(Palette.glassBorder)
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(tint: style == .card ? tint : nil, radius: style == .card ? Radius.card : Radius.inner,
                       padding: style == .card ? 16 : 12)
            .sheet(isPresented: $showsScoring) { MustWatchScoringSheet() }
        }
    }
}

/// « Comment c'est calculé » : le barème de la spec §3.6 (points entiers) et la règle anti-spoiler.
struct MustWatchScoringSheet: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Comment c'est calculé").sora(.title).tracking(Typo.titleTracking)
                Text("Chaque match du jour gagne des points ; les plus hauts passent en premier, puis par heure de début.")
                    .sora(.secondary).foregroundStyle(Palette.secondary)
                ForEach(Array(HomeTexts.scoring.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(HomeTexts.reason(row.reason)).sora(.body)
                        Spacer()
                        Text(row.points).sora(.stat).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Les raisons tirées des résultats (classement, élimination, revanche) ne comptent pas quand le classement du tournoi est masqué.")
                    .sora(.secondary).foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            .padding(20)
        }
        .abyssBackground()
        .presentationDetents([.medium, .large])
    }
}
