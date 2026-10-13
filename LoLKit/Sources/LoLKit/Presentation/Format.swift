import Foundation

/// Formats d'affichage en français, identiques sur toutes les plateformes.
public enum Format {
    /// 37442 → « 37,4k » ; 67995 → « 68k » ; 850 → « 850 ».
    public static func gold(_ value: Int) -> String {
        let magnitude = abs(value)
        guard magnitude >= 1000 else { return "\(value)" }
        let tenths = (magnitude + 50) / 100
        let sign = value < 0 ? "-" : ""
        let whole = tenths / 10
        let decimal = tenths % 10
        return decimal == 0 ? "\(sign)\(whole)k" : "\(sign)\(whole),\(decimal)k"
    }

    /// Écart signé : « +1,6k », « -800 », « 0 ».
    public static func goldDiff(_ diff: Int) -> String {
        diff > 0 ? "+" + gold(diff) : gold(diff)
    }

    private static let days = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    private static let months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

    /// « jeu. 15 oct. · 20:00 » dans le fuseau donné.
    public static func matchDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .day, .month, .hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let time = (hour < 10 ? "0" : "") + "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
        return "\(days[(parts.weekday ?? 1) - 1]) \(parts.day ?? 0) \(months[(parts.month ?? 1) - 1]) · \(time)"
    }

    /// « ven. 16 oct. » dans le fuseau donné.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .day, .month], from: date)
        return "\(days[(parts.weekday ?? 1) - 1]) \(parts.day ?? 0) \(months[(parts.month ?? 1) - 1])"
    }

    /// Date courte des widgets : « jeu. 11:00 » d'ici 6 jours (au calendrier), sinon « mar. 20 oct. ».
    public static func shortDate(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let ahead = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                            to: calendar.startOfDay(for: date)).day ?? 0
        guard ahead <= 6 else { return day(date, timeZone: timeZone) }
        let weekday = calendar.component(.weekday, from: date)
        return "\(days[weekday - 1]) \(time(date, timeZone: timeZone))"
    }

    /// `countdown` compte en heures jusqu'à cette avance (48 h), puis en jours : `WidgetTimeline` place ses paliers
    /// horaires jusque-là.
    static let countdownHoursLimit = 48

    /// Compte à rebours court pour le widget rond : « 45 min », « 21h », « 3 j », « maintenant ».
    public static func countdown(from now: Date, to date: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes <= 0 { return "maintenant" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < countdownHoursLimit { return "\(hours)h" }
        return "\(hours / 24) j"
    }
}
