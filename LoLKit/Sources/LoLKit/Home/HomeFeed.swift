import Foundation

/// Un élément de « Activité récente » (spec saison §2.4) : ce que les données disent vraiment, sans texte.
public enum ActivityKind: Sendable, Equatable {
    /// Match terminé il y a ≤ 6 h, d'une équipe ou ligue suivie, non masqué.
    case justFinished(matchId: String)
    /// Série en cours ≥ 3 d'une équipe suivie (séries de matchs non masqués).
    case streak(teamId: String, kind: Streak.Kind, count: Int)
    /// Plus grand total de kills d'une équipe dans les games données, si la game date de ≤ 7 jours.
    case killRecord(gameId: String, teamId: String, kills: Int)
    /// Un joueur à 10 kills ou plus dans une game de ≤ 7 jours.
    case bigGame(gameId: String, playerId: String, kills: Int)
    /// Game de moins de 25 min / de plus de 45 min, de ≤ 7 jours.
    case fastGame(gameId: String, seconds: Int)
    case longGame(gameId: String, seconds: Int)
    /// Équipe menée d'au moins 2 500 gold à 15 min (palier B) et gagnante (vainqueur exact seulement).
    case comeback15(gameId: String, teamId: String, deficit: Int)
}

public struct ActivityItem: Sendable, Equatable {
    public let kind: ActivityKind
    /// Fin de la game ou du match, début du dernier match d'une série : sert au tri (le plus récent d'abord).
    public let date: Date

    public init(kind: ActivityKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// Logique pure de l'onglet Accueil (spec saison §2) : l'appli la calcule hors du fil principal, la mémoïse et
/// l'affiche. Anti-spoiler : chaque ligne de match passe encore par `Presenter.scoreLine` côté appli ; ici, les
/// matchs masqués ne produisent ni activité ni joueurs en forme.
public enum HomeFeed {
    /// Ce que l'Accueil lit (tout vient du cache : aucune requête).
    public struct Input: Sendable {
        public let now: Date
        public let calendar: Calendar
        public let schedule: [MatchEvent]
        /// Réponse de `getLive`, nil si inconnue (repli : les matchs `inProgress` du calendrier).
        public let live: [MatchEvent]?
        public let follows: FollowList
        public let revealed: Set<String>
        public let revealedStandings: Set<String>
        public let seasonMatches: [SeasonMatch]
        public let games: [String: GameSummary]
        /// Classements des tournois en cours, par id de tournoi.
        public let standings: [String: Standings]
        public let catalog: [Team]

        public init(now: Date, calendar: Calendar, schedule: [MatchEvent], live: [MatchEvent]?, follows: FollowList,
                    revealed: Set<String>, revealedStandings: Set<String>, seasonMatches: [SeasonMatch],
                    games: [String: GameSummary], standings: [String: Standings], catalog: [Team]) {
            self.now = now
            self.calendar = calendar
            self.schedule = schedule
            self.live = live
            self.follows = follows
            self.revealed = revealed
            self.revealedStandings = revealedStandings
            self.seasonMatches = seasonMatches
            self.games = games
            self.standings = standings
            self.catalog = catalog
        }
    }

    /// Sections de l'Accueil (§2.2), dans l'ordre. Une section vide est absente côté appli.
    public struct Sections: Sendable, Equatable {
        /// 1 en grand + 2 lignes.
        public let mustWatch: [MustWatchPick]
        public let live: [MatchEvent]
        /// Bandeau : la veille, aujourd'hui, les 5 jours suivants.
        public let week: [CalendarDay]
        /// Matchs d'aujourd'hui (sous-titre « 3 matchs aujourd'hui »).
        public let todayCount: Int
        public let recentResults: [MatchEvent]
        public let activity: [ActivityItem]

        public init(mustWatch: [MustWatchPick], live: [MatchEvent], week: [CalendarDay], todayCount: Int,
                    recentResults: [MatchEvent], activity: [ActivityItem]) {
            self.mustWatch = mustWatch
            self.live = live
            self.week = week
            self.todayCount = todayCount
            self.recentResults = recentResults
            self.activity = activity
        }
    }

    /// Période des « Joueurs en forme ».
    public enum Period: Sendable, Equatable {
        /// 7 derniers jours, 2 games au moins.
        case week
        /// Toutes les games données, 5 games au moins.
        case season
    }

    public static let mustWatchCount = 3
    public static let recentResultsWindow: TimeInterval = 72 * 3600
    public static let recentResultsLimit = 8
    public static let activityLimit = 6
    public static let topPlayersLimit = 5

    public static func build(_ input: Input) -> Sections {
        let masked = SeasonMasking.maskedMatchIds(input.seasonMatches, follows: input.follows, revealed: input.revealed)
        let followed = followedMatchIds(input.schedule, follows: input.follows)
        // Progression de tableau (I-1 généralisé) : la suite d'un match masqué ne figure pas dans les résultats récents.
        let cards = TeamCards.build(follows: input.follows, schedule: input.schedule, live: input.live,
                                    revealed: input.revealed)
        let bracketHidden = BracketMasking.hiddenIds(
            schedule: input.schedule,
            maskedTeamIds: Presenter.maskedLatestTeamIds(cards, follows: input.follows, revealed: input.revealed),
            follows: input.follows, revealed: input.revealed)
        return Sections(
            mustWatch: MustWatch.rank(schedule: input.schedule, follows: input.follows, revealed: input.revealed,
                                      revealedStandings: input.revealedStandings, standings: input.standings,
                                      seasonMatches: input.seasonMatches, catalog: input.catalog, now: input.now,
                                      calendar: input.calendar, limit: mustWatchCount),
            live: live(input.live ?? input.schedule.filter { $0.state == .inProgress }, follows: input.follows),
            week: WeekStrip.days(today: input.now, events: input.schedule, calendar: input.calendar, followed: followed),
            todayCount: CalendarMonth.events(on: input.now, in: dayList(schedule: input.schedule, live: input.live),
                                             calendar: input.calendar).count,
            recentResults: recentResults(schedule: input.schedule, follows: input.follows, now: input.now,
                                         hiddenIds: bracketHidden),
            activity: activity(matches: input.seasonMatches, games: input.games, schedule: input.schedule,
                               follows: input.follows, revealed: input.revealed, masked: masked, now: input.now))
    }

    /// Liste du jour de l'Accueil : le direct (`getLive`) fait foi pour un match qu'il connaît, le calendrier pour le reste
    /// (même règle que l'écran, pour que « N matchs aujourd'hui » compte ce que la liste affiche).
    static func dayList(schedule: [MatchEvent], live: [MatchEvent]?) -> [MatchEvent] {
        guard let live else { return schedule }
        let liveIds = Set(live.map(\.id))
        return live + schedule.filter { !liveIds.contains($0.id) }
    }

    /// Matchs d'une équipe ou d'une ligue suivie (pastilles pleines du calendrier).
    public static func followedMatchIds(_ events: [MatchEvent], follows: FollowList) -> Set<String> {
        Set(events.filter { isFollowed($0, follows) }.map(\.id))
    }

    /// En direct : équipes suivies d'abord, puis ligues suivies, puis internationaux, puis le reste ; par heure de début.
    public static func live(_ events: [MatchEvent], follows: FollowList) -> [MatchEvent] {
        func rank(_ event: MatchEvent) -> Int {
            if follows.involves(event.match.teams) { return 0 }
            if follows.league(slug: event.league.slug) != nil { return 1 }
            if League.internationalSlugs.contains(event.league.slug) { return 2 }
            return 3
        }
        return events.sorted { (rank($0), $0.startTime, $0.id) < (rank($1), $1.startTime, $1.id) }
    }

    /// Résultats des 72 dernières heures, suivis d'abord, puis du plus récent ; 8 au plus. Le score reste à
    /// `Presenter.scoreLine` (masqué → « Terminé · toucher pour révéler »).
    /// - Parameter hiddenIds: matchs que `BracketMasking` cache (suite d'un tableau dont un match est masqué) : absents.
    public static func recentResults(schedule: [MatchEvent], follows: FollowList, now: Date,
                                     hiddenIds: Set<String> = []) -> [MatchEvent] {
        let recent = schedule.filter {
            !hiddenIds.contains($0.id) && $0.state == .completed && $0.startTime <= now && now.timeIntervalSince($0.startTime) <= recentResultsWindow
        }
        return Array(recent.sorted { a, b in
            let (x, y) = (isFollowed(a, follows), isFollowed(b, follows))
            if x != y { return x }
            return (a.startTime, a.id) > (b.startTime, b.id)
        }.prefix(recentResultsLimit))
    }

    /// Activité récente (§2.4), la plus récente d'abord, `activityLimit` au plus. Rien d'un match masqué : `masked`
    /// (`SeasonMasking.maskedMatchIds`) pour les games et les séries, `SpoilerPolicy` pour les matchs du calendrier.
    public static func activity(matches: [SeasonMatch], games: [String: GameSummary], schedule: [MatchEvent],
                                follows: FollowList, revealed: Set<String>, masked: Set<String>,
                                now: Date) -> [ActivityItem] {
        let week: TimeInterval = 7 * 86_400
        var items: [ActivityItem] = []
        let visibleGames = games.values.filter { !masked.contains($0.matchId) && $0.endedAt <= now }
        // Matchs qui viennent de finir : fin = fin de leur dernière game en cache, sinon leur début.
        for event in schedule where event.state == .completed && isFollowed(event, follows)
            && !masked.contains(event.id)
            && !SpoilerPolicy.isMasked(event.match.teams, matchId: event.id, follows: follows, revealed: revealed) {
            let end = visibleGames.filter { $0.matchId == event.id }.map(\.endedAt).max() ?? event.startTime
            guard end <= now, now.timeIntervalSince(end) <= 6 * 3600 else { continue }
            items.append(ActivityItem(kind: .justFinished(matchId: event.id), date: end))
        }
        // Séries en cours des équipes suivies.
        let played = matches.filter { $0.startTime <= now }
        for team in follows.teams {
            guard let streak = SeasonStats.streak(team.id, matches: played, masked: masked), streak.count >= 3,
                  let last = played.filter({ $0.involves(team.id) }).map(\.startTime).max() else { continue }
            items.append(ActivityItem(kind: .streak(teamId: team.id, kind: streak.kind, count: streak.count), date: last))
        }
        // Record de kills d'une équipe (sur toutes les games visibles), s'il date de ≤ 7 jours.
        let lines = visibleGames.flatMap { game in [game.blue, game.red].map { (game: game, line: $0) } }
        if let record = lines.max(by: { ($0.line.kills, $0.game.endedAt) < ($1.line.kills, $1.game.endedAt) }),
           now.timeIntervalSince(record.game.endedAt) <= week {
            items.append(ActivityItem(kind: .killRecord(gameId: record.game.gameId, teamId: record.line.teamId,
                                                        kills: record.line.kills), date: record.game.endedAt))
        }
        for game in visibleGames where now.timeIntervalSince(game.endedAt) <= week {
            for line in [game.blue, game.red] {
                for player in line.players where player.kills >= 10 {
                    items.append(ActivityItem(kind: .bigGame(gameId: game.gameId, playerId: player.playerId,
                                                             kills: player.kills), date: game.endedAt))
                }
            }
            if game.durationSeconds < 25 * 60 {
                items.append(ActivityItem(kind: .fastGame(gameId: game.gameId, seconds: game.durationSeconds),
                                          date: game.endedAt))
            } else if game.durationSeconds > 45 * 60 {
                items.append(ActivityItem(kind: .longGame(gameId: game.gameId, seconds: game.durationSeconds),
                                          date: game.endedAt))
            }
            if game.result.basis == .exact, let winner = game.result.winnerTeamId,
               let own = game.line(teamId: winner)?.gold15, let other = game.opponentLine(of: winner)?.gold15,
               other - own >= 2_500 {
                items.append(ActivityItem(kind: .comeback15(gameId: game.gameId, teamId: winner, deficit: other - own),
                                          date: game.endedAt))
            }
        }
        return Array(items.enumerated().sorted { a, b in
            a.element.date != b.element.date ? a.element.date > b.element.date : a.offset < b.offset
        }.map(\.element).prefix(activityLimit))
    }

    /// Joueurs en forme (§2.2 n° 6) : semaine (7 jours, 2 games au moins) ou saison (5 games au moins), 5 au plus.
    public static func topPlayers(games: [String: GameSummary], masked: Set<String>, metric: PlayerMetric,
                                  period: Period, now: Date) -> [PlayerSeason] {
        let since: Date? = period == .week ? now.addingTimeInterval(-7 * 86_400) : nil
        return SeasonStats.topPlayers(games: Array(games.values), masked: masked, metric: metric, since: since,
                                      minGames: period == .week ? 2 : 5, limit: topPlayersLimit)
    }

    static func isFollowed(_ event: MatchEvent, _ follows: FollowList) -> Bool {
        follows.involves(event.match.teams) || follows.league(slug: event.league.slug) != nil
    }
}
