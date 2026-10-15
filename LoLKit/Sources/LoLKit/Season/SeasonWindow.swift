import Foundation

/// Périmètre des données (spec périmètre §2) : saison en cours N, saison précédente N − 1, tournois en cours. Pur.
/// Saison d'un tournoi = année civile de son début (à défaut, de sa fin). Rien d'avant N − 1 n'est énuméré, gardé ni
/// montré, sauf un tournoi encore en cours commencé il y a au plus 400 jours (`liveOverride`). La fenêtre est un
/// plafond, pas une cible : ce que la collecte lit vraiment reste piloté par `CrawlWanted`.
public struct SeasonWindow: Sendable, Hashable {
    /// Jour de référence « yyyy-MM-dd », en UTC (comme les dates des tournois).
    public let today: String
    public let currentSeason: Int
    /// 1er janvier de N − 1, 00:00 UTC : premier instant du périmètre (dates des games, du calendrier).
    public let startDate: Date

    public var previousSeason: Int { currentSeason - 1 }
    /// « 2025-01-01 ».
    public var startDay: String { String(format: "%04d-01-01", previousSeason) }

    /// Compétitions dont toutes les équipes sont collectées (spec §2.1).
    public static let completeLeagueSlugs: Set<String> = ["worlds", "msi", "first_stand", "demacia_cup"]
    /// Ligues renommées : la saison N − 1 d'une ligue passe par ses prédécesseurs (spec §2.1).
    public static let predecessors: [String: [String]] = ["lcs": ["lta_n", "lta_cross"],
                                                          "cblol-brazil": ["lta_s", "lta_cross"]]
    /// Garde-fou de l'exception « en cours » : commencé il y a au plus 400 jours.
    public static let liveOverrideMaxAgeDays = 400

    public enum Placement: Sendable, Equatable {
        /// Saison N.
        case current
        /// Saison N − 1.
        case previous
        /// Saison > N (annoncé ; rien à lire avant son début).
        case upcoming
        /// Plus ancien que N − 1 mais en cours (`isActive`), commencé il y a ≤ 400 jours.
        case liveOverride
        /// Tout le reste, dates illisibles comprises.
        case outside
    }

    /// nil si `today` n'est pas une date « yyyy-MM-dd » lisible.
    public init?(today: String) {
        guard let day = TournamentRef.day(today) else { return nil }
        self.init(day: day, today: today)
    }

    /// Jour UTC de `now`.
    public init(now: Date) {
        let parts = Self.utc.dateComponents([.year, .month, .day], from: now)
        self.init(day: now, today: String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1))
    }

    private init(day: Date, today: String) {
        let year = Self.utc.component(.year, from: day)
        self.today = today
        currentSeason = year
        startDate = Self.utc.date(from: DateComponents(year: year - 1, month: 1, day: 1)) ?? .distantPast
    }

    /// Saison d'un tournoi : année de `startDate`, sinon année de `endDate`, sinon nil.
    public static func season(of tournament: TournamentRef) -> Int? {
        if TournamentRef.day(tournament.startDate) != nil { return Int(tournament.startDate.prefix(4)) }
        if TournamentRef.day(tournament.endDate) != nil { return Int(tournament.endDate.prefix(4)) }
        return nil
    }

    public func placement(of tournament: TournamentRef) -> Placement {
        guard let season = Self.season(of: tournament) else { return .outside }
        if season == currentSeason { return .current }
        if season == previousSeason { return .previous }
        if season > currentSeason { return .upcoming }
        guard tournament.isActive(today: today),
              let start = TournamentRef.day(tournament.startDate),
              let floorDay = TournamentRef.adding(days: -Self.liveOverrideMaxAgeDays, to: today),
              let floor = TournamentRef.day(floorDay), start >= floor else { return .outside }
        return .liveOverride
    }

    public func contains(_ tournament: TournamentRef) -> Bool {
        placement(of: tournament) != .outside
    }

    /// Saison de rattachement (pilules, « saison de référence ») : N pour `current` et `liveOverride`, N − 1 pour
    /// `previous`, la saison du tournoi pour `upcoming` ; nil hors périmètre.
    public func scopeSeason(of tournament: TournamentRef) -> Int? {
        switch placement(of: tournament) {
        case .current, .liveOverride: currentSeason
        case .previous: previousSeason
        case .upcoming: Self.season(of: tournament)
        case .outside: nil
        }
    }

    /// Tournois du périmètre, sans doublon, du plus récent au plus ancien (`startDate`, puis id).
    public func tournaments(_ all: [TournamentRef]) -> [TournamentRef] {
        var seen = Set<String>()
        return all.filter { contains($0) && seen.insert($0.id).inserted }
            .sorted { ($0.startDate, $0.id) > ($1.startDate, $1.id) }
    }

    /// Une date (début de game, de match du calendrier) est-elle dans le périmètre ? ≥ `startDate`.
    public func contains(date: Date) -> Bool {
        date >= startDate
    }

    /// Premier mois montrable par le calendrier : 1er janvier de N − 1 dans le fuseau de `calendar`.
    public func firstMonth(calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: previousSeason, month: 1, day: 1)) ?? startDate
    }

    /// Saison « de référence » d'un écran : N s'il y a des données en N, sinon N − 1 s'il y en a, sinon N.
    public func referenceSeason(seasonsWithData: Set<Int>) -> Int {
        if seasonsWithData.contains(currentSeason) { return currentSeason }
        if seasonsWithData.contains(previousSeason) { return previousSeason }
        return currentSeason
    }

    /// Pilules d'une équipe (spec §3.5) : « Saison N », ses tournois de N (dont `liveOverride`), « Saison N − 1 », ses
    /// tournois de N − 1 ; du plus récent au plus ancien dans chaque saison ; une saison sans tournoi joué n'a pas de
    /// pilule ; un tournoi annoncé (`upcoming`) n'a rien de joué, il n'en a pas. `isLive` : tournoi actif aujourd'hui.
    public func scopes(played: [TournamentRef]) -> [SeasonScope] {
        let inWindow = tournaments(played)
        var result: [SeasonScope] = []
        for season in [currentSeason, previousSeason] {
            let group = inWindow.filter { placement(of: $0) != .upcoming && scopeSeason(of: $0) == season }
            guard !group.isEmpty else { continue }
            result.append(SeasonScope(tournamentIds: Set(group.map(\.id)), label: String(season), season: season))
            result += group.map { tournament in
                SeasonScope(tournamentIds: [tournament.id], label: tournament.slug, season: season,
                            isLive: tournament.isActive(today: today))
            }
        }
        return result
    }

    /// Purge (§3.3) : ids des games hors périmètre, triés. Tournoi connu → `!contains` ; inconnu → `startedAt < startDate`.
    public func outsideGameIds(_ games: [GameSummary], tournaments: [String: TournamentRef]) -> [String] {
        games.filter { game in
            if let tournament = tournaments[game.tournamentId] { return !contains(tournament) }
            return !contains(date: game.startedAt)
        }.map(\.gameId).sorted()
    }

    /// Purge : ids de tournoi (fichiers `completed/`, `standings/`) hors périmètre. Connu → `!contains` ; inconnu → hors
    /// si son dernier match connu (`lastMatchStart`) est avant `startDate` ; inconnu sans date → gardé.
    public func outsideTournamentIds(_ ids: Set<String>, tournaments: [String: TournamentRef],
                                     lastMatchStart: [String: Date]) -> Set<String> {
        ids.filter { id in
            if let tournament = tournaments[id] { return !contains(tournament) }
            guard let last = lastMatchStart[id] else { return false }
            return !contains(date: last)
        }
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
