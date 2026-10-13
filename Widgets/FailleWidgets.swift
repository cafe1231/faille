import SwiftUI
import WidgetKit

@main
struct FailleWidgets: WidgetBundle {
    var body: some Widget {
        LockScreenWidget()
        TeamWidget()
        TeamsWidget()
        // Spec §6 : la Live Activity des matchs (écran verrouillé et Dynamic Island).
        MatchLiveActivity()
    }
}
