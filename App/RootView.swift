import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    PlaceholderScreen(title: "Mes équipes")
                }
            }
            Tab("Équipes", image: Icon.star.assetName, value: AppTab.teams) {
                NavigationStack {
                    TeamsView()
                }
            }
        }
        .tint(Palette.accent)
    }
}

/// Onglet pas encore construit (retiré à la Task 10).
private struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title, subtitle: "bientôt")
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
