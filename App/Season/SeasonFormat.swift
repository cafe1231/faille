import Foundation
import LoLKit

/// Chiffres des écrans de saison (spec saison §1.5, « Affichage ») : KDA et CS/min à 1 décimale, gold/min entier, parts
/// en % entier, durée « 35:10 », bilans « 9-0 ». Séparateur décimal de la langue de l'appareil (« 3,4 » en français).
/// Une valeur absente s'écrit « — » (jamais de chiffre inventé).
enum SeasonFormat {
    static let missing = "—"

    static func decimal(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    static func integer(_ value: Double, locale: Locale = .current) -> String {
        Int(value.rounded()).formatted(.number.locale(locale))
    }

    /// Part (0…1) en pourcentage entier : « 23 % » (espace de la langue).
    static func percent(_ share: Double?, locale: Locale = .current) -> String {
        guard let share else { return missing }
        return (share.rounded(toPlaces: 2)).formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    /// « 35:10 » ; une heure ou plus : « 1:02:03 ».
    static func duration(seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// Bilan « 9-0 ».
    static func record(_ wins: Int, _ losses: Int) -> String {
        "\(wins)-\(losses)"
    }

    /// Écart signé « +228 » / « −1 450 » (signe moins typographique) ; nil → « — ».
    static func signed(_ value: Double?, locale: Locale = .current) -> String {
        guard let value else { return missing }
        let magnitude = integer(abs(value), locale: locale)
        return value < 0 ? "\u{2212}\(magnitude)" : "+\(magnitude)"
    }

    /// K/D/A « 4/6/4 ».
    static func kda(kills: Int, deaths: Int, assists: Int) -> String {
        "\(kills)/\(deaths)/\(assists)"
    }
}

/// Noms affichés des écrans de saison (spec saison §1.5).
enum SeasonNames {
    /// Joueur : pseudo du catalogue (`Team.players`) s'il est connu, sinon le pseudo du flux sans le préfixe du code de son
    /// équipe (« KC Canna » → « Canna », `PlayerName.display`).
    static func player(_ playerId: String, raw: String, teamCode: String?, catalog: [Team]) -> String {
        for team in catalog {
            if let player = team.players?.first(where: { $0.id == playerId }) { return player.summonerName }
        }
        return PlayerName.display(raw, teamCode: teamCode)
    }

    /// Poste : « top » → « Top », « bottom » → « ADC »… ; inconnu → « Remplaçant ».
    static func role(_ role: String?) -> String {
        switch role {
        case "top": String(localized: "Top")
        case "jungle": String(localized: "Jungle")
        case "mid": String(localized: "Mid")
        case "bottom": String(localized: "ADC")
        case "support": String(localized: "Support")
        default: String(localized: "Remplaçant")
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
