import LoLKit
import SwiftUI
import WidgetKit

/// Widget en ligne de l'écran verrouillé (spec §7) : « KC 1–0 C9 · G2 », « GEN vs FUR · jeu. 11:00 ».
/// iOS n'en garde qu'une image et une ligne de texte, dans sa propre police.
struct InlineWidgetView: View {
    let content: WidgetContent
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        Label {
            Text(WidgetText.inline(content, timeZone: timeZone))
        } icon: {
            InlineIcon.image(content.headline?.isLive == true ? .live : .clock)
        }
        .numericTransition()
    }
}

/// Widget rectangulaire (spec §7, maquette ①) : « PROCHAIN », le match, la date ; en direct : la ligue et la game.
/// Monochrome sur l'écran verrouillé : seulement les niveaux primaire et secondaire, jamais de couleur d'équipe.
struct RectangularWidgetView: View {
    let content: WidgetContent
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let text = WidgetText.rectangular(content, timeZone: timeZone)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                IconView(icon: text.isLive ? .live : .trophy, size: 10)
                Text(text.label)
                    .font(Sora.font(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
            }
            .foregroundStyle(.secondary)
            Text(text.title)
                .font(Sora.font(15, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            HStack(spacing: 4) {
                if text.isMasked {
                    IconView(icon: .eyeOff, size: 10)
                }
                Text(text.detail)
                    .font(Sora.font(11, .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .numericTransition()
    }
}

/// Widget rond (spec §7) : jauge du compte à rebours jusqu'au prochain match, et code de l'équipe ; jauge pleine et
/// icône « en direct » quand une équipe suivie joue.
struct CircularWidgetView: View {
    let content: WidgetContent

    var body: some View {
        ZStack {
            switch WidgetText.circular(content) {
            case let .countdown(text, code, progress):
                ring(progress)
                VStack(spacing: 0) {
                    Text(text)
                        .font(Sora.font(14, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(code)
                        .font(Sora.font(9, .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            case let .live(code):
                ring(1)
                VStack(spacing: 2) {
                    IconView(icon: .live, size: 16)
                    Text(code)
                        .font(Sora.font(10, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            case .empty:
                ring(0)
                IconView(icon: .trophy, size: 18)
                    .foregroundStyle(.secondary)
            }
        }
        .numericTransition()
    }

    /// Piste pâle et arc plein jusqu'à `progress` (0 : 24 h ou plus avant le match ; 1 : il commence ou il est en direct).
    private func ring(_ progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(3)
    }
}
