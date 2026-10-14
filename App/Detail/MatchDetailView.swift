import LoLKit
import SwiftUI

/// Détail d'un match (spec §5.3) : en-tête teinté (ligue, bloc, Bo, chrono, équipes, score), pilules de games,
/// stats d'équipe et joueurs de la game choisie, et bouton « Épingler sur l'écran verrouillé » (iPhone, spec §6.4).
/// Anti-spoiler (spec §8) : tant que le match est masqué, rien ne s'affiche sauf l'en-tête sans score et « toucher pour
/// révéler » (ni pilules de games, ni stats, ni joueurs).
/// Finitions : capsule des pilules qui glisse, barre de gold et chiffres animés, révélation qui sort d'un flou,
/// squelettes de chargement, onglet des joueurs animé, retours haptiques (pilule, révélation, épingler, retirer).
/// Fonctionnalités : « Regarder » (match en direct) et « Revoir la game N » (game jouée), draft, courbe de l'écart de gold,
/// joueurs avec icônes, objets, runes et sorts d'invocateur (fiche au toucher), fil des événements. Rien de tout cela pour
/// un match masqué : ni affichage, ni requête (`MatchDetailModel.featureGame`).
struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    @State private var model: MatchDetailModel
    @ReduceMotion var reduceMotion
    /// Retours haptiques de l'écran : il reste affiché quand « toucher pour révéler » ou le bouton « Épingler » disparaît.
    @State private var haptics = HapticTrigger()
    /// Capsule de sélection des pilules de games, qui glisse de l'une à l'autre (`matchedGeometryEffect`).
    @Namespace private var pillSelection
    /// Fiche du joueur touché dans « Joueurs » (spec fonctionnalités §3).
    @State private var player: PlayerSheetItem?

    init(matchId: String) {
        _model = State(initialValue: MatchDetailModel(matchId: matchId))
    }

    /// Ce qui relance le chargement de la game affichée : un autre choix de game, ou la révélation du match
    /// (les stats arrivent aussitôt, sans attendre le cycle suivant de 10 s).
    private struct LoadKey: Equatable, Sendable {
        let game: Int?
        let revealed: Bool
    }

    /// Ce qui relance le fil et la courbe de la game affichée : une autre game, la révélation (la game passe de nil à la
    /// game affichée) et la fin de la game. Pas la lecture de sa frame `finished` : relancer la relecture à ce moment-là,
    /// en pleine requête, ne servirait à rien (`TimelineStore.load`).
    private struct TimelineKey: Equatable, Sendable {
        let gameId: String?
        let inProgress: Bool
    }

    /// Ce qui relance les détails par joueur de la game affichée : une autre game, la révélation, la fin de la game, et la
    /// lecture de sa frame `finished` (les détails ne sont définitifs qu'alors : la boucle de 60 s continue jusque-là).
    private struct FeatureKey: Equatable, Sendable {
        let gameId: String?
        let inProgress: Bool
        let detailsFinal: Bool
    }

    /// Ce qui relance la version Data Dragon : une autre game, ou son patch enfin connu (première frame lue).
    private struct VersionKey: Equatable, Sendable {
        let gameId: String?
        let patch: String?
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
        .haptics(haptics)
        .task { await model.run(store: store) }
        .task(id: LoadKey(game: model.selectedGameNumber, revealed: store.settings.revealedMatchIds.contains(model.matchId))) {
            await model.loadSelectedGame(store: store)
        }
        .task(id: timelineKey) { await model.loadTimeline(store: store) }
        .task(id: featureKey) { await model.followDetails(store: store) }
        .task(id: model.spellsKey(store: store)) { await model.lookUpSpells(store: store) }
        .task(id: versionKey) { await model.loadDataDragon(store: store) }
        // Chaque frame lue en direct (10 s) allonge le fil et la courbe ; nil pour un match masqué (`featureGame`).
        .onChange(of: featureSnapshot) { _, snapshot in
            if let snapshot {
                store.timelines.append(snapshot)
            }
        }
        .environment(\.dataDragon, store.dataDragon)
        .sheet(item: $player) { item in
            PlayerSheet(item: item)
                .environment(store)
                .environment(\.dataDragon, store.dataDragon)
                .presentationDetents([.medium, .large])
        }
    }

    private var timelineKey: TimelineKey {
        let game = model.featureGame(store: store)
        return TimelineKey(gameId: game?.id, inProgress: game?.state == .inProgress)
    }

    private var featureKey: FeatureKey {
        let game = model.featureGame(store: store)
        return FeatureKey(gameId: game?.id, inProgress: game?.state == .inProgress,
                          detailsFinal: game.map { model.detailsAreFinal($0, store: store) } ?? false)
    }

    private var versionKey: VersionKey {
        let game = model.featureGame(store: store)
        return VersionKey(gameId: game?.id, patch: game.flatMap { store.patches[$0.id] })
    }

    /// Dernière frame de la game des fonctionnalités ; nil pour un match masqué ou sans stats.
    private var featureSnapshot: GameSnapshot? {
        model.featureGame(store: store).flatMap { store.snapshots[$0.id] }
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
        // « Regarder » (spec fonctionnalités §1) : match en direct non masqué seulement (l'image montre le score). En direct
        // si le calendrier le dit, ou si les détails montrent une game en cours (le direct peut être tombé du cache, et le
        // calendrier pas encore relu) ; le masquage s'applique dans tous les cas.
        if let watch = WatchLinks.live(event?.streams ?? details?.streams,
                                       inProgress: event?.state == .inProgress || details?.currentGame != nil,
                                       masked: masked) {
            WatchButton(live: watch, onHaptic: { haptics.play($0) })
        }
        if masked {
            RevealButton { reveal() }
        } else if let details {
            // Pilules, stats et joueurs ; à la révélation, ils sortent d'un flou (spec finitions §8). Même espacement
            // que l'écran : la mise en page ne change pas.
            VStack(alignment: .leading, spacing: 14) {
                gamePills(details)
                // « Revoir la game N » (spec fonctionnalités §1) : game jouée, même sans stats live.
                if let game = model.selectedGame(in: details), let replay = WatchLinks.replay(game, masked: masked) {
                    ReplayButton(gameNumber: game.number, link: replay, onHaptic: { haptics.play($0) })
                }
                if details.statsDisabled || event?.statsDisabled == true {
                    NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
                } else if let game = model.selectedGame(in: details) {
                    gameStats(game: game, teams: ordered)
                }
            }
            .transition(Motion.revealTransition(reduceMotion: reduceMotion))
        } else if model.attempted {
            NoteCard(icon: .refresh, text: "Détails du match indisponibles pour l'instant")
        } else {
            // Chargement (spec finitions §10) : le gabarit des pilules et des stats, à la place d'un `ProgressView`.
            DetailLoadingSkeleton()
        }
        if showsPinButton(event: event) {
            LiveActivityPinButton(matchId: model.matchId, onHaptic: { haptics.play($0) })
        }
    }

    /// Fiche d'un joueur (spec fonctionnalités §3), avec un retour « sélection ».
    private func openPlayer(_ item: PlayerSheetItem) {
        haptics.play(.playerPicked)
        player = item
    }

    /// « Toucher pour révéler » (spec §8) : le score et les stats sortent d'un flou en fondu, avec un retour haptique.
    private func reveal() {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.reveal(matchId: model.matchId)
        }
    }

    /// Choix d'une pilule : la capsule glisse (`Motion.snappy`) ; retour « sélection » si la game affichée change.
    private func selectGame(_ number: Int, shown: Int?) {
        if number != shown {
            haptics.play(.gamePicked)
        }
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) {
            model.selectedGameNumber = number
        }
    }

    /// « Épingler sur l'écran verrouillé » (spec §5.3) : iPhone seulement (Apple n'affiche pas les Live Activities sur
    /// iPad), pour un match en direct ou dont la Live Activity est encore à l'écran.
    private func showsPinButton(event: MatchEvent?) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && (event?.state == .inProgress || store.liveActivities.shownMatchIds.contains(model.matchId))
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
        // Comme sur la carte : un match que l'API donne pour terminé est « Terminé » (jamais « En direct », spec §8),
        // même si ses détails n'ont pas encore rattrapé la fin de la série.
        let shown = state?.displayed(for: event)
        switch shown?.phase ?? phase(of: event) {
        case .inGame, .betweenGames:
            Chip {
                LiveIndicator(size: 12)
                if let shown {
                    LiveChipText(state: shown, opponent: nil)
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

    /// « G1 ✓ », « G2 · en direct » (avec le halo « en direct »), « G3 »… une pilule par game jouée ou à venir ; la
    /// capsule blanche glisse vers la pilule touchée (spec finitions §9), sauf sous « Réduire les animations ».
    private func gamePills(_ details: EventDetails) -> some View {
        let games = details.match.games.filter { $0.state != .unneeded }
        let selected = model.selectedGame(in: details)?.number
        let slide: Namespace.ID? = Motion.runs(.pillSlide, reduceMotion: reduceMotion) ? pillSelection : nil
        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(games, id: \.number) { game in
                    PillButton(selected: game.number == selected, selection: slide,
                               action: { selectGame(game.number, shown: selected) }) {
                        Text(game.state == .inProgress ? "G\(game.number) · en direct" : "G\(game.number)")
                        if game.state == .inProgress {
                            LiveIndicator(size: 12)
                        }
                        if game.state == .completed {
                            IconView(icon: .check, size: 12)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Stats et joueurs de la game affichée. Le conteneur anime l'arrivée des panneaux (`Motion.reveal`) quand la première
    /// frame de la game arrive : le squelette est remplacé en fondu, à la même hauteur pour la draft, les stats, la courbe
    /// et les joueurs. Le fil, lui, peut grandir pendant sa relecture (de trois lignes de squelette à dix et « Tout le fil »,
    /// environ 170 pt) : le bouton « Épingler » en dessous peut alors descendre ; sa position reste à juger par Dan.
    /// Ce conteneur n'existe que pour un match non masqué (branche `details`) : rien ne peut fuiter.
    @ViewBuilder private func gameStats(game: GameRef, teams: [MatchTeam]) -> some View {
        let ids = teams.compactMap(\.id)
        VStack(alignment: .leading, spacing: 14) {
            if game.state == .unstarted {
                NoteCard(icon: .clock, text: "La game \(game.number) n'a pas commencé")
            } else if store.statsUnavailable.contains(game.id) {
                NoteCard(icon: .off, text: "Stats live non fournies par Riot pour ce match")
            } else if let snapshot = store.snapshots[game.id], ids.count == 2,
                      let left = snapshot.stats(for: ids[0]), let right = snapshot.stats(for: ids[1]) {
                // Draft, stats, courbe de gold, joueurs enrichis, fil (spec fonctionnalités §3-§5).
                DraftSection(game: game, teams: teams, snapshot: snapshot)
                TeamStatsPanel(left: left, right: right, tint: store.tint(for: teams[0]) ?? Palette.accent)
                GoldCurveSection(game: game, teams: teams)
                PlayersSection(game: game, teams: teams, snapshot: snapshot,
                               selection: $model.playersTeamIndex.animation(Motion.animation(.snappy, reduceMotion: reduceMotion)),
                               onSelect: { openPlayer($0) })
                TimelineSection(game: game, teams: teams)
            } else if game.state == .inProgress || !model.hasLoaded(game) {
                // Première frame (game en cours) ou première réponse (game jouée) pas encore arrivée (spec finitions §10) :
                // le gabarit des panneaux. « Indisponibles » n'apparaît qu'une fois le chargement fini sans stats.
                GameStatsSkeleton()
            } else {
                NoteCard(icon: .refresh, text: "Stats de cette game indisponibles")
            }
        }
        .animation(Motion.animation(.reveal, reduceMotion: reduceMotion), value: store.snapshots[game.id] == nil)
    }
}

#Preview {
    NavigationStack { MatchDetailView(matchId: SampleData.kcMatchId) }.environment(AppStore(preview: .standard))
}
