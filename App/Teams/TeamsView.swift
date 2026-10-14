import LoLKit
import SwiftUI

/// Onglet Équipes (spec §5.2) : recherche, mes équipes (œil, étoile, couleur), toutes les ligues en pilules, réglages.
/// Finitions : boutons qui s'enfoncent, retours haptiques (suivre, ne plus suivre, œil, couleur), lignes de « Mes
/// équipes » qui arrivent et partent en douceur, squelettes pendant le chargement du catalogue, bandeau qui glisse.
struct TeamsView: View {
    @Environment(AppStore.self) private var store
    @ReduceMotion var reduceMotion
    @State private var query = ""
    @State private var selectedLeagueId: String?
    @State private var showSettings = false
    @State private var colorTeam: FollowedTeam?
    /// Retours haptiques de l'onglet : l'écran reste quand une ligne disparaît ou qu'une feuille se ferme.
    @State private var haptics = HapticTrigger()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Équipes", subtitle: Format.followCount(store.follows.teams.count)) {
                    Button { showSettings = true } label: {
                        IconView(icon: .settings, size: 22)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    .foregroundStyle(Palette.text)
                    .accessibilityLabel("Réglages")
                }
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                        .transition(Motion.bannerTransition(reduceMotion: reduceMotion))
                }
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    myTeams
                    leagueSection
                } else {
                    searchResults
                }
            }
            // Bandeau (spec finitions §11) et lignes de « Mes équipes » (§7) : seules ces deux valeurs animent l'écran.
            .animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: store.isFailing)
            .animation(Motion.animation(.list, reduceMotion: reduceMotion), value: store.follows.teams.map(\.id))
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .haptics(haptics)
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(store)
        }
        .sheet(item: $colorTeam) { team in
            TeamColorSheet(team: team, onPicked: { haptics.play(.colorPicked) }).environment(store)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            IconView(icon: .search, size: 16)
                .foregroundStyle(Palette.secondary)
            TextField("", text: $query, prompt: Text("Rechercher une équipe").foregroundStyle(Palette.secondary))
                .font(Typo.body)
                .foregroundStyle(Palette.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                // Cible de 44 × 44 pt ; le retrait négatif garde le glyphe (16 pt) à sa place, au bord du champ.
                Button { query = "" } label: {
                    IconView(icon: .off, size: 16)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel("Effacer")
                .padding(.trailing, -14)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Palette.glassBorder, lineWidth: 1))
    }

    @ViewBuilder private var myTeams: some View {
        SectionLabel(text: "Mes équipes")
        if store.follows.teams.isEmpty {
            NoteCard(icon: .star, text: "Touche l'étoile d'une équipe pour la suivre.")
        } else {
            VStack(spacing: 4) {
                ForEach(store.follows.teams) { team in
                    FollowedTeamRow(
                        team: team,
                        logoFile: store.logoFile(for: team.image),
                        onToggleSpoiler: { toggleSpoiler(team) },
                        onUnfollow: { unfollow(team) }
                    )
                    .transition(Motion.listTransition(reduceMotion: reduceMotion))
                    .contextMenu {
                        Button("Changer la couleur") { colorTeam = team }
                        Button("Couleur automatique") {
                            haptics.play(.colorPicked)
                            store.setColorOverride(nil, id: team.id)
                        }
                    }
                }
            }
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }

    @ViewBuilder private var leagueSection: some View {
        SectionLabel(text: "Toutes les ligues")
        let pills = store.leaguePills
        if let first = pills.first {
            let selected = pills.first(where: { $0.id == selectedLeagueId }) ?? first
            // Les pilules défilent jusqu'au bord de l'écran : la zone de défilement déborde des marges de 16 pt de la
            // page (retrait négatif), le contenu garde sa marge de départ, et rien n'est rogné au bord de la zone.
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(pills) { league in
                        PillButton(selected: league.id == selected.id, action: { selectedLeagueId = league.id }) {
                            Text(league.name)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            teamList(store.teams(in: selected))
        } else if store.isFailing {
            NoteCard(icon: .refresh, text: "Ligues indisponibles pour l'instant.")
        } else {
            // Chargement (spec finitions §10) : le gabarit des pilules et des lignes, à la place d'un texte d'attente.
            LeagueLoadingSkeleton()
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = store.search(query)
        SectionLabel(text: "Résultats")
        if results.isEmpty {
            if store.catalog.isEmpty && !store.isFailing {
                TeamRowsSkeleton(count: 4)
            } else {
                NoteCard(icon: .search, text: store.catalog.isEmpty ? "Équipes indisponibles pour l'instant." : "Aucune équipe ne correspond.")
            }
        } else {
            teamList(results)
        }
    }

    /// Équipes non suivies du catalogue ou de la recherche (plusieurs centaines) : rangées créées à la demande.
    private func teamList(_ teams: [Team]) -> some View {
        LazyVStack(spacing: 4) {
            ForEach(teams) { team in
                CatalogTeamRow(team: team, followed: store.follows.contains(id: team.id),
                               logoFile: store.logoFile(for: team.image)) {
                    toggleFollow(team)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 12)
    }

    /// Étoile du catalogue (spec finitions §3) : suivre (succès) ou ne plus suivre (impact léger).
    private func toggleFollow(_ team: Team) {
        haptics.play(store.follows.contains(id: team.id) ? .unfollow : .follow)
        store.toggleFollow(team)
    }

    /// Étoile de « Mes équipes » : ne plus suivre (impact léger) ; la ligne part en fondu.
    private func unfollow(_ team: FollowedTeam) {
        haptics.play(.unfollow)
        store.unfollow(id: team.id)
    }

    /// Œil (spec §8) : masquer ou afficher en simple fondu (spec finitions §8), retour « sélection ».
    private func toggleSpoiler(_ team: FollowedTeam) {
        haptics.play(.spoilerToggle)
        withAnimation(Motion.fade) {
            store.setSpoilerFree(!team.spoilerFree, id: team.id)
        }
    }
}

#Preview {
    NavigationStack { TeamsView() }.environment(AppStore(preview: .standard))
}
