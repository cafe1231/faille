import Foundation
import LoLKit
import Observation

/// Boucle de l'écran Détail (spec §4.1) : `getEventDetails` à l'ouverture puis toutes les 60 s si le match est en cours
/// (changement de game) ; flux de la game choisie toutes les 10 s ; seulement tant que l'écran est affiché.
@MainActor
@Observable
final class MatchDetailModel {
    let matchId: String
    /// Game choisie dans les pilules ; nil = la game en cours, sinon la dernière jouée.
    var selectedGameNumber: Int?
    /// Équipe affichée dans « Joueurs » (index dans l'ordre d'affichage).
    var playersTeamIndex = 0
    /// Un premier appel à `getEventDetails` a été tenté.
    private(set) var attempted = false

    /// Nombre de cycles entre deux relectures de `getEventDetails` tant que le match est en cours : cadence du direct
    /// (60 s) sur cadence de l'écran (10 s), soit 6.
    static let reloadEvery = max(1, Int((RefreshPolicy.interval(.live) / RefreshPolicy.detailInterval).rounded(.up)))

    init(matchId: String) {
        self.matchId = matchId
    }

    /// Lancée par `.task` : annulée, requêtes comprises, quand l'écran disparaît.
    /// Les détails sont toujours relus à l'ouverture (`cycle == 0`) : ceux du store peuvent dater d'un passage précédent
    /// (match alors à venir ou entre deux games, depuis terminé) ; ils le sont aussi quand ils manquent, puis toutes les
    /// minutes tant que le match est en cours.
    func run(store: AppStore) async {
        var cycle = 0
        while !Task.isCancelled {
            let details = store.details[matchId]
            let inProgress = details?.currentGame != nil || store.event(id: matchId)?.state == .inProgress
            if details == nil || cycle == 0 || (inProgress && cycle % Self.reloadEvery == 0) {
                await store.loadDetails(matchId: matchId)
                attempted = true
            }
            await loadSelectedGame(store: store)
            cycle += 1
            try? await Task.sleep(for: .seconds(RefreshPolicy.detailInterval))
        }
    }

    /// Game affichée : celle choisie, sinon celle en cours, sinon la dernière jouée, sinon la première.
    func selectedGame(in details: EventDetails) -> GameRef? {
        let games = details.match.games.filter { $0.state != .unneeded }
        if let number = selectedGameNumber, let game = games.first(where: { $0.number == number }) {
            return game
        }
        return games.first(where: { $0.state == .inProgress })
            ?? games.last(where: { $0.state == .completed })
            ?? games.first
    }

    /// Dernière frame de la game affichée : à chaque cycle si elle est en cours, jusqu'à la frame finale si elle est jouée.
    /// Jamais pour un match masqué (spec §8). Une game en cours est interrogée même quand Riot n'en fournit pas les stats
    /// (R-I2) : le chrono de l'en-tête en dépend, et l'écran n'affiche alors aucune stat. Une game terminée sans stats
    /// n'est pas interrogée.
    func loadSelectedGame(store: AppStore) async {
        guard let details = store.details[matchId], let game = selectedGame(in: details),
              !store.isMasked(details.match.teams, matchId: matchId) else { return }
        let statsDisabled = details.statsDisabled || store.event(id: matchId)?.statsDisabled == true
        switch game.state {
        case .inProgress:
            await store.loadWindow(gameId: game.id, inProgress: true)
        case .completed where !statsDisabled && store.snapshots[game.id]?.phase != .finished:
            await store.loadWindow(gameId: game.id, inProgress: false)
        default:
            break
        }
    }
}
