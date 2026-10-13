import LoLKit
import SwiftUI
import WidgetKit

/// Widgets de l'écran verrouillé (spec §7) : en ligne, rectangulaire, rond. iOS les rend en monochrome : Sora et les
/// icônes, sans couleur d'équipe.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FailleLockScreen", provider: FailleProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("Prochain match")
        .description("Le match en direct ou le prochain match de tes équipes.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

/// Une famille, une vue ; le fond est celui de iOS (translucide pour le rectangulaire et le rond).
struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FailleEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineWidgetView(content: entry.content)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            CircularWidgetView(content: entry.content)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            RectangularWidgetView(content: entry.content)
                .padding(.horizontal, 2)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }
}
