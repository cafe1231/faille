import ActivityKit
import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        LockScreenWidget()
        TeamWidget()
        TeamsWidget()
        // Sonde de l'étape 0 : la Live Activity des matchs la remplace à l'étape 4.
        ProbeLiveActivity()
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
