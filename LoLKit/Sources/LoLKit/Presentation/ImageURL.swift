import Foundation

/// URLs d'images de l'API : souvent en `http://`, refusé par iOS (App Transport Security).
/// static.lolesports.com répond aussi en https.
public enum ImageURL {
    public static func secure(_ string: String?) -> URL? {
        guard let string, !string.isEmpty else { return nil }
        var value = string
        if value.hasPrefix("http://") {
            value = "https://" + value.dropFirst("http://".count)
        } else if value.hasPrefix("//") {
            value = "https:" + value
        }
        guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
