import SwiftUI

/// Onglets de l'appli (spec §5). Barre flottante en Liquid Glass : style par défaut de `TabView` sous iOS 26.
enum AppTab: Hashable {
    case matches, teams
}

struct RootView: View {
    @State private var tab: AppTab
    @ReduceMotion var reduceMotion
    /// Zoom carte → Détail (spec finitions §6) : les lignes des cartes en sont les sources, l'écran Détail la destination.
    @Namespace private var zoom

    init(tab: AppTab = .matches) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Matchs", image: Icon.trophy.assetName, value: AppTab.matches) {
                NavigationStack {
                    MatchesView(openTeams: { tab = .teams }, zoom: zoom)
                        .navigationDestination(for: MatchRoute.self) { route in
                            // Sans ligne source, ou sous « Réduire les animations » : transition standard d'iOS.
                            MatchDetailView(matchId: route.matchId)
                                .zoomTransition(route.sourceID, in: zoom,
                                                enabled: Motion.runs(.zoom, reduceMotion: reduceMotion))
                        }
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

#Preview {
    RootView().environment(AppStore(preview: .standard))
}
