import Foundation

/// Formats propres à l'appli (étape 2), en français, identiques sur toutes les plateformes.
extension Format {
    /// « 14:05 » dans le fuseau donné.
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return twoDigits(parts.hour ?? 0) + ":" + twoDigits(parts.minute ?? 0)
    }

    /// Bandeau d'erreur (spec §10) : « lolesports ne répond pas · màj 14:05 ».
    public static func offlineBanner(lastUpdate: Date?, timeZone: TimeZone = .current) -> String {
        guard let lastUpdate else { return "lolesports ne répond pas" }
        return "lolesports ne répond pas · màj " + time(lastUpdate, timeZone: timeZone)
    }

    /// Chrono d'une game : « 18:42 », « 1:02:05 » au-delà d'une heure.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        if hours > 0 { return "\(hours):" + twoDigits(minutes) + ":" + twoDigits(rest) }
        return "\(minutes):" + twoDigits(rest)
    }

    /// Score de série : « 1 – 0 ».
    public static func score(_ score: [Int]) -> String {
        score.map(String.init).joined(separator: " – ")
    }

    /// KDA d'un joueur : « 2/0/1 ».
    public static func kda(_ player: PlayerLine) -> String {
        "\(player.kills)/\(player.deaths)/\(player.assists)"
    }

    private static let dragonNames = [
        "infernal": "infernal", "ocean": "océan", "cloud": "nuage", "mountain": "montagne",
        "hextech": "hextech", "chemtech": "chemtech", "elder": "ancien",
    ]

    /// Types de drakes en français : « infernal, océan ». Type inconnu : tel quel, en minuscules.
    public static func dragons(_ types: [String]) -> String {
        types.map { dragonNames[$0.lowercased()] ?? $0.lowercased() }.joined(separator: ", ")
    }

    private static let roles = ["top": "TOP", "jungle": "JGL", "mid": "MID", "bottom": "BOT", "support": "SUP"]

    /// Rôle court : « JGL ». Rôle inconnu : ses 3 premières lettres en capitales.
    public static func role(_ role: String) -> String {
        roles[role.lowercased()] ?? String(role.uppercased().prefix(3))
    }

    /// Nom de champion lisible depuis son id : « XinZhao » → « Xin Zhao » (espace avant une capitale qui suit une minuscule).
    public static func champion(_ id: String) -> String {
        var result = ""
        var previous: Character?
        for character in id {
            if character.isUppercase, let previous, previous.isLowercase {
                result.append(" ")
            }
            result.append(character)
            previous = character
        }
        return result
    }

    /// Sous-titre de l'onglet Matchs : « 2 en direct · 1 à venir » (à venir = cartes sans direct mais avec un prochain match).
    public static func cardsSubtitle(_ cards: [TeamCard]) -> String {
        let live = cards.filter { $0.live != nil }.count
        let upcoming = cards.filter { $0.live == nil && $0.next != nil }.count
        return "\(live) en direct · \(upcoming) à venir"
    }

    /// Sous-titre de l'onglet Équipes : « 3 suivies », « 1 suivie », « aucune équipe suivie ».
    public static func followCount(_ count: Int) -> String {
        switch count {
        case 0: return "aucune équipe suivie"
        case 1: return "1 suivie"
        default: return "\(count) suivies"
        }
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
