import Foundation
import LoLKit

/// « Regarder » et « Revoir » (spec fonctionnalités §1) : les liens que l'appli a le droit de montrer. Le choix du stream et
/// de la rediffusion vient de LoLKit (`StreamPicker`). Anti-spoiler : rien pour un match masqué — ni stream en direct
/// (l'image montre le score), ni rediffusion (le nombre de games trahit la série).
enum WatchLinks {
    /// Le stream du bouton « Regarder » et ceux du menu de l'appui long.
    struct Live: Equatable, Sendable {
        let preferred: StreamLink
        let others: [StreamLink]
    }

    /// Streams d'un match en cours et non masqué ; nil sinon, ou si aucun fournisseur n'est connu.
    static func live(_ streams: [StreamInfo]?, inProgress: Bool, masked: Bool) -> Live? {
        guard inProgress, !masked, let streams, let preferred = StreamPicker.preferred(streams) else { return nil }
        return Live(preferred: preferred, others: StreamPicker.others(streams))
    }

    /// « Revoir la game N » : la rediffusion d'une game jouée d'un match non masqué ; nil sinon.
    static func replay(_ game: GameRef, masked: Bool) -> StreamLink? {
        guard !masked, game.state == .completed, let vods = game.vods else { return nil }
        return StreamPicker.replay(vods)
    }

    /// Langues les plus courantes des streams lolesports, par code de langue.
    private static let languages = [
        "fr": "Français", "en": "Anglais", "ko": "Coréen", "zh": "Chinois", "es": "Espagnol", "pt": "Portugais",
        "de": "Allemand", "it": "Italien", "ja": "Japonais", "vi": "Vietnamien", "ru": "Russe", "pl": "Polonais",
        "tr": "Turc", "ar": "Arabe", "th": "Thaï",
    ]

    private static let platforms = ["twitch": "Twitch", "youtube": "YouTube", "afreecatv": "AfreecaTV"]

    /// « Français · Twitch » ; langue inconnue : son code tel quel (« xx-XX · Twitch ») ; sans langue : la plateforme seule.
    static func label(_ link: StreamLink) -> String {
        let platform = platforms[link.provider] ?? link.provider
        guard let locale = link.locale, !locale.isEmpty else { return platform }
        let code = String(locale.prefix { $0 != "-" && $0 != "_" }).lowercased()
        return "\(languages[code] ?? locale) · \(platform)"
    }
}
