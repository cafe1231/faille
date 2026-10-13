import LoLKit
import SwiftUI

/// Onglet Équipes (spec §5.2) : recherche, mes équipes (œil, étoile, couleur), toutes les ligues en pilules, réglages.
struct TeamsView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var selectedLeagueId: String?
    @State private var showSettings = false
    @State private var colorTeam: FollowedTeam?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Équipes", subtitle: Format.followCount(store.follows.teams.count)) {
                    Button { showSettings = true } label: {
                        IconView(icon: .settings, size: 22)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.text)
                    .accessibilityLabel("Réglages")
                }
                if let banner = store.bannerText {
                    ErrorBanner(text: banner)
                }
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    myTeams
                    leagueSection
                } else {
                    searchResults
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .abyssBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(store)
        }
        .sheet(item: $colorTeam) { team in
            TeamColorSheet(team: team).environment(store)
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
                .buttonStyle(.plain)
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
                        onToggleSpoiler: { store.setSpoilerFree(!team.spoilerFree, id: team.id) },
                        onUnfollow: { store.unfollow(id: team.id) }
                    )
                    .contextMenu {
                        Button("Changer la couleur") { colorTeam = team }
                        Button("Couleur automatique") { store.setColorOverride(nil, id: team.id) }
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
        } else {
            NoteCard(icon: .refresh, text: store.isFailing ? "Ligues indisponibles pour l'instant." : "Chargement des ligues…")
        }
    }

    @ViewBuilder private var searchResults: some View {
        let results = store.search(query)
        SectionLabel(text: "Résultats")
        if results.isEmpty {
            NoteCard(icon: .search, text: store.catalog.isEmpty ? "Chargement des équipes…" : "Aucune équipe ne correspond.")
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
                    store.toggleFollow(team)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 12)
    }
}

#Preview {
    NavigationStack { TeamsView() }.environment(AppStore(preview: .standard))
}
