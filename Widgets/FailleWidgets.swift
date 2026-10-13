import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        ProbeWidget()
        ProbeLiveActivity()
    }
}

struct ProbeEntry: TimelineEntry {
    let date: Date
    let lastWrite: Date?
    let groupOK: Bool
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, lastWrite: nil, groupOK: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> ProbeEntry {
        ProbeEntry(date: .now, lastWrite: ProbeStore.read(), groupOK: ProbeStore.groupAvailable)
    }
}

struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProbeWidget", provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sonde Faille")
        .description("Vérifie le partage entre l'appli et le widget.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Faille · \(entry.groupOK ? "groupe OK" : "groupe KO")")
                .font(.caption2)
            Text(entry.lastWrite.map { $0.formatted(date: .omitted, time: .shortened) } ?? "rien lu")
                .font(.headline)
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
