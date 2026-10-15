import Foundation

/// Textes des widgets (spec §7), en français. L'anti-spoiler est déjà dans `WidgetLine` (spec §8) : une ligne
/// masquée n'a ni score ni numéro de game ; elle ne s'écrit qu'avec « En direct » ou sa date.
public enum WidgetText {
    /// La jauge du widget rond se remplit pendant les 24 h qui précèdent le match.
    public static let countdownSpan: TimeInterval = 24 * 3600

    /// Widget rectangulaire de l'écran verrouillé : étiquette, match, puis date ou ligue.
    public struct Rectangular: Sendable, Equatable {
        public let label: String
        public let title: String
        public let detail: String
        public let isLive: Bool
        public let isMasked: Bool

        public init(label: String, title: String, detail: String, isLive: Bool, isMasked: Bool) {
            self.label = label
            self.title = title
            self.detail = detail
            self.isLive = isLive
            self.isMasked = isMasked
        }
    }

    /// Widget rond de l'écran verrouillé.
    public enum Circular: Sendable, Equatable {
        /// « 21h » et le code de l'équipe suivie ; `progress` va de 0 (24 h ou plus avant) à 1 (le match commence).
        case countdown(text: String, code: String, progress: Double)
        /// Une équipe suivie joue (masquée ou non : seul « en direct » est dit).
        case live(code: String)
        /// Une équipe suivie a son prochain match masqué (`WidgetTeam.Next.hidden`) : son code et un œil barré, comme le
        /// direct masqué, jamais le match, un score ni une date (spec §8, audit B-W5). Les moyen, rectangulaire et petit
        /// widgets disent déjà « Prochain · masqué » : le rond n'apprend rien de plus.
        case masked(code: String)
        /// Rien à annoncer (jauge vide et trophée), y compris sans groupe d'apps.
        case empty
    }

    /// Une ligne du moyen widget.
    public struct Row: Sendable, Equatable {
        public let title: String
        public let trailing: String
        public let isLive: Bool
        public let isMasked: Bool

        public init(title: String, trailing: String, isLive: Bool, isMasked: Bool) {
            self.title = title
            self.trailing = trailing
            self.isLive = isLive
            self.isMasked = isMasked
        }
    }

    /// Une ligne affichée du moyen widget : son texte et les couleurs des équipes suivies qu'elle montre (pastilles).
    public struct MediumRow: Sendable, Equatable, Identifiable {
        /// Id du match, ou `hidden-<id de l'équipe>` pour la ligne « Prochain · masqué » d'une équipe.
        public let id: String
        public let text: Row
        /// Couleurs (hex) des équipes suivies de la ligne, dans l'ordre d'affichage.
        public let colorHexes: [String]
        /// Ligne « <CODE> · Prochain · masqué » d'une équipe (`WidgetTeam.Next.hidden`), pas un match.
        public let isHiddenNext: Bool

        public init(id: String, text: Row, colorHexes: [String], isHiddenNext: Bool = false) {
            self.id = id
            self.text = text
            self.colorHexes = colorHexes
            self.isHiddenNext = isHiddenNext
        }
    }

    /// Le petit widget d'une équipe.
    public struct Small: Sendable, Equatable {
        public let label: String
        public let title: String
        public let day: String?
        public let time: String?
        public let note: String?
        public let isLive: Bool
        public let isMasked: Bool

        public init(label: String, title: String, day: String?, time: String?, note: String?, isLive: Bool,
                    isMasked: Bool) {
            self.label = label
            self.title = title
            self.day = day
            self.time = time
            self.note = note
            self.isLive = isLive
            self.isMasked = isMasked
        }
    }

    /// Ce que dit une équipe en anti-spoiler dont le prochain match est masqué (`WidgetTeam.Next.hidden`).
    static let hiddenNext = "Prochain · masqué"

    /// Sans équipe suivie, tous les widgets disent où en ajouter (une seule source pour les trois familles).
    public static let addTeamsAdvice = "Ajoute-en dans l'appli"

    /// Le moyen widget montre au plus ce nombre de lignes.
    public static let mediumRowLimit = 4

    /// Groupe d'apps introuvable (`WidgetContent.appGroupMissing`) : titre, conseil, et les deux d'une ligne.
    static let appGroupMissingTitle = "Groupe d'apps introuvable"
    static let appGroupMissingAdvice = "Réinstalle Faille avec AltServer"
    public static let appGroupMissingMessage = "Groupe d'apps introuvable — réinstalle Faille avec AltServer"

    /// Rien à montrer : « Groupe d'apps introuvable — réinstalle Faille avec AltServer » (l'extension ne trouve pas le
    /// groupe d'apps de Faille, elle n'a rien pu lire), « Aucune équipe suivie », « Prochain · masqué » (une équipe en
    /// anti-spoiler dont le prochain match est masqué : on ne dit pas « Aucun match prévu », on y lirait une équipe
    /// éliminée, spec §8) ou « Aucun match prévu ».
    public static func emptyMessage(_ content: WidgetContent) -> String {
        if content.appGroupMissing { return appGroupMissingMessage }
        if content.teams.isEmpty { return "Aucune équipe suivie" }
        return hasHiddenTeam(content) ? hiddenNext : "Aucun match prévu"
    }

    /// Widget en ligne : « KC 1–0 C9 · G2 », « T1 vs FLY · En direct », « GEN vs FUR · jeu. 11:00 ».
    public static func inline(_ content: WidgetContent, timeZone: TimeZone = .current) -> String {
        guard let line = content.headline else { return emptyMessage(content) }
        switch line.status {
        case let .live(score, gameNumber):
            guard !line.isMasked, score != nil else { return "\(title(line)) · \(Format.maskedStatus(.inGame))" }
            let compact = title(line, compact: true)
            return gameNumber.map { "\(compact) · G\($0)" } ?? compact
        case let .upcoming(start):
            return "\(title(line)) · \(Format.shortDate(start, now: content.date, timeZone: timeZone))"
        }
    }

    /// Widget rectangulaire : « Prochain · GEN vs FUR · jeu. 15 oct. · 11:00 » ; en direct : « En direct ·
    /// KC 1 – 0 C9 · Mondial · Game 2 » ; masqué : « En direct · T1 vs FLY · Mondial ». Sans match à montrer : « Faille ·
    /// Aucune équipe suivie » ; « Prochain · Masqué · Ouvre Faille pour révéler » quand une équipe suivie a son prochain match masqué
    /// (jamais « Aucun match prévu » : on y lirait une équipe éliminée, spec §8) ; sinon « Prochain · Aucun match prévu ».
    public static func rectangular(_ content: WidgetContent, timeZone: TimeZone = .current) -> Rectangular {
        guard let line = content.headline else {
            if content.appGroupMissing {
                return Rectangular(label: "Faille", title: appGroupMissingTitle, detail: appGroupMissingAdvice,
                                   isLive: false, isMasked: false)
            }
            if content.teams.isEmpty {
                return Rectangular(label: "Faille", title: "Aucune équipe suivie", detail: addTeamsAdvice,
                                   isLive: false, isMasked: false)
            }
            if hasHiddenTeam(content) {
                return Rectangular(label: "Prochain", title: "Masqué", detail: "Ouvre Faille pour révéler",
                                   isLive: false, isMasked: true)
            }
            return Rectangular(label: "Prochain", title: "Aucun match prévu", detail: "Ouvre Faille pour actualiser",
                               isLive: false, isMasked: false)
        }
        switch line.status {
        case .live:
            return Rectangular(label: Format.maskedStatus(.inGame), title: title(line), detail: liveDetail(line),
                               isLive: true, isMasked: line.isMasked)
        case let .upcoming(start):
            return Rectangular(label: "Prochain", title: title(line), detail: Format.matchDate(start, timeZone: timeZone),
                               isLive: false, isMasked: line.isMasked)
        }
    }

    /// Widget rond : compte à rebours vers le prochain match et code de l'équipe suivie, ou « en direct ».
    public static func circular(_ content: WidgetContent) -> Circular {
        guard let line = content.headline, let code = line.codes.first else {
            if let hidden = content.teams.first(where: { $0.next == .hidden }) { return .masked(code: hidden.team.code) }
            return .empty
        }
        switch line.status {
        case .live:
            return .live(code: code)
        case let .upcoming(start):
            let remaining = start.timeIntervalSince(content.date)
            let progress = min(1, max(0, 1 - remaining / countdownSpan))
            // « maintenant » ne tient pas dans 50 pt : à zéro (ou en retard), le rond écrit « 0 min ».
            let text = remaining < 60 ? "0 min" : Format.countdown(from: content.date, to: start)
            return .countdown(text: text, code: code, progress: progress)
        }
    }

    /// Lignes du moyen widget, `limit` au plus : d'abord les lignes datées (`content.lines` : le direct, puis les prochains
    /// matchs par heure de début), puis une ligne « T1 · Prochain · masqué » par équipe dont le prochain match est masqué
    /// (`WidgetTeam.Next.hidden`), dans l'ordre de suivi. Les lignes masquées ne sont ni triées ni placées selon le match
    /// caché : leur présence et leur place ne dépendent que du nombre de lignes datées et de l'ordre de suivi (spec §8).
    /// Une équipe en direct a déjà sa ligne dans `content.lines`. Vide quand il n'y a rien : la vue écrit `emptyMessage`.
    public static func mediumRows(_ content: WidgetContent, limit: Int = mediumRowLimit,
                                  timeZone: TimeZone = .current) -> [MediumRow] {
        let dated = content.lines.prefix(limit).map { line in
            MediumRow(id: line.matchId, text: row(line, now: content.date, timeZone: timeZone),
                      colorHexes: line.colorHexes.compactMap { $0 })
        }
        let hidden = content.teams.filter { $0.next == .hidden }.prefix(max(0, limit - dated.count)).map { team in
            MediumRow(id: "hidden-\(team.team.id)",
                      text: Row(title: team.team.code, trailing: hiddenNext, isLive: false, isMasked: true),
                      colorHexes: [team.team.colorHex], isHiddenNext: true)
        }
        return dated + hidden
    }

    /// Ligne du moyen widget : « KC 1 – 0 C9 » + « Game 2 » ; masqué : « T1 vs FLY » + « En direct » ;
    /// à venir : « GEN vs FUR » + « jeu. 11:00 ».
    public static func row(_ line: WidgetLine, now: Date, timeZone: TimeZone = .current) -> Row {
        switch line.status {
        case let .live(_, gameNumber):
            let game = line.isMasked ? nil : gameNumber
            return Row(title: title(line), trailing: game.map { "Game \($0)" } ?? Format.maskedStatus(.inGame),
                       isLive: true, isMasked: line.isMasked)
        case let .upcoming(start):
            return Row(title: title(line), trailing: Format.shortDate(start, now: now, timeZone: timeZone),
                       isLive: false, isMasked: line.isMasked)
        }
    }

    /// Petit widget : le prochain match de l'équipe (jour et heure), son match en direct, « Prochain · masqué »
    /// (`WidgetTeam.Next.hidden` : règle F1, le dernier match de l'équipe est masqué ; ou règle C, son prochain match
    /// l'oppose à une autre équipe suivie en anti-spoiler dont le dernier match est masqué) ou « Aucun match prévu ».
    /// Dans le cas masqué, le match, l'adversaire et sa date ne sont pas dits (spec §8).
    /// `appGroupMissing` (`WidgetContent.appGroupMissing`) remplace « Aucune équipe suivie » par le groupe d'apps
    /// introuvable.
    public static func small(_ team: WidgetTeam?, appGroupMissing: Bool = false, timeZone: TimeZone = .current) -> Small {
        guard let team else {
            if appGroupMissing {
                return Small(label: "Faille", title: appGroupMissingTitle, day: nil, time: nil,
                             note: appGroupMissingAdvice, isLive: false, isMasked: false)
            }
            return Small(label: "Faille", title: "Aucune équipe suivie", day: nil, time: nil,
                         note: addTeamsAdvice, isLive: false, isMasked: false)
        }
        switch team.next {
        case let .live(line):
            return Small(label: Format.maskedStatus(.inGame), title: title(line), day: nil, time: nil,
                         note: liveDetail(line), isLive: true, isMasked: line.isMasked)
        case let .match(line):
            return Small(label: "Prochain", title: title(line),
                         day: line.upcomingStart.map { Format.day($0, timeZone: timeZone) },
                         time: line.upcomingStart.map { Format.time($0, timeZone: timeZone) },
                         note: nil, isLive: false, isMasked: line.isMasked)
        case .hidden:
            return Small(label: "Prochain", title: team.team.code, day: nil, time: nil, note: "masqué",
                         isLive: false, isMasked: true)
        case .noMatch:
            return Small(label: "Prochain", title: team.team.code, day: nil, time: nil, note: "Aucun match prévu",
                         isLive: false, isMasked: false)
        }
    }

    // MARK: - Interne

    /// Au moins une équipe suivie n'annonce rien parce que son prochain match est masqué (`WidgetTeam.Next.hidden`).
    static func hasHiddenTeam(_ content: WidgetContent) -> Bool {
        content.teams.contains { $0.next == .hidden }
    }

    /// « KC 1 – 0 C9 » (« KC 1–0 C9 » en compact) ; sans score (masqué ou à venir) : « T1 vs FLY ». Une ligne masquée
    /// n'écrit jamais de score, même si on lui en a donné un (spec §8).
    static func title(_ line: WidgetLine, compact: Bool = false) -> String {
        if !line.isMasked, case let .live(score?, _) = line.status, score.count == 2, line.codes.count == 2 {
            let dash = compact ? "–" : " – "
            return "\(line.codes[0]) \(score[0])\(dash)\(score[1]) \(line.codes[1])"
        }
        return line.codes.joined(separator: " vs ")
    }

    /// « Mondial · Game 2 » ; masqué : « Mondial » (spec §8 : pas de numéro de game, même si la ligne en porte un).
    static func liveDetail(_ line: WidgetLine) -> String {
        if !line.isMasked, case let .live(_, gameNumber?) = line.status {
            return "\(line.leagueName) · Game \(gameNumber)"
        }
        return line.leagueName
    }
}
