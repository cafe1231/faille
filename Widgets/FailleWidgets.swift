import ActivityKit
import LoLKit
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        ProbeWidget()
        ProbeLiveActivity()
    }
}

/// Sonde jusqu'à l'étape 3 : prouve que l'extension trouve le même groupe d'apps que l'appli
/// et y lit les équipes suivies (follows.json).
struct ProbeEntry: TimelineEntry {
    let date: Date
    let group: String?
    let codes: [String]
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, group: AppGroup.configured, codes: ["KC", "T1"])
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> ProbeEntry {
        // Lecture seule : l'extension ne met jamais de fichier de côté et n'écrit rien.
        let follows = FileStore(directory: AppGroup.directory, readOnly: true).load(FollowList.self, from: .follows)
        return ProbeEntry(date: .now, group: AppGroup.identifier, codes: follows?.teams.map(\.code) ?? [])
    }
}

struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProbeWidget", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sonde Faille")
        .description("Vérifie que le widget lit les équipes suivies dans l'appli.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Faille · \(entry.group == nil ? "groupe KO" : "groupe OK")")
                .font(.caption2)
            Text(entry.group ?? "stockage local")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(entry.codes.isEmpty ? "aucune équipe" : entry.codes.joined(separator: " · "))
                .font(.headline)
                .lineLimit(2)
        }
    }
}

struct ProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            HStack {
                Text("Sonde Faille").bold()
                Spacer()
                Text("tick \(context.state.tick)")
                Text(context.state.updatedAt, style: .time)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("tick \(context.state.tick)")
                }
            } compactLeading: {
                Text("F")
            } compactTrailing: {
                Text("\(context.state.tick)")
            } minimal: {
                Text("\(context.state.tick)")
            }
        }
    }
}
