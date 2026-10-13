import LoLKit
import SwiftUI

/// Carte Vitrail d'une équipe suivie (spec §5.1) : en direct, prochain, dernier.
/// Chaque match est un lien vers son Détail ; l'anti-spoiler (§8) vient de LoLKit.
struct TeamCardView: View {
    @Environment(AppStore.self) private var store
    let card: TeamCard

    private var tint: Color {
        Palette.team(card.team.colorHex)
    }

    var body: some View {
        // Jamais `card.next` directement : la ligne « Prochain » passe par LoLKit (anti-spoiler, spec §8).
        let nextLine = store.nextLine(for: card)
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: header, dot: tint)
            if let live = card.live {
                liveBlock(live)
            }
            switch nextLine {
            case let .match(next):
                nextRow(next)
            case .hidden:
                hiddenNextRow
            case .none:
                EmptyView()
            }
            if let last = card.last {
                lastRow(last)
            }
            if card.live == nil, card.last == nil, case .none = nextLine {
                Text("Aucun match dans le calendrier récent")
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }

    private var header: String {
        [card.team.name, card.team.homeLeagueName].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder private func liveBlock(_ event: MatchEvent) -> some View {
        // Un match que `getLive` donne pour terminé est « Terminé », jamais « En direct » (spec §8).
        let state = store.liveState(for: event).displayed(for: event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let teams = order.map { event.match.teams[$0] }
        let icon = LiveChipText.icon(for: state.phase)
        NavigationLink(value: MatchRoute(matchId: event.id)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip(muted: icon != .live) {
                        IconView(icon: icon, size: 12)
                        LiveChipText(state: state, opponent: teams.count == 2 ? teams[1].code : nil)
                    }
                    if state.spoilerFree {
                        Chip(muted: true) {
                            IconView(icon: .eyeOff, size: 12)
                            Text("masqué")
                        }
                    }
                }
                if !state.spoilerFree {
                    ScoreRow(teams: teams, score: state.seriesScore.flatMap { reorder($0, order) },
                             tints: teams.map { store.tint(for: $0) })
                    if let stats = state.stats.flatMap({ reorder($0, order) }) {
                        MiniStats(stats: stats, tint: tint)
                    } else if !state.statsAvailable {
                        Text("Stats live non fournies par Riot")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        if state.spoilerFree {
            RevealButton { store.reveal(matchId: event.id) }
        }
    }

    /// Dernier match masqué (spec §8) : ligne fixe, qu'un prochain match existe ou non. Pas un lien : rien à ouvrir.
    private var hiddenNextRow: some View {
        HStack(spacing: 6) {
            IconView(icon: .eyeOff, size: 13)
            Text("Prochain · masqué")
        }
        .font(Typo.secondary)
        .foregroundStyle(Palette.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « GEN vs FUR » / « Prochain · jeu. 16 oct. · 11:00 » ; si l'équipe joue déjà : « Ensuite · … vs GEN ».
    private func nextRow(_ event: MatchEvent) -> some View {
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let codes = reorder(line.teamCodes, order) ?? line.teamCodes
        let date = Format.matchDate(event.startTime)
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if card.live == nil {
                        Text(codes.joined(separator: " vs "))
                            .font(Typo.bodyMedium)
                        Text("Prochain · \(date)")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    } else {
                        Text("Ensuite · \(date) vs \(codes.last ?? "")")
                            .font(Typo.secondary)
                            .foregroundStyle(Palette.secondary)
                    }
                }
                Spacer()
                IconView(icon: .clock, size: 16)
                    .foregroundStyle(Palette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// « Dernier · GEN 3 – 0 HLE » ; masqué : « Dernier · T1 vs GEN · Terminé · sam. 11 oct. · 09:00 » (aucun résultat, spec §8).
    private func lastRow(_ event: MatchEvent) -> some View {
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let text = Format.lastRow(line, order: order, date: Format.matchDate(event.startTime))
        return NavigationLink(value: MatchRoute(matchId: event.id)) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
