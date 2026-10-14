import Foundation
import LoLKit

extension AppStore {
    /// Ce que l'Accueil lit, figé pour un calcul hors du fil principal (spec saison §2.3) : tout vient du cache.
    ///
    /// Anti-spoiler I-1 : le calendrier et le direct passent par `withoutMaskedUpcoming` avant d'entrer dans
    /// `HomeModel.compute` (bandeau, jour sélectionné, pastilles et « À ne pas rater » ne trahissent aucun match à venir
    /// d'une équipe dont le dernier match est masqué).
    func homeInputs(now: Date, calendar: Calendar = .current) -> HomeInputs {
        HomeInputs(feed: HomeFeed.Input(now: now, calendar: calendar, schedule: withoutMaskedUpcoming(schedule),
                                        live: live.map { withoutMaskedUpcoming($0) }, follows: follows,
                                        revealed: settings.revealedMatchIds,
                                        revealedStandings: settings.revealedStandingIds, seasonMatches: season.matches,
                                        games: season.games, standings: season.standings, catalog: catalog),
                   progress: season.progress, isLoaded: season.isLoaded)
    }

    /// « À ne pas rater » (spec saison §3.6) : 3 dans l'Accueil (`HomeFeed.build`), 5 au plus en tête de Matchs (I2).
    func mustWatchPicks(limit: Int, now: Date = Date(), calendar: Calendar = .current) -> [MustWatchPick] {
        MustWatch.rank(schedule: withoutMaskedUpcoming(schedule), follows: follows, revealed: settings.revealedMatchIds,
                       revealedStandings: settings.revealedStandingIds, standings: season.standings,
                       seasonMatches: season.matches, catalog: catalog, now: now, calendar: calendar, limit: limit)
    }
}

/// Ce qui relance le calcul de l'Accueil (spec saison §2.3) : une game lue (`version`), les suivis, les révélations, le
/// jour, une relecture du calendrier ou du direct, la fin de la lecture du disque, l'état de la collecte, un classement
/// masqué ou révélé.
struct HomeKey: Equatable {
    let version: Int
    let follows: FollowList
    let revealed: Set<String>
    let day: Date
    let updated: Date?
    let liveIds: [String]?
    let loaded: Bool
    let running: Bool
    let revealedStandings: Set<String>

    /// M16 : pendant une passe de collecte, seules les lectures de games (version, mise à jour, direct, état de la
    /// collecte) sont retenues 30 s. Un suivi, une révélation ou un changement de jour se publie tout de suite, sinon
    /// l'écran garderait des stats calculées avant le suivi (fuite anti-spoiler) ou semblerait ignorer le geste.
    static func shouldThrottle(old: HomeKey?, new: HomeKey, running: Bool) -> Bool {
        guard running, let old else { return false }
        return old.follows == new.follows && old.revealed == new.revealed
            && old.revealedStandings == new.revealedStandings && old.day == new.day
    }
}
