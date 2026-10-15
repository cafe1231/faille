import LoLKit
import SwiftUI

// Sections des fonctionnalités dans le Détail d'une game (spec fonctionnalités §3-§5). Elles n'existent que dans la
// branche « non masqué » de `MatchDetailView` (et seulement quand une frame de la game est arrivée) : rien ne peut fuiter.

/// Les deux équipes de la game (ordre d'affichage) pour le fil et la courbe : code et couleur Vitrail (accent pour celle
/// de gauche non suivie, secondaire pour l'autre).
@MainActor
private func timelineTeams(_ teams: [MatchTeam], store: AppStore) -> [TimelineTeam] {
    teams.enumerated().compactMap { index, team in
        team.id.map { TimelineTeam(id: $0, code: team.code,
                                   tint: store.tint(for: team) ?? (index == 0 ? Palette.accent : Palette.secondary)) }
    }
}

/// Draft (spec fonctionnalités §3) : les champions des deux équipes, depuis la frame déjà lue.
struct DraftSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]
    let snapshot: GameSnapshot

    var body: some View {
        let champions = PlayerBuilds.draft(snapshot: snapshot, teamIds: teams.compactMap(\.id))
        DraftStrip(teams: zip(teams, champions).map { team, picks in
                       DraftTeam(code: team.code, tint: store.tint(for: team), champions: picks)
                   },
                   version: store.dataDragon.knownVersion(forPatch: store.patches[game.id]))
    }
}

/// Courbe de l'écart de gold (spec fonctionnalités §5), orientée vers l'équipe de gauche.
struct GoldCurveSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]

    var body: some View {
        let timelines = store.timelines
        if !timelines.unavailable.contains(game.id) {
            GoldChartCard(points: timelines.goldPoints(gameId: game.id, orientedTo: teams.first?.id),
                          markers: timelines.events(gameId: game.id).filter(TimelineText.isMarker),
                          teams: timelineTeams(teams, store: store), loading: timelines.replaying.contains(game.id),
                          live: game.state == .inProgress)
        }
    }
}

/// Fil des événements (spec fonctionnalités §4).
struct TimelineSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]

    var body: some View {
        let timelines = store.timelines
        if !timelines.unavailable.contains(game.id) {
            TimelineCard(events: timelines.events(gameId: game.id), teams: timelineTeams(teams, store: store),
                         loading: timelines.replaying.contains(game.id))
        }
    }
}

/// Section « Joueurs » enrichie (spec fonctionnalités §3) : lignes du flux + détails + catalogues + sorts d'invocateur
/// (Leaguepedia pour une game jouée).
struct PlayersSection: View {
    @Environment(AppStore.self) private var store
    let game: GameRef
    let teams: [MatchTeam]
    let snapshot: GameSnapshot
    @Binding var selection: Int
    let onSelect: (PlayerSheetItem) -> Void

    var body: some View {
        let context = Self.context(store: store, game: game)
        let details = store.gameDetails.details[game.id]
        let rows = teams.map { team in
            team.id.map { PlayerBuilds.rows(snapshot: snapshot, details: details, teamId: $0) } ?? []
        }
        BuildPlayersPanel(teams: teams, rows: rows, context: context, selection: $selection) { player, index in
            let team = teams.indices.contains(index) ? teams[index] : nil
            onSelect(PlayerSheetItem(player: player, teamCode: team?.code ?? "", tint: team.flatMap { store.tint(for: $0) },
                                     context: context, finished: game.state == .completed, gameId: game.id))
        }
    }

    /// Version et catalogues Data Dragon de la game, sorts d'invocateur de Leaguepedia (game jouée seulement).
    static func context(store: AppStore, game: GameRef) -> BuildContext {
        let version = store.dataDragon.knownVersion(forPatch: store.patches[game.id])
        return BuildContext(
            version: version,
            items: version.flatMap { store.dataDragon.items[$0] },
            runes: version.flatMap { store.dataDragon.runes[$0] },
            summoners: version.flatMap { store.dataDragon.summoners[$0] },
            summonerSpells: game.state == .completed ? (store.summonerSpells.spells[game.id] ?? [:]) : [:]
        )
    }
}
