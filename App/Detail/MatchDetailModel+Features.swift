import Foundation
import LoLKit

// MARK: - Fonctionnalités du Détail (fonctionnalités, Task 7)

extension MatchDetailModel {
    /// Game dont l'écran montre les fonctionnalités (draft et builds, fil, courbe, sorts d'invocateur) : la game affichée,
    /// en cours ou jouée, d'un match NON masqué dont Riot fournit les stats. nil sinon : aucune requête, aucun affichage
    /// (spec fonctionnalités, « Anti-spoiler d'abord » ; spec §8).
    func featureGame(store: AppStore, bracketHidden: Bool? = nil) -> GameRef? {
        guard let details = store.details[matchId], let game = selectedGame(in: details),
              !store.isDetailMasked(details.match.teams, matchId: matchId, bracketHidden: bracketHidden),
              !details.statsDisabled, store.event(id: matchId)?.statsDisabled != true,
              !store.statsUnavailable.contains(game.id),
              game.state == .inProgress || game.state == .completed else { return nil }
        return game
    }

    /// Les détails par joueur de cette game sont définitifs : elle est jouée ET sa frame `finished` a été lue (avant, ils
    /// peuvent dater d'un peu avant la fin : la boucle de 60 s continue).
    func detailsAreFinal(_ game: GameRef, store: AppStore) -> Bool {
        game.state == .completed && store.snapshots[game.id]?.phase == .finished
    }

    /// Fil et courbe de la game affichée, tant que l'écran l'affiche (tâche annulée en le quittant) : le disque, sinon la
    /// relecture du flux à pas de 60 s. Sa propre tâche, de clé (game, en cours ?) : la fin de la relecture des détails ou
    /// des sorts ne la relance pas (une relecture relancée en pleine requête risquait de ne rien lire, voir
    /// `TimelineStore.load`).
    func loadTimeline(store: AppStore) async {
        guard let game = featureGame(store: store) else { return }
        await store.timelines.load(gameId: game.id, inProgress: game.state == .inProgress)
    }

    /// Détails par joueur de la game affichée, tant que l'écran l'affiche : toutes les 60 s tant qu'ils ne sont pas
    /// définitifs, une fois ensuite. Une game jouée dont aucune frame n'est encore en mémoire (première ouverture) n'est pas
    /// lue maintenant : la frame `finished` arrive en quelques centaines de millisecondes, la clé de la tâche repart alors
    /// (`detailsAreFinal`) et la lecture est faite une seule fois, définitive, au lieu d'une lecture provisoire de 200 Ko
    /// suivie de la définitive. Le passage du direct à la fin garde sa boucle de 60 s : la game a alors des frames en
    /// mémoire.
    func followDetails(store: AppStore) async {
        guard let game = featureGame(store: store) else { return }
        if game.state == .completed, store.snapshots[game.id] == nil { return }
        await store.gameDetails.follow(gameId: game.id, finished: detailsAreFinal(game, store: store))
    }

    /// Version Data Dragon de la game affichée (patch lu dans son flux) et catalogues (objets, runes, sorts d'invocateur),
    /// tant que l'écran l'affiche. Si la version ou un catalogue manque (réseau en panne à l'ouverture), un nouvel essai
    /// toutes les `retry` (une minute : `DataDragonStore.versionsRetry`), jamais plus vite, jusqu'à les avoir tous : sans
    /// cela, les initiales et « Objet 3071 » resteraient jusqu'à la réouverture du Détail. La garde (match non masqué, patch
    /// connu) est revérifiée à chaque tour.
    /// - Parameter retry: délai entre deux essais (les tests le raccourcissent).
    func loadDataDragon(store: AppStore, retry: Duration = .seconds(DataDragonStore.versionsRetry)) async {
        while !Task.isCancelled {
            guard let game = featureGame(store: store), let patch = store.patches[game.id] else { return }
            if let version = await store.dataDragon.version(forPatch: patch) {
                await store.dataDragon.loadCatalogs(version: version)
                if store.dataDragon.hasCatalogs(version: version) { return }
            }
            try? await Task.sleep(for: retry)
        }
    }

    /// Ce qui relance la recherche des sorts d'invocateur : le match devient terminé et non masqué (nil avant : rien à
    /// chercher), et la fin de sa dernière game devient connue. Sa propre tâche : les sorts n'attendent ni le fil, ni la
    /// courbe, ni les détails, qui prennent une vingtaine de secondes.
    struct SpellsKey: Equatable, Sendable {
        /// Dernière game jouée du match ; nil si rien n'est à chercher (masqué, pas terminé, stats coupées par Riot).
        let lastGameId: String?
        /// Fin de cette game si sa frame `finished` est en mémoire ; nil : `SpellSchedule` l'estime, plus tard que la vraie
        /// fin — la recherche repart donc quand la frame arrive, et le premier essai peut alors être permis.
        let end: Date?
    }

    /// Games jouées d'un match terminé, non masqué et dont Riot fournit les stats : celles dont on cherche les sorts
    /// d'invocateur (Leaguepedia). nil si le match est masqué, n'est pas terminé (une game est en cours, ou reste à jouer
    /// alors que le calendrier ne le dit pas terminé), n'a aucune game jouée, ou n'a pas de stats : aucune requête alors.
    private func spellGames(store: AppStore) -> [GameRef]? {
        guard let details = store.details[matchId], !store.isDetailMasked(details.match.teams, matchId: matchId),
              !details.statsDisabled, store.event(id: matchId)?.statsDisabled != true else { return nil }
        let games = details.match.games
        let finished = !games.contains { $0.state == .inProgress }
            && (store.event(id: matchId)?.state == .completed || !games.contains { $0.state == .unstarted })
        let played = games.filter { $0.state == .completed }
        return finished && !played.isEmpty ? played : nil
    }

    /// Fin de la dernière game si l'écran a lu sa frame `finished` ; nil sinon.
    private func lastGameEnd(_ last: GameRef, store: AppStore) -> Date? {
        store.snapshots[last.id].flatMap { $0.phase == .finished ? $0.timestamp : nil }
    }

    func spellsKey(store: AppStore) -> SpellsKey {
        guard let last = spellGames(store: store)?.last else { return SpellsKey(lastGameId: nil, end: nil) }
        return SpellsKey(lastGameId: last.id, end: lastGameEnd(last, store: store))
    }

    /// Sorts d'invocateur d'un match terminé et non masqué : toutes ses games jouées, une seule requête Leaguepedia, sous sa
    /// règle stricte. La fin du match est la frame `finished` de sa dernière game si l'écran l'a déjà lue (sinon
    /// `SpellSchedule` l'estime). Tâche de l'écran, de clé `spellsKey`.
    func lookUpSpells(store: AppStore) async {
        guard let played = spellGames(store: store), let last = played.last else { return }
        await store.summonerSpells.lookUp(matchId: matchId, gameIds: played.map(\.id),
                                          matchEnd: lastGameEnd(last, store: store))
    }
}
