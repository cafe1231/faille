import ActivityKit
import LoLKit
import SwiftUI
import WidgetKit

/// La Live Activity d'un match (spec §6) : écran verrouillé et Dynamic Island. L'appli fournit l'état (anti-spoiler
/// déjà appliqué par `LiveMatchBuilder.state`), LoLKit (`LiveActivityDisplay`) dit quoi afficher, les vues de
/// `Shared/LiveActivity/` le posent. `context.isStale` vient d'iOS : vrai passé la `staleDate` (`updatedAt + 180 s`).
struct MatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveMatchAttributes.self) { context in
            LiveActivityLockView(display: Self.display(context))
                .activityBackgroundTint(Palette.abyss)
                .activitySystemActionForegroundColor(Palette.text)
        } dynamicIsland: { context in
            let display = Self.display(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandTeamView(side: display.teams.first)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTeamView(side: display.teams.count > 1 ? display.teams[1] : nil)
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandCenterView(display: display)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandBottomView(display: display)
                }
            } compactLeading: {
                IslandCompactView(display: display, side: 0)
            } compactTrailing: {
                IslandCompactView(display: display, side: 1)
            } minimal: {
                IslandMinimalView(display: display)
            }
            .keylineTint(display.tintHex.map(Palette.team) ?? Palette.accent)
        }
    }

    private nonisolated static func display(_ context: ActivityViewContext<LiveMatchAttributes>) -> LiveActivityDisplay {
        LiveActivityDisplay(attributes: context.attributes, state: context.state, isStale: context.isStale)
    }
}
