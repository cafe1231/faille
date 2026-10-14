import LoLKit
import SwiftUI

/// Section « Duel » du Détail (spec saison §3.3), sous les stats : onglets « Joueurs » (poste contre poste) et
/// « Équipes ». Anti-spoiler : pour un match masqué (à venir, en cours ou terminé), seules les stats de saison (matchs
/// masqués exclus) ; aucune ligne « Cette game », aucune composition lue dans ce match. « Changer » ouvre le sélecteur
/// et pousse un duel libre.
struct DuelSection: View {
    @Environment(AppStore.self) private var store
    let matchId: String
    /// Équipes du match, dans l'ordre d'affichage du Détail.
    let teams: [MatchTeam]
    /// Game affichée par le Détail si elle est jouée ; nil sinon.
    let selectedGameId: String?
    let masked: Bool
    @State private var showsTeams = false
    @State private var picking: Picking?
    @State private var freeDuel: DuelRoute?
    @State private var haptics = HapticTrigger()
    @State private var memo = DuelSectionMemo()
    @ReduceMotion var reduceMotion

    /// Poste et côté dont le joueur est à choisir (`.sheet(item:)`).
    struct Picking: Identifiable {
        let role: String
        let position: DuelSidePosition
        var id: String { "\(role)-\(position)" }
    }

    var body: some View {
        // Un seul calcul par rendu (I-8) : matchs masqués, lignes et duels de chaque poste ; les cartes reçoivent des
        // valeurs. Mémoïsé par clé tant que rien de pertinent ne change (Détail redessiné toutes les 10 s en direct).
        let content = memo.value(store: store, teams: teams, selectedGameId: selectedGameId, masked: masked)
        // Conteneur inconditionnel (I-7) : `sheet` et `navigationDestination` ne disparaissent pas avec la section.
        VStack(alignment: .leading, spacing: 10) {
            if teams.compactMap(\.id).count == 2 {
                let ids = teams.compactMap(\.id)
                HStack {
                    SectionLabel(text: String(localized: "Duel"))
                    PillButton(selected: !showsTeams, action: { select(teams: false) }) { Text("Joueurs") }
                    PillButton(selected: showsTeams, action: { select(teams: true) }) { Text("Équipes") }
                }
                if showsTeams {
                    TeamDuelCard(leftId: ids[0], rightId: ids[1], masked: content.seasonMasked)
                } else {
                    if content.lines.isEmpty {
                        NoteCard(icon: .player, text: String(localized: "Effectifs inconnus pour ce match"))
                    }
                    ForEach(content.lines) { entry in
                        PlayerDuelCard(role: entry.line.role, left: entry.line.left, right: entry.line.right,
                                       duel: entry.duel,
                                       onChange: { picking = Picking(role: entry.line.role, position: $0) })
                    }
                }
            }
        }
        .haptics(haptics)
        .sheet(item: $picking) { current in
            DuelPicker { chosen in
                let line = content.lines.first { $0.line.role == current.role }?.line
                let other = current.position == .left ? line?.right?.id : line?.left?.id
                haptics.play(.playerPicked)
                if let other {
                    freeDuel = current.position == .left ? DuelRoute(left: .player(chosen), right: .player(other))
                                                         : DuelRoute(left: .player(other), right: .player(chosen))
                }
            }
            .environment(store)
        }
        .navigationDestination(item: $freeDuel) { DuelView(left: $0.left, right: $0.right) }
    }

    private func select(teams: Bool) {
        guard teams != showsTeams else { return }
        haptics.play(.gamePicked)
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { showsTeams = teams }
    }

    /// Lignes poste contre poste (testées) : composition de la game affichée si elle est jouée et non masquée, sinon
    /// effectifs du catalogue (`DuelModel.lineup`).
    @MainActor
    static func lines(store: AppStore, teams: [MatchTeam], selectedGameId: String?, masked: Bool) -> [DuelLine] {
        lines(store: store, teams: teams, selectedGameId: selectedGameId, masked: masked,
              seasonMasked: store.seasonMasked)
    }

    @MainActor
    static func lines(store: AppStore, teams: [MatchTeam], selectedGameId: String?, masked: Bool,
                      seasonMasked hidden: Set<String>) -> [DuelLine] {
        let ids = teams.compactMap(\.id)
        guard ids.count == 2 else { return [] }
        let game = masked ? nil : selectedGameId.flatMap { store.season.games[$0] }
        // `Duel.lineup` ne lit que des games sans matchs masqués.
        let all = store.season.games.values.filter { !hidden.contains($0.matchId) }
        let left = DuelModel.lineup(teamId: ids[0], game: game, masked: masked, catalog: store.catalog, games: all,
                                    teamCode: teams[0].code)
        let right = DuelModel.lineup(teamId: ids[1], game: game, masked: masked, catalog: store.catalog, games: all,
                                     teamCode: teams[1].code)
        return DuelModel.lines(left: left, right: right)
    }
}

/// Une ligne du duel et les stats de saison de ses deux joueurs (calculées une fois).
struct DuelEntry: Identifiable {
    let line: DuelLine
    let duel: PlayerDuel
    var id: String { line.id }
}

/// Contenu calculé de la section.
struct DuelSectionContent {
    let seasonMasked: Set<String>
    let lines: [DuelEntry]
}

/// Mémo du contenu de la section (I-8) : recalculé seulement quand la clé change (match, game affichée, masquage, version
/// de la saison, matchs masqués, équipes du catalogue). Référence mutée pendant `body`, jamais observée.
@MainActor
final class DuelSectionMemo {
    private struct Key: Equatable {
        let teamIds: [String]
        let selectedGameId: String?
        let masked: Bool
        let version: Int
        let seasonMasked: Set<String>
        let catalogCount: Int
    }

    private var key: Key?
    private var content: DuelSectionContent?

    func value(store: AppStore, teams: [MatchTeam], selectedGameId: String?, masked: Bool) -> DuelSectionContent {
        let hidden = store.seasonMasked
        let next = Key(teamIds: teams.compactMap(\.id), selectedGameId: selectedGameId, masked: masked,
                       version: store.season.version, seasonMasked: hidden, catalogCount: store.catalog.count)
        if let content, key == next { return content }
        let lines = DuelSection.lines(store: store, teams: teams, selectedGameId: selectedGameId, masked: masked,
                                      seasonMasked: hidden)
        let games = Array(store.season.games.values)
        let entries = lines.map { line in
            DuelEntry(line: line, duel: Duel.players(left: line.left?.id ?? "", right: line.right?.id ?? "",
                                                     games: games, masked: hidden))
        }
        let built = DuelSectionContent(seasonMasked: hidden, lines: entries)
        key = next
        content = built
        return built
    }
}
