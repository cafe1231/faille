import LoLKit
import SwiftUI

/// Duel libre (spec saison §3.3) : deux joueurs (barres, champions favoris) ou deux équipes (bilans, face-à-face) ; stats
/// de saison sans les matchs masqués.
struct DuelView: View {
    @Environment(AppStore.self) private var store
    let left: DuelSide
    let right: DuelSide

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(String(localized: "Duel"), subtitle: String(localized: "Stats de la saison"))
                switch (left, right) {
                case let (.player(a), .player(b)):
                    PlayerDuelCard(role: nil, left: player(a), right: player(b),
                                   duel: Duel.players(left: a, right: b, games: Array(store.season.games.values),
                                                      masked: store.seasonMasked))
                case let (.team(a), .team(b)):
                    TeamDuelCard(leftId: a, rightId: b, masked: store.seasonMasked)
                default:
                    NoteCard(icon: .versus, text: String(localized: "Choisis deux joueurs ou deux équipes"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Joueur d'un duel libre : son nom (catalogue, sinon pseudo du flux sans le code d'équipe), sans ligne « Cette game ».
    private func player(_ id: String) -> DuelPlayer {
        for game in store.season.games.values {
            for line in [game.blue, game.red] {
                if let player = line.players.first(where: { $0.playerId == id }) {
                    return DuelPlayer(id: id, name: store.playerName(id: id, raw: player.name, teamId: line.teamId),
                                      thisGame: nil)
                }
            }
        }
        let name = store.catalog.lazy.compactMap { $0.players?.first { $0.id == id }?.summonerName }.first
        return DuelPlayer(id: id, name: name ?? id, thisGame: nil)
    }
}
