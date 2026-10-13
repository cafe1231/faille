import Foundation

/// Données que l'appli relit régulièrement (spec §4.1).
public enum DataKind: String, Codable, Sendable, CaseIterable {
    case leagues, teams, schedule, live
}

/// Ce que l'appli sait au moment de décider quoi relire.
public struct RefreshInput: Sendable, Equatable {
    public var now: Date
    /// L'appli vient de passer au premier plan, ou l'utilisateur a tiré pour rafraîchir.
    public var opening: Bool
    /// Dernière réponse valide de chaque donnée (au lancement : la date du cache sur disque).
    public var lastSuccess: [DataKind: Date]
    /// Dernière tentative, réussie ou non (en mémoire seulement).
    public var lastAttempt: [DataKind: Date]
    /// Ligues demandées pour le calendrier en cache ; nil s'il n'y a pas de calendrier.
    public var scheduleLeagueIds: [String]?
    /// Ligues à demander maintenant (`ScheduleQuery.leagueIds`) ; vide tant que les ligues ne sont pas connues.
    public var wantedLeagueIds: [String]
    /// Un match a quitté `getLive` depuis le dernier calendrier : il faut relire `getSchedule` (spec §10).
    public var matchLeftLive: Bool

    public init(now: Date, opening: Bool = false, lastSuccess: [DataKind: Date] = [:], lastAttempt: [DataKind: Date] = [:],
                scheduleLeagueIds: [String]? = nil, wantedLeagueIds: [String] = [], matchLeftLive: Bool = false) {
        self.now = now
        self.opening = opening
        self.lastSuccess = lastSuccess
        self.lastAttempt = lastAttempt
        self.scheduleLeagueIds = scheduleLeagueIds
        self.wantedLeagueIds = wantedLeagueIds
        self.matchLeftLive = matchLeftLive
    }
}

/// Quand relire quoi. Fonction pure : l'appli lui donne des dates, elle répond par les données à relire.
public enum RefreshPolicy {
    /// Cadence de la boucle de l'appli au premier plan.
    public static let tick: TimeInterval = 10
    /// Cadence du flux de stats tant que l'écran Détail est affiché.
    public static let detailInterval: TimeInterval = 10
    /// Après un échec, délai avant de retenter la même donnée.
    public static let retryDelay: TimeInterval = 60
    /// Écart minimal entre deux tentatives forcées (ouverture, ligues changées, match sorti du direct).
    public static let minGap: TimeInterval = 10
    /// Au-delà, la liste des matchs en direct n'est plus crue : les cartes retombent sur le calendrier.
    public static let liveTrust: TimeInterval = 600
    /// Un succès daté de plus loin que ça dans le futur veut dire que l'horloge a reculé.
    static let clockSkew: TimeInterval = 60

    public static func interval(_ kind: DataKind) -> TimeInterval {
        switch kind {
        case .leagues, .teams: return 24 * 3600
        case .schedule: return 30 * 60
        case .live: return 60
        }
    }

    /// Données à relire maintenant. Le calendrier attend que des ligues soient connues.
    public static func due(_ input: RefreshInput) -> Set<DataKind> {
        var result: Set<DataKind> = []
        for kind in DataKind.allCases {
            if kind == .schedule && input.wantedLeagueIds.isEmpty { continue }
            let success = input.lastSuccess[kind]
            let stale = success.map {
                input.now.timeIntervalSince($0) >= interval(kind) || $0 > input.now.addingTimeInterval(clockSkew)
            } ?? true
            if (stale || isForced(kind, input)) && canTry(success: success, attempt: input.lastAttempt[kind], now: input.now) {
                result.insert(kind)
            }
        }
        return result
    }

    static func isForced(_ kind: DataKind, _ input: RefreshInput) -> Bool {
        switch kind {
        case .leagues, .teams:
            return false
        case .live:
            return input.opening
        case .schedule:
            return input.opening || input.matchLeftLive
                || Set(input.scheduleLeagueIds ?? []) != Set(input.wantedLeagueIds)
        }
    }

    /// Une tentative ratée attend `retryDelay` ; sinon `minGap` suffit (évite les doublons à l'ouverture).
    static func canTry(success: Date?, attempt: Date?, now: Date) -> Bool {
        guard let attempt, attempt <= now else { return true }
        let failed = success.map { attempt > $0 } ?? true
        return now.timeIntervalSince(attempt) >= (failed ? retryDelay : minGap)
    }

    /// Vrai si un match présent dans l'ancienne réponse de `getLive` n'y est plus.
    public static func leftLive(previous: [MatchEvent]?, current: [MatchEvent]) -> Bool {
        guard let previous else { return false }
        let ids = Set(current.map(\.id))
        return previous.contains { !ids.contains($0.id) }
    }

    /// Le direct en cache s'il est assez récent pour faire foi ; sinon nil (repli sur le calendrier, `TeamCards.build`).
    public static func usableLive(_ cached: Cached<[MatchEvent]>?, now: Date) -> [MatchEvent]? {
        guard let cached else { return nil }
        let age = cached.age(now: now)
        return age >= 0 && age <= liveTrust ? cached.value : nil
    }
}
