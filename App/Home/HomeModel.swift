import Foundation
import LoLKit

/// Ce que l'Accueil lit : l'entrée de `HomeFeed` (copie figée des stores) et l'état de la collecte, envoyés hors du fil
/// principal.
struct HomeInputs: Sendable {
    var feed: HomeFeed.Input
    var progress: CrawlProgress
    var isLoaded: Bool
}

/// Joueurs en forme : période × mesure (pilules « Semaine / Saison » × « KDA / Kills / CS/min »).
/// `Period` et `PlayerMetric` (LoLKit) ne sont pas `Hashable` : la clé se hache sur leurs rangs.
struct HotPlayersKey: Hashable, Sendable {
    let period: HomeFeed.Period
    let metric: PlayerMetric

    private var periodRank: Int {
        switch period {
        case .week: 0
        case .season: 1
        }
    }

    private var metricRank: Int {
        PlayerMetric.allCases.firstIndex(of: metric) ?? 0
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.periodRank == rhs.periodRank && lhs.metricRank == rhs.metricRank
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(periodRank)
        hasher.combine(metricRank)
    }
}

/// Un match de « En direct maintenant » : masqué → « En direct » seul (ni score ni « Regarder »).
struct HomeLiveItem: Equatable, Sendable, Identifiable {
    let event: MatchEvent
    let masked: Bool
    var id: String { event.id }
}

/// Sections de l'Accueil (spec saison §2.2), calculées d'un coup.
struct HomeContent: Equatable, Sendable {
    /// « À ne pas rater » (3), direct, nombre de matchs du jour, résultats (72 h, 8), activité (6) : `HomeFeed.build`.
    var sections: HomeFeed.Sections
    var live: [HomeLiveItem]
    /// Bandeau : ± 3 semaines autour d'aujourd'hui (`WeekStrip.scrollRange`), 7 jours à l'écran.
    var strip: [CalendarDay]
    /// Matchs de chaque jour (début du jour local → matchs, par heure).
    var eventsByDay: [Date: [MatchEvent]]
    var hotPlayers: [HotPlayersKey: [PlayerSeason]]
    var masked: Set<String>
    var hasFollows: Bool
    var progress: CrawlProgress
    var isLoaded: Bool
}

/// Calcul de l'Accueil (spec saison §2.2, §2.3) : la logique est dans LoLKit (`HomeFeed`), ici l'assemblage pour l'écran.
/// Rien n'attend le réseau ; l'anti-spoiler passe par `HomeFeed` (activité, joueurs en forme, « À ne pas rater »),
/// `SpoilerPolicy` (direct) et `Presenter` (chaque ligne de match, à l'écran).
enum HomeModel {
    static let periods: [HomeFeed.Period] = [.week, .season]

    static func compute(_ inputs: HomeInputs) -> HomeContent {
        let feed = inputs.feed
        let sections = HomeFeed.build(feed)
        let masked = SeasonMasking.maskedMatchIds(feed.seasonMatches, follows: feed.follows, revealed: feed.revealed)
        let events = merged(schedule: feed.schedule, live: feed.live)
        var hot: [HotPlayersKey: [PlayerSeason]] = [:]
        for period in periods {
            for metric in PlayerMetric.allCases {
                hot[HotPlayersKey(period: period, metric: metric)] = HomeFeed.topPlayers(
                    games: feed.games, masked: masked, metric: metric, period: period, now: feed.now)
            }
        }
        return HomeContent(
            sections: sections,
            live: sections.live.map {
                HomeLiveItem(event: $0, masked: SpoilerPolicy.isMasked($0.match.teams, matchId: $0.id,
                                                                       follows: feed.follows, revealed: feed.revealed))
            },
            strip: WeekStrip.scrollRange(today: feed.now, events: events, calendar: feed.calendar,
                                         followed: HomeFeed.followedMatchIds(events, follows: feed.follows)),
            eventsByDay: Dictionary(grouping: events) { feed.calendar.startOfDay(for: $0.startTime) }
                .mapValues { $0.sorted { ($0.startTime, $0.id) < ($1.startTime, $1.id) } },
            hotPlayers: hot,
            masked: masked,
            hasFollows: !feed.follows.teams.isEmpty || !feed.follows.leagues.isEmpty,
            progress: inputs.progress,
            isLoaded: inputs.isLoaded)
    }

    /// Le direct (`getLive`) fait foi pour un match qu'il connaît ; le calendrier pour le reste (même règle que les cartes).
    static func merged(schedule: [MatchEvent], live: [MatchEvent]?) -> [MatchEvent] {
        guard let live else { return schedule }
        let liveIds = Set(live.map(\.id))
        return live + schedule.filter { !liveIds.contains($0.id) }
    }
}
