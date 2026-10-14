import SwiftUI
import UIKit

extension EnvironmentValues {
    /// Store Data Dragon des vues de la game (draft, joueurs, fiche) ; nil (aperçus de composants) : vignettes de repli.
    @Entry var dataDragon: DataDragonStore? = nil
}

/// Icône Data Dragon (champion, objet, rune, sort) : l'image du cache, décodée par `DataDragonStore` hors du `body`, sinon
/// une vignette de repli (initiales sur verre, ou verre seul pour une case vide). La vue ne lit jamais de fichier ; sans
/// URL (version Data Dragon pas encore connue) ni store (aperçus), elle ne demande rien.
struct DDragonIcon: View {
    let url: URL?
    var size: CGFloat = 28
    /// Coins ; nil : 22 % de la taille. `size / 2` : rond (runes, balise).
    var radius: CGFloat? = nil
    /// Texte de la vignette de repli (« KS » pour K'Santé) ; vide : verre seul.
    var fallback = ""
    @Environment(\.dataDragon) private var store
    @State private var loaded: (url: URL, image: UIImage)?

    /// Image à afficher : celle déjà décodée pour cette URL, sinon celle de la mémoire du store, sinon nil (repli).
    private var image: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return store?.cachedImage(url)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? size * 0.22, style: .continuous)
        ZStack {
            shape.fill(Palette.chipFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if !fallback.isEmpty {
                Text(fallback)
                    .font(Sora.font(max(8, size * 0.32), .semibold))
                    .foregroundStyle(Palette.secondary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.glassBorder, lineWidth: 0.5))
        .task(id: url) {
            guard let url, let store else {
                loaded = nil
                return
            }
            if let image = await store.image(url) {
                loaded = (url, image)
            }
        }
        .accessibilityHidden(true)
    }

    /// Initiales d'un id de champion pour la vignette de repli : « KSante » → « KS », « XinZhao » → « XZ », « Ahri » → « AH ».
    static func initials(_ name: String) -> String {
        let capitals = name.filter(\.isUppercase)
        if capitals.count >= 2 { return String(capitals.prefix(2)) }
        return String(name.filter(\.isLetter).prefix(2)).uppercased()
    }
}
