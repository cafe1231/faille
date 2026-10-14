import LoLKit
import SwiftUI

/// Bouton « Regarder » (spec fonctionnalités §1) : ouvre le stream préféré par `openURL` (l'app Twitch ou YouTube prend le
/// relais si elle est installée) ; appui long : menu des autres streams (langue · plateforme). N'existe que pour un match
/// en direct non masqué (`WatchLinks.live`). Carte : pastille compacte ; Détail : bouton en verre pleine largeur.
struct WatchButton: View {
    let live: WatchLinks.Live
    var compact = false
    /// Retour haptique (impact léger), joué par la vue qui reste affichée (carte ou Détail).
    var onHaptic: (Haptic) -> Void = { _ in }
    @Environment(\.openURL) private var openURL

    var body: some View {
        if live.others.isEmpty {
            Button(action: watch) { label }
                .buttonStyle(.pressable)
                .accessibilityLabel(accessibilityText)
        } else {
            Menu {
                ForEach(live.others, id: \.url) { link in
                    Button(WatchLinks.label(link)) { open(link.url) }
                }
            } label: {
                label
            } primaryAction: {
                watch()
            }
            .menuStyle(.button)
            .buttonStyle(.pressable)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Appui long : autres langues")
        }
    }

    private var accessibilityText: String {
        "Regarder · \(WatchLinks.label(live.preferred))"
    }

    @ViewBuilder private var label: some View {
        if compact {
            HStack(spacing: 5) {
                IconView(icon: .play, size: 12)
                Text("Regarder")
            }
            .font(Typo.chip)
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.chipFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
            // Zone tactile de 44 pt de haut, la pastille reste petite.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 6) {
                IconView(icon: .play, size: 15)
                Text("Regarder")
                Text("· \(WatchLinks.label(live.preferred))")
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .font(Typo.bodyMedium)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .glassCard(radius: Radius.inner, padding: 4)
        }
    }

    private func watch() {
        open(live.preferred.url)
    }

    private func open(_ url: URL) {
        onHaptic(.watch)
        openURL(url)
    }
}

/// « Revoir la game N » (spec fonctionnalités §1) : la rediffusion YouTube de la game choisie, dans la langue préférée,
/// au début de la game. N'existe que pour une game jouée d'un match non masqué (`WatchLinks.replay`).
struct ReplayButton: View {
    let gameNumber: Int
    let link: StreamLink
    var onHaptic: (Haptic) -> Void = { _ in }
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            onHaptic(.watch)
            openURL(link.url)
        } label: {
            HStack(spacing: 6) {
                IconView(icon: .play, size: 15)
                Text("Revoir la game \(gameNumber)")
                Text("· \(WatchLinks.label(link))")
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
            }
            .font(Typo.bodyMedium)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .glassCard(radius: Radius.inner, padding: 4)
        }
        .buttonStyle(.pressable)
    }
}
