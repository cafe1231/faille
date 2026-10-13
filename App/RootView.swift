import LoLKit
import SwiftUI

/// Écran provisoire (remplacé par la planche DA à la Task 6, puis par les onglets à la Task 7) :
/// prouve que LoLKit est lié et montre le groupe d'apps résolu.
struct RootView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Faille")
                .font(.largeTitle.bold())
            Text("LoLKit \(LoLKitInfo.version)")
            Text(AppGroup.identifier ?? "aucun groupe d'apps : stockage local")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
