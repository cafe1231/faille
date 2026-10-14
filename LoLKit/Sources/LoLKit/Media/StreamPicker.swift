import Foundation

/// Un lien « Regarder » (stream en direct) ou « Revoir » (rediffusion d'une game), à ouvrir avec `openURL`.
public struct StreamLink: Sendable, Equatable {
    /// Fournisseur en minuscules : `twitch`, `youtube` ou `afreecatv`.
    public let provider: String
    /// Langue du stream, ex. `fr-FR` (nil si l'API ne la donne pas).
    public let locale: String?
    public let url: URL

    public init(provider: String, locale: String?, url: URL) {
        self.provider = provider
        self.locale = locale
        self.url = url
    }
}

/// Choix du stream et des rediffusions (spec fonctionnalités §1). Ne connaît que les fournisseurs dont on sait écrire le
/// lien ; un autre fournisseur est ignoré. Anti-spoiler : l'appli n'appelle ces fonctions que pour un match non masqué.
public enum StreamPicker {
    /// Langues préférées, dans l'ordre ; sinon, le premier stream utilisable.
    public static let preferredLocales = ["fr-FR", "en-US"]

    /// Lien d'un stream chez son fournisseur : Twitch `https://www.twitch.tv/<parameter>`, YouTube
    /// `https://www.youtube.com/watch?v=<parameter>`, AfreecaTV `https://play.afreecatv.com/<parameter>`.
    /// nil pour un fournisseur inconnu ou un identifiant vide.
    public static func url(provider: String?, parameter: String?) -> URL? {
        guard let parameter, !parameter.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        switch provider?.lowercased() {
        case "twitch":
            components.host = "www.twitch.tv"
            components.path = "/" + parameter
        case "youtube":
            components.host = "www.youtube.com"
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: parameter)]
        case "afreecatv":
            components.host = "play.afreecatv.com"
            components.path = "/" + parameter
        default:
            return nil
        }
        return components.url
    }

    /// Streams utilisables (fournisseur connu), dans l'ordre de l'API, sans doublon de lien.
    public static func links(_ streams: [StreamInfo]) -> [StreamLink] {
        var seen = Set<URL>()
        return streams.compactMap { stream -> StreamLink? in
            guard let provider = stream.provider?.lowercased(),
                  let url = url(provider: provider, parameter: stream.parameter),
                  seen.insert(url).inserted else { return nil }
            return StreamLink(provider: provider, locale: stream.locale, url: url)
        }
    }

    /// Stream du bouton « Regarder » : `fr-FR`, sinon `en-US`, sinon le premier utilisable ; nil s'il n'y en a aucun.
    public static func preferred(_ streams: [StreamInfo]) -> StreamLink? {
        pick(links(streams))
    }

    /// Les autres streams (menu de l'appui long : langue + plateforme), dans l'ordre de l'API, sans le préféré.
    public static func others(_ streams: [StreamInfo]) -> [StreamLink] {
        let all = links(streams)
        guard let chosen = pick(all) else { return [] }
        return all.filter { $0 != chosen }
    }

    /// « Revoir la game N » : la rediffusion YouTube dans la langue préférée (même ordre que les streams), avec
    /// `&t=<startMillis / 1000>s` si la game commence plus loin dans la vidéo. nil si la game n'a pas de rediffusion.
    public static func replay(_ vods: [Vod]) -> StreamLink? {
        let links = vods.compactMap { vod -> StreamLink? in
            guard vod.provider?.lowercased() == "youtube",
                  let base = url(provider: "youtube", parameter: vod.parameter),
                  var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            let seconds = (vod.startMillis ?? 0) / 1000
            if seconds > 0 {
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "t", value: "\(seconds)s")]
            }
            guard let url = components.url else { return nil }
            return StreamLink(provider: "youtube", locale: vod.locale, url: url)
        }
        return pick(links)
    }

    /// Premier lien dans une langue préférée (dans l'ordre de `preferredLocales`), sinon le premier.
    static func pick(_ links: [StreamLink]) -> StreamLink? {
        for locale in preferredLocales {
            if let link = links.first(where: { $0.locale == locale }) { return link }
        }
        return links.first
    }
}
