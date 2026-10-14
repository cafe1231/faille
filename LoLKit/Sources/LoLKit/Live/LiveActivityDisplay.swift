import Foundation

/// Ce qu'affiche une Live Activity (spec §6.1-§6.3, maquettes ① et ②), calculé sans SwiftUI pour être testé sur
/// Windows : l'écran verrouillé et la Dynamic Island ne font que poser ces valeurs. L'anti-spoiler est déjà dans l'état
/// (`LiveMatchBuilder.state` → `masked()`) : masqué, il n'y a ici ni score, ni numéro de game, ni chrono, ni stats, ni
/// vainqueur (spec §8). Une Live Activity n'annonce jamais de prochain match.
public struct LiveActivityDisplay: Sendable, Equatable {
    /// Une équipe, dans l'ordre d'affichage : l'équipe suivie (principale) à gauche, comme les maquettes.
    public struct Side: Sendable, Equatable {
        public let code: String
        /// Couleur de l'équipe si elle est suivie ; nil : verre neutre.
        public let colorHex: String?

        public init(code: String, colorHex: String?) {
            self.code = code
            self.colorHex = colorHex
        }
    }

    /// Chrono de la game en cours.
    public enum GameClock: Sendable, Equatable {
        /// Tourne seul depuis cette date (minuteur natif d'iOS : aucune mise à jour nécessaire).
        case running(since: Date)
        /// Figé (game en pause ou finie dans le flux) : « 18:42 ».
        case stopped(String)
    }

    /// À droite de l'en-tête.
    public enum Status: Sendable, Equatable {
        case clock(GameClock)
        /// « En direct » : match masqué, avant la game 1, ou game en cours dont le début est inconnu.
        case live
        /// « entre deux games ».
        case betweenGames
        /// « Victoire KC ».
        case victory(String)
        /// « Terminé » : match masqué, ou vainqueur inconnu (forfait, Bo2).
        case finished
        /// « màj il y a X minutes » à la place du chrono : rien de frais depuis `since` (spec §6.3).
        case stale(since: Date)

        /// Texte fixe ; nil pour le chrono (minuteur natif). Pour `.stale` : « màj », la vue y ajoute la durée avec le
        /// texte système « il y a X minutes » (minuteur natif) — le libellé ne la contient donc pas.
        public var label: String? {
            switch self {
            case .clock: return nil
            case .live: return "En direct"
            case .betweenGames: return "entre deux games"
            case let .victory(code): return "Victoire \(code)"
            case .finished: return "Terminé"
            case .stale: return "màj"
            }
        }
    }

    /// Les 5 stats de la spec §6.1, dans l'ordre d'affichage.
    public enum Stat: String, Sendable, Hashable, CaseIterable {
        case kills, gold, towers, drakes, barons

        public var label: String {
            switch self {
            case .kills: return "Kills"
            case .gold: return "Gold"
            case .towers: return "Tours"
            case .drakes: return "Drakes"
            case .barons: return "Barons"
            }
        }
    }

    /// Une ligne « 7 · KILLS · 4 ». Pour le gold : l'écart (« +2,1k ») à côté de l'équipe qui mène (`leader`, 0 ou 1).
    public struct Row: Sendable, Equatable {
        public let stat: Stat
        public let left: String
        public let right: String
        public let lead: String?
        public let leader: Int?
        /// Version courte de la Dynamic Island déployée : « 7–4 », « +2,1k ».
        public let compact: String

        public init(stat: Stat, left: String, right: String, lead: String?, leader: Int?, compact: String) {
            self.stat = stat
            self.left = left
            self.right = right
            self.lead = lead
            self.leader = leader
            self.compact = compact
        }
    }

    /// Message sous le score.
    public enum Message: Sendable, Equatable {
        /// « Sans spoiler · ouvre l'appli pour révéler » (spec §8 : la révélation se fait dans l'appli).
        case masked
        /// « La game 3 commence dans quelques minutes » (spec §6.3).
        case nextGame(Int)
        /// Riot ne fournit pas les stats de ce match (spec §6.3).
        case statsUnavailable
        /// Stats prévues mais pas encore reçues du flux.
        case statsPending
        /// Match terminé : la Live Activity se retire au bout d'une heure (spec §6.3).
        case leavingSoon

        public var text: String {
            switch self {
            case .masked: return "Sans spoiler ·"
            case let .nextGame(number): return "La game \(number) commence dans quelques minutes"
            case .statsUnavailable: return "Stats live non fournies par Riot pour ce match"
            case .statsPending: return "Stats en attente du flux de Riot"
            case .leavingSoon: return "Se retire de l'écran verrouillé au bout d'une heure"
            }
        }

        /// Suite du texte, à la couleur d'accent.
        public var accent: String? {
            if case .masked = self { return "ouvre l'appli pour révéler" }
            return nil
        }
    }

    /// « Mondial · Bo5 · Game 2 » (« · terminé » à la fin ; rien après le Bo si masqué). La vue le met en capitales.
    public let header: String
    public let teams: [Side]
    /// Victoires dans l'ordre de `teams` ; nil si masqué.
    public let score: [Int]?
    /// nil si masqué ou terminé.
    public let gameNumber: Int?
    public let status: Status
    /// Les 5 lignes de stats ; vides hors d'une game en cours, sans stats, ou si masqué.
    public let rows: [Row]
    /// Pas fraîche : les stats pâlissent (spec §6.3).
    public let faded: Bool
    public let message: Message?
    /// Couleur du fond : celle de l'équipe suivie en premier (`primaryTeamIndex`) ; nil : verre neutre.
    public let tintHex: String?
    public let isMasked: Bool

    public init(attributes: LiveMatchAttributes, state: LiveMatchState, isStale: Bool) {
        let order = Self.order(attributes)
        let masked = state.spoilerFree
        let finished = state.phase == .finished
        teams = (reorder(attributes.teams, order) ?? attributes.teams).map { Side(code: $0.code, colorHex: $0.colorHex) }
        tintHex = attributes.primaryTeamIndex.flatMap { index in
            attributes.teams.indices.contains(index) ? attributes.teams[index].colorHex : nil
        }
        isMasked = masked
        score = masked ? nil : state.seriesScore.flatMap { reorder($0, order) }
        gameNumber = masked ? nil : state.gameNumber

        var parts = [attributes.leagueName, "Bo\(attributes.bestOf)"]
        if !masked {
            if finished {
                parts.append("terminé")
            } else if let number = state.gameNumber {
                parts.append("Game \(number)")
            }
        }
        header = parts.joined(separator: " · ")

        if isStale && !finished {
            status = .stale(since: state.updatedAt)
        } else if masked {
            status = finished ? .finished : .live
        } else {
            switch state.phase {
            case .inGame: status = Self.runningClock(state).map { Status.clock($0) } ?? .live
            case .betweenGames: status = .betweenGames
            case .upcoming: status = .live
            case .finished: status = state.winnerCode.map { Status.victory($0) } ?? .finished
            }
        }

        var shownRows: [Row] = []
        if !masked, state.phase == .inGame, let stats = state.stats.flatMap({ reorder($0, order) }), stats.count == 2 {
            shownRows = Self.rows(stats[0], stats[1])
        }
        rows = shownRows
        faded = isStale && !finished

        if masked {
            message = .masked
        } else {
            switch state.phase {
            case .finished: message = .leavingSoon
            case .betweenGames, .upcoming: message = .nextGame(state.gameNumber ?? 1)
            case .inGame: message = !state.statsAvailable ? .statsUnavailable : (shownRows.isEmpty ? .statsPending : nil)
            }
        }
    }

    /// Score de la Dynamic Island minimale : « 1-0 » ; nil si masqué.
    public var compactScore: String? {
        guard let score, score.count == 2 else { return nil }
        return "\(score[0])-\(score[1])"
    }

    /// Ordre d'affichage : l'équipe principale à gauche.
    static func order(_ attributes: LiveMatchAttributes) -> [Int] {
        attributes.primaryTeamIndex == 1 && attributes.teams.count == 2 ? [1, 0] : Array(attributes.teams.indices)
    }

    /// Chrono d'une game en cours ; une date d'arrêt sans date de début ne donne pas de chrono.
    static func runningClock(_ state: LiveMatchState) -> GameClock? {
        guard let start = state.gameClockStart else { return nil }
        if let stopped = state.gameClockStoppedAt {
            return .stopped(Format.clock(stopped.timeIntervalSince(start)))
        }
        return .running(since: start)
    }

    /// Kills, gold (écart à côté du meneur), tours, drakes, barons ; `a` est l'équipe de gauche.
    static func rows(_ a: TeamStats, _ b: TeamStats) -> [Row] {
        func plain(_ stat: Stat, _ x: Int, _ y: Int) -> Row {
            Row(stat: stat, left: "\(x)", right: "\(y)", lead: nil, leader: nil, compact: "\(x)–\(y)")
        }
        let diff = a.gold - b.gold
        let leader: Int? = diff > 0 ? 0 : (diff < 0 ? 1 : nil)
        let lead = leader.map { _ in Format.goldDiff(abs(diff)) }
        return [
            plain(.kills, a.kills, b.kills),
            Row(stat: .gold, left: Format.gold(a.gold), right: Format.gold(b.gold), lead: lead, leader: leader,
                compact: lead ?? Format.goldDiff(0)),
            plain(.towers, a.towers, b.towers),
            plain(.drakes, a.dragons.count, b.dragons.count),
            plain(.barons, a.barons, b.barons),
        ]
    }
}
