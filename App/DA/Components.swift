import LoLKit
import SwiftUI

/// Titre d'écran (32 pt, 700, −0,04 em) et sous-titre secondaire, avec un élément optionnel à droite.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(_ title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typo.title)
                    .tracking(Typo.titleTracking)
                    .foregroundStyle(Palette.text)
                Text(subtitle)
                    .font(Typo.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.top, 8)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Étiquette de section : 11 pt, capitales espacées, secondaire ; point lumineux optionnel à droite.
struct SectionLabel: View {
    let text: String
    var dot: Color? = nil

    var body: some View {
        HStack {
            Text(text)
                .font(Typo.label)
                .tracking(Typo.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let dot {
                GlowDot(color: dot)
            }
        }
    }
}

/// Point lumineux de l'en-tête des cartes Vitrail.
struct GlowDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color, radius: 5)
    }
}

/// Pastille : « En direct · Game 2 · 18:42 », « masqué ».
struct Chip<Content: View>: View {
    var muted = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 5) {
            content
        }
        .font(Typo.chip)
        .foregroundStyle(muted ? Palette.secondary : Palette.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(muted ? 0.07 : 0.10), in: Capsule())
    }
}

/// Pilule sélectionnable (ligues, games) : blanche quand elle est choisie, verre sinon (onglets d'Échap).
struct PillButton<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var label: Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                label
            }
            .font(selected ? Typo.secondaryMedium : Typo.secondary)
            .foregroundStyle(selected ? Palette.abyss : Palette.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Logo d'une équipe (fichier en cache, sinon téléchargé en https), ou à défaut son monogramme :
/// le code dans un badge bordé de sa couleur (verre neutre si l'équipe n'est pas suivie).
struct TeamBadge: View {
    let code: String
    var image: String? = nil
    var logoFile: URL? = nil
    var tint: Color? = nil
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.33, style: .continuous)
        ZStack {
            shape.fill(Palette.chipFill)
            if let logo = logoFile.flatMap({ UIImage(contentsOfFile: $0.path(percentEncoded: false)) }) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.14)
            } else if let url = ImageURL.secure(image) {
                AsyncImage(url: url) { phase in
                    if let loaded = phase.image {
                        loaded
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.14)
                    } else {
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(tint ?? Palette.glassBorder, lineWidth: 1))
    }

    private var monogram: some View {
        Text(code)
            .font(Sora.font(size * 0.3, .bold))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .foregroundStyle(tint ?? Palette.text)
    }
}

/// Bandeau discret quand l'API ne répond pas (spec §10).
struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            IconView(icon: .refresh, size: 13)
            Text(text)
                .font(Typo.secondaryMedium)
        }
        .foregroundStyle(Palette.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // Verre « matière » (pas de `glassEffect` : sa réfraction fait un écho du texte voisin).
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.glassBorder, lineWidth: 1))
        .frame(maxWidth: .infinity)
    }
}

/// Message sur verre neutre : chargement, liste vide, stats indisponibles.
struct NoteCard: View {
    let icon: Icon
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            IconView(icon: icon, size: 15)
            Text(text)
                .font(Typo.secondary)
        }
        .foregroundStyle(Palette.secondary)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}
