import Foundation
import LoLKit

/// Noms affichés des périmètres de saison (spec saison §3.1, §3.8 : LoLKit donne des valeurs, l'appli formule) :
/// « Saison 2026 », « LEC Split 3 », « Mondial ». Chaînes prêtes pour `Localizable.xcstrings` (P2).
enum SeasonLabels {
    static func season(year: String) -> String {
        String(localized: "Saison \(year)")
    }

    /// Libellé d'un périmètre (`SeasonScope.label` est une valeur : l'année « 2026 » ou le slug d'un tournoi).
    static func scope(_ scope: SeasonScope) -> String {
        Int(scope.label) != nil ? season(year: scope.label) : tournament(slug: scope.label)
    }

    /// Nom d'une compétition par son slug de ligue : internationales traduites (« Mondial » / « Worlds »), les autres en
    /// capitales (« LEC », « LCK », « LFL »).
    static func league(slug: String) -> String {
        switch slug {
        case "worlds": return String(localized: "Mondial")
        case "msi": return "MSI"
        case "first_stand": return "First Stand"
        default: return slug.uppercased()
        }
    }

    /// « lec_split_3_2026 » → « LEC Split 3 » ; « worlds_2026 » → « Mondial » ; « lck_split_2_playoffs_2026 » →
    /// « LCK Split 2 Play-offs ». Le slug de ligue est le premier mot connu (`first_stand` en compte deux) ; l'année finale
    /// est retirée ; les autres mots prennent une capitale.
    static func tournament(_ tournament: TournamentRef) -> String {
        self.tournament(slug: tournament.slug)
    }

    static func tournament(slug: String) -> String {
        var words = slug.split(separator: "_").map(String.init)
        if let last = words.last, last.count == 4, Int(last) != nil { words.removeLast() }
        guard !words.isEmpty else { return slug }
        let leagueSlug: String
        if words.count >= 2, words[0] == "first", words[1] == "stand" {
            leagueSlug = "first_stand"
            words.removeFirst(2)
        } else {
            leagueSlug = words.removeFirst()
        }
        let rest = words.map { word -> String in
            switch word {
            case "playoffs": return String(localized: "Play-offs")
            case "split": return String(localized: "Split")
            default: return word.prefix(1).uppercased() + word.dropFirst()
            }
        }
        return ([league(slug: leagueSlug)] + rest).joined(separator: " ")
    }
}
