import LoLKit
import SwiftUI

/// Détail d'un match (spec §5.3) : en-tête teinté (ligue, bloc, Bo, chrono, équipes, score), pilules de games,
/// stats d'équipe et joueurs de la game choisie. Le bouton « Épingler sur l'écran verrouillé » arrive à l'étape 4.
/// Anti-spoiler (spec §8) : tant que le match est masqué, rien ne s'affiche sauf l'en-tête sans score et « toucher pour
/// révéler » (ni pilules de games, ni stats, ni joueurs).
struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var model: MatchDetailModel

    init(matchId: String) {
        _model = State(initialValue: MatchDetailModel(matchId: matchId))
    }

    /// Ce qui relance le chargement de la game affichée : un autre choix de game, ou la révélation du match
    /// (les stats arrivent aussitôt, sans attendre le cycle suivant de 10 s).
    private struct LoadKey: Equatable, Sendable {
        let game: Int?
        let revealed: Bool
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.run(store: store) }
        .task(id: LoadKey(game: model.selectedGameNumber, revealed: store.settings.revealedMatchIds.contains(model.matchId))) {
            await model.loadSelectedGame(store: store)
        }
    }

    @ViewBuilder private var content: some View {
        let event = store.event(id: model.matchId)
        let details = store.details[model.matchId]
        let teams = details?.match.teams ?? event?.match.teams ?? []
        let order = store.follows.displayOrder(teams)
        let ordered = order.map { teams[$0] }
        let masked = store.isMasked(teams, matchId: model.matchId)
        let state = store.detailState(matchId: model.matchId)
        let tint = ordered.compactMap { store.tint(for: $0) }.first
        header(event: event, details: details, teams: ordered, order: order, state: state, masked: masked, tint: tint)
        if masked {
            RevealButton { store.reveal(matchId: model.matchId) }
        } else if let details {
            gamePills(details)
            if details.statsDisabled || event?.statsDisabled == true {
                NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
            } else if let game = model.selectedGame(in: details) {
                gameStats(game: game, teams: ordered)
            }
        } else if model.attempted {
            NoteCard(icon: .refresh, text: "Détails du match indisponibles pour l'instant")
        } else {
            ProgressView()
                .tint(Palette.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func header(event: MatchEvent?, details: EventDetails?, teams: [MatchTeam], order: [Int],
                        state: LiveMatchState?, masked: Bool, tint: Color?) -> some View {
        let league = details?.league.name ?? event?.league.name ?? ""
        let bestOf = details?.bestOf ?? event?.bestOf ?? 1
        let meta = [league, event?.blockName ?? "", "Bo\(bestOf)"].filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(meta)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // La pastille ne se coupe ni ne passe à la ligne : c'est le texte de gauche qui s'abrège.
                statusChip(event: event, state: state)
                    .lineLimit(1)
                    .fixedSize()
            }
            ScoreRow(teams: teams, score: seriesScore(event: event, state: state, order: order, masked: masked),
                     tints: teams.map { store.tint(for: $0) }, large: true)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }

    /// Score de série dans l'ordre d'affichage ; nil si masqué ou pas commencé (R-M5). Détails chargés : le score de
    /// `LiveMatchBuilder.state` (anti-spoiler appliqué par LoLKit) ; sinon celui de `Presenter.scoreLine`, jamais les
    /// victoires brutes du match.
    private func seriesScore(event: MatchEvent?, state: LiveMatchState?, order: [Int], masked: Bool) -> [Int]? {
        guard !masked else { return nil }
        if let state {
            return state.phase == .upcoming ? nil : state.seriesScore.flatMap { reorder($0, order) }
        }
        guard let event else { return nil }
        return store.scoreLine(event).score.flatMap { reorder($0, order) }
    }

    @ViewBuilder private func statusChip(event: MatchEvent?, state: LiveMatchState?) -> some View {
        switch state?.phase ?? phase(of: event) {
        case .inGame, .betweenGames:
            Chip {
                IconView(icon: .live, size: 12)
                if let state {
                    LiveChipText(state: state, opponent: nil)
                } else {
                    Text("En direct")
                }
            }
        case .finished:
            Chip(muted: true) {
                IconView(icon: .check, size: 12)
                Text("Terminé")
            }
        case .upcoming:
            Chip(muted: true) {
                IconView(icon: .clock, size: 12)
                Text(event.map { Format.matchDate($0.startTime) } ?? "À venir")
            }
        }
    }

    private func phase(of event: MatchEvent?) -> LiveMatchState.Phase {
        switch event?.state {
        case .inProgress: return .inGame
        case .completed: return .finished
        default: return .upcoming
        }
    }

    /// « G1 ✓ », « G2 · en direct », « G3 »… une pilule par game jouée ou à venir.
    private func gamePills(_ details: EventDetails) -> some View {
        let games = details.match.games.filter { $0.state != .unneeded }
        let selected = model.selectedGame(in: details)?.number
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(games, id: \.number) { game in
                    PillButton(selected: game.number == selected, action: { model.selectedGameNumber = game.number }) {
                        Text(game.state == .inProgress ? "G\(game.number) · en direct" : "G\(game.number)")
                        if game.state == .completed {
                            IconView(icon: .check, size: 12)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private func gameStats(game: GameRef, teams: [MatchTeam]) -> some View {
        let ids = teams.compactMap(\.id)
        if game.state == .unstarted {
            NoteCard(icon: .clock, text: "La game \(game.number) n'a pas commencé")
        } else if store.statsUnavailable.contains(game.id) {
            NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
        } else if let snapshot = store.snapshots[game.id], ids.count == 2,
                  let left = snapshot.stats(for: ids[0]), let right = snapshot.stats(for: ids[1]) {
            TeamStatsPanel(left: left, right: right, tint: store.tint(for: teams[0]) ?? Palette.accent)
            PlayersPanel(teams: teams, snapshot: snapshot, selection: $model.playersTeamIndex)
        } else {
            NoteCard(icon: .refresh, text: game.state == .inProgress ? "Stats en chargement…" : "Stats de cette game indisponibles")
        }
    }
}

#Preview {
    NavigationStack { MatchDetailView(matchId: SampleData.kcMatchId) }.environment(AppStore(preview: .standard))
}
