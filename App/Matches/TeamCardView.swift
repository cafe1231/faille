import LoLKit
import SwiftUI

/// Carte Vitrail d'une équipe suivie (spec §5.1) : en direct, prochain, dernier.
/// Chaque match est un lien vers son Détail ; l'anti-spoiler (§8) vient de LoLKit.
/// Finitions : lignes qui s'enfoncent au toucher, chiffres qui défilent, halo « en direct », lueur d'équipe pour un
/// match en direct non masqué, révélation qui sort d'un flou avec un retour haptique.
struct TeamCardView: View {
    @Environment(AppStore.self) private var store
    let card: TeamCard
    /// Espace de noms du zoom carte → Détail ; nil : transition standard.
    var zoom: Namespace.ID? = nil
    @ReduceMotion var reduceMotion
    /// Retours haptiques de la carte : elle reste à l'écran quand « toucher pour révéler » disparaît.
    @State private var haptics = HapticTrigger()

    private var tint: Color {
        Palette.team(card.team.colorHex)
    }

    /// Lueur d'équipe (spec finitions §12) : seulement pour un match en direct (en jeu ou entre deux games) que LoLKit
    /// n'a pas masqué. `state` est déjà passé par `displayed(for:)` : un match que l'API donne pour terminé ne brille pas.
    static func glows(_ state: LiveMatchState?) -> Bool {
        guard let state, !state.spoilerFree else { return false }
        return state.phase == .inGame || state.phase == .betweenGames
    }

    /// Squelette de la ligne de stats : match en jeu, non masqué, dont Riot fournit les stats mais dont la première frame
    /// n'est pas encore arrivée (typiquement juste après « toucher pour révéler », les stats d'un match masqué n'étant
    /// jamais demandées). Il tient la place de `MiniStats` : la carte ne grandit pas d'un coup quand elles arrivent.
    /// Jamais pour un état masqué, même si la vue ne l'appelle déjà que dans la branche non masquée.
    static func showsStatsSkeleton(_ state: LiveMatchState) -> Bool {
        !state.spoilerFree && state.phase == .inGame && state.statsAvailable && state.stats == nil
    }

    var body: some View {
        // Jamais `card.next` directement : la ligne « Prochain » passe par LoLKit (anti-spoiler, spec §8).
        let nextLine = store.nextLine(for: card)
        // Un match que `getLive` donne pour terminé est « Terminé », jamais « En direct » (spec §8).
        let liveState = card.live.map { store.liveState(for: $0).displayed(for: $0) }
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: header, dot: tint)
            if let live = card.live, let liveState {
                liveBlock(live, state: liveState)
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
        .teamGlow(tint, active: Self.glows(liveState))
        .haptics(haptics)
    }

    private var header: String {
        [card.team.name, card.team.homeLeagueName].compactMap { $0 }.joined(separator: " · ")
    }

    /// « Toucher pour révéler » (spec §8) : le score sort d'un flou en fondu (`Motion.reveal`), avec un retour haptique.
    private func reveal(_ matchId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.reveal(matchId: matchId)
        }
    }

    @ViewBuilder private func liveBlock(_ event: MatchEvent, state: LiveMatchState) -> some View {
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let teams = order.map { event.match.teams[$0] }
        let icon = LiveChipText.icon(for: state.phase)
        let route = MatchRoute(teamId: card.team.id, row: .live, matchId: event.id)
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Chip(muted: icon != .live) {
                        ChipIcon(icon: icon, size: 12)
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
                    // Jamais rendus tant que le match est masqué ; à la révélation, ils sortent d'un flou (spec
                    // finitions §8). Même espacement que le bloc : la mise en page ne change pas. Les stats d'un match
                    // masqué n'étant jamais demandées, elles arrivent après la révélation : un squelette tient leur place
                    // (même hauteur), puis elles le remplacent en fondu (`Motion.reveal`) sans que les cartes sautent.
                    VStack(alignment: .leading, spacing: 8) {
                        ScoreRow(teams: teams, score: state.seriesScore.flatMap { reorder($0, order) },
                                 tints: teams.map { store.tint(for: $0) })
                        if let stats = state.stats.flatMap({ reorder($0, order) }) {
                            MiniStats(stats: stats, tint: tint)
                        } else if Self.showsStatsSkeleton(state) {
                            MiniStatsSkeleton()
                        } else if !state.statsAvailable {
                            Text("Stats live non fournies par Riot")
                                .font(Typo.secondary)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .animation(Motion.animation(.reveal, reduceMotion: reduceMotion), value: state.stats == nil)
                    .transition(Motion.revealTransition(reduceMotion: reduceMotion))
                }
            }
            .contentShape(Rectangle())
            .zoomSource(route.sourceID, in: zoom)
        }
        .buttonStyle(.pressable)
        if state.spoilerFree {
            RevealButton { reveal(event.id) }
        }
    }

    /// `NextLine.hidden` (spec §8) : dernier match masqué, ou prochain match contre une autre équipe suivie en
    /// anti-spoiler dont le dernier match est masqué (règle C) ; ligne fixe, qu'un prochain match existe ou non. Pas un
    /// lien : rien à ouvrir.
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
        let route = MatchRoute(teamId: card.team.id, row: .next, matchId: event.id)
        return NavigationLink(value: route) {
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
            .zoomSource(route.sourceID, in: zoom)
        }
        .buttonStyle(.pressable)
    }

    /// « Dernier · GEN 3 – 0 HLE » ; masqué : « Dernier · T1 vs GEN · Terminé · sam. 11 oct. · 09:00 » (aucun résultat, spec §8).
    private func lastRow(_ event: MatchEvent) -> some View {
        let line = store.scoreLine(event)
        let order = store.follows.displayOrder(event.match.teams, preferring: card.team)
        let text = Format.lastRow(line, order: order, date: Format.matchDate(event.startTime))
        let route = MatchRoute(teamId: card.team.id, row: .last, matchId: event.id)
        return NavigationLink(value: route) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .zoomSource(route.sourceID, in: zoom)
        }
        .buttonStyle(.pressable)
    }
}
